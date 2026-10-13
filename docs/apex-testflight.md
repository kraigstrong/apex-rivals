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

## Launch runbook

Everything between here and a public TestFlight link, in order. The code is in pull requests; nothing is merged.

1. **Review and merge the app:** kraigstrong/apex-rivals#1 (the game), then the TestFlight PR stacked on it (icon,
   upload script, this runbook), and the tuning-panel PR on top if you want it (it changes nothing in Release builds).
2. **Review and merge the lap service:** kraigstrong/BrightBench#69. Vercel deploys `main` to brightbench.app.
3. **Set the service's secrets** on the marketing project in Vercel (Production, and Preview if you test previews):
   `APEX_APP_KEY` = `apex-laps-v1`, and `APEX_PLAYER_SALT` = a long random value (`openssl rand -base64 32`) that must
   never change once anyone has a time stored. Redeploy so the routes pick them up.
4. **Rate limit** `/api/apex/*` in the Vercel Firewall (60 requests a minute per IP is plenty for a beta).
5. **Check the routes answer:**

   ```bash
   # No one has a lap yet: no rival (204), and standings of no players.
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=ardennes&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   curl -s "https://brightbench.app/api/apex/standing?track=ardennes&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   # A made-up circuit is refused (400), and so is a request without the key (401).
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=nowhere&revision=1&physics=1&ms=29500" -H "X-App-Key: apex-laps-v1"
   curl -s -o /dev/null -w "%{http_code}\n" "https://brightbench.app/api/apex/rival?track=ardennes&revision=1&physics=1&ms=29500"
   ```

6. **Create the app record** in App Store Connect: Apps, then + New App. iOS, name **Apex Rivals** (the home-screen
   name stays Apex), bundle ID `com.kraigstrong.apex`, SKU `apex`, primary language English (U.S.).
7. **Game Center:** on the app's Services tab, add a Classic Leaderboard for each circuit: `apex.ardennes.r1.p1`,
   `apex.swirl.r1.p1`, `apex.snake.r1.p1`, `apex.mirage.r1.p1`, `apex.island.r1.p1` and `apex.harbor.r1.p1`. Score
   format: Elapsed Time, to the hundredth of a second. Sort: low to high. Reference and display name: the circuit's
   name (Ardennes, Swirl, Snake, Mirage, Island, Harbor).
8. **Upload a build:** from `main`, tag it (`git tag apex-v0.1-beta.1`), then run `scripts/testflight.sh --upload`.
   It archives with automatic signing and uploads with Xcode managing the build number, like the Organizer's
   Distribute App > App Store Connect > Upload. `scripts/testflight.sh` alone just archives, to check it signs.
9. **Internal test:** when the build finishes processing, add yourself to an internal group, install it from
   TestFlight, and run the smoke check below.
10. **Public beta:** create an external group (Friends), fill in Test Information (text below), add the build, and
    submit it for beta review. The first build of a version is reviewed by Apple, usually within a day. Once it's
    approved, turn on the group's public link and share it.
11. **Record it** in the build log at the end of this file.

## Test Information

Ready to paste into App Store Connect.

**Beta App Description**

> Apex Rivals is a one-touch racing game. Hold to steer up, let go to steer down, and set the fastest lap you can on
> six F1-style circuits. Straight is fast: every weave costs speed, so swing wide, clip the apex and run out wide.
> Race your best lap's ghost, chase a rival who's a little faster than you, and see where your lap falls among
> everyone else's.

**What to Test**

> Start with Apex School (top left) to learn the line: hit two apexes and it sends you racing. Sign in to Game Center and add
> your friends there: you'll race each other's ghosts, and the trophy shows your friends' times. Tap the flag to end a
> session and see where your best lap falls. We'd love to hear which circuits you like most, whether the controls feel
> fair, and anything that breaks.

Feedback email: your choice. A privacy policy isn't needed for TestFlight.

## Smoke check on the TestFlight build

On a physical iPhone, signed in to Game Center, with a fresh install:

- The Game Center welcome banner shows at launch, then the track list: the yellow Apex School button marked START
  HERE top left, and the six circuits scrolling sideways.
- Apex School: the yellow line, TURN IN / APEX / EXIT, the coach's three cues with a tick at turn-in and the apex,
  a verdict after each corner, your trail, and no ghosts. The second apex HIT brings "You're ready", whose button
  races Ardennes; afterwards the home button is quiet. SKIP (or the house button) goes straight back to the list.
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
