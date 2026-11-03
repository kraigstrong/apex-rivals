import Foundation
import SwiftUI
import Testing
@testable import Apex

/// Draws Ghost Thread's page on brightbench.app from the game itself, into `Art/site`: the logo in the stock paint
/// (`logo.png`), and every circuit's outline and ideal line, with when the unlock screen's thread reaches each point of
/// it (`circuits.json`), so the page can lap them as the game does. Copy both into BrightBench's
/// `apps/marketing` (`public/games/ghost-thread/` and `src/lib/`) after a change to a circuit or the logo. Only runs
/// when asked, since it writes into the repo:
///
///     TEST_RUNNER_APEX_DRAW_SITE=1 xcodebuild test ... -only-testing:ApexTests/SiteArtTests
struct SiteArtTests {
    /// One circuit, in an SVG viewBox of `width` × `height` (the longer side 1000), north up.
    struct Circuit: Encodable {
        let id: String
        let name: String
        let summary: String
        let corners: Int
        let clockwise: Bool
        let width: Double
        let height: Double
        /// The centerline, as the track list draws it.
        let outline: String
        /// The ideal line the thread follows.
        let line: String
        /// A real lap of the thread, in seconds (the unlock screen plays it four times faster).
        let lap: Double
        /// How far along `line` the thread is (a share of its length) at evenly spaced moments of the lap: SVG's
        /// `keyPoints` for `keyTimes` of 0, 1/n, … 1.
        let keyPoints: [Double]
    }

    static let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Art/site")

    @Test(.enabled(if: ProcessInfo.processInfo.environment["APEX_DRAW_SITE"] != nil))
    @MainActor func draw() throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: GhostThreadLogo(scale: 2, ghost: Livery.defaults[.best]))
        renderer.scale = 2
        let png = try #require(renderer.uiImage?.pngData())
        try png.write(to: Self.folder.appending(path: "logo.png"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(TrackLayout.all.map { Self.circuit(Track($0)) })
        try json.write(to: Self.folder.appending(path: "circuits.json"))
    }

    static func circuit(_ track: Track, moments: Int = 60) -> Circuit {
        // Framed as the unlock screen frames it: room for the line wherever it runs inside the walls.
        let bounds = track.bounds.insetBy(dx: -track.width / 2, dy: -track.width / 2)
        let scale = 1000 / max(bounds.width, bounds.height)
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - bounds.minX) * scale, y: (bounds.maxY - point.y) * scale)
        }
        // Whole units of the 1000-unit box are finer than a page draws them.
        func path(_ points: [CGPoint]) -> String {
            points.enumerated().map { index, point in
                (index == 0 ? "M" : "L") + String(format: "%.0f %.0f", point.x, point.y)
            }.joined() + "Z"
        }
        let lap = ThreadLap(track: track)
        let line = lap.points.map(map)
        // The line's length up to each point, and round to the start again.
        var lengths = [0.0]
        for (a, b) in zip(line, line.dropFirst() + [line[0]]) { lengths.append(lengths.last! + hypot(b.x - a.x, b.y - a.y)) }
        let keyPoints = (0...moments).map { moment -> Double in
            if moment == moments { return 1 }
            let time = lap.duration * Double(moment) / Double(moments)
            let next = lap.times.firstIndex { $0 > time } ?? lap.times.count - 1
            let f = (time - lap.times[next - 1]) / (lap.times[next] - lap.times[next - 1])
            let along = lengths[next - 1] + (lengths[next] - lengths[next - 1]) * f
            return (along / lengths.last! * 10_000).rounded() / 10_000
        }
        let corners = track.layout.segments.filter { if case .corner = $0 { return true } else { return false } }.count
        return Circuit(
            id: track.layout.id, name: track.layout.name, summary: track.layout.summary, corners: corners,
            clockwise: track.turning < 0, width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded(),
            outline: path(stride(from: 0, to: track.count, by: 30).map { map(CGPoint(x: track.x[$0], y: track.y[$0])) }),
            line: path(stride(from: 0, to: line.count, by: 2).map { line[$0] }), lap: (lap.duration * 100).rounded() / 100, keyPoints: keyPoints)
    }

    /// The thread moves forward the whole lap, from the start back round to it.
    @Test func eachCircuitsThreadRunsOnceRoundItsLine() {
        for layout in TrackLayout.all {
            let circuit = Self.circuit(Track(layout))
            #expect(circuit.keyPoints.first == 0 && circuit.keyPoints.last == 1, "\(layout.id)")
            #expect(zip(circuit.keyPoints, circuit.keyPoints.dropFirst()).allSatisfy { $0 <= $1 }, "\(layout.id)")
            #expect(max(circuit.width, circuit.height) == 1000, "\(layout.id)")
        }
    }
}
