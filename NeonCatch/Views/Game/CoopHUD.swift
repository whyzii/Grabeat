import SwiftUI

// MARK: - Co-op HUD
// Time-attack layout: countdown | groove meter | speed + combo

struct CoopHUD: View {
    @ObservedObject var coopManager: CoopGameManager
    var availableWidth: CGFloat
    var onPause: () -> Void = {}
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                timerBlock
                Spacer()
                grooveMeter
                Spacer()
                statusBlock
            }
            .frame(width: availableWidth - 40 * scale)   // account for horizontal padding
            .padding(.horizontal, 20 * scale)
            .padding(.vertical, 12 * scale)
            .background(.ultraThinMaterial.opacity(0.85))
        }
        .frame(width: availableWidth)
    }

    // MARK: - Timer

    private var timerBlock: some View {
        let t       = max(0, coopManager.timeLeft)
        let urgent  = t <= 5
        let warning = t <= 10
        let color: Color = urgent  ? .red
                         : warning ? Color(red: 1.0, green: 0.65, blue: 0.0)
                         : .white

        return VStack(spacing: 3) {
            Text(String(format: "%.1f", t))
                .font(.custom("Audiowide-Regular", size: 36 * scale))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.9), radius: urgent ? 20 : warning ? 12 : 6)
                .monospacedDigit()
            Text("SECONDS")
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.gray)
                .tracking(4)
            // Pause button — small and unobtrusive
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
        .frame(minWidth: 88 * scale)
    }

    // MARK: - Groove Meter (drives visual intensity — unchanged)

    private var grooveMeter: some View {
        let tier  = coopManager.groove.tier
        let level = coopManager.groove.level

        return VStack(spacing: 5) {
            Text(tier.label)
                .font(.custom("Audiowide-Regular", size: 11 * scale))
                .foregroundColor(tier.color)
                .shadow(color: tier.color, radius: tier == .ultra ? 10 : 4)
                .tracking(3)
                .scaleEffect(tier == .ultra ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: tier)

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 20 * scale)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: grooveGradient(tier: tier),
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: g.size.width * CGFloat(level / 100.0), height: 20 * scale)
                        .animation(.linear(duration: 0.15), value: level)

                    ForEach([15.0, 40.0, 68.0], id: \.self) { pct in
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1.5, height: 20 * scale)
                            .offset(x: g.size.width * CGFloat(pct / 100.0))
                    }
                }
            }
            .frame(width: 380 * scale, height: 20 * scale)

            Text("GROOVE METER")
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.gray.opacity(0.6))
                .tracking(4)
        }
    }

    private func grooveGradient(tier: GrooveTier) -> [Color] {
        switch tier {
        case .cold:  return [Color(red: 0.20, green: 0.35, blue: 0.80), .cyan]
        case .warm:  return [.cyan, Color(red: 0.0, green: 1.0, blue: 0.8)]
        case .hot:   return [.cyan, .yellow, Color(red: 1.0, green: 0.55, blue: 0.0)]
        case .ultra: return [.cyan, .yellow, Color(red: 1.0, green: 0.55, blue: 0.0), .white]
        }
    }

    // MARK: - Status Block (speed + combo + catches)

    private var statusBlock: some View {
        let spd = coopManager.speedLevel
        let spdColor: Color = spd >= 2.5 ? .red
                            : spd >= 1.8 ? Color(red: 1.0, green: 0.55, blue: 0.0)
                            : .cyan

        return VStack(alignment: .trailing, spacing: 4) {
            // Speed level — primary indicator of how intense the game is
            VStack(alignment: .trailing, spacing: 1) {
                Text("×\(String(format: "%.2f", spd))")
                    .font(.custom("Audiowide-Regular", size: 18 * scale))
                    .foregroundColor(spdColor)
                    .shadow(color: spdColor, radius: spd >= 2.0 ? 10 : 4)
                    .monospacedDigit()
                Text("SPEED")
                    .font(.custom("Audiowide-Regular", size: 9 * scale))
                    .foregroundColor(.gray)
                    .tracking(4)
            }

            if coopManager.speedBoostActive {
                Text("❄ SPEED UP!")
                    .font(.custom("Audiowide-Regular", size: 10 * scale))
                    .foregroundColor(Color(red: 0.4, green: 0.85, blue: 1.0))
                    .shadow(color: Color(red: 0.4, green: 0.85, blue: 1.0), radius: 6)
                    .tracking(1)
            }

            if coopManager.comboCount >= 5 {
                let col = comboColor(coopManager.comboCount)
                Text("×\(comboLabel(coopManager.comboMultiplier))  \(coopManager.comboCount) COMBO")
                    .font(.custom("Audiowide-Regular", size: 11 * scale))
                    .foregroundColor(col)
                    .shadow(color: col, radius: 5)
                    .tracking(1)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: coopManager.comboCount)
            }

            Text("♪ \(coopManager.totalCatches)")
                .font(.custom("Audiowide-Regular", size: 14 * scale))
                .foregroundColor(.cyan.opacity(0.7))
                .tracking(2)
            Text("CAUGHT")
                .font(.custom("Audiowide-Regular", size: 9 * scale))
                .foregroundColor(.gray)
                .tracking(4)
        }
        .frame(minWidth: 100 * scale)
    }

    private func comboColor(_ count: Int) -> Color {
        switch count {
        case ..<10:  return .cyan
        case ..<20:  return Color(red: 1.0, green: 0.55, blue: 0.0)
        default:     return .yellow
        }
    }

    private func comboLabel(_ mult: Double) -> String {
        mult == Double(Int(mult)) ? "\(Int(mult))" : String(format: "%.1f", mult)
    }
}

// MARK: - Coop Beat Indicator

struct CoopBeatIndicator: View {
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
