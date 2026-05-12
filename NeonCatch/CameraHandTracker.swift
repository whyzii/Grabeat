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

// MARK: - CameraHandTracker

class CameraHandTracker: NSObject, ObservableObject,
                         AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: Published

    @Published var handsP1:          [HandState] = []
    @Published var handsP2:          [HandState] = []
    @Published var p1CalibProgress:  Double = 0
    @Published var p2CalibProgress:  Double = 0
    @Published var calibrationReady: Bool   = false

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

    // MARK: Internal track  (capture queue only)
    //
    // One Track per confirmed hand. Positions are EMA-smoothed; velocity is
    // tracked so the 60 fps display timer can extrapolate the cursor between
    // Vision frames (~30 fps), giving perfectly smooth 60 fps motion.

    private struct Track {
        var pos:        CGPoint        // smoothed normalised screen position [0,1]
        var velPerSec:  CGPoint        // normalised units/second for dead-reckoning
        var pinching:   Bool   = false
        var pinchCount: Int    = 0     // debounce accumulator
        var isP1:       Bool
        var age:        Int    = 0     // consecutive Vision hits (ramp alpha)
        var misses:     Int    = 0     // consecutive Vision misses
    }

    private var tracks: [Track] = []

    // Tracking constants
    private let matchRadius:  CGFloat = 0.35  // max dist to match to existing track
    private let maxMisses:    Int     = 25    // ~833 ms at 30 fps before eviction
    private let pinchConfirm: Int     = 3     // consecutive frames required to enter pinch
    private let maxPerPlayer: Int     = 2     // max tracked hands per side

    // Two-threshold hysteresis for pinch.
    // enterThresh: fingers must be THIS close to start a pinch (genuinely touching).
    // exitThresh:  hand must open THIS much before pinch is released.
    // The gap between them (0.025 … 0.045) is the dead zone where a half-closed
    // hand sits — it never enters and never holds the pinch state.
    private let pinchEnter: CGFloat = 0.025
    private let pinchExit:  CGFloat = 0.045

    // MARK: Display snapshot  (main-queue only)
    //
    // Each Vision frame the capture queue pushes a lightweight snapshot to
    // the main queue. A 60 fps timer extrapolates each snapshot's position
    // by its velocity, decaying toward zero as elapsed time grows.
    //
    // Result: the cursor updates every ~16 ms at display rate even though
    // Vision only fires every ~33 ms — no more 33 ms jerk between frames.

    private struct Snapshot {
        var pos:       CGPoint
        var velPerSec: CGPoint
        var pinching:  Bool
        var isP1:      Bool
        var stamp:     Date
    }

    private var snapshots:    [Snapshot] = []  // main-queue only
    private var calibrating:  Bool       = false
    private var displayTimer: AnyCancellable?

    // MARK: Kinect-style anchor remap
    //
    // Calibration records where each player naturally holds their hand.
    // In game mode that anchor maps to the centre of their half, and
    // ±hRange / ±vRange covers the full zone — small natural arm
    // movements fill the entire game area regardless of camera distance.

    private var p1Anchor = CGPoint(x: 0.25, y: 0.5)
    private var p2Anchor = CGPoint(x: 0.75, y: 0.5)
    private let hRange:    CGFloat = 0.16
    private let vRange:    CGFloat = 0.18
    private let anchorEMA: CGFloat = 0.10

    // MARK: Calibration  (capture queue)

    private var calibMode     = false
    private var calibP1Frames = 0
    private var calibP2Frames = 0
    private let calibTarget   = 30
    private let calibDecay    = 1

    // MARK: Init

    override init() {
        super.init()
        handRequest.maximumHandCount = 4
        setupCamera()
    }

    // MARK: Public API  (call on main thread)

    func beginCalibration() {
        calibrating      = true
        calibrationReady = false
        p1CalibProgress  = 0
        p2CalibProgress  = 0
        handsP1          = []
        handsP2          = []
        snapshots        = []
        queue.async {
            self.calibMode      = true
            self.calibP1Frames  = 0
            self.calibP2Frames  = 0
            self.tracks         = []
            self.p1Anchor       = CGPoint(x: 0.25, y: 0.5)
            self.p2Anchor       = CGPoint(x: 0.75, y: 0.5)
        }
    }

    func finishCalibration() {
        calibrating = false
        queue.async { self.calibMode = false }
    }

    // MARK: Camera setup

    private func setupCamera() {
        session.sessionPreset = .hd1280x720
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video, position: .front),
            let input  = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        session.addOutput(videoOutput)

        if let conn = videoOutput.connection(with: .video) {
            conn.isVideoMirrored = false
        }

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
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
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

    // MARK: 60 fps display timer

    private func startDisplayTimer() {
        displayTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.publishDisplayState() }
    }

    private func publishDisplayState() {
        let now = Date()
        snapshots.removeAll { now.timeIntervalSince($0.stamp) > 0.60 }

        var p1: [HandState] = []
        var p2: [HandState] = []

        for snap in snapshots {
            let elapsed = CGFloat(now.timeIntervalSince(snap.stamp))

            // Velocity contribution fades to zero over ~400 ms of no new data
            // so dead-reckoning trails off gracefully rather than drifting away.
            let decay = max(0.0, 1.0 - elapsed / 0.4)
            let px    = max(0, min(1, snap.pos.x + snap.velPerSec.x * elapsed * decay))
            let py    = max(0, min(1, snap.pos.y + snap.velPerSec.y * elapsed * decay))
            let proj  = CGPoint(x: px, y: py)

            // Pinch state only valid while Vision is actively updating (~1 frame gap ok)
            let pinch = snap.pinching && elapsed < 0.12

            let mapped: CGPoint
            if calibrating {
                mapped = proj                                        // raw during calibration
            } else {
                mapped = snap.isP1 ? remapP1(proj) : remapP2(proj) // kinect remap during game
            }

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
        conn.isVideoMirrored    = true
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
        let handler = VNImageRequestHandler(cvPixelBuffer: px,
                                            orientation: visionOrientation(),
                                            options: [:])
        try? handler.perform([handRequest])
        let obs = handRequest.results ?? []
        if calibMode { runCalibration(obs) } else { runGame(obs) }
    }

    // MARK: Raw detection

    private func handScreenPos(_ obs: VNHumanHandPoseObservation) -> HandState? {
        guard let w = try? obs.recognizedPoint(.wrist), w.confidence > 0.20 else { return nil }

        // Average wrist + middleMCP for a stable palm-centre position.
        var rx = CGFloat(w.x), ry = CGFloat(w.y)
        if let m = try? obs.recognizedPoint(.middleMCP), m.confidence > 0.20 {
            rx = (rx + CGFloat(m.x)) * 0.5
            ry = (ry + CGFloat(m.y)) * 0.5
        }

        var hs = HandState()
        hs.isActive  = true
        hs.pinchDist = rawPinchDist(obs) ?? 1.0  // 1.0 = fully open; hysteresis applied in track
        // isPinching is NOT set here — it is resolved per-track with hysteresis in updateTracks
        #if os(macOS)
        hs.position = CGPoint(x: 1 - rx, y: 1 - ry)
        #else
        hs.position = CGPoint(x: ry, y: 1 - rx)
        #endif
        return hs
    }

    // Returns raw thumb-index distance in Vision normalised space, or nil if
    // either tip is low-confidence. Does NOT apply the pinch threshold.
    private func rawPinchDist(_ obs: VNHumanHandPoseObservation) -> CGFloat? {
        guard let t = try? obs.recognizedPoint(.thumbTip),
              let i = try? obs.recognizedPoint(.indexTip),
              t.confidence > 0.45, i.confidence > 0.45 else { return nil }
        let dx = CGFloat(t.x - i.x), dy = CGFloat(t.y - i.y)
        return sqrt(dx*dx + dy*dy)
    }

    // MARK: Track update  (capture queue)

    private func updateTracks(detections: [HandState]) {
        var used = [Bool](repeating: false, count: detections.count)
        let dt   = CGFloat(1.0 / 30.0)  // nominal Vision frame interval

        // Match each existing track to the nearest detection.
        // No hard zone guard here: once a track is created for P1 or P2 it is
        // sticky. A brief Vision outlier that puts P1's hand just past x=0.5
        // used to reject the match and start accumulating misses → flinch and
        // eventual disappearance. Pure distance matching solves that; the
        // maxPerPlayer cap on new-track creation still prevents zone overflow.
        for i in tracks.indices {
            var bestDist: CGFloat = matchRadius
            var bestJ             = -1
            for j in detections.indices where !used[j] {
                let d = dist(tracks[i].pos, detections[j].position)
                if d < bestDist { bestDist = d; bestJ = j }
            }

            if bestJ >= 0 {
                let raw  = detections[bestJ].position
                let prev = tracks[i].pos
                // Snappier alpha for new tracks, smoother once stable
                let α: CGFloat = tracks[i].age < 6 ? 0.75 : 0.50
                let nx   = α * raw.x + (1-α) * prev.x
                let ny   = α * raw.y + (1-α) * prev.y
                // EMA-smooth velocity (frame delta → per-second units)
                let rawVx = (nx - prev.x) / dt
                let rawVy = (ny - prev.y) / dt
                tracks[i].velPerSec.x = 0.35 * rawVx + 0.65 * tracks[i].velPerSec.x
                tracks[i].velPerSec.y = 0.35 * rawVy + 0.65 * tracks[i].velPerSec.y
                tracks[i].pos         = CGPoint(x: nx, y: ny)
                tracks[i].age        += 1
                tracks[i].misses      = 0
                used[bestJ]           = true

                // Two-threshold hysteresis — the dead zone between enterThresh and
                // exitThresh is where half-pinched hands live; they never register.
                let d = detections[bestJ].pinchDist
                if tracks[i].pinching {
                    // Already pinching: hold until the hand genuinely opens.
                    // Exit is immediate — one open frame clears the counter.
                    tracks[i].pinchCount = d < pinchExit ? pinchConfirm : 0
                } else {
                    // Not pinching: require pinchConfirm consecutive frames below
                    // the tight entry threshold before registering.
                    tracks[i].pinchCount = d < pinchEnter
                        ? min(tracks[i].pinchCount + 1, pinchConfirm)
                        : max(tracks[i].pinchCount - 1, 0)
                }
                tracks[i].pinching = tracks[i].pinchCount >= pinchConfirm

            } else {
                tracks[i].misses += 1
                // Slow velocity decay on miss so extrapolation coasts naturally
                tracks[i].velPerSec.x *= 0.75
                tracks[i].velPerSec.y *= 0.75
                if tracks[i].misses > 3 {
                    tracks[i].pinchCount = 0
                    tracks[i].pinching   = false
                }
            }
        }

        tracks.removeAll { $0.misses > maxMisses }

        // Spawn a new track for any unmatched detection (up to cap per side)
        for (j, det) in detections.enumerated() where !used[j] {
            let isP1 = det.position.x < 0.5
            guard tracks.filter({ $0.isP1 == isP1 }).count < maxPerPlayer else { continue }
            tracks.append(Track(pos: det.position, velPerSec: .zero, isP1: isP1))
        }
    }

    // MARK: Game pass

    private func runGame(_ observations: [VNHumanHandPoseObservation]) {
        let dets = observations.compactMap { handScreenPos($0) }
        updateTracks(detections: dets)
        pushSnapshot()
    }

    // MARK: Calibration pass

    private func runCalibration(_ observations: [VNHumanHandPoseObservation]) {
        let dets = observations.compactMap { handScreenPos($0) }
        updateTracks(detections: dets)

        // EMA-converge each player's anchor toward their current hand position
        for t in tracks where t.misses == 0 {
            if t.isP1 {
                p1Anchor.x = anchorEMA * t.pos.x + (1-anchorEMA) * p1Anchor.x
                p1Anchor.y = anchorEMA * t.pos.y + (1-anchorEMA) * p1Anchor.y
            } else {
                p2Anchor.x = anchorEMA * t.pos.x + (1-anchorEMA) * p2Anchor.x
                p2Anchor.y = anchorEMA * t.pos.y + (1-anchorEMA) * p2Anchor.y
            }
        }

        let hasP1     = tracks.contains { $0.isP1  && $0.misses == 0 }
        let hasP2     = tracks.contains { !$0.isP1 && $0.misses == 0 }
        calibP1Frames = hasP1 ? min(calibP1Frames + 1, calibTarget)
                              : max(calibP1Frames - calibDecay, 0)
        calibP2Frames = hasP2 ? min(calibP2Frames + 1, calibTarget)
                              : max(calibP2Frames - calibDecay, 0)

        let prog1 = Double(calibP1Frames) / Double(calibTarget)
        let prog2 = Double(calibP2Frames) / Double(calibTarget)
        let done  = prog1 >= 1.0 && prog2 >= 1.0

        pushSnapshot()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.p1CalibProgress = prog1
            self.p2CalibProgress = prog2
            if done && !self.calibrationReady { self.calibrationReady = true }
        }
    }

    private func pushSnapshot() {
        let snap = tracks.map {
            Snapshot(pos: $0.pos, velPerSec: $0.velPerSec,
                     pinching: $0.pinching, isP1: $0.isP1, stamp: Date())
        }
        DispatchQueue.main.async { [weak self] in self?.snapshots = snap }
    }

    // MARK: Kinect-style coordinate remap

    private func remapP1(_ raw: CGPoint) -> CGPoint {
        let x = (raw.x - (p1Anchor.x - hRange)) / (2 * hRange) * 0.499
        let y = (raw.y - (p1Anchor.y - vRange)) / (2 * vRange)
        return CGPoint(x: min(0.499, max(0.0, x)), y: min(1.0, max(0.0, y)))
    }

    private func remapP2(_ raw: CGPoint) -> CGPoint {
        let xNorm = (raw.x - (p2Anchor.x - hRange)) / (2 * hRange)
        let x     = 0.500 + xNorm * 0.499
        let y     = (raw.y - (p2Anchor.y - vRange)) / (2 * vRange)
        return CGPoint(x: min(0.999, max(0.500, x)), y: min(1.0, max(0.0, y)))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx*dx + dy*dy)
    }
}
