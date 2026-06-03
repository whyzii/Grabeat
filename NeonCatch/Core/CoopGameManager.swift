import SwiftUI
import Combine

@MainActor
class CoopGameManager: ObservableObject {

    // MARK: - Published State

    @Published var notes:        [CoopNoteItem] = []
    @Published var groove:       GrooveState    = GrooveState()
    @Published var timeLeft:     Double         = CoopGameManager.startingTime
    @Published var elapsed:      Double         = 0
    @Published var speedLevel:   Double         = 1.0
    @Published var peakSpeedLevel: Double       = 1.0
    @Published var particles:    [ParticleItem] = []
    @Published var scoreFloats:  [ScoreFloat]   = []
    @Published var lastCatch:    CatchEvent?    = nil
    @Published var lastQuality:  BeatQuality    = .offBeat
    @Published var gameOver:     Bool           = false
    @Published var beatPhase:    Double         = 0

    // Power-up effects
    @Published var speedBoostActive: Bool   = false
    @Published var glitchActive:     Bool   = false
    @Published var blackoutActive:   Bool   = false
    @Published var blackoutPhase:    Double = 0

    // Impact signal
    @Published var impactSignal:     UUID  = UUID()
    @Published var impactFlashColor: Color = .red

    // Combo
    @Published var comboCount: Int = 0
    @Published var peakCombo:  Int = 0

    // DROP
    @Published var dropActive:   Bool   = false
    @Published var dropProgress: Double = 0

    // Peak stats (for end screen)
    @Published var peakGroove: Double = 0

    // Confetti (spawned at DROP)
    @Published var confetti: [ConfettiParticle] = []

    // Tier announcement
    @Published var announcementTier:     GrooveTier? = nil
    @Published var announcementProgress: Double      = 0

    // Stats
    @Published var totalCatches:   Int = 0
    @Published var perfectCatches: Int = 0
    @Published var missCount:      Int = 0

    // Pause state
    @Published var isPaused: Bool = false

    var handsP1: [HandState] = []
    var handsP2: [HandState] = []

    // MARK: - Computed

    var comboMultiplier: Double {
        switch comboCount {
        case ..<5:   return 1.0
        case ..<10:  return 1.5
        case ..<20:  return 2.0
        default:     return 3.0
        }
    }

    var dropCountdownProgress: Double {
        guard !dropActive && dropCooldown <= 0 && groove.level >= 85 else { return 0 }
        return (groove.level - 85) / 15.0
    }

    // MARK: - Private

    private let audioEngine    = AudioEngine()
    private let particleSystem = ParticleSystem()

    private var spawnTimer:      AnyCancellable?
    private var displayLink:     AnyCancellable?
    private var speedBoostTimer: AnyCancellable?
    private var glitchTimer:     AnyCancellable?
    private var blackoutTimer:   AnyCancellable?
    private var bossTimer:       AnyCancellable?

    private var dropCooldown:         Double     = 0
    private var lastTier:             GrooveTier = .cold
    private var announcementTimeLeft: Double     = 0

    static let startingTime: Double = 20.0
    static let maxTime:      Double = 60.0

    /// Set by ContentView to forward bad-note events to PhotoBoothManager.
    var onBadNoteActivated: (() -> Void)?

    private let gridPositions: [CGFloat] = [0.20, 0.33, 0.46, 0.59, 0.72, 0.85]
    private var currentSpawnInterval: Double = 2.2

    private var maxAliveNotes: Int {
        // One extra note slot every 12 s of survival, capped at 12
        return min(12, 5 + Int(elapsed / 12.0))
    }

    private enum SpawnEdge { case right, left, top, bottom }

    // MARK: - Lifecycle

    func startGame() {
        notes = []; particles = []; scoreFloats = []
        groove         = GrooveState()
        timeLeft       = CoopGameManager.startingTime
        elapsed        = 0
        speedLevel     = 1.0
        peakSpeedLevel = 1.0
        totalCatches   = 0; perfectCatches = 0; missCount = 0
        comboCount     = 0; peakCombo = 0; peakGroove = 0
        dropActive     = false; dropProgress = 0; dropCooldown = 0
        lastTier       = .cold
        confetti       = []
        announcementTier = nil; announcementProgress = 0; announcementTimeLeft = 0
        gameOver       = false
        isPaused       = false
        lastCatch      = nil; lastQuality = .offBeat; beatPhase = 0
        speedBoostActive = false; glitchActive = false; blackoutActive = false

        audioEngine.reset()
        audioEngine.startMusic()

        for _ in 0..<3 { spawnNote() }

        armSpawnTimer(interval: spawnInterval())

        bossTimer = Timer.publish(every: 28, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPaused else { return }
                self.spawnBossNote()
            }

        displayLink = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPaused else { return }
                self.update()
            }
    }

    func endGame() {
        cancelAll()
        audioEngine.stopMusic()
        audioEngine.reset()
        gameOver = true
    }

    // MARK: - Pause / Resume

    func pauseGame() {
        guard !gameOver, !isPaused else { return }
        isPaused = true
    }

    func resumeGame() {
        guard isPaused else { return }
        isPaused = false
    }

    // MARK: - Spawn Timer

    private func armSpawnTimer(interval: Double) {
        currentSpawnInterval = interval
        spawnTimer?.cancel()
        spawnTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isPaused else { return }
                self.spawnNote()
                let next = self.spawnInterval()
                if abs(next - self.currentSpawnInterval) > 0.05 { self.armSpawnTimer(interval: next) }
            }
    }

    // Spawn interval tightens from 2.2 s at start to 0.35 s as elapsed grows
    private func spawnInterval() -> Double {
        max(0.35, 2.2 - elapsed * 0.022)
    }

    private func spawnNote() {
        guard notes.filter({ !$0.caught && !$0.missed }).count < maxAliveNotes else { return }
        let edge  = pickEdge()
        let kind  = randomKind()
        let size  = randomSize()
        let shape = noteShape(for: kind)
        // Bake current speedLevel into spawn velocity so late notes are inherently faster
        let speed = CGFloat(1.0 / 4.5) * CGFloat(0.85 + Double.random(in: 0...0.25)) * CGFloat(speedLevel)
        let (pos, vel) = spawnPosVel(edge: edge, speed: speed)
        notes.append(CoopNoteItem(position: pos, velocity: vel,
                                  noteKind: kind, noteSize: size, noteShape: shape))
    }

    /// Maps each NoteKind to its canonical shape — must match NoteSpawner and the tutorial.
    private func noteShape(for kind: NoteKind) -> NoteShape {
        switch kind {
        case .normal:   return Bool.random() ? .hexagon : .square
        case .frenzy:   return .diamond
        case .obstacle: return .circle
        case .trap:     return .triangle
        case .blackout: return .octagon
        }
    }

    private func spawnBossNote() {
        guard groove.level >= 40 else { return }
        guard !notes.contains(where: { $0.isBoss && !$0.caught && !$0.missed }) else { return }
        let edge = pickEdge()
        let (pos, vel) = spawnPosVel(edge: edge,
                                     speed: CGFloat(1.0 / 4.5) * 0.55 * CGFloat(speedLevel))
        var note = CoopNoteItem(position: pos, velocity: vel,
                                noteKind: .frenzy, noteSize: .large, noteShape: .hexagon)
        note.isBoss = true
        notes.append(note)
    }

    private func pickEdge() -> SpawnEdge {
        // Use elapsed as a proxy for game progress (same distribution as before)
        let t = min(1.0, elapsed / 90.0)
        let r = Double.random(in: 0..<1)
        switch t {
        case ..<0.30:
            if r < 0.52 { return .right }
            if r < 0.88 { return .left  }
            return r < 0.94 ? .top : .bottom
        case ..<0.56:
            if r < 0.52 { return .right }
            if r < 0.70 { return .top   }
            if r < 0.86 { return .bottom }
            return .left
        case ..<0.78:
            if r < 0.30 { return .right  }
            if r < 0.55 { return .left   }
            if r < 0.77 { return .top    }
            return .bottom
        default:
            switch r {
            case ..<0.25: return .right
            case ..<0.50: return .left
            case ..<0.75: return .top
            default:      return .bottom
            }
        }
    }

    private func spawnPosVel(edge: SpawnEdge, speed: CGFloat) -> (CGPoint, CGPoint) {
        let slot = freeLanePosition(edge: edge)
        switch edge {
        case .right:  return (CGPoint(x: 1.10,  y: slot),  CGPoint(x: -speed, y: 0))
        case .left:   return (CGPoint(x: -0.10, y: slot),  CGPoint(x:  speed, y: 0))
        case .top:    return (CGPoint(x: slot,  y: -0.10), CGPoint(x: 0,  y:  speed))
        case .bottom: return (CGPoint(x: slot,  y:  1.10), CGPoint(x: 0,  y: -speed))
        }
    }

    private func freeLanePosition(edge: SpawnEdge) -> CGFloat {
        let busy: [CGFloat]
        switch edge {
        case .right:  busy = notes.filter { !$0.caught && !$0.missed && $0.xPos  > 0.80 }.map(\.laneY)
        case .left:   busy = notes.filter { !$0.caught && !$0.missed && $0.xPos  < 0.20 }.map(\.laneY)
        case .top:    busy = notes.filter { !$0.caught && !$0.missed && $0.laneY < 0.20 }.map(\.xPos)
        case .bottom: busy = notes.filter { !$0.caught && !$0.missed && $0.laneY > 0.80 }.map(\.xPos)
        }
        let free = gridPositions.filter { slot in !busy.contains { abs($0 - slot) < 0.08 } }
        return (free.isEmpty ? gridPositions : free).randomElement() ?? 0.5
    }

    private func randomKind() -> NoteKind {
        let r = Double.random(in: 0..<1)
        switch r {
        case ..<0.72: return .normal
        case ..<0.87: return .frenzy
        case ..<0.93: return .obstacle
        case ..<0.97: return .trap
        default:      return .blackout
        }
    }

    private func randomSize() -> NoteSize {
        // Shift toward smaller notes as time progresses (harder to catch at speed)
        let progress = min(1.0, elapsed / 60.0)
        let r = Double.random(in: 0..<1)
        let tinyThresh   = 0.10 + 0.20 * progress
        let smallThresh  = tinyThresh  + 0.15 + 0.25 * progress
        let mediumThresh = smallThresh + 0.40 - 0.15 * progress
        switch r {
        case ..<tinyThresh:   return .tiny
        case ..<smallThresh:  return .small
        case ..<mediumThresh: return .medium
        default:              return .large
        }
    }

    // MARK: - Update Loop (60 fps)

    private func update() {
        let dt = 1.0 / 60.0

        elapsed    += dt
        speedLevel  = 1.0 + elapsed * 0.020   // +2 % per second survived
        peakSpeedLevel = max(peakSpeedLevel, speedLevel)

        // Timer drains faster as speed increases — creates an escalating pressure curve
        let drainRate = 1.0 + (speedLevel - 1.0) * 0.5
        timeLeft -= dt * drainRate
        if timeLeft <= 0 { endGame(); return }

        groove.passiveDecay()
        beatPhase  = audioEngine.currentBeatPhase()
        peakGroove = max(peakGroove, groove.level)

        // Tier crossing → crowd sounds + announcements
        let currentTier = groove.tier
        if currentTier.rawValue > lastTier.rawValue {
            switch currentTier {
            case .hot:   audioEngine.playCrowdCheer(); showAnnouncement(for: .hot)
            case .ultra: audioEngine.playCrowdDrop();  showAnnouncement(for: .ultra)
            default: break
            }
        }
        lastTier = currentTier

        tickConfetti(dt: dt)
        tickAnnouncement(dt: dt)

        // DROP
        if dropCooldown > 0 { dropCooldown -= dt }
        if groove.level >= 99.5 && dropCooldown <= 0 && !dropActive { triggerDrop() }
        if dropActive {
            dropProgress += dt / 2.0
            if dropProgress >= 1.0 {
                dropActive   = false
                dropProgress = 0
                dropCooldown = 35.0
                for _ in 0..<4 { spawnNote() }
                audioEngine.playCrowdCheer()
            }
        }

        // speedBoostActive adds a further 1.4× on all notes for 3 s when obstacle is caught
        let speedMult: CGFloat = speedBoostActive ? 1.4 : 1.0
        tickNotes(dt: dt, speedMult: speedMult)
        particleSystem.tick(particles: &particles)
        tickScoreFloats(dt: dt)
        checkCatches()
        audioEngine.updateCoopGroove(groove.level)
    }

    // MARK: - Note Tick

    private func tickNotes(dt: Double, speedMult: CGFloat) {
        var toRemove: [UUID] = []
        for i in notes.indices {
            if notes[i].caught {
                notes[i].catchProgress += dt * 4
                if notes[i].catchProgress >= 1 { toRemove.append(notes[i].id) }
            } else if notes[i].missed {
                toRemove.append(notes[i].id)
            } else if !dropActive {
                notes[i].position.x += notes[i].velocity.x * speedMult * CGFloat(dt)
                notes[i].position.y += notes[i].velocity.y * speedMult * CGFloat(dt)
                let p = notes[i].position
                if p.x < -0.14 || p.x > 1.14 || p.y < -0.14 || p.y > 1.14 {
                    notes[i].missed = true
                    if notes[i].isBoss {
                        groove.level = max(0, groove.level - 8)
                        timeLeft = max(0.1, timeLeft - 3.0)
                        spawnMissLabel(at: p, text: "DUO MISSED! -3s")
                    } else if notes[i].isGood {
                        missCount += 1
                        groove.applyMissedNote()
                        comboCount = 0
                        timeLeft = max(0.1, timeLeft - 0.5)
                        spawnMissLabel(at: p, text: "MISS! -0.5s")
                    } else {
                        groove.applyDodgedBad()
                    }
                }
            }
        }
        notes.removeAll { toRemove.contains($0.id) }
    }

    private func spawnMissLabel(at pos: CGPoint, text: String = "MISS!") {
        let cx = max(0.05, min(0.95, pos.x))
        let cy = max(0.10, min(0.90, pos.y))
        scoreFloats.append(ScoreFloat(
            position: CGPoint(x: cx, y: cy),
            target:   CGPoint(x: cx, y: max(0.05, cy - 0.10)),
            points: 0, color: .red, life: 1.2, scale: 0.5,
            beatLabel: text, beatLabelColor: .red
        ))
    }

    private func tickScoreFloats(dt: Double) {
        for i in scoreFloats.indices {
            scoreFloats[i].position.x += (scoreFloats[i].target.x - scoreFloats[i].position.x) * 0.06
            scoreFloats[i].position.y += (scoreFloats[i].target.y - scoreFloats[i].position.y) * 0.06
            if scoreFloats[i].scale < 1.0 { scoreFloats[i].scale = min(scoreFloats[i].scale + dt * 4, 1.0) }
            scoreFloats[i].life -= dt * 0.8
        }
        scoreFloats.removeAll { $0.life <= 0 }
    }

    // MARK: - Catch Detection

    private func checkCatches() {
        for i in notes.indices {
            guard !notes[i].caught, !notes[i].missed else { continue }

            if notes[i].isBoss {
                let bossR = notes[i].catchRadius * 2.2
                let p1 = handsP1.contains { $0.isActive && $0.isPinching &&
                    hypot($0.position.x - notes[i].xPos, $0.position.y - notes[i].laneY) < bossR }
                let p2 = handsP2.contains { $0.isActive && $0.isPinching &&
                    hypot($0.position.x - notes[i].xPos, $0.position.y - notes[i].laneY) < bossR }
                if p1 && p2 { notes[i].caught = true; handleBossCatch(notes[i]) }
                continue
            }

            let pinching = (handsP1 + handsP2).filter { $0.isActive && $0.isPinching }
            for hand in pinching {
                let dx = hand.position.x - notes[i].xPos
                let dy = hand.position.y - notes[i].laneY
                guard sqrt(dx*dx + dy*dy) < notes[i].catchRadius else { continue }
                notes[i].caught = true
                if notes[i].isBad { handleBadCatch(notes[i]) } else { handleGoodCatch(i) }
                break
            }
        }
    }

    // MARK: - Catch Handlers

    private func handleGoodCatch(_ i: Int) {
        let quality = audioEngine.beatQuality()
        totalCatches += 1
        if quality == .perfect { perfectCatches += 1 }

        comboCount += 1
        if comboCount > peakCombo  { peakCombo = comboCount }
        if comboCount == 10 { audioEngine.playCrowdCheer() }
        let mult = comboMultiplier

        let isFrenzy = notes[i].noteKind == .frenzy

        // Time gain is fixed (no combo mult) to keep the clock fair under high combos
        let timeGain: Double
        if isFrenzy {
            timeGain = 6.0
        } else {
            switch quality {
            case .perfect: timeGain = 4.0
            case .good:    timeGain = 2.0
            case .offBeat: timeGain = 0.8
            }
        }
        timeLeft = min(timeLeft + timeGain, CoopGameManager.maxTime)

        // Groove is combo-multiplied — drives visuals and audio only
        if isFrenzy {
            groove.level = min(100, groove.level + 9.0 * mult)
        } else {
            let grooveGain: Double
            switch quality {
            case .perfect: grooveGain = 5.5
            case .good:    grooveGain = 2.5
            case .offBeat: grooveGain = 0.8
            }
            groove.level = min(100, groove.level + grooveGain * mult)
        }

        let gold = Color(red: 1.0, green: 0.92, blue: 0.0)
        let noteColor = notes[i].glowColor
        let displayColor: Color = isFrenzy ? gold : (quality == .perfect ? .yellow : noteColor)

        particleSystem.spawnPixelBurst(at: notes[i].position,
                                       color: displayColor, quality: quality, into: &particles)

        // Float shows time gained + beat quality
        let timeStr = "+\(String(format: "%.1f", timeGain))s"
        let label: String
        if isFrenzy {
            let suffix = mult > 1 ? " ×\(String(format: "%.1g", mult))" : ""
            label = "★ \(timeStr)\(suffix)"
        } else if quality == .perfect {
            label = "\(timeStr)  PERFECT ★"
        } else if quality == .good {
            label = "\(timeStr)  GOOD ♪"
        } else {
            label = timeStr
        }

        scoreFloats.append(ScoreFloat(
            position: notes[i].position,
            target:   CGPoint(x: notes[i].xPos, y: notes[i].laneY - 0.12),
            points: 0, color: displayColor, life: 1.4, scale: 0.5,
            beatLabel: label, beatLabelColor: displayColor
        ))

        lastCatch   = CatchEvent(position: notes[i].position, color: displayColor)
        lastQuality = quality

        if isFrenzy { audioEngine.playFrenzy() } else { audioEngine.playCatch(player: 1, quality: quality) }
    }

    private func handleBadCatch(_ note: CoopNoteItem) {
        groove.applyBadCatch()
        if comboCount > 2 {
            let cx = max(0.05, min(0.95, note.xPos))
            let cy = max(0.10, min(0.90, note.laneY + 0.08))
            scoreFloats.append(ScoreFloat(
                position: CGPoint(x: cx, y: cy),
                target:   CGPoint(x: cx, y: max(0.05, cy - 0.08)),
                points: 0, color: .red, life: 1.0, scale: 0.5,
                beatLabel: "COMBO BREAK!", beatLabelColor: .red
            ))
        }
        comboCount = 0
        particleSystem.spawnGlitchBurst(at: note.position, color: note.glowColor, into: &particles)

        let timePenalty = 2.5
        timeLeft = max(0.1, timeLeft - timePenalty)

        let (label, labelColor, flashColor): (String, Color, Color)
        switch note.noteKind {
        case .obstacle:
            label = "❄  -\(String(format: "%.1f", timePenalty))s  SPEED UP!"
            labelColor = Color(red: 0.4, green: 0.85, blue: 1.0)
            flashColor = Color(red: 0.3, green: 0.75, blue: 1.0)
        case .trap:
            label = "⚡  -\(String(format: "%.1f", timePenalty))s  GLITCH!"
            labelColor = Color(red: 1.0, green: 0.2, blue: 0.35)
            flashColor = Color(red: 0.9, green: 0.1, blue: 0.25)
        case .blackout:
            label = "⊘  -\(String(format: "%.1f", timePenalty))s  BLACKOUT!"
            labelColor = .white; flashColor = .white
        default:
            label = "!"; labelColor = .red; flashColor = .red
        }
        scoreFloats.append(ScoreFloat(
            position: note.position,
            target:   CGPoint(x: note.xPos, y: note.laneY - 0.12),
            points: 0, color: labelColor, life: 1.6, scale: 0.5,
            beatLabel: label, beatLabelColor: labelColor
        ))
        lastCatch        = CatchEvent(position: note.position, color: note.glowColor)
        impactFlashColor = flashColor
        impactSignal     = UUID()

        switch note.noteKind {
        case .obstacle: audioEngine.playFreeze();   activateSpeedBoost()
        case .trap:     audioEngine.playGlitch();   activateGlitch()
        case .blackout: audioEngine.playBlackout(); activateBlackout()
        default: break
        }
    }

    private func handleBossCatch(_ note: CoopNoteItem) {
        let timeGain = 10.0
        timeLeft   = min(timeLeft + timeGain, CoopGameManager.maxTime)
        groove.level   = min(100, groove.level + 22)
        comboCount    += 3
        if comboCount > peakCombo { peakCombo = comboCount }
        totalCatches  += 1; perfectCatches += 1
        particleSystem.spawnGlitchBurst(at: note.position, color: .yellow, into: &particles)
        particleSystem.spawnPixelBurst(at: note.position, color: .yellow, quality: .perfect, into: &particles)
        scoreFloats.append(ScoreFloat(
            position: note.position,
            target:   CGPoint(x: 0.5, y: 0.15),
            points: 0, color: .yellow, life: 2.2, scale: 0.4,
            beatLabel: "★  DUO CATCH  +\(Int(timeGain))s  ★", beatLabelColor: .yellow
        ))
        lastCatch        = CatchEvent(position: note.position, color: .yellow)
        impactFlashColor = .yellow
        impactSignal     = UUID()
        audioEngine.playCrowdCheer()
    }

    // MARK: - DROP

    private func triggerDrop() {
        dropActive   = true
        dropProgress = 0
        groove.level = 100
        // Reward hitting DROP with a time bonus
        timeLeft = min(timeLeft + 5.0, CoopGameManager.maxTime)
        impactFlashColor = .yellow
        impactSignal     = UUID()
        audioEngine.playCrowdDrop()
        spawnConfetti()
    }

    private func spawnConfetti() {
        let palette: [Color] = [
            .cyan, .magenta, .yellow, .white,
            Color(red: 1.0, green: 0.5, blue: 0.0),
            Color(red: 0.6, green: 0.0, blue: 1.0),
            Color(red: 0.2, green: 1.0, blue: 0.4)
        ]
        for _ in 0..<130 {
            confetti.append(ConfettiParticle(
                x:             CGFloat.random(in: 0...1),
                y:             CGFloat.random(in: -0.20...(-0.02)),
                vx:            CGFloat.random(in: -0.08...0.08),
                vy:            CGFloat.random(in: 0.06...0.22),
                rotation:      CGFloat.random(in: 0...(.pi * 2)),
                rotationSpeed: CGFloat.random(in: -6...6),
                color:         palette.randomElement()!,
                life:          Double.random(in: 0.8...1.0),
                size:          CGFloat.random(in: 7...14)
            ))
        }
    }

    private func tickConfetti(dt: Double) {
        guard !confetti.isEmpty else { return }
        for i in confetti.indices {
            confetti[i].vy       += 0.32 * CGFloat(dt)
            confetti[i].x        += confetti[i].vx * CGFloat(dt)
            confetti[i].y        += confetti[i].vy * CGFloat(dt)
            confetti[i].rotation += confetti[i].rotationSpeed * CGFloat(dt)
            confetti[i].life     -= dt * 0.38
        }
        confetti.removeAll { $0.life <= 0 || $0.y > 1.2 }
    }

    private func showAnnouncement(for tier: GrooveTier) {
        announcementTier     = tier
        announcementProgress = 0
        announcementTimeLeft = 1.6
    }

    private func tickAnnouncement(dt: Double) {
        guard announcementTimeLeft > 0 else { return }
        announcementTimeLeft -= dt
        announcementProgress  = max(0, 1.0 - announcementTimeLeft / 1.6)
        if announcementTimeLeft <= 0 { announcementTier = nil; announcementProgress = 0 }
    }

    // MARK: - Power-Up Effects

    private func activateSpeedBoost() {
        speedBoostActive = true; speedBoostTimer?.cancel()
        speedBoostTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.speedBoostActive = false; self?.speedBoostTimer?.cancel() }
    }

    private func activateGlitch() {
        glitchActive = true; glitchTimer?.cancel()
        glitchTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.glitchActive = false; self?.glitchTimer?.cancel() }
        onBadNoteActivated?()
    }

    private func activateBlackout() {
        blackoutActive = true; blackoutPhase = 0; blackoutTimer?.cancel()
        blackoutTimer = Timer.publish(every: BlackoutState.totalDuration, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.blackoutActive = false; self?.blackoutTimer?.cancel() }
        onBadNoteActivated?()
    }

    private func cancelAll() {
        spawnTimer?.cancel(); displayLink?.cancel()
        speedBoostTimer?.cancel(); glitchTimer?.cancel(); blackoutTimer?.cancel()
        bossTimer?.cancel()
    }
}
