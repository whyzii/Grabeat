import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Content View
// Root view — owns the three long-lived objects and routes between game screens.
// All screen-specific logic lives in the individual screen files.

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @StateObject private var coopManager = CoopGameManager()
    @StateObject private var tracker     = CameraHandTracker()
    @StateObject private var photoBooth  = PhotoBoothManager()

    // Scale UI elements relative to the preferred 1280 pt window width.
    // scale = 1.0 at 1280 pt (the default window), never below 0.75 or above 2.0.
    private func computeScale(geoWidth: CGFloat) -> CGFloat {
        return min(max(geoWidth / 1280.0, 0.75), 2.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                switch gameManager.state {
                case .start:
                    StartScreen(gameManager: gameManager, tracker: tracker)
                case .tutorial:
                    TutorialView(gameManager: gameManager, tracker: tracker,
                                 isStandalone: gameManager.tutorialIsStandalone)
                case .calibrating:
                    CalibrationView(gameManager: gameManager, tracker: tracker)
                case .playing:
                    GameView(gameManager: gameManager, tracker: tracker)
                case .winnerAnnouncement:
                    WinnerAnnouncementView(gameManager: gameManager, tracker: tracker)
                case .photoBooth:
                    PhotoBoothReviewScreen(
                        gameManager: gameManager,
                        photoBooth:  photoBooth,
                        tracker:     tracker
                    )
                case .end:
                    EndScreen(gameManager: gameManager, tracker: tracker)
                case .coopTutorial:
                    CoopTutorialView(gameManager: gameManager, tracker: tracker,
                                     isStandalone: gameManager.tutorialIsStandalone)
                case .coopPlaying:
                    CoopGameView(coopManager: coopManager, gameManager: gameManager, tracker: tracker)
                case .coopPhotoBooth:
                    PhotoBoothReviewScreen(
                        gameManager: gameManager,
                        photoBooth:  photoBooth,
                        tracker:     tracker
                    )
                case .coopEnd:
                    CoopEndScreen(gameManager: gameManager, coopManager: coopManager, tracker: tracker)
                }

                // ── Photo Flash Overlay ────────────────────────────────────
                // A brief white flash whenever the photo booth captures a frame.
                // Using opacity() instead of if{} gives a smoother fade-out.
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(photoBooth.flashTriggered ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: photoBooth.flashTriggered)
            }
            #if os(iOS)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            #endif
            .onAppear {
                tracker.start()
                configureWindowIfNeeded()

                // Wire obstacle / bad-note events → photo booth captures.
                gameManager.onObstacleActivated = { [weak photoBooth] in
                    photoBooth?.onObstacleActivated()
                }
                coopManager.onBadNoteActivated = { [weak photoBooth] in
                    photoBooth?.onObstacleActivated()
                }
            }
            .onChange(of: tracker.calibrationReady) { _, ready in
                guard ready, gameManager.state == .calibrating else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard gameManager.state == .calibrating else { return }
                    tracker.finishCalibration()
                    if gameManager.isCoopMode {
                        photoBooth.setup(tracker: tracker)
                        if gameManager.photoConsentGiven == true {
                            photoBooth.startCaptures(gameDuration: Int(CoopGameManager.maxTime))
                        }
                        coopManager.startGame()
                        gameManager.state = .coopPlaying
                    } else {
                        photoBooth.setup(tracker: tracker)
                        if gameManager.photoConsentGiven == true {
                            photoBooth.startCaptures(gameDuration: GameManager.gameDurationSeconds)
                        }
                        gameManager.startGame()
                    }
                }
            }
            .onChange(of: coopManager.gameOver) { _, over in
                guard over, gameManager.state == .coopPlaying else { return }
                gameManager.state = .coopEnd
            }
            .onChange(of: gameManager.state) { _, newState in
                // Full-screen hand mapping while in co-op; versus split everywhere else.
                tracker.coopMode = (newState == .coopPlaying)

                // Stop captures the instant we leave an active game state.
                if newState != .playing && newState != .coopPlaying {
                    photoBooth.stopCaptures()
                }
                // Full reset when returning to the start screen.
                if newState == .start {
                    photoBooth.reset()
                }
            }
            .environment(\.uiScale, computeScale(geoWidth: geo.size.width))
        }
        .ignoresSafeArea()
    }

    // Opens the game at a sensible size on macOS. No-op on iOS/iPadOS.
    private func configureWindowIfNeeded() {
        #if os(macOS)
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            let preferred = CGSize(width: 1280, height: 800)
            window.setContentSize(preferred)
            window.minSize = CGSize(width: 800, height: 500)
            window.center()
        }
        #endif
    }
}

