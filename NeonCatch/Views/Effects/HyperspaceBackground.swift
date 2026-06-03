import SwiftUI

// MARK: - Glitch Circle Background
// Home screen animated background.
// Large neon ring with horizontal glitch bars (cyan left / magenta right),
// chromatic-aberration ghost rings, expanding wave pulses, and starfield.
// Everything drawn in a single Canvas — zero UIKit, no .blur().

struct GlitchCircleBackground: View {

    // MARK: Seeded data

    private struct StarSeed {
        let x, y, size, brightness, twinklePhase: Double
    }

    // Each bar is a horizontal rectangle at a fixed vertical position on the ring.
    // leftLen / rightLen are multiples of R; 0 means that side is absent.
    private struct BarSeed {
        let yFrac:    Double   // −0.88 … 0.88 (fraction of R from centre)
        let leftLen:  Double   // how far left of ring edge to extend (× R)
        let rightLen: Double   // how far right of ring edge to extend (× R)
        let inward:   Double   // how far the bar reaches INSIDE the ring (× R)
        let height:   Double   // bar thickness in pixels
        let interval: Double   // flicker cycle length (seconds)
        let phase:    Double   // time offset 0–1
    }

    private static let stars: [StarSeed] = {
        var rng = GlitchRNG(0xDEAD_BEEF)
        return (0..<220).map { _ in
            StarSeed(x:            rng.next(),
                     y:            rng.next(),
                     size:         rng.next() * 1.6 + 0.3,
                     brightness:   rng.next() * 0.40 + 0.08,
                     twinklePhase: rng.next() * .pi * 2)
        }
    }()

    private static let bars: [BarSeed] = {
        var rng = GlitchRNG(0xCAFE_BABE)
        return (0..<34).map { i in
            let yFrac   = (rng.next() - 0.5) * 1.76
            let hasLeft  = i % 3 != 2
            let hasRight = i % 3 != 0
            // Wide spread: tiny (0.04) up to very long (2.8) — skewed so most are short
            func randLen() -> Double {
                let v = rng.next()
                // 50% short, 30% medium, 20% long
                if v < 0.50 { return rng.next() * 0.28 + 0.04 }   // 0.04–0.32
                if v < 0.80 { return rng.next() * 0.55 + 0.32 }   // 0.32–0.87
                return rng.next() * 1.90 + 0.90                     // 0.90–2.80
            }
            return BarSeed(
                yFrac:    yFrac,
                leftLen:  hasLeft  ? randLen() : 0,
                rightLen: hasRight ? randLen() : 0,
                inward:   rng.next() * 0.14 + 0.03,
                height:   rng.next() * 8 + 3,
                interval: rng.next() * 0.55 + 0.18,
                phase:    rng.next()
            )
        }
    }()

    private let cyan    = Color(red: 0.00, green: 0.92, blue: 1.00)
    private let magenta = Color(red: 1.00, green: 0.08, blue: 0.80)

    // MARK: Body

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = sz.width  / 2
                let cy = sz.height / 2
                // Large ring — 36 % of shorter dimension, gentle breath
                let R  = min(sz.width, sz.height) * 0.36
                       * CGFloat(1.0 + 0.018 * sin(t * 1.1))

                drawStarfield (ctx: ctx, sz: sz, t: t)
                drawWaveRings (ctx: ctx, cx: cx, cy: cy, R: R, t: t)
                drawGlitchRing(ctx: ctx, cx: cx, cy: cy, R: R, t: t)
                drawCenterFill(ctx: ctx, cx: cx, cy: cy, R: R, t: t)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 1 – Starfield

    private func drawStarfield(ctx: GraphicsContext, sz: CGSize, t: Double) {
        for s in Self.stars {
            let twinkle = 0.5 + 0.5 * sin(t * 1.35 + s.twinklePhase)
            let a = s.brightness * (0.55 + 0.45 * twinkle)
            let r = CGFloat(s.size)
            ctx.fill(
                Path(ellipseIn: CGRect(x: CGFloat(s.x) * sz.width  - r,
                                       y: CGFloat(s.y) * sz.height - r,
                                       width: r * 2, height: r * 2)),
                with: .color(.white.opacity(a))
            )
        }
    }

    // MARK: 2 – Wave Rings

    private func drawWaveRings(ctx: GraphicsContext,
                                cx: CGFloat, cy: CGFloat, R: CGFloat, t: Double) {
        let period  = 2.6                          // faster pulses
        let maxDist = max(cx, cy) * 1.45
        for i in 0..<5 {
            let prog  = ((t / period) + Double(i) / 5.0).truncatingRemainder(dividingBy: 1.0)
            let wr    = R + CGFloat(prog * prog) * maxDist
            let alpha = (1.0 - prog) * 0.65
            guard alpha > 0.01 else { continue }
            let col: Color = i.isMultiple(of: 2) ? cyan : magenta
            let rect = CGRect(x: cx - wr, y: cy - wr, width: wr * 2, height: wr * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.05)), lineWidth: 30)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.18)), lineWidth: 10)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.55)), lineWidth: 3)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.90)), lineWidth: 0.8)
        }
    }

    // MARK: 3 – Glitch Ring

    private func drawGlitchRing(ctx: GraphicsContext,
                                 cx: CGFloat, cy: CGFloat, R: CGFloat, t: Double) {

        // Chromatic aberration offset
        let chrX = CGFloat(9 + 5 * sin(t * 0.55))
        let chrY = CGFloat(4 + 2 * cos(t * 0.48))

        // ── Outer soft halo ──────────────────────────────────────────────────
        let hR = R * 1.38
        ctx.stroke(Path(ellipseIn: CGRect(x: cx-hR, y: cy-hR, width: hR*2, height: hR*2)),
                   with: .color(.white.opacity(0.04)), lineWidth: 70)

        // ── Bloom — wide diffuse glow (full ellipses keep the shape readable) ─
        let rr = CGRect(x: cx-R, y: cy-R, width: R*2, height: R*2)
        ctx.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(0.07)), lineWidth: 55)
        ctx.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(0.15)), lineWidth: 30)
        ctx.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(0.28)), lineWidth: 14)
        ctx.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(0.50)), lineWidth: 5)

        // ── Glitch displacement — full rings that randomly snap/jump ─────────
        // Seed updates ~10× per second; ~18% of slots trigger a glitch jump
        let tSlot = UInt64(abs(t * 10.0)) & 0x7FF
        var rng   = GlitchRNG(tSlot ^ 0xDEAD_CAFE)
        let glitching = rng.next() < 0.18
        let gx  = glitching ? CGFloat((rng.next() - 0.5) * 28) : CGFloat(sin(t * 2.3) * 1.5)
        let gy  = glitching ? CGFloat((rng.next() - 0.5) * 14) : CGFloat(cos(t * 1.9) * 1.0)
        let gOp = glitching ? rng.next() * 0.35 + 0.55 : 1.0

        // ── Magenta ghost (right + down, glitch-shifted) ──────────────────────
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx + chrX + gx*0.55 - R,
                                    y: cy + chrY + gy*0.35 - R, width: R*2, height: R*2)),
            with: .color(magenta.opacity(0.78 * gOp)), lineWidth: 8
        )
        // ── Cyan ghost (left + up, glitch-shifted) ────────────────────────────
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx - chrX - gx*0.55 - R,
                                    y: cy - chrY - gy*0.35 - R, width: R*2, height: R*2)),
            with: .color(cyan.opacity(0.78 * gOp)), lineWidth: 8
        )
        // ── Main white ring ───────────────────────────────────────────────────
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx + gx*0.25 - R,
                                    y: cy + gy*0.18 - R, width: R*2, height: R*2)),
            with: .color(.white.opacity(0.58 * gOp)), lineWidth: 7
        )

        // ── Horizontal glitch bars ───────────────────────────────────────────
        // Every ~4 s a "super-glitch" fires all bars simultaneously
        let gbRaw      = t.truncatingRemainder(dividingBy: 4.2)
        let globalFrac = gbRaw < 0.18 ? CGFloat(gbRaw / 0.18) : 0

        for bar in Self.bars {
            let lt = (t / bar.interval + bar.phase).truncatingRemainder(dividingBy: 1.0)
            let frac: Double
            if      lt < 0.08 { frac = lt / 0.08 }        // fast attack
            else if lt < 0.22 { frac = 1.0 }               // hold
            else if lt < 0.30 { frac = 1.0-(lt-0.22)/0.08 }// fast decay
            else              { frac = 0 }

            let tf = CGFloat(max(frac, Double(globalFrac) * 0.75))
            guard tf > 0.02 else { continue }

            // Vertical position and x intersection with ring
            let yN = CGFloat(bar.yFrac)
            guard abs(yN) < 0.99 else { continue }
            let xRing = CGFloat(sqrt(1.0 - Double(yN * yN))) * R
            let y     = cy + yN * R
            let h     = CGFloat(bar.height) * tf
            let alpha = Double(tf)

            // ── Left bar (cyan-dominant) ─────────────────────────────────────
            if bar.leftLen > 0 {
                let xRight = cx - xRing + CGFloat(bar.inward)  * R  // right edge (bites into ring)
                let xLeft  = cx - xRing - CGFloat(bar.leftLen) * R  // left edge
                guard xRight > xLeft else { continue }
                let w = xRight - xLeft
                // Cyan ghost — shifted left
                ctx.fill(Path(CGRect(x: xLeft - chrX, y: y - h/2, width: w, height: h)),
                         with: .color(cyan.opacity(alpha * 0.95)))
                // Magenta ghost — shifted right, smaller
                ctx.fill(Path(CGRect(x: xLeft + chrX*0.4, y: y - h/2 + 1, width: w*0.65, height: h*0.55)),
                         with: .color(magenta.opacity(alpha * 0.45)))
                // White core
                ctx.fill(Path(CGRect(x: xLeft, y: y - h/2, width: w, height: h)),
                         with: .color(.white.opacity(alpha * 0.60)))
            }

            // ── Right bar (magenta-dominant) ─────────────────────────────────
            if bar.rightLen > 0 {
                let xLeft  = cx + xRing - CGFloat(bar.inward)  * R  // left edge (bites into ring)
                let xRight = cx + xRing + CGFloat(bar.rightLen) * R  // right edge
                guard xRight > xLeft else { continue }
                let w = xRight - xLeft
                // Magenta ghost — shifted right
                ctx.fill(Path(CGRect(x: xLeft + chrX, y: y - h/2, width: w, height: h)),
                         with: .color(magenta.opacity(alpha * 0.95)))
                // Cyan ghost — shifted left, smaller
                ctx.fill(Path(CGRect(x: xLeft - chrX*0.4, y: y - h/2 + 1, width: w*0.65, height: h*0.55)),
                         with: .color(cyan.opacity(alpha * 0.45)))
                // White core
                ctx.fill(Path(CGRect(x: xLeft, y: y - h/2, width: w, height: h)),
                         with: .color(.white.opacity(alpha * 0.60)))
            }
        }
    }

    // MARK: 4 – Center Fill

    private func drawCenterFill(ctx: GraphicsContext,
                                 cx: CGFloat, cy: CGFloat, R: CGFloat, t: Double) {
        // Black disc keeps the ring hollow
        let ir = R * 0.83
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx-ir, y: cy-ir, width: ir*2, height: ir*2)),
            with: .color(.black.opacity(0.93))
        )
        // Faint ambient inner glow
        let pulse = CGFloat(0.5 + 0.5 * sin(t * 1.0))
        let gr    = R * 0.70
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx-gr, y: cy-gr, width: gr*2, height: gr*2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: cyan.opacity(   0.06 + 0.05 * Double(pulse)), location: 0.00),
                    .init(color: magenta.opacity(0.04 + 0.03 * Double(pulse)), location: 0.55),
                    .init(color: .clear,                                        location: 1.00),
                ]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: gr
            )
        )
    }
}

// MARK: - Tutorial Background
// Glitching horizontal lines of various sizes + starfield.
// Used in TutorialView and CoopTutorialView.

struct TutorialBackground: View {

    private let cyan    = Color(red: 0.00, green: 0.92, blue: 1.00)
    private let magenta = Color(red: 1.00, green: 0.08, blue: 0.80)

    // ── Star data ────────────────────────────────────────────────────────────
    private struct TStar {
        let x, y, size, brightness, twinklePhase: Double
    }

    private static let stars: [TStar] = {
        var rng = GlitchRNG(0xFACE_F00D)
        return (0..<200).map { _ in
            TStar(x:            rng.next(),
                  y:            rng.next(),
                  size:         rng.next() * 1.5 + 0.3,
                  brightness:   rng.next() * 0.35 + 0.07,
                  twinklePhase: rng.next() * .pi * 2)
        }
    }()

    // ── Line seed data ───────────────────────────────────────────────────────
    // xCenter / yFrac: normalised position
    // length: fraction of screen width
    // thickness: pixels
    // colorIdx: 0=cyan 1=magenta 2=white
    // interval / phase: individual flicker cycle
    // glitchAmp: max horizontal snap distance (fraction of width)
    private struct TLine {
        let xCenter:   Double
        let yFrac:     Double
        let length:    Double
        let thickness: Double
        let colorIdx:  Int
        let interval:  Double
        let phase:     Double
        let glitchAmp: Double
    }

    private static let lines: [TLine] = {
        var rng = GlitchRNG(0xC0DE_CAFE)
        return (0..<32).map { i in
            // Length distribution: 40% short, 35% medium, 25% long
            let lv = rng.next()
            let length: Double
            if      lv < 0.40 { length = rng.next() * 0.12 + 0.03 }   // 0.03–0.15
            else if lv < 0.75 { length = rng.next() * 0.25 + 0.15 }   // 0.15–0.40
            else               { length = rng.next() * 0.55 + 0.40 }   // 0.40–0.95

            // Thickness: mostly thin, few thick
            let tv = rng.next()
            let thickness: Double
            if      tv < 0.55 { thickness = rng.next() * 1.0 + 0.5 }  // 0.5–1.5 px
            else if tv < 0.85 { thickness = rng.next() * 2.0 + 2.0 }  // 2–4 px
            else               { thickness = rng.next() * 5.0 + 5.0 } // 5–10 px

            // Keep lines in top/bottom bands — leave the centre free for text
            let yFrac: Double
            if rng.next() < 0.5 {
                yFrac = rng.next() * 0.20          // top 20 %
            } else {
                yFrac = 0.80 + rng.next() * 0.20   // bottom 20 %
            }

            return TLine(
                xCenter:   rng.next(),
                yFrac:     yFrac,
                length:    length,
                thickness: thickness,
                colorIdx:  i % 3,
                interval:  rng.next() * 1.8 + 0.4,
                phase:     rng.next(),
                glitchAmp: rng.next() * 0.18 + 0.02
            )
        }
    }()

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                drawStarfield  (ctx: ctx, sz: sz, t: t)
                drawGlitchLines(ctx: ctx, sz: sz, t: t)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // ── Starfield ─────────────────────────────────────────────────────────────

    private func drawStarfield(ctx: GraphicsContext, sz: CGSize, t: Double) {
        for s in Self.stars {
            let twinkle = 0.5 + 0.5 * sin(t * 1.35 + s.twinklePhase)
            let a = s.brightness * (0.55 + 0.45 * twinkle)
            let r = CGFloat(s.size)
            ctx.fill(
                Path(ellipseIn: CGRect(x: CGFloat(s.x) * sz.width  - r,
                                       y: CGFloat(s.y) * sz.height - r,
                                       width: r * 2, height: r * 2)),
                with: .color(.white.opacity(a))
            )
        }
    }

    // ── Glitch Lines ──────────────────────────────────────────────────────────

    private func drawGlitchLines(ctx: GraphicsContext, sz: CGSize, t: Double) {
        // Global glitch: ~10% of slots (~8/s) shift ALL lines simultaneously
        let tSlot     = UInt64(abs(t * 8.0)) & 0x7FF
        var gRng      = GlitchRNG(tSlot ^ 0xDEAD_7777)
        let globalHit = gRng.next() < 0.10
        let globalDx  = globalHit ? CGFloat((gRng.next() - 0.5) * sz.width * 0.12) : 0

        let chrOff = CGFloat(7 + 4 * sin(t * 0.7))   // chromatic aberration spread

        for line in Self.lines {
            // Per-line flicker
            let lt   = (t / line.interval + line.phase).truncatingRemainder(dividingBy: 1.0)
            // Envelope: fast spike, slow decay
            let env: Double
            if      lt < 0.06 { env = lt / 0.06 }
            else if lt < 0.20 { env = 1.0 }
            else if lt < 0.32 { env = 1.0 - (lt - 0.20) / 0.12 }
            else               { env = 0.08 }   // dim baseline — lines always faintly visible

            // Per-line glitch: occasional horizontal snap
            var lRng    = GlitchRNG(tSlot ^ UInt64(line.phase * 9999) ^ 0xABCD_1234)
            let lineHit = lRng.next() < 0.14
            let lineDx  = lineHit ? CGFloat((lRng.next() - 0.5) * sz.width * line.glitchAmp) : 0

            let dx    = globalDx + lineDx
            let cx    = CGFloat(line.xCenter) * sz.width + dx
            let y     = CGFloat(line.yFrac)   * sz.height
            let hw    = CGFloat(line.length)  * sz.width * 0.5
            let h     = CGFloat(line.thickness)
            let alpha = env

            let color: Color
            switch line.colorIdx {
            case 0:  color = cyan
            case 1:  color = magenta
            default: color = .white
            }

            // Bloom glow behind the line
            ctx.fill(Path(CGRect(x: cx - hw, y: y - h * 3, width: hw * 2, height: h * 6)),
                     with: .color(color.opacity(alpha * 0.05)))

            // Chromatic split: cyan ghost left, magenta ghost right
            ctx.fill(Path(CGRect(x: cx - hw - chrOff, y: y - h / 2, width: hw * 2, height: h)),
                     with: .color(cyan.opacity(alpha * 0.18)))
            ctx.fill(Path(CGRect(x: cx - hw + chrOff, y: y - h / 2, width: hw * 2, height: h)),
                     with: .color(magenta.opacity(alpha * 0.18)))

            // Core white/colour line
            ctx.fill(Path(CGRect(x: cx - hw, y: y - h / 2, width: hw * 2, height: h)),
                     with: .color(color.opacity(alpha * 0.40)))
        }
    }
}

// MARK: - Hyperspace Background
// Full-screen animated cyberpunk/matrix background used on the Start screen.
// Renders 8 layered effects: tunnel grid, pulse rings, debris blocks,
// speed rays, matrix rain, glitch bars, central glow, and CRT scanlines.

// MARK: - Internal Data Structures

private struct HypRay {
    let angle: Double; let phase: Double; let speed: Double
    let colorIdx: Int; let width: CGFloat; let trailLen: Double; let bright: Double
}

private struct HypBlock {
    let angle: Double; let phase: Double; let speed: Double
    let bw: CGFloat; let bh: CGFloat; let colorIdx: Int; let kind: Int
}

private struct MatrixCol {
    let xFrac: Double; let phase: Double; let speed: Double
    let chars: [Int]; let isCyan: Bool; let ch: CGFloat
}

private struct SeededRNG {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed == 0 ? 1 : seed }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s >> 11) / 9007199254740992.0
    }
}

// MARK: - View

struct HyperspaceBackground: View {

    private static let mChars = Array("01234567890ABCDEF!?#@<>[]{}|/^~")

    private static let rays: [HypRay] = {
        var r = SeededRNG(7373)
        return (0..<145).map { _ in
            let c = r.next()
            return HypRay(angle: r.next() * .pi * 2, phase: r.next(),
                          speed: 0.24 + r.next() * 0.68,
                          colorIdx: c < 0.36 ? 0 : (c < 0.72 ? 1 : 2),
                          width: CGFloat(0.8 + r.next() * 2.5),
                          trailLen: 0.05 + r.next() * 0.22,
                          bright: 0.48 + r.next() * 0.52)
        }
    }()

    private static let blocks: [HypBlock] = {
        var r = SeededRNG(1337)
        return (0..<58).map { _ in
            HypBlock(angle: r.next() * .pi * 2, phase: r.next(),
                     speed: 0.11 + r.next() * 0.33,
                     bw: CGFloat(4 + r.next() * 28), bh: CGFloat(1.5 + r.next() * 11),
                     colorIdx: r.next() < 0.5 ? 0 : 1,
                     kind: Int(r.next() * 2.99))
        }
    }()

    private static let matrixCols: [MatrixCol] = {
        var r = SeededRNG(9999)
        return (0..<22).map { _ in
            MatrixCol(xFrac: r.next(), phase: r.next(),
                      speed: 0.16 + r.next() * 0.26,
                      chars: (0..<16).map { _ in Int(r.next() * Double(mChars.count - 1)) },
                      isCyan: r.next() < 0.55,
                      ch: CGFloat(10 + r.next() * 4))
        }
    }()

    private let palette: [Color] = [
        Color(red: 0.0,  green: 0.88, blue: 1.0),
        Color(red: 1.0,  green: 0.05, blue: 0.78),
        Color(red: 0.60, green: 0.10, blue: 1.0),
        Color(red: 0.10, green: 1.0,  blue: 0.45),
    ]

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Master Draw

    private func draw(ctx: GraphicsContext, size: CGSize, t: Double) {
        let vx   = size.width  * 0.500
        let vy   = size.height * 0.468
        let maxR = max(hypot(vx, vy),
                       hypot(size.width - vx, vy),
                       hypot(vx, size.height - vy),
                       hypot(size.width - vx, size.height - vy)) * 1.10

        drawTunnelGrid (ctx: ctx, size: size, vx: vx, vy: vy, maxR: maxR)
        drawPulseRings (ctx: ctx, size: size, vx: vx, vy: vy, maxR: maxR, t: t)
        drawBlocks     (ctx: ctx, size: size, vx: vx, vy: vy, maxR: maxR, t: t)
        drawRays       (ctx: ctx, size: size, vx: vx, vy: vy, maxR: maxR, t: t)
        drawMatrixRain (ctx: ctx, size: size, t: t)
        drawGlitchBars (ctx: ctx, size: size, t: t)
        drawCentralGlow(ctx: ctx, vx: vx, vy: vy, maxR: maxR, t: t)
        drawScanlines  (ctx: ctx, size: size)
    }

    // MARK: - 1. Tunnel Grid

    private func drawTunnelGrid(ctx: GraphicsContext, size: CGSize,
                                 vx: CGFloat, vy: CGFloat, maxR: CGFloat) {
        for i in 0..<24 {
            let a = Double(i) / 24.0 * .pi * 2
            var p = Path()
            p.move(to: CGPoint(x: vx, y: vy))
            p.addLine(to: CGPoint(x: vx + CGFloat(cos(a)) * maxR, y: vy + CGFloat(sin(a)) * maxR))
            ctx.stroke(p, with: .color(Color(red: 0.40, green: 0.0, blue: 0.60).opacity(0.07)), lineWidth: 0.55)
        }
        for i in 1...8 {
            let f = Double(i) / 9.0
            let r = CGFloat(f) * maxR * 0.88
            ctx.stroke(
                Path(ellipseIn: CGRect(x: vx-r, y: vy-r*0.76, width: r*2, height: r*1.52)),
                with: .color(Color(red: 0.45, green: 0.0, blue: 0.75).opacity((1.0-f) * 0.09)),
                lineWidth: 0.65
            )
        }
    }

    // MARK: - 2. Pulse Rings

    private func drawPulseRings(ctx: GraphicsContext, size: CGSize,
                                 vx: CGFloat, vy: CGFloat, maxR: CGFloat, t: Double) {
        let period = 2.8
        for i in 0..<6 {
            let prog  = ((t / period) + Double(i) / 6.0).truncatingRemainder(dividingBy: 1.0)
            let eased = CGFloat(prog * prog)
            let r     = eased * maxR
            let alpha = (1.0 - prog) * 0.55
            guard alpha > 0.02 else { continue }
            let col  = palette[i % 3]
            let rect = CGRect(x: vx-r, y: vy-r, width: r*2, height: r*2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.07)), lineWidth: 28)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.18)), lineWidth: 11)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.48)), lineWidth: 3.5)
            ctx.stroke(Path(ellipseIn: rect), with: .color(col.opacity(alpha * 0.90)), lineWidth: 0.9)
        }
    }

    // MARK: - 3. Debris Blocks

    private func drawBlocks(ctx: GraphicsContext, size: CGSize,
                             vx: CGFloat, vy: CGFloat, maxR: CGFloat, t: Double) {
        for b in Self.blocks {
            let prog = (t * b.speed + b.phase).truncatingRemainder(dividingBy: 1.0)
            let e    = prog * prog
            let dist = e * maxR
            guard dist > 6 else { continue }
            let bx = vx + CGFloat(cos(b.angle)) * dist
            let by = vy + CGFloat(sin(b.angle)) * dist
            guard bx > -90 && bx < size.width+90 && by > -90 && by < size.height+90 else { continue }
            let alpha = min(prog * 6, 1.0) * max(0.0, 1.0 - prog * 1.12) * 0.52
            guard alpha > 0.01 else { continue }
            let bw = b.bw * CGFloat(0.10 + e * 0.90)
            let bh = b.bh * CGFloat(0.08 + e * 0.92)
            let ca = CGFloat(cos(b.angle)), sa = CGFloat(sin(b.angle))
            func corner(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
                CGPoint(x: bx + ca*dx - sa*dy, y: by + sa*dx + ca*dy)
            }
            var rp = Path()
            rp.move(to: corner(-bw/2,-bh/2)); rp.addLine(to: corner(bw/2,-bh/2))
            rp.addLine(to: corner(bw/2,bh/2)); rp.addLine(to: corner(-bw/2,bh/2))
            rp.closeSubpath()
            let ec = palette[b.colorIdx]
            switch b.kind {
            case 1:
                ctx.fill  (rp, with: .color(Color(red: 0.04, green: 0.04, blue: 0.24).opacity(min(alpha*2.5, 0.88))))
                ctx.stroke(rp, with: .color(ec.opacity(alpha * 0.35)), lineWidth: 2.5)
                ctx.stroke(rp, with: .color(ec.opacity(alpha)),         lineWidth: 0.7)
            case 2:
                ctx.stroke(rp, with: .color(ec.opacity(alpha * 0.50)), lineWidth: 0.5)
            default:
                ctx.fill  (rp, with: .color(Color(red: 0.03, green: 0.03, blue: 0.20).opacity(min(alpha*3.0, 0.82))))
                ctx.stroke(rp, with: .color(ec.opacity(alpha * 0.60)), lineWidth: 0.6)
            }
        }
    }

    // MARK: - 4. Speed Rays

    private func drawRays(ctx: GraphicsContext, size: CGSize,
                           vx: CGFloat, vy: CGFloat, maxR: CGFloat, t: Double) {
        for ray in Self.rays {
            let prog  = (t * ray.speed + ray.phase).truncatingRemainder(dividingBy: 1.0)
            let tipP  = prog * prog
            let tailR = max(0.0, prog - ray.trailLen)
            let tailP = tailR * tailR
            let tipD  = tipP  * maxR
            let tailD = tailP * maxR
            guard tipD > tailD + 5 else { continue }

            let dx = CGFloat(cos(ray.angle)), dy = CGFloat(sin(ray.angle))
            let tx = vx + dx * tipD,  ty = vy + dy * tipD
            let fx = vx + dx * tailD, fy = vy + dy * tailD
            let onS = (tx > -55 && tx < size.width+55 && ty > -55 && ty < size.height+55)
                   || (fx > -55 && fx < size.width+55 && fy > -55 && fy < size.height+55)
            guard onS else { continue }

            let col   = palette[ray.colorIdx]
            let alpha = prog * ray.bright
            let lw    = ray.width * CGFloat(0.28 + prog * 0.72)

            var p = Path()
            p.move(to: CGPoint(x: fx, y: fy)); p.addLine(to: CGPoint(x: tx, y: ty))

            let chr: CGFloat = 1.9
            var pCyan = Path()
            pCyan.move(to: CGPoint(x: fx - chr, y: fy)); pCyan.addLine(to: CGPoint(x: tx - chr, y: ty))
            var pMag  = Path()
            pMag .move(to: CGPoint(x: fx + chr, y: fy)); pMag .addLine(to: CGPoint(x: tx + chr, y: ty))
            ctx.stroke(pCyan, with: .color(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(alpha * 0.30)), lineWidth: lw * 0.80)
            ctx.stroke(pMag,  with: .color(Color(red: 1.0, green: 0.10, blue: 0.55).opacity(alpha * 0.30)), lineWidth: lw * 0.80)

            ctx.stroke(p, with: .color(col.opacity(alpha * 0.14)), lineWidth: lw * 6.0)
            ctx.stroke(p, with: .color(col.opacity(alpha * 0.35)), lineWidth: lw * 2.4)
            ctx.stroke(p, with: .color(col.opacity(alpha * 0.75)), lineWidth: lw * 1.1)
            ctx.stroke(p, with: .color(col.opacity(alpha)),         lineWidth: lw * 0.55)

            if ray.bright > 0.75 {
                let back = min(18 as CGFloat, tipD - tailD - 2)
                var tip = Path()
                tip.move(to: CGPoint(x: tx - dx*back, y: ty - dy*back))
                tip.addLine(to: CGPoint(x: tx, y: ty))
                ctx.stroke(tip, with: .color(.white.opacity(alpha * 0.60)), lineWidth: lw * 0.45)
            }

            let gltT = (t * 6.1 + ray.phase * 19.3).truncatingRemainder(dividingBy: 1.0)
            if gltT < 0.030 {
                let gFrac = CGFloat(gltT / 0.030)
                let gFade = gFrac < 0.5 ? gFrac * 2 : 2 - gFrac * 2
                let shift = gFade * 15
                var gp = Path()
                gp.move(to:    CGPoint(x: fx + shift, y: fy - shift * 0.22))
                gp.addLine(to: CGPoint(x: tx + shift, y: ty - shift * 0.22))
                ctx.stroke(gp, with: .color(col.opacity(alpha * Double(gFade) * 0.90)), lineWidth: lw * 1.2)
            }
        }
    }

    // MARK: - 5. Matrix Rain

    private func drawMatrixRain(ctx: GraphicsContext, size: CGSize, t: Double) {
        let vis    = 7
        let nChars = Double(Self.mChars.count)
        for col in Self.matrixCols {
            let x      = CGFloat(col.xFrac) * size.width
            let stride = col.ch * 1.20
            let cycleH = size.height * 1.35 + CGFloat(vis) * stride
            let frac   = CGFloat((t * col.speed + col.phase).truncatingRemainder(dividingBy: 1.35))
            let headY  = frac * cycleH - CGFloat(vis) * stride
            let base   = col.isCyan
                ? Color(red: 0.0, green: 0.88, blue: 0.95)
                : Color(red: 0.10, green: 1.0, blue: 0.45)
            for j in 0..<vis {
                let cy = headY + CGFloat(j) * stride
                guard cy > -col.ch * 2 && cy < size.height + col.ch else { continue }
                let isHead = j == 0
                let fadeA  = isHead ? 0.92 : max(0, (1.0 - Double(j) / Double(vis)) * 0.58)
                guard fadeA > 0.02 else { continue }
                let ci: Int = isHead
                    ? Int((t * 11.0 + col.phase * 97.0).truncatingRemainder(dividingBy: nChars))
                    : col.chars[j % col.chars.count]
                let safeCI = max(0, min(ci, Self.mChars.count - 1))
                let char   = String(Self.mChars[safeCI])
                let fg: Color = isHead ? .white.opacity(fadeA) : base.opacity(fadeA)
                ctx.draw(
                    Text(char).font(.system(size: col.ch * 0.88, weight: .regular, design: .monospaced))
                              .foregroundColor(fg),
                    at: CGPoint(x: x, y: cy)
                )
            }
        }
    }

    // MARK: - 6. Glitch Bars

    private func drawGlitchBars(ctx: GraphicsContext, size: CGSize, t: Double) {
        let defs: [(Double, Double, CGFloat, CGFloat)] = [
            (4.3,  0.11, 4,  28), (7.1,  0.26, 3,  44), (5.8,  0.42, 6,  18),
            (9.2,  0.54, 2,  60), (6.5,  0.63, 5,  32), (11.0, 0.70, 3,  46),
            (8.3,  0.77, 4,  38), (3.7,  0.85, 7,  22), (12.4, 0.32, 2,  56),
            (5.2,  0.91, 3,  28), (14.8, 0.48, 5,  70), (6.9,  0.18, 4,  35),
        ]
        for (interval, yFrac, barH, mag) in defs {
            let lt = t.truncatingRemainder(dividingBy: interval)
            guard lt < 0.22 else { continue }
            let prog  = lt / 0.22
            let fade  = CGFloat(1.0 - prog)
            let yPos  = CGFloat(yFrac) * size.height
            let shift = CGFloat(sin(prog * .pi * 3)) * mag * fade
            let barW  = size.width * (0.42 + fade * 0.52)
            ctx.fill(Path(CGRect(x: shift + 5, y: yPos, width: barW, height: barH)),
                     with: .color(Color(red: 0, green: 1, blue: 1).opacity(Double(fade) * 0.20)))
            ctx.fill(Path(CGRect(x: shift - 5, y: yPos + barH * 0.6, width: barW, height: barH)),
                     with: .color(Color(red: 1, green: 0, blue: 1).opacity(Double(fade) * 0.20)))
            if prog < 0.22 {
                ctx.fill(Path(CGRect(x: 0, y: yPos - 1, width: size.width, height: barH + 2)),
                         with: .color(.white.opacity(0.06 * (1.0 - prog / 0.22))))
            }
        }
    }

    // MARK: - 7. Central Glow

    private func drawCentralGlow(ctx: GraphicsContext,
                                  vx: CGFloat, vy: CGFloat, maxR: CGFloat, t: Double) {
        let pulse  = CGFloat(0.5 + 0.5 * sin(t * 1.75))
        let center = CGPoint(x: vx, y: vy)
        let gr     = maxR * (0.22 + 0.04 * pulse)

        ctx.fill(
            Path(ellipseIn: CGRect(x: vx-gr, y: vy-gr, width: gr*2, height: gr*2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.65, green: 0.05, blue: 1.0).opacity(0.14 + 0.12 * Double(pulse)), location: 0.0),
                    .init(color: Color(red: 0.45, green: 0.0,  blue: 0.80).opacity(0.18 + 0.08 * Double(pulse)), location: 0.35),
                    .init(color: Color(red: 0.25, green: 0.0,  blue: 0.55).opacity(0.08), location: 0.70),
                    .init(color: .clear, location: 1.0),
                ]),
                center: center, startRadius: 0, endRadius: gr
            )
        )
        let gr2 = gr * 0.28
        ctx.fill(
            Path(ellipseIn: CGRect(x: vx-gr2, y: vy-gr2, width: gr2*2, height: gr2*2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.42 + 0.28 * Double(pulse)), location: 0.0),
                    .init(color: Color(red: 0.80, green: 0.15, blue: 1.0).opacity(0.45 + 0.15 * Double(pulse)), location: 0.45),
                    .init(color: .clear, location: 1.0),
                ]),
                center: center, startRadius: 0, endRadius: gr2
            )
        )
    }

    // MARK: - 8. CRT Scanlines

    private func drawScanlines(ctx: GraphicsContext, size: CGSize) {
        var p = Path()
        var y: CGFloat = 0
        while y < size.height {
            p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            y += 4
        }
        ctx.fill(p, with: .color(.black.opacity(0.10)))
    }
}
