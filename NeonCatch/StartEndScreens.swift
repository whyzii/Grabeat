import SwiftUI

// MARK: - Start Screen

struct StartScreen: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @State private var glitchOffset: CGFloat = 0
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.75)

                CyberpunkCameraFilter()
                Color.black.opacity(0.40).ignoresSafeArea()
                CyberpunkGrid()

                VStack(spacing: 0) {
                    Spacer()

                    ZStack {
                        Text("GRABEAT")
                            .font(.custom("Audiowide-Regular", size: 60 * scale))
                            .foregroundColor(.cyan)
                            .offset(x: glitchOffset, y: 0)
                            .opacity(0.4)
                        Text("GRABEAT")
                            .font(.custom("Audiowide-Regular", size: 60 * scale))
                            .foregroundColor(Color(red: 1, green: 0, blue: 1))
                            .offset(x: -glitchOffset, y: 0)
                            .opacity(0.4)
                        Text("GRABEAT")
                            .font(.custom("Audiowide-Regular", size: 60 * scale))
                            .foregroundColor(.white)
                            .shadow(color: .cyan, radius: 20)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) {
                            glitchOffset = 3
                        }
                    }

                    Text("// CYBERPUNK NOTE BRAWL //")
                        .font(.custom("Audiowide-Regular", size: 13 * scale))
                        .foregroundColor(Color(red: 1, green: 0, blue: 1).opacity(0.8))
                        .tracking(6)
                        .padding(.top, 8)
                        .padding(.bottom, 52)

                    HStack(alignment: .top, spacing: 60) {
                        PlayerInstructionCard(
                            player: 1,
                            color: .cyan,
                            side: "LEFT",
                            description: "Stand on the LEFT\nside of the camera.\n\nCatch cyan notes\nby pinching your\nthumb + index finger."
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1, height: 140)
                        PlayerInstructionCard(
                            player: 2,
                            color: Color(red: 1, green: 0, blue: 1),
                            side: "RIGHT",
                            description: "Stand on the RIGHT\nside of the camera.\n\nCatch pink notes\nby pinching your\nthumb + index finger."
                        )
                    }
                    .padding(.bottom, 40)

                    MenuHandButton(
                        label: "INITIALIZE GAME",
                        color: .cyan,
                        tracker: tracker,
                        screenSize: geo.size,
                        action: { gameManager.beginCalibration() }
                    )

                    Text("✊  PINCH TO START")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.cyan.opacity(0.55))
                        .tracking(3)
                        .padding(.top, 10)

                    Spacer()
                }

                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
            }
            .ignoresSafeArea()
        }
    }
}

struct PlayerInstructionCard: View {
    let player: Int
    let color: Color
    let side: String
    let description: String
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 10) {
            Text(player == 1 ? "◀ PLAYER \(player) — \(side)" : "PLAYER \(player) — \(side) ▶")
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(color)
                .tracking(3)
            Text(description)
                .font(.custom("Audiowide-Regular", size: 12 * scale))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(width: 250 * scale)
    }
}

// MARK: - End Screen

struct EndScreen: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @State private var appeared = false
    @Environment(\.uiScale) private var scale

    var winnerText: String {
        if gameManager.scoreP1 > gameManager.scoreP2 { return "PLAYER 1 WINS" }
        if gameManager.scoreP2 > gameManager.scoreP1 { return "PLAYER 2 WINS" }
        return "DRAW — TIED!"
    }

    var winnerColor: Color {
        if gameManager.scoreP1 > gameManager.scoreP2 { return .cyan }
        if gameManager.scoreP2 > gameManager.scoreP1 { return Color(red: 1, green: 0, blue: 1) }
        return .white
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.75)

                CyberpunkCameraFilter()
                Color.black.opacity(0.50).ignoresSafeArea()
                CyberpunkGrid()

                VStack(spacing: 0) {
                    Spacer()

                    Text("GAME OVER")
                        .font(.custom("Audiowide-Regular", size: 52 * scale))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.3), radius: 20)
                        .padding(.bottom, 20)

                    Text(winnerText)
                        .font(.custom("Audiowide-Regular", size: 38 * scale))
                        .foregroundColor(winnerColor)
                        .shadow(color: winnerColor, radius: 20)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
                        .padding(.bottom, 32)

                    Text("P1: \(gameManager.scoreP1) PTS   |   P2: \(gameManager.scoreP2) PTS")
                        .font(.custom("Audiowide-Regular", size: 14 * scale))
                        .foregroundColor(.gray)
                        .tracking(3)
                        .padding(.bottom, 40)

                    MenuHandButton(
                        label: "PLAY AGAIN",
                        color: .cyan,
                        tracker: tracker,
                        screenSize: geo.size,
                        action: { gameManager.beginCalibration() }
                    )
                    .padding(.bottom, 18)

                    MenuHandButton(
                        label: "MAIN MENU",
                        color: .gray,
                        tracker: tracker,
                        screenSize: geo.size,
                        action: { gameManager.resetToStart() }
                    )

                    Text("✊  PINCH TO SELECT")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(3)
                        .padding(.top, 14)

                    Spacer()
                }

                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }
            }
            .ignoresSafeArea()
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Calibration Screen

struct CalibrationView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(tracker: tracker)
                    .ignoresSafeArea()
                    .opacity(0.88)

                CyberpunkCameraFilter()

                HStack(spacing: 0) {
                    Color.cyan.opacity(0.07)
                    Color.magenta.opacity(0.07)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                CyberpunkGrid()

                ZStack {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.cyan.opacity(0.18), .white.opacity(0.05), .magenta.opacity(0.18)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: 24)
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 1.5)
                }
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                CalibPanel(player: 1, progress: tracker.p1CalibProgress,
                           color: .cyan, size: geo.size)
                CalibPanel(player: 2, progress: tracker.p2CalibProgress,
                           color: .magenta, size: geo.size)

                if tracker.handsP1.count > 0 { HandCursor(hand: tracker.handsP1[0], color: .cyan,    size: geo.size) }
                if tracker.handsP1.count > 1 { HandCursor(hand: tracker.handsP1[1], color: .cyan,    size: geo.size) }
                if tracker.handsP2.count > 0 { HandCursor(hand: tracker.handsP2[0], color: .magenta, size: geo.size) }
                if tracker.handsP2.count > 1 { HandCursor(hand: tracker.handsP2[1], color: .magenta, size: geo.size) }

                VStack {
                    Text("// PLAYER DETECTION //")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(4)
                        .padding(.top, 20)
                    Spacer()
                    Button { gameManager.resetToStart() } label: {
                        Text("CANCEL")
                            .font(.custom("Audiowide-Regular", size: 11 * scale))
                            .foregroundColor(.gray)
                            .tracking(3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                }

                if tracker.calibrationReady { CalibReadyOverlay() }
            }
        }
        .ignoresSafeArea()
        .onAppear { tracker.beginCalibration() }
    }
}

private struct CalibPanel: View {
    let player: Int
    let progress: Double
    let color: Color
    let size: CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let confirmed = progress >= 1.0
        let cx: CGFloat = player == 1 ? size.width * 0.25 : size.width * 0.75

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 5)
                    .frame(width: 96 * scale, height: 96 * scale)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 96 * scale, height: 96 * scale)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: progress)
                    .shadow(color: color.opacity(0.6), radius: confirmed ? 12 : 4)
                if confirmed {
                    Image(systemName: "checkmark")
                        .font(.custom("Audiowide-Regular", size: 32 * scale))
                        .foregroundColor(color)
                        .shadow(color: color, radius: 8)
                } else {
                    Text("✋")
                        .font(.custom("Audiowide-Regular", size: 32 * scale))
                        .opacity(progress > 0 ? 1 : 0.35)
                }
            }
            VStack(spacing: 4) {
                Text("PLAYER \(player)")
                    .font(.custom("Audiowide-Regular", size: 12 * scale))
                    .foregroundColor(color).tracking(4)
                Text(confirmed ? "LOCKED IN ✓" : "HOLD HAND NATURALLY")
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(color.opacity(0.70)).tracking(2)
            }
        }
        .position(x: cx, y: size.height * 0.78)
    }
}

private struct CalibReadyOverlay: View {
    @State private var appeared = false
    @Environment(\.uiScale) private var scale
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("READY!")
                    .font(.custom("Audiowide-Regular", size: 72 * scale))
                    .foregroundColor(.white)
                    .shadow(color: .cyan, radius: 24)
                Text("STARTING GAME...")
                    .font(.custom("Audiowide-Regular", size: 13 * scale))
                    .foregroundColor(.white.opacity(0.65))
                    .tracking(5)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: appeared)
            .onAppear { appeared = true }
        }
    }
}

// MARK: - Menu Hand Button

private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct MenuHandButton: View {
    let label: String
    let color: Color
    let tracker: CameraHandTracker
    let screenSize: CGSize
    let action: () -> Void

    @State private var buttonFrame: CGRect = .zero
    @State private var wasPinching  = false
    @State private var isHovered    = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        Text(label)
            .font(.custom("Audiowide-Regular", size: 15 * scale))
            .tracking(4)
            .foregroundColor(isHovered ? .black : color)
            .padding(.horizontal, 40 * scale)
            .padding(.vertical, 14 * scale)
            .background(isHovered ? color : Color.clear)
            .overlay(Rectangle().stroke(color, lineWidth: 1.5))
            .shadow(color: isHovered ? color : .clear, radius: 14)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: FramePreferenceKey.self,
                                    value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { buttonFrame = $0 }
            .onChange(of: tracker.handsP1) { _, _ in checkHands() }
            .onChange(of: tracker.handsP2) { _, _ in checkHands() }
    }

    private func checkHands() {
        guard screenSize.width > 0, buttonFrame != .zero else { return }
        // Expand hit zone: 30 % extra on each side horizontally, 50 % vertically
        let hit = buttonFrame.insetBy(dx: -buttonFrame.width  * 0.30,
                                      dy: -buttonFrame.height * 0.50)
        let all = tracker.handsP1 + tracker.handsP2
        let hovered = all.contains { h in
            guard h.isActive else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }
        let pinching = all.contains { h in
            guard h.isActive, h.isPinching else { return false }
            return hit.contains(CGPoint(x: h.position.x * screenSize.width,
                                        y: h.position.y * screenSize.height))
        }
        isHovered = hovered
        if pinching && !wasPinching { action() }
        wasPinching = pinching
    }
}

