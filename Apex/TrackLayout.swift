import Foundation

/// One piece of a circuit: a straight, or a corner of constant radius turning left (positive degrees) or right.
enum TrackSegment: Equatable {
    case straight(Double)
    case corner(radius: Double, degrees: Double)
}

/// A circuit described as the pieces you'd drive, in order. `Track` turns it into geometry.
struct TrackLayout {
    /// A stable name for saves and leaderboards. Never change it once the circuit is released.
    var id: String
    /// Bump when a released circuit's shape changes: lap times on the old shape don't compare (`RaceBoard`).
    var revision: Int
    var name: String
    /// A line for the track list: what kind of driving the circuit asks for.
    var summary: String
    var segments: [TrackSegment]
    /// Two straights running in different directions. Their lengths are solved so the circuit closes exactly, so the
    /// other pieces can be tuned freely.
    var closingStraights: (Int, Int)
    /// The start/finish line's distance into the first segment.
    var startLine: Double
    /// Sector 1 ends where the first of these segments starts, sector 2 where the second does.
    var sectorStarts: [Int]

    /// A short fingerprint of the layout, for keeping best laps per circuit.
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
    static let all: [TrackLayout] = [.harbourPark, .oldTown, .ridgeway]

    static func named(_ id: String) -> TrackLayout? { all.first { $0.id == id } }

    /// An original circuit with the bones of an F1 track: a long main straight into a heavy-braking hairpin, a fast kink,
    /// three linked esses, a long back straight, a tight chicane, and a fast final corner onto the main straight. It runs
    /// counterclockwise, so most corners are lefts (toward the top of the screen).
    static let harbourPark = TrackLayout(
        id: "harbour_park",
        revision: 1,
        name: "Harbour Park",
        summary: "The all-rounder: a long straight into a hairpin, flowing esses and a tight chicane.",
        segments: [
            .straight(3600),                        // 0  main straight (length solved)
            .corner(radius: 130, degrees: 180),     // 1  T1 hairpin
            .straight(1100),                        // 2
            .corner(radius: 340, degrees: -90),     // 3  T2
            .straight(700),                         // 4  (length solved)
            .corner(radius: 700, degrees: -25),     // 5  the kink
            .corner(radius: 700, degrees: 25),      // 6
            .straight(280),                         // 7
            .corner(radius: 400, degrees: 90),      // 8  T3
            .corner(radius: 340, degrees: 50),      // 9  T4, into the esses
            .corner(radius: 320, degrees: -80),     // 10 T5
            .corner(radius: 400, degrees: 30),      // 11 T6
            .straight(1500),                        // 12 back straight
            .corner(radius: 300, degrees: 90),      // 13 T7
            .straight(420),                         // 14
            .corner(radius: 140, degrees: 55),      // 15 T8, the chicane
            .corner(radius: 140, degrees: -55),     // 16 T9
            .straight(600),                         // 17
            .corner(radius: 480, degrees: 90),      // 18 T10, the final corner
        ],
        closingStraights: (0, 4),
        startLine: 900,
        sectorStarts: [4, 13]
    )
}

extension TrackLayout {
    /// A tight street circuit, run clockwise: short straights between square corners, a double-hairpin switchback and
    /// a chicane. Precision over speed.
    static let oldTown = TrackLayout(
        id: "old_town",
        revision: 1,
        name: "Old Town",
        summary: "Tight streets: square corners, a double-hairpin switchback and a chicane. Precision over speed.",
        segments: [
            .straight(1600),                        // 0  main straight (length solved)
            .corner(radius: 170, degrees: -90),     // 1  T1
            .straight(700),                         // 2
            .corner(radius: 160, degrees: 90),      // 3  T2
            .straight(650),                         // 4
            .corner(radius: 160, degrees: -90),     // 5  T3
            .straight(1000),                        // 6
            .corner(radius: 180, degrees: -90),     // 7  T4
            .straight(1050),                        // 8
            .corner(radius: 130, degrees: 180),     // 9  the switchback: left hairpin...
            .straight(950),                         // 10
            .corner(radius: 130, degrees: -180),    // 11 ...and right hairpin
            .straight(1600),                        // 12
            .corner(radius: 200, degrees: -90),     // 13 T7
            .straight(800),                         // 14 (length solved)
            .corner(radius: 140, degrees: 45),      // 15 the chicane
            .corner(radius: 140, degrees: -45),     // 16
            .straight(600),                         // 17
            .corner(radius: 220, degrees: -90),     // 18 T10, onto the main straight
        ],
        closingStraights: (0, 14),
        startLine: 500,
        sectorStarts: [7, 13]
    )

    /// A fast, open circuit: a big sweeper, four linked esses, a heavy stop at the top, a long back straight with a
    /// flat-out kink, and a double-apex final corner. Commit to the line.
    static let ridgeway = TrackLayout(
        id: "ridgeway",
        revision: 1,
        name: "Ridgeway",
        summary: "Fast and flowing: a big sweeper, linked esses and a flat-out kink. Commit to the line.",
        segments: [
            .straight(2600),                        // 0  main straight (length solved)
            .corner(radius: 460, degrees: 90),      // 1  the sweeper
            .straight(700),                         // 2  (length solved)
            .corner(radius: 300, degrees: 45),      // 3  into the esses
            .corner(radius: 320, degrees: -50),     // 4
            .corner(radius: 300, degrees: 80),      // 5
            .corner(radius: 330, degrees: -50),     // 6
            .corner(radius: 360, degrees: 20),      // 7
            .straight(1650),                        // 8
            .corner(radius: 170, degrees: 105),     // 9  the heavy stop at the top
            .straight(1900),                        // 10 back straight
            .corner(radius: 700, degrees: -25),     // 11 the kink
            .corner(radius: 700, degrees: 25),      // 12
            .straight(500),                         // 13
            .corner(radius: 240, degrees: 30),      // 14
            .straight(1100),                        // 15
            .corner(radius: 300, degrees: 45),      // 16 double apex
            .straight(200),                         // 17
            .corner(radius: 260, degrees: 45),      // 18
        ],
        closingStraights: (0, 2),
        startLine: 900,
        sectorStarts: [3, 11]
    )
}
