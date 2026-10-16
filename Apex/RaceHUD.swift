import CoreGraphics
import Foundation
import Observation

/// What the SwiftUI overlay shows. The scene fills it in a few times a second, and at once for splits and laps.
@Observable
final class RaceHUD {
    struct Banner: Equatable {
        enum Tone { case faster, slower, neutral, best }
        var title: String
        var value: String
        var detail: String?
        var tone: Tone
        /// A medal this lap just won.
        var medal: Medal?
        var id: Int
    }

    var racing = false
    /// A lap has been finished this session, so the flag has a summary to end on. Until then it's dimmed.
    var canEndSession = false
    /// 0 on the out lap.
    var lapNumber = 0
    /// Nil on the out lap.
    var lapTime: Double?
    var bestLap: Double?
    /// The medal the best lap has won, and the next one to chase.
    var bestMedal: Medal? { Medal.earned(by: bestLap, on: layout) }
    var nextMedal: (medal: Medal, target: Double)? { Medal.next(after: bestLap, on: layout) }
    var lastLap: Double?
    /// Against the best lap at this point of the lap: negative is ahead. Nil on the out lap or with no best lap.
    var liveDelta: Double?
    var speed: Double = 0
    /// The fastest the current line allows.
    var lineSpeed: Double = RaceTuning.topSpeed
    /// 0...1: how much speed the line is costing right now.
    var scrub: Double = 0
    var banner: Banner?
    /// The car and the best lap's ghost, as fractions of the minimap.
    var carMarker = CGPoint(x: 0.5, y: 0.5)
    var ghostMarker: CGPoint?
    /// Who you're chasing (the gold ghost), and their lap.
    var rivalName: String?
    var rivalTime: Double?
    var rivalMarker: CGPoint?
    var showsRacingLine = false
    /// Apex School's coach: where you are in the corner, and what to do with your thumb.
    var coach: Coach?
    var isPractice = false
    /// Apex School: apexes hit toward the goal, and the "you're ready" card once it's reached.
    var schoolHits = 0
    var showsGraduation = false
    /// The car colors picker is open over the race.
    var showsColors = false
    /// Race a friend is open over the race, with what it lists, and the friend being raced (their token; nil is Auto).
    var showsFriends = false
    var friends: FriendList = .loading
    var racingFriend: String?
    #if DEBUG
    /// The tuning panel is open over the race, with the bots' laps on the car as tuned and as released (once known).
    var showsTuner = false
    var botLaps: BotLaps?
    var stockBotLaps: BotLaps?
    @ObservationIgnored var onTune: () -> Void = {}
    @ObservationIgnored var onShareTelemetry: () -> Void = {}
    #endif
    /// A panel is open over the race: it dims the race and hides the timing until it closes.
    var showsPanel: Bool {
        #if DEBUG
        return showsColors || showsFriends || showsTuner || showsGraduation
        #else
        return showsColors || showsFriends || showsGraduation
        #endif
    }
    /// The ⚙︎ menu is open. Unlike a panel it leaves the race in view, and its button where it was.
    var showsMenu = false
    /// The app is in front: not under Control Center, a call or Siri. A race opens from the track list, so in front.
    var isAppActive = true
    /// Game Center's leaderboard is over the race. Asked each frame, since Game Center closes it on its own.
    @ObservationIgnored var showsLeaderboard: () -> Bool = { GameCenter.shared.isShowingLeaderboard }
    /// The race holds still while anything is over it: a panel, the ⚙︎ menu, Game Center's leaderboard, or whatever
    /// took the app out of the front. The lap picks up where it was once it's gone.
    var holdsRace: Bool {
        showsPanel || showsMenu || !isAppActive || showsLeaderboard()
    }
    /// The card shown when a session ends, and where its best lap falls among other players.
    var summary: SessionSummary?
    var standing: StandingState = .loading

    /// The circuit's shape for the minimap, as fractions of its box (y down).
    let mapOutline: [CGPoint]
    /// The circuit's width over its height.
    let mapAspect: CGFloat
    let trackName: String
    let layout: TrackLayout

    @ObservationIgnored var onRestart: () -> Void = {}
    @ObservationIgnored var onToggleRacingLine: () -> Void = {}
    @ObservationIgnored var onForgetBest: () -> Void = {}
    @ObservationIgnored var onShowLeaderboard: () -> Void = {}
    @ObservationIgnored var onEndSession: () -> Void = {}
    @ObservationIgnored var onRaceAgain: () -> Void = {}
    /// The summary's share button.
    @ObservationIgnored var onShare: () -> Void = {}
    /// Race a friend: open it (which loads the list), and pick a friend or Auto (nil).
    @ObservationIgnored var onShowFriends: () -> Void = {}
    @ObservationIgnored var onPickFriend: (FriendTime?) -> Void = { _ in }
    /// The house button: ends the session (showing its summary if a lap was finished), or goes straight to the tracks.
    @ObservationIgnored var onLeave: () -> Void = {}
    /// Back to the track list.
    @ObservationIgnored var onExit: () -> Void = {}
    @ObservationIgnored private let bounds: CGRect
    @ObservationIgnored private var nextBannerID = 0

    init(track: Track) {
        let box = track.bounds
        bounds = box
        mapAspect = box.width / max(box.height, 1)
        trackName = track.layout.name
        layout = track.layout
        mapOutline = stride(from: 0, to: track.count, by: 30).map { i in
            CGPoint(x: (track.x[i] - box.minX) / box.width, y: 1 - (track.y[i] - box.minY) / box.height)
        }
    }

    /// A world point as a fraction of the minimap.
    func mapPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - bounds.minX) / bounds.width, y: 1 - (point.y - bounds.minY) / bounds.height)
    }

    func show(_ title: String, _ value: String, detail: String? = nil, tone: Banner.Tone, medal: Medal? = nil) {
        nextBannerID += 1
        banner = Banner(title: title, value: value, detail: detail, tone: tone, medal: medal, id: nextBannerID)
    }
}

extension RaceHUD {
    struct Coach: Equatable {
        var title: String
        var detail: String
        var phase: ApexGuide.Phase
    }
}

/// One sitting at the track: from the first touch until you end it (the flag) or leave the app.
struct SessionSummary: Equatable {
    var trackName: String
    var laps: Int
    /// The session's fastest lap.
    var best: Double
    /// The all-time best as it stands after the session.
    var personalBest: Double?
    /// The session set a new personal best.
    var isPersonalBest: Bool
    /// The medal the session's best lap won, and whether this session won it for the first time.
    var medal: Medal?
    var isNewMedal = false
    /// The next medal to chase after the personal best, and the lap that earns it.
    var nextMedal: Medal?
    var nextMedalTarget: Double?
    /// The session's fastest lap itself, with its line, for sharing.
    var lap: LapRecord?
}

enum StandingState: Equatable {
    case loading
    /// The lap service didn't answer (or is off).
    case unavailable
    /// `sample` is made-up players, shown in Xcode builds while the service is off.
    case ready(Standing, sample: Bool)
}

enum LapFormat {
    /// "29.871", or "1:02.345" past a minute.
    static func time(_ seconds: Double, decimals: Int = 3) -> String {
        // A lap that never finished (a bot's lap of infinity) has no time to show.
        guard seconds.isFinite else { return "—" }
        let total = max(0, seconds)
        let minutes = Int(total) / 60
        let rest = total - Double(minutes * 60)
        if minutes == 0 { return String(format: "%.\(decimals)f", rest) }
        return "\(minutes):" + String(format: "%0\(decimals + 3).\(decimals)f", rest)
    }

    /// "−0.214" or "+0.571".
    static func delta(_ seconds: Double, decimals: Int = 3) -> String {
        guard seconds.isFinite else { return "—" }
        return (seconds < 0 ? "\u{2212}" : "+") + String(format: "%.\(decimals)f", abs(seconds))
    }

    static func speed(_ unitsPerSecond: Double) -> String {
        "\(Int((unitsPerSecond * RaceTuning.displaySpeedFactor).rounded()))"
    }
}
