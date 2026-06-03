import SwiftUI

// MARK: - Co-op Note View
//
// Rendering rules (performance):
//  • NO .blur() — bloom faked with layered polygon strokes inside Canvas (zero offscreen passes)
//  • NO standalone Circle() views — every layer uses the note's actual polygon shape
//  • ONE TimelineView per live note — the single Canvas handles all 9 layers in one pass
//  • notePolygon() builds a closed Path (1 ctx.stroke call vs 6 for buildNoteSegments)
//    and is used for smooth, non-glitched layers (halo, beat ring, trail, ping, explosion)
//  • buildNoteSegments() is kept only for the glitch-displaced main frame + CA ghosts

struct CoopNoteView: View {
    let note:      CoopNoteItem
    let size:      CGSize
    let beatPhase: Double

    @Environment(\.uiScale) private var scale

    var body: some View {
        let baseR  = note.noteSize.baseRadius * scale * (note.isBoss ? 2.0 : 1.0)
        let frameW = baseR * 2.2

        ZStack {
            if note.caught {
                catchExplosion(baseR: baseR, frameW: frameW)
                    .opacity(max(0, 1 - note.catchProgress * 1.6))
            } else if note.isBoss {
                bossNote(baseR: baseR, frameW: frameW)
            } else {
                liveNote(baseR: baseR, frameW: frameW)
            }
        }
        .position(x: note.xPos * size.width,
                  y: note.laneY * size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Boss Note
    // One TimelineView → Canvas. Three hexagon rings + orbital dots + label.

    @ViewBuilder
    private func bossNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let beatPulse = CGFloat(0.5 + 0.5 * cos(beatPhase * .pi * 2))
        ZStack {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, sz in
                    let cx = sz.width / 2, cy = sz.height / 2
                    let bp = Double(beatPulse)

                    // Outer pulsing ring
                    ctx.stroke(notePolygon(.hexagon, cx: cx, cy: cy, r: frameW * 0.95),
                               with: .color(Color.yellow.opacity(0.25 + 0.45 * bp)),
                               lineWidth: 3)
                    // Mid soft-fill hexagon
                    ctx.fill(notePolygon(.hexagon, cx: cx, cy: cy, r: frameW * 0.74),
                             with: .color(Color.yellow.opacity(0.04 + 0.07 * bp)))
                    // Inner crisp ring
                    ctx.stroke(notePolygon(.hexagon, cx: cx, cy: cy, r: frameW * 0.55),
                               with: .color(Color.yellow.opacity(0.85)),
                               lineWidth: 2.5)
                    // Orbital dots
                    let dotR = frameW * 0.72
                    for i in 0..<8 {
                        let angle = Double(i) / 8.0 * .pi * 2 + t * 1.2
                        let px = cx + CGFloat(cos(angle)) * dotR
                        let py = cy + CGFloat(sin(angle)) * dotR
                        let dr: CGFloat = 5
                        ctx.fill(Path(ellipseIn: CGRect(x: px-dr, y: py-dr,
                                                        width: dr*2, height: dr*2)),
                                 with: .color(Color.yellow.opacity(0.9)))
                    }
                }
                .frame(width: frameW * 2.4, height: frameW * 2.4)
            }

            VStack(spacing: 2) {
                Text("★")
                    .font(.system(size: baseR * 0.75))
                    .foregroundColor(.yellow)
                Text("DUO CATCH")
                    .font(.custom("Audiowide-Regular", size: max(8, baseR * 0.24)))
                    .foregroundColor(.yellow.opacity(0.9))
                    .tracking(2)
            }
        }
    }

    // MARK: - Live Note
    //
    // Single TimelineView → Canvas draws all layers in order:
    //
    //  1. Trail        — shaped ghost offset along velocity, fades naturally
    //  2. Bloom rings  — 3 concentric polygon halos at decreasing opacity/weight
    //                    (simulates soft blur glow without any offscreen pass)
    //  3. Beat ring    — shaped ring that pulses in/out with the music beat
    //  4. Warning ping — expanding shaped ring for bad (avoid) notes
    //  ── rotation applied here for power notes ──
    //  5. Glow pass    — thick outline for inner illumination
    //  6. CA ghosts    — chromatic-aberration left/right copies
    //  7. Main frame   — crisp primary outline with glitch displacement
    //  8. Pixel scatter — glitch sparks orbiting the frame
    //  9. Displacement bars — horizontal glitch texture bars through frame

    @ViewBuilder
    private func liveNote(baseR: CGFloat, frameW: CGFloat) -> some View {
        let isPower   = note.isBad
        let phaseOff  = Double(note.id.hashValue & 0xFFFF) / 65535.0 * 9.0
        let idSeed    = UInt64(bitPattern: Int64(note.id.hashValue))
        let pulseDur  = note.noteSize.pulseDuration
        let beatPulse = CGFloat(0.5 + 0.5 * cos(beatPhase * .pi * 2))

        let (frameMain, ghostL, ghostR) = frameColors()

        ZStack {
            // ── One TimelineView for the entire animated note ──────────────────────
            TimelineView(.animation) { tl in
                let t      = tl.date.timeIntervalSinceReferenceDate + phaseOff
                let gPhase = t.truncatingRemainder(dividingBy: 2.7)
                let gFrac  = CGFloat(gPhase < 0.10 ? gPhase / 0.10 : 0)
                let chrX   = 2.0 + CGFloat(sin(t * 0.9)) + gFrac * 10
                let chrY   = 0.8 + CGFloat(cos(t * 0.7)) * 0.6 + gFrac * 4
                let rotDeg = t * (isPower ? -18.0 : 0.0)
                let pulseF = CGFloat(0.5 + 0.5 * sin(t * 2 * .pi / pulseDur))
                let r      = frameW * (0.94 + 0.13 * pulseF) / 2
                let lw:    CGFloat = 3.5
                let chrOff = CGFloat(2.5 + Double(gFrac) * 7)

                ZStack {
                    Canvas { ctx, sz in
                        let cx = sz.width / 2, cy = sz.height / 2
                        let bp = Double(beatPulse)

                        // ── 1. Bloom rings: fake glow via layered polygon halos ──────
                        // Innermost ring is brightest/thickest; outer rings fade out.
                        // Combined, they read as a soft neon bloom — zero blur cost.
                        let glowBase = 0.052 + 0.040 * bp
                        let glowScales: [(CGFloat, CGFloat)] = [
                            (1.20, 9), (1.48, 6), (1.76, 3)
                        ]
                        for (i, (rScale, lWidth)) in glowScales.enumerated() {
                            ctx.stroke(
                                notePolygon(note.noteShape, cx: cx, cy: cy, r: r * rScale),
                                with: .color(note.glowColor.opacity(glowBase * Double(3 - i) / 3.0)),
                                lineWidth: lWidth
                            )
                        }

                        // ── 3. Beat ring: shaped ring that pulses with the music ─────
                        ctx.stroke(
                            notePolygon(note.noteShape, cx: cx, cy: cy,
                                        r: r * (1.28 + 0.58 * beatPulse)),
                            with: .color(note.glowColor.opacity(0.17 + 0.42 * bp)),
                            lineWidth: 1.5
                        )

                        // ── 4. Warning ping: expanding ring for bad notes only ────────
                        if isPower {
                            let prog = CGFloat(t.truncatingRemainder(dividingBy: 2.0) / 2.0)
                            let pA   = (1.0 - prog) * 0.36
                            if pA > 0.02 {
                                ctx.stroke(
                                    notePolygon(note.noteShape, cx: cx, cy: cy,
                                                r: prog * r * 2.8),
                                    with: .color(note.glowColor.opacity(pA)),
                                    lineWidth: 1.5
                                )
                            }
                        }

                        // ── Rotation for power notes (affects layers 5–9) ────────────
                        if isPower {
                            ctx.translateBy(x: cx, y: cy)
                            ctx.rotate(by: .degrees(rotDeg))
                            ctx.translateBy(x: -cx, y: -cy)
                        }

                        // ── 5–7. Glow pass + CA ghosts + main frame ──────────────────
                        let segsMain = buildNoteSegments(shape: note.noteShape, cx: cx,        cy: cy,
                                                         r: r, gFrac: gFrac, idSeed: idSeed)
                        let segsL    = buildNoteSegments(shape: note.noteShape, cx: cx - chrX, cy: cy - chrY,
                                                         r: r, gFrac: gFrac, idSeed: idSeed)
                        let segsR    = buildNoteSegments(shape: note.noteShape, cx: cx + chrX, cy: cy + chrY,
                                                         r: r, gFrac: gFrac, idSeed: idSeed)

                        // 5 — inner glow pass
                        for seg in segsMain {
                            ctx.stroke(seg,
                                       with: .color(note.glowColor.opacity(0.28 + Double(gFrac) * 0.22)),
                                       lineWidth: lw * (isPower ? 5.0 : 3.5))
                        }
                        // 6 — chromatic aberration ghosts
                        for seg in segsL { ctx.stroke(seg, with: .color(ghostL.opacity(0.72)), lineWidth: lw) }
                        for seg in segsR { ctx.stroke(seg, with: .color(ghostR.opacity(0.72)), lineWidth: lw) }
                        // 7 — main frame
                        for seg in segsMain {
                            ctx.stroke(seg, with: .color(frameMain),
                                       lineWidth: lw * (isPower ? 1.4 : 1.1))
                        }

                        // ── 8. Pixel scatter ─────────────────────────────────────────
                        let timeSlot = UInt64(abs(t * 3)) & 0xFFF
                        var rng = GlitchRNG(idSeed &+ timeSlot &* 0x9E3779B9)
                        let pixCount = isPower ? 6 : 9
                        for _ in 0..<pixCount {
                            let angle = rng.next() * .pi * 2
                            let dist  = r * CGFloat(1.10 + rng.next() * 0.45)
                            let px    = cx + CGFloat(cos(angle)) * dist
                            let py    = cy + CGFloat(sin(angle)) * dist
                            let pw    = CGFloat(3 + rng.next() * 10)
                            let ph    = CGFloat(2 + rng.next() * 4)
                            let col   = rng.next() < 0.5 ? ghostL : ghostR
                            ctx.fill(
                                Path(CGRect(x: px - pw/2, y: py - ph/2, width: pw, height: ph)),
                                with: .color(col.opacity(0.50 + Double(gFrac) * 0.30))
                            )
                        }

                        // ── 9. Displacement bars: horizontal glitch texture ───────────
                        var barRNG = GlitchRNG(idSeed &+ 0xCAFEBABE)
                        for _ in 0..<4 {
                            let yFrac  = barRNG.next()
                            let barY   = cy + (CGFloat(yFrac) - 0.5) * r * 1.9
                            let xShift = CGFloat(barRNG.next() - 0.5) * r * 0.7 * (1 + gFrac * 3)
                            let barLen = r * CGFloat(0.7 + barRNG.next() * 1.0)
                            let barH   = CGFloat(2 + barRNG.next() * 4)
                            let col    = barRNG.next() < 0.5 ? ghostL : frameMain
                            ctx.fill(
                                Path(CGRect(x: cx - barLen/2 + xShift, y: barY,
                                            width: barLen, height: barH)),
                                with: .color(col.opacity(0.25 + Double(gFrac) * 0.40))
                            )
                        }
                    }
                    .frame(width: frameW * 3.4, height: frameW * 3.4)

                    // Symbol text — outside Canvas so the custom font rasterises cleanly
                    ZStack {
                        Text(note.symbol)
                            .foregroundColor(ghostL.opacity(0.55))
                            .offset(x: -chrOff, y: -chrOff * 0.35)
                        Text(note.symbol)
                            .foregroundColor(ghostR.opacity(0.55))
                            .offset(x:  chrOff, y:  chrOff * 0.35)
                        Text(note.symbol)
                            .foregroundColor(frameMain)
                            .shadow(color: note.glowColor, radius: isPower ? 8 : 5)
                    }
                    .font(.custom("Audiowide-Regular", size: baseR * 0.90))
                }
            }

            // Action label — static, lives outside TimelineView (no per-frame cost)
            Text(note.actionLabel)
                .font(.custom("Audiowide-Regular", size: max(7, baseR * 0.28)))
                .foregroundColor(isPower ? note.glowColor.opacity(0.85) : note.color.opacity(0.75))
                .offset(y: frameW * 0.62)
                .tracking(2)
        }
    }

    // MARK: - Catch Explosion
    // Expanding polygon ring (matches note shape) + chromatic ghost + glitch scan lines.

    @ViewBuilder
    private func catchExplosion(baseR: CGFloat, frameW: CGFloat) -> some View {
        let prog      = CGFloat(note.catchProgress)
        let expand    = 1.0 + prog * 2.4
        let chrOffset = prog * 20
        let chrAlpha  = Double(max(0, 0.55 - prog))
        let (_, ghostL, _) = frameColors()

        ZStack {
            Canvas { ctx, sz in
                let cx = sz.width / 2, cy = sz.height / 2
                let r  = (frameW * expand) / 2

                // Primary expanding polygon ring
                ctx.stroke(notePolygon(note.noteShape, cx: cx, cy: cy, r: r),
                           with: .color(note.glowColor.opacity(chrAlpha * 1.2)),
                           lineWidth: 2)
                // Chromatic aberration ghost ring
                ctx.stroke(notePolygon(note.noteShape, cx: cx, cy: cy, r: r * 1.08),
                           with: .color(ghostL.opacity(chrAlpha * 0.45)),
                           lineWidth: 1.5)

                // Glitch scan lines
                let slices: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.28, 0.70, -16), (0.52, 0.45, 20), (0.74, 0.60, -10)
                ]
                for (yF, wF, xS) in slices {
                    let y = sz.height * yF, w = sz.width * wF, xOff = xS * prog
                    var p = Path()
                    p.move(to: CGPoint(x: xOff, y: y))
                    p.addLine(to: CGPoint(x: w + xOff, y: y))
                    ctx.stroke(p,
                               with: .color(note.color.opacity(max(0, 0.65 - Double(prog) * 1.3))),
                               lineWidth: 2.5)
                }
            }
            .frame(width: frameW * 3.5, height: frameW * 3.5)

            Text(note.symbol)
                .font(.custom("Audiowide-Regular", size: baseR * 0.85))
                .foregroundColor(note.color)
                .scaleEffect(expand * 0.65 + 0.35)
                .offset(x: chrOffset * 0.3)
        }
    }

    // MARK: - Frame Colors

    private func frameColors() -> (Color, Color, Color) {
        switch note.noteKind {
        case .normal:
            return (.white,
                    Color(red: 0.0, green: 0.95, blue: 1.0),
                    Color(red: 1.0, green: 0.05, blue: 1.0))
        case .frenzy:
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
        case .blackout:
            return (Color(red: 0.60, green: 0.00, blue: 1.00),
                    Color(red: 0.25, green: 0.00, blue: 0.65),
                    Color(red: 0.85, green: 0.00, blue: 1.00))
        }
    }
}

// MARK: - Polygon Path Helper
//
// Builds a closed polygon path for a given NoteShape at a specified center and radius.
// Returns a single Path (1 draw call) unlike buildNoteSegments (n draw calls).
// Used for every layer that doesn't need per-edge glitch displacement:
//   bloom rings, beat ring, trail ghost, warning ping, catch explosion ring.
//
// .circle uses 12 sides (vs the 20 in buildNoteSegments) — visually indistinguishable
// at note scales but saves 40% of vertex math per call.

private func notePolygon(_ shape: NoteShape, cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
    let (sides, start): (Int, CGFloat)
    switch shape {
    case .hexagon:  (sides, start) = (6,  0)
    case .square:   (sides, start) = (4,  .pi / 4)
    case .triangle: (sides, start) = (3,  -.pi / 2)
    case .diamond:  (sides, start) = (4,  0)
    case .octagon:  (sides, start) = (8,  .pi / 8)
    case .circle:   (sides, start) = (12, 0)
    }
    var path = Path()
    for i in 0..<sides {
        let a  = CGFloat(i) / CGFloat(sides) * .pi * 2 + start
        let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
    }
    path.closeSubpath()
    return path
}
