import Foundation
import Testing
@testable import Apex

struct TrackTests {
    let track = Track(.harbourPark)

    @Test func closesIntoALoop() {
        let last = track.count - 1
        let gap = hypot(track.x[0] - track.x[last], track.y[0] - track.y[last])
        #expect(abs(gap - track.spacing) < 0.05)
        #expect(abs(abs(track.turning) - 2 * .pi) < 1e-9)
    }

    @Test func closingStraightsStayLong() {
        let (a, b) = track.layout.closingStraights
        for index in [a, b] {
            guard case .straight(let length) = track.segments[index] else {
                Issue.record("Segment \(index) isn't a straight")
                continue
            }
            #expect(length > 200, "Segment \(index) solved to \(length)")
        }
    }

    /// The inside of the tightest corner still has room: the centerline's radius beats half the track's width.
    @Test func cornersFitTheTrack() {
        let tightest = 1 / (track.curvature.map(abs).max() ?? 0)
        #expect(tightest > track.width / 2 + 50)
    }

    /// No two parts of the circuit come within a track width plus a strip of grass of each other.
    @Test func neverOverlapsItself() {
        let step = 10
        let indices = Array(stride(from: 0, to: track.count, by: step))
        var nearest = Double.infinity
        for (k, i) in indices.enumerated() {
            for j in indices[(k + 1)...] {
                let apart = min(j - i, track.count - (j - i))
                guard Double(apart) * track.spacing > 700 else { continue }
                nearest = min(nearest, hypot(track.x[i] - track.x[j], track.y[i] - track.y[j]))
            }
        }
        #expect(nearest > track.width + 80, "Closest approach \(nearest)")
    }

    @Test func lapLengthSuitsThirtySeconds() {
        #expect((11_000...14_000).contains(track.length))
    }

    @Test func sectorsFallInOrder() {
        #expect(track.sectorEnds.count == 2)
        #expect(0 < track.sectorEnds[0])
        #expect(track.sectorEnds[0] < track.sectorEnds[1])
        #expect(track.sectorEnds[1] < track.length)
    }

    @Test func offsetsAreSquareToTheTrack() {
        for s in stride(from: 0.0, to: track.length, by: 997) {
            let left = track.point(s: s, n: track.width / 2)
            let right = track.point(s: s, n: -track.width / 2)
            #expect(abs(hypot(left.x - right.x, left.y - right.y) - track.width) < 1e-6)
        }
    }

    @Test func headingIsContinuousAroundTheLap() {
        var previous = track.heading(at: 0)
        for s in stride(from: 1.0, to: track.length, by: 1) {
            let heading = track.heading(at: s)
            #expect(abs(heading - previous) < 0.02)
            previous = heading
        }
        // Crossing the line, it steps by exactly one turn.
        #expect(abs(track.heading(at: track.length - 0.001) - track.heading(at: 0) - track.turning) < 0.01)
    }

    @Test func racingLineStaysInsideAndCutsCorners() {
        let line = RacingLine(track: track)
        let reach = track.width / 2 - RaceTuning.carHalfWidth
        #expect(line.offsets.allSatisfy { abs($0) <= reach + 1e-6 })
        // It uses the track's width.
        #expect(line.offsets.contains { abs($0) > reach - 10 })
    }
}
