import Foundation
import Testing
@testable import Apex

struct LapTimerTests {
    let track = Track(.harbourPark)

    /// Drives `timer` steadily from progress `from` to `to` at `speed`, starting at `clock`.
    func drive(_ timer: inout LapTimer, from: Double, to: Double, speed: Double, clock: inout Double)
        -> [LapTimer.Event] {
        let step = RaceTuning.physicsStep
        var events: [LapTimer.Event] = []
        var p = from
        while p < to {
            let next = p + speed * step
            clock += step
            events += timer.update(from: p, to: next, at: clock, step: step,
                                   sample: GhostSample(s: Float(track.wrap(next)), n: 0, psi: 0))
            p = next
        }
        return events
    }

    @Test func timesLapsAndSectorsBetweenSteps() {
        var timer = LapTimer(track: track)
        var clock = 0.0
        let speed = 400.0
        let events = drive(&timer, from: -100, to: track.length * 2 + 10, speed: speed, clock: &clock)
        let laps = events.compactMap { if case .lap(let lap) = $0 { return lap } else { return nil } }
        let splits = events.compactMap { if case .sector(let split) = $0 { return split } else { return nil } }
        #expect(laps.count == 2)
        #expect(splits.count == 4)
        let expected = track.length / speed
        #expect(abs(laps[0].time - expected) < 1e-6)
        #expect(laps[0].isBest)
        #expect(laps[0].delta == nil)
        #expect(abs(splits[0].time - track.sectorEnds[0] / speed) < 1e-6)
        #expect(splits.map(\.sector) == [1, 2, 1, 2])
        // The second lap at the same pace ties: not a new best, and level on every split.
        #expect(!laps[1].isBest)
        #expect(abs(laps[1].delta ?? 1) < 1e-6)
        #expect(abs(splits[2].delta ?? 1) < 1e-6)
    }

    @Test func aFasterLapBecomesTheBest() {
        var timer = LapTimer(track: track)
        var clock = 0.0
        _ = drive(&timer, from: -10, to: track.length + 1, speed: 300, clock: &clock)
        let events = drive(&timer, from: track.length + 1, to: track.length * 2 + 1, speed: 400, clock: &clock)
        let lap = events.compactMap { if case .lap(let lap) = $0 { return lap } else { return nil } }.first
        #expect(lap?.isBest == true)
        #expect((lap?.delta ?? 0) < 0)
        #expect(abs((timer.best?.time ?? 0) - track.length / 400) < 1e-3)
    }

    @Test func liveDeltaComparesAtTheSameDistance() {
        var timer = LapTimer(track: track)
        var clock = 0.0
        // A best lap at 300, then halfway round a lap at 400.
        _ = drive(&timer, from: -10, to: track.length + 1, speed: 300, clock: &clock)
        let half = track.length * 1.5
        _ = drive(&timer, from: track.length + 1, to: half, speed: 400, clock: &clock)
        let delta = try! #require(timer.liveDelta(at: clock, distance: half - track.length))
        let expected = (track.length / 2) / 400 - (track.length / 2) / 300
        #expect(abs(delta - expected) < 0.02)
    }

    @Test func noLiveDeltaWithoutABestLap() {
        var timer = LapTimer(track: track)
        var clock = 0.0
        _ = drive(&timer, from: -10, to: 500, speed: 300, clock: &clock)
        #expect(timer.liveDelta(at: clock, distance: 500) == nil)
    }

    @Test func recordsAGhostSamplePerTick() {
        var timer = LapTimer(track: track)
        var clock = 0.0
        _ = drive(&timer, from: -10, to: track.length + 1, speed: 400, clock: &clock)
        let best = try! #require(timer.best)
        let expected = Int(best.time * RaceTuning.ghostSampleRate)
        #expect(abs(best.ghost.count - expected) <= 1)
    }

    @Test func ghostPoseInterpolatesAcrossTheLine() {
        let length = track.length
        let record = LapRecord(time: 1, splits: [], ghost: [
            GhostSample(s: Float(length - 10), n: 0, psi: 0),
            GhostSample(s: 10, n: 4, psi: 0.2),
            GhostSample(s: 30, n: 4, psi: 0.2),
        ])
        let pose = try! #require(record.ghostPose(at: 0.5 / RaceTuning.ghostSampleRate, trackLength: length))
        #expect(abs(Double(pose.s) - 0) < 0.01 || abs(Double(pose.s) - length) < 0.01)
        #expect(abs(pose.n - 2) < 1e-5)
        #expect(record.ghostPose(at: 2, trackLength: length) == nil)
    }

    @Test func savedBestLapsComeBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "LapTimerTests.saved"))
        defaults.removePersistentDomain(forName: "LapTimerTests.saved")
        #expect(LapStore.load(for: track, defaults: defaults) == nil)
        let record = LapRecord(time: 29.871, splits: [10.2, 19.9], ghost: [GhostSample(s: 1, n: 2, psi: 0.1)])
        LapStore.save(record, for: track, defaults: defaults)
        #expect(LapStore.load(for: track, defaults: defaults) == record)
        LapStore.clear(for: track, defaults: defaults)
        #expect(LapStore.load(for: track, defaults: defaults) == nil)
    }

    @Test func formatsTimes() {
        #expect(LapFormat.time(29.8714) == "29.871")
        #expect(LapFormat.time(62.3456) == "1:02.346")
        #expect(LapFormat.time(9.5, decimals: 2) == "9.50")
        #expect(LapFormat.delta(-0.2141) == "\u{2212}0.214")
        #expect(LapFormat.delta(0.5) == "+0.500")
    }
}
