#!/bin/bash
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$direction_root"
export DIRECTION_TEST_ARTIFACTS="$direction_root/build/verification"
export DIRECTION_LIBRARY_PATH="$direction_root/build/verification/test-library.sqlite"
# The CLI checks run as their own processes: keep their caches and log out of the real ones too.
export DIRECTION_CACHE_DIR="$direction_root/build/verification/caches"
export DIRECTION_LOG_DIR="$direction_root/build/verification/logs"
export DIRECTION_STYLES_PATH="$direction_root/build/verification/styles"
swift test
direction_bin="$(swift build --show-bin-path)"
python3 "$direction_root/scripts/smoke.py" "$direction_bin/direction" "$DIRECTION_TEST_ARTIFACTS/two-track-source.mov" "$DIRECTION_TEST_ARTIFACTS"

python3 "$direction_root/scripts/test-plugins.py" "$direction_bin/direction" "$DIRECTION_TEST_ARTIFACTS/two-track-source.mov"
