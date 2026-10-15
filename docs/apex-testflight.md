# Apex Rivals on TestFlight

How to get an Apex Rivals beta to friends, so you can race each other's times and ghosts.

## What the build has

- Bundle ID `com.kraigstrong.apex`, team `MKACSCQ588`, automatic signing. Version 0.1.0. iPhone and iPad (full
  screen), landscape.
- App icon (`Art/make-icon.py` draws it; no alpha) and the system launch screen.
- `ITSAppUsesNonExemptEncryption = NO`: the only encryption is the system's HTTPS.
- Category: Racing games.
- Game Center (`Apex/Apex.entitlements`): sign-in at launch, each personal best submitted to the circuit's
  leaderboard, each medal reported as an achievement, the trophy button opening the friends board, and Race a friend,
  which asks to see the friends list (`NSGKFriendListUsageDescription` in `Apex-Info.plist`).
- The lap service is on (`ApexOnline.isEnabled`): every lap counted anonymously at `brightbench.app/api/apex/laps`,
  each personal best's ghost shared under the player's Game Center alias, rivals from other players' ghosts, and real
  standings at the end of a session. Lap batches are tagged `testflight` for beta installs. Race a friend needs
  BrightBench's friend routes (`POST /api/apex/friends`, `GET /api/apex/ghosts`, kraigstrong/BrightBench#70) deployed
  first; without them the picker says friends' times aren't available.
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
4. **Rate limit** `/api/apex/*` in the Vercel Firewall (60 requests a minute per IP is plenty for a beta). Skipped for
   the first beta by choice. The project had no firewall config yet, and the API can't create one, so it has to be
   started from the dashboard's Firewall tab. Without it, the app key is public, so anyone can post unlimited
   anonymous laps and skew the lap-time standings ("where your lap falls"). Ghosts and bests are safe either way:
   they need a signed Game Center identity. Add the limit before the public link goes beyond friends.
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

   Then an achievement for each medal on each circuit, 24 in all, named for the circuit and medal:
   `apex.ardennes.bronze`, `apex.ardennes.silver`, `apex.ardennes.gold`, `apex.ardennes.platinum`, and the same for
   `swirl`, `snake`, `mirage`, `island` and `harbor`. Reference name and title: "Ardennes Gold". Points: bronze 5,
   silver 10, gold 20, platinum 40 (75 a circuit; Game Center allows 1,000 in all). Not hidden, not repeatable.
   Image: `Art/achievements/<id>.png`.
   Descriptions before and after earning, on Ardennes (the other circuits follow the same pattern):

   - Bronze: "Win bronze at Ardennes: beat a sloppy weaver's lap." / "Bronze at Ardennes: you beat a sloppy weaver's
     lap."
   - Silver: "Win silver at Ardennes: beat a lap down the middle of the road." / "Silver at Ardennes: you beat a lap
     down the middle of the road."
   - Gold: "Win gold at Ardennes: beat the ideal line at human reaction speed." / "Gold at Ardennes: you beat the
     ideal line at human reaction speed."
   - Platinum: "Win platinum at Ardennes: beat the ideal line at a 50 ms reaction." / "Platinum at Ardennes: you beat
     the ideal line at a 50 ms reaction."
8. **Upload a build:** from `main`, tag it (`git tag apex-v0.1-beta.1`), then run `scripts/testflight.sh --upload`.
   It archives with automatic signing and uploads with Xcode managing the build number, like the Organizer's
   Distribute App > App Store Connect > Upload. `scripts/testflight.sh` alone just archives, to check it signs.
9. **Internal test:** when the build finishes processing, add yourself to an internal group, install it from
   TestFlight, and run the smoke check below.
10. **Public beta:** create an external group (Friends), fill in Test Information (text below), add the build, and
    submit it for beta review. The first build of a version is reviewed by Apple, usually within a day. Once it's
    approved, turn on the group's public link and share it.
11. **Record it** in the build log at the end of this file.

The app's shared laps link to the public TestFlight link (`ApexLinks.join` in `Apex/ShareCard.swift`). If the
Friends group's link changes, or once the game is on the App Store, change it there.

Only one build of a version can wait for beta review at a time. To replace one that's still waiting (say, with a fix),
expire it first: that takes it out of the queue (TestFlight has no other way to withdraw it), and the new build can be
submitted. Later builds of an approved version usually clear review quickly.

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
  a verdict after each corner, your trail, and no ghosts. The second real apex (turned in to from wide) brings
  "You're ready", whose button goes to the track list; afterwards the home button is quiet. Riding the inside wall
  shows "TURN IN FROM WIDE TO COUNT" and doesn't count. SKIP (or the house button) goes straight back to the list.
- Each circuit: a lap is timed, splits show at sectors 1 and 2, and the live delta shows after the first lap. A new
  best lap shows the purple banner; the blue ghost replays it on the next lap.
- Medals: each track card shows the next medal to win (an outline and its time; bronze to start). A lap that wins
  one shows it under the lap banner (SILVER MEDAL), the medal sits beside BEST in the timing panel, and the summary
  says NEW SILVER MEDAL with the next one to chase. Game Center (the Games app, or the leaderboard's overlay) shows
  the circuit's Bronze and Silver achievements earned, with no Game Center banner during the race. A device with best
  laps from before achievements existed reports their medals at the next launch.
- The gold rival is a Pace bot at first (no one else has a time). Beating it brings a new one.
- The flag is dimmed until you finish a lap. Then it ends a session: the summary shows your best lap and, with no one
  else on the board yet, "You're the first!" The trophy opens the circuit's leaderboard with your time on it.
- SHARE on the summary opens the share sheet: a picture of the circuit with your line in your car's color, the time,
  medal and standing, and text ending with the public TestFlight link. Send it to yourself in Messages: the link
  opens TestFlight.
- Open ⚙︎ mid-lap: the lap clock, the car and the engine stop until the menu closes, then carry on from the same
  time. The trophy's leaderboard holds the race the same way until it's closed, as does pulling down Control Center.
- Best laps survive force-quitting and reopening. Background the app mid-lap: the session ends and its summary is
  waiting on return.

With a second phone on a different Game Center account (a friend's, or a test account):

- Set a lap on the same circuit on both, the second phone a little faster (0.2–3 s). Relaunch the slower phone and
  open that circuit: its rival is the faster player's ghost, named with their Game Center alias.
- The flag on either phone shows a real standing: "#1 of 2" or "#2 of 2", and the histogram.
- Both times show on the circuit's leaderboard (friends board if you're Game Center friends, global board either
  way).
- If the two accounts are Game Center friends: ⚙︎ → Race a friend on the slower phone asks to share the friends list,
  then lists the other player with their time and how far ahead they are. Pick them: the gold rival is their ghost,
  named as Game Center names them, and it stays after you beat it, and after relaunching. Pick Auto to go back.
- In Airplane Mode, laps still save on the device; back online, the next lap sends the queued ones.

## Build log

| Version | Build | Commit | Notes |
| --- | --- | --- | --- |
| 0.1.0 | 1 | 388a24a (`apex-v0.1-beta.1`) | First beta: six circuits, Apex School, Game Center, lap service. Submitted for beta review 2026-10-13, then expired before review in favor of build 2. |
| 0.1.0 | 2 | 812a4fc (`apex-v0.1-beta.2`) | Build 1 plus the camera kept square to the road through corners (#7). Submitted for beta review 2026-10-13; the Friends group's public link: https://testflight.apple.com/join/dt7sHRvR |
