import SwiftUI
import Combine
import AVFoundation

enum GameState { case start, calibrating, playing, end }

// MARK: - Note shape

enum NoteShape { case hexagon, square }

// MARK: - Note kind

enum NoteKind {
    case normal
    case obstacle   // ❄  freeze weapon — catch it to freeze the opponent for 3 s
    case trap       // ⚡ glitch trap   — catch it to glitch your own screen for 3 s
    case frenzy     // ★  gold boost    — catch it for 2× points for 5 s
    case ghost      // 👻 ghost weapon  — catch it to make the opponent's notes invisible for 3 s
}

// MARK: - Note size / scoring tiers

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

// MARK: - Beat catch quality

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

// MARK: - Data models

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
        case .obstacle: return .white
        case .trap:     return player == 1 ? Color(red: 1.0, green: 0.40, blue: 0.0)
                                           : Color(red: 0.40, green: 1.0, blue: 0.0)
        case .frenzy:   return Color(red: 1.0, green: 0.85, blue: 0.0)
        case .ghost:    return Color(red: 0.70, green: 0.40, blue: 1.0)
        case .normal:   return player == 1 ? .cyan : .magenta
        }
    }
    var glowColor: Color {
        switch noteKind {
        case .obstacle: return Color(red: 0.4, green: 0.85, blue: 1.0)
        case .trap:     return player == 1 ? Color(red: 1.0, green: 0.55, blue: 0.0)
                                           : Color(red: 0.50, green: 1.0, blue: 0.0)
        case .frenzy:   return Color(red: 1.0, green: 1.0, blue: 0.35)
        case .ghost:    return Color(red: 0.85, green: 0.60, blue: 1.0)
        case .normal:   return player == 1 ? Color(red: 0, green: 1, blue: 1)
                                           : Color(red: 1, green: 0, blue: 1)
        }
    }
    var points: Int { noteSize.points }
}

struct HandState: Equatable {
    var position:  CGPoint = .zero
    var isPinching: Bool   = false
    var isActive:   Bool   = false
    var pinchDist: CGFloat = 1.0   // raw Vision thumb-index distance; 1.0 = fully open
}

struct CatchEvent: Equatable {
    let position: CGPoint
    let color:    Color
    private let id = UUID()
    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}

struct ParticleItem: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    var color: Color
    var life: Double
    var size: CGFloat
}

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

// MARK: - Freeze state

struct FreezeState {
    var active: Bool = false
    var timeLeft: Double = 0
    var glitchPhase: Double = 0
    static let duration: Double = 3.0
}

// MARK: - Trap glitch state

struct TrapGlitchState {
    var active: Bool = false
    var timeLeft: Double = 0
    var glitchPhase: Double = 0
    static let duration: Double = 3.0
}

// MARK: - Frenzy state  (2× points for the catching player)

struct FrenzyState {
    var active: Bool = false
    var timeLeft: Double = 0
    static let duration: Double = 5.0
}

// MARK: - Ghost state  (opponent's notes become near-invisible)

struct GhostState {
    var active: Bool = false
    var timeLeft: Double = 0
    var phase: Double = 0   // used for subtle shimmer on the ghost overlay
    static let duration: Double = 3.0
}

// MARK: - Game Manager

@MainActor
class GameManager: ObservableObject {
    @Published var state: GameState = .start
    @Published var notes: [NoteItem] = []
    @Published var scoreP1: Int = 0
    @Published var scoreP2: Int = 0
    @Published var timeLeft: Int = 60
    @Published var particles: [ParticleItem] = []
    @Published var scoreFloats: [ScoreFloat] = []
    @Published var lastCatch: CatchEvent? = nil
    @Published var lastBeatQuality: BeatQuality = .offBeat

    // Freeze state — active means THIS player is frozen (cannot catch, screen glitches)
    @Published var freezeP1: FreezeState = FreezeState()
    @Published var freezeP2: FreezeState = FreezeState()

    // Trap glitch state — self-inflicted when a player catches a trap note
    @Published var trapGlitchP1: TrapGlitchState = TrapGlitchState()
    @Published var trapGlitchP2: TrapGlitchState = TrapGlitchState()

    // Frenzy — catching player scores 2× for 5 s
    @Published var frenzyP1: FrenzyState = FrenzyState()
    @Published var frenzyP2: FrenzyState = FrenzyState()

    // Ghost — catching player makes the OPPONENT's notes near-invisible for 3 s
    @Published var ghostP1: GhostState = GhostState()   // P1's notes are ghosted
    @Published var ghostP2: GhostState = GhostState()   // P2's notes are ghosted

    var handsP1: [HandState] = []
    var handsP2: [HandState] = []

    private var gameTimer: AnyCancellable?
    private var noteSpawner: AnyCancellable?
    private var displayLink: AnyCancellable?
    private let audioEngine = AudioEngine()

    private let gameDuration = 60
    private let symbols = ["♩", "♪", "♫", "♬"]
    private let maxNotesPerPlayer = 4

    // MARK: - Lifecycle

    func beginCalibration() {
        gameTimer?.cancel(); noteSpawner?.cancel(); displayLink?.cancel()
        notes = []; particles = []; scoreFloats = []; lastCatch = nil
        trapGlitchP1 = TrapGlitchState(); trapGlitchP2 = TrapGlitchState()
        frenzyP1 = FrenzyState(); frenzyP2 = FrenzyState()
        ghostP1  = GhostState();  ghostP2  = GhostState()
        state = .calibrating
    }

    func startGame() {
        scoreP1 = 0; scoreP2 = 0
        timeLeft = gameDuration
        notes = []; particles = []; scoreFloats = []; lastCatch = nil
        handsP1 = []; handsP2 = []
        freezeP1 = FreezeState(); freezeP2 = FreezeState()
        trapGlitchP1 = TrapGlitchState(); trapGlitchP2 = TrapGlitchState()
        frenzyP1 = FrenzyState(); frenzyP2 = FrenzyState()
        ghostP1  = GhostState();  ghostP2  = GhostState()
        audioEngine.reset()
        audioEngine.startMusic()
        state = .playing

        for _ in 0..<3 { spawnNote(player: 1); spawnNote(player: 2) }

        gameTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.timeLeft -= 1
                if self.timeLeft <= 0 { self.endGame() }
            }

        noteSpawner = Timer.publish(every: 0.9, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.state == .playing else { return }
                self.tickNoteSpawner()
            }

        displayLink = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    func endGame() {
        gameTimer?.cancel(); noteSpawner?.cancel(); displayLink?.cancel()
        audioEngine.stopMusic()
        state = .end
    }

    func resetToStart() {
        gameTimer?.cancel(); noteSpawner?.cancel(); displayLink?.cancel()
        audioEngine.stopMusic()
        notes = []; particles = []; scoreFloats = []
        freezeP1 = FreezeState(); freezeP2 = FreezeState()
        trapGlitchP1 = TrapGlitchState(); trapGlitchP2 = TrapGlitchState()
        frenzyP1 = FrenzyState(); frenzyP2 = FrenzyState()
        ghostP1  = GhostState();  ghostP2  = GhostState()
        state = .start
    }

    // MARK: - Note spawner tick

    private func tickNoteSpawner() {
        // Freeze and glitch notes spawn with independent per-player random rolls.
        // Score, time, or any player state have zero influence — both players
        // face the exact same probability each tick.
        //   Freeze:  ~2.5 % per tick × 0.9 s ≈ one every ~36 s on average
        //   Glitch:  ~2.0 % per tick × 0.9 s ≈ one every ~45 s on average
        //   Frenzy:  ~2.5 % per tick × 0.9 s ≈ one every ~36 s on average
        //   Ghost:   ~2.0 % per tick × 0.9 s ≈ one every ~45 s on average
        for player in [1, 2] {
            if Double.random(in: 0..<1) < 0.025 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .obstacle && !$0.caught }
                if !alreadyHas { spawnObstacleNote(player: player) }
            }
            if Double.random(in: 0..<1) < 0.020 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .trap && !$0.caught }
                if !alreadyHas { spawnTrapNote(player: player) }
            }
            if Double.random(in: 0..<1) < 0.025 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .frenzy && !$0.caught }
                if !alreadyHas { spawnFrenzyNote(player: player) }
            }
            if Double.random(in: 0..<1) < 0.020 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .ghost && !$0.caught }
                if !alreadyHas { spawnGhostNote(player: player) }
            }
        }

        let alive1 = notes.filter { $0.player == 1 && !$0.caught }.count
        let alive2 = notes.filter { $0.player == 2 && !$0.caught }.count
        if alive1 < maxNotesPerPlayer { spawnNote(player: 1) }
        if alive2 < maxNotesPerPlayer { spawnNote(player: 2) }
    }

    // MARK: - Spawning

    private func spawnNote(player: Int) {
        let pos = bestSpawnPosition(player: player)
        let sizes: [NoteSize] = [.tiny, .small, .medium, .medium, .large, .large]
        notes.append(NoteItem(
            player: player,
            position: pos,
            symbol: symbols.randomElement() ?? "♩",
            noteSize: sizes.randomElement()!,
            noteShape: Bool.random() ? .hexagon : .square,
            noteKind: .normal
        ))
    }

    private func spawnObstacleNote(player: Int) {
        let pos = bestSpawnPosition(player: player)
        notes.append(NoteItem(
            player: player,
            position: pos,
            symbol: "❄",
            noteSize: .medium,
            noteShape: .hexagon,
            noteKind: .obstacle
        ))
    }

    private func bestSpawnPosition(player: Int) -> CGPoint {
        let xRange: ClosedRange<CGFloat> = player == 1 ? 0.06...0.44 : 0.56...0.94
        let yRange: ClosedRange<CGFloat> = 0.18...0.82
        let minSep: CGFloat = 0.22
        let live = notes.filter { $0.player == player && !$0.caught }
        var bestPos = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
        var bestDist: CGFloat = 0
        for _ in 0..<12 {
            let c = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
            let d = live.map {
                let dx = c.x - $0.position.x, dy = c.y - $0.position.y
                return sqrt(dx*dx + dy*dy)
            }.min() ?? .infinity
            if d > bestDist { bestDist = d; bestPos = c }
            if bestDist >= minSep { break }
        }
        return bestPos
    }

    // MARK: - Update loop

    private func update() {
        let dt = 1.0 / 60.0

        // Tick freeze timers
        if freezeP1.active {
            freezeP1.timeLeft -= dt
            freezeP1.glitchPhase = (freezeP1.glitchPhase + dt * 9).truncatingRemainder(dividingBy: 1)
            if freezeP1.timeLeft <= 0 { freezeP1 = FreezeState() }
        }
        if freezeP2.active {
            freezeP2.timeLeft -= dt
            freezeP2.glitchPhase = (freezeP2.glitchPhase + dt * 9).truncatingRemainder(dividingBy: 1)
            if freezeP2.timeLeft <= 0 { freezeP2 = FreezeState() }
        }

        // Tick trap glitch timers
        if trapGlitchP1.active {
            trapGlitchP1.timeLeft -= dt
            trapGlitchP1.glitchPhase = (trapGlitchP1.glitchPhase + dt * 11).truncatingRemainder(dividingBy: 1)
            if trapGlitchP1.timeLeft <= 0 { trapGlitchP1 = TrapGlitchState() }
        }
        if trapGlitchP2.active {
            trapGlitchP2.timeLeft -= dt
            trapGlitchP2.glitchPhase = (trapGlitchP2.glitchPhase + dt * 11).truncatingRemainder(dividingBy: 1)
            if trapGlitchP2.timeLeft <= 0 { trapGlitchP2 = TrapGlitchState() }
        }

        // Tick frenzy timers
        if frenzyP1.active { frenzyP1.timeLeft -= dt; if frenzyP1.timeLeft <= 0 { frenzyP1 = FrenzyState() } }
        if frenzyP2.active { frenzyP2.timeLeft -= dt; if frenzyP2.timeLeft <= 0 { frenzyP2 = FrenzyState() } }

        // Tick ghost timers
        if ghostP1.active {
            ghostP1.timeLeft -= dt
            ghostP1.phase = (ghostP1.phase + dt * 7).truncatingRemainder(dividingBy: 1)
            if ghostP1.timeLeft <= 0 { ghostP1 = GhostState() }
        }
        if ghostP2.active {
            ghostP2.timeLeft -= dt
            ghostP2.phase = (ghostP2.phase + dt * 7).truncatingRemainder(dividingBy: 1)
            if ghostP2.timeLeft <= 0 { ghostP2 = GhostState() }
        }

        var toRemove: [UUID] = []
        for i in notes.indices {
            if notes[i].caught {
                notes[i].catchProgress += dt * 4
                if notes[i].catchProgress >= 1 { toRemove.append(notes[i].id) }
            } else {
                // Notes in a frozen player's zone don't decay — extra punishment: they pile up
                let playerFrozen = notes[i].player == 1 ? freezeP1.active : freezeP2.active
                if !playerFrozen { notes[i].life -= notes[i].decayRate }
                if notes[i].life <= 0 { toRemove.append(notes[i].id) }
            }
        }
        notes.removeAll { toRemove.contains($0.id) }

        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.x
            particles[i].position.y += particles[i].velocity.y
            particles[i].velocity.y += 0.00035
            particles[i].life       -= dt * 1.4
        }
        particles.removeAll { $0.life <= 0 }

        for i in scoreFloats.indices {
            scoreFloats[i].position.x += (scoreFloats[i].target.x - scoreFloats[i].position.x) * 0.06
            scoreFloats[i].position.y += (scoreFloats[i].target.y - scoreFloats[i].position.y) * 0.06
            if scoreFloats[i].scale < 1.0 { scoreFloats[i].scale = min(scoreFloats[i].scale + dt * 4, 1.0) }
            scoreFloats[i].life -= dt * 0.75
        }
        scoreFloats.removeAll { $0.life <= 0 }

        // Frozen players cannot catch anything
        if !freezeP1.active { checkCatch(hands: handsP1, player: 1) }
        if !freezeP2.active { checkCatch(hands: handsP2, player: 2) }
    }

    // MARK: - Catch detection

    private func checkCatch(hands: [HandState], player: Int) {
        let pinching = hands.filter { h in
            h.isActive && h.isPinching &&
            (player == 1 ? h.position.x <= 0.5 : h.position.x >= 0.5)
        }
        guard !pinching.isEmpty else { return }

        for i in notes.indices {
            guard notes[i].player == player,
                  !notes[i].caught,
                  notes[i].life > 0 else { continue }
            for hand in pinching {
                let dx = hand.position.x - notes[i].position.x
                let dy = hand.position.y - notes[i].position.y
                if sqrt(dx * dx + dy * dy) < notes[i].noteSize.catchRadius {
                    notes[i].caught = true
                    switch notes[i].noteKind {
                    case .obstacle: handleObstacleCatch(byPlayer: player, at: notes[i].position)
                    case .trap:     handleTrapCatch(byPlayer: player, at: notes[i].position)
                    case .frenzy:   handleFreznyCatch(byPlayer: player, at: notes[i].position)
                    case .ghost:    handleGhostCatch(byPlayer: player, at: notes[i].position)
                    case .normal:   handleNormalCatch(noteIndex: i, player: player)
                    }
                    break
                }
            }
        }
    }

    private func handleNormalCatch(noteIndex i: Int, player: Int) {
        let quality        = audioEngine.beatQuality()
        let frenzyMult     = (player == 1 ? frenzyP1.active : frenzyP2.active) ? 2.0 : 1.0
        let bonusPoints    = Int(Double(notes[i].points) * quality.bonusMultiplier * frenzyMult)

        if player == 1 { scoreP1 += bonusPoints } else { scoreP2 += bonusPoints }

        spawnPixelBurst(at: notes[i].position, color: notes[i].glowColor, quality: quality)
        spawnScoreFloat(at: notes[i].position, points: bonusPoints,
                        color: notes[i].glowColor, player: player, quality: quality)
        lastCatch       = CatchEvent(position: notes[i].position, color: notes[i].glowColor)
        lastBeatQuality = quality
        audioEngine.playCatch(player: player, quality: quality)
    }

    private func handleObstacleCatch(byPlayer player: Int, at pos: CGPoint) {
        let opponent = player == 1 ? 2 : 1

        // Freeze the opponent
        if opponent == 1 {
            freezeP1 = FreezeState(active: true, timeLeft: FreezeState.duration, glitchPhase: 0)
        } else {
            freezeP2 = FreezeState(active: true, timeLeft: FreezeState.duration, glitchPhase: 0)
        }

        let iceColor = Color(red: 0.4, green: 0.85, blue: 1.0)
        spawnIceBurst(at: pos, color: iceColor)

        // "❄ FROZEN!" float appearing on the opponent's half
        let oppCentreX: CGFloat = opponent == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: oppCentreX, y: 0.55),
            target:   CGPoint(x: oppCentreX, y: 0.30),
            points:   0,
            color:    iceColor,
            life:     1.6,
            scale:    0.5,
            beatLabel:      "❄ FROZEN!",
            beatLabelColor: iceColor
        ))

        lastCatch = CatchEvent(position: pos, color: iceColor)
        audioEngine.playFreeze()
    }

    private func handleTrapCatch(byPlayer player: Int, at pos: CGPoint) {
        if player == 1 {
            trapGlitchP1 = TrapGlitchState(active: true, timeLeft: TrapGlitchState.duration, glitchPhase: 0)
        } else {
            trapGlitchP2 = TrapGlitchState(active: true, timeLeft: TrapGlitchState.duration, glitchPhase: 0)
        }

        let glitchColor: Color = player == 1
            ? Color(red: 1.0, green: 0.40, blue: 0.0)
            : Color(red: 0.40, green: 1.0, blue: 0.0)
        spawnGlitchBurst(at: pos, color: glitchColor)

        let cx: CGFloat = player == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: cx, y: 0.55),
            target:   CGPoint(x: cx, y: 0.30),
            points:   0,
            color:    glitchColor,
            life:     1.6,
            scale:    0.5,
            beatLabel:      "⚡ GLITCHED!",
            beatLabelColor: glitchColor
        ))

        lastCatch = CatchEvent(position: pos, color: glitchColor)
        audioEngine.playGlitch()
    }

    private func handleFreznyCatch(byPlayer player: Int, at pos: CGPoint) {
        if player == 1 {
            frenzyP1 = FrenzyState(active: true, timeLeft: FrenzyState.duration)
        } else {
            frenzyP2 = FrenzyState(active: true, timeLeft: FrenzyState.duration)
        }
        let gold = Color(red: 1.0, green: 0.92, blue: 0.0)
        spawnGlitchBurst(at: pos, color: gold)
        let cx: CGFloat = player == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: cx, y: 0.55),
            target:   CGPoint(x: cx, y: 0.30),
            points:   0, color: gold, life: 1.6, scale: 0.5,
            beatLabel: "★ FRENZY!", beatLabelColor: gold
        ))
        lastCatch = CatchEvent(position: pos, color: gold)
        audioEngine.playFrenzy()
    }

    private func handleGhostCatch(byPlayer player: Int, at pos: CGPoint) {
        // Ghost makes the OPPONENT's notes near-invisible
        let purple = Color(red: 0.75, green: 0.45, blue: 1.0)
        if player == 1 {
            ghostP2 = GhostState(active: true, timeLeft: GhostState.duration, phase: 0)
        } else {
            ghostP1 = GhostState(active: true, timeLeft: GhostState.duration, phase: 0)
        }
        spawnGlitchBurst(at: pos, color: purple)
        let oppCx: CGFloat = player == 1 ? 0.75 : 0.25
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: oppCx, y: 0.55),
            target:   CGPoint(x: oppCx, y: 0.30),
            points:   0, color: purple, life: 1.6, scale: 0.5,
            beatLabel: "👻 GHOSTED!", beatLabelColor: purple
        ))
        lastCatch = CatchEvent(position: pos, color: purple)
        audioEngine.playGhost()
    }

    private func spawnFrenzyNote(player: Int) {
        let pos = bestSpawnPosition(player: player)
        notes.append(NoteItem(
            player: player, position: pos, symbol: "★",
            noteSize: .medium, noteShape: .hexagon, noteKind: .frenzy,
            decayRate: 1.0 / (10.0 * 60.0)
        ))
    }

    private func spawnGhostNote(player: Int) {
        let pos = bestSpawnPosition(player: player)
        notes.append(NoteItem(
            player: player, position: pos, symbol: "👻",
            noteSize: .medium, noteShape: .hexagon, noteKind: .ghost,
            decayRate: 1.0 / (10.0 * 60.0)
        ))
    }

    private func spawnTrapNote(player: Int) {
        let pos = bestSpawnPosition(player: player)
        notes.append(NoteItem(
            player:    player,
            position:  pos,
            symbol:    "⚡",
            noteSize:  .medium,
            noteShape: .hexagon,
            noteKind:  .trap,
            decayRate: 1.0 / (10.0 * 60.0)
        ))
    }

    private func spawnGlitchBurst(at pos: CGPoint, color: Color) {
        let sizes: [CGFloat] = [3, 4, 5, 5, 7, 8, 10]
        for _ in 0..<40 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.002...0.010)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.004),
                color:    Bool.random() ? color : .white,
                life:     Double.random(in: 0.8...1.5),
                size:     sizes.randomElement()!
            ))
        }
    }

    // MARK: - Particles

    private func spawnPixelBurst(at pos: CGPoint, color: Color, quality: BeatQuality) {
        let count: Int = quality == .perfect ? 36 : quality == .good ? 28 : 22
        let pixelSizes: [CGFloat] = [3, 4, 4, 5, 6, 6, 8, 10]
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.003...0.012)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.004),
                color:    quality == .perfect ? .yellow : color,
                life:     Double.random(in: 0.7...1.2),
                size:     pixelSizes.randomElement()!
            ))
        }
    }

    private func spawnIceBurst(at pos: CGPoint, color: Color) {
        let pixelSizes: [CGFloat] = [4, 5, 6, 6, 8, 8, 10, 12]
        let iceWhite = Color(red: 0.85, green: 0.97, blue: 1.0)
        for _ in 0..<48 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.001...0.008)
            particles.append(ParticleItem(
                position: pos,
                velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed - 0.006),
                color:    [color, .white, iceWhite].randomElement()!,
                life:     Double.random(in: 1.0...1.8),
                size:     pixelSizes.randomElement()!
            ))
        }
    }

    private func spawnScoreFloat(at pos: CGPoint, points: Int,
                                  color: Color, player: Int, quality: BeatQuality) {
        let targetX: CGFloat = player == 1 ? 0.13 : 0.87
        scoreFloats.append(ScoreFloat(
            position: pos,
            target:   CGPoint(x: targetX, y: 0.06),
            points:   points,
            color:    quality == .perfect ? .yellow : color,
            beatLabel:      quality.label,
            beatLabelColor: quality.labelColor
        ))
    }
}

// MARK: - Audio Engine

private class AudioEngine {
    private let engine        = AVAudioEngine()
    private let musicPlayer   = AVAudioPlayerNode()
    private let catchPlayer   = AVAudioPlayerNode()
    private let freezePlayer  = AVAudioPlayerNode()
    private let glitchPlayer  = AVAudioPlayerNode()
    private let frenzyPlayer  = AVAudioPlayerNode()
    private let ghostPlayer   = AVAudioPlayerNode()
    private let format:        AVAudioFormat

    private let bpm: Double = 123.046875
    private var beatInterval: Double { 60.0 / bpm }

    private var musicStartHostTime: Double = 0
    private var musicIsPlaying = false
    private var musicBuffer: AVAudioPCMBuffer?
    private var interruptionObserver: Any?

    init() {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
            fatalError("AVAudioFormat failed")
        }
        format = fmt

        // AVAudioSession is iOS-only. On macOS audio routing is handled by
        // the system and AVAudioEngine works without explicit session setup.
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        engine.attach(musicPlayer)
        engine.attach(catchPlayer)
        engine.attach(freezePlayer)
        engine.attach(glitchPlayer)
        engine.attach(frenzyPlayer)
        engine.attach(ghostPlayer)
        engine.connect(musicPlayer,  to: engine.mainMixerNode, format: nil)
        engine.connect(catchPlayer,  to: engine.mainMixerNode, format: nil)
        engine.connect(freezePlayer, to: engine.mainMixerNode, format: nil)
        engine.connect(glitchPlayer, to: engine.mainMixerNode, format: nil)
        engine.connect(frenzyPlayer, to: engine.mainMixerNode, format: nil)
        engine.connect(ghostPlayer,  to: engine.mainMixerNode, format: nil)
        try? engine.start()

        if let url = Bundle.main.url(forResource: "Midnight_Service", withExtension: "mp3"),
           let file = try? AVAudioFile(forReading: url) {
            let frameCount = AVAudioFrameCount(file.length)
            if let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) {
                try? file.read(into: buf)
                musicBuffer = buf
            }
        }

        // AVAudioSession interruptions are iOS-only. On macOS the engine
        // does not get interrupted by phone calls / Siri, so no observer needed.
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            try? self.engine.start()
            if self.musicIsPlaying { self.startMusic() }
        }
        #endif
    }

    deinit { if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) } }

    func reset() {
        musicPlayer.stop(); catchPlayer.stop(); freezePlayer.stop()
        glitchPlayer.stop(); frenzyPlayer.stop(); ghostPlayer.stop()
        musicIsPlaying = false; musicStartHostTime = 0
    }

    func startMusic() {
        guard let buf = musicBuffer else { return }
        ensureEngineRunning()
        musicPlayer.stop()
        musicPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        musicPlayer.play()
        musicIsPlaying = true
        musicStartHostTime = currentEngineTime()
    }

    func stopMusic() { musicPlayer.stop(); musicIsPlaying = false }

    func beatQuality() -> BeatQuality {
        guard musicIsPlaying else { return .offBeat }
        let elapsed = currentEngineTime() - musicStartHostTime
        let phase   = elapsed.truncatingRemainder(dividingBy: beatInterval)
        let dist    = min(phase, beatInterval - phase)
        if dist < 0.060 { return .perfect }
        if dist < 0.120 { return .good }
        return .offBeat
    }

    func playCatch(player playerNum: Int, quality: BeatQuality) {
        ensureEngineRunning()
        let sr: Double = 44100
        let dur: Double = quality == .perfect ? 0.18 : quality == .good ? 0.13 : 0.09
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        let base: Float = playerNum == 1 ? 1046.5 : 783.99
        let f1: Float = quality == .perfect ? base : base * (quality == .good ? 0.75 : 0.5)
        let f2: Float = quality == .perfect ? base * 1.5 : f1
        let vol: Float = quality == .perfect ? 0.45 : quality == .good ? 0.32 : 0.20
        for i in 0..<Int(fc) {
            let t = Float(i) / Float(sr)
            let env = max(0, 1 - t / Float(dur)); let e2 = env * env
            data[i] = (sin(2 * .pi * f1 * t) * 0.6 + sin(2 * .pi * f2 * t) * 0.4) * e2 * vol
        }
        reconnectMono(node: catchPlayer, fmt: mono)
        catchPlayer.scheduleBuffer(buf)
        if !catchPlayer.isPlaying { catchPlayer.play() }
    }

    func playFreeze() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 0.65
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Descending icy chime: C6 → A5 → F5, staggered
        let freqs: [Float]  = [1046.5, 880.0, 698.5]
        let delays: [Double] = [0.0,    0.10,  0.22]
        for i in 0..<Int(fc) {
            let t = Double(i) / sr
            var s: Float = 0
            for (f, d) in zip(freqs, delays) {
                let lt = t - d; guard lt >= 0 else { continue }
                let env = Float(max(0, 1.0 - lt / (dur - d))); let e2 = env * env
                s += sin(2 * .pi * f * Float(lt)) * e2 * 0.28
            }
            data[i] = s
        }
        reconnectMono(node: freezePlayer, fmt: mono)
        freezePlayer.scheduleBuffer(buf)
        if !freezePlayer.isPlaying { freezePlayer.play() }
    }

    func playGlitch() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 0.50
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Dissonant descending buzz — staggered harmonics create a harsh digital clang
        let freqs:  [Float]  = [440.0, 466.2, 329.6, 220.0]
        let starts: [Double] = [0.0,   0.05,  0.12,  0.22]
        for i in 0..<Int(fc) {
            let t = Double(i) / sr
            let env = Float(max(0, 1.0 - t / dur)); let e2 = env * env
            var s: Float = 0
            for (f, d) in zip(freqs, starts) {
                let lt = t - d; guard lt >= 0 else { continue }
                s += sin(2 * .pi * f * Float(lt)) * 0.22
            }
            data[i] = max(-0.30, min(0.30, s * 2.5)) * e2
        }
        reconnectMono(node: glitchPlayer, fmt: mono)
        glitchPlayer.scheduleBuffer(buf)
        if !glitchPlayer.isPlaying { glitchPlayer.play() }
    }

    func playFrenzy() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 0.55
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Ascending major arpeggio C5→E5→G5→C6 — triumphant power-up feel
        let freqs:   [Float]  = [523.25, 659.25, 783.99, 1046.5]
        let delays:  [Double] = [0.0,    0.10,   0.20,   0.32]
        for i in 0..<Int(fc) {
            let t = Double(i) / sr
            var s: Float = 0
            for (f, d) in zip(freqs, delays) {
                let lt = t - d; guard lt >= 0 else { continue }
                let env = Float(max(0, 1.0 - lt / 0.22)); let e2 = env * env
                s += sin(2 * .pi * f * Float(lt)) * e2 * 0.28
            }
            data[i] = s
        }
        reconnectMono(node: frenzyPlayer, fmt: mono)
        frenzyPlayer.scheduleBuffer(buf)
        if !frenzyPlayer.isPlaying { frenzyPlayer.play() }
    }

    func playGhost() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 0.50
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Eerie descending tone with vibrato — otherworldly ghost feel
        let baseFreq: Float = 440.0
        for i in 0..<Int(fc) {
            let t      = Float(i) / Float(sr)
            let prog   = t / Float(dur)                              // 0→1 over duration
            let freq   = baseFreq * (1.0 - prog * 0.45)             // descend to ~242 Hz
            let vib    = 1.0 + 0.018 * sin(2 * .pi * 6.0 * t)      // 6 Hz vibrato
            let env    = Float(max(0, 1.0 - Double(prog) * 1.1))
            data[i]    = sin(2 * .pi * freq * vib * t) * env * 0.30
        }
        reconnectMono(node: ghostPlayer, fmt: mono)
        ghostPlayer.scheduleBuffer(buf)
        if !ghostPlayer.isPlaying { ghostPlayer.play() }
    }

    private func reconnectMono(node: AVAudioPlayerNode, fmt: AVAudioFormat) {
        if node.outputFormat(forBus: 0).channelCount != fmt.channelCount {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: fmt)
        }
    }

    private func currentEngineTime() -> Double {
        Double(engine.outputNode.lastRenderTime?.sampleTime ?? 0) / 44100.0
    }

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        try? engine.start()
    }
}
