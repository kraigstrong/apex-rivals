#!/bin/zsh
# Archives Apex for the App Store, and with --upload sends it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh            # archive only, to check it builds and signs
#   scripts/testflight.sh --upload   # archive and upload (needs the App Store Connect app record)
#
# Signing is automatic with team MKACSCQ588 and uses the Apple account signed in to Xcode. The upload is the same as
# the Organizer's Distribute App > App Store Connect > Upload, with Xcode managing the build number.
set -euo pipefail
cd "${0:A:h}/.."

archive=build/testflight/Apex.xcarchive
rm -rf "$archive"
xcodebuild archive -project Apex.xcodeproj -scheme Apex -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates -quiet
version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$archive/Info.plist")
echo "Archived Apex $version at $archive"

if [[ "${1:-}" == "--upload" ]]; then
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath build/testflight/export -allowProvisioningUpdates
  echo "Uploaded. It shows in App Store Connect > TestFlight once processing finishes (usually 10-30 minutes)."
fi
