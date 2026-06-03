import SwiftUI

// MARK: - Note View
// Renders a single note with animated glitch frame, symbol, and catch animation.

struct NoteView: View {
    let note: NoteItem
    let size: CGSize
    @Environment(\.uiScale) private var scale

    var body: some View {
        let baseR  = note.noteSize.baseRadius * scale
        let frameW = baseR * 2.2
        ZStack {
            if note.caught {
                catchGlitch(baseR: baseR, frameW: frameW)
                    .opacity(max(0, 1 - note.catchProgress * 1.6))
            } else {
                glitchNote(baseR: baseR, frameW: frameW)
                    .opacity(note.life)
            }
        }
        .position(x: note.position.x * size.width,
                  y: note.position.y * size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Glitch Frame (all note kinds)

    @ViewBuilder
    private func glitchNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let shape    = note.noteShape
        let isPower  = note.noteKind != .normal
        let nc       = note.color
        let gc       = note.glowColor
        let tiltDeg  = isPower ? 0.0
                               : Double((note.id.hashValue & 0x7FFFFFFF) % 7 - 3) * 1.5
        let phaseOff = Double(note.id.hashValue & 0xFFFF) / 65535.0 * 9.0
        let idSeed   = UInt64(bitPattern: Int64(note.id.hashValue))
        let pulseDur = note.noteSize.pulseDuration
        let sym      = note.symbol
        let symSize  = baseR * 0.90
        let labelTxt = kindLabel
        let rotSpeed = noteRotSpeed
        let isRainbow = note.noteKind == .frenzy
        let (frameMain, ghostL, ghostR) = noteFrameColors()

        ZStack {
            // Atmospheric glow
            Circle()
                .fill(gc.opacity(0.10))
                .frame(width: frameW * 2.8, height: frameW * 2.8)
                .blur(radius: baseR * 0.9)

            // Expanding warning-ping rings (power notes only)
            if isPower {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate + phaseOff
                    Canvas { ctx, sz in
                        let cx = sz.width / 2, cy = sz.height / 2
                        let period = 2.2
                        for ring in 0..<2 {
                            let prog = (t + Double(ring) * period * 0.5)
                                .truncatingRemainder(dividingBy: period) / period
                            let alpha = (1.0 - prog) * 0.50
                            guard alpha > 0.02 else { continue }
                            let r = CGFloat(prog) * frameW * 1.7
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                                with: .color(gc.opacity(alpha)), lineWidth: 1.5
                            )
                        }
                    }
                    .frame(width: frameW * 3.8, height: frameW * 3.8)
                }
            }

            // Animated glitch frame + symbol
            TimelineView(.animation) { tl in
                let t      = tl.date.timeIntervalSinceReferenceDate + phaseOff
                let gPhase = t.truncatingRemainder(dividingBy: 2.7)
                let gFrac  = CGFloat(gPhase < 0.10 ? gPhase / 0.10 : 0)
                let chrX   = 2.0 + CGFloat(sin(t * 0.9)) + gFrac * 12
                let chrY   = 0.8 + CGFloat(cos(t * 0.7)) * 0.6 + gFrac * 5
                let rotDeg = t * rotSpeed

                let rainbowL = isRainbow ? glitchHue(t * 0.50)       : ghostL
                let rainbowR = isRainbow ? glitchHue(t * 0.50 + 0.5) : ghostR

                ZStack {
                    Canvas { ctx, sz in
                        let cx = sz.width / 2, cy = sz.height / 2

                        if isPower {
                            ctx.translateBy(x: cx, y: cy)
                            ctx.rotate(by: .degrees(rotDeg))
                            ctx.translateBy(x: -cx, y: -cy)
                        }

                        let pulseF = CGFloat(0.5 + 0.5 * sin(t * 2 * .pi / pulseDur))
                        let r      = frameW * (0.94 + 0.13 * pulseF) / 2
                        let lw: CGFloat = isPower ? 4.0 : 3.5

                        let segsMain = buildNoteSegments(shape: shape, cx: cx,        cy: cy,        r: r, gFrac: gFrac, idSeed: idSeed)
                        let segsL    = buildNoteSegments(shape: shape, cx: cx - chrX, cy: cy - chrY, r: r, gFrac: gFrac, idSeed: idSeed)
                        let segsR    = buildNoteSegments(shape: shape, cx: cx + chrX, cy: cy + chrY, r: r, gFrac: gFrac, idSeed: idSeed)

                        for seg in segsMain {
                            ctx.stroke(seg, with: .color(gc.opacity(0.28 + Double(gFrac) * 0.22)),
                                       lineWidth: lw * (isPower ? 5.0 : 3.5))
                        }
                        for seg in segsL {
                            ctx.stroke(seg, with: .color(rainbowL.opacity(0.72)), lineWidth: lw)
                        }
                        for seg in segsR {
                            ctx.stroke(seg, with: .color(rainbowR.opacity(0.72)), lineWidth: lw)
                        }
                        for seg in segsMain {
                            ctx.stroke(seg, with: .color(frameMain), lineWidth: lw * (isPower ? 1.4 : 1.1))
                        }

                        // Pixel scatter
                        let timeSlot = UInt64(abs(t * 3)) & 0xFFF
                        var rng = GlitchRNG(idSeed &+ timeSlot &* 0x9E3779B9)
                        let pixCount = (isPower ? 14 : 8) + Int(gFrac * 16)
                        for _ in 0..<pixCount {
                            let angle = rng.next() * .pi * 2
                            let dist  = r * CGFloat(1.10 + rng.next() * 0.50)
                            let px    = cx + CGFloat(cos(angle)) * dist
                            let py    = cy + CGFloat(sin(angle)) * dist
                            let pw    = CGFloat(3 + rng.next() * 16)
                            let ph    = CGFloat(2 + rng.next() * 5)
                            let col   = rng.next() < 0.5 ? rainbowL : rainbowR
                            ctx.fill(Path(CGRect(x: px - pw/2, y: py - ph/2, width: pw, height: ph)),
                                     with: .color(col.opacity(0.55 + Double(gFrac) * 0.35)))
                        }

                        // Horizontal displacement bars
                        var barRNG = GlitchRNG(idSeed &+ 0xCAFEBABE)
                        for _ in 0..<4 {
                            let yFrac  = barRNG.next()
                            let barY   = cy + (CGFloat(yFrac) - 0.5) * r * 1.9
                            let xShift = CGFloat(barRNG.next() - 0.5) * r * 0.7 * (1 + gFrac * 3)
                            let barLen = r * CGFloat(0.7 + barRNG.next() * 1.0)
                            let barH   = CGFloat(2 + barRNG.next() * 4)
                            let col    = barRNG.next() < 0.5 ? rainbowL : frameMain
                            ctx.fill(
                                Path(CGRect(x: cx - barLen/2 + xShift, y: barY, width: barLen, height: barH)),
                                with: .color(col.opacity(0.28 + Double(gFrac) * 0.45))
                            )
                        }
                    }
                    .frame(width: frameW * 2.6, height: frameW * 2.6)

                    // Symbol with chromatic aberration
                    let chrOff = CGFloat(2.5 + Double(gFrac) * 8)
                    ZStack {
                        Text(sym).foregroundColor(rainbowL.opacity(0.55)).offset(x: -chrOff, y: -chrOff * 0.35)
                        Text(sym).foregroundColor(rainbowR.opacity(0.55)).offset(x:  chrOff, y:  chrOff * 0.35)
                        Text(sym).foregroundColor(frameMain).shadow(color: gc, radius: isPower ? 12 : 8)
                    }
                    .font(.custom("Audiowide-Regular", size: symSize))
                }
            }

            // Kind label (power notes)
            if isPower {
                Text(labelTxt)
                    .font(.custom("Audiowide-Regular", size: max(7, baseR * 0.28)))
                    .foregroundColor(gc.opacity(0.90))
                    .shadow(color: gc, radius: 6)
                    .offset(y: frameW * 0.62)
                    .tracking(2)
            }

            // Point label (normal notes)
            if note.noteKind == .normal {
                Text("+\(note.points)")
                    .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.36)))
                    .foregroundColor(nc.opacity(0.90))
                    .shadow(color: gc, radius: 4)
                    .offset(y: frameW * 0.58)
            }
        }
        .rotationEffect(.degrees(tiltDeg))
    }

    // MARK: - Catch Glitch Animation

    @ViewBuilder
    private func catchGlitch(baseR: CGFloat, frameW: CGFloat) -> some View {
        let hex       = note.noteShape == .hexagon
        let prog      = CGFloat(note.catchProgress)
        let expand    = 1 + prog * 2.4
        let chrOffset = prog * 20
        let chrAlpha  = Double(max(0, 0.55 - prog))

        ZStack {
            NoteFrame(hex: hex, w: frameW, stroke: Color(red: 1, green: 0.1, blue: 0.3), lw: 2)
                .scaleEffect(expand).offset(x:  chrOffset, y: -chrOffset * 0.25).opacity(chrAlpha)

            NoteFrame(hex: hex, w: frameW, stroke: note.glowColor, lw: 2)
                .scaleEffect(expand).offset(x: -chrOffset, y:  chrOffset * 0.25).opacity(chrAlpha)

            Canvas { ctx, sz in
                let slices: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.28, 0.70, -16), (0.52, 0.45, 20), (0.74, 0.60, -10)
                ]
                for (yF, wF, xS) in slices {
                    let y = sz.height * yF, w = sz.width * wF, xOff = xS * prog
                    var p = Path()
                    p.move(to: CGPoint(x: xOff, y: y)); p.addLine(to: CGPoint(x: w + xOff, y: y))
                    let a = max(0.0, 0.65 - Double(prog) * 1.3)
                    ctx.stroke(p, with: .color(note.color.opacity(a)), lineWidth: 2.5)
                }
            }
            .frame(width: frameW, height: frameW)
            .scaleEffect(expand)

            Text(note.symbol)
                .font(.custom("Audiowide-Regular", size: baseR * 0.85))
                .foregroundColor(note.color)
                .shadow(color: note.glowColor, radius: 6)
                .scaleEffect(expand * 0.65 + 0.35)
        }
    }

    // MARK: - Computed Properties

    private var noteRotSpeed: Double {
        switch note.noteKind {
        case .obstacle: return  12
        case .trap:     return -22
        case .frenzy:   return  32
        case .blackout: return  -7
        case .normal:   return   0
        }
    }

    private func noteFrameColors() -> (Color, Color, Color) {
        switch note.noteKind {
        case .normal:
            return (.white,
                    Color(red: 0.0, green: 0.95, blue: 1.0),
                    Color(red: 1.0, green: 0.05, blue: 1.0))
        case .obstacle:
            return (Color(red: 0.20, green: 0.60, blue: 1.00),
                    Color(red: 0.05, green: 0.15, blue: 0.70),
                    .white)
        case .trap:
            return (Color(red: 1.00, green: 0.15, blue: 0.25),
                    Color(red: 0.55, green: 0.00, blue: 0.10),
                    Color(red: 1.00, green: 0.45, blue: 0.00))
        case .frenzy:
            return (.white,
                    Color(red: 0.0, green: 0.95, blue: 1.0),
                    Color(red: 1.0, green: 0.05, blue: 1.0))
        case .blackout:
            return (Color(red: 0.60, green: 0.00, blue: 1.00),
                    Color(red: 0.25, green: 0.00, blue: 0.65),
                    Color(red: 0.85, green: 0.00, blue: 1.00))
        }
    }

    private var kindLabel: String {
        switch note.noteKind {
        case .obstacle: return "FREEZE"
        case .trap:     return "GLITCH"
        case .frenzy:   return "FRENZY"
        case .blackout: return "BLACKOUT"
        case .normal:   return ""
        }
    }
}

// MARK: - Note Frame Helper
// Renders either a HexagonShape or a Rectangle as fill or stroke.

private struct NoteFrame: View {
    let hex: Bool
    let w:   CGFloat
    var fill:   Color? = nil
    var stroke: Color? = nil
    var lw:     CGFloat = 1

    var body: some View {
        if hex {
            if let f = fill   { HexagonShape().fill(f).frame(width: w, height: w) }
            if let s = stroke { HexagonShape().stroke(s, lineWidth: lw).frame(width: w, height: w) }
        } else {
            if let f = fill   { Rectangle().fill(f).frame(width: w, height: w) }
            if let s = stroke { Rectangle().stroke(s, lineWidth: lw).frame(width: w, height: w) }
        }
    }
}

// MARK: - Hexagon Shape

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a  = CGFloat(i) / 6 * .pi * 2
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}
