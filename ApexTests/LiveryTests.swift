import Foundation
import Testing
@testable import Apex

struct LiveryTests {
    func fresh(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsRedWithASkyBlueGhostAndAYellowRival() throws {
        let livery = Livery(defaults: try fresh("LiveryTests.defaults"))
        #expect(livery.paint(for: .car) == .racingRed)
        #expect(livery.paint(for: .best) == .skyBlue)
        #expect(livery.paint(for: .rival) == .yellow)
    }

    @Test func pickingAPaintAnotherCarHasSwapsThem() throws {
        let livery = Livery(defaults: try fresh("LiveryTests.swap"))
        livery.set(.orange, for: .car)
        #expect(livery.paint(for: .car) == .orange)
        // The rival's yellow, picked for the car: the rival takes the car's orange.
        livery.set(.yellow, for: .car)
        #expect(livery.paint(for: .car) == .yellow)
        #expect(livery.paint(for: .rival) == .orange)
        #expect(Set(Livery.Role.allCases.map(livery.paint(for:))).count == 3)
    }

    @Test func choicesSurviveARelaunch() throws {
        let defaults = try fresh("LiveryTests.saved")
        let livery = Livery(defaults: defaults)
        livery.set(.orange, for: .car)
        livery.set(.navy, for: .best)
        let reopened = Livery(defaults: defaults)
        #expect(reopened.paint(for: .car) == .orange)
        #expect(reopened.paint(for: .best) == .navy)
        #expect(reopened.paint(for: .rival) == .yellow)
    }

    @Test func everyChangeRepaints() throws {
        let livery = Livery(defaults: try fresh("LiveryTests.version"))
        let before = livery.version
        livery.set(.teal, for: .rival)
        livery.set(.teal, for: .rival)
        #expect(livery.version == before + 1)
    }

    /// Colors in the spirit of F1 teams', named for the color alone.
    @Test func paintsAreNamedForTheirColorsOnly() {
        let teams = ["ferrari", "mclaren", "mercedes", "red bull", "aston", "alpine", "williams", "haas", "sauber",
                     "racing bulls", "papaya", "audi", "cadillac"]
        for paint in Paint.allCases {
            #expect(!teams.contains { paint.name.lowercased().contains($0) }, "\(paint.name)")
        }
        #expect(Paint.allCases.contains(.orange))
        #expect(Set(Paint.allCases.map(\.name)).count == Paint.allCases.count)
    }

    @Test func aYellowCarGetsAWhiteHelmet() {
        #expect(Paint.yellow.helmet != Paint.yellow.body)
        #expect(Paint.racingRed.helmet != Paint.racingRed.body)
    }
}
