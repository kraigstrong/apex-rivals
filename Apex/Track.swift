import CoreGraphics
import Foundation

/// A closed circuit, sampled every `spacing` units along its centerline.
///
/// Positions on the track are (s, n): s is the distance along the lap from the start/finish line, growing in the
/// direction of travel, and n is the offset to the left of the centerline, which is toward the top of the screen while
/// racing (the camera keeps the track running left to right).
struct Track {
    let layout: TrackLayout
    let width: Double
    let spacing: Double
    let length: Double
    /// Centerline points.
    let x: [Double]
    let y: [Double]
    /// The centerline's direction, unwrapped: across one lap it changes by `turning`.
    let heading: [Double]
    let curvature: [Double]
    /// A heavily smoothed heading for the camera to turn with.
    let cameraHeading: [Double]
    /// Total change of heading over a lap: +2π for a counterclockwise circuit, −2π for a clockwise one.
    let turning: Double
    /// Where sectors 1 and 2 end.
    let sectorEnds: [Double]
    /// The layout's pieces, with the closing straights at their solved lengths.
    let segments: [TrackSegment]
    let bounds: CGRect

    var count: Int { x.count }

    init(_ layout: TrackLayout, width: Double = RaceTuning.trackWidth, spacing: Double = RaceTuning.sampleSpacing,
         smoothing: Double = RaceTuning.curvatureSmoothing) {
        self.layout = layout
        self.width = width
        self.spacing = spacing

        // Solve the two closing straights so the end meets the start. Lengthening a straight slides everything after
        // it along that straight's direction, so the gap is linear in the two lengths: one 2×2 solve, repeated to
        // absorb rounding to whole samples.
        var segments = layout.segments
        let (a, b) = layout.closingStraights
        let startHeading = layout.startHeading * .pi / 180
        var path = Track.trace(segments, spacing: spacing, smoothing: smoothing, startHeading: startHeading)
        for _ in 0..<3 {
            let gapX = path.x[path.x.count - 1] - path.x[0]
            let gapY = path.y[path.y.count - 1] - path.y[0]
            let headingA = path.heading[path.middles[a]], headingB = path.heading[path.middles[b]]
            let det = cos(headingA) * sin(headingB) - cos(headingB) * sin(headingA)
            precondition(abs(det) > 0.1, "The closing straights must run in different directions")
            let deltaA = (-gapX * sin(headingB) + gapY * cos(headingB)) / det
            let deltaB = (cos(headingA) * -gapY + sin(headingA) * gapX) / det
            for (index, delta) in [(a, deltaA), (b, deltaB)] {
                guard case .straight(let length) = segments[index] else {
                    preconditionFailure("Closing segment \(index) must be a straight")
                }
                precondition(length + delta > 0, "Segment \(index) would need a negative length to close the circuit")
                segments[index] = .straight(length + delta)
            }
            path = Track.trace(segments, spacing: spacing, smoothing: smoothing, startHeading: startHeading)
        }
        self.segments = segments

        // Spread the last sliver of rounding error along the lap so the loop closes exactly.
        let total = path.curvature.count
        var xs = path.x, ys = path.y
        let gapX = xs[total] - xs[0], gapY = ys[total] - ys[0]
        for i in 0...total {
            xs[i] -= gapX * Double(i) / Double(total)
            ys[i] -= gapY * Double(i) / Double(total)
        }
        let turning = path.heading[total] - path.heading[0]
        self.turning = turning

        // Start the arrays at the start/finish line.
        let start = path.starts[0] + Int((layout.startLine / spacing).rounded())
        func rotated(_ values: [Double]) -> [Double] {
            Array(values[start..<total]) + Array(values[0..<start])
        }
        x = rotated(xs)
        y = rotated(ys)
        curvature = rotated(path.curvature)
        heading = Array(path.heading[start..<total]) + path.heading[0..<start].map { $0 + turning }
        length = Double(total) * spacing
        sectorEnds = layout.sectorStarts.map { index in
            Double((path.starts[index] - start + total) % total) * spacing
        }

        // The camera's heading: the unwrapped heading box-filtered around the loop.
        let window = max(1, Int((RaceTuning.cameraHeadingSmoothing / spacing).rounded()))
        var prefix = [0.0]
        prefix.reserveCapacity(3 * total + 1)
        let unwrapped = heading
        for i in 0..<(3 * total) {
            prefix.append(prefix[i] + unwrapped[i % total] + turning * Double(i / total - 1))
        }
        cameraHeading = (0..<total).map { i in
            let low = total + i - window / 2
            return (prefix[low + window] - prefix[low]) / Double(window)
        }

        let minX = x.min() ?? 0, maxX = x.max() ?? 0, minY = y.min() ?? 0, maxY = y.max() ?? 0
        bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -width / 2, dy: -width / 2)
    }

    // MARK: Looking things up

    /// A distance folded into one lap, [0, length).
    func wrap(_ s: Double) -> Double {
        let folded = s.truncatingRemainder(dividingBy: length)
        return folded < 0 ? folded + length : folded
    }

    private func lookup(_ s: Double) -> (i: Int, j: Int, f: Double) {
        let u = wrap(s) / spacing
        let i = min(Int(u), count - 1)
        return (i, (i + 1) % count, u - Double(i))
    }

    func centerline(at s: Double) -> CGPoint {
        let (i, j, f) = lookup(s)
        return CGPoint(x: x[i] + (x[j] - x[i]) * f, y: y[i] + (y[j] - y[i]) * f)
    }

    /// The centerline's direction at `s`, continuous within a lap (it steps by `turning` at the line).
    func heading(at s: Double) -> Double {
        let (i, j, f) = lookup(s)
        let next = j == 0 ? heading[0] + turning : heading[j]
        return heading[i] + (next - heading[i]) * f
    }

    func curvature(at s: Double) -> Double {
        let (i, j, f) = lookup(s)
        return curvature[i] + (curvature[j] - curvature[i]) * f
    }

    func cameraHeading(at s: Double) -> Double {
        let (i, j, f) = lookup(s)
        let next = j == 0 ? cameraHeading[0] + turning : cameraHeading[j]
        return cameraHeading[i] + (next - cameraHeading[i]) * f
    }

    /// The point `n` to the left of the centerline at `s`.
    func point(s: Double, n: Double) -> CGPoint {
        let center = centerline(at: s)
        let h = heading(at: s)
        return CGPoint(x: center.x - sin(h) * n, y: center.y + cos(h) * n)
    }

    /// The point `n` to the left of sample `i` (any integer; it wraps).
    func point(sample i: Int, n: Double) -> CGPoint {
        let k = ((i % count) + count) % count
        return CGPoint(x: x[k] - sin(heading[k]) * n, y: y[k] + cos(heading[k]) * n)
    }

    // MARK: Building

    private struct Trace {
        var curvature: [Double]
        /// Each segment's first sample, and a sample in its middle.
        var starts: [Int]
        var middles: [Int]
        /// One more point than samples: the last is where the loop ends (the start, once closed).
        var x: [Double]
        var y: [Double]
        var heading: [Double]
    }

    private static func trace(_ segments: [TrackSegment], spacing: Double, smoothing: Double,
                              startHeading: Double) -> Trace {
        var raw: [Double] = []
        var starts: [Int] = [], middles: [Int] = []
        for segment in segments {
            starts.append(raw.count)
            switch segment {
            case .straight(let length):
                let n = max(1, Int((length / spacing).rounded()))
                middles.append(raw.count + n / 2)
                raw += Array(repeating: 0, count: n)
            case .corner(let radius, let degrees):
                let angle = degrees * .pi / 180
                let n = max(1, Int((abs(angle) * radius / spacing).rounded()))
                middles.append(raw.count + n / 2)
                // Each sample turns an equal share, so the corner's total angle is exact.
                raw += Array(repeating: angle / (Double(n) * spacing), count: n)
            }
        }
        let curvature = boxFilter(raw, width: Int((smoothing / spacing).rounded()))
        var x = [0.0], y = [0.0], heading = [startHeading]
        x.reserveCapacity(curvature.count + 1)
        y.reserveCapacity(curvature.count + 1)
        heading.reserveCapacity(curvature.count + 1)
        for (i, k) in curvature.enumerated() {
            let middle = heading[i] + k * spacing / 2
            x.append(x[i] + cos(middle) * spacing)
            y.append(y[i] + sin(middle) * spacing)
            heading.append(heading[i] + k * spacing)
        }
        return Trace(curvature: curvature, starts: starts, middles: middles, x: x, y: y, heading: heading)
    }

    /// A moving average around a loop. It keeps the total, so every corner still turns its full angle.
    static func boxFilter(_ values: [Double], width: Int) -> [Double] {
        let n = values.count
        guard width > 1, width < n else { return values }
        var prefix = [0.0]
        prefix.reserveCapacity(3 * n + 1)
        for i in 0..<(3 * n) { prefix.append(prefix[i] + values[i % n]) }
        return (0..<n).map { i in
            let low = n + i - width / 2
            return (prefix[low + width] - prefix[low]) / Double(width)
        }
    }
}
