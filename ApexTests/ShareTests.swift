import Testing
import UIKit
@testable import Apex

struct ShareTests {
    static let track = Track(.ardennes)

    /// A bot's flying lap, so the record has a real line.
    static let lap: LapRecord = {
        let session = RaceSession(track: track)
        let line = RacingLine(track: track)
        var driver = AutoDriver(line: { line.offset(at: $0) })
        session.start()
        var laps = 0
        while laps < 2, session.clock < 200 {
            for event in session.advance(by: RaceTuning.physicsStep, control: { driver.decide($0) }) {
                if case .timing(.lap) = event { laps += 1 }
            }
        }
        return session.timer.lastRecord!
    }()

    @Test func theMessageHasTheTimeTheCircuitTheMedalAndTheLink() {
        let share = LapShare(track: Self.track, lap: Self.lap, medal: .gold, standing: nil)
        #expect(share.message.hasPrefix(LapFormat.time(Self.lap.time) + " at Ardennes in Needle, a gold medal lap."))
        #expect(share.message.hasSuffix("Beat it: " + ApexLinks.join.absoluteString))
    }

    @Test func aLapWithoutAMedalSaysNothingAboutOne() {
        let share = LapShare(track: Self.track, lap: Self.lap, medal: nil, standing: nil)
        #expect(!share.message.contains("medal"))
    }

    @Test func theCardBoastsOnlyWhenTheLapBeatsSomeone() {
        let histogram = Standing.Histogram(fromMs: 27_000, widthMs: 250, counts: [1])
        let last = Standing(faster: 4, players: 4, histogram: histogram)
        let third = Standing(faster: 2, players: 4, histogram: histogram)
        let alone = Standing(faster: 0, players: 0, histogram: histogram)
        #expect(LapShare(track: Self.track, lap: Self.lap, medal: nil, standing: last).boast == nil)
        #expect(LapShare(track: Self.track, lap: Self.lap, medal: nil, standing: third).boast == third)
        #expect(LapShare(track: Self.track, lap: Self.lap, medal: nil, standing: alone).boast == nil)
    }

    @Test func theLinkIsThePublicBeta() {
        #expect(ApexLinks.join.host == "testflight.apple.com")
    }

    @MainActor @Test func theCardRendersAtTwiceItsSize() throws {
        let standing = Standing(faster: 3, players: 10, histogram: .init(fromMs: 27_000, widthMs: 250, counts: [1, 2, 3]))
        let share = LapShare(track: Self.track, lap: Self.lap, medal: .platinum, standing: standing)
        let image = try #require(share.image())
        #expect(image.size == ShareCard.size)
        #expect(image.scale == 2)
    }
}
