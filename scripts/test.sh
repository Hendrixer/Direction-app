#!/bin/bash
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$direction_root"
export DIRECTION_TEST_ARTIFACTS="$direction_root/build/verification"
export DIRECTION_LIBRARY_PATH="$direction_root/build/verification/test-library.sqlite"
swift test
direction_bin="$(swift build --show-bin-path)"
python3 "$direction_root/scripts/smoke.py" "$direction_bin/direction" "$DIRECTION_TEST_ARTIFACTS/two-track-source.mov" "$DIRECTION_TEST_ARTIFACTS"

python3 "$direction_root/scripts/test-plugins.py" "$direction_bin/direction" "$DIRECTION_TEST_ARTIFACTS/two-track-source.mov"
