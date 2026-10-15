import SwiftUI

/// The game's name at the top of the track list and on the share card: GHOST see-through, like a ghost on track, and
/// THREAD with a racing line woven through it, in front of one letter and behind the next, towed by a ghost car in
/// your ghost's paint.
struct GhostThreadLogo: View {
    static let size = CGSize(width: 300, height: 56)
    /// Bigger than the track list's, as on the share card, still drawn sharp.
    var scale: CGFloat = 1

    var body: some View {
        let ghost = Livery.shared.paint(for: .best)
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            Self.draw(context, size: Self.size, ghost: ghost)
        }
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .accessibilityElement()
        .accessibilityLabel("Ghost Thread")
        .accessibilityAddTraits(.isHeader)
    }

    private static let font = Font.system(size: 31, weight: .black, design: .rounded)
    /// The letters lean forward like the rest of the game's titles. SF Rounded has no italic, so the slant is drawn.
    private static let slant = CGAffineTransform(a: 1, b: 0, c: -0.21, d: 1, tx: 0, ty: 0)
    private static let lineColor = Color(red: 1, green: 0.82, blue: 0.1)
    /// How far above and below the middle of the letters the line swings.
    private static let swing: CGFloat = 4.5
    private static let carLength: CGFloat = 34
    /// GHOST is as see-through as the ghost car on track; the logo's car as the color picker's ghost preview.
    private static let ghostLetters = 0.45
    private static let ghostCar = 0.55

    private static func draw(_ context: GraphicsContext, size: CGSize, ghost: Paint) {
        func letters(_ word: String) -> [GraphicsContext.ResolvedText] {
            word.map { context.resolve(Text(String($0)).font(font).foregroundStyle(.white)) }
        }
        let ghostWord = letters("GHOST"), threadWord = letters("THREAD")
        func width(_ word: [GraphicsContext.ResolvedText]) -> CGFloat {
            word.reduce(0) { $0 + $1.measure(in: size).width }
        }
        let height = threadWord[0].measure(in: size).height
        let tail: CGFloat = 10, wordGap: CGFloat = 9, carGap: CGFloat = 8
        var x = (size.width - (width(ghostWord) + wordGap + width(threadWord) + carGap + carLength)) / 2
        func boxes(_ word: [GraphicsContext.ResolvedText]) -> [CGRect] {
            word.map { letter in
                let w = letter.measure(in: size).width
                defer { x += w }
                return CGRect(x: x, y: (size.height - height) / 2, width: w, height: height)
            }
        }
        let ghostBoxes = boxes(ghostWord)
        x += wordGap
        let threadBoxes = boxes(threadWord)
        // The middle of the capitals, a little below the box's middle.
        let mid = threadBoxes[0].midY + 2

        // In from the word gap, then a swing through each letter of THREAD, alternately up and down, to the gap after
        // it (a quadratic peaks at half its control's offset), and on to the car's rear wing.
        var line = Path()
        line.move(to: CGPoint(x: threadBoxes[0].minX - tail, y: mid + swing))
        for (i, box) in threadBoxes.enumerated() {
            line.addQuadCurve(to: CGPoint(x: box.maxX, y: mid),
                              control: CGPoint(x: box.midX, y: mid + (i.isMultiple(of: 2) ? -swing : swing) * 2))
        }
        let car = CGPoint(x: threadBoxes.last!.maxX + carGap + carLength / 2, y: mid)
        let rear = CGPoint(x: car.x - carLength / 2, y: car.y)
        line.addCurve(to: rear, control1: CGPoint(x: threadBoxes.last!.maxX + 4, y: mid - swing),
                      control2: CGPoint(x: rear.x - 6, y: rear.y))

        // A dark edge keeps the line readable over the white letters and the grass.
        func stroke(_ layer: GraphicsContext) {
            layer.stroke(line, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
            layer.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        func draw(_ word: [GraphicsContext.ResolvedText], in boxes: [CGRect], opacity: Double) {
            for (letter, box) in zip(word, boxes) {
                var layer = context
                layer.opacity = opacity
                layer.concatenate(slanted(around: CGPoint(x: box.midX, y: box.midY)))
                layer.draw(letter, at: CGPoint(x: box.midX, y: box.midY))
            }
        }
        draw(ghostWord, in: ghostBoxes, opacity: ghostLetters)
        stroke(context)
        draw(threadWord, in: threadBoxes, opacity: 1)
        // Back over every other letter, so the line passes in front of the T, the R and the A.
        for (i, box) in threadBoxes.enumerated() where i.isMultiple(of: 2) {
            var layer = context
            layer.clip(to: Path(box).applying(slanted(around: CGPoint(x: box.midX, y: box.midY))))
            stroke(layer)
        }

        // The ghost car at the head of the line, nose to the right: see-through, and like a ghost on track, no shadow.
        var layer = context
        layer.translateBy(x: car.x, y: car.y)
        layer.opacity = ghostCar
        for piece in CarArt.pieces {
            layer.fill(Path(CarArt.path(piece.form, scale: carLength / 34)),
                       with: .color(Color(rgb: CarArt.rgb(piece.part, paint: ghost))))
        }
    }

    /// The letters' slant about a point.
    private static func slanted(around point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y)
            .concatenating(slant)
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    }
}
