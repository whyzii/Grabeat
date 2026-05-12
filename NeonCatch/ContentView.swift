import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @StateObject private var tracker    = CameraHandTracker()

    // Scale UI elements relative to a 1024 pt baseline (iPad-portrait width).
    // The window now resizes freely on macOS, so geo-based scaling alone is
    // sufficient — no need for the old isiOSAppOnMac floor.
    private func computeScale(geoWidth: CGFloat) -> CGFloat {
        let base = max(geoWidth / 1024.0, 1.0)
        return min(base, 2.5)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                switch gameManager.state {
                case .start:
                    StartScreen(gameManager: gameManager, tracker: tracker)
                case .calibrating:
                    CalibrationView(gameManager: gameManager, tracker: tracker)
                case .playing:
                    GameView(gameManager: gameManager, tracker: tracker)
                case .end:
                    EndScreen(gameManager: gameManager, tracker: tracker)
                }
            }
            #if os(iOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            #endif
            .onAppear {
                tracker.start()
                configureWindowIfNeeded()
            }
            .onChange(of: tracker.calibrationReady) { _, ready in
                guard ready, gameManager.state == .calibrating else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard gameManager.state == .calibrating else { return }
                    tracker.finishCalibration()
                    gameManager.startGame()
                }
            }
            .environment(\.uiScale, computeScale(geoWidth: geo.size.width))
        }
        .ignoresSafeArea()
    }

    // Configure a sensible window size on macOS so the game opens at a
    // useful resolution. On iOS / iPadOS the window is full-screen and
    // this is a no-op.
    private func configureWindowIfNeeded() {
        #if os(macOS)
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            // Aim for a reasonable default size; the user can resize freely.
            let preferred = CGSize(width: 1280, height: 800)
            window.setContentSize(preferred)
            window.minSize = CGSize(width: 800, height: 500)
            window.center()
        }
        #endif
    }
}
