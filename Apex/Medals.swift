import SwiftUI

/// A medal for a lap on a circuit. Each tier's time is a bot's lap there (`RaceTuning.medalTimes`): bronze a sloppy
/// weaver's, silver holding the middle of the road, gold the ideal line at human reaction speed, and platinum the ideal
/// line at a quick 50 ms. Apex School has none.
enum Medal: Int, CaseIterable, Comparable, Identifiable {
    case bronze, silver, gold, platinum

    var id: Int { rawValue }

    static func < (a: Medal, b: Medal) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.86, green: 0.55, blue: 0.3)
        case .silver: return Color(red: 0.8, green: 0.83, blue: 0.88)
        case .gold: return Color(red: 1, green: 0.8, blue: 0.2)
        case .platinum: return Color(red: 0.55, green: 0.95, blue: 0.95)
        }
    }

    /// The lap time that earns this medal on a circuit, or nil on a circuit without medals.
    func target(on layout: TrackLayout) -> Double? {
        RaceTuning.medalTimes[layout.id].flatMap { $0.indices.contains(rawValue) ? $0[rawValue] : nil }
    }

    /// The best medal a lap of `time` earns: its target or faster. Only the stock car earns medals, since a tuned car's
    /// laps aren't the race the targets were set for.
    static func earned(by time: Double?, on layout: TrackLayout) -> Medal? {
        guard let time, RaceTuning.isStock else { return nil }
        return allCases.last { medal in medal.target(on: layout).map { time <= $0 } ?? false }
    }

    /// The medal a lap of `time` wins that the best lap before it (`previous`) hadn't, or nil if it wins nothing new.
    static func newlyWon(by time: Double, after previous: Double?, on layout: TrackLayout) -> Medal? {
        guard let medal = earned(by: time, on: layout) else { return nil }
        if let had = earned(by: previous, on: layout), had >= medal { return nil }
        return medal
    }

    /// The medal to chase after a best lap of `time` (the first one it hasn't earned), and the lap that earns it. Nil
    /// once platinum's won, and on a circuit without medals.
    static func next(after time: Double?, on layout: TrackLayout) -> (medal: Medal, target: Double)? {
        guard RaceTuning.isStock else { return nil }
        let earned = earned(by: time, on: layout)
        for medal in allCases where earned.map({ medal > $0 }) ?? true {
            if let target = medal.target(on: layout) { return (medal, target) }
        }
        return nil
    }
}

/// A medal, in its color.
struct MedalIcon: View {
    let medal: Medal
    var size: CGFloat = 14
    /// An outline, for a medal not won yet.
    var earned = true

    var body: some View {
        Image(systemName: earned ? "medal.fill" : "medal")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(medal.color.opacity(earned ? 1 : 0.8))
            .accessibilityLabel("\(medal.name) medal")
    }
}

/// The next medal and the lap it takes: an outline and "26.6", or with its name, "Platinum 26.6".
struct NextMedalLabel: View {
    let medal: Medal
    let target: Double
    var size: CGFloat = 12
    var showsName = false

    var body: some View {
        HStack(spacing: 3) {
            MedalIcon(medal: medal, size: size, earned: false)
            Text((showsName ? medal.name + " " : "") + LapFormat.time(target, decimals: 1))
                .font(.system(size: size + 1, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(medal.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next: \(medal.name) at \(LapFormat.time(target, decimals: 1)) seconds")
    }
}
