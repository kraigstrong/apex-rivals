import Foundation
import Testing
@testable import Apex

struct ApexSchoolTests {
    static let track = Track(.apexSchool)
    static let guide = ApexGuide(track: track, line: RacingLine(track: track)).withIdealSpeeds(on: track)

    @Test func findsFourRightHanders() {
        #expect(Self.guide.corners.count == 4)
        #expect(Self.guide.corners.allSatisfy { $0.side == -1 })
    }

    @Test func eachCornerTurnsInThenClipsTheApexThenRunsOut() {
        let guide = Self.guide
        for corner in guide.corners {
            let toApex = guide.ahead(from: corner.turnIn, to: corner.apex)
            let toExit = guide.ahead(from: corner.turnIn, to: corner.exit)
            #expect(toApex > 100 && toApex < toExit && toExit < 2000)
            // The ideal line touches the inside at the apex and the outside at turn-in and exit.
            #expect(guide.line.offset(at: corner.apex) * corner.side > guide.reach - 16)
            #expect(guide.line.offset(at: corner.turnIn) * corner.side < -(guide.reach - 10))
            #expect(corner.idealSpeed > 250 && corner.idealSpeed < RaceTuning.topSpeed)
        }
    }

    @Test func theCoachKnowsWhereYouAre() {
        let guide = Self.guide
        let corner = guide.corners[0]
        #expect(guide.situation(at: corner.turnIn - 200)?.phase == .lineUp)
        #expect(guide.situation(at: corner.turnIn + 20)?.phase == .turnIn)
        #expect(guide.situation(at: corner.apex + 20)?.phase == .runOut)
        // A right-hander's outside is the top of the screen, its inside the bottom.
        #expect(ApexGuide.prompt(.lineUp, side: -1).title == "KEEP TO THE TOP")
        #expect(ApexGuide.prompt(.turnIn, side: -1).detail.contains("bottom"))
    }

    @Test func adviceSteersTowardTheLine() {
        let guide = Self.guide
        let s = guide.corners[0].turnIn - 400
        let target = guide.line.offset(at: s)
        func car(n: Double) -> Car {
            var car = Car(track: Self.track, distanceBeforeLine: 0, n: n, speed: 400)
            car.s = s
            return car
        }
        #expect(guide.advice(for: car(n: target)) == .feather)
        #expect(guide.advice(for: car(n: target - 40)) == .hold)
        #expect(guide.advice(for: car(n: target + 40)) == .letGo)
    }

    /// Driving the ideal line hits every apex; driving down the middle misses them.
    @Test func theJudgeTellsAGoodLineFromAMissedApex() {
        func verdicts(_ line: @escaping (Double) -> Double) -> [CornerJudge.Verdict] {
            let session = RaceSession(track: Self.track)
            var driver = AutoDriver(line: line)
            var judge = CornerJudge()
            var found: [CornerJudge.Verdict] = []
            session.start()
            while found.count < 6, session.clock < 60 {
                session.advance(by: RaceTuning.physicsStep) { driver.decide($0) }
                if let verdict = judge.update(car: session.car, guide: Self.guide) { found.append(verdict) }
            }
            return found
        }
        let ideal = verdicts { Self.guide.line.offset(at: $0) }
        let middle = verdicts { _ in 0 }
        let idealHits = ideal.allSatisfy(\.hitApex)
        let middleMisses = middle.allSatisfy { !$0.closeToApex }
        let idealSlowest = ideal.map(\.slowest).reduce(0, +), middleSlowest = middle.map(\.slowest).reduce(0, +)
        #expect(ideal.count >= 4)
        #expect(idealHits, "\(ideal.map(\.apexGap))")
        #expect(middleMisses, "\(middle.map(\.apexGap))")
        #expect(middleSlowest < idealSlowest)
    }
}
