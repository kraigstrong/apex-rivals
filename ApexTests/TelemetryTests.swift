import Foundation
import Testing
@testable import Apex

/// Telemetry has to be faithful to be worth studying: a recorded run replays to the same laps, step for step.
struct TelemetryTests {
    static let ardennes = Track(TrackLayout.all.first { $0.id == "ardennes" }!)

    /// A human-speed bot drives two laps on uneven frames, as the scene would, into a run in a fresh folder.
    func record() -> (run: TelemetryRun, folder: URL, laps: [Double]) {
        let track = Self.ardennes
        let line = RacingLine(track: track)
        var driver = AutoDriver(line: { line.offset(at: $0) }, decisionInterval: 0.09, hesitation: 0.04, seed: 3)
        let parent = FileManager.default.temporaryDirectory.appending(path: "telemetry-\(UUID().uuidString)")
        let recorder = TelemetryRecorder(track: track, driver: "test", bestBefore: nil, origin: 100,
                                         maximumFramesPerSecond: 120, parent: parent)
        let session = RaceSession(track: track)
        session.start()
        var random = SplitMix64(seed: 9)
        var time = 100.0
        var laps: [Double] = []
        while laps.count < 2, session.clock < 100 {
            let dt = 1.0 / 120 + (random.unit() - 0.5) * 0.004
            time += dt
            let events = session.advance(by: dt) { recorder.step(holding: driver.decide($0)) }
            events.forEach { recorder.record($0, lap: session.timer.lapNumber, clock: session.clock) }
            recorder.frame(session, time: time, dt: dt, camera: 0, viewWidth: RaceTuning.viewWidthSlow)
            for case .timing(.lap(let lap)) in events { laps.append(lap.time) }
        }
        recorder.finish()
        Telemetry.queue.sync {}
        let data = try! Data(contentsOf: recorder.folder.appending(path: "run.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try! decoder.decode(TelemetryRun.self, from: data), recorder.folder, laps)
    }

    @Test func aRunReplaysStepForStep() {
        let (run, _, laps) = record()
        #expect(laps.count == 2)
        #expect(run.events.filter { $0.kind == .lap }.compactMap(\.time) == laps)

        let replay = RaceSession(track: Self.ardennes)
        replay.start()
        var step = 0
        var replayed: [Double] = []
        while step < run.steps {
            let events = replay.advance(by: RaceTuning.physicsStep) { _ in
                defer { step += 1 }
                return run.holding(atStep: step)
            }
            for case .timing(.lap(let lap)) in events { replayed.append(lap.time) }
        }
        #expect(replayed == laps)
    }

    @Test func holdsAreKeptAsStretchesOfSteps() {
        let recorder = TelemetryRecorder(track: Self.ardennes, driver: "test", bestBefore: nil, origin: 0,
                                         maximumFramesPerSecond: 120,
                                         parent: FileManager.default.temporaryDirectory.appending(path: "unused"))
        let pattern = [false, true, true, false, false, true, false, true]
        pattern.forEach { recorder.step(holding: $0) }
        recorder.finish()
        Telemetry.queue.sync {}
        let data = try! Data(contentsOf: recorder.folder.appending(path: "run.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try! decoder.decode(TelemetryRun.self, from: data)
        #expect(run.held == [[1, 3], [5, 6], [7, 8]])
        #expect((0..<10).map { run.holding(atStep: $0) } == pattern + [false, false])
    }

    /// Each lap's frames go in their own CSV, every row on that lap, and together they cover the run.
    @Test func everyLapHasItsFrames() throws {
        let (run, folder, _) = record()
        var frames = 0
        for lap in 0...2 {
            let text = try String(contentsOf: folder.appending(path: String(format: "lap-%02d.csv", lap)), encoding: .utf8)
            let lines = text.split(separator: "\n")
            #expect(lines.first.map(String.init) == TelemetryRecorder.Row.header)
            let columns = TelemetryRecorder.Row.header.split(separator: ",").count
            for row in lines.dropFirst() {
                let fields = row.split(separator: ",", omittingEmptySubsequences: false)
                #expect(fields.count == columns)
                #expect(Int(fields[4]) == lap)
            }
            frames += lines.count - 1
        }
        // About 120 frames a second of racing.
        let seconds = Double(run.steps) * RaceTuning.physicsStep
        #expect(abs(Double(frames) / seconds - 120) < 2)
    }
}

/// Studies runs copied off a phone (README, Telemetry): replays each one, printing its laps as logged and as replayed
/// (`REPLAY` lines), and writes what to compare them with into the folder's `reference/<circuit>/`: the circuit sampled
/// every unit with the ideal line (`track.csv`), where each of its pieces runs (`segments.csv`), and bots' laps as runs
/// of their own, with the camera turned as the race turns it. Only runs when asked:
///
///     TEST_RUNNER_APEX_TELEMETRY=<folder> xcodebuild test ... -only-testing:ApexTests/TelemetryStudy
struct TelemetryStudy {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APEX_TELEMETRY"] != nil))
    func study() throws {
        let folder = URL(filePath: ProcessInfo.processInfo.environment["APEX_TELEMETRY"]!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var circuits = Set<String>()
        for runFolder in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: runFolder.appending(path: "run.json")) else { continue }
            let run = try decoder.decode(TelemetryRun.self, from: data)
            let layout = try #require(TrackLayout.named(run.track))
            circuits.insert(run.track)
            let session = RaceSession(track: Track(layout))
            session.start()
            var step = 0
            var replayed: [Double] = []
            while step < run.steps {
                let events = session.advance(by: RaceTuning.physicsStep) { _ in
                    defer { step += 1 }
                    return run.holding(atStep: step)
                }
                for case .timing(.lap(let lap)) in events { replayed.append(lap.time) }
            }
            let logged = run.events.filter { $0.kind == .lap }.compactMap(\.time)
            print("REPLAY \(runFolder.lastPathComponent) logged \(logged) replayed \(replayed)")
        }

        for id in circuits {
            let track = Track(try #require(TrackLayout.named(id)))
            let line = RacingLine(track: track)
            let reference = folder.appending(path: "reference/\(id)")
            try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: true)
            let samples = (0..<track.count).map { i in
                let s = Double(i) * track.spacing
                return [s, track.x[i], track.y[i], track.heading[i], track.cameraHeading[i], track.curvature[i],
                        line.offset(at: s)].map { String(format: "%.6f", $0) }.joined(separator: ",")
            }
            try (["s,x,y,heading,cameraHeading,curvature,ideal"] + samples).joined(separator: "\n")
                .write(to: reference.appending(path: "track.csv"), atomically: true, encoding: .utf8)

            // Pieces are laid end to end from the layout's start, in whole samples; the lap starts `startLine` in.
            var start = 0
            var pieces = ["index,kind,radius,degrees,start,end"]
            let lineSample = Int((track.layout.startLine / track.spacing).rounded())
            for (index, segment) in track.segments.enumerated() {
                let (kind, radius, degrees, count): (String, Double, Double, Int)
                switch segment {
                case .straight(let length):
                    (kind, radius, degrees) = ("straight", 0, 0)
                    count = max(1, Int((length / track.spacing).rounded()))
                case .corner(let r, let d):
                    (kind, radius, degrees) = ("corner", r, d)
                    count = max(1, Int((abs(d * .pi / 180) * r / track.spacing).rounded()))
                }
                let s = Double((start - lineSample + track.count) % track.count) * track.spacing
                pieces.append("\(index),\(kind),\(radius),\(degrees),\(s),\(s + Double(count) * track.spacing)")
                start += count
            }
            try pieces.joined(separator: "\n").write(to: reference.appending(path: "segments.csv"), atomically: true,
                                                    encoding: .utf8)

            let bots: [(String, AutoDriver)] = [
                ("perfect", AutoDriver(line: { line.offset(at: $0) })),
                ("platinum-50ms", AutoDriver(line: { line.offset(at: $0) }, decisionInterval: 0.05)),
                ("gold-90ms", AutoDriver(line: { line.offset(at: $0) }, decisionInterval: 0.09, hesitation: 0.04)),
            ]
            for (name, bot) in bots {
                var driver = bot
                let recorder = TelemetryRecorder(track: track, driver: name, bestBefore: nil, origin: 0,
                                                 maximumFramesPerSecond: 120, parent: reference.appending(path: name))
                let session = RaceSession(track: track)
                session.start()
                // As `RaceScene.placeCamera` turns it.
                var camera = track.cameraHeading(at: session.car.s + RaceTuning.cameraHeadingAhead)
                var time = 0.0, laps = 0
                while laps < 3, session.clock < 120 {
                    let dt = 1.0 / 120
                    time += dt
                    let events = session.advance(by: dt) { recorder.step(holding: driver.decide($0)) }
                    events.forEach { recorder.record($0, lap: session.timer.lapNumber, clock: session.clock) }
                    let target = track.cameraHeading(at: session.car.s + RaceTuning.cameraHeadingAhead)
                    camera += (target - camera).remainder(dividingBy: 2 * .pi) * (1 - exp(-dt / RaceTuning.cameraTurnLag))
                    recorder.frame(session, time: time, dt: dt, camera: camera, viewWidth: RaceTuning.viewWidthSlow)
                    for case .timing(.lap) in events { laps += 1 }
                }
                recorder.finish()
            }
        }
        Telemetry.queue.sync {}
    }
}
