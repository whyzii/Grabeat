import SwiftUI

// MARK: - HUD Bar
// Top-of-screen overlay showing both player scores, timer, and active power-up countdowns.

struct HUDBar: View {
    @ObservedObject var gameManager: GameManager
    var availableWidth: CGFloat
    var onPause: () -> Void = {}
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            playerOneScore
                .frame(maxWidth: .infinity, alignment: .leading)
            timerDisplay
                .frame(minWidth: 100 * scale)
            playerTwoScore
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: availableWidth)
        .padding(.vertical, 14 * scale)
        .background(.ultraThinMaterial.opacity(0.85))
    }

    // MARK: - Player 1

    private var playerOneScore: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(gameManager.scoreP1)")
                    .font(.custom("Audiowide-Regular", size: 38 * scale))
                    .foregroundColor(gameManager.freezeP1.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .cyan)
                    .shadow(color: gameManager.freezeP1.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .cyan, radius: 12)
                if gameManager.freezeP1.active {
                    powerUpBadge("❄ \(Int(ceil(gameManager.freezeP1.timeLeft)))s",
                                 color: Color(red: 0.4, green: 0.85, blue: 1.0))
                }
                if gameManager.frenzyP1.active {
                    powerUpBadge("★ \(Int(ceil(gameManager.frenzyP1.timeLeft)))s", color: .yellow)
                }
            }
            Text("PLAYER 1")
                .font(.custom("Audiowide-Regular", size: 10 * scale))
                .foregroundColor(.cyan.opacity(0.7))
                .tracking(4)
        }
        .padding(.leading, 16 * scale)
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        VStack(spacing: 3) {
            Text("\(gameManager.timeLeft)")
                .font(.custom("Audiowide-Regular", size: 40 * scale))
                .foregroundColor(gameManager.timeLeft <= 10 ? .red : .white)
                .shadow(color: gameManager.timeLeft <= 10 ? .red : .white.opacity(0.4), radius: 14)
            Text("TIME")
                .font(.custom("Audiowide-Regular", size: 10 * scale))
                .foregroundColor(.gray)
                .tracking(4)
            // Pause button — small and centred under the timer
            Button(action: onPause) {
                HStack(spacing: 3 * scale) {
                    Text("⏸")
                        .font(.system(size: 10 * scale))
                    Text("PAUSE")
                        .font(.custom("Audiowide-Regular", size: 8 * scale))
                        .tracking(2)
                }
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 4 * scale)
                .background(Color.white.opacity(0.07))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Player 2

    private var playerTwoScore: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if gameManager.freezeP2.active {
                    powerUpBadge("❄ \(Int(ceil(gameManager.freezeP2.timeLeft)))s",
                                 color: Color(red: 0.4, green: 0.85, blue: 1.0))
                }
                if gameManager.frenzyP2.active {
                    powerUpBadge("★ \(Int(ceil(gameManager.frenzyP2.timeLeft)))s", color: .yellow)
                }
                Text("\(gameManager.scoreP2)")
                    .font(.custom("Audiowide-Regular", size: 38 * scale))
                    .foregroundColor(gameManager.freezeP2.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .magenta)
                    .shadow(color: gameManager.freezeP2.active ? Color(red: 0.4, green: 0.85, blue: 1.0) : .magenta, radius: 12)
            }
            Text("PLAYER 2")
                .font(.custom("Audiowide-Regular", size: 10 * scale))
                .foregroundColor(.magenta.opacity(0.7))
                .tracking(4)
        }
        .padding(.trailing, 16 * scale)
    }

    // MARK: - Shared Helper

    private func powerUpBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.custom("Audiowide-Regular", size: 13 * scale))
            .foregroundColor(color)
            .shadow(color: color, radius: 8)
    }
}

// MARK: - Beat Indicator
// Brief on-screen label that appears on each catch, showing beat timing quality.

struct BeatIndicator: View {
    let quality: BeatQuality
    @Environment(\.uiScale) private var scale

    var body: some View {
        Group {
            switch quality {
            case .perfect:
                Text("★ PERFECT BEAT ★")
                    .font(.custom("Audiowide-Regular", size: 14 * scale))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow, radius: 16)
                    .tracking(3)
            case .good:
                Text("♪ ON BEAT")
                    .font(.custom("Audiowide-Regular", size: 12 * scale))
                    .foregroundColor(.white.opacity(0.75))
                    .tracking(3)
            case .offBeat:
                EmptyView()
            }
        }
        .id(quality.label)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: quality.label)
    }
}

// MARK: - Pause Overlay
// Shown on top of gameplay when the game is paused.
// Offers two actions: Resume (continue playing) or Home (back to main menu).

struct PauseOverlay: View {
    let onResume: () -> Void
    let onHome:   () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 28 * scale) {
                VStack(spacing: 6 * scale) {
                    Text("⏸")
                        .font(.system(size: 32 * scale))
                    Text("PAUSED")
                        .font(.custom("Audiowide-Regular", size: 30 * scale))
                        .foregroundColor(.white)
                        .shadow(color: .cyan.opacity(0.8), radius: 14)
                        .tracking(8)
                }
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .cyan.opacity(0.4), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 200 * scale, height: 1)
                VStack(spacing: 14 * scale) {
                    pauseButton(label: "▶  RESUME",    color: .cyan,             action: onResume)
                    pauseButton(label: "⌂  MAIN MENU", color: Color(white: 0.65), action: onHome)
                }
            }
            .padding(.horizontal, 40 * scale)
            .padding(.vertical, 36 * scale)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.45), .white.opacity(0.10), .cyan.opacity(0.20)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
        }
    }

    private func pauseButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Audiowide-Regular", size: 16 * scale))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.7), radius: 6)
                .tracking(3)
                .frame(width: 200 * scale)
                .padding(.vertical, 12 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(color.opacity(0.40), lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Zone Labels
// Subtle bottom-of-screen labels showing which half belongs to which player.

struct ZoneLabels: View {
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack {
            Text("")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.cyan.opacity(0.4))
                .tracking(2)
                .padding(.leading, 16)
            Spacer()
            Text("")
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(.magenta.opacity(0.4))
                .tracking(2)
                .padding(.trailing, 16)
        }
        .padding(.bottom, 14)
    }
}
