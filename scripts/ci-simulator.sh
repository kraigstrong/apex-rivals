#!/bin/bash
# Picks the iPhone simulator CI tests on, boots it, and prints its id.
#
#   scripts/ci-simulator.sh    # prints a simulator udid, for -destination "platform=iOS Simulator,id=<udid>"
#
# A runner's simulator service sometimes hasn't listed its devices yet when xcodebuild asks for one by name, and the
# test step fails with "Unable to find a device matching the provided destination specifier". So this asks the
# service itself, waits and asks again if it lists no iPhone, and creates one on the newest iOS runtime if it never
# does. It prefers an iPhone 17 Pro on the newest iOS. Everything but the id goes to stderr.
set -euo pipefail

# The newest iOS runtime's iPhone, preferring an iPhone 17 Pro: "<udid> <name> (iOS <version>)", or nothing.
pick() {
  xcrun simctl list devices available -j | python3 -I -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".SimRuntime.iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".SimRuntime.iOS-")[1].split("-"))
    for device in devices:
        if device.get("isAvailable") and ".SimDeviceType.iPhone" in device.get("deviceTypeIdentifier", ""):
            key = (version, device["name"] == "iPhone 17 Pro", device["name"])
            if best is None or key > best[0]:
                best = (key, device["udid"])
if best:
    print(best[1], best[0][2], "(iOS " + ".".join(map(str, best[0][0])) + ")")
'
}

found=""
for attempt in 1 2 3 4 5 6; do
  found=$(pick)
  [[ -n "$found" ]] && break
  echo "No iPhone simulator listed yet (try $attempt of 6); waiting for the simulator service." >&2
  sleep 10
done

if [[ -z "$found" ]]; then
  echo "Still none listed; creating one. Runtimes:" >&2
  xcrun simctl list runtimes >&2
  # The newest available iOS runtime, and an iPhone it runs: a 17 Pro if it can, else whichever comes first.
  read -r runtime devicetype < <(xcrun simctl list runtimes available -j | python3 -I -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if runtimes:
    newest = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
    phones = {t["name"]: t["identifier"] for t in newest.get("supportedDeviceTypes", [])
              if t.get("productFamily") == "iPhone"}
    if phones:
        print(newest["identifier"], phones.get("iPhone 17 Pro") or next(iter(phones.values())))
') || true
  if [[ -z "${runtime:-}" ]]; then
    echo "No iOS simulator runtime is installed for this Xcode; nothing to test on." >&2
    exit 1
  fi
  udid=$(xcrun simctl create "CI iPhone" "$devicetype" "$runtime")
  found="$udid CI iPhone ($runtime)"
fi

udid=${found%% *}
echo "Testing on ${found#* } ($udid)." >&2
# Booted ahead, so the test step doesn't spend its time (or time out) booting it.
xcrun simctl bootstatus "$udid" -b >&2
echo "$udid"
