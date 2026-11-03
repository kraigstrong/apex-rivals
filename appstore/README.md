# App Store listing

Ghost Thread's App Store Connect listing lives here as plain text files, reviewed in pull requests like code, and
`push.py` sends them to App Store Connect through Apple's API. It's Bigger Fish's `appstore/push.py`, ported with
Ghost Thread's entry in `APPS`; see Bigger Fish's `appstore/README.md` for the parts not used here yet.

```
appstore/
├── push.py
└── ghost-thread/
    ├── app/<locale>/<field>.txt            # name, subtitle, promotional_text, description, keywords,
    │                                       # release_notes, support_url, marketing_url, privacy_policy_url
    ├── iap/<purchase>/<locale>/{name,description}.txt
    └── review_notes.txt                    # App Review's notes, for the version (not a locale)
```

```bash
python3 appstore/push.py validate                                  # Apple's limits and a few house rules; no network
python3 appstore/push.py check                                     # the credentials work; lists each app's Apple ID
python3 appstore/push.py pull --app ghost-thread                   # App Store Connect's text into the files
python3 appstore/push.py push --app ghost-thread --dry-run         # what would change, field by field
python3 appstore/push.py media --app ghost-thread --screenshots DIR DIR --dry-run
python3 appstore/push.py purchase --app ghost-thread --screenshot FILE --dry-run   # set up the in-app purchase
```

`purchase` takes an in-app purchase to Ready to Submit. If App Store Connect doesn't have it yet, it creates it with
the settings in `push.py`'s `PURCHASE_SETUP` (type, reference name, US price, Family Sharing); **the product ID and
Family Sharing can't be undone once created**, so dry-run first. Then it fills in only what's missing: the display name
and description from `iap/<purchase>/<locale>/`, the price, the availability, and the review screenshot
(`--screenshot`, a PNG without alpha or a JPEG of the purchase screen; a different one replaces it). It never changes
a price or availability that's set. `com.kraigstrong.apex.allcircuits` was created this way on 2026-11-02, with the
unlock's screen from the simulator as its review screenshot:

```bash
xcrun simctl launch <udid> com.kraigstrong.apex -ApexUnlocked NO -ApexUnlockPrice '$1.99' -ApexUnlockScreen ardennes
xcrun simctl io <udid> screenshot --type=jpeg unlock-review.jpg
```

- **A push writes to the editable version** (Prepare for Submission and the like). Nothing goes public until that
  version is submitted and released. Always dry-run first.
- **Edited something in App Store Connect's website?** Run `pull` (or copy it into the file), or the next push
  overwrites it.

## Credentials

Nothing secret is in a file. The App Store Connect API key is in the 1Password Environment **App Store Connect**, which
1Password mounts at `~/.appstoreconnect/.env`: a pipe it feeds when the script reads it, never plaintext on disk. It
holds `ASCC_KEY_ID`, `ASCC_ISSUER_ID` and `ASCC_PRIVATE_KEY` (the `.p8` file's contents, concealed). Ghost Thread's
Apple ID (6822499299) isn't secret, so it's in `APPS`; `ASCC_APP_ID_GHOST_THREAD` overrides it.

Talking to the API needs the `cryptography` package (`python3 -m pip install --user cryptography`); `validate` needs
nothing.
