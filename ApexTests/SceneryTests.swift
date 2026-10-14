import CoreGraphics
import Foundation
import Testing
@testable import Apex

struct SceneryTests {
    static let ids = TrackLayout.all.map(\.id) + [TrackLayout.apexSchool.id]
    static let tracks = Dictionary(uniqueKeysWithValues: (TrackLayout.all + [.apexSchool]).map { ($0.id, Track($0)) })

    /// Distances to a centerline, checked against every sample near the point (its own simple grid, independent of
    /// the game's).
    struct Nearest {
        let cell = 100.0
        var buckets: [String: [CGPoint]] = [:]

        init(_ track: Track) {
            for i in 0..<track.count {
                let p = CGPoint(x: track.x[i], y: track.y[i])
                buckets["\(Int(floor(p.x / cell))),\(Int(floor(p.y / cell)))", default: []].append(p)
            }
        }

        /// Exact to within the sample spacing, for anything closer than 200.
        func distance(_ p: CGPoint) -> Double {
            let i0 = Int(floor(p.x / cell)), j0 = Int(floor(p.y / cell))
            var best = Double.infinity
            for i in (i0 - 2)...(i0 + 2) {
                for j in (j0 - 2)...(j0 + 2) {
                    for q in buckets["\(i),\(j)"] ?? [] { best = min(best, hypot(q.x - p.x, q.y - p.y)) }
                }
            }
            return best
        }
    }

    @Test(arguments: ids) func nothingIsPlacedOnTheTrack(id: String) {
        let track = Self.tracks[id]!
        let nearest = Nearest(track)
        let half = track.width / 2
        for item in Scenery.layout(for: track) {
            let d = nearest.distance(item.position)
            switch item.kind {
            case .tree:
                #expect(d - item.size >= half + 3 + 10, "\(id): a tree at \(item.position) is \(d) from the centerline")
            case .tires:
                #expect(d >= half + 3 + item.size - 2, "\(id): a tire stack at \(item.position) is \(d) from the centerline")
            case .grandstand:
                #expect(d >= half + 3 + RaceTuning.grandstandGap + RaceTuning.grandstandDepth / 2 - 4,
                        "\(id): a grandstand at \(item.position) is \(d) from the centerline")
            }
        }
    }

    @Test(arguments: ids) func everyCircuitHasTreesAndAGrandstand(id: String) {
        let items = Scenery.layout(for: Self.tracks[id]!)
        let trees = items.filter { if case .tree = $0.kind { return true } else { return false } }.count
        let stands = items.filter { $0.kind == .grandstand }.count
        #expect(trees > 150, "\(id): \(trees) trees")
        #expect(stands >= 1, "\(id): no grandstand")
    }

    @Test func theSameEveryTime() {
        let track = Self.tracks["ardennes"]!
        #expect(Scenery.layout(for: track) == Scenery.layout(for: track))
    }
}
