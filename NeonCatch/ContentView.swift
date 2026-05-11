import SwiftUI

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @StateObject private var tracker    = CameraHandTracker()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch gameManager.state {
            case .start:
                StartScreen(gameManager: gameManager)
            case .calibrating:
                CalibrationView(gameManager: gameManager, tracker: tracker)
            case .playing:
                GameView(gameManager: gameManager, tracker: tracker)
            case .end:
                EndScreen(gameManager: gameManager)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { tracker.start() }
        .onChange(of: tracker.calibrationReady) { _, ready in
            guard ready, gameManager.state == .calibrating else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard gameManager.state == .calibrating else { return }
                tracker.finishCalibration()
                gameManager.startGame()
            }
        }
    }
}
