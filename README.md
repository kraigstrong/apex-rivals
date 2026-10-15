# Apex

A one-touch time-trial racer for iPhone and iPad (landscape, SwiftUI + SpriteKit, iOS 17+). Working title.

**Hold to steer up. Let go to steer down.** Pick a circuit from the track list and set the fastest lap you can. A
good lap is about 30 seconds on each. The six circuits are original, each with the feel of a famous F1 track:

- **Ardennes** (clockwise): a hairpin, a plunging left-right-left, a long straight to a twisty far end, a fast
  sweep home.
- **Swirl**: a hairpin at the top of the hill, esses across the top, a stadium section and a three-apex swirl.
- **Snake**: a double right into esses up the hill, a hairpin, a fast sweep and a chicane.
- **Mirage**: a long straight into a hairpin, an angular stadium climb and a hairpin at the top.
- **Island**: long and narrow, chicanes down both sides and a hairpin at the far end.
- **Harbor** (clockwise): a street circuit with a climb, a hairpin, a curving tunnel and a swimming-pool wiggle.

They were sketched as track maps, a polygon of corner points each rounded with its own radius, then exported to the
game's straights and corners; see `TrackLayout`.

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
- **Race a friend**: the ⚙︎ menu lists your Game Center friends with a time on the circuit (fastest first, with how
  far ahead or behind you they are). Pick one and their best lap is your gold rival, on this circuit, until you pick
  Auto again; beating them doesn't swap them out. The pick belongs to your Game Center account, so another account on
  the same device starts on Auto, and a friend who's no longer one is dropped the next time the list loads. The first time, Game Center asks whether to share your friends
  list. Offline, or if their lap can't be found, the rival is the usual pick until it can.
- **Medals**: bronze, silver, gold and platinum on each circuit, for beating a bot's lap there (see Tuning): a sloppy
  weaver's, the middle of the road's, and the ideal line's at human reaction speed (90 ms) and at a quick 50 ms. The
  track list shows each circuit's best medal and the next to chase (an outline and its time), as does the start card.
  The timing panel shows the best lap's medal, and a lap that wins a new one says so in its banner. Only the stock car
  wins medals; Apex School has none.
- **Achievements**: each medal on each circuit is also a Game Center achievement (`apex.ardennes.gold`); winning
  gold earns bronze and silver with it. A best lap reports its medals as it's set, and signing in reports any the saved
  best laps won while signed out or offline. Game Center's own banner stays off, since the lap banner already names the
  medal.
- **Leaderboards**: the trophy opens Game Center's leaderboard for the circuit. Each new personal best is submitted.
- **Apex School**: the button top left of the track list (yellow, marked START HERE, until you've graduated or
  skipped it). A short tutorial with a goal: hit 2 apexes, each turned in to from wide (riding the inside wall doesn't
  count), and a "You're ready" card sends you to the track list to pick a circuit (or lets you keep practicing). SKIP bails straight to the track list. It's a practice square of four identical right-angle corners, with
  the ideal line painted on, TURN IN / APEX / EXIT markers at every corner, a coach with one big cue that changes
  three times a corner (STAY WIDE, then LET GO at turn-in to dive for the apex, then HOLD to ease back out on a
  right-hander) with a haptic tick at turn-in and at the apex, a verdict after every
  corner (how wide of the apex, and your slowest speed against the ideal line's), and your own line traced behind the
  car. No ghosts or rival: the line is the guide. No leaderboard; nothing leaves the device.
- **Track list**: the house button heads back to it (through the session summary, if you finished a lap).
- **Session summary**: the checkered flag ends a session (so does leaving the app); it's dimmed until you finish a
  lap, since there's nothing to sum up before that. The summary shows the session's best lap, its medal (NEW the
  first time) and the next one to chase, and its standing among other players' bests. First place says "Fastest". A
  board of fewer than 10 players shows your place ("3rd of 5") and a dot for each player, yours in your car's color;
  a bigger one shows the top share you're in ("Top 12%", or your place in the slower half) over a histogram of
  everyone's times, the players you beat lit. The share card words it the same way. Xcode builds show labeled sample
  players while the lap service is off.
- **Share**: the summary's SHARE button opens the share sheet with a picture of the session's best lap (the circuit
  drawn to scale with your line on it in your car's color, the time, its medal and, if it beats anyone, its standing) and a line of text:
  "27.843 at Ardennes in Apex Rivals, a gold medal lap. Beat it:" and the link to the game (`ApexLinks.join`, the
  public TestFlight link for now).
- **Ideal line**: the ⚙︎ menu draws the minimum-curvature line on the track. The menu also clears your best lap.
- **Holding still**: the race holds while anything is over it (the ⚙︎ menu or a panel from it, Game Center's
  leaderboard, Control Center or a call) and picks up where it was once it's gone: the lap clock, the car and the
  ghosts all wait. Only leaving the app ends the session.

## Online

Rankings live in Game Center; everything Game Center can't hold lives in the Apex lap service on BrightBench
(`apps/marketing`, `/api/apex/*`; its README describes the routes and what they store):

- every finished lap, counted anonymously into lap-time histograms per board;
- each player's best lap and ghost, uploaded with Game Center's identity signature, which rivals, friends' laps and
  session standings come from.

Both are per **board** (`RaceBoard`): a circuit at one revision, driven with one physics version. Lap times only
compare within a board, so **once a board is live, freeze it**: a change that moves lap times needs a new
`RaceTuning.physicsVersion` (or the circuit's `revision`), and with it a new Game Center leaderboard.
`FreezeTests` pins the physics and every circuit to their versions and fails until a change is given one.

The service is on (`ApexOnline.isEnabled`). When it can't be reached, laps queue on the device (`LapLog`) and send
later, rivals are bots, and the session summary says standings will show once you're online. On a board with only a
few players, the rival is the nearest player who beats you at all, up to 3 s ahead, before falling back to a bot.
Race a friend asks the service which friends have a best on the board, naming them by the same token the app names
the player by (`ApexOnline.playerToken`, a hash of the team player ID, sent in a body or header, never a URL); the
service stores nothing for it.
`docs/apex-testflight.md` covers what has to be live before a build ships (the BrightBench routes and their
secrets, and the Game Center leaderboards) and the smoke check, including racing a second account's ghost.

## Running

Open `Apex.xcodeproj`, pick an iPhone, iPad or simulator, and Run. The app icon is drawn by `Art/make-icon.py`
(`python3 Art/make-icon.py` rewrites it). The achievements' art in `Art/achievements` (each circuit inside a ring in the
medal's color) is drawn by `AchievementArtTests`, which only runs when asked:
`TEST_RUNNER_APEX_DRAW_ACHIEVEMENTS=1 xcodebuild test ... -only-testing:ApexTests/AchievementArtTests`. Signing uses
automatic signing with team `MKACSCQ588`.

```bash
xcodebuild test -project Apex.xcodeproj -scheme Apex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

GitHub Actions runs the same tests on every pull request and push to `main` (`.github/workflows/tests.yml`), and
builds Release too. Any build warning fails it. It uses Xcode 26.4, the version the project is built with; to move
Xcode, change `DEVELOPER_DIR` there.

Launch arguments for Xcode (Debug) builds, in the scheme's Run options or `xcrun simctl launch ... <args>`:

- `-ApexAutopilot perfect` drives the ideal line perfectly; `-ApexAutopilot human` drives it at human reaction
  speed, so laps vary and the ghost shows. Autopilot laps are never saved.
- `-ApexShowFPS YES` shows frame rate, node and draw counts.
- `-ApexTrack snake` skips the track list and opens that circuit's race (`ardennes`, `swirl`, `snake`, `mirage`,
  `island`, `harbor`, or `apex_school`). An unknown id shows the list. With `-ApexAutopilot`, it makes simulator
  checks scriptable: launch, then `xcrun simctl io <udid> screenshot <file>`.

## Tuning

Every feel constant is in `Apex/RaceTuning.swift`. Bots in `LapTimeTests` pin down how hard the game is, using the
player's one control. Four of them set the medals (`RaceTuning.medalTimes`, these laps to the tenth):

| Driver | Medal | Ardennes | Swirl | Snake | Mirage | Island | Harbor |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Perfect, on the ideal line | | 25.9s | 25.8s | 25.4s | 26.4s | 26.8s | 24.9s |
| Deciding every 50 ms, on the ideal line | Platinum | 26.6s | 26.7s | 26.3s | 27.0s | 27.1s | 25.7s |
| Deciding every ~90 ms, on the ideal line | Gold | 28.5s | 28.9s | 28.5s | 28.7s | 28.8s | 27.7s |
| Deciding every ~90 ms, middle of the road | Silver | 29.8s | 30.2s | 30.0s | 30.0s | 29.7s | 30.0s |
| Sloppy weaver, middle of the road | Bronze | 35.8s | 35.5s | 34.6s | 36.2s | 36.7s | 34.7s |

After a retune, print the table with
`xcodebuild test ... '-only-testing:ApexTests/LapTimeTests/report(id:)'` (lines start with `LAPTIME`), and if the
change was meant to move lap times, update the ranges in `LapTimeTests`, the medal times and this table together
(`medalsAreTheBotsLaps` fails while a medal is more than a quarter second off its bot). The knobs that matter most:

- `straightnessLength`: longer forgives more weaving; shorter punishes every correction.
- `grip`: higher makes corners faster and lines matter less.
- `steerRate` / `steerReturn`: how quickly the nose swings, and the angle it settles at when you hold.
- `topSpeed`, `acceleration`, `braking`: pace, and how much a slow exit costs.
- `viewWidthSlow` / `viewWidthFast`, `camera*`: how much track you see and how the camera turns.

Best laps are saved per circuit and per version of the tuning (`RaceTuning.lapSignature`), so a retune starts a
fresh best lap.

To feel a change before making it, use the tuning panel in Xcode (Debug) builds: ⚙︎ → **Tune controls** in a race.
It has sliders for steering, return, smoothing, grip and acceleration (plus the camera's look-ahead, which only
changes how the race is drawn), and shows what the bots lap in on that circuit,
tuned against stock. Changes apply at once and last across launches. A tuned car keeps its own best laps and never
uploads a lap or submits to Game Center (`RaceTuning.isStock`). **Reset** puts the stock car back. Once a setting
feels right, copy it into `RaceTuning.swift` and update the lap times as above.

## Layout

- `Apex/TrackLayout.swift`: circuits as pieces you'd drive: straights and constant-radius corners. Two straights
  (`closingStraights`) are solved so the loop closes exactly, so corners can be tuned freely. `TrackLayout.all` is
  the track list.
- `Apex/TrackMenu.swift`: the track list, and `TrackCatalog`, which builds each circuit's geometry once.
- `Apex/Logo.swift`: the NEEDLE logo at the top of the track list: your car, in its paint, towing its racing line
  through the letters, in front of one and behind the next.
- `Apex/ApexSchool.swift`: the practice circuit, `ApexGuide` (each corner's turn-in, apex and exit on the ideal line,
  and the coach's cues) and `CornerJudge` (the verdict after each corner).
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
- `Apex/Medals.swift`: medals: which one a lap wins on a circuit, the next to chase, and how they're drawn.
- `Apex/Achievements.swift`: medals as Game Center achievements, and `Achievements`, which reports them.
- `Apex/ShareCard.swift`: sharing a lap: the picture (`ShareCard`, with `LapLineMap` drawing its line), its text, and
  `ApexLinks.join`, where a shared lap sends people.
- `Apex/RaceBoard.swift`, `Apex/GameCenter.swift`, `Apex/ApexOnline.swift`: boards, Game Center, and the lap service
  (the lap log queue, ghost sharing, rival lookup and friends' laps).
- `Apex/Friends.swift`: Race a friend: Game Center's friends list, the friend each player picked on each board
  (`FriendPick`), and the picker.
- `Apex/RaceScene.swift`: the SpriteKit scene: touches, camera, car, ghost, skid marks, sparks, culling.
- `Apex/TrackArt.swift`: procedural art: track pieces, curbs, start line, the car, and the grass shader.
- `Apex/Scenery.swift`: trees, grandstands and tire walls, placed from each circuit's shape and kept clear of the
  track (`SceneryTests` checks every circuit).
- `Apex/RaceAudio.swift`: the sound, synthesized live: a growling engine whose firings quicken with speed (silent on
  the grid and under the cards), tire scrub, curbs, walls, cues and a synthwave loop (settings from the Apex Sound
  Lab). Sound and music switch off from the ⚙︎ menu.
- `Apex/RaceHUD.swift`, `Apex/ContentView.swift`: the SwiftUI overlay: timing, splits, speed, map and menu.

## License

The source code is under the [PolyForm Noncommercial License 1.0.0](LICENSE): free to read, learn from, and use
for noncommercial purposes, but not in anything commercial. (The license also permits any use by charities,
schools, and public and government institutions; see its Noncommercial Organizations section.) The names, icons,
art, and videos are all rights reserved.
