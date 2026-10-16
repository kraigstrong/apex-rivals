#if DEBUG
import Foundation
import UIKit

/// Xcode builds only: every run (from the grid to a restart) is recorded so a lap can be studied afterwards. Each run is
/// a folder in Documents/Telemetry holding `run.json` (every physics step's input, so the run replays step for step,
/// with its touches, splits, laps and wall hits) and a CSV of every drawn frame for each lap (`lap-00.csv` is the out
/// lap): the car, the camera and the frame's timing. Copy the folder off a connected phone with
///
///     xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///         --domain-identifier com.kraigstrong.apex --source Documents/Telemetry --destination <folder>
///
/// or share it from the ⚙︎ menu.
enum Telemetry {
    static var folder: URL { URL.documentsDirectory.appending(path: "Telemetry") }
    /// Older runs are deleted as new ones start.
    static let runsKept = 60
    /// Files are written here, in order, off the main thread.
    static let queue = DispatchQueue(label: "apex.telemetry", qos: .utility)

    /// Every run so far, zipped, once the writes queued before it have finished.
    static func archive(completion: @escaping (URL?) -> Void) {
        queue.async {
            var zipped: URL?
            var error: NSError?
            // Reading a folder "for uploading" hands back a zip of it.
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &error) { zip in
                let stamp = TelemetryRun.stamp.string(from: Date())
                let copy = FileManager.default.temporaryDirectory.appending(path: "apex-telemetry-\(stamp).zip")
                try? FileManager.default.removeItem(at: copy)
                if (try? FileManager.default.copyItem(at: zip, to: copy)) != nil { zipped = copy }
            }
            DispatchQueue.main.async { completion(zipped) }
        }
    }

    /// Opens the share sheet with every run so far (AirDrop it to the Mac).
    static func share() {
        archive { zip in
            guard let zip, let top = UIViewController.top else { return }
            let sheet = UIActivityViewController(activityItems: [zip], applicationActivities: nil)
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: 40, width: 1, height: 1)
            }
            top.present(sheet, animated: true)
        }
    }
}

/// One run as `run.json` keeps it.
struct TelemetryRun: Codable {
    struct Touch: Codable, Equatable {
        /// Seconds from the run's start, on the same clock as `TelemetryRecorder.Row.time`.
        var time: Double
        var down: Bool
    }

    struct Event: Codable, Equatable {
        enum Kind: String, Codable { case sector, lap, wall }
        var kind: Kind
        /// Race clock at the end of the frame it came in.
        var clock: Double
        /// The lap it belongs to (0 is the out lap).
        var lap: Int
        var sector: Int?
        /// The sector's or lap's time, and against the best lap.
        var time: Double?
        var delta: Double?
        var isBest: Bool?
        /// A wall: +1 the left (top of the screen), −1 the right, and how hard.
        var side: Double?
        var severity: Double?
    }

    var track: String
    var trackSignature: String
    var lapSignature: String
    var isStock: Bool
    /// "player", or the autopilot's mode.
    var driver: String
    var started: Date
    var device: String
    var system: String
    var build: String
    var maximumFramesPerSecond: Int
    var physicsStep: Double
    /// Only how the race is drawn, so it isn't in `lapSignature`, but the tuning panel can change it.
    var cameraHeadingAhead: Double
    /// The best lap when the run began.
    var bestBefore: Double?
    /// Physics steps run.
    var steps = 0
    /// Steps run holding, as [first, end) pairs: step i (counting from 0) held if some pair has first ≤ i < end.
    var held: [[Int]] = []
    var touches: [Touch] = []
    var events: [Event] = []

    /// Whether physics step `step` ran holding.
    func holding(atStep step: Int) -> Bool {
        var low = 0, high = held.count
        while low < high {
            let middle = (low + high) / 2
            if held[middle][1] <= step { low = middle + 1 } else { high = middle }
        }
        return low < held.count && held[low][0] <= step
    }

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // To the millisecond, so a run started just after a restart doesn't share the last one's folder.
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}

/// Records one run as it's driven. The scene hands it every physics step's input, every event and every frame.
final class TelemetryRecorder {
    /// One drawn frame, a line of its lap's CSV.
    struct Row {
        /// Seconds from the run's start: the frame's timestamp, on the touches' clock.
        var time: Double
        /// The time the frame advanced the race (capped after a hitch).
        var dt: Double
        var clock: Double
        var step: Int
        var lap: Int
        var lapTime: Double?
        var delta: Double?
        var holding: Bool
        var s: Double
        var n: Double
        var psi: Double
        var speed: Double
        var lineSpeed: Double
        var pathCurvature: Double
        var scrub: Double
        /// The nose's world heading (unwrapped), and the camera's angle: their difference is the nose on screen.
        var heading: Double
        var camera: Double
        var viewWidth: Double

        static let header = "t,dt,clock,step,lap,lapTime,delta,hold,s,n,psi,speed,lineSpeed,kappa,scrub,heading,camera,"
            + "viewWidth"

        var line: String {
            let optional = { (value: Double?) in value.map { String(format: "%.4f", $0) } ?? "" }
            return String(format: "%.5f,%.5f,%.5f,%ld,%ld,", time, dt, clock, step, lap)
                + optional(lapTime) + "," + optional(delta) + ","
                + String(format: "%ld,%.2f,%.2f,%.4f,%.2f,%.2f,%.6f,%.3f,%.4f,%.4f,%.1f", holding ? 1 : 0, s, n, psi,
                         speed, lineSpeed, pathCurvature, scrub, heading, camera, viewWidth)
        }
    }

    let folder: URL
    private let track: Track
    /// The run's start, on the frames' and touches' clock.
    private let origin: TimeInterval
    private var run: TelemetryRun
    private var holding = false
    /// The frames of the lap under way.
    private var rows: [Row] = []
    private var rowsLap = 0

    /// Starts a run in its own folder of `parent`, deleting the oldest runs there beyond `Telemetry.runsKept`.
    init(track: Track, driver: String, bestBefore: Double?, origin: TimeInterval, maximumFramesPerSecond: Int,
         started: Date = Date(), parent: URL = Telemetry.folder) {
        self.track = track
        self.origin = origin
        folder = parent.appending(path: TelemetryRun.stamp.string(from: started) + "-" + track.layout.id)
        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: machine.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let info = Bundle.main.infoDictionary
        run = TelemetryRun(
            track: track.layout.id, trackSignature: LapStore.fingerprint(track.layout.signature),
            lapSignature: RaceTuning.lapSignature, isStock: RaceTuning.isStock, driver: driver, started: started,
            device: model, system: ProcessInfo.processInfo.operatingSystemVersionString,
            build: "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))",
            maximumFramesPerSecond: maximumFramesPerSecond, physicsStep: RaceTuning.physicsStep,
            cameraHeadingAhead: RaceTuning.cameraHeadingAhead, bestBefore: bestBefore)
        let folder = folder
        Telemetry.queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let runs = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            // Folder names start with when the run began, so they sort oldest first.
            for old in runs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(Telemetry.runsKept) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    /// One physics step, run holding or not. Returns `holding`, so it can wrap the step's control.
    @discardableResult
    func step(holding: Bool) -> Bool {
        if holding, !self.holding {
            run.held.append([run.steps, run.steps + 1])
        } else if holding {
            run.held[run.held.count - 1][1] = run.steps + 1
        }
        self.holding = holding
        run.steps += 1
        return holding
    }

    func touch(down: Bool, at time: TimeInterval) {
        run.touches.append(TelemetryRun.Touch(time: time - origin, down: down))
    }

    /// An event from the frame that just ran. A finished lap writes the run so far.
    func record(_ event: RaceSession.Event, lap: Int, clock: Double) {
        switch event {
        case .wallHit(let hit):
            run.events.append(.init(kind: .wall, clock: clock, lap: lap, side: hit.side, severity: hit.severity))
        case .timing(.sector(let split)):
            run.events.append(.init(kind: .sector, clock: clock, lap: lap, sector: split.sector, time: split.time,
                                    delta: split.delta))
        case .timing(.lap(let finished)):
            run.events.append(.init(kind: .lap, clock: clock, lap: finished.number, time: finished.time,
                                    delta: finished.delta, isBest: finished.isBest))
            writeRun()
        }
    }

    /// A drawn frame, after the race advanced and the camera moved. A frame on a new lap writes the last one's CSV.
    func frame(_ session: RaceSession, time: TimeInterval, dt: Double, camera: Double, viewWidth: Double) {
        let car = session.car
        let lap = session.timer.lapNumber
        if lap != rowsLap { writeLap() }
        rowsLap = lap
        rows.append(Row(time: time - origin, dt: dt, clock: session.clock, step: run.steps, lap: lap,
                        lapTime: session.timer.lapTime(at: session.clock),
                        delta: session.timer.liveDelta(at: session.clock, distance: car.s), holding: holding,
                        s: car.s, n: car.n, psi: car.psi, speed: car.speed, lineSpeed: car.lineSpeed,
                        pathCurvature: car.pathCurvature, scrub: car.scrub, heading: car.heading(on: track),
                        camera: camera, viewWidth: viewWidth))
    }

    /// Writes the lap under way and the run as it stands. The run is over; nothing more is recorded.
    func finish() {
        writeLap()
        writeRun()
    }

    private func writeLap() {
        guard !rows.isEmpty else { return }
        let rows = rows, file = folder.appending(path: String(format: "lap-%02d.csv", rowsLap))
        self.rows = []
        Telemetry.queue.async {
            let text = ([Row.header] + rows.map(\.line)).joined(separator: "\n") + "\n"
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func writeRun() {
        let run = run, file = folder.appending(path: "run.json")
        Telemetry.queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try? encoder.encode(run).write(to: file, options: .atomic)
        }
    }
}
#endif
