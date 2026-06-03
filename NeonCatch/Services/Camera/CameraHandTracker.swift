import AVFoundation
import Vision
import SwiftUI
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
private enum MacOrientation { case landscapeLeft }
#endif

// MARK: - Calibration Step

enum CalibrationStep: Int, Equatable {
    case presence = 1
    case range    = 2
    case point    = 3
}

// MARK: - CameraHandTracker

class CameraHandTracker: NSObject, ObservableObject,
                         AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: Published

    @Published var handsP1:          [HandState]     = []
    @Published var handsP2:          [HandState]     = []
    @Published var p1CalibProgress:  Double          = 0
    @Published var p2CalibProgress:  Double          = 0
    @Published var calibStep:        CalibrationStep = .presence
    @Published var p1TargetIndex:    Int             = 0
    @Published var p2TargetIndex:    Int             = 0
    @Published var p1TargetPoints:   [CGPoint]       = []
    @Published var p2TargetPoints:   [CGPoint]       = []
    @Published var calibrationReady: Bool            = false

    // MARK: - Silhouette

    /// Pre-processed cyberpunk silhouette mask — updated ~30 fps on the main thread.
    /// Left half = cyan (P1), right half = magenta (P2).
    /// nil until the first camera frame arrives.
    @Published var silhouetteMask: CGImage?

    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    /// Separate queue so CI rendering never blocks hand-pose tracking.
    private let silhouetteQueue = DispatchQueue(label: "silhouette.ci", qos: .userInitiated)

    // MARK: AVFoundation

    private let session     = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue       = DispatchQueue(label: "hand.tracking", qos: .userInteractive)
    private var handRequest = VNDetectHumanHandPoseRequest()
    private var orientationObserver: Any?
    #if os(iOS)
    private var cachedOrientation: UIDeviceOrientation = .landscapeLeft
    #endif
    private var isRunning = false
    var previewLayer: AVCaptureVideoPreviewLayer?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Photo Booth: Latest Frame
    // Stores the most-recent pixel buffer so PhotoBoothManager can grab
    // a still at any time. Protected by bufferLock for thread safety.

    private var latestPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    // MARK: Track  (capture queue only)

    private struct Track {
        var pos:          CGPoint
        var isP1:         Bool
        var age:          Int     = 0
        var misses:       Int     = 0
        var palmLen:      CGFloat = 0.10
        var rawPinchNorm: CGFloat = 1.0
        var pinching:     Bool    = false
        var pinchCount:   Int     = 0
        var noTipFrames:  Int     = 0
    }

    private var tracks:         [Track] = []
    private let matchRadius:    CGFloat = 0.28
    private let maxMisses:      Int     = 20
    private let pinchConfirm:   Int     = 2
    private let maxNoTipFrames: Int     = 10
    private let pinchEnter:     CGFloat = 0.28
    private let pinchExit:      CGFloat = 0.42

    // MARK: Linear remap  (screen = A * raw + B, per player per axis)

    private var p1Ax: CGFloat = 1.56; private var p1Bx: CGFloat = -0.14
    private var p1Ay: CGFloat = 1.39; private var p1By: CGFloat = -0.25
    private var p2Ax: CGFloat = 1.56; private var p2Bx: CGFloat =  0.36
    private var p2Ay: CGFloat = 1.39; private var p2By: CGFloat = -0.25

    // MARK: Snapshot  (main-queue only)

    private struct Snapshot {
        var pos:      CGPoint
        var pinching: Bool
        var isP1:     Bool
        var stamp:    Date
    }

    private var snapshots:   [Snapshot]  = []
    private var calibrating: Bool        = false
    private var displayTimer: AnyCancellable?

    // When true, both players get full-screen x mapping instead of half-screen.
    // Set by ContentView when entering / leaving co-op gameplay.
    var coopMode: Bool = false

    // Tracks whether calibration has been completed at least once this session.
    // Raw positions are used until then so both players' cursors work pre-calibration.
    private(set) var hasCalibrated: Bool = false

    // MARK: Calibration state  (capture queue)

    private var p1Anchor = CGPoint(x: 0.25, y: 0.5)
    private var p2Anchor = CGPoint(x: 0.75, y: 0.5)
    private var p1HRange: CGFloat = 0.16
    private var p1VRange: CGFloat = 0.18
    private var p2HRange: CGFloat = 0.16
    private var p2VRange: CGFloat = 0.18
    private let anchorEMA: CGFloat = 0.08

    private var calibMode:         Bool            = false
    private var calibStepInternal: CalibrationStep = .presence

    private let presenceTarget = 60
    private let presenceDecay  = 3
    private var presenceP1 = 0
    private var presenceP2 = 0

    private let rangeFrameTarget = 100
    private let rangeMinXSpread: CGFloat = 0.08
    private var rangeP1Frames = 0
    private var rangeP2Frames = 0
    private var rP1xMin: CGFloat = 1, rP1xMax: CGFloat = 0
    private var rP1yMin: CGFloat = 1, rP1yMax: CGFloat = 0
    private var rP2xMin: CGFloat = 1, rP2xMax: CGFloat = 0
    private var rP2yMin: CGFloat = 1, rP2yMax: CGFloat = 0

    private let pointCaptureRadius: CGFloat = 0.13
    private let pointDwellRequired: Int     = 3
    private var p1TargetsCQ: [CGPoint] = []
    private var p2TargetsCQ: [CGPoint] = []
    private var p1Captures:  [(raw: CGPoint, target: CGPoint)] = []
    private var p2Captures:  [(raw: CGPoint, target: CGPoint)] = []
    private var p1CurPt = 0, p2CurPt = 0
    private var p1Dwell = 0, p2Dwell = 0

    // MARK: Init

    override init() {
        super.init()
        handRequest.maximumHandCount = 4
        // .fast gives ~5 ms on A-series; edges are soft enough for our glow treatment
        segmentationRequest.qualityLevel      = .fast
        setupCamera()
    }

    // MARK: Public API

    func beginCalibration() {
        let t1 = Self.randomTargets(xMin: 0.08, xMax: 0.42)
        let t2 = Self.randomTargets(xMin: 0.58, xMax: 0.92)
        p1TargetPoints   = t1
        p2TargetPoints   = t2
        calibrating      = true
        calibrationReady = false
        p1CalibProgress  = 0
        p2CalibProgress  = 0
        calibStep        = .presence
        p1TargetIndex    = 0
        p2TargetIndex    = 0
        handsP1          = []
        handsP2          = []
        snapshots        = []
        queue.async { self.resetCalibState(t1: t1, t2: t2) }
    }

    func finishCalibration() {
        calibrating    = false
        hasCalibrated  = true
        queue.async { self.calibMode = false }
    }

    private func resetCalibState(t1: [CGPoint], t2: [CGPoint]) {
        calibMode         = true
        calibStepInternal = .presence
        tracks            = []
        p1Anchor = CGPoint(x: 0.25, y: 0.5)
        p2Anchor = CGPoint(x: 0.75, y: 0.5)
        p1HRange = 0.16; p1VRange = 0.18
        p2HRange = 0.16; p2VRange = 0.18
        initRemapCoeffs()
        presenceP1 = 0; presenceP2 = 0
        rangeP1Frames = 0; rangeP2Frames = 0
        rP1xMin = 1; rP1xMax = 0; rP1yMin = 1; rP1yMax = 0
        rP2xMin = 1; rP2xMax = 0; rP2yMin = 1; rP2yMax = 0
        p1TargetsCQ = t1; p2TargetsCQ = t2
        p1Captures = []; p2Captures = []
        p1CurPt = 0; p2CurPt = 0
        p1Dwell = 0; p2Dwell = 0
    }

    private func initRemapCoeffs() {
        p1Ax = 0.499 / (2 * p1HRange)
        p1Bx = -p1Ax * (p1Anchor.x - p1HRange)
        p1Ay = 1.0   / (2 * p1VRange)
        p1By = -p1Ay * (p1Anchor.y - p1VRange)
        p2Ax = 0.499 / (2 * p2HRange)
        p2Bx = 0.500 - p2Ax * (p2Anchor.x - p2HRange)
        p2Ay = 1.0   / (2 * p2VRange)
        p2By = -p2Ay * (p2Anchor.y - p2VRange)
    }

    // 4 random, well-separated target points within the given x band.
    private static func randomTargets(xMin: CGFloat, xMax: CGFloat) -> [CGPoint] {
        let minSep: CGFloat = 0.22
        var pts: [CGPoint] = []
        var attempts = 0
        while pts.count < 4 && attempts < 400 {
            let c = CGPoint(x: CGFloat.random(in: xMin...xMax),
                            y: CGFloat.random(in: 0.14...0.86))
            // Inline distance — cannot call instance method from static context.
            let ok = pts.allSatisfy { p in
                let dx = p.x - c.x, dy = p.y - c.y
                return sqrt(dx*dx + dy*dy) >= minSep
            }
            if ok { pts.append(c) }
            attempts += 1
        }
        if pts.count < 4 {
            pts = [CGPoint(x: xMin + 0.03, y: 0.18),
                   CGPoint(x: xMax - 0.03, y: 0.18),
                   CGPoint(x: xMax - 0.03, y: 0.82),
                   CGPoint(x: xMin + 0.03, y: 0.82)]
        }
        return pts
    }

    // MARK: Camera setup

    private func setupCamera() {
        session.sessionPreset = .hd1280x720
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input  = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        session.addOutput(videoOutput)
        if let conn = videoOutput.connection(with: .video) { conn.isVideoMirrored = false }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
        applyPreviewOrientation()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        #if os(iOS)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleOrientationChange() }
        #endif
        queue.async {
            self.session.startRunning()
            DispatchQueue.main.async { self.handleOrientationChange() }
        }
        startDisplayTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        displayTimer?.cancel(); displayTimer = nil
        queue.async { self.session.stopRunning() }
        if let obs = orientationObserver {
            NotificationCenter.default.removeObserver(obs)
            orientationObserver = nil
        }
        #if os(iOS)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        #endif
    }

    // MARK: Display timer

    private func startDisplayTimer() {
        displayTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.publishDisplayState() }
    }

    private func publishDisplayState() {
        let now = Date()
        snapshots.removeAll { now.timeIntervalSince($0.stamp) > 0.40 }

        var p1: [HandState] = [], p2: [HandState] = []
        let applyRemap = hasCalibrated || (calibrating && calibStep == .point)

        for snap in snapshots {
            let elapsed = now.timeIntervalSince(snap.stamp)
            guard elapsed < 0.25 else { continue }

            let mapped: CGPoint
            if applyRemap {
                if coopMode {
                    mapped = snap.isP1 ? coopRemapP1(snap.pos) : coopRemapP2(snap.pos)
                } else {
                    mapped = snap.isP1 ? remapP1(snap.pos) : remapP2(snap.pos)
                }
            } else {
                mapped = snap.pos
            }
            let pinch = snap.pinching && elapsed < 0.20

            let hs = HandState(position: mapped, isPinching: pinch, isActive: true)
            if snap.isP1 { p1.append(hs) } else { p2.append(hs) }
        }
        if handsP1 != p1 { handsP1 = p1 }
        if handsP2 != p2 { handsP2 = p2 }
    }

    // MARK: Orientation

    private func handleOrientationChange() {
        #if os(iOS)
        let o = UIDevice.current.orientation
        if o.isLandscape { cachedOrientation = o }
        #endif
        applyPreviewOrientation()
    }

    private func applyPreviewOrientation() {
        guard let conn = previewLayer?.connection else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = true
        #if os(iOS)
        conn.videoRotationAngle = (cachedOrientation == .landscapeRight) ? 180 : 0
        #else
        conn.videoRotationAngle = 0
        #endif
    }

    private func visionOrientation() -> CGImagePropertyOrientation {
        #if os(macOS)
        return .up
        #else
        return cachedOrientation == .landscapeRight ? .right : .left
        #endif
    }

    // MARK: Capture delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Store the latest frame for photo-booth snapshots.
        bufferLock.lock()
        latestPixelBuffer = px
        bufferLock.unlock()

        let handler = VNImageRequestHandler(cvPixelBuffer: px,
                                            orientation: visionOrientation(), options: [:])
        // Run hand-pose and person-segmentation in a single handler call (most efficient).
        try? handler.perform([handRequest, segmentationRequest])
        let obs = handRequest.results ?? []
        if calibMode { runCalibration(obs) } else { runGame(obs) }

        // Kick off silhouette CI rendering on a secondary queue so it never stalls hand tracking.
        if let maskBuf = segmentationRequest.results?.first?.pixelBuffer {
            let fW = CGFloat(CVPixelBufferGetWidth(px))
            let fH = CGFloat(CVPixelBufferGetHeight(px))
            processSilhouette(maskBuffer: maskBuf, frameSize: CGSize(width: fW, height: fH))
        }
    }

    // MARK: - Silhouette CI Pipeline
    //
    // Runs on silhouetteQueue (never blocks hand-tracking).
    // Pipeline:
    //   1. Scale Vision mask (low-res) to the camera frame size.
    //   2. Blend a cyan→magenta gradient with the mask → colour only where a person is.
    //   3. Blur the coloured mask outward  →  neon edge glow.
    //   4. Dark interior: gradient at ~18 % brightness, 55 % alpha  →  Tron body fill.
    //   5. Composite interior over glow  →  glow visible outside body, dark fill inside.
    //   6. Mirror horizontally to match preview (isVideoMirrored = true).
    //   7. Render to CGImage and publish on main thread.

    private func processSilhouette(maskBuffer: CVPixelBuffer, frameSize: CGSize) {
        silhouetteQueue.async { [weak self] in
            guard let self else { return }

            let frameRect = CGRect(origin: .zero, size: frameSize)
            let ciMask    = CIImage(cvPixelBuffer: maskBuffer)

            // 1. Scale to camera frame
            let sx = frameSize.width  / ciMask.extent.width
            let sy = frameSize.height / ciMask.extent.height
            let scaled = ciMask
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .cropped(to: frameRect)

            // 2. Gradient: cyan (P1 left zone) → magenta (P2 right zone)
            let midY = frameSize.height / 2
            guard
                let gradientImage = CIFilter(name: "CILinearGradient", parameters: [
                    "inputPoint0": CIVector(x: 0,               y: midY),
                    "inputPoint1": CIVector(x: frameSize.width, y: midY),
                    "inputColor0": CIColor(red: 0, green: 1, blue: 1, alpha: 1), // cyan
                    "inputColor1": CIColor(red: 1, green: 0, blue: 1, alpha: 1), // magenta
                ])?.outputImage?.cropped(to: frameRect),

                // Mask the gradient: visible only where a person is detected
                let brightMasked = CIFilter(name: "CIBlendWithMask", parameters: [
                    "inputImage":           gradientImage,
                    "inputBackgroundImage": CIImage(color: CIColor(red: 0, green: 0,
                                                                   blue: 0, alpha: 0))
                                                .cropped(to: frameRect),
                    "inputMaskImage":       scaled,
                ])?.outputImage?.cropped(to: frameRect)
            else { return }

            // 3. Edge glow: Gaussian bloom on the coloured person shape.
            //    Blur on a ~256×192 mask texture (Vision .fast output) is very cheap on GPU.
            let glow = brightMasked
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 14])
                .cropped(to: frameRect)

            // 4. Dark interior: ~18 % brightness, 55 % alpha  →  Tron silhouette body.
            //    CIColorMatrix row semantics: inputRVector = (rr,rg,rb,ra)
            //    → output.R = rr*in.R + rg*in.G + rb*in.B + ra*in.A
            let darkInterior = brightMasked
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector":    CIVector(x: 0.18, y: 0,    z: 0,    w: 0),
                    "inputGVector":    CIVector(x: 0,    y: 0.18, z: 0,    w: 0),
                    "inputBVector":    CIVector(x: 0,    y: 0,    z: 0.22, w: 0),
                    "inputAVector":    CIVector(x: 0,    y: 0,    z: 0,    w: 0.55),
                    "inputBiasVector": CIVector(x: 0,    y: 0,    z: 0,    w: 0),
                ])
                .cropped(to: frameRect)

            // 5. Composite: dark interior sits on top of the glow.
            //    Inside the body: dark fill covers the glow → Tron look.
            //    Outside the body: glow bleeds out → neon edge halo.
            var composite = darkInterior.composited(over: glow)

            // 6. Mirror to match AVCaptureVideoPreviewLayer (isVideoMirrored = true)
            let w = composite.extent.width
            composite = composite
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                    .concatenating(CGAffineTransform(translationX: w, y: 0)))
                .cropped(to: frameRect)

            // 7. Render and publish
            guard let cgImage = self.ciContext.createCGImage(composite, from: frameRect) else { return }
            DispatchQueue.main.async { [weak self] in self?.silhouetteMask = cgImage }
        }
    }

    // MARK: - Photo Booth Frame Capture (iOS only)
    // Returns a UIImage of the current camera frame, mirrored horizontally
    // to match the preview layer (isVideoMirrored = true).

    // Returns a CGImage (cross-platform) of the current camera frame,
    // mirrored horizontally to match the preview layer (isVideoMirrored = true).
    // CGImage, CIImage, and CIContext all work on both iOS and macOS.
    func captureCurrentFrame() -> CGImage? {
        var pb: CVPixelBuffer?
        bufferLock.lock()
        pb = latestPixelBuffer
        bufferLock.unlock()

        guard let pixelBuffer = pb else { return nil }

        // The hd1280x720 front-camera buffer is already delivered in landscape
        // (1280 × 720). Only a horizontal mirror is needed to match the preview.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let w = ciImage.extent.width
        let mirrored = ciImage.transformed(
            by: CGAffineTransform(scaleX: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: w, y: 0))
        )

        return ciContext.createCGImage(mirrored, from: mirrored.extent)
    }

    // MARK: Hand detection

    private func handScreenPos(_ obs: VNHumanHandPoseObservation) -> HandState? {
        guard let w = try? obs.recognizedPoint(.wrist), w.confidence > 0.25 else { return nil }

        var sumX = CGFloat(w.x), sumY = CGFloat(w.y), totalW = CGFloat(1.0)
        var palmLen: CGFloat = 0.10

        let mcpJoints: [(VNHumanHandPoseObservation.JointName, CGFloat)] = [
            (.indexMCP, 0.9), (.middleMCP, 1.0), (.ringMCP, 0.8), (.littleMCP, 0.6),
        ]
        for (joint, w8) in mcpJoints {
            guard let pt = try? obs.recognizedPoint(joint), pt.confidence > 0.20 else { continue }
            sumX += CGFloat(pt.x) * w8
            sumY += CGFloat(pt.y) * w8
            totalW += w8
            if joint == .middleMCP {
                let dx = CGFloat(pt.x) - CGFloat(w.x)
                let dy = CGFloat(pt.y) - CGFloat(w.y)
                let len = sqrt(dx * dx + dy * dy)
                if len > 0.01 { palmLen = len }
            }
        }

        let rx = sumX / totalW, ry = sumY / totalW
        var hs = HandState()
        hs.isActive  = true
        hs.palmLen   = palmLen
        hs.pinchDist = computePinchDist(obs) ?? 0.0
        #if os(macOS)
        hs.position = CGPoint(x: 1 - rx, y: 1 - ry)
        #else
        hs.position = CGPoint(x: ry, y: 1 - rx)
        #endif
        return hs
    }

    private func computePinchDist(_ obs: VNHumanHandPoseObservation) -> CGFloat? {
        let tThumb = try? obs.recognizedPoint(.thumbTip)
        let tIndex = try? obs.recognizedPoint(.indexTip)
        if let t = tThumb, let i = tIndex, t.confidence > 0.15, i.confidence > 0.15 {
            let dx = CGFloat(t.x - i.x), dy = CGFloat(t.y - i.y)
            return sqrt(dx * dx + dy * dy)
        }
        let tMiddle = try? obs.recognizedPoint(.middleTip)
        if let t = tThumb, let m = tMiddle, t.confidence > 0.18, m.confidence > 0.18 {
            let dx = CGFloat(t.x - m.x), dy = CGFloat(t.y - m.y)
            return sqrt(dx * dx + dy * dy) * 0.85
        }
        return nil
    }

    // MARK: Track update

    private func updateTracks(detections: [HandState]) {
        var used = [Bool](repeating: false, count: detections.count)

        for i in tracks.indices {
            // Only match detections on the same side of the frame.
            // Without this, a track near centre can steal a detection from the other
            // player, teleporting the cursor across the divider and causing visible wobble.
            var bestDist: CGFloat = matchRadius
            var bestJ = -1
            for j in detections.indices where !used[j] {
                guard (detections[j].position.x < 0.5) == tracks[i].isP1 else { continue }
                let dd = dist(tracks[i].pos, detections[j].position)
                if dd < bestDist { bestDist = dd; bestJ = j }
            }

            if bestJ >= 0 {
                let raw  = detections[bestJ].position
                let prev = tracks[i].pos
                let α: CGFloat = tracks[i].age < 8 ? 0.85 : 0.60
                tracks[i].pos    = CGPoint(x: α * raw.x + (1 - α) * prev.x,
                                           y: α * raw.y + (1 - α) * prev.y)
                tracks[i].age   += 1
                tracks[i].misses = 0
                used[bestJ]      = true

                tracks[i].palmLen = 0.20 * detections[bestJ].palmLen + 0.80 * tracks[i].palmLen

                let pd = detections[bestJ].pinchDist
                if pd > 0.001 {
                    let dNorm = pd / max(tracks[i].palmLen, 0.01)
                    tracks[i].rawPinchNorm = 0.70 * dNorm + 0.30 * tracks[i].rawPinchNorm
                    tracks[i].noTipFrames  = 0
                    if tracks[i].pinching {
                        if tracks[i].rawPinchNorm >= pinchExit {
                            tracks[i].pinching   = false
                            tracks[i].pinchCount = 0
                        }
                    } else {
                        tracks[i].pinchCount = tracks[i].rawPinchNorm < pinchEnter
                            ? min(tracks[i].pinchCount + 1, pinchConfirm)
                            : max(tracks[i].pinchCount - 1, 0)
                        tracks[i].pinching = tracks[i].pinchCount >= pinchConfirm
                    }
                } else {
                    // No tip reading: hold pinch state (fingertips occlude during real pinch).
                    tracks[i].noTipFrames += 1
                    if tracks[i].pinching && tracks[i].noTipFrames > maxNoTipFrames {
                        tracks[i].pinching   = false
                        tracks[i].pinchCount = 0
                    }
                }

            } else {
                tracks[i].misses      += 1
                tracks[i].noTipFrames += 1
                if tracks[i].pinching && tracks[i].noTipFrames > maxNoTipFrames {
                    tracks[i].pinching   = false
                    tracks[i].pinchCount = 0
                }
            }
        }

        tracks.removeAll { $0.misses > maxMisses }

        for (j, det) in detections.enumerated() where !used[j] {
            let isP1 = det.position.x < 0.5
            guard tracks.filter({ $0.isP1 == isP1 }).count < 1 else { continue }
            var t = Track(pos: det.position, isP1: isP1)
            t.palmLen = det.palmLen
            tracks.append(t)
        }
    }

    // MARK: Game

    private func runGame(_ obs: [VNHumanHandPoseObservation]) {
        updateTracks(detections: obs.compactMap { handScreenPos($0) })
        pushSnapshot()
    }

    // MARK: Calibration

    private func runCalibration(_ obs: [VNHumanHandPoseObservation]) {
        updateTracks(detections: obs.compactMap { handScreenPos($0) })
        switch calibStepInternal {
        case .presence: stepPresence()
        case .range:    stepRange()
        case .point:    stepPoint()
        }
        pushSnapshot()
    }

    // MARK: Step 1 — Presence

    private func stepPresence() {
        for t in tracks where t.misses == 0 && t.age >= 5 {
            if t.isP1 {
                p1Anchor.x = anchorEMA * t.pos.x + (1 - anchorEMA) * p1Anchor.x
                p1Anchor.y = anchorEMA * t.pos.y + (1 - anchorEMA) * p1Anchor.y
            } else {
                p2Anchor.x = anchorEMA * t.pos.x + (1 - anchorEMA) * p2Anchor.x
                p2Anchor.y = anchorEMA * t.pos.y + (1 - anchorEMA) * p2Anchor.y
            }
        }
        let hasP1 = tracks.contains { $0.isP1  && $0.misses == 0 && $0.age >= 5 }
        let hasP2 = tracks.contains { !$0.isP1 && $0.misses == 0 && $0.age >= 5 }
        presenceP1 = hasP1 ? min(presenceP1 + 1, presenceTarget) : max(presenceP1 - presenceDecay, 0)
        presenceP2 = hasP2 ? min(presenceP2 + 1, presenceTarget) : max(presenceP2 - presenceDecay, 0)
        let prog1 = Double(presenceP1) / Double(presenceTarget)
        let prog2 = Double(presenceP2) / Double(presenceTarget)
        pubCalib(prog1, prog2, .presence)
        guard prog1 >= 1.0, prog2 >= 1.0 else { return }
        rP1xMin = p1Anchor.x; rP1xMax = p1Anchor.x
        rP1yMin = p1Anchor.y; rP1yMax = p1Anchor.y
        rP2xMin = p2Anchor.x; rP2xMax = p2Anchor.x
        rP2yMin = p2Anchor.y; rP2yMax = p2Anchor.y
        calibStepInternal = .range
    }

    // MARK: Step 2 — Range

    private func stepRange() {
        for t in tracks where t.misses == 0 && t.age >= 3 {
            if t.isP1 {
                rP1xMin = min(rP1xMin, t.pos.x); rP1xMax = max(rP1xMax, t.pos.x)
                rP1yMin = min(rP1yMin, t.pos.y); rP1yMax = max(rP1yMax, t.pos.y)
                rangeP1Frames += 1
            } else {
                rP2xMin = min(rP2xMin, t.pos.x); rP2xMax = max(rP2xMax, t.pos.x)
                rP2yMin = min(rP2yMin, t.pos.y); rP2yMax = max(rP2yMax, t.pos.y)
                rangeP2Frames += 1
            }
        }
        let xs1 = rP1xMax - rP1xMin, xs2 = rP2xMax - rP2xMin
        let fp1 = min(1.0, Double(rangeP1Frames) / Double(rangeFrameTarget))
        let fp2 = min(1.0, Double(rangeP2Frames) / Double(rangeFrameTarget))
        let cp1 = min(1.0, Double(xs1 / rangeMinXSpread))
        let cp2 = min(1.0, Double(xs2 / rangeMinXSpread))
        pubCalib(fp1 * cp1, fp2 * cp2, .range)
        guard rangeP1Frames >= rangeFrameTarget, xs1 >= rangeMinXSpread,
              rangeP2Frames >= rangeFrameTarget, xs2 >= rangeMinXSpread else { return }
        let margin: CGFloat = 0.025
        p1HRange   = max((xs1 / 2) + margin, 0.12)
        p1VRange   = max(((rP1yMax - rP1yMin) / 2) + margin, 0.14)
        p1Anchor   = CGPoint(x: (rP1xMin + rP1xMax) / 2, y: (rP1yMin + rP1yMax) / 2)
        p2HRange   = max((xs2 / 2) + margin, 0.12)
        p2VRange   = max(((rP2yMax - rP2yMin) / 2) + margin, 0.14)
        p2Anchor   = CGPoint(x: (rP2xMin + rP2xMax) / 2, y: (rP2yMin + rP2yMax) / 2)
        initRemapCoeffs()
        calibStepInternal = .point
    }

    // MARK: Step 3 — Point calibration

    private func stepPoint() {
        capturePointTarget(isP1: true,  targets: p1TargetsCQ,
                           curPt: &p1CurPt, captures: &p1Captures, dwell: &p1Dwell) { [weak self] idx in
            DispatchQueue.main.async { self?.p1TargetIndex = idx }
        }
        capturePointTarget(isP1: false, targets: p2TargetsCQ,
                           curPt: &p2CurPt, captures: &p2Captures, dwell: &p2Dwell) { [weak self] idx in
            DispatchQueue.main.async { self?.p2TargetIndex = idx }
        }

        let n1 = p1TargetsCQ.count, n2 = p2TargetsCQ.count
        guard n1 > 0, n2 > 0 else { return }
        let dw1 = Double(p1Dwell) / Double(pointDwellRequired)
        let dw2 = Double(p2Dwell) / Double(pointDwellRequired)
        let prog1 = min(1.0, (Double(p1CurPt) + dw1) / Double(n1))
        let prog2 = min(1.0, (Double(p2CurPt) + dw2) / Double(n2))
        pubCalib(prog1, prog2, .point)

        guard p1Captures.count >= n1, p2Captures.count >= n2 else { return }

        applyRegression()

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.calibrationReady else { return }
            self.calibrationReady = true
        }
    }

    private func capturePointTarget(isP1: Bool,
                                    targets: [CGPoint],
                                    curPt: inout Int,
                                    captures: inout [(raw: CGPoint, target: CGPoint)],
                                    dwell: inout Int,
                                    onCapture: (Int) -> Void) {
        guard curPt < targets.count else { return }
        let target = targets[curPt]
        let track  = tracks.first { $0.isP1 == isP1 && $0.misses == 0 && $0.age >= 5 }

        if let t = track {
            let mapped = isP1 ? remapP1(t.pos) : remapP2(t.pos)
            if dist(mapped, target) < pointCaptureRadius && t.pinching {
                dwell += 1
            } else {
                dwell = 0
            }
        } else {
            dwell = 0
        }

        if dwell >= pointDwellRequired, let t = track {
            captures.append((raw: t.pos, target: target))
            curPt += 1
            dwell  = 0
            onCapture(curPt)
        }
    }

    private func applyRegression() {
        func tryApply(rawX: [CGFloat], tgtX: [CGFloat], rawY: [CGFloat], tgtY: [CGFloat],
                      setAx: (CGFloat) -> Void, setBx: (CGFloat) -> Void,
                      setAy: (CGFloat) -> Void, setBy: (CGFloat) -> Void) {
            let (ax, bx) = linearFit(rawX, tgtX)
            let (ay, by) = linearFit(rawY, tgtY)
            if ax >= 0.3 && ax <= 4.0 { setAx(ax); setBx(bx) }
            if ay >= 0.3 && ay <= 4.0 { setAy(ay); setBy(by) }
        }
        tryApply(
            rawX: p1Captures.map { $0.raw.x }, tgtX: p1Captures.map { $0.target.x },
            rawY: p1Captures.map { $0.raw.y }, tgtY: p1Captures.map { $0.target.y },
            setAx: { self.p1Ax = $0 }, setBx: { self.p1Bx = $0 },
            setAy: { self.p1Ay = $0 }, setBy: { self.p1By = $0 }
        )
        tryApply(
            rawX: p2Captures.map { $0.raw.x }, tgtX: p2Captures.map { $0.target.x },
            rawY: p2Captures.map { $0.raw.y }, tgtY: p2Captures.map { $0.target.y },
            setAx: { self.p2Ax = $0 }, setBx: { self.p2Bx = $0 },
            setAy: { self.p2Ay = $0 }, setBy: { self.p2By = $0 }
        )
    }

    // MARK: Helpers

    private func linearFit(_ xs: [CGFloat], _ ys: [CGFloat]) -> (CGFloat, CGFloat) {
        guard xs.count >= 2 else { return (1, 0) }
        let n  = CGFloat(xs.count)
        let xm = xs.reduce(0, +) / n
        let ym = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(CGFloat(0)) { $0 + ($1.0 - xm) * ($1.1 - ym) }
        let den = xs.reduce(CGFloat(0))           { $0 + ($1 - xm) * ($1 - xm) }
        guard den > 1e-6 else { return (1, ym - xm) }
        let a = num / den
        return (a, ym - a * xm)
    }

    private func pubCalib(_ p1: Double, _ p2: Double, _ step: CalibrationStep) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.p1CalibProgress = p1
            self.p2CalibProgress = p2
            if self.calibStep != step { self.calibStep = step }
        }
    }

    private func pushSnapshot() {
        let snap = tracks.map {
            Snapshot(pos: $0.pos, pinching: $0.pinching, isP1: $0.isP1, stamp: Date())
        }
        DispatchQueue.main.async { [weak self] in self?.snapshots = snap }
    }

    private func remapP1(_ r: CGPoint) -> CGPoint {
        CGPoint(x: min(0.499, max(0.0,   p1Ax * r.x + p1Bx)),
                y: min(1.0,   max(0.0,   p1Ay * r.y + p1By)))
    }

    private func remapP2(_ r: CGPoint) -> CGPoint {
        CGPoint(x: min(0.999, max(0.500, p2Ax * r.x + p2Bx)),
                y: min(1.0,   max(0.0,   p2Ay * r.y + p2By)))
    }

    // Co-op variants: stretch each player's calibrated half-range to the full screen.
    // P1 versus output is [0, 0.499] → multiply by 2 → [0, ~1.0].
    // P2 versus output is [0.5, 0.999] → 2×result − 1 → [0, ~1.0].
    private func coopRemapP1(_ r: CGPoint) -> CGPoint {
        CGPoint(x: min(1.0, max(0.0, 2.0 * (p1Ax * r.x + p1Bx))),
                y: min(1.0, max(0.0, p1Ay * r.y + p1By)))
    }

    private func coopRemapP2(_ r: CGPoint) -> CGPoint {
        CGPoint(x: min(1.0, max(0.0, 2.0 * (p2Ax * r.x + p2Bx) - 1.0)),
                y: min(1.0, max(0.0, p2Ay * r.y + p2By)))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

