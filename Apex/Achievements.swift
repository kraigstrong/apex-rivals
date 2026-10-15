import GameKit

extension Medal {
    /// This medal's Game Center achievement on a circuit, like `apex.ardennes.gold`. Create it in App Store Connect
    /// before a build with a new circuit ships. It isn't tied to a board: a medal won stays won after a retune moves
    /// the medal times.
    func achievementID(on layout: TrackLayout) -> String {
        "apex.\(layout.id).\(name.lowercased())"
    }

    /// The achievements a best lap of `time` has earned on a circuit: its medal's and every one below it, so a first
    /// lap good for gold earns bronze and silver too. None for a tuned car or on Apex School, which win no medals.
    static func achievements(earnedBy time: Double?, on layout: TrackLayout) -> Set<String> {
        guard let medal = earned(by: time, on: layout) else { return [] }
        return Set(allCases.filter { $0 <= medal }.map { $0.achievementID(on: layout) })
    }

    /// The achievements the best laps saved on this device have earned, on every circuit.
    static func achievementsEarnedBySavedBests(defaults: UserDefaults = .standard) -> Set<String> {
        TrackLayout.all.reduce(into: []) { ids, layout in
            ids.formUnion(achievements(earnedBy: LapStore.load(for: layout, defaults: defaults)?.time, on: layout))
        }
    }
}

/// Medals as Game Center achievements. Each sign-in loads what the player has achieved and reports whatever the saved
/// best laps have earned beyond it, so medals won while signed out or offline, or before achievements existed, catch
/// up; a best lap that wins a medal reports it at once. Game Center's own banner stays off: the lap banner already
/// names the medal, and Game Center's would drop over the timing mid-race.
final class Achievements {
    static let shared = Achievements()

    /// What the signed-in player has achieved: loaded at sign-in, plus whatever's been reported since.
    private var achieved: Set<String> = []
    private var player: String?

    /// Called once Game Center has signed a player in.
    func signedIn() {
        let player = GKLocalPlayer.local.teamPlayerID
        if player != self.player {
            self.player = player
            achieved = []
        }
        GKAchievement.loadAchievements { [weak self] loaded, error in
            DispatchQueue.main.async {
                guard let self, error == nil, GKLocalPlayer.local.teamPlayerID == player else { return }
                self.achieved = Set((loaded ?? []).filter(\.isCompleted).map(\.identifier))
                self.report(Medal.achievementsEarnedBySavedBests())
            }
        }
    }

    /// Reports the achievements in `ids` the player hasn't achieved yet. Signed out, or if Game Center can't be
    /// reached, they wait for the next sign-in.
    func report(_ ids: Set<String>) {
        let player = GKLocalPlayer.local.teamPlayerID
        let new = ids.subtracting(achieved)
        guard GKLocalPlayer.local.isAuthenticated, player == self.player, !new.isEmpty else { return }
        let achievements = new.sorted().map { id in
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = false
            return achievement
        }
        GKAchievement.report(achievements) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, error == nil, self.player == player else { return }
                self.achieved.formUnion(new)
            }
        }
    }
}
