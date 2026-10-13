import Foundation
import Testing
@testable import Apex

struct RaceSessionTests {
    /// Walls hit on the run-up to the line don't count against the first timed lap.
    @Test func wallHitsCountFromTheLine() {
        let session = RaceSession(track: Track(.testOval))
        session.start()
        session.holding = true
        for _ in 0..<120 { session.advance(by: 1.0 / 60) }
        #expect(session.timer.lapNumber == 0)
        #expect(session.wallHitsThisLap > 0)

        // A clean lap down the middle from there.
        var driver = AutoDriver(line: { _ in 0 })
        var laps = 0
        while laps == 0, session.clock < 60 {
            for case .timing(.lap) in session.advance(by: 1.0 / 60, control: { driver.decide($0) }) { laps += 1 }
        }
        #expect(laps == 1)
        #expect(session.wallHitsLastLap == 0)
    }
}
