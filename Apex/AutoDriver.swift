import Foundation

/// Drives with the player's only control, holding or letting go, to follow a line across the track. Tests use it to
/// check how long laps take: a perfect driver decides every physics step, a human-like one every tenth of a second or so.
struct AutoDriver {
    /// The offset to aim for at each distance along the lap.
    var line: (Double) -> Double
    /// How far ahead (seconds) it predicts the car's offset before deciding.
    var lookAhead: Double = 0.12
    /// Seconds between decisions; 0 decides every physics step.
    var decisionInterval: Double = 0
    /// Lets misses smaller than this (units) ride, so it weaves more.
    var tolerance: Double = 0
    /// Up to this many extra seconds before each next decision, at random.
    var hesitation: Double = 0
    private var holding = false
    private var nextDecision = 0.0
    private var random: SplitMix64

    init(line: @escaping (Double) -> Double, lookAhead: Double = 0.12, decisionInterval: Double = 0,
         tolerance: Double = 0, hesitation: Double = 0, seed: UInt64 = 1) {
        self.line = line
        self.lookAhead = lookAhead
        self.decisionInterval = decisionInterval
        self.tolerance = tolerance
        self.hesitation = hesitation
        random = SplitMix64(seed: seed)
    }

    mutating func decide(_ session: RaceSession) -> Bool {
        let car = session.car
        guard session.clock >= nextDecision else { return holding }
        let predicted = car.n + car.speed * sin(car.psi) * lookAhead
        let miss = line(car.s + car.speed * lookAhead) - predicted
        if abs(miss) > tolerance { holding = miss > 0 }
        nextDecision = session.clock + decisionInterval + random.unit() * hesitation
        return holding
    }
}

/// A tiny seeded random source, so bot laps repeat exactly.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
