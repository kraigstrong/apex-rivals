#!/bin/bash
# App Store screenshots for Ghost Thread, from the simulator.
#
#   scripts/store-capture.sh [moment ...]          # default: every moment, in the listing's order
#   scripts/store-capture.sh --ipad [moment ...]   # the same moments on a 13-inch iPad
#   scripts/store-capture.sh --duo [moment ...]    # on an iPhone Duo, open (its inside screen)
#
# Builds a Debug build and, for each moment, installs it fresh and launches it with `-ApexStoreCapture <moment>` (see
# Apex/StoreCapture.swift). The app stages the moment on that fresh install (best laps and medals, a bot rival, the
# race driven by a seeded autopilot), plays up to it, holds still, and writes Documents/StoreCapture/<moment>.ready;
# this script then takes the simulator's screenshot with the display's mask left out, so no Dynamic Island. On an
# iPad the app saves the screen itself (<moment>.png beside it): a simulator held upright shows a landscape-only game
# shrunk into a band, and simctl can't turn it. The lap service and Game Center stay out of it. A rerun gives the same
# frames.
#
# Output goes to build/store-capture/ (ignored by git):
#   screenshots/NN-<moment>.png       2868x1320 landscape PNGs: the 6.9" size, which App Store Connect scales down for
#                                     smaller iPhones
#   screenshots-ipad-13/NN-<moment>.png  with --ipad: 2752x2064, the 13-inch iPad size
#   screenshots-duo/NN-<moment>.png   with --duo: 2853x2007, an iPhone Duo's inside screen, open
#
# STORE_CAPTURE_DEVICE picks the simulator (a name or UDID; default iPhone 17 Pro Max, with --ipad iPad Pro 13-inch
# (M5), or with --duo iPhone Duo). A Duo simulator has to be open first: its pose is a button in Xcode's Device Hub,
# not a simctl command. Each moment reinstalls the app on it, so use one whose Ghost Thread data you don't need. STORE_CAPTURE_OUT
# moves the output.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${STORE_CAPTURE_OUT:-$ROOT/build/store-capture}"
DERIVED="$ROOT/build/store-capture/DerivedData"
IPAD=0 DUO=0
if [ "${1:-}" = --ipad ]; then IPAD=1; shift; elif [ "${1:-}" = --duo ]; then DUO=1; shift; fi
if [ $IPAD = 1 ]; then
    DEVICE="${STORE_CAPTURE_DEVICE:-iPad Pro 13-inch (M5)}"
    SHOTS=screenshots-ipad-13 SIZE=2752x2064 SIZE_NAME='13-inch iPad'
elif [ $DUO = 1 ]; then
    DEVICE="${STORE_CAPTURE_DEVICE:-iPhone Duo}"
    SHOTS=screenshots-duo SIZE=2853x2007 SIZE_NAME='iPhone Duo (open)'
else
    DEVICE="${STORE_CAPTURE_DEVICE:-iPhone 17 Pro Max}"
    SHOTS=screenshots SIZE=2868x1320 SIZE_NAME='6.9" iPhone'
fi
BUNDLE=com.kraigstrong.apex
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Apex.app"
# The listing's order (StoreCapture.Moment): the ideal line first, the race with its ghosts, a medal, where a lap
# stands, then the track list and the unlock.
MOMENTS=(line ghosts medal standing circuits unlock)

usage() { sed -n '2,6p' "$0"; exit 1; }

build() {
    local destination="name=$DEVICE"
    [[ $DEVICE =~ ^[0-9A-Fa-f-]{36}$ ]] && destination="id=$DEVICE"
    xcodebuild build -quiet -project Apex.xcodeproj -scheme Apex -configuration Debug \
        -destination "platform=iOS Simulator,$destination" -derivedDataPath "$DERIVED"
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl bootstatus "$DEVICE" -b >/dev/null
}

pause() { perl -e "select(undef, undef, undef, $1)"; }

# What else a moment launches with: every circuit open, except for the unlock's own screen, which shows the price as
# the App Store would (only a Run from Xcode has the StoreKit configuration).
extra_args() {
    if [ "$1" = unlock ]; then
        echo -ApexUnlocked NO -ApexUnlockPrice '$1.99' -ApexUnlockScreen ardennes
    else
        echo -ApexUnlocked YES
    fi
}

capture() {
    local moment="$1" number="$2"
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl install "$DEVICE" "$APP"
    local signals
    signals="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Documents/StoreCapture"
    # shellcheck disable=SC2046
    xcrun simctl launch "$DEVICE" "$BUNDLE" -ApexStoreCapture "$moment" $(extra_args "$moment") >/dev/null
    local waited=0
    until [ -f "$signals/$moment.ready" ] || [ -f "$signals/$moment.failed" ]; do
        [ $waited -gt 1800 ] && { echo "$moment: not ready after three minutes" >&2; return 1; }
        pause 0.1
        waited=$((waited + 1))
    done
    if [ -f "$signals/$moment.failed" ]; then
        echo "$moment failed: $(cat "$signals/$moment.failed")" >&2
        xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
        return 1
    fi
    local name
    name="$(printf '%02d' "$number")-$moment.png"
    rm -f "$OUT/$SHOTS"/??-"$moment".png
    # Called as `capture ... || failed=1`, which turns off `set -e` in here: each step that writes the shot is checked.
    local saved=0
    if [ $IPAD = 1 ]; then
        # The app's own drawing of the screen: an upright iPad simulator shows the game shrunk into a band.
        cp "$signals/$moment.png" "$OUT/$SHOTS/$name" || saved=1
    elif [ $DUO = 1 ]; then
        # The inside screen, which App Store Connect's iPhone Duo slot takes.
        xcrun simctl io "$DEVICE" screenshot --type=png --display=internal --mask=ignored "$OUT/$SHOTS/$name" \
            >/dev/null 2>&1 || saved=1
    else
        xcrun simctl io "$DEVICE" screenshot --type=png --mask=ignored "$OUT/$SHOTS/$name" >/dev/null 2>&1 || saved=1
    fi
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    [ $saved = 0 ] && [ -s "$OUT/$SHOTS/$name" ] || { echo "$moment: couldn't save the screenshot" >&2; return 1; }
    local size
    size="$(sips -g pixelWidth -g pixelHeight "$OUT/$SHOTS/$name" | awk '/pixel/ { printf "%s%s", sep, $2; sep = "x" }')"
    if [ "$size" != "$SIZE" ]; then
        echo "$moment: ${size:-unreadable}, not the $SIZE_NAME size ($SIZE); is $DEVICE the right simulator?" >&2
        return 1
    fi
    echo "captured $SHOTS/$name ($size)"
}

moments=("$@")
[ ${#moments[@]} -eq 0 ] && moments=("${MOMENTS[@]}")
for moment in "${moments[@]}"; do
    [[ " ${MOMENTS[*]} " == *" $moment "* ]] || { echo "unknown moment: $moment (one of: ${MOMENTS[*]})" >&2; usage; }
done
mkdir -p "$OUT/$SHOTS"
build
failed=0
for moment in "${moments[@]}"; do
    for index in "${!MOMENTS[@]}"; do [ "${MOMENTS[$index]}" = "$moment" ] && number=$((index + 1)); done
    capture "$moment" "$number" || failed=1
done
exit $failed
