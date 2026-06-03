import SwiftUI

// MARK: - Co-op End Screen

struct CoopEndScreen: View {
    @ObservedObject var gameManager:  GameManager
    @ObservedObject var coopManager:  CoopGameManager
    @ObservedObject var tracker:      CameraHandTracker
    @State private var appeared = false
    @Environment(\.uiScale) private var scale

    // Tier based on how long the team survived
    private var survivalTier: GrooveTier {
        switch coopManager.elapsed {
        case ..<20:  return .cold
        case ..<45:  return .warm
        case ..<75:  return .hot
        default:     return .ultra
        }
    }

    private var stars: Int {
        switch survivalTier {
        case .cold:  return 1
        case .warm:  return 2
        case .hot:   return 3
        case .ultra: return 4
        }
    }

    private var headline: String {
        switch survivalTier {
        case .cold:  return "JUST WARMING UP"
        case .warm:  return "SOLID TEAM!"
        case .hot:   return "HOT STREAK!"
        case .ultra: return "LEGENDARY RUN!"
        }
    }

    private var survivalTimeDisplay: String {
        let t = coopManager.elapsed
        if t >= 60 {
            let m = Int(t) / 60
            let s = Int(t) % 60
            return "\(m):\(String(format: "%02d", s))"
        }
        return String(format: "%.1f", t) + "s"
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // ── Background: same as home screen ──────────────────────────
                GlitchCircleBackground()

                // ── Results — centred inside the ring ────────────────────────
                VStack(spacing: 0) {
                    // Star rating
                    HStack(spacing: 6) {
                        ForEach(1...4, id: \.self) { i in
                            Text(i <= stars ? "★" : "☆")
                                .font(.custom("Audiowide-Regular", size: 28 * scale))
                                .foregroundColor(i <= stars ? survivalTier.color : .gray.opacity(0.35))
                                .shadow(color: i <= stars ? survivalTier.color : .clear, radius: 8)
                                .scaleEffect(appeared && i <= stars ? 1.0 : 0.5)
                                .opacity(appeared && i <= stars ? 1.0 : 0.3)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.55)
                                    .delay(appeared ? Double(i) * 0.12 : 0),
                                    value: appeared
                                )
                        }
                    }
                    .padding(.bottom, 10)

                    // Headline
                    Text(headline)
                        .font(.custom("Audiowide-Regular", size: 32 * scale))
                        .foregroundColor(survivalTier.color)
                        .shadow(color: survivalTier.color, radius: 16)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
                        .padding(.bottom, 6)

                    // Survival time — primary stat
                    Text(survivalTimeDisplay)
                        .font(.custom("Audiowide-Regular", size: 44 * scale))
                        .foregroundColor(.white)
                        .shadow(color: survivalTier.color, radius: 20)
                        .monospacedDigit()
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.1), value: appeared)

                    Text("SURVIVED")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.gray)
                        .tracking(5)
                        .padding(.bottom, 16)

                    // Stats row
                    HStack(spacing: 20) {
                        statBlock(label: "CAUGHT",     value: "\(coopManager.totalCatches)")
                        statBlock(label: "PERFECT",    value: "\(coopManager.perfectCatches)",  color: .yellow)
                        statBlock(label: "BEST COMBO", value: "×\(coopManager.peakCombo)",      color: .cyan)
                        statBlock(label: "PEAK SPEED", value: "×\(String(format: "%.2f", coopManager.peakSpeedLevel))",
                                  color: peakSpeedColor(coopManager.peakSpeedLevel))
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
                        label: "CONTINUE",
                        color: .white,
                        tracker: tracker, screenSize: geo.size,
                        action: { gameManager.state = gameManager.photoConsentGiven == false ? .start : .coopPhotoBooth }
                    )
                    Text("")
                        .font(.custom("Audiowide-Regular", size: 11 * scale))
                        .foregroundColor(.white)
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

    private func statBlock(label: String, value: String, color: Color = .white) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("Audiowide-Regular", size: 26 * scale))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.5), radius: 6)
                .monospacedDigit()
            Text(label)
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.gray)
                .tracking(2)
        }
    }

    private func peakSpeedColor(_ spd: Double) -> Color {
        spd >= 2.5 ? .red : spd >= 1.8 ? Color(red: 1.0, green: 0.55, blue: 0.0) : .cyan
    }
}
