import CryptoKit
import Foundation
import GameKit

/// The lap service on BrightBench (`/api/apex`). Every finished lap is counted into anonymous lap-time histograms per
/// board; each personal best's ghost is shared under the player's Game Center alias; and rivals come back from other
/// players' ghosts. When it can't be reached, laps wait on the device and rivals are bots.
enum ApexOnline {
    static let isEnabled = true
    static let base = URL(string: "https://brightbench.app/api/apex")!
    /// A public noise filter, not authentication: the server validates everything it stores.
    static let appKey = "apex-laps-v1"

    /// Where this build came from: "debug" (Xcode), "testflight", or "appstore".
    static var channel: String {
        #if DEBUG
        return "debug"
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore"
        #endif
    }

    /// How the service names the signed-in player when it needs to leave out their own best: SHA-256 of "apex:" and
    /// their team player ID, sent in a header so the raw ID never appears in a URL.
    static func playerToken(_ teamPlayerID: String) -> String {
        SHA256.hash(data: Data("apex:\(teamPlayerID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
}

// MARK: Wire format (keep in sync with BrightBench's apps/marketing/src/lib/apex-laps.ts)

/// One finished lap, with nothing about who drove it. Times are whole milliseconds.
struct LapEntry: Codable, Equatable {
    var track: String
    var revision: Int
    var physics: Int
    var ms: Int
    /// Lap time at the end of sectors 1 and 2.
    var splits: [Int]
    var walls: Int

    init(lap: LapRecord, board: RaceBoard, walls: Int) {
        track = board.trackID
        revision = board.trackRevision
        physics = board.physicsVersion
        ms = Int((lap.time * 1000).rounded())
        splits = lap.splits.map { Int(($0 * 1000).rounded()) }
        self.walls = walls
    }
}

struct LapBatch: Codable, Equatable {
    var schema = 1
    var appVersion: String
    var build: String
    var channel: String
    var laps: [LapEntry]
}

/// A ghost in whole numbers: s and n in tenths of a unit, the nose's angle in milliradians, 30 samples a second.
struct GhostTrace: Codable, Equatable {
    var s: [Int]
    var n: [Int]
    var psi: [Int]

    init(_ samples: [GhostSample]) {
        s = samples.map { Int((Double($0.s) * 10).rounded()) }
        n = samples.map { Int((Double($0.n) * 10).rounded()) }
        psi = samples.map { Int((Double($0.psi) * 1000).rounded()) }
    }

    var samples: [GhostSample] {
        zip(s, zip(n, psi)).map { GhostSample(s: Float($0) / 10, n: Float($1.0) / 10, psi: Float($1.1) / 1000) }
    }
}

struct GhostUpload: Codable {
    struct Player: Codable {
        /// Game Center's `teamPlayerID`.
        var id: String
        var alias: String
    }

    /// Game Center's identity verification signature, so the server knows the ghost is really this player's.
    struct Identity: Codable {
        var publicKeyURL: String
        var signature: String
        var salt: String
        var timestamp: UInt64
    }

    var schema = 1
    var track: String
    var revision: Int
    var physics: Int
    var ms: Int
    var splits: [Int]
    var player: Player
    var identity: Identity
    var ghost: GhostTrace
}

/// The server's answer to "who should I chase?".
struct RivalGhost: Codable {
    var alias: String
    var ms: Int
    var splits: [Int]
    var ghost: GhostTrace

    var rival: Rival {
        Rival(name: alias,
              record: LapRecord(time: Double(ms) / 1000, splits: splits.map { Double($0) / 1000 }, ghost: ghost.samples),
              source: .player)
    }
}

/// Where a lap falls among other players' bests on its board.
struct Standing: Codable, Equatable {
    struct Histogram: Codable, Equatable {
        var fromMs: Int
        var widthMs: Int
        var counts: [Int]
    }

    /// Other players whose best beats the lap.
    var faster: Int
    /// Other players on the board.
    var players: Int
    /// Their bests, bucketed.
    var histogram: Histogram

    /// The share of other players the lap beats (ties count as beaten).
    var beatenShare: Double { players > 0 ? Double(players - faster) / Double(players) : 1 }
    /// The lap's place counting you: 1 is fastest.
    var place: Int { faster + 1 }

    /// Made-up players for Xcode builds while the lap service is off, so the session summary can be seen: 240 bests
    /// spread like the bots' laps, from near-perfect to sloppy.
    static func sample(for ms: Int) -> Standing {
        var random = SplitMix64(seed: 2026)
        let times = (0..<240).map { _ -> Int in
            let spread = -log(max(random.unit(), 1e-9)) - log(max(random.unit(), 1e-9))
            return Int((26_100 + 2_100 * spread).rounded())
        }
        let sorted = times.sorted()
        let high = sorted[Int((Double(sorted.count) * 0.98).rounded(.up)) - 1]
        var width = 250
        while (high - sorted[0]) / width + 1 > 40 { width += 250 }
        let from = sorted[0] / width * width
        var counts = [Int](repeating: 0, count: (high - from) / width + 1)
        for t in sorted { counts[min(counts.count - 1, (t - from) / width)] += 1 }
        return Standing(faster: times.filter { $0 < ms }.count, players: times.count,
                        histogram: Histogram(fromMs: from, widthMs: width, counts: counts))
    }
}

// MARK: Sending

/// Every finished lap, queued on the device and sent in batches whenever the service is reachable.
final class LapLog {
    static let shared = LapLog()
    static let batchSize = 25
    static let maxPending = 500

    private let defaults: UserDefaults
    private let key = "apex.lapLog.v1"
    private let send: (LapBatch, @escaping (Bool) -> Void) -> Void
    private(set) var pending: [LapEntry]
    private var sending = false

    /// - Parameter send: Delivers a batch and reports whether to drop it from the queue (sent, or refused for good).
    init(defaults: UserDefaults = .standard,
         send: @escaping (LapBatch, @escaping (Bool) -> Void) -> Void = ApexService.send) {
        self.defaults = defaults
        self.send = send
        pending = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([LapEntry].self, from: $0) } ?? []
    }

    /// Lap times the service accepts, in milliseconds. A lap outside them would get its whole batch refused.
    static let acceptedTimes = 10_000...120_000

    func record(_ entry: LapEntry, enabled: Bool = ApexOnline.isEnabled) {
        // A full queue keeps its oldest laps; it only fills while the service is unreachable for hundreds of laps.
        guard pending.count < Self.maxPending, Self.acceptedTimes.contains(entry.ms) else { return }
        pending.append(entry)
        save()
        flush(enabled: enabled)
    }

    func flush(enabled: Bool = ApexOnline.isEnabled) {
        guard enabled, !sending, !pending.isEmpty else { return }
        sending = true
        let laps = Array(pending.prefix(Self.batchSize))
        let batch = LapBatch(appVersion: ApexOnline.appVersion, build: ApexOnline.build, channel: ApexOnline.channel,
                             laps: laps)
        send(batch) { [weak self] done in
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                guard done else { return }
                self.pending.removeFirst(min(laps.count, self.pending.count))
                self.save()
                self.flush(enabled: enabled)
            }
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: key)
    }
}

enum ApexService {
    private static func request(_ path: String, method: String = "POST", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: ApexOnline.base.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ApexOnline.appKey, forHTTPHeaderField: "X-App-Key")
        return request
    }

    /// Lets the service leave out the signed-in player's own best.
    private static func identify(_ request: inout URLRequest) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        request.setValue(ApexOnline.playerToken(GKLocalPlayer.local.teamPlayerID), forHTTPHeaderField: "X-Apex-Player")
    }

    static func send(_ batch: LapBatch, completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONEncoder().encode(batch) else { return completion(true) }
        URLSession.shared.dataTask(with: request("laps", body: body)) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Sent, or refused as invalid (it would never succeed): drop it. Busy or offline: keep it for later.
            completion(status == 204 || status == 400 || status == 413)
        }.resume()
    }

    /// Shares a personal best's ghost under the player's Game Center alias, so it can be someone else's rival.
    static func shareBest(_ lap: LapRecord, on board: RaceBoard) {
        let player = GKLocalPlayer.local
        guard ApexOnline.isEnabled, player.isAuthenticated else { return }
        player.fetchItems { url, signature, salt, timestamp, error in
            guard error == nil, let url, let signature, let salt else { return }
            let upload = GhostUpload(
                track: board.trackID, revision: board.trackRevision, physics: board.physicsVersion,
                ms: Int((lap.time * 1000).rounded()), splits: lap.splits.map { Int(($0 * 1000).rounded()) },
                player: .init(id: player.teamPlayerID, alias: player.alias),
                identity: .init(publicKeyURL: url.absoluteString, signature: signature.base64EncodedString(),
                                salt: salt.base64EncodedString(), timestamp: timestamp),
                ghost: GhostTrace(lap.ghost))
            guard let body = try? JSONEncoder().encode(upload) else { return }
            URLSession.shared.dataTask(with: request("ghosts", body: body)).resume()
        }
    }

    /// Where `lapTime` falls among other players' bests on the board, or nil if the service can't say.
    static func standing(of lapTime: Double, on board: RaceBoard, completion: @escaping (Standing?) -> Void) {
        var components = URLComponents(url: ApexOnline.base.appendingPathComponent("standing"),
                                       resolvingAgainstBaseURL: false)
        let items = [
            URLQueryItem(name: "track", value: board.trackID),
            URLQueryItem(name: "revision", value: String(board.trackRevision)),
            URLQueryItem(name: "physics", value: String(board.physicsVersion)),
            URLQueryItem(name: "ms", value: String(Int((lapTime * 1000).rounded()))),
        ]
        components?.queryItems = items
        guard let url = components?.url else { return completion(nil) }
        var request = request("standing", method: "GET")
        request.url = url
        identify(&request)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let standing = try? JSONDecoder().decode(Standing.self, from: data) else { return completion(nil) }
            completion(standing)
        }.resume()
    }

    /// Another player's ghost that beats `best` by `RaceTuning.rivalWindow`, or nil.
    static func rival(on board: RaceBoard, beating best: Double, completion: @escaping (Rival?) -> Void) {
        var components = URLComponents(url: ApexOnline.base.appendingPathComponent("rival"), resolvingAgainstBaseURL: false)
        let items = [
            URLQueryItem(name: "track", value: board.trackID),
            URLQueryItem(name: "revision", value: String(board.trackRevision)),
            URLQueryItem(name: "physics", value: String(board.physicsVersion)),
            URLQueryItem(name: "ms", value: String(Int((best * 1000).rounded()))),
        ]
        components?.queryItems = items
        guard let url = components?.url else { return completion(nil) }
        var request = request("rival", method: "GET")
        request.url = url
        identify(&request)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let ghost = try? JSONDecoder().decode(RivalGhost.self, from: data),
                  ghost.ghost.s.count > 1 else { return completion(nil) }
            completion(ghost.rival)
        }.resume()
    }
}
