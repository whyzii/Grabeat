import SwiftUI
import Combine

// MARK: - Game Manager
// Owns the game state machine, the 60 fps update loop, scoring, and catch detection.
// Delegates note spawning to NoteSpawner and particle effects to ParticleSystem.

@MainActor
class GameManager: ObservableObject {

    // MARK: - Published State

    @Published var state:      GameState  = .start
    @Published var notes:      [NoteItem] = []
    @Published var scoreP1:    Int = 0
    @Published var scoreP2:    Int = 0
    @Published var timeLeft:   Int = 60
    @Published var particles:  [ParticleItem] = []
    @Published var scoreFloats:[ScoreFloat]   = []
    @Published var lastCatch:  CatchEvent?    = nil
    @Published var lastBeatQuality: BeatQuality = .offBeat

    // Power-up states
    @Published var freezeP1:     FreezeState     = FreezeState()
    @Published var freezeP2:     FreezeState     = FreezeState()
    @Published var trapGlitchP1: TrapGlitchState = TrapGlitchState()
    @Published var trapGlitchP2: TrapGlitchState = TrapGlitchState()
    @Published var frenzyP1:     FrenzyState     = FrenzyState()
    @Published var frenzyP2:     FrenzyState     = FrenzyState()
    @Published var blackout:     BlackoutState   = BlackoutState()

    // Pause state
    @Published var isPaused: Bool = false

    // Hand state forwarded from GameView (not @Published — avoids re-renders)
    var handsP1: [HandState] = []
    var handsP2: [HandState] = []

    // True when the pending / active game is co-op mode.
    var isCoopMode: Bool = false

    // Photo consent: nil = not yet asked, true = user accepted, false = user declined.
    // Reset to nil each time a new mode is chosen so the prompt re-fires every game.
    @Published var photoConsentGiven: Bool? = nil

    // True when the tutorial was opened via the "?" shortcut (standalone).
    // False when it plays automatically on first launch.
    var tutorialIsStandalone: Bool = false

    // MARK: - Photo Booth Hook
    // ContentView sets this closure so GameManager can notify PhotoBoothManager
    // whenever an obstacle note is activated — without creating a direct dependency.
    var onObstacleActivated: (() -> Void)?

    // MARK: - Private

    private var gameTimer:    AnyCancellable?
    private var noteSpawner_: AnyCancellable?
    private var displayLink:  AnyCancellable?

    private let audioEngine    = AudioEngine()
    private let noteSpawner    = NoteSpawner()
    private let particleSystem = ParticleSystem()

    static let gameDurationSeconds = 60
    private let gameDuration       = GameManager.gameDurationSeconds
    private let maxNotesPerPlayer  = 4

    // MARK: - UserDefaults keys for tutorial-seen flags
    private static let versusSeenKey = "GraBeat.versusTutorialSeen"
    private static let coopSeenKey   = "GraBeat.coopTutorialSeen"

    // MARK: - Lifecycle

    func beginTutorial() {
        isCoopMode = false
        tutorialIsStandalone = false
        cancelTimers()
        resetTransientState()
        // Show tutorial only the very first time; jump straight to calibration after that.
        if UserDefaults.standard.bool(forKey: Self.versusSeenKey) {
            state = .calibrating
        } else {
            state = .tutorial
        }
    }

    func beginCalibration() {
        isCoopMode = false
        cancelTimers()
        resetTransientState()
        // Mark the versus tutorial as seen so it never shows again.
        UserDefaults.standard.set(true, forKey: Self.versusSeenKey)
        state = .calibrating
    }

    func beginCoopTutorial() {
        isCoopMode = true
        tutorialIsStandalone = false
        cancelTimers()
        resetTransientState()
        // Show tutorial only the very first time; jump straight to calibration after that.
        if UserDefaults.standard.bool(forKey: Self.coopSeenKey) {
            state = .calibrating
        } else {
            state = .coopTutorial
        }
    }

    func beginCoopCalibration() {
        isCoopMode = true
        cancelTimers()
        resetTransientState()
        // Mark the co-op tutorial as seen so it never shows again.
        UserDefaults.standard.set(true, forKey: Self.coopSeenKey)
        state = .calibrating
    }

    func startGame() {
        scoreP1 = 0; scoreP2 = 0
        timeLeft = gameDuration
        handsP1  = []; handsP2 = []
        resetTransientState()
        audioEngine.reset()
        audioEngine.startMusic()
        state = .playing

        for _ in 0..<3 {
            notes.append(noteSpawner.spawnNote(player: 1, existingNotes: notes))
            notes.append(noteSpawner.spawnNote(player: 2, existingNotes: notes))
        }

        gameTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPaused else { return }
                self.timeLeft -= 1
                if self.timeLeft <= 0 { self.endGame() }
            }

        noteSpawner_ = Timer.publish(every: 0.9, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.state == .playing, !self.isPaused else { return }
                self.tickNoteSpawner()
            }

        displayLink = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
    }

    /// Transitions to the Photo Booth review screen.
    /// Called automatically when the timer reaches zero.
    func endGame() {
        cancelTimers()
        audioEngine.stopMusic()
        state = .winnerAnnouncement
    }

    /// Called by WinnerAnnouncementView when its animation finishes (or the player skips).
    func proceedToPhotoBooth() {
        // Skip the photo booth entirely if the player declined photo consent.
        if photoConsentGiven == false {
            state = .end
        } else {
            state = .photoBooth
        }
    }

    /// Advances from Photo Booth to the End Screen.
    /// Called by PhotoBoothReviewScreen's Continue button.
    func showEndScreen() {
        state = .end
    }

    func resetToStart() {
        cancelTimers()
        audioEngine.stopMusic()
        resetTransientState()
        photoConsentGiven = nil
        state = .start
    }

    // MARK: - Note Spawner Tick
    // Spawn probabilities per tick (every 0.9 s):
    //   Obstacle: ~2.5 % → one every ~36 s on average
    //   Trap:     ~2.0 % → one every ~45 s on average
    //   Frenzy:   ~2.5 % → one every ~36 s on average
    //   Blackout: ~2.0 % → one every ~45 s on average

    private func tickNoteSpawner() {
        for player in [1, 2] {
            if Double.random(in: 0..<1) < 0.025 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .obstacle && !$0.caught }
                if !alreadyHas {
                    notes.append(noteSpawner.spawnObstacleNote(player: player, existingNotes: notes))
                }
            }
            if Double.random(in: 0..<1) < 0.020 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .trap && !$0.caught }
                if !alreadyHas {
                    notes.append(noteSpawner.spawnTrapNote(player: player, existingNotes: notes))
                }
            }
            if Double.random(in: 0..<1) < 0.025 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .frenzy && !$0.caught }
                if !alreadyHas {
                    notes.append(noteSpawner.spawnFrenzyNote(player: player, existingNotes: notes))
                }
            }
            if Double.random(in: 0..<1) < 0.020 {
                let alreadyHas = notes.contains { $0.player == player && $0.noteKind == .blackout && !$0.caught }
                if !alreadyHas {
                    notes.append(noteSpawner.spawnBlackoutNote(player: player, existingNotes: notes))
                }
            }
        }

        let alive1 = notes.filter { $0.player == 1 && !$0.caught }.count
        let alive2 = notes.filter { $0.player == 2 && !$0.caught }.count
        if alive1 < maxNotesPerPlayer {
            notes.append(noteSpawner.spawnNote(player: 1, existingNotes: notes))
        }
        if alive2 < maxNotesPerPlayer {
            notes.append(noteSpawner.spawnNote(player: 2, existingNotes: notes))
        }
    }

    /// Always shows the Versus tutorial regardless of the seen flag.
    /// Used by the "?" button on the start screen.
    func forceTutorial() {
        isCoopMode = false
        tutorialIsStandalone = true
        cancelTimers()
        resetTransientState()
        state = .tutorial
    }

    /// Always shows the Co-op tutorial regardless of the seen flag.
    func forceCoopTutorial() {
        isCoopMode = true
        tutorialIsStandalone = true
        cancelTimers()
        resetTransientState()
        state = .coopTutorial
    }

    // MARK: - Pause / Resume

    func pauseGame() {
        guard state == .playing, !isPaused else { return }
        isPaused = true
    }

    func resumeGame() {
        guard isPaused else { return }
        isPaused = false
    }

    // MARK: - Update Loop (60 fps)

    private func update() {
        guard !isPaused else { return }
        let dt = 1.0 / 60.0

        tickPowerUpTimers(dt: dt)
        tickNotes(dt: dt)
        particleSystem.tick(particles: &particles)
        tickScoreFloats(dt: dt)

        if !freezeP1.active { checkCatch(hands: handsP1, player: 1) }
        if !freezeP2.active { checkCatch(hands: handsP2, player: 2) }
    }

    // MARK: - Power-Up Timer Ticks

    private func tickPowerUpTimers(dt: Double) {
        if freezeP1.active {
            freezeP1.timeLeft   -= dt
            freezeP1.glitchPhase = (freezeP1.glitchPhase + dt * 9).truncatingRemainder(dividingBy: 1)
            if freezeP1.timeLeft <= 0 { freezeP1 = FreezeState() }
        }
        if freezeP2.active {
            freezeP2.timeLeft   -= dt
            freezeP2.glitchPhase = (freezeP2.glitchPhase + dt * 9).truncatingRemainder(dividingBy: 1)
            if freezeP2.timeLeft <= 0 { freezeP2 = FreezeState() }
        }
        if trapGlitchP1.active {
            trapGlitchP1.timeLeft   -= dt
            trapGlitchP1.glitchPhase = (trapGlitchP1.glitchPhase + dt * 11).truncatingRemainder(dividingBy: 1)
            if trapGlitchP1.timeLeft <= 0 { trapGlitchP1 = TrapGlitchState() }
        }
        if trapGlitchP2.active {
            trapGlitchP2.timeLeft   -= dt
            trapGlitchP2.glitchPhase = (trapGlitchP2.glitchPhase + dt * 11).truncatingRemainder(dividingBy: 1)
            if trapGlitchP2.timeLeft <= 0 { trapGlitchP2 = TrapGlitchState() }
        }
        if frenzyP1.active { frenzyP1.timeLeft -= dt; if frenzyP1.timeLeft <= 0 { frenzyP1 = FrenzyState() } }
        if frenzyP2.active { frenzyP2.timeLeft -= dt; if frenzyP2.timeLeft <= 0 { frenzyP2 = FrenzyState() } }
        if blackout.active {
            blackout.timeLeft -= dt
            blackout.phase     = (blackout.phase + dt * 1.0).truncatingRemainder(dividingBy: 1)
            if blackout.timeLeft <= 0 { blackout = BlackoutState() }
        }
    }

    private func tickNotes(dt: Double) {
        var toRemove: [UUID] = []
        for i in notes.indices {
            if notes[i].caught {
                notes[i].catchProgress += dt * 4
                if notes[i].catchProgress >= 1 { toRemove.append(notes[i].id) }
            } else {
                // Notes in a frozen player's zone do not decay
                let playerFrozen = notes[i].player == 1 ? freezeP1.active : freezeP2.active
                if !playerFrozen { notes[i].life -= notes[i].decayRate }
                if notes[i].life <= 0 { toRemove.append(notes[i].id) }
            }
        }
        notes.removeAll { toRemove.contains($0.id) }
    }

    private func tickScoreFloats(dt: Double) {
        for i in scoreFloats.indices {
            scoreFloats[i].position.x += (scoreFloats[i].target.x - scoreFloats[i].position.x) * 0.06
            scoreFloats[i].position.y += (scoreFloats[i].target.y - scoreFloats[i].position.y) * 0.06
            if scoreFloats[i].scale < 1.0 { scoreFloats[i].scale = min(scoreFloats[i].scale + dt * 4, 1.0) }
            scoreFloats[i].life -= dt * 0.75
        }
        scoreFloats.removeAll { $0.life <= 0 }
    }

    // MARK: - Catch Detection

    private func checkCatch(hands: [HandState], player: Int) {
        let pinching = hands.filter { h in
            h.isActive && h.isPinching &&
            (player == 1 ? h.position.x <= 0.5 : h.position.x >= 0.5)
        }
        guard !pinching.isEmpty else { return }

        for i in notes.indices {
            guard notes[i].player == player, !notes[i].caught, notes[i].life > 0 else { continue }
            for hand in pinching {
                let dx = hand.position.x - notes[i].position.x
                let dy = hand.position.y - notes[i].position.y
                guard sqrt(dx * dx + dy * dy) < notes[i].noteSize.catchRadius else { continue }
                notes[i].caught = true
                switch notes[i].noteKind {
                case .obstacle: handleObstacleCatch(byPlayer: player, at: notes[i].position)
                case .trap:     handleTrapCatch(byPlayer: player, at: notes[i].position)
                case .frenzy:   handleFrenzyCatch(byPlayer: player, at: notes[i].position)
                case .blackout: handleBlackoutCatch(byPlayer: player, at: notes[i].position)
                case .normal:   handleNormalCatch(noteIndex: i, player: player)
                }
                break
            }
        }
    }

    // MARK: - Catch Handlers

    private func handleNormalCatch(noteIndex i: Int, player: Int) {
        let quality     = audioEngine.beatQuality()
        let frenzyMult  = (player == 1 ? frenzyP1.active : frenzyP2.active) ? 2.0 : 1.0
        let bonusPoints = Int(Double(notes[i].points) * quality.bonusMultiplier * frenzyMult)

        if player == 1 { scoreP1 += bonusPoints } else { scoreP2 += bonusPoints }

        particleSystem.spawnPixelBurst(at: notes[i].position, color: notes[i].glowColor,
                                       quality: quality, into: &particles)
        spawnScoreFloat(at: notes[i].position, points: bonusPoints,
                        color: notes[i].glowColor, player: player, quality: quality)
        lastCatch       = CatchEvent(position: notes[i].position, color: notes[i].glowColor)
        lastBeatQuality = quality
        audioEngine.playCatch(player: player, quality: quality)
    }

    private func handleObstacleCatch(byPlayer player: Int, at pos: CGPoint) {
        let opponent = player == 1 ? 2 : 1
        if opponent == 1 {
            freezeP1 = FreezeState(active: true, timeLeft: FreezeState.duration, glitchPhase: 0)
        } else {
            freezeP2 = FreezeState(active: true, timeLeft: FreezeState.duration, glitchPhase: 0)
        }
        let iceColor = Color(red: 0.4, green: 0.85, blue: 1.0)
        particleSystem.spawnIceBurst(at: pos, color: iceColor, into: &particles)
        let oppCentreX: CGFloat = opponent == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: oppCentreX, y: 0.55),
            target:   CGPoint(x: oppCentreX, y: 0.30),
            points: 0, color: iceColor, life: 1.6, scale: 0.5,
            beatLabel: "❄ FROZEN!", beatLabelColor: iceColor
        ))
        lastCatch = CatchEvent(position: pos, color: iceColor)
        audioEngine.playFreeze()

        // Notify Photo Booth to capture a moment when an obstacle is activated.
        onObstacleActivated?()
    }

    private func handleTrapCatch(byPlayer player: Int, at pos: CGPoint) {
        if player == 1 {
            trapGlitchP1 = TrapGlitchState(active: true, timeLeft: TrapGlitchState.duration, glitchPhase: 0)
        } else {
            trapGlitchP2 = TrapGlitchState(active: true, timeLeft: TrapGlitchState.duration, glitchPhase: 0)
        }
        let crimson = Color(red: 0.86, green: 0.08, blue: 0.24)
        particleSystem.spawnGlitchBurst(at: pos, color: crimson, into: &particles)
        let cx: CGFloat = player == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: cx, y: 0.55),
            target:   CGPoint(x: cx, y: 0.30),
            points: 0, color: crimson, life: 1.6, scale: 0.5,
            beatLabel: "⚡ GLITCHED!", beatLabelColor: crimson
        ))
        lastCatch = CatchEvent(position: pos, color: crimson)
        audioEngine.playGlitch()
    }

    private func handleFrenzyCatch(byPlayer player: Int, at pos: CGPoint) {
        if player == 1 {
            frenzyP1 = FrenzyState(active: true, timeLeft: FrenzyState.duration)
        } else {
            frenzyP2 = FrenzyState(active: true, timeLeft: FrenzyState.duration)
        }
        let gold = Color(red: 1.0, green: 0.92, blue: 0.0)
        particleSystem.spawnGlitchBurst(at: pos, color: gold, into: &particles)
        let cx: CGFloat = player == 1 ? 0.25 : 0.75
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: cx, y: 0.55),
            target:   CGPoint(x: cx, y: 0.30),
            points: 0, color: gold, life: 1.6, scale: 0.5,
            beatLabel: "★ FRENZY!", beatLabelColor: gold
        ))
        lastCatch = CatchEvent(position: pos, color: gold)
        audioEngine.playFrenzy()
    }

    private func handleBlackoutCatch(byPlayer player: Int, at pos: CGPoint) {
        let opponent = player == 1 ? 2 : 1
        if player   == 1 { scoreP1 = max(0, scoreP1 - 1000) } else { scoreP2 = max(0, scoreP2 - 1000) }
        if opponent == 1 { scoreP1 = max(0, scoreP1 - 2000) } else { scoreP2 = max(0, scoreP2 - 2000) }

        blackout = BlackoutState(active: true, timeLeft: BlackoutState.totalDuration, phase: 0)
        particleSystem.spawnGlitchBurst(at: pos, color: .white, into: &particles)

        let catcherCx: CGFloat = player == 1 ? 0.25 : 0.75
        let silver = Color(red: 0.75, green: 0.75, blue: 0.85)
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: catcherCx, y: 0.55),
            target:   CGPoint(x: catcherCx, y: 0.30),
            points: 0, color: silver, life: 1.6, scale: 0.5,
            beatLabel: "-1000", beatLabelColor: silver
        ))
        let oppCx: CGFloat = player == 1 ? 0.75 : 0.25
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: oppCx, y: 0.55),
            target:   CGPoint(x: oppCx, y: 0.30),
            points: 0, color: .white, life: 1.8, scale: 0.5,
            beatLabel: "⊘ BLACKOUT!", beatLabelColor: .white
        ))
        lastCatch = CatchEvent(position: pos, color: .white)
        audioEngine.playBlackout()
    }

    // MARK: - Score Float Helper

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

    // MARK: - Helpers

    private func cancelTimers() {
        gameTimer?.cancel(); noteSpawner_?.cancel(); displayLink?.cancel()
    }

    private func resetTransientState() {
        isPaused     = false
        notes        = []; particles  = []; scoreFloats = []; lastCatch = nil
        freezeP1     = FreezeState();     freezeP2     = FreezeState()
        trapGlitchP1 = TrapGlitchState(); trapGlitchP2 = TrapGlitchState()
        frenzyP1     = FrenzyState();     frenzyP2     = FrenzyState()
        blackout     = BlackoutState()
    }
}

