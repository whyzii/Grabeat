import SwiftUI

// MARK: - Player Side

enum PlayerSide { case left, right, full }

// MARK: - Freeze Overlay
// Half-screen ice tint + scanline glitch shown when a player is frozen.

struct FreezeOverlay: View {
    let freeze: FreezeState
    let side:   PlayerSide
    let size:   CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let iceBlue = Color(red: 0.4, green: 0.85, blue: 1.0)
        let w = size.width / 2
        let h = size.height
        let x = side == .left ? w / 2 : size.width * 0.75

        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        iceBlue.opacity(0.22 + 0.06 * sin(freeze.glitchPhase * .pi * 2)),
                        Color(red: 0.7, green: 0.95, blue: 1.0).opacity(0.12)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: w, height: h)

            Canvas { ctx, sz in
                let lineCount = 18
                for i in 0..<lineCount {
                    let yFrac = Double(i) / Double(lineCount)
                    let yPos  = yFrac * sz.height
                    let shift = CGFloat(sin((freeze.glitchPhase + yFrac) * .pi * 4)) * 8
                    var p = Path()
                    p.move(to:    CGPoint(x: shift, y: yPos))
                    p.addLine(to: CGPoint(x: sz.width + shift, y: yPos))
                    let alpha = 0.06 + 0.04 * abs(sin((freeze.glitchPhase + yFrac) * .pi * 3))
                    ctx.stroke(p, with: .color(iceBlue.opacity(alpha)), lineWidth: 1.5)
                }
            }
            .frame(width: w, height: h)

            Rectangle()
                .stroke(iceBlue.opacity(0.55), lineWidth: 2)
                .frame(width: w - 2, height: h - 2)

            VStack(spacing: 4) {
                Text("❄ FROZEN ❄")
                    .font(.custom("Audiowide-Regular", size: 22 * scale))
                    .foregroundColor(iceBlue)
                    .shadow(color: iceBlue, radius: 16)
                    .tracking(3)
                    .scaleEffect(1.0 + 0.04 * sin(freeze.glitchPhase * .pi * 6))
                Text("\(Int(ceil(freeze.timeLeft)))s")
                    .font(.custom("Audiowide-Regular", size: 36 * scale))
                    .foregroundColor(.white)
                    .shadow(color: iceBlue, radius: 12)
            }
        }
        .position(x: x, y: h / 2)
        .allowsHitTesting(false)
    }
}
