import Testing
@testable import Apex

struct MedalTests {
    let ardennes = TrackLayout.ardennes

    @Test func everyCircuitHasFourMedalsEachFasterThanTheLast() throws {
        for layout in TrackLayout.all {
            let times = try #require(RaceTuning.medalTimes[layout.id], "\(layout.id) has no medals")
            #expect(times.count == Medal.allCases.count, "\(layout.id)")
            #expect(zip(times, times.dropFirst()).allSatisfy { $0 > $1 }, "\(layout.id): \(times)")
        }
        #expect(RaceTuning.medalTimes.count == TrackLayout.all.count)
    }

    @Test func aLapEarnsEveryMedalItMatchesOrBeats() throws {
        let gold = try #require(Medal.gold.target(on: ardennes))
        #expect(Medal.earned(by: gold, on: ardennes) == .gold)
        #expect(Medal.earned(by: gold - 0.001, on: ardennes) == .gold)
        #expect(Medal.earned(by: gold + 0.001, on: ardennes) == .silver)
        #expect(Medal.earned(by: 60, on: ardennes) == nil)
        #expect(Medal.earned(by: 10, on: ardennes) == .platinum)
        #expect(Medal.earned(by: nil, on: ardennes) == nil)
    }

    @Test func theNextMedalIsTheFirstNotWonYet() throws {
        let next = try #require(Medal.next(after: nil, on: ardennes))
        #expect(next.medal == .bronze)
        #expect(next.target == Medal.bronze.target(on: ardennes))
        #expect(Medal.next(after: 28, on: ardennes)?.medal == .gold)
        #expect(Medal.next(after: 10, on: ardennes) == nil)
    }

    @Test func onlyABetterMedalIsNew() {
        #expect(Medal.newlyWon(by: 30, after: nil, on: ardennes) == .bronze)
        #expect(Medal.newlyWon(by: 28, after: 30, on: ardennes) == .silver)
        #expect(Medal.newlyWon(by: 29.5, after: 29.7, on: ardennes) == nil)
        #expect(Medal.newlyWon(by: 40, after: nil, on: ardennes) == nil)
    }

    @Test func apexSchoolHasNoMedals() {
        #expect(Medal.earned(by: 10, on: .apexSchool) == nil)
        #expect(Medal.next(after: nil, on: .apexSchool) == nil)
    }
}
