import SwiftUI

// MARK: - Grid Ripple
// A single catch-triggered shockwave that expands across the animated grid.

struct GridRipple {
    let origin:    CGPoint   // normalised 0–1
    let color:     Color
    let startDate: Date = Date()
    static let duration: Double = 1.6

    func progress(at date: Date) -> Double {
        min(date.timeIntervalSince(startDate) / Self.duration, 1.0)
    }
    var isAlive: Bool { Date().timeIntervalSince(startDate) < Self.duration }
}

// MARK: - Animated Grid
// Gameplay grid with:
//   • Sine-wave vertex warp + perspective depth convergence
//   • Beat-synchronised brightness pulse (123 BPM)
//   • Hand proximity glow + electric-arc white flare
//   • Expanding catch shockwaves
//   • Junction dots at every intersection
//   • Data-stream packets travelling across each player zone

struct AnimatedGrid: View {
    let handPositions: [CGPoint]
    let ripples:       [GridRipple]
    @Environment(\.uiScale) private var scale

    // Static stream definitions — generated once at launch
    private struct DataStream {
        let yFrac: Double; let phase: Double; let speed: Double
        let isP1: Bool; let tailFrac: Double
    }

    private static let dataStreams: [DataStream] = {
        var rng = GlitchRNG(0xFEED4321)
        return (0..<22).map { _ in
            DataStream(yFrac:    rng.next(),
                       phase:    rng.next(),
                       speed:    0.050 + rng.next() * 0.090,
                       isP1:     rng.next() < 0.5,
                       tailFrac: 0.05  + rng.next() * 0.11)
        }
    }()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, date: tl.date)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Master Draw

    private func draw(ctx: GraphicsContext, size: CGSize, date: Date) {
        let step: CGFloat = 42 * scale
        let t    = date.timeIntervalSinceReferenceDate
        let cols = Int(size.width  / step) + 2
        let rows = Int(size.height / step) + 2

        let beatInterval = 60.0 / 123.046875
        let beatPhase    = t.truncatingRemainder(dividingBy: beatInterval) / beatInterval
        let beatPulse    = CGFloat(pow(max(0.0, 1.0 - beatPhase * 5.0), 2.0)) * 0.22

        let hpx = handPositions.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

        typealias Rip = (ox: CGFloat, oy: CGFloat, prog: Double, col: Color)
        let rips: [Rip] = ripples.compactMap {
            let p = $0.progress(at: date)
            guard p < 1 else { return nil }
            return ($0.origin.x * size.width, $0.origin.y * size.height, p, $0.color)
        }

        let n = rows * cols
        var vx = [CGFloat](repeating: 0, count: n)
        var vy = [CGFloat](repeating: 0, count: n)
        var vb = [Double](repeating: 0, count: n)

        // Build vertex positions + brightness
        for r in 0..<rows {
            for c in 0..<cols {
                let bx = CGFloat(c) * step - step
                let by = CGFloat(r) * step - step

                var px = bx + sin(CGFloat(r) * 0.28 + t * 1.10) * 6
                var py = by + cos(CGFloat(c) * 0.28 + t * 0.85) * 6

                let byNorm       = max(0.0, min(1.0, by / size.height))
                let perspCompress = (1.0 - byNorm) * 0.28
                px = size.width / 2 + (px - size.width / 2) * CGFloat(1.0 - perspCompress)

                var b = Double(0.055 + beatPulse)

                for h in hpx {
                    let dx = px - h.x, dy = py - h.y
                    let d  = sqrt(dx*dx + dy*dy)
                    if d < 160 { let f = 1 - d / 160; b += Double(f * f) * 0.42 }
                }

                for rip in rips {
                    let maxR = max(size.width, size.height)
                    let ring = CGFloat(rip.prog) * maxR
                    let dx   = px - rip.ox, dy = py - rip.oy
                    let d    = sqrt(dx*dx + dy*dy)
                    let gap  = abs(d - ring); let w: CGFloat = 38
                    if gap < w {
                        let f    = 1 - gap / w
                        let push = f * sin(.pi * f) * 15 * CGFloat(1 - rip.prog)
                        if d > 0 { px += dx / d * push; py += dy / d * push }
                        b += Double(f * (1 - rip.prog)) * 0.52
                    }
                }

                let i = r * cols + c
                vx[i] = px; vy[i] = py; vb[i] = min(b, 0.90)
            }
        }

        drawGridLines(ctx: ctx, size: size, cols: cols, rows: rows,
                      vx: vx, vy: vy, vb: vb, hpx: hpx)
        drawJunctionDots(ctx: ctx, size: size, cols: cols, rows: rows,
                         vx: vx, vy: vy, vb: vb, beatPulse: beatPulse)
        drawDataStreams(ctx: ctx, size: size, t: t, beatPulse: beatPulse)
    }

    // MARK: - Grid Lines + Electric Arc

    private func drawGridLines(ctx: GraphicsContext, size: CGSize, cols: Int, rows: Int,
                                vx: [CGFloat], vy: [CGFloat], vb: [Double],
                                hpx: [CGPoint]) {
        let arcR: CGFloat = 55
        for r in 0..<rows {
            for c in 0..<cols {
                let i  = r * cols + c
                let px = vx[i], py = vy[i], b = vb[i]

                if c + 1 < cols {
                    let j   = r * cols + (c + 1)
                    let qx  = vx[j], qy = vy[j]
                    let avg = (b + vb[j]) / 2
                    let mX  = (px + qx) / 2, mY = (py + qy) / 2
                    let col = mX < size.width / 2 ? Color.cyan : Color.magenta
                    var seg = Path()
                    seg.move(to: CGPoint(x: px, y: py)); seg.addLine(to: CGPoint(x: qx, y: qy))
                    ctx.stroke(seg, with: .color(col.opacity(avg)), lineWidth: 0.8)
                    for h in hpx {
                        let d = sqrt((mX-h.x)*(mX-h.x) + (mY-h.y)*(mY-h.y))
                        if d < arcR {
                            let f = CGFloat(1 - d / arcR)
                            ctx.stroke(seg, with: .color(.white.opacity(Double(f*f) * 0.90)), lineWidth: 2.0)
                        }
                    }
                }

                if r + 1 < rows {
                    let j   = (r + 1) * cols + c
                    let qx  = vx[j], qy = vy[j]
                    let avg = (b + vb[j]) / 2
                    let mX  = (px + qx) / 2, mY = (py + qy) / 2
                    let col = mX < size.width / 2 ? Color.cyan : Color.magenta
                    var seg = Path()
                    seg.move(to: CGPoint(x: px, y: py)); seg.addLine(to: CGPoint(x: qx, y: qy))
                    ctx.stroke(seg, with: .color(col.opacity(avg)), lineWidth: 0.8)
                    for h in hpx {
                        let d = sqrt((mX-h.x)*(mX-h.x) + (mY-h.y)*(mY-h.y))
                        if d < arcR {
                            let f = CGFloat(1 - d / arcR)
                            ctx.stroke(seg, with: .color(.white.opacity(Double(f*f) * 0.90)), lineWidth: 2.0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Junction Dots

    private func drawJunctionDots(ctx: GraphicsContext, size: CGSize, cols: Int, rows: Int,
                                   vx: [CGFloat], vy: [CGFloat], vb: [Double],
                                   beatPulse: CGFloat) {
        // Pass 1: batch all dim base dots
        var p1Dots = Path(), p2Dots = Path()
        for r in 0..<rows {
            for c in 0..<cols {
                let i  = r * cols + c
                let px = vx[i], py = vy[i]
                let dr: CGFloat = 1.2
                let rect = CGRect(x: px-dr, y: py-dr, width: dr*2, height: dr*2)
                if px < size.width / 2 { p1Dots.addEllipse(in: rect) }
                else                   { p2Dots.addEllipse(in: rect) }
            }
        }
        ctx.fill(p1Dots, with: .color(Color.cyan.opacity(0.08)))
        ctx.fill(p2Dots, with: .color(Color.magenta.opacity(0.08)))

        // Pass 2: individual bright dots for elevated vertices
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let b = vb[i]; guard b > 0.18 else { continue }
                let px = vx[i], py = vy[i]
                let col = px < size.width / 2 ? Color.cyan : Color.magenta
                let dr  = CGFloat(1.5 + (b - 0.18) * 5)
                ctx.fill(Path(ellipseIn: CGRect(x: px-dr, y: py-dr, width: dr*2, height: dr*2)),
                         with: .color(col.opacity(min(b * 2.0, 0.90))))
                if beatPulse > 0.05 {
                    let bl = dr + 4
                    ctx.fill(Path(ellipseIn: CGRect(x: px-bl, y: py-bl, width: bl*2, height: bl*2)),
                             with: .color(col.opacity(Double(beatPulse) * 0.28)))
                }
            }
        }
    }

    // MARK: - Data Streams

    private func drawDataStreams(ctx: GraphicsContext, size: CGSize, t: Double, beatPulse: CGFloat) {
        for stream in Self.dataStreams {
            let sy    = CGFloat(stream.yFrac) * size.height
            let prog  = CGFloat((t * stream.speed + stream.phase).truncatingRemainder(dividingBy: 1.0))
            let headX = prog * (size.width + 120) - 60
            let col   = stream.isP1
                        ? Color(red: 0, green: 0.95, blue: 1.0)
                        : Color(red: 1.0, green: 0.05, blue: 1.0)
            let tLen  = CGFloat(stream.tailFrac) * size.width
            let alpha = 0.48 + Double(beatPulse) * 0.32

            ctx.fill(Path(CGRect(x: headX - tLen,       y: sy-1,   width: tLen*0.45, height: 2)),
                     with: .color(col.opacity(alpha * 0.18)))
            ctx.fill(Path(CGRect(x: headX - tLen*0.55,  y: sy-1,   width: tLen*0.50, height: 2)),
                     with: .color(col.opacity(alpha * 0.52)))
            ctx.fill(Path(CGRect(x: headX - tLen*0.06,  y: sy-1.5, width: tLen*0.06, height: 3)),
                     with: .color(col.opacity(alpha)))
            ctx.fill(Path(ellipseIn: CGRect(x: headX-2.5, y: sy-2.5, width: 5, height: 5)),
                     with: .color(Color.white.opacity(alpha * 0.92)))
        }
    }
}
