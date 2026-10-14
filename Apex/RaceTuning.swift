import Foundation

/// Every feel constant in one place. The handful the Xcode-only tuning panel (`Tuner`) can change live are `var`s;
/// Release builds never change them. Distances are world units (the car is 34 long, the track 120 wide wall to wall);
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
    static var steerRate: Double = 2.4
    /// Pulls the nose back toward the track's direction (per second). Holding settles at `steerRate / steerReturn` radians.
    static var steerReturn: Double = 4.0

    // MARK: Speed

    static let topSpeed: Double = 500
    /// The fastest a car can follow a path of curvature κ is √(grip / κ), so straighter is faster.
    static var grip: Double = 480
    /// The car's heading is smoothed over this distance before its curvature sets the speed. Quick, small corrections
    /// mostly cancel out; slower weaves and corners don't.
    static var straightnessLength: Double = 90
    static var acceleration: Double = 280
    /// Acceleration fades by this share as the car nears top speed.
    static let accelerationFade: Double = 0.55
    /// How quickly speed drops to what the line allows.
    static let braking: Double = 1500
    /// However badly a lap goes, the car never drops below this speed once it's rolling.
    static let minimumSpeed: Double = 110

    /// The steering and speed constants the tuning panel changes, taken together, so a bot can drive a car tuned
    /// differently from the one on screen.
    struct Handling: Equatable {
        var steerRate: Double
        var steerReturn: Double
        var grip: Double
        var straightnessLength: Double
        var acceleration: Double

        static var current: Handling {
            Handling(steerRate: RaceTuning.steerRate, steerReturn: RaceTuning.steerReturn, grip: RaceTuning.grip,
                     straightnessLength: RaceTuning.straightnessLength, acceleration: RaceTuning.acceleration)
        }
    }

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
    /// The camera turns with the track this far ahead of the car... Its smoothing and easing make it trail the road a
    /// little; this cancels that out, so through corners the screen stays square to the road under the car and "hold"
    /// keeps meaning "up". At 140 the camera ran ahead: tilted over 10° from the road for a fifth to a third of a lap,
    /// up to 41°. At 80, over 10° for 2–6% of a lap, at most 18°. Only how the race is drawn: not in `lapSignature`.
    static var cameraHeadingAhead: Double = 80
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

    // MARK: Scenery

    // Only how the race looks: none of these are in `lapSignature`.
    /// Trees start this far beyond the wall...
    static let treeClearance = 40.0
    /// ...and grow up to this far from it, about as far as the camera sees.
    static let treeReach = 470.0
    static let treeSpacing = 62.0
    static let grandstandDepth = 76.0
    /// A gap between the wall and a grandstand's front.
    static let grandstandGap = 26.0
    /// Corners tighter than this radius get a tire wall on the outside.
    static let tireWallRadius = 330.0
    static let tireRadius = 7.5
    /// Groves: trees grow where a smooth noise over this many units is above the threshold, leaving clearings.
    static let groveScale = 340.0
    static let groveThreshold = 0.44
    static let treeRadius: ClosedRange<Double> = 20...38
    // MARK: Sound

    // Tuned in the Apex Sound Lab. Only how the race sounds: none of these are in `lapSignature`.
    static let soundMaster = 0.7
    static let engineLevel = 0.55
    /// The engine's pitch (Hz), from idle to the limiter.
    static let enginePitch: ClosedRange<Double> = 90...620
    static let engineBrightness = 0.45
    static let tireLevel = 0.5
    static let tireHissPitch = 1800.0
    static let tireSqueal = 0.25
    static let curbLevel = 0.45
    static let wallLevel = 0.7
    static let cueLevel = 0.5
    static let musicLevel = 0.35
    static let musicTempo = 112.0
    /// The top speed (km/h) in each of the engine's eight gears.
    static let gearTopSpeeds: [Double] = [95, 135, 170, 205, 240, 272, 302, 335]

    // MARK: Rivals

    /// A rival is picked to beat your best lap by about this much: close enough to catch.
    static let rivalGap: Double = 0.4
    /// Other players' ghosts count as rivals when they beat your best by between these two margins.
    static let rivalWindow: ClosedRange<Double> = 0.15...0.8
    /// Before you've set a lap, the rival is a bot lapping in about this long.
    static let firstRivalTime: Double = 31

    // MARK: Medals

    /// Each circuit's medal times in seconds: bronze, silver, gold and platinum. Each is a bot's lap there, rounded to
    /// the tenth: a sloppy weaver, the middle of the road at human reaction speed (90 ms), the ideal line at 90 ms, and
    /// the ideal line at 50 ms. `LapTimeTests` holds them to the bots, so a change that moves lap times moves these
    /// too. They don't change how fast a lap can be, so they aren't in `lapSignature`.
    static let medalTimes: [String: [Double]] = [
        "ardennes": [35.8, 29.8, 28.5, 26.6],
        "swirl": [35.5, 30.2, 28.9, 26.7],
        "snake": [34.6, 30.0, 28.5, 26.3],
        "mirage": [36.2, 30.0, 28.7, 27.0],
        "island": [36.7, 29.7, 28.8, 27.1],
        "harbor": [34.7, 30.0, 27.7, 25.7],
    ]

    // MARK: Versions

    /// The physics' version. Leaderboards are kept per version (`RaceBoard`), so a change that moves lap times (anything
    /// in `lapSignature`) must bump it once released. `FreezeTests` fails until the new signature is recorded.
    static let physicsVersion = 1
    /// `lapSignature`'s fingerprint for `physicsVersion`. `FreezeTests` checks the stock car matches it.
    static let physicsFingerprint = "93a7f30b1b41fad9"

    /// Whether the car is as released (no tuning-panel changes). Only stock laps reach leaderboards and the lap
    /// service, so a tuned car can't put times on a board it doesn't belong to.
    static var isStock: Bool { LapStore.fingerprint(lapSignature) == physicsFingerprint }

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
