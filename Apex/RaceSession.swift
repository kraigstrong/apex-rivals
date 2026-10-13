import Foundation

/// A race against the clock with no drawing: the car, its laps, and a fixed-step clock. `RaceScene` drives it from the
/// screen; tests and bots drive it directly.
final class RaceSession {
    enum Phase {
        /// On the grid, waiting for the first touch.
        case ready
        case racing
    }

    enum Event {
        case wallHit(CarPhysics.WallHit)
        case timing(LapTimer.Event)
    }

    let track: Track
    private(set) var car: Car
    private(set) var timer: LapTimer
    private(set) var phase: Phase = .ready
    /// Seconds of racing since the start.
    private(set) var clock: Double = 0
    /// Whether the player is touching the screen.
    var holding = false
    /// Walls touched since the current lap began (on the out lap, since the start).
    private(set) var wallHitsThisLap = 0
    /// Walls touched on the last finished lap.
    private(set) var wallHitsLastLap = 0
    private var leftover: Double = 0

    init(track: Track, best: LapRecord? = nil) {
        self.track = track
        car = Car(track: track)
        timer = LapTimer(track: track, best: best)
    }

    func start() {
        phase = .racing
    }

    /// Back to the grid; the best lap stays.
    func reset() {
        car = Car(track: track)
        timer.abandonLap()
        phase = .ready
        clock = 0
        leftover = 0
        holding = false
        wallHitsThisLap = 0
        wallHitsLastLap = 0
    }

    func forgetBest() {
        timer.forgetBest()
    }

    func replaceBest(with record: LapRecord?) {
        timer.replaceBest(with: record)
    }

    /// Runs `time` seconds of physics in fixed steps. `control`, if given, decides holding before every step (bots).
    @discardableResult
    func advance(by time: Double, control: ((RaceSession) -> Bool)? = nil) -> [Event] {
        guard phase == .racing else { return [] }
        let step = RaceTuning.physicsStep
        leftover += min(time, 0.1)
        var events: [Event] = []
        while leftover >= step {
            leftover -= step
            if let control { holding = control(self) }
            let before = car.progress(on: track)
            if let hit = CarPhysics.step(&car, holding: holding, dt: step, on: track) {
                events.append(.wallHit(hit))
                wallHitsThisLap += 1
            }
            clock += step
            let lapNumber = timer.lapNumber
            let timing = timer.update(from: before, to: car.progress(on: track), at: clock, step: step,
                                      sample: GhostSample(car))
            // Crossing the line starts a new count, so the out lap's hits don't land on the first timed lap.
            if timer.lapNumber != lapNumber {
                wallHitsLastLap = wallHitsThisLap
                wallHitsThisLap = 0
            }
            events += timing.map { .timing($0) }
        }
        return events
    }
}
