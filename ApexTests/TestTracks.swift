@testable import Apex

extension TrackLayout {
    /// A rounded rectangle with 3,000-unit straights, for physics tests that need long, plain straights. Not a race
    /// circuit, so it never appears in the game.
    static let testOval = TrackLayout(
        id: "test_oval",
        revision: 1,
        name: "Test Oval",
        summary: "",
        segments: [
            .straight(3000), .corner(radius: 300, degrees: 90),
            .straight(1000), .corner(radius: 300, degrees: 90),
            .straight(3000), .corner(radius: 300, degrees: 90),
            .straight(1000), .corner(radius: 300, degrees: 90),
        ],
        closingStraights: (0, 2),
        startLine: 700,
        sectorStarts: [2, 4]
    )
}
