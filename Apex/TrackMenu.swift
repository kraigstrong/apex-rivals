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

/// The main menu: pick a circuit.
struct TrackMenu: View {
    let onSelect: (String) -> Void
    /// Each circuit's saved best lap, read whenever the menu appears.
    @State private var bests: [String: Double] = [:]
    @State private var showsColors = false
    /// Apex School has been graduated or skipped, so it no longer needs pointing out.
    @State private var schoolDone = SchoolProgress.isDone()

    var body: some View {
        ZStack {
            MowedGrass().ignoresSafeArea()
            VStack(spacing: 14) {
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
                    .padding(.top, -8)
                // More circuits than fit across the screen: they scroll sideways, a card at a time.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(TrackCatalog.tracks, id: \.layout.id) { track in
                            Button {
                                onSelect(track.layout.id)
                            } label: {
                                TrackCard(track: track, best: bests[track.layout.id])
                                    .frame(width: 250)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
            .padding(.vertical, 12)
            .foregroundStyle(.white)

            if showsColors {
                Color.black.opacity(0.45).ignoresSafeArea()
                LiveryPicker(livery: Livery.shared, onDone: { showsColors = false })
            }
        }
        .onAppear {
            bests = Dictionary(uniqueKeysWithValues: TrackCatalog.tracks.compactMap { track in
                LapStore.load(for: track).map { (track.layout.id, $0.time) }
            })
            schoolDone = SchoolProgress.isDone()
        }
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

/// One circuit on the menu: its shape, name, character, your best lap there and its medal, and the next medal to chase.
struct TrackCard: View {
    let track: Track
    let best: Double?

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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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

