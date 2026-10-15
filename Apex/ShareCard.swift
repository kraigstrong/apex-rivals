import LinkPresentation
import SwiftUI
import UIKit

/// Where a shared lap sends people: the public TestFlight beta for now. Swap it for the App Store link at launch.
enum ApexLinks {
    static let join = URL(string: "https://testflight.apple.com/join/dt7sHRvR")!
}

/// A session's best lap to share: a picture of it and a line of text with the link, through the share sheet.
struct LapShare {
    let track: Track
    let lap: LapRecord
    let medal: Medal?
    /// Where the lap falls among other players, when the lap service has answered with real ones.
    let standing: Standing?

    /// The standing worth showing off: only when the lap beats someone.
    var boast: Standing? { standing.flatMap { $0.players > 0 && $0.faster < $0.players ? $0 : nil } }

    /// "27.843 at Ardennes in Needle, a gold medal lap. Beat it: https://…"
    var message: String {
        let medalPart = medal.map { ", a \($0.name.lowercased()) medal lap" } ?? ""
        return "\(LapFormat.time(lap.time)) at \(track.layout.name) in Needle\(medalPart). Beat it: \(ApexLinks.join.absoluteString)"
    }

    @MainActor func image() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(share: self))
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Opens the share sheet over whatever's on screen.
    @MainActor func present() {
        var items: [Any] = [message]
        if let image = image() {
            items.insert(LapImageItem(image: image, title: "\(track.layout.name) · \(LapFormat.time(lap.time))"), at: 0)
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let top = UIViewController.top else { return }
        // On an iPad the sheet is a popover, pointing down at the summary's buttons.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
            popover.permittedArrowDirections = .down
        }
        top.present(sheet, animated: true)
    }
}

/// The picture, previewed at the top of the share sheet (which otherwise previews the text).
final class LapImageItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

extension UIViewController {
    /// The view controller on top of the key window, to present over.
    static var top: UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The picture that's shared: the circuit with the lap's line on it, the time, its medal and where it stands.
struct ShareCard: View {
    let share: LapShare

    static let size = CGSize(width: 1200, height: 675)

    var body: some View {
        HStack(spacing: 44) {
            LapLineMap(track: share.track, lap: share.lap)
                .padding(28)
                .frame(width: 600, height: 595)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 28))
            VStack(alignment: .leading, spacing: 14) {
                // The track list's logo, with the sharer's car towing the line.
                NeedleLogo(scale: 1.7)
                Spacer(minLength: 0)
                Text(share.track.layout.name.uppercased())
                    .font(.system(size: 34, weight: .heavy, design: .rounded).italic())
                    .opacity(0.9)
                Text(LapFormat.time(share.lap.time))
                    .font(.system(size: 112, weight: .heavy, design: .rounded).monospacedDigit().italic())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, -16)
                if let medal = share.medal {
                    HStack(spacing: 10) {
                        MedalIcon(medal: medal, size: 38)
                        Text("\(medal.name.uppercased()) MEDAL")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(medal.color)
                    }
                }
                if let standing = share.boast {
                    Text(standing.line)
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Text("CAN YOU BEAT IT?")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.9, green: 0.12, blue: 0.1), in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.vertical, 18)
        }
        .padding(40)
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white)
        .background(MowedGrass())
    }
}

/// A circuit drawn to scale, road as wide as the track, with a lap's line along it in the car's color.
struct LapLineMap: View {
    let track: Track
    let lap: LapRecord

    var body: some View {
        Canvas { context, size in
            let bounds = track.bounds
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let inset = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
            func map(_ point: CGPoint) -> CGPoint {
                CGPoint(x: inset.x + (point.x - bounds.minX) * scale, y: inset.y + (bounds.maxY - point.y) * scale)
            }
            var road = Path()
            road.addLines(stride(from: 0, to: track.count, by: 6).map { map(track.point(sample: $0, n: 0)) })
            road.closeSubpath()
            let width = track.width * scale
            context.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: width + 4, lineJoin: .round))
            context.stroke(road, with: .color(Color(white: 0.27)), style: StrokeStyle(lineWidth: width, lineJoin: .round))

            // The start/finish line, across the road.
            var start = Path()
            start.move(to: map(track.point(s: 0, n: -track.width / 2)))
            start.addLine(to: map(track.point(s: 0, n: track.width / 2)))
            context.stroke(start, with: .color(.white), lineWidth: 4)

            // The lap's line, broken wherever it wraps past the line.
            var line = Path()
            var previous: Float?
            for sample in lap.ghost {
                let point = map(track.point(s: Double(sample.s), n: Double(sample.n)))
                if let previous, abs(sample.s - previous) < Float(track.length / 2) {
                    line.addLine(to: point)
                } else {
                    line.move(to: point)
                }
                previous = sample.s
            }
            // The car's body color stands out on the gray road, unless it's too dark to see there.
            let paint = Livery.shared.paint(for: .car)
            let body = paint.body
            let color = 0.2126 * body.r + 0.7152 * body.g + 0.0722 * body.b >= 0.12 ? paint.color : paint.labelColor
            context.stroke(line, with: .color(.black.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        }
    }
}
