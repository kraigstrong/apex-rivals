import Foundation
import SwiftUI
import Testing
@testable import Apex

struct AchievementTests {
    let ardennes = TrackLayout.ardennes

    @Test func everyMedalOnEveryCircuitHasTheAchievementInAppStoreConnect() {
        // A failure means a circuit or medal was added or renamed: create its achievements in App Store Connect (see
        // docs/apex-testflight.md) and its art (AchievementArtTests), then add them here.
        let circuits = ["ardennes", "swirl", "snake", "mirage", "island", "harbor"]
        let expected = Set(circuits.flatMap { id in
            ["bronze", "silver", "gold", "platinum"].map { "apex.\(id).\($0)" }
        })
        let ids = Set(TrackLayout.all.flatMap { layout in Medal.allCases.map { $0.achievementID(on: layout) } })
        #expect(ids == expected)
    }

    @Test func aLapEarnsItsMedalAndEveryOneBelowIt() throws {
        let gold = try #require(Medal.gold.target(on: ardennes))
        #expect(Medal.achievements(earnedBy: gold, on: ardennes)
            == ["apex.ardennes.bronze", "apex.ardennes.silver", "apex.ardennes.gold"])
        #expect(Medal.achievements(earnedBy: 10, on: ardennes).count == 4)
        #expect(Medal.achievements(earnedBy: 60, on: ardennes).isEmpty)
        #expect(Medal.achievements(earnedBy: nil, on: ardennes).isEmpty)
        #expect(Medal.achievements(earnedBy: 10, on: .apexSchool).isEmpty)
    }

    @Test func savedBestsEarnTheirCircuitsMedals() throws {
        let name = "AchievementTests.saved"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        #expect(Medal.achievementsEarnedBySavedBests(defaults: defaults).isEmpty)

        let silver = try #require(Medal.silver.target(on: .swirl))
        LapStore.save(LapRecord(time: silver, splits: [], ghost: []), for: Track(.swirl), defaults: defaults)
        LapStore.save(LapRecord(time: 60, splits: [], ghost: []), for: Track(.snake), defaults: defaults)
        #expect(Medal.achievementsEarnedBySavedBests(defaults: defaults) == ["apex.swirl.bronze", "apex.swirl.silver"])
    }
}

/// Draws the achievements' art into `Art/achievements`: a circuit's outline on a disc rimmed in the medal's color,
/// 1024 pixels square (Game Center shows it in a circle). Only runs when asked, since it writes into the repo:
///
///     TEST_RUNNER_APEX_DRAW_ACHIEVEMENTS=1 xcodebuild test ... -only-testing:ApexTests/AchievementArtTests
struct AchievementArtTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APEX_DRAW_ACHIEVEMENTS"] != nil))
    @MainActor func draw() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Art/achievements")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for layout in TrackLayout.all {
            let track = Track(layout)
            for medal in Medal.allCases {
                let renderer = ImageRenderer(content: AchievementBadge(medal: medal, track: track))
                renderer.scale = 4
                renderer.isOpaque = true
                let png = try #require(renderer.uiImage?.pngData())
                try png.write(to: folder.appending(path: medal.achievementID(on: layout) + ".png"))
            }
        }
    }
}

/// One achievement's art, 256 points square: a ring in the medal's color around the circuit, drawn as big as the disc
/// holds and thick enough to read at the size Game Center shows achievements.
struct AchievementBadge: View {
    let medal: Medal
    let track: Track

    private let disc: CGFloat = 100
    private let lineWidth: CGFloat = 7

    /// The circuit's frame: its shape's proportions, with corners (plus the line's glow) just inside the disc.
    private var outline: CGSize {
        let aspect = track.bounds.width / track.bounds.height
        let height = 2 * (disc - lineWidth * 2) / (1 + aspect * aspect).squareRoot()
        return CGSize(width: aspect * height, height: height)
    }

    var body: some View {
        ZStack {
            medal.color
            Circle().fill(Color(white: 0.11)).frame(width: disc * 2, height: disc * 2)
            TrackOutline(track: track, lineWidth: lineWidth).frame(width: outline.width, height: outline.height)
        }
        .frame(width: 256, height: 256)
    }
}
