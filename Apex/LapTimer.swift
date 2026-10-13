import Foundation

/// Where the car was at one instant of a lap, for replaying it as a ghost.
struct GhostSample: Codable, Equatable {
    var s: Float
    var n: Float
    var psi: Float

    init(s: Float, n: Float, psi: Float) {
        self.s = s
        self.n = n
        self.psi = psi
    }

    init(_ car: Car) {
        self.init(s: Float(car.s), n: Float(car.n), psi: Float(car.psi))
    }
}

/// A finished lap: its time, its sector splits, and its ghost.
struct LapRecord: Codable, Equatable {
    var time: Double
    /// Lap time when sectors 1 and 2 ended.
    var splits: [Double]
    /// The car every 1/`RaceTuning.ghostSampleRate` seconds from the line.
    var ghost: [GhostSample]

    /// How long this lap took to reach `distance` along it, read from its ghost.
    func time(atDistance distance: Double, trackLength: Double) -> Double {
        let step = 1 / RaceTuning.ghostSampleRate
        guard let first = ghost.first, distance > Double(first.s) else { return 0 }
        // Ghost positions climb from the line to the end of the lap: find the last sample at or before `distance`.
        var low = 0, high = ghost.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Double(ghost[middle].s) <= distance { low = middle } else { high = middle - 1 }
        }
        let s0 = Double(ghost[low].s), t0 = Double(low) * step
        let (s1, t1) = low + 1 < ghost.count ? (Double(ghost[low + 1].s), t0 + step) : (trackLength, time)
        guard s1 > s0 else { return t0 }
        return t0 + (t1 - t0) * min(1, (distance - s0) / (s1 - s0))
    }

    /// Where this lap's car was `lapTime` seconds in, or nil once it had finished.
    func ghostPose(at lapTime: Double, trackLength: Double) -> GhostSample? {
        guard lapTime >= 0, lapTime < time else { return nil }
        let u = lapTime * RaceTuning.ghostSampleRate
        let i = Int(u)
        guard i + 1 < ghost.count else { return ghost.last }
        let f = Float(u - Double(i))
        let a = ghost[i], b = ghost[i + 1]
        let length = Float(trackLength)
        var nextS = b.s
        if nextS < a.s - length / 2 { nextS += length }
        var s = a.s + (nextS - a.s) * f
        if s >= length { s -= length }
        return GhostSample(s: s, n: a.n + (b.n - a.n) * f, psi: a.psi + (b.psi - a.psi) * f)
    }
}

/// Times laps and sectors from the car's unwrapped progress, interpolating each crossing within its physics step, and
/// records every lap's ghost.
struct LapTimer {
    struct Split: Equatable {
        /// 1 or 2.
        var sector: Int
        /// Lap time at the end of the sector.
        var time: Double
        /// Against the best lap's split: negative is faster.
        var delta: Double?
    }

    struct Lap: Equatable {
        var number: Int
        var time: Double
        /// Against the best lap before this one: negative is faster.
        var delta: Double?
        var isBest: Bool
    }

    enum Event: Equatable {
        case sector(Split)
        case lap(Lap)
    }

    let trackLength: Double
    let sectorEnds: [Double]
    private(set) var best: LapRecord?
    /// 0 on the out lap, then 1, 2, ...
    private(set) var lapNumber = 0
    /// Race clock when the current lap began; nil on the out lap.
    private(set) var lapStart: Double?
    private(set) var splits: [Double] = []
    private(set) var lastLap: Double?
    /// The last finished lap, best or not.
    private(set) var lastRecord: LapRecord?
    private var ghost: [GhostSample] = []

    init(track: Track, best: LapRecord? = nil) {
        trackLength = track.length
        sectorEnds = track.sectorEnds
        self.best = best
    }

    func lapTime(at clock: Double) -> Double? { lapStart.map { clock - $0 } }

    /// How far behind (positive) or ahead of the best lap this lap is, at the same distance along it.
    func liveDelta(at clock: Double, distance: Double) -> Double? {
        guard let best, let lapTime = lapTime(at: clock) else { return nil }
        return lapTime - best.time(atDistance: distance, trackLength: trackLength)
    }

    /// The car moved from progress `from` to `to` during the physics step that ended at `clock`.
    mutating func update(from p0: Double, to p1: Double, at clock: Double, step: Double, sample: GhostSample) -> [Event] {
        guard p1 > p0 else { return [] }
        var events: [Event] = []
        func crossing(_ mark: Double) -> Double { clock - step + step * (mark - p0) / (p1 - p0) }

        if let start = lapStart {
            for (index, end) in sectorEnds.enumerated() where splits.count == index {
                let mark = (((p1 - end) / trackLength).rounded(.down)) * trackLength + end
                guard mark > p0 else { break }
                let time = crossing(mark) - start
                splits.append(time)
                let delta = best.flatMap { $0.splits.count > index ? time - $0.splits[index] : nil }
                events.append(.sector(Split(sector: index + 1, time: time, delta: delta)))
            }
        }

        let line = (p1 / trackLength).rounded(.down) * trackLength
        if line > p0 {
            let at = crossing(line)
            if let start = lapStart {
                let time = at - start
                let record = LapRecord(time: time, splits: splits, ghost: ghost)
                let delta = best.map { time - $0.time }
                let isBest = best.map { time < $0.time } ?? true
                if isBest { best = record }
                lastLap = time
                lastRecord = record
                events.append(.lap(Lap(number: lapNumber, time: time, delta: delta, isBest: isBest)))
            }
            lapNumber += 1
            lapStart = at
            splits = []
            ghost = []
        }

        if let start = lapStart {
            let due = Int((clock - start) * RaceTuning.ghostSampleRate)
            while ghost.count <= due { ghost.append(sample) }
        }
        return events
    }

    /// Back to the out lap, keeping the best lap.
    mutating func abandonLap() {
        lapNumber = 0
        lapStart = nil
        splits = []
        ghost = []
    }

    mutating func forgetBest() {
        best = nil
    }

    /// Races against a different best lap, as when the car's tuning changes.
    mutating func replaceBest(with record: LapRecord?) {
        best = record
    }
}

/// Best laps, kept on the device per circuit and per version of the car's tuning.
enum LapStore {
    static func key(for track: Track) -> String {
        "apex.bestLap." + fingerprint(track.layout.signature + "|" + RaceTuning.lapSignature)
    }

    static func load(for track: Track, defaults: UserDefaults = .standard) -> LapRecord? {
        guard let data = defaults.data(forKey: key(for: track)) else { return nil }
        return try? PropertyListDecoder().decode(LapRecord.self, from: data)
    }

    static func save(_ record: LapRecord, for track: Track, defaults: UserDefaults = .standard) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: key(for: track))
    }

    static func clear(for track: Track, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: track))
    }

    /// FNV-1a, so the key is the same on every launch (Swift's `Hasher` is seeded per process).
    static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
