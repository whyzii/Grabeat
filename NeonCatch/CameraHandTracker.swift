import AVFoundation
import Vision
import SwiftUI

class CameraHandTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Published

    @Published var handsP1: [HandState] = []
    @Published var handsP2: [HandState] = []
    @Published var p1CalibProgress: Double = 0
    @Published var p2CalibProgress: Double = 0
    @Published var calibrationReady: Bool  = false

    // MARK: - AVFoundation

    private let session     = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue       = DispatchQueue(label: "hand.tracking", qos: .userInteractive)
    private var handRequest = VNDetectHumanHandPoseRequest()
    private var orientationObserver: Any?
    private var cachedOrientation: UIDeviceOrientation = .landscapeLeft
    private var isRunning   = false
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Slot tracker  (capture queue only)

    private struct Slot {
        var trackPos:    CGPoint
        var dispPos:     CGPoint    // raw position (no zone clamping during calib)
        var isPinching:  Bool = false
        var pinchFrames: Int  = 0   // consecutive frames Vision detected a pinch
        var misses:      Int  = 0
        var isP1:        Bool

        var handState: HandState {
            HandState(position: dispPos, isPinching: isPinching, isActive: true)
        }
    }

    private var allSlots: [Slot] = []

    private let emaAlpha:     CGFloat = 0.65
    private let maxMisses:    Int     = 5
    private let matchDist:    CGFloat = 0.40
    // Pinch must be detected for this many consecutive Vision frames before
    // registering — eliminates brief accidental hand closures.
    private let pinchConfirm: Int     = 2

    // Calibration
    private var calibMode     = false
    private var calibP1Frames = 0
    private var calibP2Frames = 0
    private let calibTarget   = 30
    private let calibDecay    = 1

    // MARK: - Kinect-style per-player anchor  (capture queue only)
    //
    // During calibration each player holds their hand in the natural centre of
    // where they will be playing. We EMA the raw position into an anchor.
    // In game mode all raw positions are remapped so that anchor = centre of the
    // player's half, and ±hRange / ±vRange covers the full game zone.
    //
    //   Increase hRange / vRange  →  larger active area (need to move more)
    //   Decrease                  →  smaller area (small movements = full screen)
    private var p1Anchor = CGPoint(x: 0.25, y: 0.5)   // updated by calibration
    private var p2Anchor = CGPoint(x: 0.75, y: 0.5)
    private let hRange:  CGFloat = 0.16   // ±16 % of camera width per player half
    private let vRange:  CGFloat = 0.18   // ±18 % of camera height

    // EMA weight used to update the anchor during calibration.
    // Lower = smoother convergence, higher = faster response.
    private let anchorEMA: CGFloat = 0.12

    // MARK: - Init

    override init() {
        super.init()
        handRequest.maximumHandCount = 4
        setupCamera()
    }

    // MARK: - Calibration API

    func beginCalibration() {
        DispatchQueue.main.async {
            self.calibrationReady = false
            self.p1CalibProgress  = 0
            self.p2CalibProgress  = 0
            self.handsP1 = []
            self.handsP2 = []
        }
        queue.async {
            self.calibMode      = true
            self.calibP1Frames  = 0
            self.calibP2Frames  = 0
            self.allSlots       = []
            self.p1Anchor = CGPoint(x: 0.25, y: 0.5)
            self.p2Anchor = CGPoint(x: 0.75, y: 0.5)
        }
    }

    func finishCalibration() {
        queue.async { self.calibMode = false }
    }

    // MARK: - Camera setup

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

        if let conn = videoOutput.connection(with: .video) {
            conn.isVideoMirrored = false
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        applyPreviewOrientation()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleOrientationChange() }
        queue.async {
            self.session.startRunning()
            DispatchQueue.main.async { self.handleOrientationChange() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { self.session.stopRunning() }
        if let obs = orientationObserver {
            NotificationCenter.default.removeObserver(obs)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    // MARK: - Orientation

    private func handleOrientationChange() {
        let o = UIDevice.current.orientation
        if o.isLandscape { cachedOrientation = o }
        applyPreviewOrientation()
    }

    private func applyPreviewOrientation() {
        guard let conn = previewLayer?.connection else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored    = true
        conn.videoRotationAngle = (cachedOrientation == .landscapeRight) ? 180 : 0
    }

    // Vision orientation must match what the mirrored preview shows.
    // The video connection mirrors the frame, so we use non-mirrored constants
    // here — Vision sees the same pixel layout the user sees in preview.
    private func visionOrientation() -> CGImagePropertyOrientation {
        cachedOrientation == .landscapeRight ? .right : .left
    }

    // MARK: - Capture delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: px,
                                            orientation: visionOrientation(),
                                            options: [:])
        try? handler.perform([handRequest])
        guard let obs = handRequest.results else { return }

        if calibMode { runCalibration(obs) } else { runGame(obs) }
    }

    // MARK: - Raw detection

    private func rawHand(_ obs: VNHumanHandPoseObservation) -> HandState? {
        guard let w = try? obs.recognizedPoint(.wrist), w.confidence > 0.30 else { return nil }
        var hs = HandState()
        hs.isActive   = true
        // Vision riceve il buffer raw (non specchiato), ma il preview è specchiato
        // (conn.isVideoMirrored = true). Dobbiamo specchiare la x per far coincidere
        // le coordinate Vision con quello che l'utente vede sullo schermo:
        // chi appare a destra nel preview deve avere x > 0.5.
        //
        // In landscape, Vision usa assi ruotati: w.y → x schermo, w.x → y schermo.
        // Senza specchiatura: x = 1 - w.y  (utente reale a destra → x alto ✓ ma preview specchiato)
        // Con specchiatura:   x = w.y      (inverte l'asse x, allinea con il preview)
        hs.position   = CGPoint(x: CGFloat(w.y), y: 1 - CGFloat(w.x))
        hs.isPinching = pinching(obs)
        return hs
    }

    private func pinching(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard let t = try? obs.recognizedPoint(.thumbTip),
              let i = try? obs.recognizedPoint(.indexTip),
              t.confidence > 0.60, i.confidence > 0.60 else { return false }
        let dx = t.x - i.x, dy = t.y - i.y
        // Threshold tightened from 0.06 → 0.04 so a slightly closed hand
        // does not register. A deliberate pinch consistently sits below 0.03.
        return sqrt(dx*dx + dy*dy) < 0.04
    }

    // MARK: - Slot update (game mode)
    //
    // Slots are zone-clamped so a hand can never visually cross to the
    // other player's side during gameplay.

    private func updateSlotsGame(detections: [HandState]) {
        var used = [Bool](repeating: false, count: detections.count)

        for i in allSlots.indices {
            var bestDist: CGFloat = matchDist
            var bestJ   = -1

            for j in detections.indices where !used[j] {
                // Hard zone guard: a slot only ever matches detections in its own zone.
                guard allSlots[i].isP1 == (detections[j].position.x < 0.5) else { continue }
                let raw = dist(allSlots[i].trackPos, detections[j].position)
                if raw < bestDist { bestDist = raw; bestJ = j }
            }

            if bestJ >= 0 {
                let d  = detections[bestJ]
                let α  = emaAlpha
                let tx = α * d.position.x + (1 - α) * allSlots[i].trackPos.x
                let ty = α * d.position.y + (1 - α) * allSlots[i].trackPos.y
                // Clamp display position to the slot's zone.
                let dx = allSlots[i].isP1 ? min(tx, 0.499) : max(tx, 0.500)
                allSlots[i].trackPos = CGPoint(x: tx, y: ty)
                allSlots[i].dispPos  = CGPoint(x: dx, y: ty)
                allSlots[i].misses   = 0
                used[bestJ]          = true

                if d.isPinching {
                    allSlots[i].pinchFrames = min(allSlots[i].pinchFrames + 1, pinchConfirm)
                } else {
                    allSlots[i].pinchFrames = 0
                }
                allSlots[i].isPinching = allSlots[i].pinchFrames >= pinchConfirm
            } else {
                allSlots[i].misses      += 1
                allSlots[i].pinchFrames  = 0
                allSlots[i].isPinching   = false
            }
        }

        allSlots.removeAll { $0.misses > maxMisses }

        for (j, det) in detections.enumerated() where !used[j] {
            let isP1 = det.position.x < 0.5
            guard allSlots.filter({ $0.isP1 == isP1 }).count < 2 else { continue }
            let cx = isP1 ? min(det.position.x, 0.499) : max(det.position.x, 0.500)
            allSlots.append(Slot(
                trackPos: det.position,
                dispPos:  CGPoint(x: cx, y: det.position.y),
                isP1:     isP1
            ))
        }
    }

    // MARK: - Slot update (calibration mode)
    //
    // During calibration we do NOT clamp to zone boundaries. The cursor shows
    // the hand's true raw position so the player can see exactly where they
    // are before the remap is applied. Zone assignment still uses the raw
    // x < 0.5 split, which is correct because anchors live in raw space.

    private func updateSlotsCalib(detections: [HandState]) {
        var used = [Bool](repeating: false, count: detections.count)

        for i in allSlots.indices {
            var bestDist: CGFloat = matchDist
            var bestJ   = -1

            for j in detections.indices where !used[j] {
                guard allSlots[i].isP1 == (detections[j].position.x < 0.5) else { continue }
                let raw = dist(allSlots[i].trackPos, detections[j].position)
                if raw < bestDist { bestDist = raw; bestJ = j }
            }

            if bestJ >= 0 {
                let d  = detections[bestJ]
                let α  = emaAlpha
                let tx = α * d.position.x + (1 - α) * allSlots[i].trackPos.x
                let ty = α * d.position.y + (1 - α) * allSlots[i].trackPos.y
                // No zone clamping during calibration — show true raw position.
                allSlots[i].trackPos = CGPoint(x: tx, y: ty)
                allSlots[i].dispPos  = CGPoint(x: tx, y: ty)
                allSlots[i].misses   = 0
                used[bestJ]          = true

                if d.isPinching {
                    allSlots[i].pinchFrames = min(allSlots[i].pinchFrames + 1, pinchConfirm)
                } else {
                    allSlots[i].pinchFrames = 0
                }
                allSlots[i].isPinching = allSlots[i].pinchFrames >= pinchConfirm
            } else {
                allSlots[i].misses      += 1
                allSlots[i].pinchFrames  = 0
                allSlots[i].isPinching   = false
            }
        }

        allSlots.removeAll { $0.misses > maxMisses }

        for (j, det) in detections.enumerated() where !used[j] {
            let isP1 = det.position.x < 0.5
            guard allSlots.filter({ $0.isP1 == isP1 }).count < 2 else { continue }
            allSlots.append(Slot(
                trackPos: det.position,
                dispPos:  det.position,     // raw — no clamping
                isP1:     isP1
            ))
        }
    }

    // MARK: - Kinect-style coordinate remapping
    //
    // Maps a raw camera-space position to game-space [0, 1] using the
    // player's calibrated anchor as the centre of their active zone.

    private func remapP1(_ raw: CGPoint) -> CGPoint {
        let x = (raw.x - (p1Anchor.x - hRange)) / (2 * hRange) * 0.499
        let y = (raw.y - (p1Anchor.y - vRange)) / (2 * vRange)
        return CGPoint(x: min(0.499, max(0.0, x)), y: min(1.0, max(0.0, y)))
    }

    private func remapP2(_ raw: CGPoint) -> CGPoint {
        // Normalise within P2's active range [0, 1], then map to [0.500, 0.999].
        let xNorm = (raw.x - (p2Anchor.x - hRange)) / (2 * hRange)
        let x     = 0.500 + xNorm * 0.499
        let y     = (raw.y - (p2Anchor.y - vRange)) / (2 * vRange)
        return CGPoint(x: min(0.999, max(0.500, x)), y: min(1.0, max(0.0, y)))
    }

    // MARK: - Calibration pass

    private func runCalibration(_ observations: [VNHumanHandPoseObservation]) {
        var dets: [HandState] = []
        for obs in observations { if let hs = rawHand(obs) { dets.append(hs) } }

        // EMA-update the anchors from raw positions so they converge to
        // wherever the player's hand is held (recent frames dominate).
        for d in dets {
            if d.position.x < 0.5 {
                p1Anchor.x = anchorEMA * d.position.x + (1 - anchorEMA) * p1Anchor.x
                p1Anchor.y = anchorEMA * d.position.y + (1 - anchorEMA) * p1Anchor.y
            } else {
                p2Anchor.x = anchorEMA * d.position.x + (1 - anchorEMA) * p2Anchor.x
                p2Anchor.y = anchorEMA * d.position.y + (1 - anchorEMA) * p2Anchor.y
            }
        }

        // Use the calibration-specific slot updater (no zone clamping) so the
        // cursor faithfully shows the hand's raw camera position.
        updateSlotsCalib(detections: dets)

        let hasP1 = allSlots.contains { $0.isP1  && $0.misses == 0 }
        let hasP2 = allSlots.contains { !$0.isP1 && $0.misses == 0 }

        calibP1Frames = hasP1
            ? min(calibP1Frames + 1, calibTarget)
            : max(calibP1Frames - calibDecay, 0)
        calibP2Frames = hasP2
            ? min(calibP2Frames + 1, calibTarget)
            : max(calibP2Frames - calibDecay, 0)

        let prog1 = Double(calibP1Frames) / Double(calibTarget)
        let prog2 = Double(calibP2Frames) / Double(calibTarget)
        let done  = prog1 >= 1.0 && prog2 >= 1.0

        let sp1 = allSlots.filter {  $0.isP1 }.sorted { $0.dispPos.x < $1.dispPos.x }.map(\.handState)
        let sp2 = allSlots.filter { !$0.isP1 }.sorted { $0.dispPos.x < $1.dispPos.x }.map(\.handState)

        DispatchQueue.main.async {
            if self.handsP1 != sp1 { self.handsP1 = sp1 }
            if self.handsP2 != sp2 { self.handsP2 = sp2 }
            self.p1CalibProgress = prog1
            self.p2CalibProgress = prog2
            if done, !self.calibrationReady { self.calibrationReady = true }
        }
    }

    // MARK: - Game pass

    private func runGame(_ observations: [VNHumanHandPoseObservation]) {
        var dets: [HandState] = []
        for obs in observations { if let hs = rawHand(obs) { dets.append(hs) } }

        // Slot matching in raw camera space with hard zone guard.
        updateSlotsGame(detections: dets)

        // Apply Kinect-style remap at publish time.
        let sp1 = allSlots.filter { $0.isP1 }.sorted { $0.dispPos.x < $1.dispPos.x }.map { s -> HandState in
            HandState(position: remapP1(s.dispPos), isPinching: s.isPinching, isActive: true)
        }
        let sp2 = allSlots.filter { !$0.isP1 }.sorted { $0.dispPos.x < $1.dispPos.x }.map { s -> HandState in
            HandState(position: remapP2(s.dispPos), isPinching: s.isPinching, isActive: true)
        }

        DispatchQueue.main.async {
            if self.handsP1 != sp1 { self.handsP1 = sp1 }
            if self.handsP2 != sp2 { self.handsP2 = sp2 }
        }
    }

    // MARK: - Helpers

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx*dx + dy*dy)
    }
}
