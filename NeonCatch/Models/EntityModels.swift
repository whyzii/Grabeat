import SwiftUI

// MARK: - Note Item

struct NoteItem: Identifiable {
    let id = UUID()
    var player: Int
    var position: CGPoint
    var symbol: String
    var noteSize: NoteSize = .medium
    var noteShape: NoteShape = .square
    var noteKind: NoteKind = .normal
    var life: Double = 1.0
    var caught: Bool = false
    var catchProgress: Double = 0
    var decayRate: Double = 0.004   // units of life/frame at 60 fps; trap notes use a slower rate

    var color: Color {
        switch noteKind {
        case .obstacle: return Color(red: 0.20, green: 0.60, blue: 1.00)  // electric blue
        case .trap:     return Color(red: 1.00, green: 0.15, blue: 0.25)  // crimson
        case .frenzy:   return .white                                      // white (rainbow glitch ghosts)
        case .blackout: return Color(red: 0.60, green: 0.00, blue: 1.00)  // deep purple
        case .normal:   return player == 1 ? .cyan : .magenta
        }
    }

    var glowColor: Color {
        switch noteKind {
        case .obstacle: return Color(red: 0.00, green: 0.45, blue: 1.00)  // deep electric blue
        case .trap:     return Color(red: 1.00, green: 0.20, blue: 0.35)  // crimson glow
        case .frenzy:   return Color(red: 1.00, green: 1.00, blue: 0.85)  // warm white
        case .blackout: return Color(red: 0.55, green: 0.00, blue: 0.90)  // violet glow
        case .normal:   return player == 1 ? Color(red: 0, green: 1, blue: 1)
                                           : Color(red: 1, green: 0, blue: 1)
        }
    }

    var points: Int { noteSize.points }
}

// MARK: - Hand State

struct HandState: Equatable {
    var position:   CGPoint = .zero
    var isPinching: Bool    = false
    var isActive:   Bool    = false
    var pinchDist:  CGFloat = 1.0   // raw Vision thumb-index distance; 1.0 = fully open
    var palmLen:    CGFloat = 0.10  // wrist→middleMCP in Vision space; used to normalise pinchDist
}

// MARK: - Catch Event

struct CatchEvent: Equatable {
    let position: CGPoint
    let color:    Color
    private let id = UUID()
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

// MARK: - Particle Item

struct ParticleItem: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var color: Color
    var life: Double
    var size: CGFloat
}

// MARK: - Score Float

struct ScoreFloat: Identifiable {
    let id = UUID()
    var position: CGPoint
    let target: CGPoint
    let points: Int
    let color: Color
    var life: Double = 1.0
    var scale: Double = 0.6
    var beatLabel: String = ""
    var beatLabelColor: Color = .clear
}
