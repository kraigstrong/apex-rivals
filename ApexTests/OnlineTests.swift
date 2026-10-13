import Foundation
import Testing
@testable import Apex

/// Leaderboards only compare laps driven on the same circuit with the same physics. These pin both, so a change that
/// would move lap times fails here until it's given a new version (and so a new leaderboard).
struct FreezeTests {
    @Test func physicsMatchesItsVersion() {
        // A failure means the car changed. Once boards are live, bump `RaceTuning.physicsVersion` and add its signature.
        let signatures = [1: "ac17662e2de184ad"]
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

    @Test func lapsGoInBatchesAndLeaveTheQueueOnceSent() async throws {
        let defaults = try freshDefaults("OnlineTests.batches")
        let offline = LapLog(defaults: defaults) { _, done in done(false) }
        for i in 0..<30 { offline.record(entry(28_000 + i), enabled: false) }

        var batches: [Int] = []
        let log = LapLog(defaults: defaults) { batch, done in
            batches.append(batch.laps.count)
            done(true)
        }
        log.flush(enabled: true)
        // Each batch's removal lands on the main queue; wait for both.
        for _ in 0..<100 where !log.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
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
