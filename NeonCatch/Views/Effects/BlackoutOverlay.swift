import SwiftUI

// MARK: - Blackout Overlay
// Full-screen SMPTE test-card effect triggered by a blackout note catch.
// Phase 1 (first 1 s): pure black screen.
// Phase 2 (remaining 2 s): instant SMPTE test card with no fade in/out.

struct BlackoutOverlay: View {
    let state: BlackoutState
    let size:  CGSize

    var body: some View {
        Canvas { ctx, _ in draw(ctx: ctx, size: size) }
            .frame(width: size.width, height: size.height)
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        if state.isBlackPhase {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        } else {
            drawTestCard(ctx: ctx, size: size)
        }
    }

    // MARK: - Test Card

    private func drawTestCard(ctx: GraphicsContext, size: CGSize) {
        let cx = size.width  * 0.50
        let cy = size.height * 0.50
        let r  = min(size.width, size.height) * 0.44
        let cr = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

        drawTileBackground(ctx: ctx, size: size)
        drawSideBars(ctx: ctx, cx: cx, cy: cy, r: r)

        ctx.drawLayer { lc in
            lc.clip(to: Path(ellipseIn: cr))
            drawCircleContent(ctx: lc, cx: cx, cy: cy, r: r)
        }

        ctx.stroke(Path(ellipseIn: cr),
                   with: .color(Color(red: 0, green: 0.93, blue: 0.97)),
                   lineWidth: 3)
    }

    // MARK: - 1. Grey tile background

    private func drawTileBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.07, green: 0.07, blue: 0.09)))
        let ts   = max(28 as CGFloat, size.width / 36)
        let gap  = ts * 0.09
        let step = ts + gap
        var path = Path()
        var x: CGFloat = gap * 0.5
        while x < size.width {
            var y: CGFloat = gap * 0.5
            while y < size.height {
                path.addRect(CGRect(x: x, y: y, width: ts, height: ts))
                y += step
            }
            x += step
        }
        ctx.fill(path, with: .color(Color(red: 0.14, green: 0.14, blue: 0.18)))
    }

    // MARK: - 2. Outside-circle coloured side bars

    private func drawSideBars(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        let palBlue = Color(red: 0.22, green: 0.27, blue: 0.72)
        let palPink = Color(red: 1.0,  green: 0.09, blue: 0.58)
        let palCyan = Color(red: 0.0,  green: 0.93, blue: 0.97)
        let palGrey = Color(white: 0.91)

        let bw     = r * 0.145
        let bTop   = cy - r * 0.74
        let bTotal = r * 1.48

        let lx = cx - r - bw - r * 0.025
        var y  = bTop
        for (col, frac): (Color, Double) in [(palCyan, 0.255), (palBlue, 0.255),
                                              (palPink, 0.255), (palGrey, 0.235)] {
            let h = bTotal * CGFloat(frac)
            ctx.fill(Path(CGRect(x: lx, y: y, width: bw, height: h)), with: .color(col))
            y += h
        }

        let rx = cx + r + r * 0.025
        y = bTop
        for (col, frac): (Color, Double) in [(palBlue, 0.32), (palPink, 0.38), (palCyan, 0.30)] {
            let h = bTotal * CGFloat(frac)
            ctx.fill(Path(CGRect(x: rx, y: y, width: bw, height: h)), with: .color(col))
            y += h
        }
    }

    // MARK: - 3. Circle content

    private func drawCircleContent(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        let palBlue = Color(red: 0.22, green: 0.27, blue: 0.72)
        let palPink = Color(red: 1.0,  green: 0.09, blue: 0.58)
        let palCyan = Color(red: 0.0,  green: 0.93, blue: 0.97)
        let palGrey = Color(white: 0.91)

        let left = cx - r; let top = cy - r
        let cw   = r * 2;  let ch  = r * 2

        ctx.fill(Path(CGRect(x: left, y: top, width: cw, height: ch)), with: .color(.black))

        // S1: Castle / step-wedge (top 14 %)
        let s1h = ch * 0.14
        var tl  = Path()
        tl.move(to: CGPoint(x: cx, y: top)); tl.addLine(to: CGPoint(x: cx, y: top + s1h * 0.44))
        ctx.stroke(tl, with: .color(palCyan), lineWidth: 2)
        let brW = cw * 0.275, brH = s1h * 0.42
        ctx.fill(Path(CGRect(x: cx - brW/2, y: top, width: brW, height: brH)), with: .color(palPink))
        let swTop = top + brH, swH = s1h - brH
        let levels: [Double] = [0, 0.15, 0.30, 0.50, 0.70, 0.91, 0.70, 0.50, 0.30, 0.15, 0, 0.15, 0.30, 0.50]
        let swW = cw / CGFloat(levels.count)
        for (i, lv) in levels.enumerated() {
            ctx.fill(Path(CGRect(x: left + CGFloat(i)*swW, y: swTop, width: swW+0.5, height: swH)),
                     with: .color(Color(white: lv)))
        }

        // S2: Colour bars (next 43 %)
        let s2y = top + s1h, s2h = ch * 0.43
        let bars: [Color] = [palGrey, palCyan, palPink, palBlue, palPink, palCyan, .black]
        let cbW = cw / CGFloat(bars.count)
        for (i, col) in bars.enumerated() {
            ctx.fill(Path(CGRect(x: left + CGFloat(i)*cbW, y: s2y, width: cbW+0.5, height: s2h)),
                     with: .color(col))
        }

        // S3: Black + stripe groups (next 25 %)
        let s3y = s2y + s2h, s3h = ch * 0.25
        ctx.fill(Path(CGRect(x: left, y: s3y, width: cw, height: s3h)), with: .color(.black))
        for (startFrac, widthFrac): (Double, Double) in [(0.18, 0.27), (0.52, 0.30)] {
            var sx   = left + cw * CGFloat(startFrac)
            let endX = sx + cw * CGFloat(widthFrac)
            var bright = true
            while sx < endX {
                ctx.fill(Path(CGRect(x: sx, y: s3y + s3h*0.08, width: 3, height: s3h*0.72)),
                         with: .color(bright ? palGrey : .black))
                sx += 3; bright.toggle()
            }
        }

        // S4: Dark-to-light ramp (next 10 %)
        let s4y = s3y + s3h, s4h = ch * 0.10
        let nSteps = 8, gsW = cw / CGFloat(nSteps)
        for i in 0..<nSteps {
            let lv = Double(i) / Double(nSteps - 1) * 0.91
            ctx.fill(Path(CGRect(x: left + CGFloat(i)*gsW, y: s4y, width: gsW+0.5, height: s4h)),
                     with: .color(Color(white: lv)))
        }

        // S5: Bottom accent strip
        let s5y = s4y + s4h, s5h = (cy + r) - s5y
        ctx.fill(Path(CGRect(x: left,           y: s5y, width: cw,        height: s5h)), with: .color(palPink))
        ctx.fill(Path(CGRect(x: cx - cw * 0.07, y: s5y, width: cw * 0.14, height: s5h)), with: .color(palBlue))
        ctx.fill(Path(CGRect(x: cx + cw * 0.07, y: s5y, width: cw * 0.04, height: s5h)), with: .color(palCyan))
    }
}
