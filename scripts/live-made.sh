#!/bin/bash
# The paid trials of made-media versions (docs/speed-and-quality.md › Still to test), with your OpenRouter key.
#
#   scripts/live-made.sh <a take with you on camera> <a take of you at a desk> [results folder]
#
# The key comes from Direction's own keychain item (macOS asks you to allow it) or, if that fails, you paste it.
# It's handed to the test in the environment only: never printed, logged or saved. Everything else runs on
# scratch paths in the results folder: its own film, spend record and logs, never your library or films.
# DIRECTION_LIVE_MADE_ROUND is 2 (the follow-ups, the default) or 1 (the first set, 8 Nov 2026).
# DIRECTION_LIVE_MADE_BUDGET (default 4) is the most it spends; DIRECTION_LIVE_MADE_ONLY=4,6-flare runs some.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { echo "Usage: scripts/live-made.sh <camera take> <desk take> [results folder]" >&2; exit 2; }
camera="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
desk="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
[ -f "$camera" ] && [ -f "$desk" ] || { echo "Both takes must be files." >&2; exit 2; }
out="${3:-$root/build/live-made/$(date +%Y-%m-%d-%H%M)}"
mkdir -p "$out/env"

key="$(security find-generic-password -s dev.direction.openrouter -a app -w 2>/dev/null || true)"
if [ -z "$key" ]; then
  read -r -s -p "OpenRouter key (it isn't shown): " key; echo
fi
[ -n "$key" ] || { echo "No key, so nothing was sent." >&2; exit 1; }

round="${DIRECTION_LIVE_MADE_ROUND:-2}"
echo "Running round $round of the trials (up to \$${DIRECTION_LIVE_MADE_BUDGET:-4}); results in $out"
cd "$root"
DIRECTION_OPENROUTER_KEY="$key" \
DIRECTION_LIVE_MADE="$out" DIRECTION_LIVE_MADE_CAMERA="$camera" DIRECTION_LIVE_MADE_DESK="$desk" \
DIRECTION_LIVE_MADE_BUDGET="${DIRECTION_LIVE_MADE_BUDGET:-4}" DIRECTION_LIVE_MADE_ROUND="$round" \
DIRECTION_LIBRARY_PATH="$out/env/library.sqlite" DIRECTION_LOG_DIR="$out/env/logs" DIRECTION_CACHE_DIR="$out/env/caches" \
DIRECTION_STYLES_PATH="$out/env/styles" DIRECTION_TECHNIQUES_PATH="$out/env/techniques" HF_HUB_OFFLINE=1 \
  swift test --filter LiveMadeTrials 2>&1 | grep --line-buffered -E "LIVE-MADE|error:|recorded an issue|passed after|failed after" || true
unset key
echo "Done: $out/results.json"
