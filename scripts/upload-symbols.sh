#!/bin/bash
# Sends a release's debug symbols to Sentry (docs/releasing.md), so a crash or hang from that release names the
# functions and lines it happened in instead of bare addresses. scripts/release.sh keeps each release's symbols in
# build/symbols/<version>: one .dSYM for the app and one for its helper, matched to the signed copy by their IDs.
#
#   scripts/upload-symbols.sh 0.3.10
#
# The Sentry token is read from your login keychain (service direction-sentry), or from SENTRY_AUTH_TOKEN.
# Save it once with:  security add-generic-password -U -s direction-sentry -a sentry -w
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$direction_root"

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: scripts/upload-symbols.sh <version>, for example: scripts/upload-symbols.sh 0.3.10" >&2; exit 2; }

org="personal-projects-rn"
project="direction"
api="https://sentry.io/api/0/projects/$org/$project/files/dsyms/"
symbols="${DIRECTION_SYMBOLS_DIR:-$direction_root/build/symbols}/$version"

fail() { printf '\n%s\n' "$*" >&2; exit 1; }
compgen -G "$symbols/*.dSYM" >/dev/null || fail "No symbols for $version in $symbols. scripts/release.sh keeps them there; a release made before it did has none."

token="${SENTRY_AUTH_TOKEN:-}"
[ -n "$token" ] || token="$(security find-generic-password -s direction-sentry -a sentry -w 2>/dev/null || true)"
[ -n "$token" ] || fail "No Sentry token. Make an organization token at https://$org.sentry.io/settings/auth-tokens/ and save it with: security add-generic-password -U -s direction-sentry -a sentry -w"

# The token goes to curl on its standard input, never on the command line where other processes could read it.
sentry() { printf 'Authorization: Bearer %s\n' "$token" | curl -fsS -H @- "$@"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for dsym in "$symbols"/*.dSYM; do
  name="$(basename "$dsym")"
  ids="$(dwarfdump --uuid "$dsym" | awk '{ print $2 }')"
  echo "Sending $name ($(du -sh "$dsym" | cut -f1 | tr -d ' '))…"
  ditto -c -k --keepParent "$dsym" "$work/$name.zip"
  sentry -o /dev/null -F "file=@$work/$name.zip" "$api" || fail "Sentry didn't take $name. Check the token can upload debug files (project:releases or project:write)."
  for id in $ids; do
    lower="$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
    sentry "$api?query=$lower" | grep -qi "$lower" || fail "Sentry took $name but doesn't list $id yet."
  done
done
printf '\nSentry has the symbols for Direction %s.\n' "$version"
