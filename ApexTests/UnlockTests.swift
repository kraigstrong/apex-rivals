import Foundation
import Testing
@testable import Apex

/// Free to try: Ardennes and Apex School. The unlock opens every other circuit, and every one added later.
struct UnlockTests {
    @Test func ardennesAndApexSchoolAreFree() {
        for id in [TrackLayout.ardennes.id, TrackLayout.apexSchool.id] {
            #expect(!CircuitUnlock.isLocked(id, unlocked: false, selling: true), "\(id)")
        }
    }

    @Test func everyOtherCircuitNeedsTheUnlock() {
        #expect(CircuitUnlock.circuitsItOpens.map(\.id) == ["swirl", "snake", "mirage", "island", "harbor"])
        for layout in CircuitUnlock.circuitsItOpens {
            #expect(CircuitUnlock.isLocked(layout.id, unlocked: false, selling: true), "\(layout.id)")
        }
        // A circuit added later is part of it from the start.
        #expect(CircuitUnlock.isLocked(TrackLayout.testOval.id, unlocked: false, selling: true))
    }

    @Test func theUnlockOpensEverythingAndSoDoesNotSellingIt() {
        for layout in TrackLayout.all + [.apexSchool, .testOval] {
            #expect(!CircuitUnlock.isLocked(layout.id, unlocked: true, selling: true))
            #expect(!CircuitUnlock.isLocked(layout.id, unlocked: false, selling: false))
        }
    }

    /// The unlock is cached on the device so the track list draws right at launch and offline.
    @MainActor @Test func purchasesStartLockedAndRememberTheUnlock() {
        let defaults = UserDefaults(suiteName: "apex.tests.\(UUID().uuidString)")!
        #expect(!CircuitPurchases(defaults: defaults, syncWithAppStore: {}).isUnlocked)
        defaults.set(true, forKey: CircuitPurchases.unlockedKey)
        let purchases = CircuitPurchases(defaults: defaults, syncWithAppStore: {})
        #expect(purchases.isUnlocked && !purchases.isLocked("swirl"))
    }

    /// Each circuit on the unlock's screen laps its ideal line about as fast as a good lap: between the 50 ms bot's
    /// platinum time and a few seconds under it (the thread doesn't steer, so it's a little quicker than any bot).
    @Test func eachThreadLapsLikeAGoodLap() {
        for layout in CircuitUnlock.circuitsItOpens {
            let lap = ThreadLap(track: Track(layout))
            let platinum = RaceTuning.medalTimes[layout.id]![3]
            #expect(lap.duration > platinum - 5 && lap.duration < platinum + 1, "\(layout.id): \(lap.duration)")
            #expect(zip(lap.times, lap.times.dropFirst()).allSatisfy { $0 < $1 })
            // Any time, wrapped to the lap.
            let point = lap.position(at: lap.times[5] - lap.duration * 2)
            #expect(lap.position(at: 0) == lap.points[0] && hypot(point.x - lap.points[5].x, point.y - lap.points[5].y) < 0.01)
        }
    }
}
