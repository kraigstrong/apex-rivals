import Foundation
import Testing
@testable import Apex

/// Bots lap every circuit with the player's one control. They pin down the difficulty, the same on each: a perfect line
/// is around 26 seconds, a skilled human-speed player gets near 29, holding the middle of the road is around 30, and a
/// sloppy weaver still finishes in under 40.
struct LapTimeTests {
    static let ids = TrackLayout.all.map(\.id)
    static let tracks = Dictionary(uniqueKeysWithValues: TrackLayout.all.map { ($0.id, Track($0)) })
    static let lines = tracks.mapValues { RacingLine(track: $0) }

    struct Run {
        var laps: [Double]
        var wallHits: Int
        var mean: Double { laps.reduce(0, +) / Double(max(laps.count, 1)) }
    }

    /// The bot's second and third laps (the first starts from rest).
    func run(_ driver: AutoDriver, on id: String, laps: Int = 3) -> Run {
        let session = RaceSession(track: Self.tracks[id]!)
        var driver = driver
        session.start()
        var times: [Double] = []
        var hits = 0
        while times.count < laps, session.clock < 200 {
            for event in session.advance(by: RaceTuning.physicsStep, control: { driver.decide($0) }) {
                switch event {
                case .wallHit: hits += 1
                case .timing(.lap(let lap)): times.append(lap.time)
                case .timing: break
                }
            }
        }
        return Run(laps: Array(times.dropFirst()), wallHits: hits)
    }

    func idealLine(_ id: String) -> (Double) -> Double {
        let line = Self.lines[id]!
        return { line.offset(at: $0) }
    }
    var middle: (Double) -> Double { { _ in 0 } }

    @Test(arguments: ids) func aPerfectLineIsAroundTwentySixSeconds(id: String) {
        let lap = run(AutoDriver(line: idealLine(id)), on: id)
        #expect(lap.laps.count == 2)
        #expect((24.5...27.5).contains(lap.mean), "\(id), perfect line: \(lap.mean)s")
    }

    @Test(arguments: ids) func aSkilledPlayerIsUnderThirty(id: String) {
        let lap = run(AutoDriver(line: idealLine(id), decisionInterval: 0.09, hesitation: 0.04), on: id)
        #expect((27...30).contains(lap.mean), "\(id), skilled: \(lap.mean)s")
    }

    @Test(arguments: ids) func holdingTheMiddleIsAroundThirty(id: String) {
        let lap = run(AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04), on: id)
        #expect((28.5...32).contains(lap.mean), "\(id), middle of the road: \(lap.mean)s")
    }

    @Test(arguments: ids) func aSloppyWeaverStillFinishes(id: String) {
        let lap = run(AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08), on: id)
        #expect(lap.laps.count == 2)
        #expect((33...40).contains(lap.mean), "\(id), sloppy: \(lap.mean)s")
    }

    @Test(arguments: ids) func betterDrivingIsFaster(id: String) {
        let perfect = run(AutoDriver(line: idealLine(id)), on: id).mean
        let skilled = run(AutoDriver(line: idealLine(id), decisionInterval: 0.09, hesitation: 0.04), on: id).mean
        let centered = run(AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04), on: id).mean
        let sloppy = run(AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08), on: id).mean
        #expect(perfect < skilled)
        #expect(skilled < centered)
        #expect(centered < sloppy)
    }

    /// Prints a table of bot laps for tuning: `-only-testing:ApexTests/LapTimeTests/report()`.
    @Test(arguments: ids) func report(id: String) {
        let rows: [(String, AutoDriver)] = [
            ("perfect, ideal line", AutoDriver(line: idealLine(id))),
            ("50 ms, ideal line", AutoDriver(line: idealLine(id), decisionInterval: 0.05)),
            ("90 ms, ideal line", AutoDriver(line: idealLine(id), decisionInterval: 0.09, hesitation: 0.04)),
            ("perfect, middle", AutoDriver(line: middle)),
            ("90 ms, middle", AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04)),
            ("sloppy, middle", AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08)),
        ]
        for (name, driver) in rows {
            let lap = run(driver, on: id)
            print("LAPTIME \(id) \(name): \(lap.laps.map { String(format: "%.2f", $0) }) walls \(lap.wallHits)")
        }
    }
}
