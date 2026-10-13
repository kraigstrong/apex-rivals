# Agent notes

One iOS app, **Apex** (`Apex/`), with unit tests in `ApexTests/`. `README.md` has the tour of the files and the
tuning table.

## Build and test

Tests run on a simulator; any iPhone simulator works (`iPhone 17 Pro` is an example).

```bash
xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Unit-test the game logic (track
geometry, physics, timing, saves); the SpriteKit scene is checked by running the app. Keep the build warning-free.

## Conventions

- **Xcode picks up new files automatically.** The project uses folder-synced groups, so add files under `Apex/` or
  `ApexTests/` without editing `project.pbxproj`.
- **Tuning constants stay in one place:** `RaceTuning` in `Apex/RaceTuning.swift`.
- **Lap times are pinned by bots.** `LapTimeTests` drives laps with the player's one control at several skill levels.
  A change to physics, tuning or the circuit that moves lap times should move them on purpose: print the table with
  `-only-testing:ApexTests/LapTimeTests/report()` and update the ranges and the README's table together.
- **Circuits are segment lists** (`TrackLayout`). Keep the two closing straights long and running in different
  directions; `TrackTests` checks the loop closes, never overlaps itself, and fits its corners.
- **Saved best laps are keyed by circuit and tuning** (`LapStore.key`), so changing either starts a fresh best lap.
  Add any new constant that changes how fast a lap can be to `RaceTuning.lapSignature`.
- **Freeze boards before they're live.** Leaderboards are per `RaceBoard` (circuit, revision, physics version).
  Once a board has public times, a change that moves lap times needs a new `RaceTuning.physicsVersion` or circuit
  `revision`, a new Game Center leaderboard, and the new signature recorded in `FreezeTests`. Ask Kraig first.
- **The lap service's wire format is shared** with BrightBench (`apps/marketing/src/lib/apex-laps.ts`). Change both
  together, and keep the service's privacy rules: laps are anonymous counters; only a salted hash of a Game Center
  player ID is stored, with the player's public alias, best time and ghost.
- **Draw order:** the SpriteView ignores sibling order, so anything that overlaps needs its own depth
  (`TrackArt.Depth`).
- **Debug-only tools go behind `#if DEBUG`**, like the autopilot and FPS launch arguments.
