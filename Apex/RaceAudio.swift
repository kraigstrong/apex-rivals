import AVFoundation
import Foundation
import os

/// The race's sound, synthesized as it plays: no audio files, so nothing to license. The engine growls, its firings
/// coming faster and slower with the car's speed (no gear changes), the tires hiss and squeal with the same scrub that
/// leaves skid marks, curbs rumble, walls thump, splits and best laps chime, and a synthwave loop plays underneath. Tuned in the
/// Apex Sound Lab; these are its settings. It mixes with the player's own music and plays with the silent switch on
/// (it's switched off in the menu).
final class RaceAudio {
    static let shared = RaceAudio()

    enum Cue: Int, CaseIterable {
        case faster, slower, best, apex
    }

    /// Sound and music, each switched off from the race's menu and remembered.
    var soundOn: Bool {
        get { !defaults.bool(forKey: "apex.sound.off") }
        set { defaults.set(!newValue, forKey: "apex.sound.off"); controls.withLock { $0.soundOn = newValue } }
    }
    var musicOn: Bool {
        get { !defaults.bool(forKey: "apex.music.off") }
        set {
            defaults.set(!newValue, forKey: "apex.music.off")
            // Someone's own music playing still wins, as it does when a race starts.
            let otherMusic = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
            controls.withLock { $0.musicOn = newValue && !otherMusic }
        }
    }

    private let defaults = UserDefaults.standard
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let controls = OSAllocatedUnfairLock(initialState: SoundControls())

    private init() {}

    /// Starts the sound for a race. The engine is silent until `drive` says the car is racing.
    func start() {
        let session = AVAudioSession.sharedInstance()
        // Playback ignores the silent switch; mixing keeps the player's own music going underneath.
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        let otherMusic = session.secondaryAudioShouldBeSilencedHint
        controls.withLock {
            $0.soundOn = soundOn
            // Someone's own music is already playing: leave it be rather than playing ours over it.
            $0.musicOn = musicOn && !otherMusic
            $0.racing = false
        }
        if source == nil {
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 1)!
            let synth = Synth(sampleRate: format.sampleRate)
            let controls = self.controls
            let node = AVAudioSourceNode(format: format) { _, _, frames, buffers in
                let list = UnsafeMutableAudioBufferListPointer(buffers)
                guard let data = list[0].mData else { return noErr }
                // Never wait on the game: if the controls are being written this instant, use the last ones.
                let current = controls.withLockIfAvailable { $0 } ?? synth.last
                synth.render(into: data.assumingMemoryBound(to: Float.self), count: Int(frames), controls: current)
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        if !engine.isRunning { try? engine.start() }
    }

    /// Stops the sound when leaving a race.
    func stop() {
        controls.withLock { $0.racing = false }
        engine.pause()
    }

    /// Called every frame with what the car is doing. `racing` false (on the grid, under the session's card, or paused
    /// behind a panel) quiets the engine, tires and curbs.
    func drive(speedKmh: Double, throttle: Double, scrub: Double, onCurb: Bool, racing: Bool) {
        controls.withLock {
            $0.speed = speedKmh
            $0.throttle = throttle
            $0.scrub = scrub
            $0.onCurb = onCurb
            $0.racing = racing
        }
    }

    func play(_ cue: Cue) {
        controls.withLock { $0.cueCount[cue.rawValue] &+= 1 }
    }

    func wall(severity: Double) {
        controls.withLock {
            $0.wallCount &+= 1
            $0.wallSeverity = severity
        }
    }
}

/// What the game tells the synthesizer: plain values only, so the audio thread copies it without allocating. Cues and
/// wall hits are counters; the synthesizer plays one each time a count goes up.
struct SoundControls {
    var soundOn = true
    var musicOn = true
    var racing = false
    var speed = 0.0
    var throttle = 0.0
    var scrub = 0.0
    var onCurb = false
    var cueCount = CueCounts()
    var wallCount = 0
    var wallSeverity = 0.0
}

/// One counter per cue, in a fixed-size value (no array, so no allocation on the audio thread).
struct CueCounts {
    private var counts: (Int, Int, Int, Int) = (0, 0, 0, 0)

    subscript(index: Int) -> Int {
        get {
            switch index {
            case 0: return counts.0
            case 1: return counts.1
            case 2: return counts.2
            default: return counts.3
            }
        }
        set {
            switch index {
            case 0: counts.0 = newValue
            case 1: counts.1 = newValue
            case 2: counts.2 = newValue
            default: counts.3 = newValue
            }
        }
    }
}

/// Revs and notes. The levels and pitches are in `RaceTuning`, with the rest of the tuning.
enum SoundSettings {
    /// Engine revs, 0...1: from 0.25 at a standstill to 1 at the car's top speed, with no gear changes between.
    static func revs(at kmh: Double) -> Double {
        let top = RaceTuning.topSpeed * RaceTuning.displaySpeedFactor
        return 0.25 + 0.75 * min(1, max(0, kmh / top))
    }

    static func note(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
}

/// The synthesizer. Lives on the audio thread: everything it needs is allocated up front.
final class Synth {
    private let rate: Double
    private(set) var last = SoundControls()
    private var heard = SoundControls()

    // Engine
    private var pitch = 0.0, enginePhase = 0.0, engineGain = 0.0, low1 = 0.0, low2 = 0.0
    private var firingStretch = 1.0, firingStrength = 1.0, bodyLow = 0.0, bodyBand = 0.0
    #if DEBUG
    /// Cylinder firings so far, for the tests.
    private(set) var firings = 0
    #endif
    // Tires
    private var tireGain = 0.0, squealGain = 0.0, svfLow = 0.0, svfBand = 0.0, squealPhase = 0.0, vibrato = 0.0
    // Curbs
    private var curbGain = 0.0, curbPhase = 0.0, chopPhase = 0.0, curbLow = 0.0
    // Walls
    private var wallEnv = 0.0, wallDecay = 0.0, wallCut = 0.0, wallLow = 0.0, thumpPhase = 0.0, thumpTime = 1.0
    // Notes for cues and music
    private var voices = [Voice](repeating: Voice(), count: 48)
    private var musicGain = 0.0, step = 0, untilStep = 0.0
    private var noise: UInt32 = 0x9E37_79B9

    init(sampleRate: Double) {
        rate = sampleRate
        // Static tables are built on first use; touch them now, so it isn't the audio thread that builds them.
        _ = Self.bestRun.count + Self.chords.count
    }

    private func smooth(_ tau: Double) -> Double { 1 - exp(-1 / (tau * rate)) }

    private func white() -> Double {
        noise ^= noise << 13
        noise ^= noise >> 17
        noise ^= noise << 5
        return Double(noise) / Double(UInt32.max) * 2 - 1
    }

    func render(into out: UnsafeMutablePointer<Float>, count: Int, controls c: SoundControls) {
        last = c
        let on = c.soundOn
        // New cues and wall hits since the last buffer.
        for index in 0..<4 where c.cueCount[index] != heard.cueCount[index] {
            if on, let cue = RaceAudio.Cue(rawValue: index) { play(cue) }
        }
        if c.wallCount != heard.wallCount, on {
            let severity = c.wallSeverity
            wallEnv = RaceTuning.wallLevel * (0.3 + 0.7 * severity)
            wallDecay = 0.18 + 0.2 * severity
            wallCut = 1 - exp(-2 * .pi * (1200 + 3000 * severity) / rate)
            thumpTime = 0
        }
        heard = c

        let s = SoundSettings.self, t = RaceTuning.self
        let kmh = c.racing ? c.speed : 0
        // Off the track (on the grid, under the session's card, behind a panel) the engine is silent, not idling: it
        // fades out at the pitch it had and starts again with the race.
        let pitchTarget = c.racing
            ? t.enginePitch.lowerBound + (t.enginePitch.upperBound - t.enginePitch.lowerBound) * s.revs(at: kmh) : pitch
        let swing = t.engineThrottleSwing
        let engineTarget = on && c.racing ? t.engineLevel * 0.22 * t.engineLoudness * (1 - swing + swing * c.throttle) : 0
        let engineCut = 1 - exp(-2 * .pi * (300 + 8000 * t.engineBrightness) / rate)
        let glide = smooth(0.03)
        let bodyF = 2 * sin(.pi * min(t.engineBody, rate / 6) / rate), bodyDamp = 1.0 / 3
        let rough = t.engineRoughness
        let tireTarget = on && c.racing ? t.tireLevel * 0.5 * pow(c.scrub, 1.4) : 0
        let squealTarget = on && c.racing ? t.tireLevel * t.tireSqueal * 0.08 * c.scrub * c.scrub : 0
        let curbTarget = on && c.racing && c.onCurb ? t.curbLevel * 0.35 : 0
        let musicTarget = on && c.musicOn ? t.musicLevel : 0
        let fast = smooth(0.02), medium = smooth(0.04), slow = smooth(0.05)
        // The throttle steps on and off as the line brakes the car; the engine's level swells to follow it.
        let swell = smooth(0.15)
        let svfF = 2 * sin(.pi * t.tireHissPitch / rate), svfQ = 1 / 0.9
        let curbCut = 1 - exp(-2 * .pi * 380 / rate)
        let chopRate = 6 + kmh / 12
        let samplesPerStep = rate * 60 / t.musicTempo / 4

        for i in 0..<count {
            // Engine: each cylinder firing kicks a resonance tuned like an exhaust (the body), and the firings come a
            // little unevenly, so it growls rather than buzzes. The firing rate glides with the speed.
            pitch = pitch == 0 ? pitchTarget : pitch + (pitchTarget - pitch) * glide
            engineGain += (engineTarget - engineGain) * swell
            enginePhase += pitch * firingStretch / rate
            var kick = 0.0
            if enginePhase >= 1 {
                enginePhase -= enginePhase.rounded(.down)
                // Each cycle runs a little long or short, and fires a little harder or softer.
                firingStretch = 1 + rough * 0.05 * white()
                firingStrength = 1 + rough * 0.6 * white()
                kick = 6 * firingStrength
                #if DEBUG
                firings &+= 1
                #endif
            }
            // A breath of noise between firings.
            kick += rough * 0.15 * white()
            let high = kick - bodyLow - bodyDamp * bodyBand
            bodyBand += bodyF * high
            bodyLow += bodyF * bodyBand
            low1 += (bodyBand + 0.5 * bodyLow - low1) * engineCut
            low2 += (low1 - low2) * engineCut
            var mix = low2 * engineGain

            // Tires: band-passed noise, and a wobbling squeal.
            tireGain += (tireTarget - tireGain) * medium
            squealGain += (squealTarget - squealGain) * slow
            if tireGain > 1e-5 || squealGain > 1e-5 {
                let high = white() - svfLow - svfQ * svfBand
                svfBand += svfF * high
                svfLow += svfF * svfBand
                vibrato += 7 / rate
                squealPhase += (950 + 35 * sin(2 * .pi * vibrato)) / rate
                mix += svfBand * tireGain + sin(2 * .pi * squealPhase) * squealGain
            }

            // Curbs: a low buzz chopped at the rate the blocks pass under the tires.
            curbGain += (curbTarget - curbGain) * fast
            if curbGain > 1e-5 {
                curbPhase = (curbPhase + 58 / rate).truncatingRemainder(dividingBy: 1)
                chopPhase = (chopPhase + chopRate / rate).truncatingRemainder(dividingBy: 1)
                curbLow += ((curbPhase < 0.5 ? 1 : -1) - curbLow) * curbCut
                mix += curbLow * (chopPhase < 0.5 ? 1 : 0) * curbGain
            }

            // Walls: a burst of filtered noise and a falling thump.
            if thumpTime < 0.4 {
                let t = thumpTime
                wallLow += (white() - wallLow) * wallCut
                let burst = wallEnv * 0.9 * exp(-t / (wallDecay / 6.9))
                let thump = 140 * pow(40 / 140, min(1, t / 0.25))
                thumpPhase += thump / rate
                mix += wallLow * burst + sin(2 * .pi * thumpPhase) * wallEnv * exp(-t / (0.3 / 6.9))
                thumpTime += 1 / rate
            }

            // Music: a step every sixteenth note.
            musicGain += (musicTarget - musicGain) * slow
            if musicTarget > 0 {
                untilStep -= 1
                if untilStep <= 0 {
                    playStep(step)
                    step += 1
                    untilStep += samplesPerStep
                }
            }

            // Notes: cue voices go straight out, music voices through the music level.
            var music = 0.0
            for v in voices.indices where voices[v].active {
                let sample = voices[v].next(rate: rate, noise: white())
                if voices[v].music { music += sample } else { mix += sample }
            }
            mix += music * musicGain

            out[i] = Float(tanh(mix * t.soundMaster * 1.2))
        }
    }

    // MARK: Cues

    private func play(_ cue: RaceAudio.Cue) {
        let v = RaceTuning.cueLevel * 0.3, n = SoundSettings.note
        switch cue {
        case .faster:
            start(Voice(wave: .triangle, freq: n(76), dur: 0.12, vol: v))
            start(Voice(wave: .triangle, freq: n(83), dur: 0.2, vol: v, delay: 0.09))
        case .slower:
            start(Voice(wave: .triangle, freq: n(76), dur: 0.12, vol: v))
            start(Voice(wave: .triangle, freq: n(71), dur: 0.22, vol: v, delay: 0.09))
        case .best:
            for k in 0..<Self.bestRun.count {
                start(Voice(wave: .triangle, freq: n(Self.bestRun[k]), dur: k == 4 ? 0.5 : 0.14, vol: v,
                            delay: Double(k) * 0.08))
            }
        case .apex:
            start(Voice(wave: .square, freq: n(96), dur: 0.05, vol: v * 0.8))
        }
    }

    private func start(_ voice: Voice) {
        guard let free = voices.firstIndex(where: { !$0.active }) else { return }
        voices[free] = voice
        voices[free].active = true
        voices[free].prepare(rate: rate)
    }

    // MARK: Music

    // Built once, so the audio thread never allocates.
    private static let bestRun: [Double] = [72, 76, 79, 84, 88]
    private static let chords: [[Double]] = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]

    /// Night drive: a four-chord synthwave loop (Am F C G) of kick, snare, hats, bass, arpeggio and pad.
    private func playStep(_ step: Int) {
        let n = SoundSettings.note
        let i = step % 16, chord = Self.chords[(step / 16) % 4]
        if i % 4 == 0 { start(Voice(wave: .sine, freq: 150, freqEnd: 45, sweep: 0.12, dur: 0.2, vol: 0.9, music: true)) }
        if i == 4 || i == 12 { start(Voice(wave: .noise, dur: 0.22, vol: 0.35, highPass: 1200, music: true)) }
        if i % 2 == 0 { start(Voice(wave: .noise, dur: 0.04, vol: 0.12, highPass: 7000, music: true)) }
        if i % 2 == 0 {
            start(Voice(wave: .saw, freq: n(chord[0] - 12) * (i % 4 == 2 ? 2 : 1), dur: 0.2, vol: 0.32, lowPass: 700,
                        music: true))
        }
        let octave = Double(12 * (1 + (i >> 3) % 2))
        start(Voice(wave: .triangle, freq: n(chord[i % 3] + octave), dur: 0.16, vol: 0.08, lowPass: 2400, music: true))
        if i == 0 {
            for midi in chord { start(Voice(wave: .saw, freq: n(midi), dur: 1.9, vol: 0.05, lowPass: 1400, music: true)) }
        }
    }
}

/// One note: an oscillator or noise with a quick attack and an exponential fade, optionally filtered.
struct Voice {
    enum Wave { case sine, triangle, square, saw, noise }

    var active = false
    var wave = Wave.sine
    var freq = 440.0
    /// Pitch slides to this over `sweep` seconds (a kick drum's thud); nil holds the pitch.
    var freqEnd: Double?
    var sweep = 0.0
    var dur = 0.1
    var vol = 0.1
    var delay = 0.0
    var lowPass: Double?
    var highPass: Double?
    var music = false

    private var phase = 0.0, time = 0.0, filtered = 0.0, lpCoef = 0.0, hpCoef = 0.0

    init() {}

    init(wave: Wave, freq: Double = 440, freqEnd: Double? = nil, sweep: Double = 0, dur: Double, vol: Double,
         delay: Double = 0, lowPass: Double? = nil, highPass: Double? = nil, music: Bool = false) {
        self.wave = wave
        self.freq = freq
        self.freqEnd = freqEnd
        self.sweep = sweep
        self.dur = dur
        self.vol = vol
        self.delay = delay
        self.lowPass = lowPass
        self.highPass = highPass
        self.music = music
    }

    mutating func prepare(rate: Double) {
        time = -delay
        lpCoef = lowPass.map { 1 - exp(-2 * .pi * $0 / rate) } ?? 0
        hpCoef = highPass.map { 1 - exp(-2 * .pi * $0 / rate) } ?? 0
    }

    mutating func next(rate: Double, noise: Double) -> Double {
        time += 1 / rate
        guard time >= 0 else { return 0 }
        guard time < dur else {
            active = false
            return 0
        }
        var f = freq
        if let end = freqEnd { f = freq * pow(end / freq, min(1, time / max(sweep, 1e-4))) }
        phase = (phase + f / rate).truncatingRemainder(dividingBy: 1)
        var x: Double
        switch wave {
        case .sine: x = sin(2 * .pi * phase)
        case .triangle: x = 1 - 4 * abs(phase - 0.5)
        case .square: x = phase < 0.5 ? 1 : -1
        case .saw: x = 2 * phase - 1
        case .noise: x = noise
        }
        if lowPass != nil {
            filtered += (x - filtered) * lpCoef
            x = filtered
        } else if highPass != nil {
            filtered += (x - filtered) * hpCoef
            x -= filtered
        }
        let attack = 0.008
        let env = time < attack ? vol * time / attack : vol * pow(0.0001 / vol, (time - attack) / max(dur - attack, 1e-4))
        return x * env
    }
}
