import Foundation

/// Gets each circuit's best lap to Game Center and to the lap service, once each. A best set while signed out (or
/// before sign-in finished, or with no connection) goes up the next time the player signs in.
enum BestLapDelivery {
    enum Destination: String, CaseIterable {
        case gameCenter, lapService
    }

    /// Sends `best`, saved under `key`, wherever it hasn't reached yet.
    static func send(_ best: LapRecord, on board: RaceBoard, key: String, defaults: UserDefaults = .standard) {
        let ms = Int((best.time * 1000).rounded())
        for destination in Destination.allCases where defaults.integer(forKey: sentKey(key, destination)) != ms {
            let delivered: (Bool) -> Void = { delivered in
                guard delivered else { return }
                DispatchQueue.main.async { defaults.set(ms, forKey: sentKey(key, destination)) }
            }
            switch destination {
            case .gameCenter: GameCenter.shared.submit(best.time, on: board, completion: delivered)
            case .lapService: ApexService.shareBest(best, on: board, completion: delivered)
            }
        }
    }

    /// Sends every circuit's saved best that hasn't gone up yet.
    static func sendSaved(defaults: UserDefaults = .standard) {
        for layout in TrackLayout.all {
            guard let best = LapStore.load(for: layout, defaults: defaults) else { continue }
            send(best, on: RaceBoard(layout: layout), key: LapStore.key(for: layout), defaults: defaults)
        }
    }

    /// Where the time (in milliseconds) of the last best delivered to `destination` is kept.
    static func sentKey(_ key: String, _ destination: Destination) -> String {
        key + ".sent." + destination.rawValue
    }
}
