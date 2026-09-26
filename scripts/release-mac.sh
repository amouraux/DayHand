#!/bin/sh
# Builds the Mac app as a signed, notarised .dmg for direct download.
#
#   scripts/release-mac.sh
#
# This is the download-it-yourself channel, not the App Store one. It needs a
# **Developer ID Application** certificate — a different certificate from the
# Apple Distribution one the App Store upload uses. Without it, and without
# notarisation, Gatekeeper refuses the download outright: "DayHand is damaged
# and can't be opened."
#
# Two one-time steps before the first run:
#
#   1. Xcode → Settings → Accounts → Manage Certificates → + →
#      Developer ID Application.
#
#   2. Store an app-specific password for notarisation, once, in the keychain
#      (make one at appleid.apple.com → Sign-In and Security → App-Specific
#      Passwords):
#
#        xcrun notarytool store-credentials "DayHand" \
#          --apple-id you@example.com --team-id ZL9BJ32RWX --password xxxx-xxxx-xxxx-xxxx
#
# Nothing here stores or prints a password: notarytool reads the profile from
# your keychain by name.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

team=${DEVELOPMENT_TEAM:-ZL9BJ32RWX}
profile=${NOTARY_PROFILE:-DayHand}
out="$root/build-mac"
archive="$out/DayHand.xcarchive"
export_dir="$out/export"
app="$export_dir/DayHand.app"
staging="$out/dmg"

version=$(xcodebuild -project DayHand.xcodeproj -scheme DayHand -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION =/ { print $2; exit }')
[ -n "$version" ] || version=1.0
dmg="$out/DayHand-$version.dmg"

# The certificate is the thing people trip over, so say so before spending five
# minutes on an archive that cannot be exported.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "error: no Developer ID Application certificate in the keychain." >&2
  echo "       Xcode → Settings → Accounts → Manage Certificates → + →" >&2
  echo "       Developer ID Application, then run this again." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "error: no notarytool keychain profile called \"$profile\"." >&2
  echo "       See the comment at the top of this script." >&2
  exit 1
fi

echo "==> Archiving (Mac Catalyst, Release)"
rm -rf "$out"
mkdir -p "$out"
xcodebuild -project DayHand.xcodeproj -scheme DayHand \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Release \
  -archivePath "$archive" \
  archive

echo "==> Exporting with Developer ID"
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$out/ExportOptions.plist" \
  -exportPath "$export_dir"

echo "==> Building $dmg"
rm -rf "$staging"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"   # so the window says: drag it there
hdiutil create -volname DayHand -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null

echo "==> Notarising (this waits for Apple, usually a minute or two)"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait

echo "==> Stapling"
xcrun stapler staple "$dmg"

echo "==> Checking it the way a downloader's Mac will"
spctl --assess --type open --context context:primary-signature -v "$dmg"

echo
echo "Done: $dmg"
echo "Attach it to a GitHub release — the site's Download button points at"
echo "https://github.com/amouraux/DayHand/releases/latest"
