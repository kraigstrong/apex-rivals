import Foundation
import Testing
@testable import Apex

struct RaceAudioTests {
    /// Renders `seconds` of sound in hardware-sized buffers.
    func render(_ synth: Synth, _ controls: SoundControls, seconds: Double, rate: Double = 48_000) -> [Float] {
        var out: [Float] = []
        var buffer = [Float](repeating: 0, count: 512)
        for _ in 0..<Int(seconds * rate / 512) {
            buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, count: 512, controls: controls) }
            out += buffer
        }
        return out
    }

    /// No gear changes: revs climb steadily from idle to the top at top speed, never jumping.
    @Test func revsRiseSmoothlyWithSpeed() {
        #expect(SoundSettings.revs(at: 0) == 0.25)
        #expect(abs(SoundSettings.revs(at: 330) - 1) < 1e-9)
        let revs = (0...340).map { SoundSettings.revs(at: Double($0)) }
        #expect(revs.allSatisfy { (0...1).contains($0) })
        #expect(zip(revs, revs.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 < 0.01 })
    }

    /// The engine fires as often as its revs call for: the bottom of `enginePitch` plus the revs' share of it, give or
    /// take its roughness.
    @Test(arguments: [0.0, 165, 330])
    func theEngineFiresAtItsRate(kmh: Double) {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.musicOn = false
        controls.racing = true
        controls.speed = kmh
        controls.throttle = 1
        _ = render(synth, controls, seconds: 0.2)
        let before = synth.firings
        let seconds = Double(render(synth, controls, seconds: 2).count) / 48_000
        let rate = Double(synth.firings - before) / seconds
        let pitch = RaceTuning.enginePitch
        let expected = pitch.lowerBound + (pitch.upperBound - pitch.lowerBound) * SoundSettings.revs(at: kmh)
        #expect(abs(rate - expected) <= expected * 0.03 + 1, "\(rate) firings a second, expected \(expected)")
    }

    /// After a restart, the next race starts at the grid's firing rate, not gliding down from the last race's top speed.
    @Test func aNewRaceStartsFromTheGrid() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.musicOn = false
        controls.racing = true
        controls.speed = 330
        controls.throttle = 1
        _ = render(synth, controls, seconds: 0.5)
        controls.racing = false
        controls.speed = 0
        _ = render(synth, controls, seconds: 0.5)
        controls.racing = true
        var buffer = [Float](repeating: 0, count: 512)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0.baseAddress!, count: 512, controls: controls) }
        let pitch = RaceTuning.enginePitch
        let grid = pitch.lowerBound + (pitch.upperBound - pitch.lowerBound) * SoundSettings.revs(at: 0)
        #expect(abs(synth.firingRate - grid) < 0.5, "\(synth.firingRate) firings a second, expected \(grid)")
    }

    /// Everything at once (flat out, scrubbing, on a curb, a wall hit, every cue, the music) stays in range.
    @Test func everythingAtOnceStaysInRange() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.racing = true
        controls.speed = 300
        controls.throttle = 1
        controls.scrub = 1
        controls.onCurb = true
        for cue in RaceAudio.Cue.allCases { controls.cueCount[cue.rawValue] += 1 }
        controls.wallCount = 1
        controls.wallSeverity = 1
        let samples = render(synth, controls, seconds: 2)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
        let rms = (samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count)).squareRoot()
        #expect(rms > 0.02, "rms \(rms)")
    }

    @Test func soundOffIsSilent() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.soundOn = false
        controls.racing = true
        controls.speed = 250
        controls.throttle = 1
        controls.scrub = 1
        controls.cueCount[RaceAudio.Cue.best.rawValue] += 1
        let samples = render(synth, controls, seconds: 0.6)
        #expect(samples.suffix(4_800).allSatisfy { abs($0) < 1e-3 })
    }

    func peak(_ samples: some Collection<Float>) -> Float { samples.map { abs($0) }.max() ?? 0 }

    /// With the music off, the grid is silent: no engine idling while you wait to start or read the session's card.
    @Test func theGridIsSilent() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.musicOn = false
        let samples = render(synth, controls, seconds: 0.6).suffix(9_600)
        #expect(peak(samples) < 1e-3, "peak \(peak(samples))")
    }

    /// When the race stops (the session ends, or a panel opens), the engine fades out instead of dropping to an idle.
    @Test func theEngineFadesOutWhenTheRaceStops() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.musicOn = false
        controls.racing = true
        controls.speed = 250
        controls.throttle = 1
        let racing = render(synth, controls, seconds: 0.6).suffix(9_600)
        controls.racing = false
        controls.speed = 0
        let stopped = render(synth, controls, seconds: 1).suffix(4_800)
        #expect(peak(racing) > 0.02, "peak \(peak(racing))")
        #expect(peak(stopped) < 1e-3, "peak \(peak(stopped))")
    }
}
