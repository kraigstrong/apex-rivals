import Foundation

/// One leaderboard: a circuit at one revision, driven with one version of the physics. Lap times only compare within a
/// board, so changing the circuit's shape or the car's physics after release starts new boards.
struct RaceBoard: Equatable {
    let trackID: String
    let trackRevision: Int
    let physicsVersion: Int

    init(trackID: String, trackRevision: Int, physicsVersion: Int = RaceTuning.physicsVersion) {
        self.trackID = trackID
        self.trackRevision = trackRevision
        self.physicsVersion = physicsVersion
    }

    init(track: Track) {
        self.init(layout: track.layout)
    }

    init(layout: TrackLayout) {
        self.init(trackID: layout.id, trackRevision: layout.revision)
    }

    /// The Game Center leaderboard's ID. Create it in App Store Connect (Elapsed Time to the hundredth of a second,
    /// low to high) before a build with this board ships.
    var leaderboardID: String { "apex.\(trackID).r\(trackRevision).p\(physicsVersion)" }
}
