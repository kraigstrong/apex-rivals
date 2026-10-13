# Apex

A one-touch time-trial racer for iPhone and iPad (landscape, SwiftUI + SpriteKit, iOS 17+). Working title.

**Hold to steer up. Let go to steer down.** Set the fastest lap you can around Harbour Park, an original circuit
with the bones of an F1 track. A good lap is about 30 seconds.

## The idea

The control is Bigger Fish's: holding swings the car's nose toward the top of the screen, letting go swings it
toward the bottom, and it eases back toward the track's direction either way. The camera turns with the track, so
the road ahead always runs left to right and "up" is always the car's left. In a hairpin the world swings around
rather than asking you to steer backwards.

**Speed comes from how straight you drive.** The car's heading is smoothed over the last 90 units of travel, and the
curvature of that smoothed path caps the speed: `√(grip / κ)`. So:

- quick taps to hold a line are nearly free, but slow weaves bend the path and cost speed;
- following the inside of a corner is slow, while swinging wide, clipping the apex and running out wide bends the
  path least and carries the most speed;
- speed drops fast and comes back slowly, so a scruffy exit costs you all the way down the next straight.

Walls bounce you back with a speed penalty (more for a square hit than a glancing one), and the car never stops, so
every lap finishes.

What the game shows you:

- **Ghost**: your best lap replays as a blue car (and a blue dot on the map). Best laps are saved on the device.
- **Splits**: at the end of sectors 1 and 2, and at the line, against your best lap: green faster, yellow slower,
  purple for a new best.
- **Speed loss**: skid marks whenever the line is braking the car, the speed readout warms toward red, and the speed
  bar has an orange tick at the most your current line allows.
- **Live delta**: next to the lap timer, how far behind (red) or ahead (green) of your best lap you are at this
  point of the lap, so you can see which corner the time goes in.
- **Rival**: a gold ghost a little faster than your best (`RaceTuning.rivalGap`, 0.4 s) to chase. It's another
  player's best lap when the lap service has one close enough, otherwise a bot driving the ideal line at whatever
  reaction speed beats you by that much, so it also shows you the line. Beat it and a new one takes its place.
- **Leaderboards**: the trophy opens Game Center's leaderboard for the circuit. Each new personal best is submitted.
- **Session summary**: the chequered flag ends a session (so does leaving the app). The summary shows the session's
  best lap and where it falls among other players' bests: the share it beats, its place, and a histogram of everyone's
  times with yours marked. Xcode builds show labelled sample players while the lap service is off.
- **Ideal line**: the ••• menu draws the minimum-curvature line on the track. The menu also clears your best lap.

## Online

Rankings live in Game Center; everything Game Center can't hold lives in the Apex lap service on BrightBench
(`apps/marketing`, `/api/apex/*`; its README describes the routes and what they store):

- every finished lap, counted anonymously into lap-time histograms per board;
- each player's best lap and ghost, uploaded with Game Center's identity signature, which rivals and session
  standings come from.

Both are per **board** (`RaceBoard`): a circuit at one revision, driven with one physics version. Lap times only
compare within a board, so **once a board is live, freeze it**: a change that moves lap times needs a new
`RaceTuning.physicsVersion` (or the circuit's `revision`), and with it a new Game Center leaderboard.
`FreezeTests` pins the physics and every circuit to their versions and fails until a change is given one.

The service is off (`ApexOnline.isEnabled = false`) until the routes are deployed. With it off, laps queue on the
device (`LapLog`) and rivals are bots. To go live:

1. App Store Connect: create the app (`com.kraigstrong.apex`), enable Game Center, and add a leaderboard for each
   board, ID `apex.harbour_park.r1.p1`, score format Elapsed Time to the hundredth of a second, sorted low to high.
2. BrightBench: set `APEX_APP_KEY` (`apex-laps-v1`) and `APEX_PLAYER_SALT` in the marketing project, add Vercel rate
   limits for `/api/apex/*`, and deploy.
3. Set `ApexOnline.isEnabled = true`.

## Running

Open `Apex.xcodeproj`, pick an iPhone, iPad or simulator, and Run. Signing uses automatic signing with team
`MKACSCQ588`.

```bash
xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Launch arguments for Xcode (Debug) builds, in the scheme's Run options or `xcrun simctl launch ... <args>`:

- `-ApexAutopilot perfect` drives the ideal line perfectly; `-ApexAutopilot human` drives it at human reaction
  speed, so laps vary and the ghost shows. Autopilot laps are never saved.
- `-ApexShowFPS YES` shows frame rate, node and draw counts.

## Tuning

Every feel constant is in `Apex/RaceTuning.swift`. Bots in `LapTimeTests` pin down how hard the game is, using the
player's one control:

| Driver | Lap |
| --- | --- |
| Perfect, on the ideal line | 25.7s |
| Deciding every 50 ms, ideal line | 26.6s |
| Deciding every ~90 ms (human), ideal line | 28.5s |
| Deciding every ~90 ms, middle of the road | 30.0s |
| Sloppy weaver, middle of the road | 37.0s |

After a retune, print the table with
`xcodebuild test ... '-only-testing:ApexTests/LapTimeTests/report()'` (lines start with `LAPTIME`) and update the
ranges in `LapTimeTests` if the change was meant to move them. The knobs that matter most:

- `straightnessLength`: longer forgives more weaving; shorter punishes every correction.
- `grip`: higher makes corners faster and lines matter less.
- `steerRate` / `steerReturn`: how quickly the nose swings, and the angle it settles at when you hold.
- `topSpeed`, `acceleration`, `braking`: pace, and how much a slow exit costs.
- `viewWidthSlow` / `viewWidthFast`, `camera*`: how much track you see and how the camera turns.

Best laps are saved per circuit and per version of the tuning (`RaceTuning.lapSignature`), so a retune starts a
fresh best lap.

## Layout

- `Apex/TrackLayout.swift`: circuits as pieces you'd drive: straights and constant-radius corners. Two straights
  (`closingStraights`) are solved so the loop closes exactly, so corners can be tuned freely.
- `Apex/Track.swift`: turns a layout into geometry sampled every unit: centerline, heading, curvature (box-filtered
  so corners ease in), and a smoothed heading for the camera. Positions are (s, n): distance from the line, and offset
  left of the centerline.
- `Apex/CarPhysics.swift`: the car in track coordinates and one fixed physics step: steering, the straightness speed
  rule, and walls.
- `Apex/RaceSession.swift`: the car, laps and a fixed 240 Hz clock with no drawing; the scene and tests both drive it.
- `Apex/LapTimer.swift`: laps and sectors (interpolated within a step), ghost recording, and `LapStore` for saved
  best laps.
- `Apex/RacingLine.swift`: the minimum-curvature line (LAPACK), for the ideal-line overlay and the fastest bot.
- `Apex/AutoDriver.swift`: a bot that drives with hold/let-go to follow a line.
- `Apex/Rivals.swift`: rivals, bot rivals tuned to a target lap time, and `RivalScout`, which picks the next one.
- `Apex/RaceBoard.swift`, `Apex/GameCenter.swift`, `Apex/ApexOnline.swift`: boards, Game Center, and the lap service
  (the lap log queue, ghost sharing and rival lookup).
- `Apex/RaceScene.swift`: the SpriteKit scene: touches, camera, car, ghost, skid marks, sparks, culling.
- `Apex/TrackArt.swift`: procedural art: track pieces, kerbs, start line, the car, and the grass shader.
- `Apex/RaceHUD.swift`, `Apex/ContentView.swift`: the SwiftUI overlay: timing, splits, speed, map and menu.
