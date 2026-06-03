import SwiftUI

// MARK: - Co-op Note Item
// Moves in any direction depending on which edge it spawned from.
// Any player may catch any note. Good notes increase groove; bad ones tank it.

struct CoopNoteItem: Identifiable {
    let id       = UUID()
    var position: CGPoint     // normalized screen position (0-1), updated every frame
    let velocity: CGPoint     // normalized units / second; direction encodes spawn edge
    let noteKind: NoteKind    // .normal / .frenzy = good; .obstacle / .trap / .blackout = bad
    let noteSize: NoteSize
    let noteShape: NoteShape
    var caught         = false
    var missed         = false  // set when note exits any screen edge without being caught
    var catchProgress: Double = 0

    // Convenience aliases kept so callers don't need updating
    var xPos:  CGFloat { position.x }
    var laneY: CGFloat { position.y }

    var isBoss: Bool = false   // requires both players to catch simultaneously
    var isBad:  Bool { noteKind == .obstacle || noteKind == .trap || noteKind == .blackout }
    var isGood: Bool { !isBad }

    var catchRadius: CGFloat { noteSize.catchRadius * 1.3 }

    var color: Color {
        switch noteKind {
        case .normal:   return .cyan
        case .frenzy:   return .white
        case .obstacle: return Color(red: 0.20, green: 0.60, blue: 1.00)
        case .trap:     return Color(red: 1.00, green: 0.15, blue: 0.25)
        case .blackout: return Color(red: 0.60, green: 0.00, blue: 1.00)
        }
    }

    var glowColor: Color {
        switch noteKind {
        case .normal:   return Color(red: 0, green: 1, blue: 1)
        case .frenzy:   return Color(red: 1.00, green: 1.00, blue: 0.85)
        case .obstacle: return Color(red: 0.00, green: 0.45, blue: 1.00)
        case .trap:     return Color(red: 1.00, green: 0.20, blue: 0.35)
        case .blackout: return Color(red: 0.55, green: 0.00, blue: 0.90)
        }
    }

    var symbol: String {
        switch noteKind {
        case .normal:   return "♪"
        case .frenzy:   return "★"
        case .obstacle: return "❄"
        case .trap:     return "⚡"
        case .blackout: return "⊘"
        }
    }

    var actionLabel: String { isBad ? "AVOID" : "CATCH" }
}

// MARK: - Groove State
// Shared 0–100 team meter. Drives visual intensity and audio layers.

struct GrooveState {
    // Start low so players have to earn their way up
    var level: Double = 15.0

    var tier: GrooveTier {
        switch level {
        case ..<15:  return .cold   // 15 pts — small, quick to escape
        case ..<40:  return .warm   // 25 pts
        case ..<68:  return .hot    // 28 pts
        default:     return .ultra  // 32 pts — largest, most time spent here
        }
    }

    mutating func applyGoodCatch(_ quality: BeatQuality) {
        let gain: Double
        switch quality {
        case .perfect: gain = 5.5
        case .good:    gain = 2.5
        case .offBeat: gain = 0.8
        }
        level = min(100, level + gain)
    }

    mutating func applyFrenzyCatch() { level = min(100, level +  9.0) }
    mutating func applyBadCatch()    { level = max(0,   level -  8.0) }
    mutating func applyMissedNote()  { level = max(0,   level -  3.0) }
    mutating func applyDodgedBad()   { level = min(100, level +  1.0) }
    // Gentle pull — players can build up as long as they keep catching
    mutating func passiveDecay()     { level = max(0,   level -  0.02) }
}

// MARK: - Confetti Particle

struct ConfettiParticle {
    var x:             CGFloat
    var y:             CGFloat
    var vx:            CGFloat
    var vy:            CGFloat
    var rotation:      CGFloat
    var rotationSpeed: CGFloat
    let color:         Color
    var life:          Double   // 1 → 0
    let size:          CGFloat
}

// MARK: - Groove Tier

enum GrooveTier: Int, Equatable {
    case cold = 0, warm, hot, ultra

    var label: String {
        switch self {
        case .cold:  return "COLD"
        case .warm:  return "WARM"
        case .hot:   return "HOT"
        case .ultra: return "ULTRA ★"
        }
    }

    var color: Color {
        switch self {
        case .cold:  return Color(red: 0.30, green: 0.50, blue: 1.00)
        case .warm:  return .cyan
        case .hot:   return Color(red: 1.00, green: 0.55, blue: 0.00)
        case .ultra: return .yellow
        }
    }

    var cameraOpacity: Double {
        switch self {
        case .cold:  return 0.30   // barely lit — dead party
        case .warm:  return 0.58
        case .hot:   return 0.80
        case .ultra: return 0.94
        }
    }

    var particleScale: Double {
        switch self {
        case .cold:  return 0.15   // almost no particles at dead-party level
        case .warm:  return 0.80
        case .hot:   return 1.70
        case .ultra: return 3.00
        }
    }
}
