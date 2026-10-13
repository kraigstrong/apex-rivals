import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var hud: RaceHUD
    @State private var scene: RaceScene
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let track = Track(.harbourPark)
        let hud = RaceHUD(track: track)
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
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { GameCenter.shared.signIn() }
        // Leaving the app ends the session; its summary is waiting on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scene.endSession() }
        }
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
            racingHUD
                .opacity(hud.summary == nil ? 1 : 0)
                .allowsHitTesting(hud.summary == nil)

            if let summary = hud.summary {
                SessionSummaryCard(summary: summary, standing: hud.standing, onRaceAgain: hud.onRaceAgain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hud.racing {
                // Low and to the right, clear of the car on the left third of the screen.
                StartCard(name: hud.trackName, best: hud.bestLap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, 240)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
    }

    /// Timing, splits, map, buttons and speed: everything shown while racing.
    private var racingHUD: some View {
        ZStack {
            timing
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

            if let banner = hud.banner {
                SplitBanner(banner: banner)
                    .id(banner.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .task(id: banner.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        if hud.banner?.id == banner.id { hud.banner = nil }
                    }
            }

            VStack(alignment: .trailing, spacing: 10) {
                MiniMap(hud: hud)
                    .allowsHitTesting(false)
                HStack(spacing: 10) {
                    Menu {
                        Button {
                            hud.onToggleRacingLine()
                        } label: {
                            Label(hud.showsRacingLine ? "Hide ideal line" : "Show ideal line",
                                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        Button(role: .destructive) {
                            hud.onForgetBest()
                        } label: {
                            Label("Clear best lap", systemImage: "trash")
                        }
                    } label: {
                        RoundIcon(symbol: "ellipsis")
                    }
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
                    Button {
                        hud.onRestart()
                    } label: {
                        RoundIcon(symbol: "arrow.counterclockwise")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            SpeedGauge(hud: hud)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(hud.lapNumber == 0 ? "OUT LAP" : "LAP \(hud.lapNumber)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .opacity(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(hud.lapTime.map { LapFormat.time($0, decimals: 2) } ?? "--.--")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit().italic())
                if let delta = hud.liveDelta {
                    // Live against the best lap, so you can see which corner the time goes in.
                    Text(LapFormat.delta(delta, decimals: 2))
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(delta <= 0 ? Color(red: 0.3, green: 0.9, blue: 0.45)
                                                    : Color(red: 1, green: 0.38, blue: 0.32))
                }
            }
            row("BEST", hud.bestLap, color: Color(red: 0.75, green: 0.5, blue: 1))
            row("LAST", hud.lastLap, color: .white)
            if let rivalTime = hud.rivalTime {
                // The gold ghost: who you're chasing.
                HStack(spacing: 6) {
                    row("RIVAL", rivalTime, color: Color(red: 1, green: 0.78, blue: 0.2))
                    if let name = hud.rivalName {
                        Text(name).font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.75)
                    }
                }
            }
        }
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
        HStack(spacing: 10) {
            Text(banner.title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .opacity(0.85)
            Text(banner.value)
                .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit().italic())
            if let detail = banner.detail {
                Text(detail)
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
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
        let outline = hud.mapOutline
        let width: CGFloat = 170
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
            if let rival { dot(rival, radius: 3.5, color: Color(red: 1, green: 0.78, blue: 0.2)) }
            if let ghost { dot(ghost, radius: 3.5, color: Color(red: 0.3, green: 0.8, blue: 1)) }
            dot(car, radius: 5, color: .white)
            dot(car, radius: 3.5, color: Color(red: 0.95, green: 0.15, blue: 0.1))
        }
        .frame(width: width, height: width / hud.mapAspect)
        .padding(8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StartCard: View {
    let name: String
    let best: Double?

    var body: some View {
        VStack(spacing: 8) {
            Text(name.uppercased())
                .font(.system(size: 30, weight: .black, design: .rounded).italic())
            Text("Hold to steer up. Let go to steer down.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Straight is fast: every weave costs speed. Swing wide, clip the apex, and run out wide.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .opacity(0.85)
            if let best {
                Text("Best lap \(LapFormat.time(best))")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(red: 0.75, green: 0.5, blue: 1))
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
                }
                standingHeadline
                    .frame(minWidth: 180, alignment: .leading)
            }
            standingDetail
            Button(action: onRaceAgain) {
                Text("RACE AGAIN")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(Color(white: 0.07).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
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
                context.fill(bar, with: .color(i == yours ? Color(red: 0.95, green: 0.2, blue: 0.15)
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
