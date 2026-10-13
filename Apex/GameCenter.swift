import GameKit
import UIKit

/// Signs the player in to Game Center, submits best laps to each board's leaderboard, and shows the leaderboards.
/// Everything else works without it: signed out, laps just stay on the device.
final class GameCenter: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenter()

    var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    /// Starts sign-in. Game Center shows its own sheet if the player needs to sign in. Once signed in, any best laps
    /// set while signed out go up.
    func signIn() {
        GKLocalPlayer.local.authenticateHandler = { controller, _ in
            if let controller {
                Self.present(controller)
                return
            }
            if GKLocalPlayer.local.isAuthenticated { BestLapDelivery.sendSaved() }
        }
    }

    /// Submits a lap to the board's leaderboard, in hundredths of a second (Game Center keeps each player's best).
    /// `completion` says whether Game Center took it.
    func submit(_ lapTime: Double, on board: RaceBoard, completion: @escaping (Bool) -> Void = { _ in }) {
        guard isSignedIn else { return completion(false) }
        GKLeaderboard.submitScore(Int((lapTime * 100).rounded()), context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [board.leaderboardID]) { error in completion(error == nil) }
    }

    /// Opens on your Game Center friends' times; the global board is a tap away in the same screen.
    func showLeaderboard(_ board: RaceBoard) {
        let controller = GKGameCenterViewController(leaderboardID: board.leaderboardID, playerScope: .friendsOnly,
                                                    timeScope: .allTime)
        controller.gameCenterDelegate = self
        Self.present(controller)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }

    private static func present(_ controller: UIViewController) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }
}
