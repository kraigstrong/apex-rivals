import SwiftUI

/// What the unlock opens: every circuit past Ardennes, each with the ideal line threading around it, and every circuit
/// added later; then its price, Restore and Not now. Shown when a locked circuit is tapped on the track list. Modeled on
/// Bigger Fish's `UnlockView`, with the circuits drawn where it plays a clip of each world.
struct UnlockView: View {
    let purchases: CircuitPurchases
    /// The locked circuit tapped to get here: ringed on the screen, and raced once it's open.
    var circuit: String?
    let onRace: (String) -> Void
    let onClose: () -> Void

    private enum Stage: Equatable {
        case offer, working
        case message(String, String, unlocked: Bool)
    }
    @State private var stage = Stage.offer
    @State private var shown = false

    var body: some View {
        ZStack {
            // The track list's grass under a dark wash, so nothing behind shows through the words.
            MowedGrass().ignoresSafeArea()
            Color.black.opacity(0.82).ignoresSafeArea()
            // Laid out for a phone, and drawn bigger on a bigger screen (an iPad), as much bigger as fits both ways.
            GeometryReader { geometry in
                let scale = max(1, min(geometry.size.width / Self.designSize.width,
                                       geometry.size.height / Self.designSize.height))
                let size = CGSize(width: geometry.size.width / scale, height: geometry.size.height / scale)
                Group {
                    switch stage {
                    case .offer:
                        offer(width: size.width)
                    case .working:
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).tint(.white)
                            Text("Talking to the App Store…").font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                    case .message(let title, let line, let unlocked):
                        message(title, line, unlocked: unlocked)
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .scaleEffect(shown ? 1 : 0.94).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shown = true } }
        // Bought on another device, approved by a parent (often while WAITING FOR APPROVAL is up), or restored while this
        // was open. A purchase or restore under way says so itself when it's done.
        .onChange(of: purchases.isUnlocked) { _, unlocked in
            if unlocked && stage != .working { stage = Self.unlockedMessage }
        }
        .task { await purchases.loadProduct() }
    }

    /// The room an iPhone 17 Pro leaves it in landscape.
    private static let designSize = CGSize(width: 750, height: 370)

    private func offer(width: CGFloat) -> some View {
        let circuits = CircuitUnlock.circuitsItOpens
        let gap: CGFloat = 10
        let cardWidth = min(190, (width - 48 - gap * CGFloat(circuits.count - 1)) / CGFloat(circuits.count))
        return VStack(spacing: 0) {
            Text("UNLOCK EVERY CIRCUIT")
                .font(.system(size: 30, weight: .black, design: .rounded).italic())
            Text("One purchase opens every circuit, yours to keep.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .opacity(0.85)
            Spacer(minLength: 8)
            HStack(spacing: gap) {
                ForEach(circuits, id: \.id) { layout in
                    UnlockCircuitCard(track: TrackCatalog.track(layout.id), width: cardWidth,
                                      featured: layout.id == circuit)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 6) {
                perk("plus.circle.fill", "Plus every circuit added later, at no extra cost.")
                perk("medal.fill", "Each with its own medals, leaderboard and rival ghosts to chase.")
            }
            Spacer(minLength: 8)
            UnlockButton(title: purchases.displayPrice.map { "UNLOCK ALL FOR \($0)" } ?? "UNLOCK ALL", action: buy)
            HStack(spacing: 22) {
                Text("One-time purchase. No ads.").opacity(0.6)
                Button("Restore purchase", action: restore).buttonStyle(.plain).opacity(0.85)
                Button("Not now", action: onClose).buttonStyle(.plain).opacity(0.85)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxHeight: 440)
    }

    private func perk(_ symbol: String, _ line: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(GhostThreadLogo.lineColor)
                .frame(width: 22)
            Text(line).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }

    private func message(_ title: String, _ line: String, unlocked: Bool) -> some View {
        VStack(spacing: 10) {
            if unlocked {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 34))
                    .foregroundStyle(GhostThreadLogo.lineColor)
            }
            Text(title).font(.system(size: 30, weight: .black, design: .rounded).italic())
            Text(line).font(.system(size: 14, weight: .medium, design: .rounded)).opacity(0.85)
            if unlocked, let circuit, let name = TrackLayout.named(circuit)?.name {
                UnlockButton(title: "RACE \(name.uppercased())") { onRace(circuit) }.padding(.top, 6)
            } else {
                UnlockButton(title: unlocked ? "LET'S RACE" : "OK") { unlocked ? onClose() : (stage = .offer) }
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 440)
    }

    private static let unlockedMessage = Stage.message("EVERY CIRCUIT IS OPEN",
                                                       "And every circuit added later opens as it arrives.",
                                                       unlocked: true)

    private func buy() {
        stage = .working
        Task {
            switch await purchases.purchase() {
            case .unlocked:
                stage = Self.unlockedMessage
            case .pending:
                stage = .message("WAITING FOR APPROVAL", "Once it's approved, every circuit opens.", unlocked: false)
            case .cancelled:
                stage = .offer
            case .failed:
                stage = .message("SOMETHING WENT WRONG", "The App Store didn't finish the purchase. Try again later.",
                                 unlocked: false)
            }
        }
    }

    private func restore() {
        stage = .working
        Task {
            stage = await purchases.restore() ? Self.unlockedMessage
                : .message("NOTHING TO RESTORE", "No unlock was found for this Apple Account.", unlocked: false)
        }
    }
}

/// The unlock's buttons, in the logo's thread yellow.
private struct UnlockButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 30)
                .padding(.vertical, 11)
                .background(GhostThreadLogo.lineColor, in: Capsule())
                .shadow(color: GhostThreadLogo.lineColor.opacity(0.45), radius: 12)
        }
        .buttonStyle(.plain)
    }
}

/// One circuit on the unlock screen: its thread and its name. The tapped one is ringed in yellow.
private struct UnlockCircuitCard: View {
    let track: Track
    let width: CGFloat
    let featured: Bool

    var body: some View {
        VStack(spacing: 6) {
            CircuitThread(track: track)
                .frame(height: ((width - 20) * 0.72).rounded())
            Text(track.layout.name.uppercased())
                .font(.system(size: 15, weight: .heavy, design: .rounded).italic())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(width: width)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(featured ? GhostThreadLogo.lineColor : .white.opacity(0.12), lineWidth: featured ? 2 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.layout.name): \(track.layout.summary)")
    }
}

/// A circuit's outline, north up, with the ideal line threaded around it: a car on the line lapping at the speed it
/// allows, four times real time, trailing its thread. With Reduce Motion it stands still, the whole line drawn.
struct CircuitThread: View {
    let track: Track
    @State private var lap: ThreadLap?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Laps go by this many times faster than real ones.
    static let playback = 4.0
    /// How much of the lap the thread trails behind the car.
    static let trail = 0.35

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || lap == nil)) { timeline in
            Canvas { context, size in
                // Room for the line wherever it runs inside the walls, and for the car's glow at the edges.
                let bounds = track.bounds.insetBy(dx: -track.width / 2, dy: -track.width / 2)
                let scale = min((size.width - 14) / bounds.width, (size.height - 14) / bounds.height)
                let inset = CGPoint(x: (size.width - bounds.width * scale) / 2,
                                    y: (size.height - bounds.height * scale) / 2)
                func map(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: inset.x + (point.x - bounds.minX) * scale, y: inset.y + (bounds.maxY - point.y) * scale)
                }
                var outline = Path()
                outline.addLines(stride(from: 0, to: track.count, by: 20).map {
                    map(CGPoint(x: track.x[$0], y: track.y[$0]))
                })
                outline.closeSubpath()
                // Dimmer than the track list's, so the thread stands out on it.
                context.stroke(outline, with: .color(.white.opacity(0.12)),
                               style: StrokeStyle(lineWidth: 8, lineJoin: .round))
                context.stroke(outline, with: .color(.white.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                guard let lap else { return }
                let yellow = GhostThreadLogo.lineColor
                if reduceMotion {
                    var line = Path()
                    line.addLines(lap.points.map(map))
                    line.closeSubpath()
                    context.stroke(line, with: .color(yellow), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    return
                }
                let now = timeline.date.timeIntervalSinceReferenceDate * Self.playback
                let head = now.truncatingRemainder(dividingBy: lap.duration)
                // The thread fades and thins toward its tail, a piece at a time.
                let pieces = 14, steps = 5
                let length = lap.duration * Self.trail
                for piece in 0..<pieces {
                    let fade = 1 - Double(piece) / Double(pieces)
                    var path = Path()
                    path.addLines((0...steps).map { step in
                        let back = (Double(piece) + Double(step) / Double(steps)) / Double(pieces) * length
                        return map(lap.position(at: head - back))
                    })
                    context.stroke(path, with: .color(yellow.opacity(fade)),
                                   style: StrokeStyle(lineWidth: 1.2 + 2.3 * fade, lineCap: .round, lineJoin: .round))
                }
                let car = map(lap.position(at: head))
                func dot(_ radius: CGFloat, _ color: Color) {
                    context.fill(Path(ellipseIn: CGRect(x: car.x - radius, y: car.y - radius,
                                                        width: radius * 2, height: radius * 2)), with: .color(color))
                }
                dot(7, yellow.opacity(0.3))
                dot(3.5, yellow)
                dot(1.5, .white)
            }
        }
        .task { lap = await ThreadLap.load(track.layout.id) }
        .accessibilityHidden(true)
    }
}

/// The ideal line around a circuit, and when a car on it reaches each point: its speed capped by the line's curvature,
/// as the race caps it (`√(grip / κ)`), and gained and lost at the car's acceleration and braking.
struct ThreadLap: Sendable {
    let points: [CGPoint]
    /// Seconds into the lap at each point, and the whole lap last.
    let times: [Double]

    var duration: Double { times[times.count - 1] }

    init(track: Track, spacing: Double = 24) {
        let line = RacingLine(track: track)
        let count = Int((track.length / spacing).rounded())
        let step = track.length / Double(count)
        let points = (0..<count).map { i in
            let s = Double(i) * step
            return track.point(s: s, n: line.offset(at: s))
        }
        func wrap(_ i: Int) -> Int { (i % count + count) % count }
        let headings = (0..<count).map { i in
            let a = points[i], b = points[wrap(i + 1)]
            return atan2(b.y - a.y, b.x - a.x)
        }
        // The line's curvature over the length the race smooths the car's heading over.
        let half = max(1, Int((RaceTuning.straightnessLength / step / 2).rounded()))
        var speeds = (0..<count).map { i in
            var turn = headings[wrap(i + half)] - headings[wrap(i - half)]
            turn = atan2(sin(turn), cos(turn))
            let curvature = abs(turn) / (Double(half * 2) * step)
            return curvature > 0 ? min(RaceTuning.topSpeed, (RaceTuning.grip / curvature).squareRoot())
                                 : RaceTuning.topSpeed
        }
        // Braking into each corner, then accelerating out, twice round so the lap joins up.
        for _ in 0..<2 {
            for i in (0..<count).reversed() {
                let next = speeds[wrap(i + 1)]
                speeds[i] = min(speeds[i], (next * next + 2 * RaceTuning.braking * step).squareRoot())
            }
        }
        for _ in 0..<2 {
            for i in 0..<count {
                let previous = speeds[wrap(i - 1)]
                let acceleration = RaceTuning.acceleration
                    * (1 - RaceTuning.accelerationFade * previous / RaceTuning.topSpeed)
                speeds[i] = max(RaceTuning.minimumSpeed,
                                min(speeds[i], (previous * previous + 2 * acceleration * step).squareRoot()))
            }
        }
        var times = [0.0]
        for i in 0..<count {
            times.append(times[i] + step * 2 / (speeds[i] + speeds[wrap(i + 1)]))
        }
        self.points = points
        self.times = times
    }

    /// Where the car is `time` seconds into a lap; any time, wrapped to the lap.
    func position(at time: Double) -> CGPoint {
        var t = time.truncatingRemainder(dividingBy: duration)
        if t < 0 { t += duration }
        // The last time at or before t.
        var low = 0, high = points.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if times[middle] <= t { low = middle } else { high = middle - 1 }
        }
        let a = points[low], b = points[(low + 1) % points.count]
        let f = (t - times[low]) / (times[low + 1] - times[low])
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Built once for each circuit, off the main thread: the ideal line takes a moment to solve.
    @MainActor private static var built: [String: ThreadLap] = [:]

    @MainActor static func load(_ id: String) async -> ThreadLap {
        if let lap = built[id] { return lap }
        let lap = await Task.detached(priority: .userInitiated) { ThreadLap(track: TrackCatalog.track(id)) }.value
        built[id] = lap
        return lap
    }
}
