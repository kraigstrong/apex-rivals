import Foundation
import Testing
@testable import Apex

/// A rating is asked for after the first gold medal and the first platinum, from App Store builds only, at most twice,
/// 90 days apart.
struct ApexReviewTests {
    private func fresh(saved: [Medal] = []) -> (ApexReview, UserDefaults) {
        let defaults = UserDefaults(suiteName: "apex.tests.\(UUID().uuidString)")!
        return (ApexReview(defaults: defaults, savedMedals: { saved }), defaults)
    }

    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func theFirstGoldAsksOnceAndOnlyFromTheAppStore() {
        let (review, _) = fresh()
        review.won(.bronze, now: start)
        review.won(.silver, now: start)
        review.won(nil, now: start)
        #expect(!review.shouldRequest(channel: "appstore", now: start))
        review.won(.gold, now: start)
        #expect(review.shouldRequest(channel: "appstore", now: start))
        #expect(!review.shouldRequest(channel: "testflight", now: start) && !review.shouldRequest(channel: "debug", now: start))
        review.didRequest(now: start)
        #expect(!review.shouldRequest(channel: "appstore", now: start))
        // A gold on another circuit isn't a first.
        review.won(.gold, now: start + 200 * day)
        #expect(!review.shouldRequest(channel: "appstore", now: start + 200 * day))
    }

    @Test func theFirstPlatinumAsksAgainOnlyNinetyDaysOn() {
        let (soon, _) = fresh()
        soon.won(.gold, now: start)
        soon.didRequest(now: start)
        soon.won(.platinum, now: start + 30 * day)
        #expect(!soon.shouldRequest(channel: "appstore", now: start + 120 * day), "too soon after the gold's: it passes")

        let (later, _) = fresh()
        later.won(.gold, now: start)
        later.didRequest(now: start)
        later.won(.platinum, now: start + 91 * day)
        #expect(later.shouldRequest(channel: "appstore", now: start + 91 * day))
        later.didRequest(now: start + 91 * day)
        // Twice at most, ever.
        #expect(!later.shouldRequest(channel: "appstore", now: start + 400 * day))
    }

    @Test func aPlatinumFirstReachesGoldWithIt() {
        let (review, _) = fresh()
        review.won(.platinum, now: start)
        review.didRequest(now: start)
        review.won(.gold, now: start + 200 * day)
        #expect(!review.shouldRequest(channel: "appstore", now: start + 200 * day))
    }

    /// A device whose best laps already won gold (a beta tester's) starts with gold reached; platinum is still to come.
    @Test func medalsWonBeforeItCouldAskAreNotNew() {
        let (review, _) = fresh(saved: [.silver, .gold])
        review.won(.gold, now: start)
        #expect(!review.shouldRequest(channel: "appstore", now: start))
        review.won(.platinum, now: start)
        #expect(review.shouldRequest(channel: "appstore", now: start))
    }

    @Test func aRequestDueSurvivesARelaunch() {
        let (review, defaults) = fresh()
        review.won(.gold, now: start)
        let relaunched = ApexReview(defaults: defaults, savedMedals: { [.gold] })
        #expect(relaunched.shouldRequest(channel: "appstore", now: start))
    }
}
