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
            #expect(toApex > 100 && toApex < toExit && toExit < 1200)
            // Plenty of straight on the outside before the next corner: at least four seconds at top speed.
            let next = guide.corners[(guide.corners.firstIndex(of: corner)! + 1) % guide.corners.count]
            #expect(guide.ahead(from: corner.exit, to: next.turnIn) > 4 * RaceTuning.topSpeed)
            // The ideal line touches the inside at the apex and the outside at turn-in and exit.
            #expect(guide.line.offset(at: corner.apex) * corner.side > guide.reach - 16)
            #expect(guide.line.offset(at: corner.turnIn) * corner.side < -(guide.reach - 16))
            #expect(corner.idealSpeed > 250 && corner.idealSpeed < RaceTuning.topSpeed)
        }
    }

    @Test func theCoachKnowsWhereYouAre() {
        let guide = Self.guide
        let corner = guide.corners[0]
        #expect(guide.situation(at: corner.turnIn - 200)?.phase == .lineUp)
        #expect(guide.situation(at: corner.turnIn + 20)?.phase == .turnIn)
        #expect(guide.situation(at: corner.apex + 20)?.phase == .runOut)
        // A right-hander: stay wide at the top, let go to dive to the apex at the bottom, hold to ease back out.
        #expect(ApexGuide.prompt(.lineUp, side: -1).title == "STAY WIDE")
        #expect(ApexGuide.prompt(.lineUp, side: -1).detail.contains("top"))
        #expect(ApexGuide.prompt(.turnIn, side: -1).title == "LET GO")
        #expect(ApexGuide.prompt(.turnIn, side: -1).detail.contains("bottom"))
        #expect(ApexGuide.prompt(.runOut, side: -1).title == "HOLD")
        // A left-hander is the mirror image.
        #expect(ApexGuide.prompt(.turnIn, side: 1).title == "HOLD")
        #expect(ApexGuide.prompt(.runOut, side: 1).title == "LET GO")
    }

    /// Driving the ideal line hits every apex; driving down the middle misses them.
    @Test func theJudgeTellsAGoodLineFromAMissedApex() {
        func verdicts(_ line: @escaping (Double) -> Double) -> [CornerJudge.Verdict] {
            let session = RaceSession(track: Self.track)
            var driver = AutoDriver(line: line)
            var judge = CornerJudge()
            var found: [CornerJudge.Verdict] = []
            session.start()
            while found.count < 6, session.clock < 90 {
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

    /// Two apex hits, not necessarily in a row, and you're ready. Only the second hit graduates.
    @Test func twoApexHitsGraduate() {
        var progress = SchoolProgress()
        let hit = CornerJudge.Verdict(apexGap: 5, slowest: 300, idealSpeed: 320)
        let miss = CornerJudge.Verdict(apexGap: 40, slowest: 300, idealSpeed: 320)
        let graduated = [hit, miss, hit, hit].map { progress.record($0) }
        #expect(graduated == [false, false, true, false])
        #expect(progress.hits == 3)
    }

    @Test func graduatingIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "ApexSchoolTests.done"))
        defaults.removePersistentDomain(forName: "ApexSchoolTests.done")
        #expect(!SchoolProgress.isDone(defaults: defaults))
        SchoolProgress.markDone(defaults: defaults)
        #expect(SchoolProgress.isDone(defaults: defaults))
    }
}
