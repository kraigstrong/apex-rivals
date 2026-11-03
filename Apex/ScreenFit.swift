import SwiftUI

// Ghost Thread on screens bigger than a phone's (an iPad). The race's HUD, cards and panels are laid out as on the
// biggest iPhone and drawn bigger to fill the screen, and the camera comes in a little, so an iPad shows the race bigger
// rather than small in a lot of grass. Every iPhone draws exactly as before, and so does an iPhone Duo, open or closed:
// open, its screen is a Pro Max's width, just taller.

enum ScreenFit {
    /// The biggest phone screen the HUD is laid out for: an iPhone Pro Max's, in landscape.
    static let largestPhone = CGSize(width: 956, height: 440)

    /// How much bigger the HUD draws on a screen of `size`: 1 on every phone, and on a bigger screen as much bigger as
    /// fits both ways.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(1, min(size.width / largestPhone.width, size.height / largestPhone.height))
    }

    /// How much closer the camera comes on a screen of `size`: the square root of the HUD's scale, so the cars grow with
    /// a bigger screen while it still shows more of the road ahead.
    static func cameraZoom(for size: CGSize) -> CGFloat {
        scale(for: size).squareRoot()
    }
}

/// A view laid out at a phone's size and scaled up to fill a bigger screen (`ScreenFit.scale`); on a phone it's the
/// screen as it is. Backgrounds that run to the screen's edges belong outside it, unscaled.
struct ScreenScaled<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let scale = ScreenFit.scale(for: geometry.size)
            content()
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
