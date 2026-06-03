import SwiftUI

// MARK: - Game State

enum GameState { case start, tutorial, calibrating, playing, winnerAnnouncement, photoBooth, end, coopTutorial, coopPlaying, coopPhotoBooth, coopEnd }

// MARK: - Note Shape

enum NoteShape: CaseIterable { case hexagon, square, triangle, diamond, octagon, circle }

// MARK: - Note Kind

enum NoteKind {
    case normal
    case obstacle   // ❄  freeze weapon — catch it to freeze the opponent for 3 s
    case trap       // ⚡ glitch trap   — catch it to glitch your own screen for 3 s
    case frenzy     // ★  gold boost    — catch it for 2× points for 5 s
    case blackout   // ⊘  blackout     — catcher −2500 pts, rival −7500 pts + 3 s full-screen CRT static
}

// MARK: - Note Size / Scoring Tiers

enum NoteSize: CaseIterable {
    case tiny, small, medium, large

    var baseRadius: CGFloat {
        switch self {
        case .tiny:   return 16
        case .small:  return 24
        case .medium: return 34
        case .large:  return 46
        }
    }

    var points: Int {
        switch self {
        case .tiny:   return 2000
        case .small:  return 1000
        case .medium: return 500
        case .large:  return 100
        }
    }

    var catchRadius: CGFloat {
        switch self {
        case .tiny:   return 0.050
        case .small:  return 0.065
        case .medium: return 0.080
        case .large:  return 0.100
        }
    }

    var pulseDuration: Double {
        switch self {
        case .tiny:   return 0.40
        case .small:  return 0.55
        case .medium: return 0.72
        case .large:  return 0.95
        }
    }
}

// MARK: - Beat Catch Quality

enum BeatQuality {
    case perfect
    case good
    case offBeat

    var bonusMultiplier: Double {
        switch self {
        case .perfect: return 2.0
        case .good:    return 1.5
        case .offBeat: return 1.0
        }
    }

    var label: String {
        switch self {
        case .perfect: return "PERFECT ★"
        case .good:    return "GOOD ♪"
        case .offBeat: return ""
        }
    }

    var labelColor: Color {
        switch self {
        case .perfect: return .yellow
        case .good:    return .white
        case .offBeat: return .clear
        }
    }
}

