import SwiftUI

// MARK: - Glitch RNG  (xorshift64, deterministic per-note)
// Used by NoteView and AnimatedGrid to produce consistent per-frame glitch patterns
// without relying on Swift.random (which is non-deterministic per call).

struct GlitchRNG {
    private var s: UInt64
    init(_ seed: UInt64) {
        s = seed == 0 ? 1 : seed
        s ^= s << 13; s ^= s >> 7; s ^= s << 17  // warm-up
    }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s >> 11) / 9007199254740992.0
    }
}

// MARK: - HSV Hue Helper
// HSV → RGB at full saturation/brightness — used for frenzy rainbow cycling.

func glitchHue(_ t: Double) -> Color {
    let h = t.truncatingRemainder(dividingBy: 1.0) * 6
    let x = 1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0)
    switch Int(h) {
    case 0:  return Color(red: 1, green: x, blue: 0)
    case 1:  return Color(red: x, green: 1, blue: 0)
    case 2:  return Color(red: 0, green: 1, blue: x)
    case 3:  return Color(red: 0, green: x, blue: 1)
    case 4:  return Color(red: x, green: 0, blue: 1)
    default: return Color(red: 1, green: 0, blue: x)
    }
}

// MARK: - Note Segment Builder
// Builds the frame as individual edge-segments so each can shear independently.
// All shapes are regular polygons — the segment count sets the shape.

func buildNoteSegments(shape: NoteShape, cx: CGFloat, cy: CGFloat, r: CGFloat,
                       gFrac: CGFloat, idSeed: UInt64) -> [Path] {
    let sides: Int
    let startAngle: CGFloat
    switch shape {
    case .hexagon:  sides = 6;  startAngle = 0
    case .square:   sides = 4;  startAngle = .pi / 4
    case .triangle: sides = 3;  startAngle = -.pi / 2
    case .diamond:  sides = 4;  startAngle = 0
    case .octagon:  sides = 8;  startAngle = .pi / 8
    case .circle:   sides = 20; startAngle = 0
    }
    return (0..<sides).map { i in
        let a1 = CGFloat(i)     / CGFloat(sides) * .pi * 2 + startAngle
        let a2 = CGFloat(i + 1) / CGFloat(sides) * .pi * 2 + startAngle
        var rng  = GlitchRNG(idSeed &+ UInt64(i) &* 17 &+ 0xBEEF1234)
        let disp = gFrac * CGFloat(rng.next() - 0.5) * 22
        var p = Path()
        p.move(to:    CGPoint(x: cx + r * cos(a1) + disp, y: cy + r * sin(a1)))
        p.addLine(to: CGPoint(x: cx + r * cos(a2) + disp, y: cy + r * sin(a2)))
        return p
    }
}
