import SwiftUI

/// The game's name at the top of the track list: NEEDLE, with your car towing its racing line through the letters, in
/// front of one and behind the next, the way a needle threads them.
struct NeedleLogo: View {
    static let size = CGSize(width: 250, height: 56)
    /// Bigger than the track list's, as on the share card, still drawn sharp.
    var scale: CGFloat = 1

    var body: some View {
        let paint = Livery.shared.paint(for: .car)
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            Self.draw(context, size: Self.size, paint: paint)
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .accessibilityElement()
        .accessibilityLabel("Needle")
        .accessibilityAddTraits(.isHeader)
    }

    private static let font = Font.system(size: 40, weight: .black, design: .rounded)
    /// The letters lean forward like the rest of the game's titles. SF Rounded has no italic, so the slant is drawn.
    private static let slant = CGAffineTransform(a: 1, b: 0, c: -0.21, d: 1, tx: 0, ty: 0)
    private static let lineColor = Color(red: 1, green: 0.82, blue: 0.1)
    /// How far above and below the middle of the letters the line swings.
    private static let swing: CGFloat = 5
    private static let carLength: CGFloat = 40

    private static func draw(_ context: GraphicsContext, size: CGSize, paint: Paint) {
        let letters = "NEEDLE".map { context.resolve(Text(String($0)).font(font).foregroundStyle(.white)) }
        let widths = letters.map { $0.measure(in: size).width }
        let height = letters[0].measure(in: size).height
        let tail: CGFloat = 12, carGap: CGFloat = 10
        let total = tail + widths.reduce(0, +) + carGap + carLength
        var x = (size.width - total) / 2 + tail
        var boxes: [CGRect] = []
        for width in widths {
            boxes.append(CGRect(x: x, y: (size.height - height) / 2, width: width, height: height))
            x += width
        }
        // The middle of the capitals: the box's middle, give or take a point.
        let mid = boxes[0].midY + 1

        // In from the left, then a swing through each letter, alternately up and down, to the gap after it.
        var line = Path()
        line.move(to: CGPoint(x: boxes[0].minX - tail, y: mid + swing))
        for (i, box) in boxes.enumerated() {
            line.addQuadCurve(to: CGPoint(x: box.maxX, y: mid),
                              control: CGPoint(x: box.midX, y: mid + (i.isMultiple(of: 2) ? -swing : swing) * 2))
            // A quadratic's peak is half its control's offset, so the line swings `swing` either side.
        }
        let car = CGPoint(x: boxes.last!.maxX + carGap + carLength / 2, y: mid)
        let rear = CGPoint(x: car.x - carLength / 2, y: car.y)
        line.addCurve(to: rear, control1: CGPoint(x: boxes.last!.maxX + 4, y: mid - swing),
                      control2: CGPoint(x: rear.x - 6, y: rear.y))

        // A dark edge keeps the line readable over the white letters and the grass.
        func stroke(_ layer: GraphicsContext) {
            layer.stroke(line, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            layer.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        stroke(context)
        for (letter, box) in zip(letters, boxes) {
            var layer = context
            layer.concatenate(slanted(around: CGPoint(x: box.midX, y: box.midY)))
            layer.draw(letter, at: CGPoint(x: box.midX, y: box.midY))
        }
        // Back over every other letter, so the line passes in front of the N, the second E and the L.
        for (i, box) in boxes.enumerated() where i.isMultiple(of: 2) {
            var layer = context
            layer.clip(to: Path(box).applying(slanted(around: CGPoint(x: box.midX, y: box.midY))))
            stroke(layer)
        }

        // The car at the head of the line, nose to the right, with a shadow on the grass.
        let k = carLength / 34
        for (offset, shadow) in [(CGSize(width: 1.5, height: 2), true), (.zero, false)] {
            var layer = context
            layer.translateBy(x: car.x + offset.width, y: car.y + offset.height)
            for piece in CarArt.pieces {
                let color = shadow ? Color.black.opacity(0.3) : Color(rgb: CarArt.rgb(piece.part, paint: paint))
                layer.fill(Path(CarArt.path(piece.form, scale: k)), with: .color(color))
            }
        }
    }

    /// The letters' slant about a point.
    private static func slanted(around point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y)
            .concatenating(slant)
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    }
}
