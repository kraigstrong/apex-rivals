import SwiftUI

@main
struct ApexApp: App {
    init() {
        #if DEBUG
        Tuner.shared.restore()
        StoreCapture.stage()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
