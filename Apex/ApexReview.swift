import Foundation

/// When Ghost Thread asks for an App Store rating: after a high point, the player's first gold medal and then their
/// first platinum, on any circuit, the next time the track list is up with nothing over it. Never over a race, its
/// summary or the unlock's screen, at most `RaceTuning.reviewRequestLimit` times, `RaceTuning.reviewRetryInterval`
/// apart, and only from App Store builds (TestFlight can't show the sheet, and Xcode builds would show it every time).
/// Kept on this device. StoreKit doesn't say whether its sheet appeared, so this counts requests, not ratings. Modeled
/// on Bigger Fish's `ArcadeReview`.
final class ApexReview {
    static let shared = ApexReview()

    /// A high point a medal can reach. Raw values are what's saved.
    enum HighPoint: String, Codable, CaseIterable {
        case gold, platinum

        /// The high points a medal reaches: platinum reaches gold too.
        static func reached(by medal: Medal) -> Set<HighPoint> {
            Set(allCases.filter { medal >= $0.medal })
        }

        var medal: Medal { self == .gold ? .gold : .platinum }
    }

    private struct State: Codable {
        var pending = false
        var requestCount = 0
        var lastRequest: Date?
        var reached: Set<HighPoint> = []
    }

    private let defaults: UserDefaults
    static let key = "apex.review.v1"
    private var state: State

    /// `savedMedals` are the medals the device's best laps have already won: a device that reached gold before it
    /// could ask (a beta tester's) doesn't count that gold as new.
    init(defaults: UserDefaults = .standard, savedMedals: () -> [Medal] = ApexReview.savedBestMedals) {
        self.defaults = defaults
        if let saved = defaults.data(forKey: Self.key).flatMap({ try? JSONDecoder().decode(State.self, from: $0) }) {
            state = saved
        } else {
            state = State()
            state.reached = savedMedals().reduce(into: []) { $0.formUnion(HighPoint.reached(by: $1)) }
            save()
        }
    }

    /// A best lap won `medal`, new on its circuit (nil: none). Reaching gold or platinum for the first time anywhere
    /// makes the next quiet moment on the track list ask.
    func won(_ medal: Medal?, now: Date = Date()) {
        guard let medal else { return }
        let new = HighPoint.reached(by: medal).subtracting(state.reached)
        guard !new.isEmpty else { return }
        state.reached.formUnion(new)
        if isEligible(now: now) { state.pending = true }
        save()
    }

    /// Whether to ask now. `channel` is the build's (`ApexOnline.channel`): only App Store builds ask.
    func shouldRequest(channel: String, now: Date = Date()) -> Bool {
        channel == "appstore" && state.pending && isEligible(now: now)
    }

    /// Call when handing the request to StoreKit.
    func didRequest(now: Date = Date()) {
        state.pending = false
        state.requestCount += 1
        state.lastRequest = now
        save()
    }

    private func isEligible(now: Date) -> Bool {
        guard state.requestCount < RaceTuning.reviewRequestLimit else { return false }
        guard let last = state.lastRequest else { return true }
        return now.timeIntervalSince(last) >= RaceTuning.reviewRetryInterval
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }

    /// The medals the saved best laps have won, one per circuit.
    static func savedBestMedals() -> [Medal] {
        TrackLayout.all.compactMap { layout in LapStore.load(for: layout).flatMap { Medal.earned(by: $0.time, on: layout) } }
    }
}
