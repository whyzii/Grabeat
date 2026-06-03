import SwiftUI

// MARK: - Silhouette Overlay
//
// Renders the Vision person-segmentation mask as a cyberpunk neon silhouette.
// The CGImage is fully pre-processed in CameraHandTracker.processSilhouette():
//   • Left half = cyan  (P1 zone)   Right half = magenta  (P2 zone)
//   • Dark interior (~18 % brightness, 55 % alpha)  →  Tron-style body fill
//   • Neon edge glow (Gaussian blur blooms outward from the person boundary)
//   • Horizontally mirrored to match the AVCaptureVideoPreviewLayer
//
// The view itself is a single Image draw + opacity pulse — zero extra work on the main thread.
// Beat-phase drives a gentle ±12 % opacity flicker in sync with the music.

struct SilhouetteOverlay: View {
    let mask:      CGImage?
    let beatPhase: Double   // 0–1 phase from AudioEngine; drives subtle beat-sync pulse

    // ±12 % pulse: peaks when beatPhase≈0 (on the beat), dims between beats
    private var pulseOpacity: Double {
        0.82 + 0.18 * (0.5 + 0.5 * cos(beatPhase * .pi * 2))
    }

    var body: some View {
        if let mask {
            Image(decorative: mask, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
                .opacity(pulseOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .clipped()
        }
    }
}
