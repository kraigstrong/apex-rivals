import SpriteKit
import UIKit

/// The world around a circuit: groves of trees, grandstands full of fans beside the start/finish straight and the
/// tightest corner, and tire walls outside the hairpins. It's placed from the circuit's shape, the same every time, and
/// kept clear of the track everywhere, including where the track passes close to itself. Only how the race looks:
/// nothing here touches the car.
enum Scenery {
    enum Kind: Equatable {
        case tree(variant: Int)
        case grandstand
        case tires(red: Bool)
    }

    struct Item: Equatable {
        var kind: Kind
        var position: CGPoint
        /// Grandstands and tires lie along the track; trees don't turn.
        var rotation: Double
        /// A tree's canopy radius, a grandstand's length, a tire stack's radius.
        var size: Double
    }

    /// Trees start this far beyond the wall...
    static let treeClearance = 40.0
    /// ...and grow up to this far from it, about as far as the camera sees.
    static let treeReach = 470.0
    static let treeSpacing = 62.0
    static let grandstandDepth = 76.0
    /// A gap between the wall and a grandstand's front.
    static let grandstandGap = 26.0
    /// Corners tighter than this radius get a tire wall on the outside.
    static let tireWallRadius = 330.0
    static let tireRadius = 7.5

    // MARK: Placing

    static func layout(for track: Track) -> [Item] {
        let clearance = Clearance(track: track)
        var random = SplitMix64(seed: UInt64(LapStore.fingerprint("scenery|" + track.layout.id), radix: 16) ?? 1)
        var items = grandstands(track, clearance)
        items += tireWalls(track, clearance)
        items += trees(track, clearance, avoiding: items, random: &random)
        return items
    }

    /// One along the start/finish straight, on whichever side has room, and one outside the tightest corner.
    private static func grandstands(_ track: Track, _ clearance: Clearance) -> [Item] {
        var found: [Item] = []
        let half = track.width / 2
        func fits(center s: Double, side: Double, length: Double) -> Item? {
            let n = side * (half + 3 + grandstandGap + grandstandDepth / 2)
            let center = track.point(s: s, n: n)
            let heading = track.heading(at: s)
            // Every corner and edge midpoint of the stand must be clear of the track, and of any stand already placed.
            let along = CGVector(dx: cos(heading), dy: sin(heading)), across = CGVector(dx: -sin(heading), dy: cos(heading))
            for u in stride(from: -0.5, through: 0.5, by: 0.125) {
                for v in [-0.5, 0.0, 0.5] {
                    let p = CGPoint(x: center.x + along.dx * length * u + across.dx * grandstandDepth * v,
                                    y: center.y + along.dy * length * u + across.dy * grandstandDepth * v)
                    if !clearance.isClear(p, by: half + 3 + grandstandGap - 2) { return nil }
                    if found.contains(where: { hypot($0.position.x - p.x, $0.position.y - p.y) < $0.size / 2 + 60 }) {
                        return nil
                    }
                }
            }
            // Laid along the track with the roof away from it: on the right-hand side, turned round.
            return Item(kind: .grandstand, position: center, rotation: heading + (side > 0 ? 0 : .pi), size: length)
        }
        // Beside the start line, the longest stand that fits on either side.
        start: for length in [560.0, 440.0, 320.0] {
            for side in [1.0, -1.0] {
                if let stand = fits(center: track.wrap(-length / 2 + 120), side: side, length: length) {
                    found.append(stand)
                    break start
                }
            }
        }
        // Outside the tightest corner, facing the apex.
        if let tightest = (0..<track.count).max(by: { abs(track.curvature[$0]) < abs(track.curvature[$1]) }) {
            let s = Double(tightest) * track.spacing
            let outside: Double = track.curvature[tightest] > 0 ? -1 : 1
            for length in [360.0, 260.0] {
                if let stand = fits(center: s, side: outside, length: length) {
                    found.append(stand)
                    break
                }
            }
        }
        return found
    }

    /// Stacks of tires just outside the wall wherever a corner is tight, red and white like the curbs.
    private static func tireWalls(_ track: Track, _ clearance: Clearance) -> [Item] {
        var items: [Item] = []
        let half = track.width / 2
        let step = tireRadius * 2.1
        let offset = half + 3 + tireRadius + 3
        var s = 0.0, count = 0
        while s < track.length {
            let k = track.curvature(at: s)
            if abs(k) > 1 / tireWallRadius {
                let side: Double = k > 0 ? -1 : 1
                let p = track.point(s: s, n: side * offset)
                if clearance.isClear(p, by: offset - 1) {
                    items.append(Item(kind: .tires(red: count % 2 == 0), position: p, rotation: track.heading(at: s),
                                      size: tireRadius))
                    count += 1
                }
            }
            s += step
        }
        return items
    }

    /// Groves of trees in the grass beside the track, thinning into clearings, never on the track or a stand.
    private static func trees(_ track: Track, _ clearance: Clearance, avoiding placed: [Item],
                              random: inout SplitMix64) -> [Item] {
        let half = track.width / 2
        var trees: [Item] = []
        var taken = SpatialHash(cell: treeSpacing * 1.5)
        let seed = Double(random.next() % 10_000)
        for s in stride(from: 0.0, to: track.length, by: treeSpacing) {
            for side in [1.0, -1.0] {
                for n in stride(from: half + 3 + treeClearance, through: half + treeReach, by: treeSpacing) {
                    let jitter = CGVector(dx: (random.unit() - 0.5) * treeSpacing * 0.8,
                                          dy: (random.unit() - 0.5) * treeSpacing * 0.8)
                    let base = track.point(s: s, n: side * n)
                    let p = CGPoint(x: base.x + jitter.dx, y: base.y + jitter.dy)
                    // Groves: thick where the noise is high, open grass where it's low.
                    guard groveNoise(p, seed: seed) > 0.44 else { continue }
                    let radius = 20 + random.unit() * 18
                    guard clearance.isClear(p, by: half + 3 + 14 + radius) else { continue }
                    guard !taken.any(near: p, within: radius + 26) else { continue }
                    guard !placed.contains(where: { overlaps($0, p, radius: radius) }) else { continue }
                    trees.append(Item(kind: .tree(variant: Int(random.next() % 3)), position: p, rotation: 0, size: radius))
                    taken.insert(p)
                }
            }
        }
        return trees
    }

    private static func overlaps(_ item: Item, _ p: CGPoint, radius: Double) -> Bool {
        let d = hypot(item.position.x - p.x, item.position.y - p.y)
        switch item.kind {
        case .grandstand: return d < item.size / 2 + radius + 10
        case .tires: return d < item.size + radius + 6
        case .tree: return d < item.size + radius
        }
    }

    /// Smooth value noise, about 0...1, varying over a few hundred units.
    static func groveNoise(_ p: CGPoint, seed: Double) -> Double {
        let scale = 340.0
        let x = p.x / scale + seed, y = p.y / scale - seed
        let x0 = floor(x), y0 = floor(y)
        func lattice(_ i: Double, _ j: Double) -> Double {
            let h = sin(i * 127.1 + j * 311.7) * 43758.5453
            return h - floor(h)
        }
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let u = smooth(x - x0), v = smooth(y - y0)
        let a = lattice(x0, y0), b = lattice(x0 + 1, y0), c = lattice(x0, y0 + 1), d = lattice(x0 + 1, y0 + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }

    // MARK: Drawing

    /// The scenery as pieces the scene can cull like the track's: one per patch of ground.
    static func pieces(for track: Track) -> [TrackPiece] {
        let items = layout(for: track)
        let atlas = SKTextureAtlas(dictionary: [
            "tree0": treeImage(variant: 0), "tree1": treeImage(variant: 1), "tree2": treeImage(variant: 2),
            "tiresRed": tireImage(red: true), "tiresWhite": tireImage(red: false),
        ])
        let patch = 700.0
        var nodes: [String: SKNode] = [:]
        for item in items {
            let key = "\(Int(floor(item.position.x / patch))),\(Int(floor(item.position.y / patch)))"
            let parent = nodes[key] ?? SKNode()
            nodes[key] = parent
            let sprite: SKSpriteNode
            switch item.kind {
            case .tree(let variant):
                sprite = SKSpriteNode(texture: atlas.textureNamed("tree\(variant)"))
                // The texture leaves room around the canopy for its shadow.
                sprite.size = CGSize(width: item.size * 2 * treeTextureSpan, height: item.size * 2 * treeTextureSpan)
                sprite.zPosition = TrackArt.Depth.scenery
            case .tires(let red):
                sprite = SKSpriteNode(texture: atlas.textureNamed(red ? "tiresRed" : "tiresWhite"))
                sprite.size = CGSize(width: item.size * 2.4, height: item.size * 2.4)
                sprite.zPosition = TrackArt.Depth.tires
            case .grandstand:
                let image = grandstandImage(length: item.size, seed: UInt64(abs(item.position.x * 7 + item.position.y)))
                sprite = SKSpriteNode(texture: SKTexture(image: image))
                sprite.size = CGSize(width: item.size + 24, height: grandstandDepth + 24)
                sprite.zPosition = TrackArt.Depth.scenery
            }
            sprite.position = item.position
            sprite.zRotation = CGFloat(item.rotation)
            parent.addChild(sprite)
        }
        return nodes.values.map { TrackPiece(node: $0, frame: $0.calculateAccumulatedFrame()) }
    }

    /// A tree texture is this many canopy-widths across: room for the shadow cast down and to the right.
    private static let treeTextureSpan = 1.4

    private static func treeImage(variant: Int) -> UIImage {
        let size = CGSize(width: 140, height: 140)
        let shades: [(UIColor, UIColor, UIColor)] = [
            (UIColor(red: 0.15, green: 0.36, blue: 0.17, alpha: 1), UIColor(red: 0.21, green: 0.45, blue: 0.22, alpha: 1),
             UIColor(red: 0.30, green: 0.56, blue: 0.28, alpha: 1)),
            (UIColor(red: 0.18, green: 0.40, blue: 0.16, alpha: 1), UIColor(red: 0.26, green: 0.50, blue: 0.20, alpha: 1),
             UIColor(red: 0.38, green: 0.62, blue: 0.27, alpha: 1)),
            (UIColor(red: 0.13, green: 0.32, blue: 0.20, alpha: 1), UIColor(red: 0.18, green: 0.41, blue: 0.25, alpha: 1),
             UIColor(red: 0.26, green: 0.50, blue: 0.31, alpha: 1)),
        ]
        let (dark, mid, light) = shades[variant % shades.count]
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let r = size.width / 2 / treeTextureSpan, c = CGPoint(x: size.width / 2, y: size.height / 2)
            // A canopy of overlapping puffs, so it isn't a perfect circle.
            let puffs: [(CGFloat, CGFloat, CGFloat)] = variant == 1
                ? [(0, 0, 1), (-0.35, -0.3, 0.62), (0.4, -0.2, 0.6), (0.1, 0.42, 0.6)]
                : [(0, 0, 1), (-0.42, 0.18, 0.6), (0.3, -0.38, 0.62), (0.36, 0.3, 0.58), (-0.2, -0.42, 0.55)]
            func canopy(_ dx: CGFloat, _ dy: CGFloat, _ scale: CGFloat) {
                for (px, py, pr) in puffs {
                    let rr = r * 0.62 * pr * scale
                    cg.addEllipse(in: CGRect(x: c.x + dx + px * r * 0.5 - rr, y: c.y + dy + py * r * 0.5 - rr,
                                             width: rr * 2, height: rr * 2))
                }
            }
            // Shadow, down and to the right.
            cg.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            canopy(r * 0.22, r * 0.26, 1.02)
            cg.fillPath()
            cg.setFillColor(dark.cgColor)
            canopy(0, 0, 1)
            cg.fillPath()
            cg.setFillColor(mid.cgColor)
            canopy(-r * 0.08, -r * 0.1, 0.78)
            cg.fillPath()
            cg.setFillColor(light.cgColor)
            canopy(-r * 0.2, -r * 0.24, 0.42)
            cg.fillPath()
        }
    }

    private static func tireImage(red: Bool) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let c = CGPoint(x: 20, y: 20)
            func disc(_ r: CGFloat, _ color: UIColor, dx: CGFloat = 0, dy: CGFloat = 0) {
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: c.x - r + dx, y: c.y - r + dy, width: r * 2, height: r * 2))
            }
            disc(14.5, UIColor(white: 0, alpha: 0.2), dx: 2.5, dy: 3)
            disc(14.5, UIColor(white: 0.12, alpha: 1))
            // Mostly black, with a thin painted band, so it reads as a barrier rather than more curb.
            cg.setStrokeColor((red ? TrackArt.curbRed : TrackArt.curbWhite).withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(2.5)
            cg.strokeEllipse(in: CGRect(x: c.x - 9.5, y: c.y - 9.5, width: 19, height: 19))
            disc(5, UIColor(white: 0.05, alpha: 1))
        }
    }

    /// Rows of fans in every color, a roof along the back, and a low white wall at the front. Seen from above, with the
    /// front (the track side) along the bottom edge of the image, which becomes the left of the stand as it's laid down.
    private static func grandstandImage(length: Double, seed: UInt64) -> UIImage {
        var random = SplitMix64(seed: seed)
        let k = 2.0
        let size = CGSize(width: (length + 24) * k, height: (grandstandDepth + 24) * k)
        let body = CGRect(x: 12 * k, y: 12 * k, width: length * k, height: grandstandDepth * k)
        let fans: [UIColor] = [
            UIColor(red: 0.95, green: 0.30, blue: 0.28, alpha: 1), UIColor(red: 1, green: 0.80, blue: 0.20, alpha: 1),
            UIColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1), UIColor(white: 0.96, alpha: 1),
            UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1), UIColor(red: 0.45, green: 0.80, blue: 0.45, alpha: 1),
            UIColor(red: 0.85, green: 0.45, blue: 0.85, alpha: 1),
        ]
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            cg.fill(body.offsetBy(dx: 7 * k, dy: 9 * k))
            // Seats.
            cg.setFillColor(UIColor(red: 0.24, green: 0.29, blue: 0.40, alpha: 1).cgColor)
            cg.fill(body)
            // Fans: rows across the stand, most seats full.
            let rows = 7, roof = body.height * 0.22, front = body.height * 0.1
            let rowHeight = (body.height - roof - front) / CGFloat(rows)
            let spacing = 8 * k
            for row in 0..<rows {
                let y = body.minY + roof + rowHeight * (CGFloat(row) + 0.5)
                var x = body.minX + spacing * (row % 2 == 0 ? 0.5 : 1)
                while x < body.maxX - spacing * 0.4 {
                    if random.unit() < 0.88 {
                        let color = fans[Int(random.next() % UInt64(fans.count))]
                        cg.setFillColor(color.cgColor)
                        let r = 2.7 * k
                        cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    x += spacing
                }
            }
            // Roof along the back (top of the image), and the low wall at the front.
            cg.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
            cg.fill(CGRect(x: body.minX, y: body.minY, width: body.width, height: roof))
            cg.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
            cg.fill(CGRect(x: body.minX, y: body.minY + roof - 2 * k, width: body.width, height: 2 * k))
            cg.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            cg.fill(CGRect(x: body.minX, y: body.maxY - front, width: body.width, height: front))
        }
    }
}

/// How far a point is from the nearest part of a circuit's centerline, from a grid of its samples.
struct Clearance {
    private let cell = 80.0
    private var grid: [Int: [CGPoint]] = [:]

    init(track: Track) {
        for i in stride(from: 0, to: track.count, by: 3) {
            let p = CGPoint(x: track.x[i], y: track.y[i])
            grid[key(p), default: []].append(p)
        }
    }

    private func key(_ p: CGPoint) -> Int { key(Int(floor(p.x / cell)), Int(floor(p.y / cell))) }
    private func key(_ i: Int, _ j: Int) -> Int { (i & 0xFFFF) << 16 | (j & 0xFFFF) }

    /// Whether no part of the centerline comes within `distance` of `p`.
    func isClear(_ p: CGPoint, by distance: Double) -> Bool {
        let i0 = Int(floor(p.x / cell)), j0 = Int(floor(p.y / cell)), reach = Int((distance / cell).rounded(.up))
        for i in (i0 - reach)...(i0 + reach) {
            for j in (j0 - reach)...(j0 + reach) {
                for q in grid[key(i, j)] ?? [] where hypot(q.x - p.x, q.y - p.y) < distance { return false }
            }
        }
        return true
    }
}

/// Points already taken, for checking a new one keeps its distance.
private struct SpatialHash {
    let cell: Double
    private var grid: [Int: [CGPoint]] = [:]

    init(cell: Double) { self.cell = cell }

    private func key(_ i: Int, _ j: Int) -> Int { (i & 0xFFFF) << 16 | (j & 0xFFFF) }

    mutating func insert(_ p: CGPoint) {
        grid[key(Int(floor(p.x / cell)), Int(floor(p.y / cell))), default: []].append(p)
    }

    func any(near p: CGPoint, within distance: Double) -> Bool {
        let i0 = Int(floor(p.x / cell)), j0 = Int(floor(p.y / cell)), reach = Int((distance / cell).rounded(.up))
        for i in (i0 - reach)...(i0 + reach) {
            for j in (j0 - reach)...(j0 + reach) where (grid[key(i, j)] ?? []).contains(where: { hypot($0.x - p.x, $0.y - p.y) < distance }) {
                return true
            }
        }
        return false
    }
}
