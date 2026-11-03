#if DEBUG
import Foundation
import UIKit

/// App Store screenshots, from Xcode builds only; `scripts/store-capture.sh` drives it, on a fresh install for each
/// moment. Launched with `-ApexStoreCapture <moment>`, the app stages what the moment shows (best laps and their
/// medals, a bot rival, the race driven by the autopilot), plays up to the moment, holds still there, and writes
/// Documents/StoreCapture/<moment>.ready; the script then takes the simulator's screenshot, with the Dynamic Island left
/// out. The lap service and Game Center stay out of it, so no real player's name or time can appear. Runs repeat
/// exactly: the bots and the autopilot are seeded.
enum StoreCapture {
    /// The screenshots, in the listing's order, and the app preview's moments.
    enum Moment: String, CaseIterable {
        /// The ideal line drawn on the track, the car on it: what the game is about.
        case line
        /// Racing through a corner with your blue ghost and the gold rival around you.
        case ghosts
        /// A lap that wins a gold medal, its banner up.
        case medal
        /// A session's summary: the best lap, its medal, and where it stands among other players.
        case standing
        /// The track list, every circuit open, with best laps and medals on them.
        case circuits
        /// The unlock's screen, each circuit threading its line.
        case unlock
        /// The app preview's alone (no screenshot): a lap on Snake crossing the line, a new best, its banner up.
        case best

        /// The circuit its race is on; nil for the track list's moments.
        var track: String? {
            switch self {
            case .ghosts: "swirl"
            case .line: "harbor"
            case .medal, .standing: "ardennes"
            case .best: "snake"
            case .circuits, .unlock: nil
            }
        }

        /// How far round the first timed lap the race holds still (a share of the lap), for the moments in a corner.
        /// `-ApexStoreCaptureAt 0.4` tries another.
        var at: Double? {
            switch self {
            case .ghosts: 0.44
            case .line: 0.6
            default: nil
            }
        }

        /// The saved best lap's bot: how quickly it reacts, so the moment's lap beats it by about the right amount.
        var bestReaction: Double {
            switch self {
            case .medal: 0.2
            default: 0.11
            }
        }
    }

    static let moment: Moment? = UserDefaults.standard.string(forKey: "ApexStoreCapture").flatMap(Moment.init)
    static var isActive: Bool { moment != nil }
    /// With `-ApexStoreCaptureVideo YES` too, a clip for the app preview (`scripts/store-capture.sh --video`): the
    /// moment plays on through, with its sound, rather than holding still, and `<moment>.mark` says when it came.
    static let isVideo = moment != nil && UserDefaults.standard.bool(forKey: "ApexStoreCaptureVideo")
    /// With `-ApexStoreCaptureScale 3.8111` too, for the App Store's header and search results images
    /// (`scripts/store-creative.py`): the moment drawn that many times its size in points, with no HUD over it (on a
    /// 13-inch iPad, 3.8111 makes it 5244 pixels wide).
    static let drawingScale: CGFloat? = moment != nil && UserDefaults.standard.object(forKey: "ApexStoreCaptureScale") != nil
        ? CGFloat(UserDefaults.standard.double(forKey: "ApexStoreCaptureScale")) : nil
    static var hidesHUD: Bool { drawingScale != nil }

    /// Where the race holds still this launch: the moment's, or `-ApexStoreCaptureAt`'s.
    static var at: Double? {
        UserDefaults.standard.object(forKey: "ApexStoreCaptureAt") != nil
            ? UserDefaults.standard.double(forKey: "ApexStoreCaptureAt") : moment?.at
    }

    /// The autopilot that drives the moment's race: the ideal line at a quick human's reactions, the same lap each run.
    static func autopilot(line: RacingLine) -> AutoDriver {
        AutoDriver(line: { line.offset(at: $0) }, decisionInterval: 0.065, hesitation: 0.03, seed: 11)
    }

    /// The best laps the track list shows, as a player some way in would have them: a medal of each kind, and one
    /// circuit still to race. Times only; a race moment's own circuit gets a real lap with its ghost.
    static let listBests: [(track: String, medal: Medal?)] = [
        ("ardennes", .platinum), ("swirl", .gold), ("snake", .gold), ("mirage", .silver), ("island", .bronze),
        ("harbor", nil),
    ]

    /// Stages the moment, before anything is on screen: Apex School done, the sound off (on for a video, which records
    /// it), best laps on every circuit,
    /// and on the race's circuit a bot's lap with its ghost to race. They're set with no one signed in: a capture has
    /// no Game Center.
    static func stage() {
        guard let moment else { return }
        SchoolProgress.markDone()
        RaceAudio.shared.soundOn = isVideo
        RaceAudio.shared.musicOn = isVideo
        for (id, medal) in listBests {
            guard let medal, let layout = TrackLayout.named(id), let times = RaceTuning.medalTimes[id] else { continue }
            let time = times[medal.rawValue] - 0.13
            LapStore.save(LapRecord(time: time, splits: [], ghost: []), for: TrackCatalog.track(layout.id), player: nil)
        }
        if let id = moment.track {
            let track = TrackCatalog.track(id)
            let best = RivalBot.drive(reaction: moment.bestReaction, track: track, line: RacingLine(track: track), seed: 3)
            LapStore.save(best, for: track, player: nil)
        }
    }

    /// The moment is on screen: tells the script to take it, after `delay` for what's on screen to settle. On an iPad
    /// the app saves the screen itself first, as `<moment>.png`: a simulator can't be turned sideways from the command
    /// line, and held upright it shows a landscape-only game shrunk into a band, while the app still lays it out and
    /// draws it at the landscape screen's full size.
    static func ready(after delay: Double = 0.6) {
        guard let moment else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if isVideo { return mark() }
            MainActor.assumeIsolated {
                if let scale = drawingScale ?? (UIDevice.current.userInterfaceIdiom == .pad ? 2 : nil) {
                    guard let png = drawScreen(scale: scale) else { return fail("couldn't draw the screen") }
                    write(data: png, to: "\(moment.rawValue).png")
                }
                write("\(moment.rawValue).ready", "")
            }
        }
    }

    /// The window as it's laid out, everything in it drawn at `scale` times its size in points (2: an iPad's screen
    /// pixels).
    @MainActor private static func drawScreen(scale: CGFloat) -> Data? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }.pngData()
    }

    /// A video's moment has come: the wall-clock time it came, as `<moment>.mark`, for the script to cut the clip around.
    static func mark() {
        guard let moment else { return }
        write("\(moment.rawValue).mark", String(Date().timeIntervalSince1970))
    }

    /// A video records the race's sound as it plays, into `<moment>.caf`, with the wall-clock time of its first sample
    /// as `<moment>.sound`: the simulator's recording has none.
    static func recordSound() {
        guard isVideo, let moment else { return }
        let folder = URL.documentsDirectory.appending(path: "StoreCapture")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        RaceAudio.shared.record(to: folder.appending(path: "\(moment.rawValue).caf")) { start in
            write("\(moment.rawValue).sound", String(start))
        }
    }

    /// The moment couldn't be staged: tells the script why.
    static func fail(_ reason: String) {
        guard let moment else { return }
        write("\(moment.rawValue).failed", reason)
    }

    private static func write(_ name: String, _ text: String) {
        write(data: Data(text.utf8), to: name)
    }

    private static func write(data: Data, to name: String) {
        let folder = URL.documentsDirectory.appending(path: "StoreCapture")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: name), options: .atomic)
    }
}
#endif
