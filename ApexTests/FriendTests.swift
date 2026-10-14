import Foundation
import Testing
@testable import Apex

struct FriendTests {
    let board = RaceBoard(track: Track(.ardennes))

    /// The service refuses anything but exactly these keys (BrightBench's `validateFriends`).
    @Test func aFriendsQueryHasExactlyTheKeysTheServiceTakes() throws {
        let query = try #require(ApexService.friendsQuery([ApexOnline.playerToken("T:_a")], on: board))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        #expect(Set(json.keys) == ["schema", "track", "revision", "physics", "players"])
        #expect(json["schema"] as? Int == 1)
        #expect(json["track"] as? String == "ardennes")
    }

    @Test func aFriendsQueryNamesEachFriendOnceAndAtMostAHundred() throws {
        let tokens = (0..<150).map { ApexOnline.playerToken("T:_\($0)") }
        let query = try #require(ApexService.friendsQuery(tokens + tokens, on: board))
        #expect(query.players.count == ApexService.friendsPerQuery)
        #expect(Set(query.players).count == query.players.count)
        #expect(ApexService.friendsQuery([], on: board) == nil)
    }

    @Test func friendsAreNamedFromGameCenterAndOrderedFastestFirst() throws {
        let json = #"{"friends":[{"player":"b","ms":28150},{"player":"a","ms":27900},{"player":"stranger","ms":26000}]}"#
        let answer = try JSONDecoder().decode(FriendsAnswer.self, from: Data(json.utf8))
        let friends = FriendTime.list(answer.friends, names: ["a": "Alice", "b": "Bob"])
        #expect(friends.map(\.name) == ["Alice", "Bob"])
        #expect(friends.first?.time == 27.9)
    }

    @Test func thePickedFriendIsKeptPerCircuitUntilAutoIsPicked() throws {
        let defaults = try #require(UserDefaults(suiteName: "FriendTests"))
        defer { defaults.removePersistentDomain(forName: "FriendTests") }
        let me = ApexOnline.playerToken("T:_me")
        let swirl = RaceBoard(track: Track(.swirl))
        let pick = FriendPick.Pick(token: ApexOnline.playerToken("T:_a"), name: "Alice")
        FriendPick.save(pick, on: board, player: me, defaults: defaults)
        #expect(FriendPick.load(on: board, player: me, defaults: defaults) == pick)
        #expect(FriendPick.load(on: swirl, player: me, defaults: defaults) == nil)
        FriendPick.save(nil, on: board, player: me, defaults: defaults)
        #expect(FriendPick.load(on: board, player: me, defaults: defaults) == nil)
    }

    /// Another Game Center account on the device, or none, doesn't race the friend someone else picked.
    @Test func aPickBelongsToThePlayerWhoMadeIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "FriendTests.players"))
        defer { defaults.removePersistentDomain(forName: "FriendTests.players") }
        let me = ApexOnline.playerToken("T:_me"), sibling = ApexOnline.playerToken("T:_sibling")
        FriendPick.save(.init(token: ApexOnline.playerToken("T:_a"), name: "Alice"), on: board, player: me, defaults: defaults)
        #expect(FriendPick.load(on: board, player: sibling, defaults: defaults) == nil)
        #expect(FriendPick.load(on: board, player: nil, defaults: defaults) == nil)
        FriendPick.save(.init(token: "x", name: "X"), on: board, player: nil, defaults: defaults)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("apex.raceFriend") }.count == 1)
    }
}
