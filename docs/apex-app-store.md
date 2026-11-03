# Ghost Thread on the App Store

Everything between the TestFlight beta (`docs/apex-testflight.md`) and Ghost Thread 1.0 on the App Store. Tick each off
in the pull request that does it.

## In the app

- [x] **Free to try, one unlock.** Ardennes and Apex School are free; a one-time $1.99 purchase opens every other
      circuit, and every circuit added later (`CircuitUnlock.swift`, `UnlockView.swift`).
- [ ] **Version 1.0.** `MARKETING_VERSION` is 0.1.0.
- [ ] **Share link to the App Store.** `ApexLinks.join` is the public TestFlight link; the share text should send
      people to the App Store page once it's live.
- [ ] **Ask for a rating** at a good moment, such as a new medal (`SKStoreReviewController`), the way Bigger Fish does.
      Optional.
- [ ] **Dark and tinted app icons** for iOS 18's home screen styles. Optional.

## App Store Connect

- [ ] **The in-app purchase** (see below), submitted with 1.0: an app's first in-app purchase can only be reviewed with
      a version.
- [ ] **Screenshots**: 6.9" iPhone and 13" iPad (the app runs on iPad, so both are required).
- [ ] **App preview video** for each of those sizes, up to 30 seconds. Optional, but the game sells on motion.
- [ ] **Metadata**: subtitle, promotional text, description, keywords, copyright, support URL, marketing URL, privacy
      policy URL. Category is Racing.
- [ ] **App Privacy** answers, matching `Apex/PrivacyInfo.xcprivacy`: gameplay content (ghosts) and a user ID (the
      Game Center player ID, hashed), linked to the player, not used for tracking; anonymous lap counts.
- [ ] **Age rating** questionnaire.
- [ ] **Game Center**: add each circuit's leaderboard and medal achievements to the 1.0 version page, or they don't go
      live with it.
- [ ] **App Review notes**: no account needed; where the unlock and Restore are; Game Center and the lap service.
- [ ] **Price and availability**: free, every territory; release by hand (or phased) once approved.

Bigger Fish keeps its metadata, purchase text and screenshots in the repo and pushes them with the App Store Connect
API (`appstore/push.py` there); porting it would make all of the above repeatable.

## On the web (BrightBench)

- [ ] **Privacy policy** page: what the lap service stores (anonymous lap counts; a salted hash of the Game Center
      player ID with the player's alias, best time and ghost), and what it doesn't.
- [ ] **Support** page.
- [ ] **Landing page** for the marketing URL. Optional.

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

Create it before uploading a build that sells it: until App Store Connect has the product, TestFlight builds can't
load it, so the unlock button has no price and the purchase fails, and testers are locked out of every circuit but
Ardennes. TestFlight purchases are free (the sandbox), so testers can unlock with a tap once it exists.

The purchase flow can't run under `xcodebuild test` (StoreKit test sessions need Xcode), so check it by hand: Run from
Xcode, which uses `Apex.storekit`, tap a locked circuit, buy, and check every circuit opens; then Debug ▸ StoreKit ▸
Manage Transactions, refund it, and check they lock again. Restore is on the same screen.
