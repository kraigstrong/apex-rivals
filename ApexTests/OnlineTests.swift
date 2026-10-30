import Foundation
import Testing
@testable import Apex

/// Leaderboards only compare laps driven on the same circuit with the same physics. These pin both, so a change that
/// would move lap times fails here until it's given a new version (and so a new leaderboard).
struct FreezeTests {
    @Test func physicsMatchesItsVersion() {
        // A failure means the car changed. Once boards are live, bump `RaceTuning.physicsVersion` and add its signature.
        let signatures = [1: "93a7f30b1b41fad9", 2: "4d73b39228fdfde0"]
        #expect(signatures[RaceTuning.physicsVersion] == LapStore.fingerprint(RaceTuning.lapSignature))
        #expect(signatures[RaceTuning.physicsVersion] == RaceTuning.physicsFingerprint)
        #expect(RaceTuning.isStock)
        #expect(RaceTuning.physicsStep == 1.0 / 240)
    }

    @Test func circuitsMatchTheirRevisions() {
        // A failure means a circuit's shape changed. Once its board is live, bump its `revision` and add the signature.
        let signatures = [
            "ardennes.1": "361e53068f255da0",
            "swirl.1": "b41cb960ba96883b",
            "snake.1": "9e81af1a445d6099",
            "mirage.1": "fee011a2a6e7a2",
            "island.1": "4af6a572035d9fa6",
            "harbor.1": "4bc651367b3ce1b8",
        ]
        for layout in TrackLayout.all {
            #expect(signatures["\(layout.id).\(layout.revision)"] == LapStore.fingerprint(layout.signature), "\(layout.id)")
        }
    }

    @Test func leaderboardIDsNameTheBoard() {
        let board = RaceBoard(track: Track(.ardennes))
        #expect(board.leaderboardID == "apex.ardennes.r1.p\(RaceTuning.physicsVersion)")
    }
}

struct RivalTests {
    static let track = Track(.ardennes)
    static let line = RacingLine(track: track)

    @Test(arguments: [27.5, 29.0, 31.0])
    func botsLapCloseToTheirTarget(target: Double) {
        let lap = RivalBot.lap(near: target, track: Self.track, line: Self.line)
        #expect(abs(lap.time - target) < 0.25, "Asked for \(target), got \(lap.time)")
        #expect(lap.ghost.count > Int(lap.time * RaceTuning.ghostSampleRate) - 2)
    }

    @Test func noBotBeatsThePerfectLine() {
        let lap = RivalBot.lap(near: 20, track: Self.track, line: Self.line)
        #expect(lap.time > 25)
    }
}

struct OnlineTests {
    @Test func ghostsSurviveTheWireFormat() throws {
        let samples = [GhostSample(s: 12.34, n: -40.06, psi: 0.123), GhostSample(s: 12_590.5, n: 3.2, psi: -0.5)]
        let trace = try JSONDecoder().decode(GhostTrace.self, from: JSONEncoder().encode(GhostTrace(samples)))
        for (a, b) in zip(trace.samples, samples) {
            #expect(abs(a.s - b.s) <= 0.05)
            #expect(abs(a.n - b.n) <= 0.05)
            #expect(abs(a.psi - b.psi) <= 0.0005)
        }
    }

    @Test func playerTokensMatchTheServer() {
        // The same value BrightBench's `playerToken('T:_racer1')` gives: SHA-256 of "apex:T:_racer1", in hex.
        #expect(ApexOnline.playerToken("T:_racer1") == "2875da87c19cb7ed75a836acdbe89118fba9c47d0382c86197d52c53c2b1e151")
    }

    @Test func lapEntriesAreWholeMillisecondsAndNameTheBoard() {
        let board = RaceBoard(trackID: "ardennes", trackRevision: 1, physicsVersion: 1)
        let entry = LapEntry(lap: LapRecord(time: 28.5976, splits: [10.1234, 19.0005], ghost: []), board: board, walls: 2)
        #expect(entry == LapEntry(lap: LapRecord(time: 28.598, splits: [10.123, 19.001], ghost: []), board: board,
                                  walls: 2))
        #expect(entry.ms == 28_598)
        #expect(entry.track == "ardennes" && entry.revision == 1 && entry.physics == 1)
    }

    func entry(_ ms: Int) -> LapEntry {
        LapEntry(lap: LapRecord(time: Double(ms) / 1000, splits: [], ghost: []),
                 board: RaceBoard(trackID: "ardennes", trackRevision: 1), walls: 0)
    }

    /// Nothing is signed in to Game Center during tests, so a new best counts as sent nowhere and waits for sign-in.
    @Test func aBestSetWhileSignedOutWaitsToBeSent() throws {
        let defaults = try freshDefaults("OnlineTests.delivery")
        let best = LapRecord(time: 29.5, splits: [10, 20], ghost: [])
        BestLapDelivery.send(best, on: RaceBoard(layout: .ardennes), key: "best", defaults: defaults)
        for destination in BestLapDelivery.Destination.allCases {
            #expect(defaults.object(forKey: BestLapDelivery.sentKey("best", destination)) == nil)
        }
    }

    func freshDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func lapsWaitOnTheDeviceWhileOffline() throws {
        let defaults = try freshDefaults("OnlineTests.offline")
        var sent = 0
        let log = LapLog(defaults: defaults) { _, done in sent += 1; done(false) }
        log.record(entry(28_598), enabled: false)
        log.record(entry(29_100), enabled: false)
        #expect(sent == 0)
        // Still there after a relaunch.
        #expect(LapLog(defaults: defaults) { _, _ in }.pending.map(\.ms) == [28_598, 29_100])
    }

    // On the main actor, since each batch's removal lands on the main queue: the test can't start, and its wait can't
    // run out, while something else holds the main thread (on CI, as long as 40 s early in a run).
    @MainActor @Test func lapsGoInBatchesAndLeaveTheQueueOnceSent() async throws {
        let defaults = try freshDefaults("OnlineTests.batches")
        let offline = LapLog(defaults: defaults) { _, done in done(false) }
        for i in 0..<30 { offline.record(entry(28_000 + i), enabled: false) }

        var batches: [Int] = []
        let log = LapLog(defaults: defaults) { batch, done in
            batches.append(batch.laps.count)
            done(true)
        }
        log.flush(enabled: true)
        // Both removals run on the main queue while this waits.
        let deadline = ContinuousClock.now + .seconds(10)
        while !log.pending.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(batches == [25, 5])
        #expect(log.pending.isEmpty)
    }

    @Test func lapsTheServiceWouldRefuseAreSkipped() throws {
        let log = LapLog(defaults: try freshDefaults("OnlineTests.refused")) { _, done in done(false) }
        log.record(entry(9_000), enabled: false)
        log.record(entry(150_000), enabled: false)
        log.record(entry(28_598), enabled: false)
        #expect(log.pending.map(\.ms) == [28_598])
    }

    @Test func aFullQueueKeepsItsOldestLaps() throws {
        let defaults = try freshDefaults("OnlineTests.full")
        let log = LapLog(defaults: defaults) { _, done in done(false) }
        for i in 0..<(LapLog.maxPending + 5) { log.record(entry(28_000 + i), enabled: false) }
        #expect(log.pending.count == LapLog.maxPending)
        #expect(log.pending.first?.ms == 28_000)
    }
}

struct StandingTests {
    @Test func readsTheServersAnswer() throws {
        let json = #"{"faster":2,"players":4,"histogram":{"fromMs":27250,"widthMs":250,"counts":[1,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,1]}}"#
        let standing = try JSONDecoder().decode(Standing.self, from: Data(json.utf8))
        #expect(standing.place == 3)
        #expect(standing.beatenShare == 0.5)
        #expect(standing.histogram.counts.reduce(0, +) == 4)
    }

    @Test func aLapAheadOfEveryoneBeatsThemAll() {
        let standing = Standing(faster: 0, players: 10, histogram: .init(fromMs: 28_000, widthMs: 250, counts: [10]))
        #expect(standing.place == 1)
        #expect(standing.beatenShare == 1)
    }

    /// `faster` other players ahead of you, of `others`.
    func standing(_ faster: Int, of others: Int) -> Standing {
        Standing(faster: faster, players: others, histogram: .init(fromMs: 28_000, widthMs: 250, counts: [others]))
    }

    @Test func theFirstOnABoardSaysSo() {
        let alone = standing(0, of: 0)
        #expect(alone.headline == "You're the first!")
        #expect(alone.detail == nil)
        #expect(alone.line == "You're the first!")
    }

    @Test func firstPlaceIsFastestOnAnyBoard() {
        for others in [1, 8, 289] {
            let first = standing(0, of: others)
            #expect(first.headline == "Fastest")
            #expect(first.detail == "of \(others + 1) players")
            #expect(first.line == "Fastest of \(others + 1) players")
        }
    }

    @Test func aSmallBoardShowsYourPlaceAndEachPlayer() {
        // Nine players counting you is still small; ten isn't.
        #expect(standing(1, of: 8).isSmallBoard)
        #expect(!standing(1, of: 9).isSmallBoard)
        let second = standing(1, of: 1)
        #expect(second.headline == "2nd of 2")
        #expect(second.detail == nil)
        #expect(second.line == "2nd of 2 players")
        #expect(standing(4, of: 8).headline == "5th of 9")
    }

    @Test func aBigBoardShowsTheTopShareYoureIn() {
        let mid = standing(33, of: 289)
        #expect(mid.headline == "Top 12%")
        #expect(mid.detail == "34th of 290")
        #expect(mid.line == "Top 12% · 34th of 290")
        // Rounded up, so it never claims a better share than your place.
        #expect(standing(1, of: 99).headline == "Top 2%")
        #expect(standing(2, of: 9).headline == "Top 30%")
        #expect(standing(4, of: 9).headline == "Top 50%")
    }

    @Test func theSlowerHalfOfABigBoardShowsYourPlace() {
        let slow = standing(211, of: 289)
        #expect(slow.headline == "212th of 290")
        #expect(slow.detail == nil)
        #expect(slow.line == "212th of 290 players")
        #expect(standing(5, of: 9).headline == "6th of 10")
    }

    @Test func ordinalsReadAsWords() {
        let ordinals = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 11: "11th", 12: "12th", 13: "13th", 21: "21st",
                        22: "22nd", 101: "101st", 111: "111th", 112: "112th", 213: "213th"]
        for (n, word) in ordinals { #expect(Standing.ordinal(n) == word) }
    }

    /// The chart colors your bucket: none when you're ahead of everyone, the last one (it holds the slow tail) when
    /// you're behind the range.
    @Test func aLapFallsInItsBucket() {
        let histogram = Standing.Histogram(fromMs: 27_500, widthMs: 250, counts: [1, 0, 2])
        #expect(histogram.bucket(of: 25_414) == nil)
        #expect(histogram.bucket(of: 27_499) == nil)
        #expect(histogram.bucket(of: 27_500) == 0)
        #expect(histogram.bucket(of: 27_750) == 1)
        #expect(histogram.bucket(of: 28_100) == 2)
        #expect(histogram.bucket(of: 31_000) == 2)
        #expect(Standing.Histogram(fromMs: 0, widthMs: 250, counts: []).bucket(of: 28_000) == nil)
    }

    @Test func samplePlayersAreStableAndSpreadLikeRealLaps() {
        let sample = Standing.sample(for: 28_598)
        #expect(sample == Standing.sample(for: 28_598))
        #expect(sample.players == 240)
        #expect(sample.histogram.counts.reduce(0, +) == 240)
        #expect(sample.histogram.counts.count <= 40)
        // A 28.6 sits well up the field, but not at the top.
        #expect((0.5...0.95).contains(sample.beatenShare))
        #expect(Standing.sample(for: 26_000).beatenShare == 1)
    }
}
