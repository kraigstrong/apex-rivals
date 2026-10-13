# Apex Rivals on TestFlight

How to get an Apex Rivals beta to friends, so you can race each other's times and ghosts.

## What the build has

- Bundle ID `com.kraigstrong.apex`, team `MKACSCQ588`, automatic signing. Version 0.1.0. iPhone and iPad (full
  screen), landscape.
- App icon (`Art/make-icon.py` draws it; no alpha) and the system launch screen.
- `ITSAppUsesNonExemptEncryption = NO`: the only encryption is the system's HTTPS.
- Category: Racing games.
- Game Center (`Apex/Apex.entitlements`): sign-in at launch, each personal best submitted to the circuit's
  leaderboard, and the trophy button opening the friends board.
- The lap service is on (`ApexOnline.isEnabled`): every lap counted anonymously at `brightbench.app/api/apex/laps`,
  each personal best's ghost shared under the player's Game Center alias, rivals from other players' ghosts, and real
  standings at the end of a session. Lap batches are tagged `testflight` for beta installs.
- Privacy manifest (`Apex/PrivacyInfo.xcprivacy`): UserDefaults for best laps and the lap queue; anonymous lap
  counts; gameplay content (ghosts) and a user ID (the Game Center player ID, salted and hashed on the server), linked
  to the player for the leaderboard, not used for tracking.
- The Release build has none of the debug tools: no autopilot, FPS counter, or sample standings.

## Before the first build

1. **The lap service is live.** Merge and deploy kraigstrong/BrightBench#69, set `APEX_APP_KEY` (`apex-laps-v1`) and
   `APEX_PLAYER_SALT` (a long random secret that must never change) on the marketing project in Vercel, and add a
   Vercel Firewall rate limit on `/api/apex/*`. Then check it answers:

   ```bash
   # No one has a lap yet: no rival (204), and standings of no players.
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=ardennes&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   curl -s "https://brightbench.app/api/apex/standing?track=ardennes&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   # A made-up circuit is refused (400), and so is a request without the key (401).
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=nowhere&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=ardennes&revision=1&physics=1&ms=29500"
   ```

2. **The app record** (first time only). In App Store Connect, go to Apps, then + New App. Choose iOS, name it Apex
   Rivals, pick the `com.kraigstrong.apex` bundle ID, and use `apex` as the SKU. If the bundle ID isn't in the list,
   archiving once with automatic signing registers it.
3. **Game Center.** On the app's Services tab, add a Classic Leaderboard for each circuit: `apex.ardennes.r1.p1`,
   `apex.swirl.r1.p1`, `apex.snake.r1.p1`, `apex.mirage.r1.p1`, `apex.island.r1.p1` and `apex.harbour.r1.p1`. Score
   format: Elapsed Time, to the hundredth of a second. Sort: low to high. Reference name and display name: the
   circuit's name.

## Uploading a build

1. **Archive.** Check out `main` at the commit you want and tag it (`apex-v0.1-beta.1`). In Xcode, choose the Apex
   scheme and Any iOS Device (arm64), then Product > Archive.
2. **Upload.** In the Organizer, choose Distribute App > App Store Connect > Upload. Leave "Manage Version and Build
   Number" on so each upload gets a new build number.
3. **Internal test.** When the build finishes processing, add yourself to an internal group, install it from
   TestFlight, and run the smoke check below.
4. **External test.** Create an external group (Friends), fill in Test Information (a beta description and feedback
   email), add the build, and submit it for beta review. The first build of a version is reviewed by Apple. Once it's
   approved, invite friends by email or with a public link. Ask them to sign in to Game Center (Settings > Game
   Center) and to add each other as Game Center friends: the friends board and their ghosts depend on it.
5. **Record it** in the build log at the end of this file.

## Smoke check on the TestFlight build

On a physical iPhone, signed in to Game Center, with a fresh install:

- The Game Center welcome banner shows at launch, then the track list: Apex School first (marked Practice), then the
  six circuits, scrolling sideways.
- Apex School: the yellow line, TURN IN / APEX / EXIT, the coach's three cues with a tick at turn-in and the apex,
  a verdict after each corner, your trail, and no ghosts. The house button goes straight back to the list.
- Each circuit: a lap is timed, splits show at sectors 1 and 2, and the live delta shows after the first lap. A new
  best lap shows the purple banner; the blue ghost replays it on the next lap.
- The gold rival is a Pace bot at first (no one else has a time). Beating it brings a new one.
- The flag ends a session: the summary shows your best lap and, with no one else on the board yet, "You're the
  first!" The trophy opens the circuit's leaderboard with your time on it.
- Best laps survive force-quitting and reopening. Background the app mid-lap: the session ends and its summary is
  waiting on return.

With a second phone on a different Game Center account (a friend's, or a test account):

- Set a lap on the same circuit on both, the second phone a little faster (0.2–3 s). Relaunch the slower phone and
  open that circuit: its rival is the faster player's ghost, named with their Game Center alias.
- The flag on either phone shows a real standing: "#1 of 2" or "#2 of 2", and the histogram.
- Both times show on the circuit's leaderboard (friends board if you're Game Center friends, global board either
  way).
- In Airplane Mode, laps still save on the device; back online, the next lap sends the queued ones.

## Build log

| Version | Build | Commit | Notes |
| --- | --- | --- | --- |
| 0.1.0 | | | First beta: six circuits, Apex School, Game Center, lap service. |
