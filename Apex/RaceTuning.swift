import Foundation

/// Every feel constant in one place. Distances are world units (the car is 34 long, the track 120 wide wall to wall);
/// speeds are units a second.
enum RaceTuning {
    // MARK: Track

    static let trackWidth: Double = 120
    /// The track is sampled this often along its centerline.
    static let sampleSpacing: Double = 1
    /// Corner curvature is box-filtered over this length, so every corner eases in and out instead of snapping.
    static let curvatureSmoothing: Double = 70
    /// Curbs line the edges wherever the centerline is curving tighter than this radius.
    static let curbRadius: Double = 1100

    // MARK: Steering

    /// Holding swings the car's nose toward the top of the screen (the car's left) at this rate, and letting go swings it
    /// toward the bottom, in radians a second.
    static let steerRate: Double = 2.4
    /// Pulls the nose back toward the track's direction (per second). Holding settles at `steerRate / steerReturn` radians.
    static let steerReturn: Double = 4.0

    // MARK: Speed

    static let topSpeed: Double = 500
    /// The fastest a car can follow a path of curvature κ is √(grip / κ), so straighter is faster.
    static let grip: Double = 480
    /// The car's heading is smoothed over this distance before its curvature sets the speed. Quick, small corrections
    /// mostly cancel out; slower weaves and corners don't.
    static let straightnessLength: Double = 90
    static let acceleration: Double = 280
    /// Acceleration fades by this share as the car nears top speed.
    static let accelerationFade: Double = 0.55
    /// How quickly speed drops to what the line allows.
    static let braking: Double = 1500
    /// However badly a lap goes, the car never drops below this speed once it's rolling.
    static let minimumSpeed: Double = 110

    // MARK: Walls

    /// Half the car's width: how close its center can come to a wall.
    static let carHalfWidth: Double = 8
    /// Share of the nose's angle into the wall that bounces back out.
    static let wallBounce: Double = 0.3
    /// Share of speed lost per unit of sin(impact angle): glancing touches are cheap, square hits are not.
    static let wallScrub: Double = 0.3
    /// A flat share of speed lost on a fresh hit, and how long until another hit counts as fresh.
    static let wallKnock: Double = 0.04
    static let wallKnockCooldown: Double = 0.3

    // MARK: Simulation

    /// Physics runs in fixed steps, whatever the frame rate.
    static let physicsStep: Double = 1.0 / 240

    // MARK: Camera

    /// World units across the screen, from standing still to top speed: the view widens as you go faster.
    static let viewWidthSlow: Double = 760
    static let viewWidthFast: Double = 980
    /// On a tall screen (an iPad), at least this much track shows top to bottom.
    static let minimumViewHeight: Double = 380
    /// The camera leads the car by this share of the visible width, so the car sits left of center.
    static let cameraLead: Double = 0.17
    /// The camera turns with the track this far ahead of the car...
    static let cameraHeadingAhead: Double = 140
    /// ...smoothed along the track over this length...
    static let cameraHeadingSmoothing: Double = 220
    /// ...and eased over this many seconds, so a hairpin swings the world around rather than snapping it.
    static let cameraTurnLag: Double = 0.16
    static let cameraZoomLag: Double = 0.6
    /// The camera sits on the centerline, pulled this share of the way toward the car, so the car visibly moves up and
    /// down the screen as you steer.
    static let cameraCarPull: Double = 0.25

    // MARK: Laps

    /// The car starts from rest this far before the start/finish line, so every timed lap is a flying lap.
    static let startDistanceBeforeLine: Double = 600
    /// Ghost laps keep this many samples a second.
    static let ghostSampleRate: Double = 30

    // MARK: Feedback

    /// Skid marks appear once `Car.scrub` passes this: the line is braking the car by about 1.5% or more.
    static let skidThreshold: Double = 0.12
    /// Shown speed (km/h) for each unit a second: top speed reads 330.
    static let displaySpeedFactor: Double = 330 / topSpeed

    // MARK: Rivals

    /// A rival is picked to beat your best lap by about this much: close enough to catch.
    static let rivalGap: Double = 0.4
    /// Other players' ghosts count as rivals when they beat your best by between these two margins.
    static let rivalWindow: ClosedRange<Double> = 0.15...0.8
    /// Before you've set a lap, the rival is a bot lapping in about this long.
    static let firstRivalTime: Double = 31

    // MARK: Versions

    /// The physics' version. Leaderboards are kept per version (`RaceBoard`), so a change that moves lap times (anything
    /// in `lapSignature`) must bump it once released. `FreezeTests` fails until the new signature is recorded.
    static let physicsVersion = 1

    /// Everything that changes how fast a lap can be: the track's shape and sampling, the car, the walls, the physics
    /// step, and the run-up to the first timed lap. Saved best laps are kept per version of these, so a retune starts a
    /// fresh best lap rather than comparing against laps from a different car.
    static var lapSignature: String {
        [trackWidth, sampleSpacing, curvatureSmoothing, steerRate, steerReturn, topSpeed, grip, straightnessLength,
         acceleration, accelerationFade, braking, minimumSpeed, carHalfWidth, wallBounce, wallScrub, wallKnock,
         wallKnockCooldown, physicsStep, startDistanceBeforeLine]
            .map { String(format: "%g", $0) }.joined(separator: ",")
    }
}
