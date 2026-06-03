// MARK: - Freeze State

struct FreezeState {
    var active: Bool = false
    var timeLeft: Double = 0
    var glitchPhase: Double = 0
    static let duration: Double = 3.0
}

// MARK: - Trap Glitch State

struct TrapGlitchState {
    var active: Bool = false
    var timeLeft: Double = 0
    var glitchPhase: Double = 0
    static let duration: Double = 3.0
}

// MARK: - Frenzy State  (2× points for the catching player)

struct FrenzyState {
    var active: Bool = false
    var timeLeft: Double = 0
    static let duration: Double = 5.0
}

// MARK: - Blackout State  (full-screen CRT effect — catcher −2500, rival −7500)

struct BlackoutState {
    var active:   Bool   = false
    var timeLeft: Double = 0
    var phase:    Double = 0   // cycles at 1 Hz; drives static-noise seed (15 Hz via *15)

    static let totalDuration: Double = 3.0
    static let blackDuration: Double = 1.0  // first second is pure black

    // True while the screen should be pitch-black (timeLeft in the top 1 s window)
    var isBlackPhase: Bool { timeLeft > (BlackoutState.totalDuration - BlackoutState.blackDuration) }
    // 0..14 index for static noise frame; changes ~15 times per second
    var staticSeed:   Int  { Int(phase * 15) % 15 }
}
