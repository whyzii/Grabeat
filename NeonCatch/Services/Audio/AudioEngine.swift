import AVFoundation

// MARK: - Audio Engine
// Manages all game audio: background music playback and synthesised sound effects.
// All public methods are safe to call from the main thread.

class AudioEngine {

    // MARK: - Nodes

    private let engine          = AVAudioEngine()
    private let musicPlayer     = AVAudioPlayerNode()
    private let catchPlayer     = AVAudioPlayerNode()
    private let freezePlayer    = AVAudioPlayerNode()
    private let glitchPlayer    = AVAudioPlayerNode()
    private let frenzyPlayer    = AVAudioPlayerNode()
    private let blackoutPlayer  = AVAudioPlayerNode()
    private let grooveArpPlayer = AVAudioPlayerNode()
    private let crowdPlayer     = AVAudioPlayerNode()
    // Sits between musicPlayer and the mixer — changes playback speed without affecting pitch
    private let timePitch       = AVAudioUnitTimePitch()
    private let format:         AVAudioFormat

    // Co-op groove state
    private var currentGrooveTier: Int   = 0
    private var grooveArpBuffer: AVAudioPCMBuffer?

    // Tempo rate: smoothly interpolated toward targetRate each update call
    private var currentRate: Float = 1.0
    private var targetRate:  Float = 1.0

    // MARK: - Beat tracking

    /// Song BPM — used for beat-quality detection on each catch.
    private let bpm: Double = 123.046875
    private var beatInterval: Double { 60.0 / bpm }

    private var musicStartHostTime: Double = 0
    private var musicIsPlaying = false
    private var musicBuffer:    AVAudioPCMBuffer?
    private var interruptionObserver: Any?

    // MARK: - Init

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

        engine.attach(timePitch)
        [musicPlayer, catchPlayer, freezePlayer, glitchPlayer, frenzyPlayer, blackoutPlayer, grooveArpPlayer, crowdPlayer]
            .forEach { engine.attach($0) }

        // Music chain: musicPlayer → timePitch → mainMixer
        engine.connect(musicPlayer,    to: timePitch,            format: nil)
        engine.connect(timePitch,      to: engine.mainMixerNode, format: nil)
        // SFX bypass timePitch
        [catchPlayer, freezePlayer, glitchPlayer, frenzyPlayer, blackoutPlayer, grooveArpPlayer, crowdPlayer]
            .forEach { engine.connect($0, to: engine.mainMixerNode, format: nil) }

        try? engine.start()
        grooveArpBuffer = buildGrooveArpBuffer()

        if let url  = Bundle.main.url(forResource: "Midnight_Service", withExtension: "mp3"),
           let file = try? AVAudioFile(forReading: url) {
            let frameCount = AVAudioFrameCount(file.length)
            if let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                          frameCapacity: frameCount) {
                try? file.read(into: buf)
                musicBuffer = buf
            }
        }

        // AVAudioSession interruptions are iOS-only.
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

    deinit {
        if let obs = interruptionObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Music

    func reset() {
        [musicPlayer, catchPlayer, freezePlayer, glitchPlayer, frenzyPlayer, blackoutPlayer, grooveArpPlayer, crowdPlayer]
            .forEach { $0.stop() }
        musicIsPlaying     = false
        musicStartHostTime = 0
        currentGrooveTier  = 0
        currentRate        = 1.0
        targetRate         = 1.0
        timePitch.rate     = 1.0
    }

    func startMusic() {
        guard let buf = musicBuffer else { return }
        ensureEngineRunning()
        musicPlayer.stop()
        musicPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        musicPlayer.play()
        musicIsPlaying    = true
        musicStartHostTime = currentEngineTime()
    }

    func stopMusic() {
        musicPlayer.stop()
        musicIsPlaying = false
    }

    // MARK: - Beat Quality

    /// Returns how well-timed the current moment is relative to the song's beat grid.
    func beatQuality() -> BeatQuality {
        guard musicIsPlaying else { return .offBeat }
        // Wall-clock elapsed × current rate = actual position in the song
        let songElapsed = (currentEngineTime() - musicStartHostTime) * Double(currentRate)
        let phase = songElapsed.truncatingRemainder(dividingBy: beatInterval)
        let dist  = min(phase, beatInterval - phase)
        if dist < 0.060 { return .perfect }
        if dist < 0.120 { return .good }
        return .offBeat
    }

    /// 0.0 = exactly on beat, 1.0 = next beat. Used to drive co-op note beat rings.
    func currentBeatPhase() -> Double {
        guard musicIsPlaying else { return 0 }
        let songElapsed = (currentEngineTime() - musicStartHostTime) * Double(currentRate)
        return songElapsed.truncatingRemainder(dividingBy: beatInterval) / beatInterval
    }

    // MARK: - Co-op Groove Audio
    // Called every frame from CoopGameManager with the continuous 0-100 groove level.
    // Smoothly slides playback tempo + updates volume and arp layer on tier change.

    func updateCoopGroove(_ level: Double) {
        // Smooth rate interpolation — 5 % per call so there are no jarring jumps
        targetRate   = Float(0.84 + (level / 100.0) * 0.32)   // 0.84× (dead) → 1.16× (rave)
        currentRate += (targetRate - currentRate) * 0.05
        if abs(currentRate - targetRate) < 0.001 { currentRate = targetRate }
        timePitch.rate = currentRate

        // Volume + arp only need updating when the tier boundary is crossed
        let newTier: Int
        if      level < 15 { newTier = 0 }
        else if level < 40 { newTier = 1 }
        else if level < 68 { newTier = 2 }
        else               { newTier = 3 }
        guard newTier != currentGrooveTier else { return }
        currentGrooveTier = newTier
        ensureEngineRunning()

        let volumes: [Float] = [0.30, 0.60, 0.85, 1.00]
        musicPlayer.volume = volumes[newTier]

        if newTier >= 2 {
            if !grooveArpPlayer.isPlaying, let buf = grooveArpBuffer {
                grooveArpPlayer.volume = newTier == 3 ? 0.38 : 0.22
                grooveArpPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                grooveArpPlayer.play()
            } else {
                grooveArpPlayer.volume = newTier == 3 ? 0.38 : 0.22
            }
        } else {
            if grooveArpPlayer.isPlaying { grooveArpPlayer.stop() }
        }
    }

    // MARK: - Crowd Sounds

    /// Rising "WHOOO" cluster — tier crossing, boss catch, combo milestone.
    func playCrowdCheer() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 0.75
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // 8 detuned voices rising in pitch — sounds like a crowd "woo"
        let voices: [Float] = [480, 496, 510, 525, 540, 556, 572, 590]
        for i in 0..<Int(fc) {
            let t   = Float(i) / Float(sr)
            let rise = min(1.0, t / 0.10)
            let fade = max(0.0, 1.0 - max(0.0, t - 0.40) / 0.35)
            let env  = rise * fade
            var s: Float = 0
            for f in voices { s += sin(2 * .pi * (f + t * 180) * t) * 0.09 }
            data[i] = max(-0.5, min(0.5, s * env * env))
        }
        reconnectMono(node: crowdPlayer, fmt: mono)
        crowdPlayer.stop()
        crowdPlayer.scheduleBuffer(buf)
        if !crowdPlayer.isPlaying { crowdPlayer.play() }
    }

    /// Bass thump + crowd roar — ULTRA crossing and DROP event.
    func playCrowdDrop() {
        ensureEngineRunning()
        let sr: Double = 44100; let dur: Double = 1.2
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        var seed: UInt32 = 0xB33F1234
        for i in 0..<Int(fc) {
            let t = Float(i) / Float(sr)
            // Sub-bass punch
            let be  = max(0.0, 1.0 - t / 0.40); let be3 = be * be * be
            let bass = sin(2 * .pi * 62.0 * t) * be3 * 0.55
            // Mid noise burst
            seed = seed &* 1664525 &+ 1013904223
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            let nEnv  = min(1.0, t / 0.10) * max(0.0, 1.0 - max(0.0, t - 0.15) / 0.50)
            // Crowd shimmer rising at 0.2 s
            let ct = t - 0.20
            let cEnv: Float = ct > 0 ? min(1.0, ct / 0.15) * max(0.0, 1.0 - max(0.0, ct - 0.30) / 0.70) : 0
            var shimmer: Float = 0
            for f: Float in [500, 522, 544, 566] { shimmer += sin(2 * .pi * (f + ct * 150) * t) * 0.07 }
            data[i] = max(-0.8, min(0.8, bass + noise * nEnv * 0.18 + shimmer * cEnv))
        }
        reconnectMono(node: crowdPlayer, fmt: mono)
        crowdPlayer.stop()
        crowdPlayer.scheduleBuffer(buf)
        if !crowdPlayer.isPlaying { crowdPlayer.play() }
    }

    // MARK: - Groove Arpeggio Buffer
    // Generates a 4-beat pentatonic arpeggio loop at 123 BPM.

    private func buildGrooveArpBuffer() -> AVAudioPCMBuffer? {
        let sr: Double = 44100
        let bpm = 123.046875
        let beatSec = 60.0 / bpm
        let totalSec = beatSec * 4          // 4-beat phrase ≈ 1.95 s
        let fc = AVAudioFrameCount(sr * totalSec)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = fc

        // Pentatonic ascend/descend: C5 E5 G5 B5 G5 E5 C5 rest
        let noteLen = beatSec * 0.5
        let freqs:  [Float]  = [523.25, 659.25, 783.99, 987.77, 783.99, 659.25, 523.25, 0]
        let starts: [Double] = (0..<8).map { Double($0) * noteLen }

        for i in 0..<Int(fc) {
            let t = Double(i) / sr
            var s: Float = 0
            for (f, start) in zip(freqs, starts) where f > 0 {
                let lt = t - start
                guard lt >= 0 && lt < noteLen else { continue }
                let env = Float(max(0, 1.0 - lt / (noteLen * 0.85))); let e2 = env * env
                s += sin(2 * .pi * f * Float(lt)) * e2 * 0.18
                // add a softer octave
                s += sin(2 * .pi * f * 0.5 * Float(lt)) * e2 * 0.08
            }
            data[i] = max(-0.4, min(0.4, s))
        }

        reconnectMono(node: grooveArpPlayer, fmt: mono)
        return buf
    }

    // MARK: - Sound Effects

    func playCatch(player playerNum: Int, quality: BeatQuality) {
        ensureEngineRunning()
        let sr: Double = 44100
        let dur: Double = quality == .perfect ? 0.18 : quality == .good ? 0.13 : 0.09
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        let base: Float = playerNum == 1 ? 1046.5 : 783.99
        let f1: Float = quality == .perfect ? base : base * (quality == .good ? 0.75 : 0.5)
        let f2: Float = quality == .perfect ? base * 1.5 : f1
        let vol: Float = quality == .perfect ? 0.45 : quality == .good ? 0.32 : 0.20
        for i in 0..<Int(fc) {
            let t   = Float(i) / Float(sr)
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
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Descending icy chime: C6 → A5 → F5, staggered
        let freqs:  [Float]  = [1046.5, 880.0, 698.5]
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
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // Dissonant descending buzz
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
        // Ascending major arpeggio C5→E5→G5→C6
        let freqs:  [Float]  = [523.25, 659.25, 783.99, 1046.5]
        let delays: [Double] = [0.0,    0.10,   0.20,   0.32]
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

    func playBlackout() {
        ensureEngineRunning()
        // Classic CRT TV white-noise static — pure random broadband signal
        let sr: Double = 44100; let dur: Double = 2.5
        let fc = AVAudioFrameCount(sr * dur)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf  = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: fc),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = fc
        // LCG pseudo-random noise
        var seed: UInt32 = 0xA5F3C2B1
        for i in 0..<Int(fc) {
            seed = seed &* 1664525 &+ 1013904223
            let noise  = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            let t      = Float(i) / Float(sr)
            let fadeIn: Float = min(1.0, t / 0.005)   // 5 ms fade-in to prevent click
            data[i] = noise * 0.40 * fadeIn
        }
        reconnectMono(node: blackoutPlayer, fmt: mono)
        blackoutPlayer.scheduleBuffer(buf)
        if !blackoutPlayer.isPlaying { blackoutPlayer.play() }
    }

    // MARK: - Private Helpers

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
