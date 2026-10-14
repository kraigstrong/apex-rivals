import SpriteKit
import SwiftUI

/// The track list, or a race on the track picked from it.
struct ContentView: View {
    /// The track being raced; nil shows the track list.
    @State private var racing: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let id = racing {
                RaceView(track: TrackCatalog.track(id), onExit: { racing = nil })
                    .id(id)
            } else {
                TrackMenu(onSelect: { racing = $0 })
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { GameCenter.shared.signIn() }
        // Laps that couldn't go up before (offline, or the service was down) try again at launch and on every return
        // to the app, not only after the next lap.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { LapLog.shared.flush() }
        }
    }
}

/// One circuit's race: the SpriteKit scene with the HUD over it.
struct RaceView: View {
    @State private var hud: RaceHUD
    @State private var scene: RaceScene
    @Environment(\.scenePhase) private var scenePhase

    init(track: Track, onExit: @escaping () -> Void) {
        let hud = RaceHUD(track: track)
        hud.onExit = onExit
        _hud = State(initialValue: hud)
        _scene = State(initialValue: RaceScene(track: track, hud: hud))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder],
                       debugOptions: Self.debugOptions)
                .ignoresSafeArea()
            RaceOverlay(hud: hud)
        }
        // Leaving the app ends the session; its summary is waiting on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scene.endSession() }
            // Quiet whenever the app isn't in front (Control Center, a call), and back on return.
            if phase == .active { RaceAudio.shared.start() } else { RaceAudio.shared.stop() }
        }
        .onAppear { RaceAudio.shared.start() }
        .onDisappear { RaceAudio.shared.stop() }
    }

    /// Launch with `-ApexShowFPS YES` (Xcode builds) to see frame rate, node and draw counts.
    private static var debugOptions: SpriteView.DebugOptions {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ApexShowFPS") { return [.showsFPS, .showsNodeCount, .showsDrawCount] }
        #endif
        return []
    }
}

/// The timing, speed and map over the race. Only its buttons take touches; everywhere else, touches reach the race.
struct RaceOverlay: View {
    let hud: RaceHUD
    @State private var soundOn = RaceAudio.shared.soundOn
    @State private var musicOn = RaceAudio.shared.musicOn

    var body: some View {
        ZStack {
            // A panel dims the race edge to edge, and keeps touches off it.
            if hud.showsPanel {
                Color.black.opacity(0.35).ignoresSafeArea()
            }
            ZStack {
                racingHUD
                    .opacity(hud.summary == nil && !hud.showsPanel ? 1 : 0)
                    .allowsHitTesting(hud.summary == nil && !hud.showsPanel)

                if hud.showsColors {
                    LiveryPicker(livery: Livery.shared, onDone: { hud.showsColors = false })
                } else if showsTuner {
                    #if DEBUG
                    TunerPanel(tuner: Tuner.shared, trackName: hud.trackName, laps: hud.botLaps,
                               stockLaps: hud.stockBotLaps, onDone: { hud.showsTuner = false })
                    #endif
                } else if hud.showsGraduation {
                    GraduationCard(onPickTrack: hud.onExit, onKeepPracticing: { hud.showsGraduation = false })
                } else if let summary = hud.summary {
                    SessionSummaryCard(summary: summary, standing: hud.standing, onRaceAgain: hud.onRaceAgain,
                                       onTracks: hud.onExit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hud.racing {
                    // Low and to the right, clear of the car on the left third of the screen.
                    StartCard(name: hud.trackName, best: hud.bestLap, medal: hud.bestMedal, next: hud.nextMedal,
                              practice: hud.isPractice)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.leading, 240)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
    }

    private var showsTuner: Bool {
        #if DEBUG
        return hud.showsTuner
        #else
        return false
        #endif
    }

    /// Timing, splits, map, buttons and speed: everything shown while racing.
    private var racingHUD: some View {
        ZStack {
            // One row across the top, above the track wherever it runs: timing, then the buttons with split and lap
            // banners under them, then the minimap. Side by side, so none can sit on another, whatever the screen
            // width or the lap time; both sides keep a fixed width so the buttons don't shift as times change.
            HStack(alignment: .top, spacing: 12) {
                timing
                    .allowsHitTesting(false)
                VStack(spacing: 8) {
                    controls
                    if let banner = hud.banner {
                        SplitBanner(banner: banner)
                            .id(banner.id)
                            .allowsHitTesting(false)
                            .task(id: banner.id) {
                                try? await Task.sleep(for: .seconds(2.4))
                                if hud.banner?.id == banner.id { hud.banner = nil }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                MiniMap(hud: hud)
                    .allowsHitTesting(false)
                    .frame(width: 170, alignment: .topTrailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SpeedGauge(hud: hud)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)

            if let coach = hud.coach, hud.racing {
                CoachPanel(coach: coach)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, 200)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Home, the menu, the tutorial's skip or the race's flag and trophy, and restart.
    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                hud.onLeave()
            } label: {
                RoundIcon(symbol: "house.fill")
            }
            Menu {
                Button {
                    hud.onToggleRacingLine()
                } label: {
                    Label(hud.showsRacingLine ? "Hide ideal line" : "Show ideal line",
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                Button {
                    hud.showsColors = true
                } label: {
                    Label("Car colors", systemImage: "paintpalette")
                }
                Toggle(isOn: $soundOn) { Label("Sound", systemImage: "speaker.wave.2") }
                Toggle(isOn: $musicOn) { Label("Music", systemImage: "music.note") }
                #if DEBUG
                Button {
                    hud.onTune()
                } label: {
                    Label("Tune controls", systemImage: "slider.horizontal.3")
                }
                #endif
                Button(role: .destructive) {
                    hud.onForgetBest()
                } label: {
                    Label("Clear best lap", systemImage: "trash")
                }
            } label: {
                RoundIcon(symbol: "ellipsis")
            }
            .onChange(of: soundOn) { _, on in RaceAudio.shared.soundOn = on }
            .onChange(of: musicOn) { _, on in RaceAudio.shared.musicOn = on }
            // Apex School has no standings or leaderboard, but a way out for anyone who'd rather just race.
            if hud.isPractice {
                Button {
                    SchoolProgress.markDone()
                    hud.onExit()
                } label: {
                    Label("SKIP", systemImage: "forward.fill")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(.black.opacity(0.45), in: Capsule())
                }
            } else {
                Button {
                    hud.onEndSession()
                } label: {
                    RoundIcon(symbol: "flag.checkered")
                }
                Button {
                    hud.onShowLeaderboard()
                } label: {
                    RoundIcon(symbol: "trophy.fill")
                }
            }
            Button {
                hud.onRestart()
            } label: {
                RoundIcon(symbol: "arrow.counterclockwise")
            }
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(hud.lapNumber == 0 ? "OUT LAP" : "LAP \(hud.lapNumber)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .opacity(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(hud.lapTime.map { LapFormat.time($0, decimals: 2) } ?? "--.--")
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit().italic())
                if let delta = hud.liveDelta {
                    // Live against the best lap, so you can see which corner the time goes in.
                    Text(LapFormat.delta(delta, decimals: 2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(delta <= 0 ? Color(red: 0.3, green: 0.9, blue: 0.45)
                                                    : Color(red: 1, green: 0.38, blue: 0.32))
                }
            }
            HStack(spacing: 5) {
                row("BEST", hud.bestLap, color: Color(red: 0.75, green: 0.5, blue: 1))
                if let medal = hud.bestMedal { MedalIcon(medal: medal, size: 12) }
            }
            row("LAST", hud.lastLap, color: .white)
            if hud.isPractice {
                // Apex School's goal: a dot per apex to hit.
                HStack(spacing: 5) {
                    Text("APEXES").font(.system(size: 12, weight: .heavy, design: .rounded)).opacity(0.7)
                    ForEach(0..<SchoolProgress.goal, id: \.self) { index in
                        Image(systemName: index < hud.schoolHits ? "circle.fill" : "circle")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(index < hud.schoolHits ? Color.schoolYellow : .white.opacity(0.6))
                    }
                }
                .padding(.top, 2)
            }
            if let rivalTime = hud.rivalTime {
                // The gold ghost: who you're chasing.
                HStack(spacing: 6) {
                    row("RIVAL", rivalTime, color: Livery.shared.paint(for: .rival).labelColor)
                    if let name = hud.rivalName {
                        // A Game Center alias can be long: it's cut short rather than widening the panel.
                        Text(name).font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.75)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: 176, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ time: Double?, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12, weight: .heavy, design: .rounded)).opacity(0.7)
            Text(time.map { LapFormat.time($0) } ?? "—")
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(time == nil ? .white : color)
        }
    }
}

/// A split or lap time, colored like F1 timing: purple for a best lap, green for a faster sector, yellow for slower.
struct SplitBanner: View {
    let banner: RaceHUD.Banner

    private var tint: Color {
        switch banner.tone {
        case .best: return Color(red: 0.62, green: 0.3, blue: 0.95)
        case .faster: return Color(red: 0.1, green: 0.7, blue: 0.3)
        case .slower: return Color(red: 0.95, green: 0.72, blue: 0.1)
        case .neutral: return Color(white: 0.25)
        }
    }

    var body: some View {
        // A medal won gets its own line: beside the lap and its detail, it would crowd them out on a phone.
        VStack(spacing: 6) {
            times
            if let medal = banner.medal {
                Label("\(medal.name.uppercased()) MEDAL", systemImage: "medal.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(medal.color, in: Capsule())
            }
        }
    }

    private var times: some View {
        HStack(spacing: 10) {
            Text(banner.title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .opacity(0.85)
            Text(banner.value)
                .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit().italic())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail = banner.detail {
                Text(detail)
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(banner.detail == nil ? tint.opacity(0.9) : Color.black.opacity(0.55), in: Capsule())
    }
}

/// Speed, with a bar showing it against top speed and an orange tick at the most the current line allows. When the
/// line is costing speed, the readout warms toward red.
struct SpeedGauge: View {
    let hud: RaceHUD

    var body: some View {
        let top = RaceTuning.topSpeed
        let scrub = min(1, hud.scrub)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(LapFormat.speed(hud.speed))
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit().italic())
                Text("km/h")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .opacity(0.7)
            }
            .foregroundStyle(Color(red: 1, green: 1 - 0.55 * scrub, blue: 1 - 0.9 * scrub))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: 170 * min(1, hud.speed / top))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)
                    .offset(x: 170 * min(1, hud.lineSpeed / top) - 1.5)
                    .opacity(hud.lineSpeed < top - 1 ? 1 : 0)
            }
            .frame(width: 170, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The whole circuit, north up, with you, your best lap's ghost (blue) and your rival (gold) on it.
struct MiniMap: View {
    let hud: RaceHUD

    var body: some View {
        let car = hud.carMarker
        let ghost = hud.ghostMarker
        let rival = hud.rivalMarker
        let livery = Livery.shared
        let colors = (car: livery.paint(for: .car).labelColor, best: livery.paint(for: .best).labelColor,
                      rival: livery.paint(for: .rival).labelColor)
        let outline = hud.mapOutline
        // Fits the circuit in a 170 × 100 box, so tall circuits don't push the buttons down.
        let width = min(170, 100 * hud.mapAspect)
        Canvas { context, size in
            var path = Path()
            path.addLines(outline.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
            path.closeSubpath()
            context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            func dot(_ point: CGPoint, radius: CGFloat, color: Color) {
                let rect = CGRect(x: point.x * size.width - radius, y: point.y * size.height - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
            if let rival { dot(rival, radius: 3.5, color: colors.rival) }
            if let ghost { dot(ghost, radius: 3.5, color: colors.best) }
            dot(car, radius: 5, color: .white)
            dot(car, radius: 3.5, color: colors.car)
        }
        .frame(width: width, height: width / hud.mapAspect)
        .padding(8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StartCard: View {
    let name: String
    let best: Double?
    var medal: Medal?
    var next: (medal: Medal, target: Double)?
    var practice = false

    var body: some View {
        VStack(spacing: 8) {
            Text(name.uppercased())
                .font(.system(size: 30, weight: .black, design: .rounded).italic())
            Text("Hold to steer up. Let go to steer down.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(practice
                 ? "Follow the yellow line: stay wide, and when you reach TURN IN let go to dive for the yellow APEX, then hold to ease back out to EXIT. You'll feel a tick at each."
                 : "Straight is fast: every weave costs speed. Swing wide, clip the apex, and run out wide.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .opacity(0.85)
            if practice {
                Text("GOAL: HIT \(SchoolProgress.goal) APEXES")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.schoolYellow)
            }
            if best != nil || next != nil {
                HStack(spacing: 14) {
                    if let best {
                        HStack(spacing: 5) {
                            Text("Best lap \(LapFormat.time(best))")
                                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(red: 0.75, green: 0.5, blue: 1))
                            if let medal { MedalIcon(medal: medal) }
                        }
                    }
                    if let next {
                        NextMedalLabel(medal: next.medal, target: next.target, size: 13, showsName: true)
                    }
                }
            }
            Text("TOUCH TO START")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Apex School's end: the goal's reached, so off to pick a real circuit, or a little more practice first.
struct GraduationCard: View {
    let onPickTrack: () -> Void
    let onKeepPracticing: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.schoolYellow)
            Text("YOU'RE READY")
                .font(.system(size: 30, weight: .black, design: .rounded).italic())
            Text("\(SchoolProgress.goal) apexes hit. Swing wide, clip the apex, run out wide: that's the whole game. Now do it against the clock.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .opacity(0.85)
            Button(action: onPickTrack) {
                Label("PICK A TRACK", systemImage: "flag.checkered")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
            }
            .padding(.top, 4)
            Button(action: onKeepPracticing) {
                Text("Keep practicing")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .opacity(0.8)
            }
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
}

extension Color {
    /// Apex School's yellow: its home-screen button, goal and turn-in cue.
    static let schoolYellow = Color(red: 1, green: 0.82, blue: 0.1)
}

struct RoundIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.45), in: Circle())
    }
}

/// The end of a session: its best lap, and where that lap falls among other players' bests.
struct SessionSummaryCard: View {
    let summary: SessionSummary
    let standing: StandingState
    let onRaceAgain: () -> Void
    let onTracks: () -> Void

    private let purple = Color(red: 0.75, green: 0.5, blue: 1)

    var body: some View {
        VStack(spacing: 12) {
            Text("SESSION COMPLETE · \(summary.trackName.uppercased())")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .opacity(0.75)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SESSION BEST").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                    Text(LapFormat.time(summary.best))
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit().italic())
                    if summary.isPersonalBest {
                        Text("NEW PERSONAL BEST").font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(purple)
                    } else if let personalBest = summary.personalBest {
                        Text("Personal best \(LapFormat.time(personalBest))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .opacity(0.8)
                    }
                    Text("\(summary.laps) lap\(summary.laps == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.7)
                    medals.padding(.top, 2)
                }
                standingHeadline
                    .frame(minWidth: 180, alignment: .leading)
            }
            standingDetail
            HStack(spacing: 12) {
                Button(action: onTracks) {
                    Text("TRACKS")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 2))
                }
                Button(action: onRaceAgain) {
                    Text("RACE AGAIN")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(Color(white: 0.07).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
    }

    /// The session best's medal ("NEW GOLD MEDAL" the first time), then the next medal to chase.
    @ViewBuilder private var medals: some View {
        if summary.medal != nil || summary.nextMedal != nil {
            HStack(spacing: 10) {
                if let medal = summary.medal {
                    HStack(spacing: 4) {
                        MedalIcon(medal: medal, size: 13)
                        Text((summary.isNewMedal ? "NEW " : "") + "\(medal.name.uppercased()) MEDAL")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(medal.color)
                    }
                }
                if let next = summary.nextMedal, let target = summary.nextMedalTarget {
                    NextMedalLabel(medal: next, target: target, showsName: true)
                }
            }
        }
    }

    @ViewBuilder private var standingHeadline: some View {
        switch standing {
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                Text("VS OTHER PLAYERS").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                ProgressView().tint(.white)
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 2) {
                Text("VS OTHER PLAYERS").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                Text("Standings will show here once you're online.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.85)
            }
        case .ready(let standing, _):
            VStack(alignment: .leading, spacing: 2) {
                Text("VS OTHER PLAYERS").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                if standing.players == 0 {
                    Text("You're the first!").font(.system(size: 24, weight: .heavy, design: .rounded))
                } else {
                    Text("Faster than \(Int((standing.beatenShare * 100).rounded(.down)))%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                    Text("#\(standing.place) of \(standing.players + 1) players")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.8)
                }
            }
        }
    }

    @ViewBuilder private var standingDetail: some View {
        if case .ready(let standing, let sample) = standing, standing.players > 0 {
            VStack(spacing: 4) {
                StandingChart(standing: standing, lapMs: Int((summary.best * 1000).rounded()))
                    .frame(height: 74)
                if sample {
                    Text("Sample players: the lap service isn't live yet")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.6)
                }
            }
        }
    }
}

/// Other players' best laps as a histogram, with your lap marked: its bar in your car's red, and a line at its time.
struct StandingChart: View {
    let standing: Standing
    let lapMs: Int

    var body: some View {
        let histogram = standing.histogram
        let counts = histogram.counts
        let yourColor = Livery.shared.paint(for: .car).labelColor
        Canvas { context, size in
            guard let tallest = counts.max(), tallest > 0 else { return }
            let markerRoom: CGFloat = 14, axisRoom: CGFloat = 16, gap: CGFloat = 2
            let plotHeight = size.height - markerRoom - axisRoom
            let barWidth = (size.width - gap * CGFloat(counts.count - 1)) / CGFloat(counts.count)
            let span = CGFloat(histogram.widthMs * counts.count)
            let yours = min(max((lapMs - histogram.fromMs) / histogram.widthMs, 0), counts.count - 1)
            for (i, count) in counts.enumerated() where count > 0 {
                let height = max(2, plotHeight * CGFloat(count) / CGFloat(tallest))
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: markerRoom + plotHeight - height,
                                  width: barWidth, height: height)
                let bar = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).path(in: rect)
                context.fill(bar, with: .color(i == yours ? yourColor
                                                           : .white.opacity(0.32)))
            }
            // Baseline.
            context.fill(Path(CGRect(x: 0, y: markerRoom + plotHeight, width: size.width, height: 1)),
                         with: .color(.white.opacity(0.25)))
            // Your lap.
            let x = min(max(CGFloat(lapMs - histogram.fromMs) / span * size.width, 1), size.width - 1)
            context.fill(Path(CGRect(x: x - 1, y: markerRoom - 2, width: 2, height: plotHeight + 2)),
                         with: .color(.white))
            context.draw(Text("YOU").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white),
                         at: CGPoint(x: min(max(x, 12), size.width - 12), y: markerRoom / 2 - 1))
            // The range of times.
            let label = { (ms: Int) in
                Text(LapFormat.time(Double(ms) / 1000, decimals: 1))
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            let axisY = size.height - axisRoom / 2 + 1
            context.draw(label(histogram.fromMs), at: CGPoint(x: 0, y: axisY), anchor: .leading)
            context.draw(label(histogram.fromMs + histogram.widthMs * counts.count), at: CGPoint(x: size.width, y: axisY),
                         anchor: .trailing)
            context.draw(Text("FASTER").font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45)), at: CGPoint(x: 40, y: axisY), anchor: .leading)
            context.draw(Text("SLOWER").font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45)), at: CGPoint(x: size.width - 40, y: axisY),
                         anchor: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel("Other players' best laps, from \(LapFormat.time(Double(histogram.fromMs) / 1000, decimals: 1)) "
                            + "to \(LapFormat.time(Double(histogram.fromMs + histogram.widthMs * counts.count) / 1000, decimals: 1)) seconds. "
                            + "Your lap beats \(Int((standing.beatenShare * 100).rounded(.down))) percent of them.")
    }
}

/// Apex School's coach: one big cue that changes three times a corner (stay wide, then turn in, then ease out), with a
/// line on where to aim.
struct CoachPanel: View {
    let coach: RaceHUD.Coach

    private var tint: Color {
        switch coach.phase {
        case .lineUp: return .white
        case .turnIn: return .schoolYellow
        case .runOut: return Color(red: 0.4, green: 0.7, blue: 1)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(coach.title)
                .font(.system(size: 26, weight: .black, design: .rounded).italic())
                .foregroundStyle(tint)
            Text(coach.detail)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.9)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.15), value: coach.title)
    }
}
