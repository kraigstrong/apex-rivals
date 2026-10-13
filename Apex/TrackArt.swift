import SpriteKit

/// A stretch of the drawn circuit and the world-space box it covers.
struct TrackPiece {
    let node: SKNode
    let frame: CGRect
}

/// Procedural artwork: the circuit, the car, and the grass. Everything is drawn from code; there are no image assets.
enum TrackArt {
    /// Draw order. The SpriteView ignores sibling order, so anything that overlaps needs its own depth.
    enum Depth {
        static let grass: CGFloat = -100
        static let asphalt: CGFloat = 2
        static let kerbs: CGFloat = 3
        static let paint: CGFloat = 4
        static let walls: CGFloat = 5
        static let skids: CGFloat = 6
        static let racingLine: CGFloat = 7
        static let trail: CGFloat = 7.5
        static let markers: CGFloat = 8
        static let ghost: CGFloat = 9
        static let car: CGFloat = 10
        static let sparks: CGFloat = 11
    }

    static let asphalt = SKColor(red: 0.27, green: 0.28, blue: 0.30, alpha: 1)
    static let grassColor = SKColor(red: 0.30, green: 0.52, blue: 0.26, alpha: 1)
    static let kerbRed = SKColor(red: 0.86, green: 0.13, blue: 0.13, alpha: 1)
    static let kerbWhite = SKColor(white: 0.96, alpha: 1)
    static let wall = SKColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1)
    static let livery = SKColor(red: 0.90, green: 0.12, blue: 0.10, alpha: 1)

    /// Length of track in each drawn piece. Pieces off screen are culled.
    private static let chunkLength = 240.0
    /// Samples between the points of a drawn edge.
    private static let edgeStep = 3
    private static let kerbWidth = 12.0
    private static let kerbBlock = 20.0
    /// The white line's offset in from each wall.
    private static let lineInset = 15.0

    // MARK: The circuit

    /// The circuit in pieces of `chunkLength`, each with its own asphalt, paint, walls and kerbs. SpriteKit doesn't
    /// cull these shapes on its own, so the scene hides the pieces the camera can't see (`TrackPiece.frame`).
    static func circuit(_ track: Track) -> [TrackPiece] {
        let half = track.width / 2
        let samples = max(1, Int(chunkLength / track.spacing))
        let kerbThreshold = 1 / RaceTuning.kerbRadius
        var pieces: [TrackPiece] = []

        var start = 0
        while start < track.count {
            let end = min(start + samples, track.count)
            let piece = SKNode()
            // Each piece reaches one edge step into the next, so no seam shows between them.
            let indices = Array(stride(from: start, through: end + edgeStep, by: edgeStep))

            let surface = CGMutablePath()
            surface.addLines(between: indices.map { track.point(sample: $0, n: half + 2) }
                + indices.reversed().map { track.point(sample: $0, n: -half - 2) })
            surface.closeSubpath()
            piece.addChild(shape(surface, fill: asphalt, depth: Depth.asphalt))

            let paint = CGMutablePath()
            let walls = CGMutablePath()
            for side in [1.0, -1.0] {
                paint.addLines(between: indices.map { track.point(sample: $0, n: side * (half - lineInset)) })
                walls.addLines(between: indices.map { track.point(sample: $0, n: side * (half + 3)) })
            }
            piece.addChild(shape(paint, stroke: SKColor(white: 1, alpha: 0.85), width: 2.5, depth: Depth.paint))
            piece.addChild(shape(walls, stroke: wall, width: 6, depth: Depth.walls))

            // Red and white kerb blocks along both edges wherever the track is cornering.
            let red = CGMutablePath(), white = CGMutablePath()
            let firstBlock = Int((Double(start) * track.spacing / kerbBlock).rounded(.up))
            var block = firstBlock
            while Double(block) * kerbBlock < Double(end) * track.spacing {
                let s0 = Double(block) * kerbBlock
                if abs(track.curvature(at: s0 + kerbBlock / 2)) > kerbThreshold {
                    let along = Array(stride(from: s0, through: s0 + kerbBlock, by: 5))
                    for side in [1.0, -1.0] {
                        let outer = along.map { track.point(s: $0, n: side * half) }
                        let inner = along.reversed().map { track.point(s: $0, n: side * (half - kerbWidth)) }
                        let path = block % 2 == 0 ? red : white
                        path.addLines(between: outer + inner)
                        path.closeSubpath()
                    }
                }
                block += 1
            }
            if !red.isEmpty { piece.addChild(shape(red, fill: kerbRed, depth: Depth.kerbs)) }
            if !white.isEmpty { piece.addChild(shape(white, fill: kerbWhite, depth: Depth.kerbs)) }

            if start == 0 { piece.addChild(startLine(track)) }
            pieces.append(TrackPiece(node: piece, frame: piece.calculateAccumulatedFrame()))
            start = end
        }
        return pieces
    }

    /// A chequered band across the track at s = 0.
    private static func startLine(_ track: Track) -> SKNode {
        let node = SKNode()
        let half = track.width / 2
        let columns = 12, rows = 2
        let across = track.width / Double(columns), along = 7.0
        let black = CGMutablePath(), white = CGMutablePath()
        for row in 0..<rows {
            for column in 0..<columns {
                let s0 = Double(row) * along, n0 = -half + Double(column) * across
                let corners = [
                    track.point(s: s0, n: n0), track.point(s: s0 + along, n: n0),
                    track.point(s: s0 + along, n: n0 + across), track.point(s: s0, n: n0 + across),
                ]
                let path = (row + column) % 2 == 0 ? black : white
                path.addLines(between: corners)
                path.closeSubpath()
            }
        }
        node.addChild(shape(white, fill: kerbWhite, depth: Depth.paint))
        node.addChild(shape(black, fill: SKColor(white: 0.1, alpha: 1), depth: Depth.paint))
        return node
    }

    /// The racing line drawn along the track (Xcode builds).
    static func racingLine(_ line: RacingLine, on track: Track) -> SKNode {
        let path = CGMutablePath()
        let points = line.offsets.indices.map { i -> CGPoint in
            let s = Double(i) * line.spacing
            return track.point(s: s, n: line.offsets[i])
        }
        path.addLines(between: points)
        path.closeSubpath()
        return shape(path, stroke: SKColor(red: 1, green: 0.82, blue: 0.1, alpha: 0.6), width: 3, depth: Depth.racingLine)
    }

    /// Apex School's markers at every corner: where to turn in, the apex on the ideal line, and the exit, each with a
    /// board on the grass beside it.
    static func apexMarkers(_ guide: ApexGuide, on track: Track) -> SKNode {
        let node = SKNode()
        let half = track.width / 2
        let blue = SKColor(red: 0.35, green: 0.65, blue: 1, alpha: 0.95)
        let yellow = SKColor(red: 1, green: 0.82, blue: 0.1, alpha: 1)
        func bar(at s: Double, from n0: Double, to n1: Double, color: SKColor) {
            let path = CGMutablePath()
            path.addLines(between: [track.point(s: s, n: n0), track.point(s: s, n: n1)])
            node.addChild(shape(path, stroke: color, width: 5, depth: Depth.markers))
        }
        func board(_ text: String, at s: Double, n: Double, color: SKColor) {
            let label = SKLabelNode(text: text)
            label.fontName = "AvenirNext-Heavy"
            label.fontSize = 17
            label.fontColor = color
            label.verticalAlignmentMode = .center
            label.position = track.point(s: s, n: n)
            label.zRotation = CGFloat(track.heading(at: s))
            label.zPosition = Depth.markers
            node.addChild(label)
        }
        for corner in guide.corners {
            let outside = -corner.side
            bar(at: corner.turnIn, from: outside * half, to: outside * (half - 46), color: blue)
            board("TURN IN", at: corner.turnIn, n: outside * (half + 24), color: blue)
            let apex = track.point(s: corner.apex, n: guide.line.offset(at: corner.apex))
            let disc = SKShapeNode(circleOfRadius: 9)
            disc.position = apex
            disc.fillColor = yellow
            disc.strokeColor = SKColor(white: 0.1, alpha: 1)
            disc.lineWidth = 2
            disc.zPosition = Depth.markers
            node.addChild(disc)
            board("APEX", at: corner.apex, n: corner.side * (half + 24), color: yellow)
            bar(at: corner.exit, from: outside * half, to: outside * (half - 46), color: blue)
            board("EXIT", at: corner.exit, n: outside * (half + 24), color: blue)
        }
        return node
    }

    private static func shape(_ path: CGPath, fill: SKColor? = nil, stroke: SKColor? = nil, width: CGFloat = 0,
                              depth: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill ?? .clear
        node.strokeColor = stroke ?? .clear
        node.lineWidth = stroke == nil ? 0 : width
        node.lineJoin = .round
        node.isAntialiased = true
        node.zPosition = depth
        return node
    }

    // MARK: The car

    /// The car seen from above, nose pointing right, drawn at `scale` times its world size (34 × 15) so its texture
    /// stays sharp when the camera zooms in.
    static func carNode(livery: SKColor, scale k: CGFloat) -> SKNode {
        let car = SKNode()
        let tire = SKColor(white: 0.07, alpha: 1)
        let carbon = SKColor(white: 0.16, alpha: 1)
        func add(_ path: CGPath, _ color: SKColor) {
            let node = SKShapeNode(path: path)
            node.fillColor = color
            node.strokeColor = .clear
            node.lineWidth = 0
            car.addChild(node)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: SKColor, corner: CGFloat = 0.8) {
            add(CGPath(roundedRect: CGRect(x: x * k, y: y * k, width: w * k, height: h * k),
                       cornerWidth: corner * k, cornerHeight: corner * k, transform: nil), color)
        }
        // Wheels.
        rect(-14.5, 3.6, 8, 4.1, tire)
        rect(-14.5, -7.7, 8, 4.1, tire)
        rect(5.5, 3.9, 6.5, 3.6, tire)
        rect(5.5, -7.5, 6.5, 3.6, tire)
        // Wings.
        rect(-17.5, -6.2, 3.4, 12.4, carbon, corner: 0.5)
        rect(14.1, -6.6, 3.4, 13.2, livery, corner: 0.5)
        // Body: sidepods tapering to a narrow nose.
        let body = CGMutablePath()
        let outline: [(CGFloat, CGFloat)] = [
            (-14.5, -2.6), (-9, -4.9), (0, -4.9), (4.5, -2.2), (15, -1.1),
            (15, 1.1), (4.5, 2.2), (0, 4.9), (-9, 4.9), (-14.5, 2.6),
        ]
        body.addLines(between: outline.map { CGPoint(x: $0.0 * k, y: $0.1 * k) })
        body.closeSubpath()
        add(body, livery)
        rect(-13, -0.7, 27, 1.4, SKColor(white: 1, alpha: 0.9), corner: 0.3)
        // Cockpit and helmet.
        add(CGPath(ellipseIn: CGRect(x: -5.5 * k, y: -2 * k, width: 7 * k, height: 4 * k), transform: nil), carbon)
        add(CGPath(ellipseIn: CGRect(x: -3.6 * k, y: -1.6 * k, width: 3.2 * k, height: 3.2 * k), transform: nil),
            SKColor(red: 1, green: 0.85, blue: 0.1, alpha: 1))
        return car
    }

    /// The car as one sprite. The drawing is symmetric about its center, so the sprite's center is the car's.
    static func carSprite(in view: SKView, livery: SKColor = livery) -> SKSpriteNode {
        let scale: CGFloat = 4
        let node = carNode(livery: livery, scale: scale)
        let texture = view.texture(from: node) ?? SKTexture()
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: texture.size().width / scale, height: texture.size().height / scale)
        return sprite
    }

    // MARK: Grass

    /// A screen-filling sprite (child of the camera) that draws mown grass in world space, so it slides and turns with
    /// the track and shows how fast you're going. Feed it the camera each frame with `aimGrass`.
    static func grass(size: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode(color: grassColor, size: size)
        sprite.zPosition = Depth.grass
        let shader = SKShader(source: """
        float hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }
        void main() {
            vec2 local = (v_tex_coord - vec2(0.5)) * u_span;
            float turnCos = cos(u_angle);
            float turnSin = sin(u_angle);
            vec2 p = u_center + vec2(local.x * turnCos - local.y * turnSin, local.x * turnSin + local.y * turnCos);
            float stripe = step(0.5, fract(dot(p, vec2(0.94, 0.34)) / 260.0));
            vec3 light = vec3(0.33, 0.56, 0.28);
            vec3 dark = vec3(0.29, 0.50, 0.25);
            vec3 color = mix(dark, light, stripe);
            float speck = hash(floor(p / 7.0));
            color *= 0.965 + 0.05 * speck;
            gl_FragColor = vec4(color, 1.0);
        }
        """)
        shader.uniforms = [
            SKUniform(name: "u_center", vectorFloat2: vector_float2(0, 0)),
            SKUniform(name: "u_span", vectorFloat2: vector_float2(Float(size.width), Float(size.height))),
            SKUniform(name: "u_angle", float: 0),
        ]
        sprite.shader = shader
        return sprite
    }

    static func aimGrass(_ grass: SKSpriteNode, center: CGPoint, angle: CGFloat, worldSpan: CGSize) {
        guard let uniforms = grass.shader?.uniforms, uniforms.count == 3 else { return }
        uniforms[0].vectorFloat2Value = vector_float2(Float(center.x), Float(center.y))
        uniforms[1].vectorFloat2Value = vector_float2(Float(worldSpan.width), Float(worldSpan.height))
        uniforms[2].floatValue = Float(angle)
    }
}
