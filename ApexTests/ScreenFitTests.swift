import CoreGraphics
import Testing
@testable import Apex

/// Every phone, an iPhone Duo open or closed included, draws the race as it always has; an iPad draws its HUD bigger,
/// as much as fits both ways, and brings the camera in a little.
struct ScreenFitTests {
    @Test func phonesAndTheDuoDrawAsTheyAre() {
        let phones = [
            CGSize(width: 667, height: 375),  // iPhone SE
            CGSize(width: 874, height: 402),  // iPhone 17 Pro
            CGSize(width: 956, height: 440),  // iPhone 17 Pro Max
            CGSize(width: 678, height: 466),  // iPhone Duo, closed
            CGSize(width: 951, height: 669),  // iPhone Duo, open
        ]
        for size in phones {
            #expect(ScreenFit.scale(for: size) == 1, "\(size)")
            #expect(ScreenFit.cameraZoom(for: size) == 1, "\(size)")
        }
    }

    @Test func anIPadDrawsBiggerAsFarAsItsWidthAllows() {
        let ipad13 = CGSize(width: 1376, height: 1032)
        #expect(abs(ScreenFit.scale(for: ipad13) - 1376 / 956) < 0.001)
        #expect(abs(ScreenFit.cameraZoom(for: ipad13) - (1376.0 / 956).squareRoot()) < 0.001)
        let mini = CGSize(width: 1133, height: 744)
        #expect(ScreenFit.scale(for: mini) > 1 && ScreenFit.scale(for: mini) < ScreenFit.scale(for: ipad13))
    }

    @Test func aScreenWithNoSizeYetDrawsAsAPhone() {
        #expect(ScreenFit.scale(for: .zero) == 1)
    }
}
