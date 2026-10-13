import SpriteKit
import UIKit

/// The race on screen. It turns touches into holding, runs the session, draws the car, its ghost and its skid marks,
/// and turns the camera with the track so the road ahead always runs left to right.
final class RaceScene: SKScene {
    let session: RaceSession
    let hud: RaceHUD
    let board: RaceBoard
    private var track: Track { session.track }
    private let scout: RivalScout
    private var rival: Rival?
    private var rivalNode: SKSpriteNode?
    /// Walls touched since the lap began, for the lap log.
    private var wallHitsThisLap = 0
    /// Laps finished this session, and the fastest of them.
    private var sessionLaps = 0
    private var sessionBest: Double?
    /// The best lap before this session, to tell whether the session set a new one.
    private var bestBeforeSession: Double?

    private let cameraNode = SKCameraNode()
    private let world = SKNode()
    private var pieces: [TrackPiece] = []
    private var grass: SKSpriteNode?
    private var car: SKSpriteNode?
    private var ghost: SKSpriteNode?
    private var skids: [SKSpriteNode] = []
    private var nextSkid = 0
    /// Distance driven since the last pair of skid marks.
    private var skidGap = 0.0
    private var racingLineNode: SKNode?
    private var buildingRacingLine = false
    private var holdTouches = Set<UITouch>()
    private var lastTime: TimeInterval?
    private var cameraAngle = 0.0
    private var viewWidth = RaceTuning.viewWidthSlow
    private var sinceHUD = 0.0
    private var built = false
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notice = UINotificationFeedbackGenerator()
    #if DEBUG
    /// Launch with `-ApexAutopilot perfect` to watch a bot drive the ideal line, or `-ApexAutopilot human` for one
    /// that reacts at human speed (so its laps differ and the ghost shows). Its laps are never saved.
    private var autopilot: AutoDriver?
    #endif

    init(track: Track, hud: RaceHUD) {
        session = RaceSession(track: track, best: LapStore.load(for: track))
        self.hud = hud
        board = RaceBoard(track: track)
        scout = RivalScout(track: track)
        super.init(size: CGSize(width: 874, height: 402))
        scaleMode = .resizeFill
        backgroundColor = TrackArt.grassColor
        hud.bestLap = session.timer.best?.time
        hud.onRestart = { [weak self] in self?.restart() }
        hud.onToggleRacingLine = { [weak self] in self?.toggleRacingLine() }
        hud.onForgetBest = { [weak self] in self?.forgetBest() }
        hud.onEndSession = { [weak self] in self?.endSession() }
        hud.onLeave = { [weak self] in self?.leave() }
        hud.onRaceAgain = { [weak self] in self?.hud.summary = nil }
        hud.onShowLeaderboard = { [weak self] in
            guard let self else { return }
            GameCenter.shared.showLeaderboard(board)
        }
        #if DEBUG
        if let mode = UserDefaults.standard.string(forKey: "ApexAutopilot") {
            let line = RacingLine(track: track)
            autopilot = mode == "human"
                ? AutoDriver(line: { line.offset(at: $0) }, decisionInterval: 0.09, hesitation: 0.05,
                             seed: UInt64(Date().timeIntervalSince1970))
                : AutoDriver(line: { line.offset(at: $0) })
        }
        #endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        guard !built else { return }
        built = true

        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        pieces = TrackArt.circuit(track)
        pieces.forEach { world.addChild($0.node) }

        let grass = TrackArt.grass(size: size)
        cameraNode.addChild(grass)
        self.grass = grass

        let car = TrackArt.carSprite(in: view)
        car.zPosition = TrackArt.Depth.car
        world.addChild(car)
        self.car = car

        let ghost = TrackArt.carSprite(in: view, livery: SKColor(red: 0.25, green: 0.75, blue: 1, alpha: 1))
        ghost.alpha = 0.45
        ghost.zPosition = TrackArt.Depth.ghost
        ghost.isHidden = true
        world.addChild(ghost)
        self.ghost = ghost

        let rivalNode = TrackArt.carSprite(in: view, livery: SKColor(red: 1, green: 0.76, blue: 0.1, alpha: 1))
        rivalNode.alpha = 0.5
        rivalNode.zPosition = TrackArt.Depth.ghost
        rivalNode.isHidden = true
        world.addChild(rivalNode)
        self.rivalNode = rivalNode
        findRival()

        skids = (0..<400).map { _ in
            let mark = SKSpriteNode(color: SKColor(white: 0.06, alpha: 1), size: CGSize(width: 7, height: 2.6))
            mark.zPosition = TrackArt.Depth.skids
            mark.isHidden = true
            world.addChild(mark)
            return mark
        }

        impact.prepare()
        placeCamera(dt: 0, snap: true)
        render(dt: 0)
        refreshHUD()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        grass?.size = size
        if built { placeCamera(dt: 0, snap: true) }
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(max(currentTime - $0, 0), 1.0 / 15) } ?? 0
        lastTime = currentTime
        session.holding = !holdTouches.isEmpty
        var control: ((RaceSession) -> Bool)?
        #if DEBUG
        if autopilot != nil {
            if session.phase == .ready { session.start() }
            control = { [unowned self] in self.autopilot?.decide($0) ?? false }
        }
        #endif
        let events = session.advance(by: dt, control: control)
        events.forEach(handle)
        render(dt: dt)
        placeCamera(dt: dt, snap: false)
        sinceHUD += dt
        if sinceHUD >= 1.0 / 20 || !events.isEmpty {
            sinceHUD = 0
            refreshHUD()
        }
    }

    private func render(dt: Double) {
        let state = session.car
        let position = state.position(on: track)
        let heading = state.heading(on: track)
        car?.position = position
        car?.zRotation = CGFloat(heading)

        if let best = session.timer.best, let lapTime = session.timer.lapTime(at: session.clock),
           let pose = best.ghostPose(at: lapTime, trackLength: track.length) {
            ghost?.isHidden = false
            ghost?.position = track.point(s: Double(pose.s), n: Double(pose.n))
            ghost?.zRotation = CGFloat(track.heading(at: Double(pose.s)) + Double(pose.psi))
        } else {
            ghost?.isHidden = true
        }

        if let rival, let lapTime = session.timer.lapTime(at: session.clock),
           let pose = rival.record.ghostPose(at: lapTime, trackLength: track.length) {
            rivalNode?.isHidden = false
            rivalNode?.position = track.point(s: Double(pose.s), n: Double(pose.n))
            rivalNode?.zRotation = CGFloat(track.heading(at: Double(pose.s)) + Double(pose.psi))
        } else {
            rivalNode?.isHidden = true
        }

        // Skid marks behind the rear wheels whenever the line is costing speed.
        skidGap += state.speed * dt
        if state.scrub > RaceTuning.skidThreshold, skidGap >= 5, !skids.isEmpty {
            skidGap = 0
            let alpha = CGFloat(0.12 + 0.5 * min(1, state.scrub))
            for side in [-1.0, 1.0] {
                let mark = skids[nextSkid]
                nextSkid = (nextSkid + 1) % skids.count
                mark.removeAllActions()
                mark.position = CGPoint(x: position.x + cos(heading) * -11 - sin(heading) * 5.6 * side,
                                        y: position.y + sin(heading) * -11 + cos(heading) * 5.6 * side)
                mark.zRotation = CGFloat(heading)
                mark.alpha = alpha
                mark.isHidden = false
                mark.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 2.5), .hide()]))
            }
        } else {
            skidGap = min(skidGap, 5)
        }
    }

    /// Keeps the road ahead running left to right: the camera turns with the track a little ahead of the car, sits on
    /// the centerline (pulled partway toward the car, so steering shows as the car moving up and down the screen), leads
    /// the car so it sits left of center, and widens the view with speed.
    private func placeCamera(dt: Double, snap: Bool) {
        let tuning = RaceTuning.self
        let state = session.car
        let target = track.cameraHeading(at: state.s + tuning.cameraHeadingAhead)
        let turn = (target - cameraAngle).remainder(dividingBy: 2 * .pi)
        cameraAngle += snap ? turn : turn * (1 - exp(-dt / tuning.cameraTurnLag))

        let wanted = tuning.viewWidthSlow
            + (tuning.viewWidthFast - tuning.viewWidthSlow) * min(1, state.speed / tuning.topSpeed)
        viewWidth += snap ? wanted - viewWidth : (wanted - viewWidth) * (1 - exp(-dt / tuning.cameraZoomLag))

        guard size.width > 0, size.height > 0 else { return }
        let scale = max(viewWidth / size.width, tuning.minimumViewHeight / size.height)
        let center = track.centerline(at: state.s)
        let carPoint = state.position(on: track)
        let lead = size.width * scale * tuning.cameraLead
        let position = CGPoint(
            x: center.x + (carPoint.x - center.x) * tuning.cameraCarPull + cos(cameraAngle) * lead,
            y: center.y + (carPoint.y - center.y) * tuning.cameraCarPull + sin(cameraAngle) * lead)
        cameraNode.position = position
        cameraNode.zRotation = CGFloat(cameraAngle)
        cameraNode.setScale(scale)

        // Draw only the pieces of track within reach of the screen, however it's turned.
        let reach = hypot(size.width, size.height) * scale / 2
        for piece in pieces {
            let dx = max(piece.frame.minX - position.x, 0, position.x - piece.frame.maxX)
            let dy = max(piece.frame.minY - position.y, 0, position.y - piece.frame.maxY)
            piece.node.isHidden = dx * dx + dy * dy > reach * reach
        }
        if let grass {
            TrackArt.aimGrass(grass, center: position, angle: CGFloat(cameraAngle),
                              worldSpan: CGSize(width: size.width * scale, height: size.height * scale))
        }
    }

    // MARK: Events

    private func handle(_ event: RaceSession.Event) {
        switch event {
        case .wallHit(let hit):
            wallHitsThisLap += 1
            impact.impactOccurred(intensity: CGFloat(hit.severity))
            sparks(hit)
        case .timing(.sector(let split)):
            if let delta = split.delta {
                hud.show("S\(split.sector)", LapFormat.delta(delta), tone: delta < 0 ? .faster : .slower)
            } else {
                hud.show("S\(split.sector)", LapFormat.time(split.time), tone: .neutral)
            }
        case .timing(.lap(let lap)):
            hud.lastLap = lap.time
            if let record = session.timer.lastRecord, !isAutopilot {
                LapLog.shared.record(LapEntry(lap: record, board: board, walls: wallHitsThisLap))
            }
            wallHitsThisLap = 0
            sessionLaps += 1
            sessionBest = min(sessionBest ?? .infinity, lap.time)
            let beatRival = rival.map { lap.time < $0.time } ?? false
            if lap.isBest {
                hud.bestLap = lap.time
                if let best = session.timer.best, !isAutopilot {
                    LapStore.save(best, for: track)
                    GameCenter.shared.submit(best.time, on: board)
                    ApexService.shareBest(best, on: board)
                }
                let detail = beatRival ? "BEAT \(rival?.name.uppercased() ?? "RIVAL")"
                    : lap.delta.map { "BEST " + LapFormat.delta($0) } ?? "BEST"
                hud.show("LAP \(lap.number)", LapFormat.time(lap.time), detail: detail, tone: .best)
                notice.notificationOccurred(.success)
                // Chase someone new once this rival is beaten or barely ahead.
                if rival.map({ $0.time > lap.time - RaceTuning.rivalWindow.lowerBound }) ?? true { findRival() }
            } else {
                hud.show("LAP \(lap.number)", LapFormat.time(lap.time), detail: lap.delta.map { LapFormat.delta($0) },
                         tone: .slower)
            }
        }
    }

    private func sparks(_ hit: CarPhysics.WallHit) {
        let state = session.car
        let heading = track.heading(at: state.s)
        let contact = track.point(s: state.s, n: hit.side * track.width / 2)
        for _ in 0..<(4 + Int(hit.severity * 8)) {
            let spark = SKSpriteNode(color: SKColor(red: 1, green: .random(in: 0.55...0.9), blue: 0.2, alpha: 1),
                                     size: CGSize(width: 3, height: 3))
            spark.position = contact
            spark.zPosition = TrackArt.Depth.sparks
            spark.blendMode = .add
            world.addChild(spark)
            // Carried along with the car a little, and thrown off the wall.
            let forward = state.speed * .random(in: 0.08...0.2)
            let off = -hit.side * .random(in: 10...45)
            let duration = 0.35
            spark.run(.sequence([
                .group([
                    .moveBy(x: cos(heading) * forward - sin(heading) * off,
                            y: sin(heading) * forward + cos(heading) * off, duration: duration),
                    .fadeOut(withDuration: duration),
                    .scale(to: 0.3, duration: duration),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func findRival() {
        scout.find(beating: session.timer.best?.time) { [weak self] rival in
            guard let self else { return }
            self.rival = rival
            hud.rivalName = rival?.name
            hud.rivalTime = rival?.time
        }
    }

    private func refreshHUD() {
        let state = session.car
        hud.racing = session.phase == .racing
        hud.lapNumber = session.timer.lapNumber
        hud.lapTime = session.timer.lapTime(at: session.clock)
        hud.liveDelta = session.timer.liveDelta(at: session.clock, distance: state.s)
        hud.speed = state.speed
        hud.lineSpeed = state.lineSpeed
        hud.scrub = state.scrub
        hud.carMarker = hud.mapPoint(state.position(on: track))
        if let ghost, !ghost.isHidden {
            hud.ghostMarker = hud.mapPoint(ghost.position)
        } else {
            hud.ghostMarker = nil
        }
        if let rivalNode, !rivalNode.isHidden {
            hud.rivalMarker = hud.mapPoint(rivalNode.position)
        } else {
            hud.rivalMarker = nil
        }
    }

    // MARK: Controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The session summary is up: touches are for its button, not the car.
        guard hud.summary == nil else { return }
        holdTouches.formUnion(touches)
        if session.phase == .ready {
            if sessionLaps == 0 { bestBeforeSession = session.timer.best?.time }
            session.start()
            refreshHUD()
        }
    }

    /// Heading back to the track list: a session with a finished lap gets its summary first (which offers the tracks),
    /// and one without goes straight there.
    func leave() {
        if sessionLaps > 0 {
            endSession()
        } else {
            hud.onExit()
        }
    }

    /// Ends the session: back to the grid, with a summary of its best lap and where that lap falls among other
    /// players. A session with no finished laps just goes back to the grid.
    func endSession() {
        guard hud.summary == nil else { return }
        defer {
            sessionLaps = 0
            sessionBest = nil
            restart()
        }
        guard let best = sessionBest, sessionLaps > 0 else { return }
        let personalBest = session.timer.best?.time
        hud.summary = SessionSummary(trackName: track.layout.name, laps: sessionLaps, best: best,
                                     personalBest: personalBest,
                                     isPersonalBest: bestBeforeSession.map { best < $0 } ?? true)
        hud.standing = .loading
        if ApexOnline.isEnabled {
            ApexService.standing(of: best, on: board) { [weak self] standing in
                DispatchQueue.main.async {
                    self?.hud.standing = standing.map { .ready($0, sample: false) } ?? .unavailable
                }
            }
        } else {
            #if DEBUG
            hud.standing = .ready(.sample(for: Int((best * 1000).rounded())), sample: true)
            #else
            hud.standing = .unavailable
            #endif
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
    }

    /// Back to the grid. The best lap and its ghost stay.
    func restart() {
        session.reset()
        holdTouches.removeAll()
        wallHitsThisLap = 0
        for mark in skids {
            mark.removeAllActions()
            mark.isHidden = true
        }
        hud.banner = nil
        placeCamera(dt: 0, snap: true)
        render(dt: 0)
        refreshHUD()
    }

    private func toggleRacingLine() {
        hud.showsRacingLine.toggle()
        if let racingLineNode {
            racingLineNode.isHidden = !hud.showsRacingLine
            return
        }
        guard hud.showsRacingLine, !buildingRacingLine else { return }
        buildingRacingLine = true
        let track = self.track
        DispatchQueue.global(qos: .userInitiated).async {
            let line = RacingLine(track: track)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let node = TrackArt.racingLine(line, on: track)
                node.isHidden = !self.hud.showsRacingLine
                self.world.addChild(node)
                self.racingLineNode = node
                self.buildingRacingLine = false
            }
        }
    }

    private var isAutopilot: Bool {
        #if DEBUG
        return autopilot != nil
        #else
        return false
        #endif
    }

    private func forgetBest() {
        LapStore.clear(for: track)
        session.forgetBest()
        hud.bestLap = nil
        ghost?.isHidden = true
        findRival()
    }
}
