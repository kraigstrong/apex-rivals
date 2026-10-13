import Foundation
import Testing
@testable import Apex

/// Bots lap the circuit with the player's one control. They pin down the difficulty: a perfect line is around 26
/// seconds, a skilled human-speed player gets near 29, holding the middle of the road is around 30, and a sloppy weaver
/// still finishes in under 40.
struct LapTimeTests {
    static let track = Track(.harbourPark)
    static let racingLine = RacingLine(track: track)

    struct Run {
        var laps: [Double]
        var wallHits: Int
        var mean: Double { laps.reduce(0, +) / Double(max(laps.count, 1)) }
    }

    /// The bot's second and third laps (the first starts from rest).
    func run(_ driver: AutoDriver, laps: Int = 3) -> Run {
        let session = RaceSession(track: Self.track)
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

    var idealLine: (Double) -> Double { { Self.racingLine.offset(at: $0) } }
    var middle: (Double) -> Double { { _ in 0 } }

    @Test func aPerfectLineIsAroundTwentySixSeconds() {
        let lap = run(AutoDriver(line: idealLine))
        #expect(lap.laps.count == 2)
        #expect((24.5...27.5).contains(lap.mean), "Perfect line: \(lap.mean)s")
    }

    @Test func aSkilledPlayerIsUnderThirty() {
        let lap = run(AutoDriver(line: idealLine, decisionInterval: 0.09, hesitation: 0.04))
        #expect((27...30).contains(lap.mean), "Skilled: \(lap.mean)s")
    }

    @Test func holdingTheMiddleIsAroundThirty() {
        let lap = run(AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04))
        #expect((28.5...32).contains(lap.mean), "Middle of the road: \(lap.mean)s")
    }

    @Test func aSloppyWeaverStillFinishes() {
        let lap = run(AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08))
        #expect(lap.laps.count == 2)
        #expect((33...40).contains(lap.mean), "Sloppy: \(lap.mean)s")
    }

    @Test func betterDrivingIsFaster() {
        let perfect = run(AutoDriver(line: idealLine)).mean
        let skilled = run(AutoDriver(line: idealLine, decisionInterval: 0.09, hesitation: 0.04)).mean
        let centered = run(AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04)).mean
        let sloppy = run(AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08)).mean
        #expect(perfect < skilled)
        #expect(skilled < centered)
        #expect(centered < sloppy)
    }

    /// Prints a table of bot laps for tuning: `-only-testing:ApexTests/LapTimeTests/report()`.
    @Test func report() {
        let rows: [(String, AutoDriver)] = [
            ("perfect, ideal line", AutoDriver(line: idealLine)),
            ("50 ms, ideal line", AutoDriver(line: idealLine, decisionInterval: 0.05)),
            ("90 ms, ideal line", AutoDriver(line: idealLine, decisionInterval: 0.09, hesitation: 0.04)),
            ("perfect, middle", AutoDriver(line: middle)),
            ("90 ms, middle", AutoDriver(line: middle, decisionInterval: 0.09, hesitation: 0.04)),
            ("sloppy, middle", AutoDriver(line: middle, decisionInterval: 0.12, tolerance: 30, hesitation: 0.08)),
        ]
        for (name, driver) in rows {
            let lap = run(driver)
            print("LAPTIME \(name): \(lap.laps.map { String(format: "%.2f", $0) }) walls \(lap.wallHits)")
        }
    }
}
