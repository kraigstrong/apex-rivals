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
    /// An original circuit with the bones of an F1 track: a long main straight into a heavy-braking hairpin, a fast kink,
    /// three linked esses, a long back straight, a tight chicane, and a fast final corner onto the main straight. It runs
    /// counterclockwise, so most corners are lefts (toward the top of the screen).
    static let harbourPark = TrackLayout(
        id: "harbour_park",
        revision: 1,
        name: "Harbour Park",
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
