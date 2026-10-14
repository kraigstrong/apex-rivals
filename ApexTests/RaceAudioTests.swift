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

    @Test func revsClimbThroughEachGearAndDropAtTheShift() {
        #expect(SoundSettings.revs(at: 0) == 0.25)
        #expect(SoundSettings.revs(at: 120) > SoundSettings.revs(at: 100))
        #expect(SoundSettings.revs(at: 96) < SoundSettings.revs(at: 94))
        #expect(SoundSettings.gear(at: 330) == 7)
        #expect((0...340).allSatisfy { (0...1).contains(SoundSettings.revs(at: Double($0))) })
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

    /// With the music off, an idle car on the grid is a quiet hum; nothing else plays.
    @Test func theGridIsJustAnIdle() {
        let synth = Synth(sampleRate: 48_000)
        var controls = SoundControls()
        controls.musicOn = false
        let samples = render(synth, controls, seconds: 0.6).suffix(9_600)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.005 && peak < 0.2, "peak \(peak)")
    }
}
