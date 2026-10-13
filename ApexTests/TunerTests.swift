#if DEBUG
import Foundation
import Testing
@testable import Apex

struct TunerTests {
    /// Every slider can sit exactly on the car as released, so Reset puts back the stock car.
    @Test func everyKnobCanSitAtStock() throws {
        let tuner = Tuner(defaults: try #require(UserDefaults(suiteName: "TunerTests.stock")))
        for knob in Tuner.knobs {
            let stock = try #require(tuner.stock[knob.id])
            #expect(knob.range.contains(stock), "\(knob.id)")
            let steps = (stock - knob.range.lowerBound) / knob.step
            #expect(abs(steps - steps.rounded()) < 1e-9, "\(knob.id)")
        }
        #expect(Set(Tuner.knobs.map(\.id)).count == Tuner.knobs.count)
    }
}
#endif
