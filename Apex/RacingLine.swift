import Accelerate
import Foundation

/// The minimum-curvature line around a track: the path that bends least while staying inside the walls. Since speed
/// comes from how little the path bends, it is close to the fastest line there is. The fastest test bot follows it, and
/// Xcode builds can draw it on the track.
struct RacingLine {
    /// Spacing of `offsets` along the lap.
    let spacing: Double
    /// Offset from the centerline at each `spacing` along the lap.
    let offsets: [Double]
    let trackLength: Double

    /// - Parameter margin: How far the car's center stays inside the walls' reach.
    init(track: Track, margin: Double = 8, spacing: Double = 12) {
        let count = Int((track.length / spacing).rounded())
        let spacing = track.length / Double(count)
        self.spacing = spacing
        trackLength = track.length
        let limit = track.width / 2 - RaceTuning.carHalfWidth - margin

        var cx = [Double](repeating: 0, count: count), cy = cx, nx = cx, ny = cx
        for i in 0..<count {
            let s = Double(i) * spacing
            let c = track.centerline(at: s), h = track.heading(at: s)
            cx[i] = c.x; cy[i] = c.y; nx[i] = -sin(h); ny[i] = cos(h)
        }

        // Minimize Σ|P[i−1] − 2P[i] + P[i+1]|² over P[i] = C[i] + offset[i]·N[i]. The normal equations are banded:
        // H[i][i+d] = (N[i]·N[i+d])·band[d] with band = (6, −4, 1), and b[i] = −N[i]·(DᵀD C)[i].
        let band: [Double] = [6, -4, 1]
        func wrap(_ i: Int) -> Int { (i % count + count) % count }
        func h(_ i: Int, _ d: Int) -> Double {
            let j = wrap(i + d)
            return (nx[i] * nx[j] + ny[i] * ny[j]) * band[abs(d)]
        }
        var b = [Double](repeating: 0, count: count)
        for i in 0..<count {
            var fx = 0.0, fy = 0.0
            for d in -2...2 {
                let j = wrap(i + d)
                fx += band[abs(d)] * cx[j]
                fy += band[abs(d)] * cy[j]
            }
            b[i] = -(nx[i] * fx + ny[i] * fy)
        }

        // Active set: solve with the free offsets, pin any that cross a wall to it, release pinned ones that want back
        // in, and repeat until nothing changes.
        var offsets = [Double](repeating: 0, count: count)
        var pinned = [Bool](repeating: false, count: count)
        for _ in 0..<60 {
            let free = (0..<count).filter { !pinned[$0] }
            var position = [Int](repeating: -1, count: count)
            for (k, i) in free.enumerated() { position[i] = k }
            let m = free.count
            var matrix = [Double](repeating: 0, count: m * m)
            var rhs = [Double](repeating: 0, count: m)
            for (k, i) in free.enumerated() {
                rhs[k] = b[i]
                for d in -2...2 {
                    let j = wrap(i + d)
                    if pinned[j] {
                        rhs[k] -= h(i, d) * offsets[j]
                    } else {
                        matrix[position[j] * m + k] += h(i, d)
                    }
                }
                matrix[k * m + k] += 1e-9
            }
            guard RacingLine.solveSymmetric(&matrix, &rhs, size: m) else { break }
            for (k, i) in free.enumerated() { offsets[i] = rhs[k] }

            var changed = false
            for i in 0..<count {
                if !pinned[i], abs(offsets[i]) > limit {
                    offsets[i] = offsets[i] > 0 ? limit : -limit
                    pinned[i] = true
                    changed = true
                } else if pinned[i] {
                    var gradient = -b[i]
                    for d in -2...2 { gradient += h(i, d) * offsets[wrap(i + d)] }
                    // Pinned against a wall with the objective pulling it inward: let it go.
                    if gradient * offsets[i] > 0 {
                        pinned[i] = false
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        self.offsets = offsets
    }

    func offset(at s: Double) -> Double {
        var u = s.truncatingRemainder(dividingBy: trackLength) / spacing
        if u < 0 { u += Double(offsets.count) }
        let i = min(Int(u), offsets.count - 1)
        let f = u - Double(i)
        return offsets[i] + (offsets[(i + 1) % offsets.count] - offsets[i]) * f
    }

    /// Solves a symmetric positive-definite system in place (Cholesky); the answer replaces `rhs`.
    private static func solveSymmetric(_ matrix: inout [Double], _ rhs: inout [Double], size: Int) -> Bool {
        guard size > 0 else { return true }
        var n = __LAPACK_int(size), nrhs = __LAPACK_int(1), lda = __LAPACK_int(size), ldb = __LAPACK_int(size)
        var info = __LAPACK_int(0)
        var uplo = CChar(UInt8(ascii: "L"))
        dposv_(&uplo, &n, &nrhs, &matrix, &lda, &rhs, &ldb, &info)
        return info == 0
    }
}
