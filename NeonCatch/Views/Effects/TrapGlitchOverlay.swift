import SwiftUI

// MARK: - Trap Glitch Overlay
// Full-intensity half-screen glitch. Deliberately designed to be unreadable:
// heavy base fill + displaced scanlines + large corruption blocks + chromatic
// aberration text. The glitching player genuinely cannot see their notes.

struct TrapGlitchOverlay: View {
    let glitch: TrapGlitchState
    let side:   PlayerSide
    let player: Int
    let size:   CGSize
    @Environment(\.uiScale) private var scale

    private let crimson = Color(red: 0.95, green: 0.04, blue: 0.18)

    var body: some View {
        let w  = side == .full ? size.width : size.width / 2
        let h  = size.height
        let cx: CGFloat = switch side {
            case .left:  w / 2
            case .right: size.width * 0.75
            case .full:  size.width / 2
        }

        ZStack {
            GlitchCanvas(phase: glitch.glitchPhase, crimson: crimson)
                .frame(width: w, height: h)

            GlitchLabel(phase: glitch.glitchPhase, timeLeft: glitch.timeLeft,
                        crimson: crimson, scale: scale)
        }
        .position(x: cx, y: h / 2)
        .allowsHitTesting(false)
    }
}

// MARK: - Glitch Canvas

private struct GlitchCanvas: View {
    let phase:   Double
    let crimson: Color

    var body: some View {
        Canvas { ctx, sz in
            // Seed changes every frame (phase updates at 60 fps).
            let rawSeed = UInt64(bitPattern: Int64(phase * 99_999)) &* 0x9E3779B97F4A7C15
            var rng = GlitchRNG(rawSeed == 0 ? 0xDEADBEEF : rawSeed)

            // ── 1. Heavy base fill ───────────────────────────────────────────
            // Oscillates between 0.58 and 0.76 — always opaque enough to kill note visibility.
            let baseAlpha = 0.58 + 0.18 * abs(sin(phase * .pi * 5))
            ctx.fill(Path(CGRect(origin: .zero, size: sz)),
                     with: .color(crimson.opacity(baseAlpha)))

            // ── 2. Scanline displacement (60 horizontal slices) ──────────────
            // Each slice is horizontally displaced by up to 55 % of the half-width.
            // Some slices are replaced with solid bright artifacts (VHS tracking error).
            let sliceCount = 60
            let sliceH     = sz.height / CGFloat(sliceCount) + 0.5
            for i in 0..<sliceCount {
                let y    = CGFloat(i) * (sz.height / CGFloat(sliceCount))
                let disp = CGFloat(rng.next() * 2 - 1) * sz.width * 0.55
                let roll = rng.next()

                if roll < 0.07 {
                    // Bright VHS streak — wipes across the full slice
                    let streak = streakColor(rng.next())
                    ctx.fill(Path(CGRect(x: -sz.width + disp, y: y,
                                        width: sz.width * 2.8, height: sliceH + 1)),
                             with: .color(streak.opacity(0.88)))
                } else if roll < 0.28 {
                    // Black dropout bar
                    ctx.fill(Path(CGRect(x: disp, y: y,
                                        width: sz.width, height: sliceH)),
                             with: .color(Color.black.opacity(0.60 + rng.next() * 0.35)))
                } else if roll < 0.52 {
                    // Displaced crimson band — looks like corrupted content underneath
                    ctx.fill(Path(CGRect(x: disp * 0.6, y: y,
                                        width: sz.width, height: sliceH)),
                             with: .color(crimson.opacity(0.28 + rng.next() * 0.42)))
                }
                // ~48 % of slices: keep the base fill untouched
            }

            // ── 3. Large digital corruption blocks ──────────────────────────
            // 14 randomly-sized rectangles covering big swaths of the zone.
            let blockColors: [Color] = [
                crimson,
                Color.black,
                Color.white,
                Color(red: 1.0, green: 0.0, blue: 0.5),
                Color(red: 0.0, green: 0.9, blue: 1.0),
                Color(red: 0.8, green: 0.0, blue: 0.0),
                Color(red: 0.0, green: 0.0, blue: 0.0),
            ]
            for _ in 0..<14 {
                let bx  = CGFloat(rng.next()) * sz.width  * 0.9 - sz.width * 0.05
                let by  = CGFloat(rng.next()) * sz.height * 1.05 - sz.height * 0.02
                let bw  = CGFloat(rng.next()) * sz.width  * 0.65 + sz.width * 0.12
                // Tall-narrow or short-wide blocks; squaring next() skews toward thin bars
                let bh  = CGFloat(rng.next() * rng.next()) * sz.height * 0.18 + 3
                let col = blockColors[Int(rng.next() * Double(blockColors.count))]
                ctx.fill(Path(CGRect(x: bx, y: by, width: bw, height: bh)),
                         with: .color(col.opacity(0.62 + rng.next() * 0.38)))
            }

            // ── 4. Vertical tears ────────────────────────────────────────────
            // Bright white hairlines running the full height — "digital rip" effect.
            for _ in 0..<5 {
                let tx = CGFloat(rng.next()) * sz.width
                let tw = CGFloat(rng.next() * 3 + 1)
                ctx.fill(Path(CGRect(x: tx, y: 0, width: tw, height: sz.height)),
                         with: .color(Color.white.opacity(0.45 + rng.next() * 0.45)))
            }

            // ── 5. Pixel noise scatter ───────────────────────────────────────
            // 35 small bright squares — "static" feel.
            let noiseColors: [Color] = [.white, crimson, Color.cyan,
                                         Color(red: 1, green: 0.8, blue: 0)]
            for _ in 0..<35 {
                let px = CGFloat(rng.next()) * sz.width
                let py = CGFloat(rng.next()) * sz.height
                let ps = CGFloat(rng.next() * 7 + 2)
                let nc = noiseColors[Int(rng.next() * Double(noiseColors.count))]
                ctx.fill(Path(CGRect(x: px, y: py, width: ps, height: ps)),
                         with: .color(nc.opacity(0.72 + rng.next() * 0.28)))
            }

            // ── 6. Chromatic fringe edges ────────────────────────────────────
            // Red fringe on left edge, cyan on right — classic lens aberration.
            let fw = sz.width * 0.07
            ctx.fill(Path(CGRect(x: 0, y: 0, width: fw, height: sz.height)),
                     with: .color(Color(red: 1, green: 0, blue: 0).opacity(0.40)))
            ctx.fill(Path(CGRect(x: sz.width - fw, y: 0, width: fw, height: sz.height)),
                     with: .color(Color(red: 0, green: 0.8, blue: 1).opacity(0.40)))

            // ── 7. Strobing border ───────────────────────────────────────────
            let borderAlpha = 0.55 + 0.45 * abs(sin(phase * .pi * 19))
            let bw2: CGFloat = 3.5
            ctx.stroke(Path(CGRect(x: bw2 / 2, y: bw2 / 2,
                                   width: sz.width - bw2, height: sz.height - bw2)),
                       with: .color(crimson.opacity(borderAlpha)), lineWidth: bw2)
        }
    }

    private func streakColor(_ r: Double) -> Color {
        switch Int(r * 4) {
        case 0:  return .white
        case 1:  return Color(red: 0, green: 0.9, blue: 1)
        case 2:  return Color(red: 1, green: 0, blue: 0.5)
        default: return Color(red: 1, green: 0.9, blue: 0)
        }
    }
}

// MARK: - Glitch Label
// Text rendered with split chromatic-aberration copies (R, G, B layers offset).

private struct GlitchLabel: View {
    let phase:    Double
    let timeLeft: Double
    let crimson:  Color
    let scale:    CGFloat

    var body: some View {
        let ca = CGFloat(9 * sin(phase * .pi * 23))

        VStack(spacing: 8) {
            ZStack {
                label("⚡ GLITCH ⚡", color: Color(red: 1, green: 0, blue: 0).opacity(0.75),
                      offset: CGSize(width: -ca, height:  2))
                label("⚡ GLITCH ⚡", color: Color(red: 0, green: 0.85, blue: 1).opacity(0.75),
                      offset: CGSize(width:  ca, height: -2))
                label("⚡ GLITCH ⚡", color: .white, offset: .zero)
            }

            Text("\(max(0, Int(ceil(timeLeft))))s")
                .font(.custom("Audiowide-Regular", size: 46 * scale))
                .foregroundColor(.white)
                .shadow(color: crimson, radius: 14)
                .shadow(color: .white,  radius: 4)
        }
    }

    private func label(_ text: String, color: Color, offset: CGSize) -> some View {
        Text(text)
            .font(.custom("Audiowide-Regular", size: 21 * scale))
            .foregroundColor(color)
            .shadow(color: color, radius: 6)
            .offset(offset)
    }
}
