import Foundation
import GameKit
import SwiftUI

/// A Game Center friend's best lap on a board: named from Game Center, timed by the lap service.
struct FriendTime: Equatable, Identifiable {
    /// Their `ApexOnline.playerToken`: how the lap service names them.
    var token: String
    var name: String
    var time: Double

    var id: String { token }

    /// The service's answer (fastest first) with each friend's Game Center name. A token Game Center didn't name isn't
    /// a friend, so it's left out.
    static func list(_ answer: [FriendsAnswer.Friend], names: [String: String]) -> [FriendTime] {
        answer.compactMap { friend in
            names[friend.player].map { FriendTime(token: friend.player, name: $0, time: Double(friend.ms) / 1000) }
        }
        .sorted { $0.time < $1.time }
    }
}

/// What the Race a friend picker shows.
enum FriendList: Equatable {
    case loading
    case signedOut
    /// The player said no to sharing their friends list (or it's restricted).
    case denied
    /// The lap service didn't answer.
    case unavailable
    /// Game Center listed no friends: it only lists those who've let the game see their own friends.
    case noneShared
    /// Friends with a best on this board, fastest first; none yet if empty.
    case ready([FriendTime])

    /// What the picker says in place of friends, on the circuit named `track`: nil while loading, or when there are
    /// friends to list.
    func note(on track: String) -> String? {
        switch self {
        case .loading:
            return nil
        case .signedOut:
            return "Sign in to Game Center to race your friends' best laps."
        case .denied:
            return "Ghost Thread can't see your Game Center friends. You can allow it in Settings, under Game Center."
        case .unavailable:
            return "Friends' times aren't available right now. Try again when you're online."
        case .noneShared:
            return "No friends to show yet. Game Center only lists a friend once they've let Ghost Thread see their "
                + "friends, which it asks them on the track list. Share a lap to invite them."
        case .ready(let friends) where friends.isEmpty:
            return "None of your Game Center friends have a time on \(track) yet. Share a lap to invite them. Friends "
                + "who haven't let Ghost Thread see their friends don't show up here."
        case .ready:
            return nil
        }
    }
}

/// The friend picked to race on each board, kept on the device until Auto is picked again. A pick belongs to the Game
/// Center player who made it (`player`, their token), so another account on the device, or none, starts on Auto.
enum FriendPick {
    struct Pick: Codable, Equatable {
        var token: String
        var name: String
    }

    static func key(_ board: RaceBoard, player: String) -> String {
        "apex.raceFriend.v2.\(player).\(board.leaderboardID)"
    }

    static func load(on board: RaceBoard, player: String?, defaults: UserDefaults = .standard) -> Pick? {
        guard let player else { return nil }
        return defaults.data(forKey: key(board, player: player)).flatMap { try? JSONDecoder().decode(Pick.self, from: $0) }
    }

    static func save(_ pick: Pick?, on board: RaceBoard, player: String?, defaults: UserDefaults = .standard) {
        guard let player else { return }
        if let pick, let data = try? JSONEncoder().encode(pick) {
            defaults.set(data, forKey: key(board, player: player))
        } else {
            defaults.removeObject(forKey: key(board, player: player))
        }
    }
}

extension GameCenter {
    enum Friends {
        case signedOut
        /// The player said no to sharing their friends list, or it's restricted.
        case denied
        /// Game Center couldn't say (offline, or a hiccup): worth trying again.
        case failed
        case players([GKPlayer])
    }

    /// The signed-in player's token (`ApexOnline.playerToken`), or nil when signed out.
    var playerToken: String? {
        isSignedIn ? ApexOnline.playerToken(GKLocalPlayer.local.teamPlayerID) : nil
    }

    /// GameKit's notice that the player signed in or out.
    static var authenticationChanged: Notification.Name { .GKPlayerAuthenticationDidChangeNotificationName }

    /// The player (`teamPlayerID`) asked this launch, so the track list's two triggers (appearing, and sign-in
    /// finishing) don't ask them twice. Friends access is each player's own, so another account signing in is asked.
    private static var askedForFriends: String?

    /// Asks the signed-in player whether to share their friends list, if they haven't answered. Game Center only lists
    /// a player in their friends' Race a friend once they've allowed it, so asking only from the picker would leave
    /// anyone who never opens it invisible. The track list asks after sign-in; `stillOnMenu` keeps Game Center's
    /// prompt from opening over a race that started meanwhile.
    func askForFriends(stillOnMenu: @escaping () -> Bool) {
        let local = GKLocalPlayer.local
        let player = local.teamPlayerID
        guard local.isAuthenticated, Self.askedForFriends != player else { return }
        local.loadFriendsAuthorizationStatus { status, error in
            DispatchQueue.main.async {
                // Still the same player, still on the list, and not asked meanwhile by the other trigger.
                guard status == .notDetermined, error == nil, stillOnMenu(), local.isAuthenticated,
                      local.teamPlayerID == player, Self.askedForFriends != player else { return }
                Self.askedForFriends = player
                // Loading the friends list is what asks.
                local.loadFriends { _, _ in }
            }
        }
    }

    /// The signed-in player's Game Center friends who've let the game see their friends too (Game Center lists no
    /// others). If the player hasn't answered yet, Game Center asks them whether to share them.
    func loadFriends(completion: @escaping (Friends) -> Void) {
        let local = GKLocalPlayer.local
        guard local.isAuthenticated else { return completion(.signedOut) }
        local.loadFriendsAuthorizationStatus { status, error in
            if status == .denied || status == .restricted { return completion(.denied) }
            guard error == nil else { return completion(.failed) }
            local.loadFriends { friends, error in
                if let friends, error == nil { return completion(.players(friends)) }
                let code = (error as? GKError)?.code
                completion(code == .friendListDenied || code == .friendListRestricted ? .denied : .failed)
            }
        }
    }
}

/// Race a friend, over the race: Auto (the rival scout's pick), then each Game Center friend with a time here.
struct FriendPicker: View {
    let trackName: String
    let list: FriendList
    /// The friend being raced, or nil for Auto.
    let racing: String?
    let yourBest: Double?
    let onPick: (FriendTime?) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RACE A FRIEND").font(.system(size: 20, weight: .black, design: .rounded).italic())
                    Text(trackName.uppercased()).font(.system(size: 12, weight: .heavy, design: .rounded)).opacity(0.7)
                }
                Spacer()
                Button(action: onDone) {
                    Text("DONE")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            // As tall as the list, scrolling once it's longer than the screen.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(Color(white: 0.07).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            row(title: "Auto", detail: "The nearest player who beats you, or a pace bot", time: nil,
                picked: racing == nil) { onPick(nil) }
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch list {
        case .loading:
            ProgressView().tint(.white).padding(.vertical, 12)
        case .ready(let friends) where !friends.isEmpty:
            ForEach(friends) { friend in
                row(title: friend.name, detail: gap(friend.time), time: friend.time, picked: racing == friend.token) {
                    onPick(friend)
                }
            }
        default:
            if let text = list.note(on: trackName) { note(text) }
        }
    }

    /// How far ahead of (or behind) your best the friend's lap is.
    private func gap(_ time: Double) -> String? {
        guard let yourBest else { return nil }
        let gap = yourBest - time
        if abs(gap) < 0.0005 { return "Level with you" }
        return gap > 0 ? "\(LapFormat.time(gap)) s ahead of you" : "\(LapFormat.time(-gap)) s behind you"
    }

    private func row(title: String, detail: String?, time: Double?, picked: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(picked ? Livery.shared.paint(for: .rival).labelColor : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.7).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let time {
                    Text(LapFormat.time(time))
                        .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Livery.shared.paint(for: .rival).labelColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(picked ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .opacity(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}
