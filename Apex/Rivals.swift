import Foundation

/// Someone to chase: a lap a little faster than your best, raced as a gold ghost.
struct Rival: Equatable {
    enum Source: Equatable {
        /// Another player's best lap.
        case player
        /// A bot driving the ideal line, slowed to the right pace.
        case bot
    }

    var name: String
    var record: LapRecord
    var source: Source

    var time: Double { record.time }
}

/// Bot rivals: the ideal line, driven with the player's one control at whatever reaction speed laps closest to a target
/// time. Slower targets mean slower reactions, so the bot weaves more, exactly as a person would.
enum RivalBot {
    static let name = "Pace bot"

    /// A bot lap as close to `target` seconds as the bot can manage. It can't beat the ideal line driven perfectly.
    static func lap(near target: Double, track: Track, line: RacingLine, seed: UInt64 = 7) -> LapRecord {
        var quick = 0.0, slow = 0.3
        var closest = drive(reaction: quick, track: track, line: line, seed: seed)
        guard closest.time < target else { return closest }
        for _ in 0..<14 {
            let reaction = (quick + slow) / 2
            let record = drive(reaction: reaction, track: track, line: line, seed: seed)
            if abs(record.time - target) < abs(closest.time - target) { closest = record }
            if abs(record.time - target) < 0.04 { break }
            if record.time < target { quick = reaction } else { slow = reaction }
        }
        return closest
    }

    /// One flying lap by a bot deciding every `reaction` seconds (give or take 40%).
    static func drive(reaction: Double, track: Track, line: RacingLine, seed: UInt64) -> LapRecord {
        let session = RaceSession(track: track)
        var driver = AutoDriver(line: { line.offset(at: $0) }, decisionInterval: reaction * 0.8,
                                hesitation: reaction * 0.4, seed: seed)
        session.start()
        while session.timer.lastRecord == nil, session.clock < 180 {
            session.advance(by: RaceTuning.physicsStep) { driver.decide($0) }
        }
        return session.timer.lastRecord ?? LapRecord(time: .infinity, splits: [], ghost: [])
    }
}

/// Finds the next rival: another player's ghost that beats your best by a little (when the lap service is on), or else
/// a bot driven to beat it by `RaceTuning.rivalGap`. Work happens off the main thread; answers come back on it.
final class RivalScout {
    private let track: Track
    private let board: RaceBoard
    /// Apex School's rival is always the Instructor: the ideal line, driven perfectly.
    private let instructor: Bool
    private let queue = DispatchQueue(label: "apex.rivals", qos: .userInitiated)
    /// Built on `queue` the first time a bot is needed.
    private var line: RacingLine?
    /// Only the latest request's answer is delivered.
    private var request = 0

    init(track: Track, instructor: Bool = false) {
        self.track = track
        self.instructor = instructor
        board = RaceBoard(track: track)
    }

    func find(beating best: Double?, completion: @escaping (Rival?) -> Void) {
        request += 1
        let id = request
        let deliver: (Rival?) -> Void = { [weak self] rival in
            DispatchQueue.main.async {
                guard let self, id == self.request else { return }
                completion(rival)
            }
        }
        guard let best, ApexOnline.isEnabled, !instructor else {
            findBot(beating: best, deliver: deliver)
            return
        }
        ApexService.rival(on: board, beating: best) { [weak self] player in
            if let player {
                deliver(player)
            } else {
                self?.findBot(beating: best, deliver: deliver)
            }
        }
    }

    private func findBot(beating best: Double?, deliver: @escaping (Rival?) -> Void) {
        let target = instructor ? 0 : best.map { $0 - RaceTuning.rivalGap } ?? RaceTuning.firstRivalTime
        let name = instructor ? "Instructor" : RivalBot.name
        let track = self.track
        queue.async { [weak self] in
            guard let self else { return }
            if line == nil { line = RacingLine(track: track) }
            guard let line else { return }
            let record = RivalBot.lap(near: target, track: track, line: line)
            // Nothing to chase once you're faster than the bot can go.
            if let best, record.time >= best {
                deliver(nil)
            } else {
                deliver(Rival(name: name, record: record, source: .bot))
            }
        }
    }
}
