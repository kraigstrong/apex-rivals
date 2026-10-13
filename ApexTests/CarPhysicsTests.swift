import Foundation
import Testing
@testable import Apex

struct CarPhysicsTests {
    let track = Track(.testOval)
    let dt = RaceTuning.physicsStep

    /// A car on the main straight, `distanceBeforeLine` short of the line.
    func carOnStraight(speed: Double = RaceTuning.topSpeed) -> Car {
        Car(track: track, distanceBeforeLine: 600, speed: speed)
    }

    @Test func holdingSettlesTheNoseAtItsSteadyAngle() {
        // From rest by the right-hand wall, so a second of holding doesn't reach the other one.
        var car = Car(track: track, distanceBeforeLine: -100, n: -50)
        for _ in 0..<240 { CarPhysics.step(&car, holding: true, dt: dt, on: track) }
        #expect(car.sinceWallHit == .infinity)
        #expect(abs(car.psi - RaceTuning.steerRate / RaceTuning.steerReturn) < 0.02)
    }

    /// A car can drive with its own handling (as the tuning panel's bots do), whatever `RaceTuning` says.
    @Test func aCarCanHaveItsOwnHandling() {
        var handling = RaceTuning.Handling.current
        handling.steerRate /= 2
        var car = Car(track: track, distanceBeforeLine: -100, n: -50)
        for _ in 0..<240 { CarPhysics.step(&car, holding: true, dt: dt, on: track, handling: handling) }
        #expect(abs(car.psi - handling.steerRate / handling.steerReturn) < 0.02)
    }

    @Test func holdingMovesTowardTheTopAndLettingGoTowardTheBottom() {
        var up = carOnStraight(), down = carOnStraight()
        for _ in 0..<60 {
            CarPhysics.step(&up, holding: true, dt: dt, on: track)
            CarPhysics.step(&down, holding: false, dt: dt, on: track)
        }
        #expect(up.n > 10)
        #expect(down.n < -10)
    }

    /// Tapping fast enough to hold a line keeps the car at nearly full speed.
    @Test func quickCorrectionsAreNearlyFree() {
        var car = Car(track: track, distanceBeforeLine: -100, speed: RaceTuning.topSpeed)
        var lowest = car.speed
        for step in 0..<(240 * 3) {
            CarPhysics.step(&car, holding: step % 24 < 12, dt: dt, on: track)
            lowest = min(lowest, car.speed)
        }
        #expect(lowest > RaceTuning.topSpeed * 0.95)
    }

    /// Swinging across the track and back costs real speed, though the track itself is straight.
    @Test func weavingCostsSpeed() {
        var car = Car(track: track, distanceBeforeLine: -100, speed: RaceTuning.topSpeed)
        var total = 0.0
        let steps = 240 * 3
        for step in 0..<steps {
            CarPhysics.step(&car, holding: step % 140 < 70, dt: dt, on: track)
            total += car.speed
        }
        #expect(total / Double(steps) < RaceTuning.topSpeed * 0.9)
    }

    @Test func grindingAWallNeverStopsTheCar() {
        var car = carOnStraight()
        var hits = 0
        for _ in 0..<(240 * 3) {
            if CarPhysics.step(&car, holding: true, dt: dt, on: track) != nil { hits += 1 }
            #expect(abs(car.n) <= track.width / 2 - RaceTuning.carHalfWidth + 1e-9)
        }
        #expect(hits > 0)
        #expect(car.speed >= RaceTuning.minimumSpeed)
    }

    @Test func aSquareHitCostsMoreThanAGlancingOne() {
        func speedAfterHit(angle: Double) -> Double {
            var car = carOnStraight()
            car.n = track.width / 2 - RaceTuning.carHalfWidth - 0.01
            car.psi = angle
            CarPhysics.step(&car, holding: true, dt: dt, on: track)
            return car.speed
        }
        #expect(speedAfterHit(angle: 0.55) < speedAfterHit(angle: 0.1))
    }

    @Test func crossingTheLineCountsALap() {
        var car = Car(track: track, distanceBeforeLine: 20, speed: 300)
        #expect(car.progress(on: track) < 0)
        for _ in 0..<60 { CarPhysics.step(&car, holding: false, dt: dt, on: track) }
        #expect(car.wraps == 0)
        #expect(car.progress(on: track) > 0)
    }
}
