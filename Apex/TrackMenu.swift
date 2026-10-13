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

    var body: some View {
        ZStack {
            MowedGrass().ignoresSafeArea()
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("APEX RIVALS")
                        .font(.system(size: 34, weight: .black, design: .rounded).italic())
                    KerbStripe().frame(width: 200, height: 6)
                    Text("Hold to steer up. Let go to steer down. Straight is fast.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
                // More circuits than fit across the screen: they scroll sideways, a card at a time.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        Button {
                            onSelect(TrackCatalog.school.layout.id)
                        } label: {
                            TrackCard(track: TrackCatalog.school, best: bests[TrackCatalog.school.layout.id],
                                      practice: true)
                                .frame(width: 250)
                        }
                        .buttonStyle(.plain)
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

            Button {
                showsColors = true
            } label: {
                Label("COLORS", systemImage: "paintpalette.fill")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showsColors {
                Color.black.opacity(0.45).ignoresSafeArea()
                LiveryPicker(livery: Livery.shared, onDone: { showsColors = false })
            }
        }
        .onAppear {
            bests = Dictionary(uniqueKeysWithValues: ([TrackCatalog.school] + TrackCatalog.tracks).compactMap { track in
                LapStore.load(for: track).map { (track.layout.id, $0.time) }
            })
        }
    }
}

/// One circuit on the menu: its shape, name, character, and your best lap there.
struct TrackCard: View {
    let track: Track
    let best: Double?
    /// Apex School: marked as practice, with a yellow edge.
    var practice = false

    private var corners: Int {
        track.layout.segments.filter { if case .corner = $0 { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackOutline(track: track)
                .frame(height: 104)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Text(track.layout.name.uppercased())
                    .font(.system(size: 20, weight: .heavy, design: .rounded).italic())
                if practice {
                    Text("PRACTICE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 1, green: 0.82, blue: 0.1), in: Capsule())
                }
            }
            Text(practice ? "4 identical corners · learn the line"
                          : "\(corners) corners · \(track.turning > 0 ? "anticlockwise" : "clockwise")")
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
                } else {
                    Text("No lap yet").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.6)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).opacity(0.6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if practice {
                RoundedRectangle(cornerRadius: 16).stroke(Color(red: 1, green: 0.82, blue: 0.1), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A circuit's shape, north up, with the start/finish line marked.
struct TrackOutline: View {
    let track: Track

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
            context.stroke(path, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 9, lineJoin: .round))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            let start = map(0)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 4.5, y: start.y - 4.5, width: 9, height: 9)),
                         with: .color(Color(red: 0.95, green: 0.15, blue: 0.1)))
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

/// A run of red and white kerb blocks.
struct KerbStripe: View {
    var body: some View {
        Canvas { context, size in
            let block: CGFloat = 12
            var x: CGFloat = 0
            var red = true
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: min(block, size.width - x), height: size.height)),
                             with: .color(red ? Color(red: 0.86, green: 0.13, blue: 0.13) : .white))
                x += block
                red.toggle()
            }
        }
    }
}
