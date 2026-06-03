import SwiftUI

// MARK: - Hand Cursor
// Renders a cyberpunk-style targeting reticle that follows each tracked hand.
// Changes appearance based on pinch state and freeze status.

struct HandCursor: View {
    let hand:   HandState
    let color:  Color
    let size:   CGSize
    var frozen: Bool = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        if hand.isActive {
            let r: CGFloat = (hand.isPinching ? 46 : 62) * scale
            let displayColor: Color = frozen ? Color(red: 0.4, green: 0.85, blue: 1.0) : color

            ZStack {
                // Crosshair lines
                Group {
                    Rectangle().frame(width: 48 * scale, height: 1)
                    Rectangle().frame(width: 1, height: 48 * scale)
                }
                .foregroundColor(displayColor.opacity(0.55))

                // Outer ring
                Circle()
                    .stroke(displayColor, lineWidth: 2.5)
                    .frame(width: r, height: r)
                    .shadow(color: displayColor, radius: (hand.isPinching ? 16 : 8) * scale)

                // Fill on pinch
                if hand.isPinching {
                    Circle()
                        .fill(displayColor.opacity(0.3))
                        .frame(width: r, height: r)
                }

                // Inner indicator canvas
                Canvas { ctx, sz in
                    let cx = sz.width / 2, cy = sz.height / 2
                    let s  = sz.width * 0.26

                    if frozen {
                        drawIceCrystal(ctx: ctx, cx: cx, cy: cy, s: s)
                    } else if hand.isPinching {
                        drawFilledDiamond(ctx: ctx, cx: cx, cy: cy, s: s, color: displayColor)
                    } else {
                        drawHollowDiamond(ctx: ctx, cx: cx, cy: cy, s: s, color: displayColor)
                    }
                }
                .frame(width: 30 * scale, height: 30 * scale)
                .opacity(0.90)
            }
            .position(x: hand.position.x * size.width, y: hand.position.y * size.height)
            .animation(.spring(response: 0.08, dampingFraction: 0.7), value: hand.isPinching)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Canvas Helpers

    private func drawIceCrystal(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        let ice = Color(red: 0.4, green: 0.85, blue: 1.0)
        for k in 0..<4 {
            let a    = Double(k) * .pi / 4
            let ex   = cx + CGFloat(cos(a)) * s * 1.65
            let ey   = cy + CGFloat(sin(a)) * s * 1.65
            let perp = a + .pi / 2
            var p = Path()
            p.move(to:    CGPoint(x: cx + CGFloat(cos(a)) * 2, y: cy + CGFloat(sin(a)) * 2))
            p.addLine(to: CGPoint(x: ex, y: ey))
            p.move(to:    CGPoint(x: ex + CGFloat(cos(perp)) * 3, y: ey + CGFloat(sin(perp)) * 3))
            p.addLine(to: CGPoint(x: ex - CGFloat(cos(perp)) * 3, y: ey - CGFloat(sin(perp)) * 3))
            ctx.stroke(p, with: .color(ice.opacity(0.95)), lineWidth: 1.5)
        }
    }

    private func drawFilledDiamond(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                                   s: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - s)); path.addLine(to: CGPoint(x: cx + s, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy + s)); path.addLine(to: CGPoint(x: cx - s, y: cy))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.opacity(0.95)))
    }

    private func drawHollowDiamond(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                                   s: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - s)); path.addLine(to: CGPoint(x: cx + s, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy + s)); path.addLine(to: CGPoint(x: cx - s, y: cy))
        path.closeSubpath()
        ctx.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3)),
                 with: .color(color))
    }
}
