import SpriteKit
import SwiftUI

/// The track list, or a race on the track picked from it.
struct ContentView: View {
    /// The track being raced; nil shows the track list.
    @State private var racing: String? = Self.launchTrack
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

    /// Launch with `-ApexTrack snake` (Xcode builds) to skip the track list and race that circuit. An unknown id
    /// shows the list.
    private static var launchTrack: String? {
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "ApexTrack"),
           id == TrackCatalog.school.layout.id || TrackCatalog.tracks.contains(where: { $0.layout.id == id }) {
            return id
        }
        #endif
        return nil
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
            // Held still and quiet whenever the app isn't in front (Control Center, a call), and back on return.
            hud.isAppActive = phase == .active
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
                } else if hud.showsFriends {
                    FriendPicker(trackName: hud.trackName, list: hud.friends, racing: hud.racingFriend,
                                 yourBest: hud.bestLap, onPick: hud.onPickFriend, onDone: { hud.showsFriends = false })
                } else if hud.showsGraduation {
                    GraduationCard(onPickTrack: hud.onExit, onKeepPracticing: { hud.showsGraduation = false })
                } else if let summary = hud.summary {
                    SessionSummaryCard(summary: summary, standing: hud.standing, onRaceAgain: hud.onRaceAgain,
                                       onTracks: hud.onExit, onShare: hud.onShare)
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

    /// Home, settings, the tutorial's skip or the race's flag and trophy, and restart.
    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                hud.onLeave()
            } label: {
                RoundIcon(symbol: "house.fill")
            }
            RaceMenu(hud: hud)
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
                        .foregroundStyle(.white.opacity(hud.canEndSession ? 1 : 0.35))
                }
                // Dimmed until a lap is finished: before that there's no summary, and ending would only restart.
                .disabled(!hud.canEndSession)
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
        .hudPanel()
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
        .hudPanel()
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
            // A dark casing under the line keeps it crisp over anything light behind the map.
            context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
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
        .hudPanel(cornerRadius: 10)
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

extension View {
    /// The panel behind the HUD's timing, map and speed. It blurs what's under it as well as dimming it, so scenery
    /// passing beneath (a grandstand's crowd, curbs, the track's lines) melts into a soft wash instead of breaking up
    /// the text and the map's line. The dimming stays light, so the track under it still shows, just softened.
    func hudPanel(cornerRadius: CGFloat = 12) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(.black.opacity(0.3))
            }
            // The dark material whatever the phone's appearance: the light one would wash out the white text.
            .environment(\.colorScheme, .dark)
        }
    }
}

/// The race's settings: the ideal line, race a friend, car colors, sound and music, and clearing the best lap. A UIKit
/// button rather than SwiftUI's `Menu`, which can't say when it's open: the race holds still while the menu is up
/// (`RaceHUD.showsMenu`). The menu is built as it opens, from the race as it is then, so the timing's 20 Hz updates
/// never rebuild it under a finger.
struct RaceMenu: UIViewRepresentable {
    let hud: RaceHUD

    func makeUIView(context: Context) -> MenuButton {
        Self.button(for: hud)
    }

    func updateUIView(_ button: MenuButton, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuButton, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    static func button(for hud: RaceHUD) -> MenuButton {
        let button = MenuButton(symbol: "gearshape.fill")
        button.accessibilityLabel = "Settings"
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [hud] completion in
            completion(Self.items(for: hud))
        }])
        button.onOpen = { [hud] open in hud.showsMenu = open }
        return button
    }

    /// The menu as the race stands: which way the ideal line toggles, whether sound and music are on.
    static func items(for hud: RaceHUD) -> [UIMenuElement] {
        func item(_ title: String, _ symbol: String, attributes: UIMenuElement.Attributes = [],
                  state: UIMenuElement.State = .off, action: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), attributes: attributes, state: state) { _ in
                action()
            }
        }
        let audio = RaceAudio.shared
        var items = [item(hud.showsRacingLine ? "Hide ideal line" : "Show ideal line",
                          "point.topleft.down.to.point.bottomright.curvepath") { hud.onToggleRacingLine() }]
        if !hud.isPractice {
            items.append(item("Race a friend", "person.2") { hud.onShowFriends() })
        }
        items.append(item("Car colors", "paintpalette") { hud.showsColors = true })
        items.append(item("Sound", "speaker.wave.2", state: audio.soundOn ? .on : .off) { audio.soundOn.toggle() })
        items.append(item("Music", "music.note", state: audio.musicOn ? .on : .off) { audio.musicOn.toggle() })
        #if DEBUG
        items.append(item("Tune controls", "slider.horizontal.3") { hud.onTune() })
        items.append(item("Share telemetry", "waveform.path.ecg") { hud.onShareTelemetry() })
        #endif
        items.append(item("Clear best lap", "trash", attributes: .destructive) { hud.onForgetBest() })
        return items
    }
}

/// A `RoundIcon` as a UIKit button whose menu opens on a tap, and which says when the menu opens and closes.
final class MenuButton: UIButton {
    /// Called with true as the menu opens, and false as it starts to close (on a pick, or a tap anywhere else). Not
    /// when the closing animation completes: UIKit finishes that over a second after the menu has faded from view, and
    /// the race would sit frozen with nothing over it.
    var onOpen: (Bool) -> Void = { _ in }

    init(symbol: String) {
        super.init(frame: .zero)
        var look = UIButton.Configuration.plain()
        look.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17,
                                                                                               weight: .bold))
        look.baseForegroundColor = .white
        look.background.backgroundColor = .black.withAlphaComponent(0.45)
        look.cornerStyle = .capsule
        look.contentInsets = .zero
        configuration = look
        showsMenuAsPrimaryAction = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 40) }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onOpen(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onOpen(false)
    }
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
    let onShare: () -> Void

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
                if summary.lap != nil {
                    Button(action: onShare) {
                        Label("SHARE", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 2))
                    }
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
        let label = Text("STANDING").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
        switch standing {
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                label
                ProgressView().tint(.white)
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 2) {
                label
                Text("Standings will show here once you're online.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.85)
            }
        case .ready(let standing, _):
            VStack(alignment: .leading, spacing: 2) {
                label
                // Beside a wide session best and medals, the headline shrinks to fit rather than cutting off. Over a small
                // board's dots it's short ("9th of 9" at most) and always fits, but SwiftUI shrinks it anyway when the
                // dots are the column's widest line, so there it keeps its size.
                let dots = standing.players > 0 && standing.isSmallBoard
                Text(standing.headline)
                    .font(.system(size: standing.players == 0 ? 24 : 28, weight: .heavy, design: .rounded)
                        .monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(dots ? 1 : 0.6)
                if let detail = standing.detail {
                    Text(detail)
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.8)
                }
                if dots {
                    RankDots(standing: standing).padding(.top, 8)
                }
            }
        }
    }

    /// A big board's histogram, under both columns. A small board's players are dots under the headline instead.
    @ViewBuilder private var standingDetail: some View {
        if case .ready(let standing, let sample) = standing, standing.players > 0, sample || !standing.isSmallBoard {
            VStack(spacing: 4) {
                if !standing.isSmallBoard {
                    StandingChart(standing: standing, lapMs: Int((summary.best * 1000).rounded()))
                        .frame(height: 74)
                }
                if sample {
                    Text("Sample players: the lap service isn't live yet")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.6)
                }
            }
        }
    }
}

/// A small board's players as dots in finishing order, fastest first: yours in your car's color under YOU, the others
/// outlined.
struct RankDots: View {
    let standing: Standing

    var body: some View {
        let yourColor = Livery.shared.paint(for: .car).markColor
        // Nine dots fit the standing's 180-point column, so a small board never squeezes the session best beside it.
        HStack(spacing: 6) {
            ForEach(1...standing.field, id: \.self) { place in
                VStack(spacing: 3) {
                    Group {
                        if place == standing.place {
                            Circle().fill(yourColor)
                        } else {
                            Circle().strokeBorder(.white.opacity(0.45), lineWidth: 2)
                        }
                    }
                    .frame(width: 14, height: 14)
                    // Above your dot without widening the row.
                    .overlay(alignment: .top) {
                        if place == standing.place {
                            Text("YOU").font(.system(size: 9, weight: .heavy, design: .rounded))
                                .fixedSize()
                                .offset(y: -13)
                        }
                    }
                    Text("\(place)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.55)
                }
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Standing.ordinal(standing.place)) of \(standing.field) players")
    }
}

/// Other players' best laps as a histogram, with your lap marked: the players it beats lit, those ahead of it dimmed,
/// its own bar in your car's color, and a line at its time.
struct StandingChart: View {
    let standing: Standing
    let lapMs: Int

    var body: some View {
        let histogram = standing.histogram
        let counts = histogram.counts
        let yourColor = Livery.shared.paint(for: .car).markColor
        Canvas { context, size in
            guard let tallest = counts.max(), tallest > 0 else { return }
            let markerRoom: CGFloat = 14, axisRoom: CGFloat = 16, gap: CGFloat = 2
            let plotHeight = size.height - markerRoom - axisRoom
            let barWidth = (size.width - gap * CGFloat(counts.count - 1)) / CGFloat(counts.count)
            let span = CGFloat(histogram.widthMs * counts.count)
            // Your bar, if your lap falls among the others. Slower bars are players it beats; a lap ahead of everyone
            // is in no bar and beats them all.
            let yours = histogram.bucket(of: lapMs)
            for (i, count) in counts.enumerated() where count > 0 {
                let height = max(2, plotHeight * CGFloat(count) / CGFloat(tallest))
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: markerRoom + plotHeight - height,
                                  width: barWidth, height: height)
                let bar = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).path(in: rect)
                let beaten = yours.map { i > $0 } ?? true
                context.fill(bar, with: .color(i == yours ? yourColor : .white.opacity(beaten ? 0.75 : 0.2)))
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
