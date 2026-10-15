# Agent notes

One iOS app, **Apex** (`Apex/`), with unit tests in `ApexTests/`. `README.md` has the tour of the files and the
tuning table.

## Build and test

Tests run on a simulator; any iPhone simulator works (`iPhone 17 Pro` is an example).

```bash
xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Unit-test the game logic (track
geometry, physics, timing, saves); the SpriteKit scene is checked by running the app. Keep the build warning-free:
CI (`.github/workflows/tests.yml`) runs the tests and a Release build on every PR, with warnings as errors.

## Conventions

- **Xcode picks up new files automatically.** The project uses folder-synced groups, so add files under `Apex/` or
  `ApexTests/` without editing `project.pbxproj`.
- **Tuning constants stay in one place:** `RaceTuning` in `Apex/RaceTuning.swift`.
- **Lap times are pinned by bots.** `LapTimeTests` drives laps with the player's one control at several skill levels.
  A change to physics, tuning or the circuit that moves lap times should move them on purpose: print the table with
  `-only-testing:ApexTests/LapTimeTests/report(id:)` and update the ranges, the medal times
  (`RaceTuning.medalTimes`, which are bot laps) and the README's table together.
- **Circuits are segment lists** (`TrackLayout`). Keep the two closing straights long and running in different
  directions; `TrackTests` checks every circuit closes, never overlaps itself, and fits its corners, and
  `LapTimeTests` holds each to the same bot lap times. To add one: add it to `TrackLayout.all`, record its
  signature in `FreezeTests`, add its board to BrightBench's `apexBoards` (deployed before the app ships), and
  create its Game Center leaderboard.
- **Saved best laps are keyed by circuit and tuning** (`LapStore.key`), so changing either starts a fresh best lap.
  Add any new constant that changes how fast a lap can be to `RaceTuning.lapSignature`.
- **Freeze boards before they're live.** Leaderboards are per `RaceBoard` (circuit, revision, physics version).
  Once a board has public times, a change that moves lap times needs a new `RaceTuning.physicsVersion` or circuit
  `revision`, a new Game Center leaderboard, and the new signature recorded in `FreezeTests`. Ask Kraig first.
- **The lap service's wire format is shared** with BrightBench (`apps/marketing/src/lib/apex-laps.ts`). Change both
  together, and keep the service's privacy rules: laps are anonymous counters; only a salted hash of a Game Center
  player ID is stored, with the player's public alias, best time and ghost.
- **Anything over the race holds it** (`RaceHUD.holdsRace`): panels, the ⚙︎ menu, Game Center and an inactive app.
  Something new that covers the race (a panel, a sheet) adds itself there, or the lap clock runs on under it.
- **Draw order:** the SpriteView ignores sibling order, so anything that overlaps needs its own depth
  (`TrackArt.Depth`).
- **Debug-only tools go behind `#if DEBUG`**, like the autopilot and FPS launch arguments and the tuning panel
  (`Tuner`). Tuned laps stay off the boards: anything that uploads or submits a lap checks `RaceTuning.isStock`.
