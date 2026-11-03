import SwiftUI

/// Every circuit's geometry, built once.
enum TrackCatalog {
    static let tracks: [Track] = TrackLayout.all.map { Track($0) }
    static let school = Track(.apexSchool)

    static func track(_ id: String) -> Track {
        if id == school.layout.id { return school }
        return tracks.first { $0.layout.id == id } ?? tracks[0]
    }
}

/// The main menu: pick a circuit. A locked one offers the unlock instead.
struct TrackMenu: View {
    let purchases: CircuitPurchases
    let onSelect: (String) -> Void
    /// Each circuit's saved best lap, read whenever the menu appears.
    @State private var bests: [String: Double] = [:]
    @State private var showsColors = false
    /// Apex School has been graduated or skipped, so it no longer needs pointing out.
    @State private var schoolDone = SchoolProgress.isDone()
    /// The list is up, not a race: Game Center's friends prompt only opens over the list.
    @State private var onScreen = false
    /// The locked circuit tapped, while the unlock's screen is up.
    @State private var unlocking: String? = Self.launchUnlock

    /// A screen with room for every circuit at once, three to a row at a phone's card size (an iPad), shows them that
    /// way, the whole list drawn bigger to fill it. A phone's cards scroll sideways instead, as tall as its screen.
    private static let gridColumns = 3
    private static let gridCard = CGSize(width: 250, height: 290)
    /// The grid's list at its own size, the top bar and margins included: the room a screen needs for it.
    private static let gridSize = CGSize(width: 820, height: 720)
    /// The tallest the sideways row's cards grow: more than any phone gives them (a Pro Max, about 314).
    private static let rowHeight: CGFloat = 330

    var body: some View {
        ZStack {
            MowedGrass().ignoresSafeArea()
            GeometryReader { geometry in
                let size = geometry.size
                if size.width >= Self.gridSize.width && size.height >= Self.gridSize.height {
                    let scale = min(size.width / Self.gridSize.width, size.height / Self.gridSize.height)
                    VStack(spacing: 14) {
                        header
                        grid
                    }
                    .frame(width: size.width / scale, height: size.height / scale)
                    .scaleEffect(scale)
                    .frame(width: size.width, height: size.height)
                } else {
                    VStack(spacing: 14) {
                        header
                        // On a screen taller than a phone's but too short for the grid (an iPhone Duo, open), the cards
                        // keep a phone's height, in the middle of what's left, rather than stretching.
                        row
                            .frame(maxHeight: Self.rowHeight)
                            .frame(maxHeight: .infinity)
                    }
                    .padding(.vertical, 12)
                }
            }
            .foregroundStyle(.white)

            if showsColors {
                Color.black.opacity(0.45).ignoresSafeArea()
                LiveryPicker(livery: Livery.shared, onDone: { showsColors = false })
            }
            if let unlocking {
                UnlockView(purchases: purchases, circuit: unlocking,
                           onRace: { id in
                               self.unlocking = nil
                               onSelect(id)
                           },
                           onClose: { self.unlocking = nil })
            }
        }
        .onAppear {
            bests = Dictionary(uniqueKeysWithValues: TrackCatalog.tracks.compactMap { track in
                LapStore.load(for: track).map { (track.layout.id, $0.time) }
            })
            schoolDone = SchoolProgress.isDone()
            onScreen = true
            askForFriends()
            #if DEBUG
            // The track list's App Store moments: up once the unlock's threads have laid out.
            if StoreCapture.isActive { StoreCapture.ready(after: 2.5) }
            #endif
        }
        .onDisappear { onScreen = false }
        // Sign-in usually finishes after the list is up.
        .onReceive(NotificationCenter.default.publisher(for: GameCenter.authenticationChanged)) { _ in askForFriends() }
    }

    /// Apex School, the title and COLORS, and how to play.
    private var header: some View {
        VStack(spacing: 6) {
            // Apex School, the title and COLORS share the top bar, so on a small phone none sits on another.
            HStack(alignment: .top, spacing: 12) {
                SchoolButton(done: schoolDone) { onSelect(TrackCatalog.school.layout.id) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                GhostThreadLogo()
                Button {
                    showsColors = true
                } label: {
                    Label("COLORS", systemImage: "paintpalette.fill")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            Text("Hold to steer up. Let go to steer down. Straight is fast.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.85)
        }
    }

    /// More circuits than fit across a phone: they scroll sideways, a card at a time.
    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(TrackCatalog.tracks, id: \.layout.id) { track in
                    card(track).frame(width: 250)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    /// Every circuit at once, three to a row.
    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(Self.gridCard.width), spacing: 14), count: Self.gridColumns)
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(TrackCatalog.tracks, id: \.layout.id) { track in
                card(track).frame(width: Self.gridCard.width, height: Self.gridCard.height)
            }
        }
    }

    /// A circuit's card: a tap races it, or offers the unlock if it's locked.
    private func card(_ track: Track) -> some View {
        let id = track.layout.id
        return Button {
            if purchases.isLocked(id) { unlocking = id } else { onSelect(id) }
        } label: {
            TrackCard(track: track, best: bests[id], locked: purchases.isLocked(id))
        }
        .buttonStyle(.plain)
    }

    /// Launch with `-ApexUnlockScreen swirl` (Xcode builds) to open on the unlock's screen, as if that circuit had been
    /// tapped.
    private static var launchUnlock: String? {
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "ApexUnlockScreen"), TrackLayout.named(id) != nil { return id }
        #endif
        return nil
    }

    /// Asks for the friends list if the player hasn't answered, so their friends can race their laps.
    private func askForFriends() {
        GameCenter.shared.askForFriends { onScreen && unlocking == nil }
    }
}

/// Apex School, top left of the menu: yellow and marked START HERE until it's been graduated or skipped, then as quiet
/// as the COLORS button.
struct SchoolButton: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Side by side where there's room; on a narrow phone, START HERE goes under the name.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { name; tag }
                VStack(alignment: .leading, spacing: 4) { name; tag }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(done ? AnyShapeStyle(.black.opacity(0.45)) : AnyShapeStyle(Color.schoolYellow),
                        in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(done ? .white : .black)
        }
    }

    private var name: some View {
        Label("APEX SCHOOL", systemImage: "graduationcap.fill")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .fixedSize()
    }

    @ViewBuilder private var tag: some View {
        if !done {
            Text("START HERE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black, in: Capsule())
                .foregroundStyle(Color.schoolYellow)
                .fixedSize()
        }
    }
}

/// One circuit on the menu: its shape, name, character, your best lap there and its medal, and the next medal to chase;
/// or, without the unlock, a padlock.
struct TrackCard: View {
    let track: Track
    let best: Double?
    var locked = false

    private var corners: Int {
        track.layout.segments.filter { if case .corner = $0 { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackOutline(track: track)
                .frame(height: 104)
                .frame(maxWidth: .infinity)
            Text(track.layout.name.uppercased())
                .font(.system(size: 20, weight: .heavy, design: .rounded).italic())
            Text("\(corners) corners · \(track.turning > 0 ? "counterclockwise" : "clockwise")")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .opacity(0.65)
            Text(track.layout.summary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .opacity(0.85)
                .lineLimit(3, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if locked {
                HStack(spacing: 6) {
                    Label("UNLOCK EVERY CIRCUIT", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(GhostThreadLogo.lineColor)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).opacity(0.6)
                }
                .frame(height: 22)
            } else {
                bestRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var bestRow: some View {
        HStack(spacing: 6) {
            Text("BEST").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
            if let best {
                Text(LapFormat.time(best))
                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(red: 0.75, green: 0.5, blue: 1))
                if let medal = Medal.earned(by: best, on: track.layout) { MedalIcon(medal: medal) }
            } else {
                Text("No lap yet").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.6)
            }
            Spacer()
            if let next = Medal.next(after: best, on: track.layout) {
                NextMedalLabel(medal: next.medal, target: next.target)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).opacity(0.6)
        }
    }
}

/// A circuit's shape, north up, with the start/finish line marked.
struct TrackOutline: View {
    let track: Track
    /// The line's width; its glow and the start/finish dot are three times it.
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let bounds = track.bounds
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let inset = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
            func map(_ i: Int) -> CGPoint {
                CGPoint(x: inset.x + (track.x[i] - bounds.minX) * scale,
                        y: inset.y + (bounds.maxY - track.y[i]) * scale)
            }
            var path = Path()
            path.addLines(stride(from: 0, to: track.count, by: 20).map(map))
            path.closeSubpath()
            let glow = lineWidth * 3
            context.stroke(path, with: .color(.white.opacity(0.25)),
                           style: StrokeStyle(lineWidth: glow, lineJoin: .round))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            let start = map(0)
            let dot = CGRect(x: start.x - glow / 2, y: start.y - glow / 2, width: glow, height: glow)
            context.fill(Path(ellipseIn: dot), with: .color(Color(red: 0.95, green: 0.15, blue: 0.1)))
        }
        .accessibilityHidden(true)
    }
}

/// Mown grass stripes, like the trackside in the race.
struct MowedGrass: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.29, green: 0.50, blue: 0.25)))
            let width: CGFloat = 70
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: 0))
                stripe.addLine(to: CGPoint(x: x + width, y: 0))
                stripe.addLine(to: CGPoint(x: x + width - size.height * 0.36, y: size.height))
                stripe.addLine(to: CGPoint(x: x - size.height * 0.36, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(Color(red: 0.33, green: 0.56, blue: 0.28)))
                x += width * 2
            }
        }
    }
}

