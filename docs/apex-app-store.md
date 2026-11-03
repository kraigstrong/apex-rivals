# Ghost Thread on the App Store

Everything between the TestFlight beta (`docs/apex-testflight.md`) and Ghost Thread 1.0 on the App Store. Tick each off
in the pull request that does it.

## In the app

- [x] **Free to try, one unlock.** Ardennes and Apex School are free; a one-time $1.99 purchase opens every other
      circuit, and every circuit added later (`CircuitUnlock.swift`, `UnlockView.swift`).
- [x] **Version 1.0.** `MARKETING_VERSION` is 1.0, as App Store Connect's version (Prepare for Submission) is.
- [x] **Share link.** Shared laps link to `https://brightbench.app/ghost-thread` (`ApexLinks.join`), which offers the
      beta now and the App Store once BrightBench's `appStoreUrl` is set: no app update at launch.
- [ ] **At launch:** set `appStoreUrl` in BrightBench's `apps/marketing/src/lib/ghost-thread.ts` to the App Store link.
- [x] **Ask for a rating** after the player's first gold medal, and again after their first platinum, on any circuit
      (an `ApexReview` modeled on Bigger Fish's `ArcadeReview`). The lap that wins one marks a request due; it's made on
      the next return to the track list, a second after it's up with nothing over it, never over a race, its summary
      or the unlock's screen. App Store builds only (TestFlight can't show the sheet), at most twice, 90 days apart.
- [ ] **Dark and tinted app icons** for iOS 18's home screen styles. Optional.

## App Store Connect

- [ ] **The in-app purchase** (see below): created 2026-11-02. It goes to review with 1.0: an app's first in-app
      purchase can only be reviewed with a version (add it on the version page before submitting).
- [x] **Screenshots**: 6.9" iPhone, 13" iPad and iPhone Duo, six each, on 1.0 since 2026-11-02. `scripts/store-capture.sh`
      (and `--ipad`) captures the six moments and `scripts/store-frames.py` captions them (README, App Store
      screenshots); upload with `appstore/push.py media`. The iPhone set is ready; recapture the iPad's now its race
      and track list scale up. App Store Connect has an iPhone Duo slot too (2853×2007, the open inner screen):
      `scripts/store-capture.sh --duo`, with the simulator opened first in Xcode's Device Hub.
- [x] **App preview video** for the iPhone (the iPhone Duo's slot takes it too) and the 13-inch iPad, about 29 seconds
      with the game's sound, ending on the challenge (`scripts/store-preview.py`; README, App Store screenshots).
- [x] **Header and search results images** (iOS 27's creative assets, 5244×2950): the logo over the ideal line, and
      your ghost into Swirl's hairpin (`scripts/store-creative.py`). Both, and the previews (poster at 7.7 s, your
      ghost and the rival into Swirl's hairpin), on 1.0 since 2026-11-02.
- [ ] **Metadata**: subtitle, promotional text, description, keywords, support URL, marketing URL, privacy policy
      URL, drafted in `appstore/ghost-thread/app/en-US/`; push with `appstore/push.py push --app ghost-thread` (dry-run
      first). The description's headings are the screenshots' captions, in their order. Copyright isn't one of
      `push.py`'s fields: set it by hand on the version page ("2026 Kraig Strong"). Category is Racing.
- [ ] **App Privacy** answers (below), matching `Apex/PrivacyInfo.xcprivacy`.
- [ ] **Age rating** questionnaire (below).
- [ ] **Game Center**: add each circuit's leaderboard and medal achievements to the 1.0 version page, or they don't go
      live with it.
- [ ] **App Review notes**: drafted in `appstore/ghost-thread/review_notes.txt` (no account needed; where the unlock
      and Restore are; Game Center and the lap service); `push` sends them with the metadata.
- [ ] **Price and availability**: free, every territory; release by hand (or phased) once approved.

The metadata, purchase text and screenshots live in `appstore/` and go up with the App Store Connect API
(`appstore/push.py`, ported from Bigger Fish; see `appstore/README.md`).

### App Privacy answers

App Store Connect ▸ App Privacy. Ghost Thread collects data (the lap service; `ApexOnline.swift`), none of it used
for tracking, in three types:

| Data type | What it is | Linked to the player | Purposes |
| --- | --- | --- | --- |
| Gameplay Content | a best lap's ghost (the car's path) and its times | Yes | App Functionality |
| User ID | the Game Center player ID (stored only as a salted hash) and the player's Game Center nickname | Yes | App Functionality |
| Product Interaction | every finished lap, counted anonymously: circuit, time, splits, wall hits, app version and build | No | Analytics, App Functionality |

Nothing else: no contact info, location, device ID, purchase history (StoreKit is Apple's), or diagnostics. IP
addresses only pass through Vercel, which rate-limits by them; the lap service doesn't store them. Game Center itself
is Apple's, under Apple's policy.

### Age rating answers

Everything is None or No: no violence (cars bounce off walls; no one is hurt), no mature themes, no medical or
wellness content, no gambling, contests (leaderboards have no prizes), loot boxes, advertising, messaging or web
access, and no parental controls or age assurance. One judgment call:

- **User-generated content.** The rival's panel shows another player's Game Center nickname, and their ghost (a path,
  no text or images) races beside you. The nicknames are Game Center's own, which every Game Center leaderboard shows,
  so the answer here is No; answer Yes if App Review sees it otherwise.

## On the web (BrightBench)

Ghost Thread has no domain of its own, so its pages are on brightbench.app, in BrightBench's `apps/marketing`
(live since 2026-11-02). Its art
comes from the game (`SiteArtTests`, `Art/site`).

- [x] **Privacy policy**: `https://brightbench.app/ghost-thread/privacy`. What the lap service stores (anonymous lap
      counts; a salted hash of the Game Center player ID with the player's alias, best time and ghost), and what it
      doesn't. Keep it in step with `ApexOnline.swift` and `PrivacyInfo.xcprivacy`.
- [x] **Support**: `https://brightbench.app/ghost-thread/support`.
- [x] **Landing page** for the marketing URL: `https://brightbench.app/ghost-thread`, each circuit lapped by its
      ideal line as on the unlock screen. It invites players to the TestFlight beta until the App Store listing is live
      (`appStoreUrl` in BrightBench's `src/lib/ghost-thread.ts`).

## Marketing

- [ ] **Trailer.**
- [x] **Rate limit** on the lap service, before the link goes beyond friends (live since 2026-11-01).
- [ ] **TestFlight times at launch**: keep the beta's laps on the boards, or start them fresh. Lap batches are tagged
      `testflight` or `appstore` (`ApexOnline.channel`), so the histograms could drop beta laps.

## The unlock

A non-consumable in-app purchase:

| Field | Value |
| --- | --- |
| Product ID | `com.kraigstrong.apex.allcircuits` (permanent once created) |
| Reference name | Unlock every circuit |
| Price | $1.99 (US) |
| Family Sharing | On |
| Display name | All Circuits |
| Description | Every circuit, and every one added later. |
| Review screenshot | The unlock screen |

Created on 2026-11-02 with `python3 appstore/push.py purchase --app ghost-thread --screenshot <jpeg>` (Apple ID
6829970261): its name and description are in `appstore/ghost-thread/iap/allcircuits/`, and it's sold in every
territory. A build that sells it needs it in App Store Connect: without it, TestFlight builds can't load it, so the
unlock button has no price and testers are locked out of every circuit but Ardennes. TestFlight purchases are free
(the sandbox), so testers can unlock with a tap.

The purchase flow can't run under `xcodebuild test` (StoreKit test sessions need Xcode), so check it by hand: Run from
Xcode, which uses `Apex.storekit`, tap a locked circuit, buy, and check every circuit opens; then Debug ▸ StoreKit ▸
Manage Transactions, refund it, and check they lock again. Restore is on the same screen.
