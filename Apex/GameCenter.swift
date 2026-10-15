import GameKit
import UIKit

/// Signs the player in to Game Center, submits best laps to each board's leaderboard, and shows the leaderboards.
/// Everything else works without it: signed out, laps just stay on the device.
final class GameCenter: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenter()

    var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    /// Game Center's leaderboard is up: its overlay on iOS 26, or its view controller before that. The race holds
    /// still under it.
    var isShowingLeaderboard: Bool {
        GKAccessPoint.shared.isPresentingGameCenter || leaderboard?.presentingViewController != nil
    }
    private weak var leaderboard: GKGameCenterViewController?

    /// Starts sign-in. Game Center shows its own sheet if the player needs to sign in. Once signed in, any best laps
    /// set while signed out go up, and so do the medals they won (`Achievements`).
    func signIn() {
        GKLocalPlayer.local.authenticateHandler = { controller, _ in
            if let controller {
                Self.present(controller)
                return
            }
            guard GKLocalPlayer.local.isAuthenticated else { return }
            BestLapDelivery.sendSaved()
            Achievements.shared.signedIn()
        }
    }

    /// Submits a lap to the board's leaderboard, in hundredths of a second (Game Center keeps each player's best).
    /// `completion` says whether Game Center took it.
    func submit(_ lapTime: Double, on board: RaceBoard, completion: @escaping (Bool) -> Void = { _ in }) {
        guard isSignedIn, RaceTuning.isStock else { return completion(false) }
        GKLeaderboard.submitScore(Int((lapTime * 100).rounded()), context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [board.leaderboardID]) { error in completion(error == nil) }
    }

    /// Opens on your Game Center friends' times; the global board is a tap away in the same screen. iOS 26 replaced
    /// Game Center's view controller with its overlay, opened through the access point: presented there, the view
    /// controller came up empty and was hard to get out of.
    func showLeaderboard(_ board: RaceBoard) {
        if #available(iOS 26, *) {
            GKAccessPoint.shared.trigger(leaderboardID: board.leaderboardID, playerScope: .friendsOnly,
                                         timeScope: .allTime) {}
            return
        }
        let controller = GKGameCenterViewController(leaderboardID: board.leaderboardID, playerScope: .friendsOnly,
                                                    timeScope: .allTime)
        controller.gameCenterDelegate = self
        leaderboard = controller
        Self.present(controller)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }

    private static func present(_ controller: UIViewController) {
        UIViewController.top?.present(controller, animated: true)
    }
}
