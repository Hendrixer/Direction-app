#!/bin/bash
# Publishes a release that scripts/release.sh made (docs/releasing.md) to the direction-releases bucket, served at
# updates.givedirection.ai: the DMG, the same DMG as Direction.dmg (the website's download link), then the feed.
# Uploading the feed is what offers the update to every signed copy, so it goes last.
#
#   scripts/publish-release.sh 0.3.0
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$direction_root"

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: scripts/publish-release.sh <version>, for example: scripts/publish-release.sh 0.3.0" >&2; exit 2; }

releases="${DIRECTION_RELEASES_DIR:-$direction_root/build/releases}"
bucket="direction-releases"
zone_id="ed9886c0b0af0835c10ab45f8fa9ee4f"   # givedirection.ai
host="https://updates.givedirection.ai"
dmg="$releases/Direction-$version.dmg"
feed="$releases/appcast.xml"

fail() { printf '\n%s\n' "$*" >&2; exit 1; }
[ -f "$dmg" ] || fail "No $dmg. Make it first with: scripts/release.sh $version"
[ -f "$feed" ] && grep -q "Direction-$version.dmg" "$feed" || fail "$feed doesn't offer $version. Make the release again with scripts/release.sh."
command -v cf >/dev/null || fail "The Cloudflare CLI isn't installed: npm install --global cf"
cf auth whoami >/dev/null 2>&1 || fail "Sign in to Cloudflare first: cf auth login"
xcrun stapler validate -q "$dmg" || fail "$dmg isn't notarized and stapled."

put() { cf r2 objects put "$2" --bucket-name "$bucket" --file "$1" --content-type "$3" >/dev/null; }
echo "Uploading Direction-$version.dmg…"
put "$dmg" "Direction-$version.dmg" "application/x-apple-diskimage"
put "$dmg" "Direction.dmg" "application/x-apple-diskimage"
echo "Uploading the feed…"
put "$feed" "appcast.xml" "application/xml"
# Cloudflare caches what the bucket serves: the names that change with every release go from the cache now.
cf cache purge --zone "$zone_id" --body "{\"files\":[\"$host/appcast.xml\",\"$host/Direction.dmg\"]}" >/dev/null

curl -fsS -o /dev/null "$host/Direction-$version.dmg" || fail "$host/Direction-$version.dmg doesn't download yet."
curl -fsS "$host/appcast.xml" | grep -q "Direction-$version.dmg" || fail "$host/appcast.xml doesn't offer $version yet (the cache may still hold the old feed)."
printf '\nPublished Direction %s:\n  %s/Direction.dmg\n  %s/appcast.xml\n' "$version" "$host" "$host"
