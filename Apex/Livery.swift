import CoreGraphics
import Foundation
import Observation
import SpriteKit
import SwiftUI

/// A paint scheme for a car: its body and the stripe down its spine. The colors are in the spirit of F1 teams', and
/// named for the color alone.
enum Paint: String, CaseIterable, Codable, Identifiable {
    case racingRed, orange, yellow, racingGreen, teal, skyBlue, blue, navy, pink, silver, white, blackGold

    var id: String { rawValue }

    var name: String {
        switch self {
        case .racingRed: return "Racing Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .racingGreen: return "Racing Green"
        case .teal: return "Teal"
        case .skyBlue: return "Sky Blue"
        case .blue: return "Blue"
        case .navy: return "Navy"
        case .pink: return "Pink"
        case .silver: return "Silver"
        case .white: return "White"
        case .blackGold: return "Black & Gold"
        }
    }

    /// Red, green, blue from 0 to 1.
    typealias RGB = (r: Double, g: Double, b: Double)

    var body: RGB {
        switch self {
        case .racingRed: return (0.86, 0.06, 0.06)
        case .orange: return (1.0, 0.50, 0.0)
        case .yellow: return (1.0, 0.82, 0.05)
        case .racingGreen: return (0.0, 0.42, 0.30)
        case .teal: return (0.0, 0.78, 0.72)
        case .skyBlue: return (0.30, 0.75, 1.0)
        case .blue: return (0.05, 0.40, 0.95)
        case .navy: return (0.09, 0.16, 0.42)
        case .pink: return (1.0, 0.42, 0.74)
        case .silver: return (0.74, 0.76, 0.80)
        case .white: return (0.96, 0.96, 0.97)
        case .blackGold: return (0.10, 0.10, 0.12)
        }
    }

    var stripe: RGB {
        switch self {
        case .orange, .yellow, .teal: return (0.08, 0.08, 0.10)
        case .navy, .white: return (0.88, 0.10, 0.12)
        case .silver: return (0.0, 0.78, 0.72)
        case .blackGold: return (0.85, 0.68, 0.25)
        default: return (0.97, 0.97, 0.97)
        }
    }

    /// The helmet: yellow, unless that's the body's own color.
    var helmet: RGB { self == .yellow ? (0.97, 0.97, 0.97) : (1.0, 0.84, 0.1) }

    var skBody: SKColor { SKColor(rgb: body) }
    var color: Color { Color(rgb: body) }
    var stripeColor: Color { Color(rgb: stripe) }
}

/// Which paint each car on track wears: yours, your best lap's ghost, and your rival's ghost. No two share a paint, so
/// they're always told apart; choosing one another role has swaps the two. Kept on the device.
@Observable
final class Livery {
    enum Role: String, CaseIterable, Identifiable {
        case car, best, rival
        var id: String { rawValue }

        var title: String {
            switch self {
            case .car: return "Your car"
            case .best: return "Best-lap ghost"
            case .rival: return "Rival ghost"
            }
        }
    }

    static let shared = Livery()
    static let defaults: [Role: Paint] = [.car: .racingRed, .best: .skyBlue, .rival: .yellow]

    private(set) var paints: [Role: Paint]
    /// Goes up with every change, so the race knows to repaint its cars.
    private(set) var version = 0
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let key = "apex.livery.v1"

    init(defaults store: UserDefaults = .standard) {
        self.store = store
        var paints = Livery.defaults
        if let saved = store.dictionary(forKey: key) as? [String: String] {
            for (role, paint) in saved {
                if let role = Role(rawValue: role), let paint = Paint(rawValue: paint) { paints[role] = paint }
            }
        }
        // A save that somehow gave two roles one paint falls back to the defaults.
        self.paints = Set(paints.values).count == Role.allCases.count ? paints : Livery.defaults
    }

    func paint(for role: Role) -> Paint { paints[role] ?? Livery.defaults[role]! }

    func set(_ paint: Paint, for role: Role) {
        let previous = self.paint(for: role)
        guard previous != paint else { return }
        if let other = Role.allCases.first(where: { $0 != role && self.paint(for: $0) == paint }) {
            paints[other] = previous
        }
        paints[role] = paint
        version += 1
        store.set(Dictionary(uniqueKeysWithValues: paints.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: key)
    }
}

/// The car seen from above, nose to the right, in car units (34 long, 15.4 wide, centered on the origin). The race's
/// sprites and the color picker's previews both draw it from here.
enum CarArt {
    enum Part { case tire, carbon, body, stripe, helmet }

    enum Form {
        case rect(CGRect, corner: CGFloat)
        case polygon([CGPoint])
        case ellipse(CGRect)
    }

    struct Piece {
        var part: Part
        var form: Form
    }

    static let pieces: [Piece] = [
        // Wheels.
        Piece(part: .tire, form: .rect(CGRect(x: -14.5, y: 3.6, width: 8, height: 4.1), corner: 0.8)),
        Piece(part: .tire, form: .rect(CGRect(x: -14.5, y: -7.7, width: 8, height: 4.1), corner: 0.8)),
        Piece(part: .tire, form: .rect(CGRect(x: 5.5, y: 3.9, width: 6.5, height: 3.6), corner: 0.8)),
        Piece(part: .tire, form: .rect(CGRect(x: 5.5, y: -7.5, width: 6.5, height: 3.6), corner: 0.8)),
        // Wings.
        Piece(part: .carbon, form: .rect(CGRect(x: -17.5, y: -6.2, width: 3.4, height: 12.4), corner: 0.5)),
        Piece(part: .body, form: .rect(CGRect(x: 14.1, y: -6.6, width: 3.4, height: 13.2), corner: 0.5)),
        // Body: sidepods tapering to a narrow nose.
        Piece(part: .body, form: .polygon([
            CGPoint(x: -14.5, y: -2.6), CGPoint(x: -9, y: -4.9), CGPoint(x: 0, y: -4.9), CGPoint(x: 4.5, y: -2.2),
            CGPoint(x: 15, y: -1.1), CGPoint(x: 15, y: 1.1), CGPoint(x: 4.5, y: 2.2), CGPoint(x: 0, y: 4.9),
            CGPoint(x: -9, y: 4.9), CGPoint(x: -14.5, y: 2.6),
        ])),
        Piece(part: .stripe, form: .rect(CGRect(x: -13, y: -0.7, width: 27, height: 1.4), corner: 0.3)),
        // Cockpit and helmet.
        Piece(part: .carbon, form: .ellipse(CGRect(x: -5.5, y: -2, width: 7, height: 4))),
        Piece(part: .helmet, form: .ellipse(CGRect(x: -3.6, y: -1.6, width: 3.2, height: 3.2))),
    ]

    static func rgb(_ part: Part, paint: Paint) -> Paint.RGB {
        switch part {
        case .tire: return (0.07, 0.07, 0.07)
        case .carbon: return (0.16, 0.16, 0.16)
        case .body: return paint.body
        case .stripe: return paint.stripe
        case .helmet: return paint.helmet
        }
    }

    /// A piece's outline, scaled by `k` (y up, as SpriteKit draws).
    static func path(_ form: Form, scale k: CGFloat) -> CGPath {
        let transform = CGAffineTransform(scaleX: k, y: k)
        switch form {
        case .rect(let rect, let corner):
            return CGPath(roundedRect: rect.applying(transform), cornerWidth: corner * k, cornerHeight: corner * k,
                          transform: nil)
        case .polygon(let points):
            let path = CGMutablePath()
            path.addLines(between: points.map { $0.applying(transform) })
            path.closeSubpath()
            return path
        case .ellipse(let rect):
            return CGPath(ellipseIn: rect.applying(transform), transform: nil)
        }
    }
}

extension SKColor {
    convenience init(rgb: Paint.RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}

extension Color {
    init(rgb: Paint.RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension Paint {
    /// A version of the paint that reads on the HUD's dark panels: the body, or the stripe when the body is too dark,
    /// or else the body lightened.
    var labelColor: Color {
        func luminance(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        if luminance(body) >= 0.3 { return Color(rgb: body) }
        if luminance(stripe) >= 0.3 { return Color(rgb: stripe) }
        return Color(rgb: (body.r * 0.5 + 0.5, body.g * 0.5 + 0.5, body.b * 0.5 + 0.5))
    }

    /// The paint as a shape on a dark panel, like your bar in the session summary's chart: the body, unless it's too
    /// dark to see there. A shape needs less contrast than text, so racing red stays red where its label is white.
    var markColor: Color {
        0.2126 * body.r + 0.7152 * body.g + 0.0722 * body.b >= 0.2 ? color : labelColor
    }
}

/// The car in a paint, on a patch of asphalt; a ghost is see-through, as on track.
struct CarPreview: View {
    let paint: Paint
    var ghost = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 38, size.height / 17)
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.opacity = ghost ? 0.55 : 1
            for piece in CarArt.pieces {
                let path = Path(CarArt.path(piece.form, scale: scale))
                context.fill(path, with: .color(Color(rgb: CarArt.rgb(piece.part, paint: paint))))
            }
        }
        .background(Color(red: 0.27, green: 0.28, blue: 0.30), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// One paint to pick: its body, with its stripe across it.
struct PaintSwatch: View {
    let paint: Paint
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(paint.color)
            Rectangle().fill(paint.stripeColor).frame(height: 5)
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        .padding(4)
        .overlay(Circle().stroke(selected ? .white : .clear, lineWidth: 3))
        .frame(width: 38, height: 38)
        .accessibilityLabel(paint.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pick a paint for your car, your best lap's ghost and your rival's ghost. Picking a paint another car has swaps
/// the two, so every car on track stays its own color.
struct LiveryPicker: View {
    let livery: Livery
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CAR COLORS")
                    .font(.system(size: 22, weight: .black, design: .rounded).italic())
                Spacer()
                Button(action: onDone) {
                    Text("DONE")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
                }
            }
            ForEach(Livery.Role.allCases) { role in
                let current = livery.paint(for: role)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role.title.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .opacity(0.7)
                        CarPreview(paint: current, ghost: role != .car)
                            .frame(width: 96, height: 40)
                        Text(current.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .frame(width: 110, alignment: .leading)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 2), count: 6), spacing: 2) {
                        ForEach(Paint.allCases) { paint in
                            Button {
                                livery.set(paint, for: role)
                            } label: {
                                PaintSwatch(paint: paint, selected: paint == current)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("Each car keeps its own color: picking one another car has swaps the two.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.6)
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(Color(white: 0.07).opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }
}
