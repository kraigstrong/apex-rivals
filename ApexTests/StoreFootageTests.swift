import Testing
@testable import Apex

/// The website's footage (`StoreFootage`): which launches ask for it, and how much of the race around its moment they
/// keep. The frames themselves are checked by running `scripts/store-capture.sh --footage`.
struct StoreFootageTests {
    @Test func aWindowIsSecondsBeforeTheMomentThenAfterIt() {
        #expect(StoreFootage.Window("3,7") == StoreFootage.Window(before: 3, after: 7))
        #expect(StoreFootage.Window("0, 4.5") == StoreFootage.Window(before: 0, after: 4.5))
    }

    @Test func anythingElseAsksForNoFootage() {
        for text in [nil, "", "3", "3,7,1", "-1,7", "3,0", "three,seven"] {
            #expect(StoreFootage.Window(text) == nil, "\(text ?? "nil")")
        }
    }
}
