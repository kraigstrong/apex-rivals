import Foundation

/// One piece of a circuit: a straight, or a corner of constant radius turning left (positive degrees) or right.
enum TrackSegment: Equatable {
    case straight(Double)
    case corner(radius: Double, degrees: Double)
}

/// A circuit described as the pieces you'd drive, in order. `Track` turns it into geometry.
///
/// The circuits were sketched as track maps (a polygon of corner points, each rounded with its own radius) and
/// exported to segments; the corner angles are what the sketch's turns came to.
struct TrackLayout {
    /// A stable name for saves and leaderboards. Never change it once the circuit is released.
    var id: String
    /// Bump when a released circuit's shape changes: lap times on the old shape don't compare (`RaceBoard`).
    var revision: Int
    var name: String
    /// A line for the track list: what kind of driving the circuit asks for.
    var summary: String
    /// The direction (degrees, counterclockwise from east) the first segment runs, so the circuit sits on the map the
    /// way it was drawn. It turns the whole circuit and changes nothing about how it drives.
    var startHeading: Double = 0
    var segments: [TrackSegment]
    /// Two straights running in different directions. Their lengths are solved so the circuit closes exactly, so the
    /// other pieces can be tuned freely.
    var closingStraights: (Int, Int)
    /// The start/finish line's distance into the first segment.
    var startLine: Double
    /// Sector 1 ends where the first of these segments starts, sector 2 where the second does.
    var sectorStarts: [Int]

    /// A short fingerprint of the layout's shape, for keeping best laps per circuit.
    var signature: String {
        let pieces = segments.map { segment -> String in
            switch segment {
            case .straight(let length): return "S\(length)"
            case .corner(let radius, let degrees): return "C\(radius),\(degrees)"
            }
        }
        return pieces.joined(separator: ";") + "|\(closingStraights.0),\(closingStraights.1)|\(startLine)"
    }
}

extension TrackLayout {
    /// Every circuit, in the track list's order. The lap service only accepts these boards (BrightBench's
    /// `apexBoards`), so add a new circuit's board there before it ships.
    static let all: [TrackLayout] = [.ardennes, .swirl, .snake, .mirage, .island, .harbor]

    static func named(_ id: String) -> TrackLayout? { all.first { $0.id == id } }

    /// Long and flowing: a hairpin, a plunging left-right-left, a long straight to a twisty far end, and a fast sweep home. Clockwise.
    static let ardennes = TrackLayout(
        id: "ardennes",
        revision: 1,
        name: "Ardennes",
        summary: "Long and flowing: a hairpin, a plunging left-right-left, a long straight to a twisty far end, and a fast sweep home.",
        startHeading: 88.6,
        segments: [
            .straight(1552),                            // 0
            .corner(radius: 120, degrees: -101.17),     // 1
            .straight(203),                             // 2
            .corner(radius: 120, degrees: -41.61),      // 3
            .straight(950),                             // 4
            .corner(radius: 300, degrees: 9.14),        // 5
            .straight(175),                             // 6
            .corner(radius: 240, degrees: 59.04),       // 7
            .straight(147),                             // 8
            .corner(radius: 420, degrees: 11.52),       // 9
            .straight(1885),                            // 10
            .corner(radius: 150, degrees: -59.25),      // 11
            .straight(164),                             // 12
            .corner(radius: 150, degrees: -26.57),      // 13
            .straight(434),                             // 14
            .corner(radius: 220, degrees: -74.74),      // 15
            .straight(333),                             // 16
            .corner(radius: 300, degrees: 59.04),       // 17
            .straight(376),                             // 18
            .corner(radius: 380, degrees: 30.96),       // 19
            .straight(59),                              // 20
            .corner(radius: 260, degrees: -113.2),      // 21
            .straight(393),                             // 22
            .corner(radius: 260, degrees: -27.51),      // 23
            .straight(1466),                            // 24
            .corner(radius: 800, degrees: -8.33),       // 25
            .straight(880),                             // 26
            .corner(radius: 140, degrees: -30.96),      // 27
            .straight(274),                             // 28
            .corner(radius: 140, degrees: 18.43),       // 29
            .straight(342),                             // 30
            .corner(radius: 260, degrees: -64.79),      // 31
        ],
        closingStraights: (10, 0),
        startLine: 543,
        sectorStarts: [11, 23]
    )

    /// A hairpin at the top of the hill, esses across the top, a stadium section and a three-apex swirl. Counterclockwise.
    static let swirl = TrackLayout(
        id: "swirl",
        revision: 1,
        name: "Swirl",
        summary: "A hairpin at the top of the hill, esses across the top, a stadium section and a three-apex swirl.",
        startHeading: 85.8,
        segments: [
            .straight(2590),                            // 0
            .corner(radius: 125, degrees: 94.21),       // 1
            .straight(262),                             // 2
            .corner(radius: 125, degrees: 24.44),       // 3
            .straight(593),                             // 4
            .corner(radius: 280, degrees: -54.26),      // 5
            .straight(181),                             // 6
            .corner(radius: 280, degrees: 76.7),        // 7
            .straight(200),                             // 8
            .corner(radius: 280, degrees: -48.04),      // 9
            .straight(742),                             // 10
            .corner(radius: 220, degrees: 44.45),       // 11
            .straight(693),                             // 12
            .corner(radius: 125, degrees: 103.01),      // 13
            .straight(231),                             // 14
            .corner(radius: 125, degrees: 31.48),       // 15
            .straight(1303),                            // 16
            .corner(radius: 600, degrees: 2.21),        // 17
            .straight(734),                             // 18
            .corner(radius: 150, degrees: -68.2),       // 19
            .straight(246),                             // 20
            .corner(radius: 150, degrees: -72),         // 21
            .straight(497),                             // 22
            .corner(radius: 220, degrees: 28.39),       // 23
            .straight(206),                             // 24
            .corner(radius: 240, degrees: 78.11),       // 25
            .straight(330),                             // 26
            .corner(radius: 240, degrees: 39.4),        // 27
            .straight(597),                             // 28
            .corner(radius: 200, degrees: 80.1),        // 29
        ],
        closingStraights: (0, 16),
        startLine: 906,
        sectorStarts: [10, 19]
    )

    /// A double right into esses up the hill, a hairpin, a fast sweep and a chicane. Counterclockwise.
    static let snake = TrackLayout(
        id: "snake",
        revision: 1,
        name: "Snake",
        summary: "A double right into esses up the hill, a hairpin, a fast sweep and a chicane.",
        startHeading: 0.0,
        segments: [
            .straight(2646),                            // 0
            .corner(radius: 300, degrees: 39.81),       // 1
            .straight(409),                             // 2
            .corner(radius: 200, degrees: 40.3),        // 3
            .straight(307),                             // 4
            .corner(radius: 230, degrees: 73.49),       // 5
            .straight(101),                             // 6
            .corner(radius: 230, degrees: -96.14),      // 7
            .straight(132),                             // 8
            .corner(radius: 230, degrees: 62.96),       // 9
            .straight(606),                             // 10
            .corner(radius: 240, degrees: 51.99),       // 11
            .straight(989),                             // 12
            .corner(radius: 900, degrees: -4.85),       // 13
            .straight(1043),                            // 14
            .corner(radius: 125, degrees: 98.86),       // 15
            .straight(146),                             // 16
            .corner(radius: 125, degrees: 69.21),       // 17
            .straight(599),                             // 18
            .corner(radius: 260, degrees: -102.51),     // 19
            .straight(255),                             // 20
            .corner(radius: 500, degrees: -39.09),      // 21
            .straight(644),                             // 22
            .corner(radius: 170, degrees: 67.83),       // 23
            .straight(370),                             // 24
            .corner(radius: 150, degrees: -36.87),      // 25
            .straight(137),                             // 26
            .corner(radius: 150, degrees: 83.66),       // 27
            .straight(225),                             // 28
            .corner(radius: 260, degrees: 51.35),       // 29
        ],
        closingStraights: (0, 10),
        startLine: 926,
        sectorStarts: [10, 19]
    )

    /// Desert speed: a long straight into a hairpin, an angular stadium climb and a hairpin at the top. Counterclockwise.
    static let mirage = TrackLayout(
        id: "mirage",
        revision: 1,
        name: "Mirage",
        summary: "Desert speed: a long straight into a hairpin, an angular stadium climb and a hairpin at the top.",
        startHeading: -9.0,
        segments: [
            .straight(4870),                            // 0
            .corner(radius: 120, degrees: 101.2),       // 1
            .straight(302),                             // 2
            .corner(radius: 120, degrees: 74.64),       // 3
            .straight(1029),                            // 4
            .corner(radius: 240, degrees: -31.88),      // 5
            .straight(480),                             // 6
            .corner(radius: 260, degrees: 36.87),       // 7
            .straight(392),                             // 8
            .corner(radius: 300, degrees: -55.3),       // 9
            .straight(609),                             // 10
            .corner(radius: 150, degrees: 28.57),       // 11
            .straight(798),                             // 12
            .corner(radius: 125, degrees: 103.07),      // 13
            .straight(214),                             // 14
            .corner(radius: 125, degrees: -63.92),      // 15
            .straight(666),                             // 16
            .corner(radius: 300, degrees: 27.73),       // 17
            .straight(676),                             // 18
            .corner(radius: 180, degrees: 57.99),       // 19
            .straight(611),                             // 20
            .corner(radius: 220, degrees: 81.03),       // 21
        ],
        closingStraights: (0, 18),
        startLine: 1704,
        sectorStarts: [4, 16]
    )

    /// Long and narrow: chicanes down both sides and a hairpin at the far end. Counterclockwise.
    static let island = TrackLayout(
        id: "island",
        revision: 1,
        name: "Island",
        summary: "Long and narrow: chicanes down both sides and a hairpin at the far end.",
        startHeading: 22.5,
        segments: [
            .straight(1494),                            // 0
            .corner(radius: 120, degrees: 100.22),      // 1
            .straight(412),                             // 2
            .corner(radius: 120, degrees: 47.09),       // 3
            .straight(1888),                            // 4
            .corner(radius: 600, degrees: 10.17),       // 5
            .straight(917),                             // 6
            .corner(radius: 140, degrees: -33.69),      // 7
            .straight(271),                             // 8
            .corner(radius: 140, degrees: 40.4),        // 9
            .straight(1591),                            // 10
            .corner(radius: 260, degrees: 38.29),       // 11
            .straight(573),                             // 12
            .corner(radius: 260, degrees: 74.74),       // 13
            .straight(554),                             // 14
            .corner(radius: 150, degrees: 46.22),       // 15
            .straight(342),                             // 16
            .corner(radius: 150, degrees: 8.84),        // 17
            .straight(2054),                            // 18
            .corner(radius: 900, degrees: 21.89),       // 19
            .straight(817),                             // 20
            .corner(radius: 140, degrees: -50.39),      // 21
            .straight(224),                             // 22
            .corner(radius: 140, degrees: 56.22),       // 23
        ],
        closingStraights: (18, 12),
        startLine: 523,
        sectorStarts: [7, 17]
    )

    /// Streets by the water: a climb, a hairpin, a curving tunnel and a swimming-pool wiggle. Clockwise.
    static let harbor = TrackLayout(
        id: "harbor",
        revision: 1,
        name: "Harbor",
        summary: "Streets by the water: a climb, a hairpin, a curving tunnel and a swimming-pool wiggle.",
        startHeading: 7.1,
        segments: [
            .straight(518),                             // 0
            .corner(radius: 150, degrees: 61.14),       // 1
            .straight(730),                             // 2
            .corner(radius: 260, degrees: 48.37),       // 3
            .straight(337),                             // 4
            .corner(radius: 200, degrees: -66.37),      // 5
            .straight(480),                             // 6
            .corner(radius: 230, degrees: -33.5),       // 7
            .straight(772),                             // 8
            .corner(radius: 260, degrees: -29.14),      // 9
            .straight(582),                             // 10
            .corner(radius: 120, degrees: -104.12),     // 11
            .straight(234),                             // 12
            .corner(radius: 120, degrees: 3.37),        // 13
            .straight(286),                             // 14
            .corner(radius: 220, degrees: 118.9),       // 15
            .straight(137),                             // 16
            .corner(radius: 700, degrees: -55.11),      // 17
            .straight(172),                             // 18
            .corner(radius: 400, degrees: -67.17),      // 19
            .straight(206),                             // 20
            .corner(radius: 140, degrees: -77.47),      // 21
            .straight(190),                             // 22
            .corner(radius: 140, degrees: 43.78),       // 23
            .straight(496),                             // 24
            .corner(radius: 300, degrees: -52.94),      // 25
            .straight(433),                             // 26
            .corner(radius: 140, degrees: 60.07),       // 27
            .straight(249),                             // 28
            .corner(radius: 140, degrees: -73.74),      // 29
            .straight(257),                             // 30
            .corner(radius: 140, degrees: 55.63),       // 31
            .straight(1127),                            // 32
            .corner(radius: 120, degrees: -97.45),      // 33
            .straight(82),                              // 34
            .corner(radius: 120, degrees: -94.25),      // 35
        ],
        closingStraights: (32, 2),
        startLine: 181,
        sectorStarts: [10, 24]
    )
}
