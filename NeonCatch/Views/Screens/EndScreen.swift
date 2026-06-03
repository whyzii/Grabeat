import SwiftUI

// MARK: - Winner Announcement View
// Glitch-ring reveal screen shown between game-end and the photo booth.
// Deep purple background, animated chromatic-aberration ring, displaced glitch
// bars — pinch CONTINUE to proceed (no auto-advance timer).

struct WinnerAnnouncementView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker:     CameraHandTracker

    @State private var appeared    = false
    @State private var winnerReady = false
    @State private var ctaReady    = false

    @Environment(\.uiScale) private var scale

    // MARK: - Derived

    private var scoreP1: Int { gameManager.scoreP1 }
    private var scoreP2: Int { gameManager.scoreP2 }

    private enum Outcome { case p1, p2, draw }
    private var outcome: Outcome {
        scoreP1 > scoreP2 ? .p1 : scoreP2 > scoreP1 ? .p2 : .draw
    }
    private var winnerColor: Color {
        switch outcome {
        case .p1:   return .cyan
        case .p2:   return Color(red: 1, green: 0, blue: 1)
        case .draw: return .white
        }
    }
    private var winnerLabel: String {
        switch outcome {
        case .p1: return "PLAYER 1"
        case .p2: return "PLAYER 2"
        case .draw: return "DRAW"
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // 1 ── Background: same as home screen
                GlitchCircleBackground()

                // 2 ── Winner text centred inside the ring
                VStack(spacing: 6 * scale) {
                    Text("GAME OVER")
                        .font(.custom("Audiowide-Regular", size: 28 * scale))
                        .foregroundColor(.white.opacity(0.38))
                        .tracking(10)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                    Text(winnerLabel)
                        .font(.custom("Audiowide-Regular", size: 32 * scale))
                        .foregroundColor(.white)
                        .shadow(color: winnerColor, radius: 18)
                        .shadow(color: winnerColor.opacity(0.5), radius: 36)
                        .tracking(5)

                    Text(outcome == .draw ? "P E R F E C T  T I E" : "W I N S !")
                        .font(.custom("Audiowide-Regular", size: 18 * scale))
                        .foregroundColor(.white.opacity(0.75))
                        .tracking(7)
                        .padding(.bottom, 10 * scale)

                    // Compact score comparison
                    HStack(spacing: 16 * scale) {
                        miniScore(score: scoreP1, color: .cyan,
                                  label: "P1", isWinner: outcome == .p1)
                        Text("VS")
                            .font(.custom("Audiowide-Regular", size: 26 * scale))
                            .foregroundColor(.white.opacity(0.22))
                            .tracking(3)
                        miniScore(score: scoreP2,
                                  color: Color(red: 1, green: 0, blue: 1),
                                  label: "P2", isWinner: outcome == .p2)
                    }
                }
                .scaleEffect(winnerReady ? 1.0 : 0.35)
                .opacity(winnerReady ? 1 : 0)
                .animation(.spring(response: 0.44, dampingFraction: 0.58), value: winnerReady)
                .position(x: W / 2, y: H / 2)

                // 3 ── CONTINUE button — pinch required, no auto-advance
                VStack {
                    Spacer()
                    MenuHandButton(
                        label: "CONTINUE",
                        color: .white,
                        tracker: tracker,
                        screenSize: geo.size
                    ) {
                        gameManager.proceedToPhotoBooth()
                    }
                    .padding(.bottom, 44 * scale)
                }
                .opacity(ctaReady ? 1 : 0)
                .animation(.easeIn(duration: 0.4), value: ctaReady)

                // 4 ── Hand cursors
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
            }
            .ignoresSafeArea()
        }
        .onAppear { startSequence() }
    }

    // MARK: - Mini score label

    private func miniScore(score: Int, color: Color, label: String, isWinner: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.custom("Audiowide-Regular", size: isWinner ? 40 * scale : 30 * scale))
                .foregroundColor(isWinner ? color : color.opacity(0.32))
                .shadow(color: isWinner ? color : .clear, radius: 8)
                .monospacedDigit()
            Text("\(label)  PTS")
                .font(.custom("Audiowide-Regular", size: 18 * scale))
                .foregroundColor(isWinner ? color.opacity(0.65) : color.opacity(0.20))
                .tracking(2)
        }
    }

    // MARK: - Animation sequence

    private func startSequence() {
        appeared = true
        after(0.50) { winnerReady = true }
        after(1.20) { ctaReady    = true }
    }

    private func after(_ s: Double, block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: block)
    }
}

// MARK: - End Screen

struct EndScreen: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @State private var appeared = false
    @Environment(\.uiScale) private var scale

    private var winnerLabel: String {
        if gameManager.scoreP1 > gameManager.scoreP2 { return "PLAYER 1" }
        if gameManager.scoreP2 > gameManager.scoreP1 { return "PLAYER 2" }
        return "DRAW"
    }
    private var winnerSub: String {
        if gameManager.scoreP1 == gameManager.scoreP2 { return "PERFECT TIE" }
        return "W I N S !"
    }
    private var winnerColor: Color {
        if gameManager.scoreP1 > gameManager.scoreP2 { return .cyan }
        if gameManager.scoreP2 > gameManager.scoreP1 { return Color(red: 1, green: 0, blue: 1) }
        return .white
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // ── Background: same as home screen ─────────────────────────
                GlitchCircleBackground()

                // ── Results — centred inside the ring ────────────────────────
                VStack(spacing: 6 * scale) {
                    Text("GAME OVER")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.38))
                        .tracking(10)

                    Text(winnerLabel)
                        .font(.custom("Audiowide-Regular", size: 30 * scale))
                        .foregroundColor(.white)
                        .shadow(color: winnerColor, radius: 18)
                        .shadow(color: winnerColor.opacity(0.5), radius: 36)
                        .tracking(5)

                    Text(winnerSub)
                        .font(.custom("Audiowide-Regular", size: 13 * scale))
                        .foregroundColor(.white.opacity(0.70))
                        .tracking(6)
                        .padding(.bottom, 10 * scale)

                    HStack(spacing: 16 * scale) {
                        scoreChip(score: gameManager.scoreP1, color: .cyan,
                                  label: "P1", isWinner: gameManager.scoreP1 > gameManager.scoreP2)
                        Text("VS")
                            .font(.custom("Audiowide-Regular", size: 9 * scale))
                            .foregroundColor(.white.opacity(0.22))
                            .tracking(3)
                        scoreChip(score: gameManager.scoreP2,
                                  color: Color(red: 1, green: 0, blue: 1),
                                  label: "P2", isWinner: gameManager.scoreP2 > gameManager.scoreP1)
                    }
                }
                .scaleEffect(appeared ? 1.0 : 0.4)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.60), value: appeared)
                .position(x: W / 2, y: H / 2)

                // ── Buttons — below the ring ──────────────────────────────────
                VStack(spacing: 0) {
                    Spacer()
                    MenuHandButton(
                        label: "PLAY AGAIN", color: .cyan,
                        tracker: tracker, screenSize: geo.size,
                        action: { gameManager.beginCalibration() }
                    )
                    .padding(.bottom, 16 * scale)
                    MenuHandButton(
                        label: "MAIN MENU", color: .white.opacity(0.55),
                        tracker: tracker, screenSize: geo.size,
                        action: { gameManager.resetToStart() }
                    )
                    Text("PINCH TO SELECT")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.30))
                        .tracking(3)
                        .padding(.top, 12 * scale)
                        .padding(.bottom, 40 * scale)
                }

                // ── Hand cursors ──────────────────────────────────────────────
                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { appeared = true }
        }
    }

    private func scoreChip(score: Int, color: Color, label: String, isWinner: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.custom("Audiowide-Regular", size: isWinner ? 22 * scale : 14 * scale))
                .foregroundColor(isWinner ? color : color.opacity(0.32))
                .shadow(color: isWinner ? color : .clear, radius: 8)
                .monospacedDigit()
            Text("\(label)  PTS")
                .font(.custom("Audiowide-Regular", size: 7 * scale))
                .foregroundColor(isWinner ? color.opacity(0.65) : color.opacity(0.20))
                .tracking(2)
        }
    }
}
