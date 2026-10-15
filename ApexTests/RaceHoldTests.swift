import Testing
import UIKit
@testable import Apex

/// The race holds still while anything is over it, and picks up where it was once nothing is.
struct RaceHoldTests {
    static let track = Track(.ardennes)

    /// A HUD with Game Center's leaderboard down, whatever this device's Game Center is doing.
    func hud() -> RaceHUD {
        let hud = RaceHUD(track: Self.track)
        hud.showsLeaderboard = { false }
        return hud
    }

    func titles(_ hud: RaceHUD) -> [String] {
        RaceMenu.items(for: hud).map(\.title)
    }

    func item(_ title: String, _ hud: RaceHUD) -> UIAction? {
        RaceMenu.items(for: hud).first { $0.title == title } as? UIAction
    }

    @Test func nothingOverTheRaceLetsItRun() {
        #expect(!hud().holdsRace)
    }

    @Test func everyPanelHoldsTheRace() {
        var panels: [ReferenceWritableKeyPath<RaceHUD, Bool>] = [\.showsColors, \.showsFriends, \.showsGraduation]
        #if DEBUG
        panels.append(\.showsTuner)
        #endif
        for panel in panels {
            let hud = hud()
            hud[keyPath: panel] = true
            #expect(hud.showsPanel && hud.holdsRace)
        }
    }

    /// The ⚙︎ menu holds the race without being a panel, so the timing and the button the menu hangs from stay put.
    @Test func theMenuHoldsTheRaceInView() {
        let hud = hud()
        hud.showsMenu = true
        #expect(hud.holdsRace)
        #expect(!hud.showsPanel)
        hud.showsMenu = false
        #expect(!hud.holdsRace)
    }

    /// Game Center's leaderboard holds the race for as long as it's up, as does anything that takes the app out of
    /// the front (Control Center, a call).
    @Test func gameCenterAndTheSystemHoldTheRace() {
        let hud = hud()
        var leaderboardUp = true
        hud.showsLeaderboard = { leaderboardUp }
        #expect(hud.holdsRace)
        leaderboardUp = false
        #expect(!hud.holdsRace)
        hud.isAppActive = false
        #expect(hud.holdsRace)
        hud.isAppActive = true
        #expect(!hud.holdsRace)
    }

    /// The button tells the race as its menu opens, and again as it closes, whether on a pick or a tap elsewhere.
    @MainActor @Test func theButtonSaysWhenItsMenuIsOpen() throws {
        let hud = hud()
        let button = RaceMenu.button(for: hud)
        let interaction = try #require(button.contextMenuInteraction)
        #expect(button.showsMenuAsPrimaryAction)
        #expect(button.accessibilityLabel == "Settings")
        button.contextMenuInteraction(interaction, willDisplayMenuFor: UIContextMenuConfiguration(), animator: nil)
        #expect(hud.showsMenu && hud.holdsRace)
        button.contextMenuInteraction(interaction, willEndFor: UIContextMenuConfiguration(), animator: nil)
        #expect(!hud.showsMenu && !hud.holdsRace)
    }

    /// The menu is built as it opens, so it shows the race as it is then.
    @MainActor @Test func theMenuShowsTheRaceAsItIs() throws {
        let hud = hud()
        #expect(titles(hud).first == "Show ideal line")
        #expect(titles(hud).contains("Race a friend"))
        #expect(item("Sound", hud)?.state == (RaceAudio.shared.soundOn ? .on : .off))
        #expect(item("Music", hud)?.state == (RaceAudio.shared.musicOn ? .on : .off))
        #expect(item("Clear best lap", hud)?.attributes.contains(.destructive) == true)
        hud.showsRacingLine = true
        #expect(titles(hud).first == "Hide ideal line")
        // Apex School has no friends' laps to race.
        hud.isPractice = true
        #expect(!titles(hud).contains("Race a friend"))
    }

    /// Car colors opens its panel from the menu, which keeps the race held as the menu closes.
    @MainActor @Test func carColorsOpensItsPanel() throws {
        let hud = hud()
        try #require(item("Car colors", hud)).performWithSender(nil, target: nil)
        #expect(hud.showsColors && hud.holdsRace)
    }
}
