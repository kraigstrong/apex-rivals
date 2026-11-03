import Foundation

/// Gets each circuit's best lap to Game Center and to the lap service, once each, under the player who set it
/// (`LapStore.player`). A best that missed them (no connection, or a hiccup) goes up the next time that player signs
/// in; another player signing in on the device never sends it. A best set while no one was signed in goes to the first
/// player who signs in (`LapStore.claim`).
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

    /// Sends every circuit's saved best that `player` (the one signed in) set and that hasn't gone up yet.
    static func sendSaved(for player: String, defaults: UserDefaults = .standard) {
        for (layout, best) in LapStore.bests(of: player, defaults: defaults) {
            send(best, on: RaceBoard(layout: layout), key: LapStore.key(for: layout), defaults: defaults)
        }
    }

    /// Where the time (in milliseconds) of the last best delivered to `destination` is kept.
    static func sentKey(_ key: String, _ destination: Destination) -> String {
        key + ".sent." + destination.rawValue
    }
}
