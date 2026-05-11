import SwiftUI

// MARK: - Start Screen

struct StartScreen: View {
    @ObservedObject var gameManager: GameManager
    @State private var glitchOffset: CGFloat = 0
    @State private var scanY: CGFloat = -100

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CyberpunkGrid()

            VStack(spacing: 0) {
                Spacer()

                // Title
                ZStack {
                    Text("GRABEAT")
                        .font(.custom("Audiowide-Regular", size: 60))
                        .foregroundColor(.cyan)
                        .offset(x: glitchOffset, y: 0)
                        .opacity(0.4)
                    Text("GRABEAT")
                        .font(.custom("Audiowide-Regular", size: 60))
                        .foregroundColor(Color(red: 1, green: 0, blue: 1))
                        .offset(x: -glitchOffset, y: 0)
                        .opacity(0.4)
                    Text("GRABEAT")
                        .font(.custom("Audiowide-Regular", size: 60))
                        .foregroundColor(.white)
                        .shadow(color: .cyan, radius: 20)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) {
                        glitchOffset = 3
                    }
                }

                Text("// CYBERPUNK NOTE BRAWL //")
                    .font(.custom("Audiowide-Regular", size: 13))
                    .foregroundColor(Color(red: 1, green: 0, blue: 1).opacity(0.8))
                    .tracking(6)
                    .padding(.top, 8)
                    .padding(.bottom, 52)

                // Player instructions
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
                .padding(.bottom, 52)

                // Start button
                Button {
                    gameManager.beginCalibration()
                } label: {
                    Text("INITIALIZE GAME")
                        .font(.custom("Audiowide-Regular", size: 15))
                        .tracking(4)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .overlay(
                            Rectangle().stroke(Color.cyan, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                Text("Camera access required")
                    .font(.custom("Audiowide-Regular", size: 11))
                    .foregroundColor(Color(red: 1, green: 0.55, blue: 0).opacity(0.8))
                    .tracking(2)
                    .padding(.top, 18)

                Spacer()
            }
        }
    }
}

struct PlayerInstructionCard: View {
    let player: Int
    let color: Color
    let side: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Text(player == 1 ? "◀ PLAYER \(player) — \(side)" : "PLAYER \(player) — \(side) ▶")
                .font(.custom("Audiowide-Regular", size: 12))
                .foregroundColor(color)
                .tracking(3)
            Text(description)
                .font(.custom("Audiowide-Regular", size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(width: 250)
    }
}

// MARK: - End Screen

struct EndScreen: View {
    @ObservedObject var gameManager: GameManager
    @State private var appeared = false

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
        ZStack {
            Color.black.ignoresSafeArea()
            CyberpunkGrid()

            VStack(spacing: 0) {
                Spacer()

                Text("GAME OVER")
                    .font(.custom("Audiowide-Regular", size: 52))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.3), radius: 20)
                    .padding(.bottom, 20)

                Text(winnerText)
                    .font(.custom("Audiowide-Regular", size: 38))
                    .foregroundColor(winnerColor)
                    .shadow(color: winnerColor, radius: 20)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
                    .padding(.bottom, 32)

                Text("P1: \(gameManager.scoreP1) PTS   |   P2: \(gameManager.scoreP2) PTS")
                    .font(.custom("Audiowide-Regular", size: 14))
                    .foregroundColor(.gray)
                    .tracking(3)
                    .padding(.bottom, 52)

                Button {
                    gameManager.beginCalibration()
                } label: {
                    Text("PLAY AGAIN")
                        .font(.custom("Audiowide-Regular", size: 15))
                        .tracking(4)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .overlay(Rectangle().stroke(Color.cyan, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)

                Button {
                    gameManager.resetToStart()
                } label: {
                    Text("MAIN MENU")
                        .font(.custom("Audiowide-Regular", size: 12))
                        .foregroundColor(.gray)
                        .tracking(3)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Calibration Screen

struct CalibrationView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject var tracker: CameraHandTracker

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
                        .font(.custom("Audiowide-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(4)
                        .padding(.top, 20)
                    Spacer()
                    Button { gameManager.resetToStart() } label: {
                        Text("CANCEL")
                            .font(.custom("Audiowide-Regular", size: 11))
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

    var body: some View {
        let confirmed = progress >= 1.0
        let cx: CGFloat = player == 1 ? size.width * 0.25 : size.width * 0.75

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 5)
                    .frame(width: 96, height: 96)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: progress)
                    .shadow(color: color.opacity(0.6), radius: confirmed ? 12 : 4)
                if confirmed {
                    Image(systemName: "checkmark")
                        .font(.custom("Audiowide-Regular", size: 32))
                        .foregroundColor(color)
                        .shadow(color: color, radius: 8)
                } else {
                    Text("✋")
                        .font(.custom("Audiowide-Regular", size: 32))
                        .opacity(progress > 0 ? 1 : 0.35)
                }
            }
            VStack(spacing: 4) {
                Text("PLAYER \(player)")
                    .font(.custom("Audiowide-Regular", size: 12))
                    .foregroundColor(color).tracking(4)
                Text(confirmed ? "LOCKED IN ✓" : "HOLD HAND NATURALLY")
                    .font(.custom("Audiowide-Regular", size: 10))
                    .foregroundColor(color.opacity(0.70)).tracking(2)
            }
        }
        .position(x: cx, y: size.height * 0.78)
    }
}

private struct CalibReadyOverlay: View {
    @State private var appeared = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("READY!")
                    .font(.custom("Audiowide-Regular", size: 72))
                    .foregroundColor(.white)
                    .shadow(color: .cyan, radius: 24)
                Text("STARTING GAME...")
                    .font(.custom("Audiowide-Regular", size: 13))
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

