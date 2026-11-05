#!/bin/bash
# Makes a release to hand out (docs/releasing.md): Direction signed with your Developer ID, notarized and
# stapled, in a DMG that's notarized too, and the Sparkle feed (appcast.xml) that offers it as an update.
# Nothing is uploaded; scripts/publish-release.sh does that once you've tried the DMG.
#
#   scripts/release.sh 0.3.0                 the release notes are build/releases/Direction-0.3.0.md if it exists
#   scripts/release.sh 0.3.0 notes.md        or this file
#
# DIRECTION_SIGNING_IDENTITY  the certificate's name, when the keychain has more than one Developer ID Application
# DIRECTION_NOTARY_PROFILE    the notarytool keychain profile (default direction-notary)
# DIRECTION_RELEASES_DIR      where releases and the feed are kept (default build/releases)
# DIRECTION_SIGNING_IDENTITY=- signs ad hoc and stops before notarizing: a dry run of the packaging only.
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$direction_root"

version="${1:-}"
notes="${2:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/release.sh <version> [notes.md], for example: scripts/release.sh 0.3.0" >&2
  exit 2
fi

# Where updates come from, and the public half of the key they're checked with. The private half is in your
# login keychain under the Sparkle account below (generate_keys --account givedirection.ai), backed up in 1Password.
feed_url="https://updates.givedirection.ai/appcast.xml"
download_prefix="https://updates.givedirection.ai/"
website="https://givedirection.ai"
sparkle_public_key="mmD876s5PKSfRQlP+g3a2MezoP/gEuY9PTgx/JtOp4M="
sparkle_account="givedirection.ai"
notary_profile="${DIRECTION_NOTARY_PROFILE:-direction-notary}"

sparkle_bin="$direction_root/.build/artifacts/sparkle/Sparkle/bin"
dist="$direction_root/build/dist"
releases="${DIRECTION_RELEASES_DIR:-$direction_root/build/releases}"
app="$dist/Direction.app"
dmg_name="Direction-$version.dmg"

fail() { printf '\n%s\n' "$*" >&2; exit 1; }

# MARK: Before anything is built

identity="${DIRECTION_SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
  found="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p')"
  [ -n "$found" ] || fail "No Developer ID Application certificate in your keychain. Make one in Xcode › Settings › Accounts › your team › Manage Certificates… › + › Developer ID Application (docs/releasing.md)."
  [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = "1" ] || fail "More than one Developer ID Application certificate. Choose one: DIRECTION_SIGNING_IDENTITY=\"Developer ID Application: …\" scripts/release.sh $version"
  identity="$found"
fi
dry_run=false
[ "$identity" = "-" ] && dry_run=true

if ! $dry_run; then
  xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
    || fail "notarytool can't use the keychain profile \"$notary_profile\". Save your App Store Connect API key once with: xcrun notarytool store-credentials $notary_profile --key <AuthKey_….p8> --key-id <key ID> --issuer <issuer ID> (docs/releasing.md)."
fi
[ -x "$sparkle_bin/generate_appcast" ] || fail "Sparkle's tools aren't in .build/artifacts. Run: swift package resolve"
if [ -z "$notes" ] && [ -f "$releases/Direction-$version.md" ]; then notes="$releases/Direction-$version.md"; fi
[ -z "$notes" ] || [ -f "$notes" ] || fail "No release notes at $notes."
if [ -f "$releases/$dmg_name" ]; then fail "$releases/$dmg_name is already made. A new release needs a new version."; fi

# Sparkle compares build numbers, so each release's must be higher than the last: the count of commits on HEAD.
build_number="$(git rev-list --count HEAD)"
dirty="$(git status --porcelain -- Sources Resources plugins Package.swift Package.resolved scripts)"
if [ -n "$dirty" ]; then
  printf 'Note: these files differ from the last commit, and the release is built with them as they are:\n%s\n\n' "$dirty" >&2
fi

# MARK: Build

echo "Building Direction $version ($build_number)…"
rm -rf "$dist"; mkdir -p "$dist"
DIRECTION_APP_DIR="$app" "$direction_root/scripts/build-app.sh" release >/dev/null
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $feed_url" -c "Add :SUPublicEDKey string $sparkle_public_key" -c "Add :SUEnableAutomaticChecks bool true" "$plist"

# MARK: Sign, from the inside out, with the hardened runtime notarization requires

echo "Signing with ${identity}…"
timestamp=(--timestamp); $dry_run && timestamp=(--timestamp=none)
sign() { codesign --force "${timestamp[@]}" --sign "$identity" "$@"; }
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign --options runtime "$sparkle/XPCServices/Installer.xpc"
sign --options runtime --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign --options runtime "$sparkle/Autoupdate"
sign --options runtime "$sparkle/Updater.app"
sign --options runtime "$app/Contents/Frameworks/Sparkle.framework"
# SwiftPM's resource bundles hold no code, but they're bundles, so each gets its own seal.
for bundle in "$app"/Contents/Resources/*.bundle; do sign "$bundle"; done
sign --options runtime --identifier dev.direction.editor.helper "$app/Contents/Helpers/direction"
sign --options runtime "$app"
codesign --verify --deep --strict "$app" || fail "The signed app doesn't verify."

if $dry_run; then
  echo "Dry run: signed ad hoc and not notarized. $app"
  exit 0
fi

# MARK: Notarize the app, then the DMG it goes in

notarize() {
  local file="$1" result="$dist/notary-$(basename "$1").json"
  echo "Notarizing $(basename "$file") (this takes a few minutes)…"
  xcrun notarytool submit "$file" --keychain-profile "$notary_profile" --wait --output-format json >"$result" || true
  local status id
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo "no answer")"
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo "")"
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$notary_profile" "$dist/notary-log-$(basename "$file").json" >/dev/null 2>&1 || true
    fail "Apple didn't accept $(basename "$file"): $status. Its log is in $dist."
  fi
}

ditto -c -k --keepParent "$app" "$dist/Direction.zip"
notarize "$dist/Direction.zip"
xcrun stapler staple -q "$app"
rm "$dist/Direction.zip"

echo "Making $dmg_name…"
stage="$dist/dmg"; mkdir -p "$stage"
ditto "$app" "$stage/Direction.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Direction" -srcfolder "$stage" -ov -format UDZO "$dist/$dmg_name"
rm -rf "$stage"
sign "$dist/$dmg_name"
notarize "$dist/$dmg_name"
xcrun stapler staple -q "$dist/$dmg_name"
spctl --assess --type open --context context:primary-signature "$dist/$dmg_name" || fail "Gatekeeper doesn't accept the DMG."
spctl --assess --type execute "$app" || fail "Gatekeeper doesn't accept the app."

# MARK: The feed

mkdir -p "$releases"
cp "$dist/$dmg_name" "$releases/"
if [ -n "$notes" ] && [ "$notes" != "$releases/Direction-$version.md" ]; then cp "$notes" "$releases/Direction-$version.md"; fi
"$sparkle_bin/generate_appcast" --account "$sparkle_account" --download-url-prefix "$download_prefix" --link "$website" \
  --embed-release-notes --maximum-deltas 0 "$releases"

printf '\nDirection %s (%s) is ready:\n  %s\n  %s\nTry the DMG, then publish it with: scripts/publish-release.sh %s\n' \
  "$version" "$build_number" "$releases/$dmg_name" "$releases/appcast.xml" "$version"
