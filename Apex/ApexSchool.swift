import Foundation

extension TrackLayout {
    /// The practice circuit for Apex School: a rounded square of four identical right-hand corners. The straights are
    /// long enough (about five seconds on the outside at full speed) to settle and line up before the next corner comes.
    /// Not a race circuit: no leaderboard.
    static let apexSchool = TrackLayout(
        id: "apex_school",
        revision: 1,
        name: "Apex School",
        summary: "Learn the line on one right-angle corner, four times a lap: turn in, clip the apex, run out wide.",
        segments: [
            .straight(3000), .corner(radius: 240, degrees: -90),
            .straight(3000), .corner(radius: 240, degrees: -90),
            .straight(3000), .corner(radius: 240, degrees: -90),
            .straight(3000), .corner(radius: 240, degrees: -90),
        ],
        closingStraights: (0, 2),
        // The grid (`RaceTuning.startDistanceBeforeLine` before the line) is mid-straight, well clear of the corners.
        startLine: 2100,
        sectorStarts: [2, 4]
    )

    var isPractice: Bool { id == TrackLayout.apexSchool.id }
}

/// Where the ideal line turns in, clips the apex and runs out wide at each corner, and what to tell the driver.
struct ApexGuide {
    struct Corner: Equatable {
        /// +1 for a left-hander (its inside is the top of the screen), −1 for a right-hander.
        var side: Double
        /// Distances along the lap. `apex` follows `turnIn`, and `exit` follows `apex`, going round (they can wrap).
        var turnIn: Double
        var apex: Double
        var exit: Double
        /// The slowest the ideal line, driven perfectly, goes through the corner.
        var idealSpeed: Double = 0
    }

    /// Where the car is relative to a corner.
    enum Phase: Equatable {
        /// Approaching: stay on the outside.
        case lineUp
        /// Turned in, heading for the apex.
        case turnIn
        /// Past the apex, running out to the exit.
        case runOut
    }

    let line: RacingLine
    private(set) var corners: [Corner]
    let trackLength: Double
    /// How far the car's center can go from the centerline: the line is "on the inside" within a few units of it.
    let reach: Double

    init(track: Track, line: RacingLine) {
        self.line = line
        trackLength = track.length
        reach = track.width / 2 - RaceTuning.carHalfWidth
        let step = 4.0
        let count = Int(track.length / step)
        let bending = (0..<count).map { abs(track.curvature(at: Double($0) * step)) > 1 / 1500 }
        // Start the scan on a straight, so no corner is split across the end of the array.
        guard let straight = bending.firstIndex(of: false) else {
            corners = []
            return
        }
        var found: [Corner] = []
        var i = 0
        while i < count {
            let k = (straight + i) % count
            guard bending[k] else {
                i += 1
                continue
            }
            var j = i
            while j < count, bending[(straight + j) % count] { j += 1 }
            let first = Double(straight + i) * step, last = Double(straight + j) * step
            let middle = (first + last) / 2
            let side: Double = track.curvature(at: middle) > 0 ? 1 : -1
            found.append(ApexGuide.corner(around: first, last, side: side, line: line, reach: reach,
                                          length: track.length))
            i = j
        }
        corners = found
    }

    private static func corner(around first: Double, _ last: Double, side: Double, line: RacingLine, reach: Double,
                               length: Double) -> Corner {
        func inside(_ s: Double) -> Double { line.offset(at: s) * side }
        // The apex: where the line comes closest to the inside, around the bend.
        var apex = first, best = -Double.infinity
        for s in stride(from: first - 300, through: last + 300, by: 2) where inside(s) > best {
            best = inside(s)
            apex = s
        }
        // Turn-in and exit: where the line clearly leaves, and comes back to, the outside. (The line runs up to 8 inside
        // the car's reach; it drifts a unit or two off it long before the real turn-in.)
        let outside = -(reach - 14)
        var turnIn = apex
        while turnIn > apex - 1500, inside(turnIn) > outside { turnIn -= 4 }
        var exit = apex
        while exit < apex + 1500, inside(exit) > outside { exit += 4 }
        func wrap(_ s: Double) -> Double { (s.truncatingRemainder(dividingBy: length) + length).truncatingRemainder(dividingBy: length) }
        return Corner(side: side, turnIn: wrap(turnIn), apex: wrap(apex), exit: wrap(exit))
    }

    /// Distance from `a` forward to `b` along the lap.
    func ahead(from a: Double, to b: Double) -> Double {
        let d = (b - a).truncatingRemainder(dividingBy: trackLength)
        return d < 0 ? d + trackLength : d
    }

    /// The corner the car is in or coming to, and where it is relative to it.
    func situation(at s: Double) -> (corner: Corner, phase: Phase)? {
        guard !corners.isEmpty else { return nil }
        for corner in corners {
            let toExit = ahead(from: s, to: corner.exit)
            let span = ahead(from: corner.turnIn, to: corner.exit)
            guard toExit <= span else { continue }
            let sinceTurnIn = ahead(from: corner.turnIn, to: s)
            return (corner, sinceTurnIn < ahead(from: corner.turnIn, to: corner.apex) ? .turnIn : .runOut)
        }
        let next = corners.min { ahead(from: s, to: $0.turnIn) < ahead(from: s, to: $1.turnIn) }!
        return (next, .lineUp)
    }

    /// The coach's cue for where the car is. It changes only three times a corner: the rhythm of a corner is two
    /// moments, turning in toward the apex and then easing back out from it; the painted line covers the fine control.
    static func prompt(_ phase: Phase, side: Double) -> (title: String, detail: String) {
        // On screen, a left-hander's inside is the top and a right-hander's the bottom. Holding moves the car up.
        let outside = side > 0 ? "bottom" : "top"
        let inside = side > 0 ? "top" : "bottom"
        let towardInside = side > 0 ? "HOLD" : "LET GO"
        let towardOutside = side > 0 ? "LET GO" : "HOLD"
        switch phase {
        case .lineUp:
            return ("STAY WIDE", "Keep to the \(outside). At TURN IN, \(towardInside.lowercased()).")
        case .turnIn:
            return (towardInside, "Turn in: aim for the APEX on the \(inside) kerb.")
        case .runOut:
            return (towardOutside, "Past the apex: ease back out to the \(outside).")
        }
    }

    /// The slowest speed through each corner when the ideal line is driven perfectly, from one bot lap.
    func withIdealSpeeds(on track: Track) -> ApexGuide {
        let session = RaceSession(track: track)
        var driver = AutoDriver(line: { line.offset(at: $0) })
        session.start()
        var slowest = [Double](repeating: .infinity, count: corners.count)
        var laps = 0
        while laps < 2, session.clock < 120 {
            for event in session.advance(by: RaceTuning.physicsStep, control: { driver.decide($0) }) {
                if case .timing(.lap) = event { laps += 1 }
            }
            guard laps == 1 else { continue }
            for (index, corner) in corners.enumerated()
            where ahead(from: corner.turnIn, to: session.car.s) <= ahead(from: corner.turnIn, to: corner.exit) {
                slowest[index] = min(slowest[index], session.car.speed)
            }
        }
        var guide = self
        guide.corners = zip(corners, slowest).map { corner, speed in
            var corner = corner
            corner.idealSpeed = speed.isFinite ? speed : 0
            return corner
        }
        return guide
    }
}

/// Watches the car through each corner and judges it: how close it came to the apex, and the slowest it went.
struct CornerJudge {
    struct Verdict: Equatable {
        /// How far wide of the ideal line's apex the car passed (units): 0 is right on it, or inside it.
        var apexGap: Double
        var slowest: Double
        var idealSpeed: Double

        var hitApex: Bool { apexGap <= 12 }
        var closeToApex: Bool { apexGap <= 30 }
    }

    private var inCorner: Int?
    /// Whether the car came into this corner before its apex (it didn't if it started past it).
    private var enteredBeforeApex = false
    private var apexGap: Double?
    private var slowest = Double.infinity

    /// Call every physics step; returns a verdict as the car leaves a corner.
    mutating func update(car: Car, guide: ApexGuide) -> Verdict? {
        let index = guide.corners.firstIndex { corner in
            guide.ahead(from: corner.turnIn, to: car.s) <= guide.ahead(from: corner.turnIn, to: corner.exit)
        }
        if let current = inCorner, index != current {
            // Left the corner: judge it.
            let corner = guide.corners[current]
            defer { reset() }
            guard let gap = apexGap, enteredBeforeApex else { return nil }
            return Verdict(apexGap: gap, slowest: slowest, idealSpeed: corner.idealSpeed)
        }
        guard let index else { return nil }
        let corner = guide.corners[index]
        if inCorner == nil {
            reset()
            enteredBeforeApex = guide.ahead(from: corner.turnIn, to: car.s) < guide.ahead(from: corner.turnIn, to: corner.apex)
        }
        inCorner = index
        slowest = min(slowest, car.speed)
        if apexGap == nil, guide.ahead(from: corner.apex, to: car.s) < guide.ahead(from: corner.turnIn, to: corner.apex) {
            // Just passed the apex: how far wide of the ideal line's apex.
            apexGap = max(0, guide.line.offset(at: corner.apex) * corner.side - car.n * corner.side)
        }
        return nil
    }

    private mutating func reset() {
        inCorner = nil
        enteredBeforeApex = false
        apexGap = nil
        slowest = .infinity
    }
}
