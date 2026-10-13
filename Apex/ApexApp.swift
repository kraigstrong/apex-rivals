import SwiftUI

@main
struct ApexApp: App {
    init() {
        #if DEBUG
        Tuner.shared.restore()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
