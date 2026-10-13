import CoreGraphics
import Foundation

/// The car, in track coordinates.
struct Car {
    /// Distance along the lap from the start/finish line.
    var s: Double
    /// Offset left of the centerline: toward the top of the screen.
    var n: Double
    /// The nose's angle to the track's direction, positive toward the top of the screen.
    var psi: Double = 0
    var speed: Double
    /// Times the car has crossed the start/finish line (−1 before its first), so progress and headings never jump.
    var wraps: Int
    /// The nose's world heading, smoothed over `RaceTuning.straightnessLength` of travel.
    var smoothedHeading: Double
    /// How sharply the smoothed path is curving. It sets `lineSpeed`.
    var pathCurvature: Double = 0
    /// The fastest the current line allows: top speed on a straight path, less the more it curves.
    var lineSpeed: Double = RaceTuning.topSpeed
    /// 0...1: how hard the line is braking the car right now, eased so it reads as skid marks.
    var scrub: Double = 0
    var sinceWallHit: Double = .infinity

    /// A car at rest on the centerline, `distanceBeforeLine` short of the start/finish line.
    init(track: Track, distanceBeforeLine: Double = RaceTuning.startDistanceBeforeLine, n: Double = 0, speed: Double = 0) {
        s = track.wrap(-distanceBeforeLine)
        self.n = n
        self.speed = speed
        wraps = distanceBeforeLine > 0 ? -1 : 0
        smoothedHeading = track.heading(at: s) + track.turning * Double(wraps)
    }

    /// Distance from the start/finish line, counting laps: negative before the first crossing.
    func progress(on track: Track) -> Double { Double(wraps) * track.length + s }

    /// The nose's direction in the world, unwrapped.
    func heading(on track: Track) -> Double { track.heading(at: s) + track.turning * Double(wraps) + psi }

    func position(on track: Track) -> CGPoint { track.point(s: s, n: n) }
}

enum CarPhysics {
    struct WallHit {
        /// +1 for the wall on the car's left (top of the screen), −1 for the right.
        var side: Double
        /// 0...1, for sparks and haptics.
        var severity: Double
    }

    /// Advances the car by one fixed step.
    ///
    /// Holding swings the nose toward the top of the screen, letting go swings it toward the bottom; either way it eases
    /// back toward the track's direction, like Bigger Fish's rise and fall. The nose sets how the car drifts across the
    /// track as the track carries it around.
    ///
    /// Speed comes from how straight the car's path through the world is: its heading, smoothed over a short distance,
    /// gives a curvature κ, and the car can go no faster than √(grip / κ). Weaving bends the path and costs speed; so
    /// does following a corner's tight inside, while a wide entry, a clipped apex and a wide exit bend it least.
    @discardableResult
    static func step(_ car: inout Car, holding: Bool, dt: Double, on track: Track) -> WallHit? {
        let t = RaceTuning.self
        car.psi += ((holding ? t.steerRate : -t.steerRate) - t.steerReturn * car.psi) * dt

        // Move: along the track (faster on the inside of a corner, where the lap is shorter) and across it.
        let k = track.curvature(at: car.s)
        let along = car.speed * cos(car.psi) / max(0.2, 1 - car.n * k) * dt
        car.n += car.speed * sin(car.psi) * dt
        let s = car.s + along
        if s >= track.length { car.wraps += 1 } else if s < 0 { car.wraps -= 1 }
        car.s = track.wrap(s)

        var hit: WallHit?
        let limit = track.width / 2 - t.carHalfWidth
        if abs(car.n) > limit {
            let side: Double = car.n > 0 ? 1 : -1
            car.n = side * limit
            if car.psi * side > 0 {
                let angle = abs(sin(car.psi))
                let fresh = car.sinceWallHit > t.wallKnockCooldown
                let scrubbed = car.speed * (1 - t.wallScrub * angle - (fresh ? t.wallKnock : 0))
                car.speed = max(min(car.speed, t.minimumSpeed), scrubbed)
                car.psi = -car.psi * t.wallBounce
                if fresh {
                    hit = WallHit(side: side, severity: min(1, 0.25 + angle * 2.5))
                }
                car.sinceWallHit = 0
            }
        }
        car.sinceWallHit += dt

        // How straight the path has been sets how fast the car may go. For heading smoothed exponentially over a
        // distance L, the smoothed path's curvature is exactly (heading − smoothed) / L.
        let heading = car.heading(on: track)
        let blend = 1 - exp(-car.speed * dt / t.straightnessLength)
        car.smoothedHeading += (heading - car.smoothedHeading) * blend
        car.pathCurvature = abs(heading - car.smoothedHeading) / t.straightnessLength
        let allowed = car.pathCurvature > 1e-9 ? (t.grip / car.pathCurvature).squareRoot() : .infinity
        car.lineSpeed = max(t.minimumSpeed, min(t.topSpeed, allowed))

        let excess = max(0, car.speed - car.lineSpeed) / max(car.speed, 1)
        if car.speed > car.lineSpeed {
            car.speed = max(car.lineSpeed, car.speed - t.braking * dt)
        } else {
            let fade = 1 - t.accelerationFade * pow(car.speed / t.topSpeed, 2)
            car.speed = min(car.lineSpeed, car.speed + t.acceleration * fade * dt)
        }
        let scrubTarget = min(1, excess / 0.12)
        car.scrub += (scrubTarget - car.scrub) * (1 - exp(-dt / 0.1))
        return hit
    }
}
