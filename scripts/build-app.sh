#!/bin/bash
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
direction_configuration="${1:-debug}"
cd "$direction_root"
swift build -c "$direction_configuration" --product DirectionApp
swift build -c "$direction_configuration" --product direction
direction_bin="$(swift build -c "$direction_configuration" --show-bin-path)"
# DIRECTION_APP_DIR: where the app goes (scripts/release.sh builds its own copy, so the one you run stays).
direction_app="${DIRECTION_APP_DIR:-$direction_root/build/Direction.app}"
rm -rf "$direction_app"
mkdir -p "$direction_app/Contents/MacOS" "$direction_app/Contents/Helpers" "$direction_app/Contents/Resources" "$direction_app/Contents/Frameworks"
cp "$direction_bin/DirectionApp" "$direction_app/Contents/MacOS/Direction"
cp "$direction_bin/direction" "$direction_app/Contents/Helpers/direction"
if cmp -s "$direction_app/Contents/MacOS/Direction" "$direction_app/Contents/Helpers/direction"; then
  printf '%s\n' 'Packaging failed: GUI and CLI must be distinct executables.' >&2
  exit 1
fi
cp "$direction_root/Resources/Info.plist" "$direction_app/Contents/Info.plist"
cp "$direction_root/Resources/AppIcon.icns" "$direction_app/Contents/Resources/AppIcon.icns"
cp "$direction_root/THIRD_PARTY_NOTICES.md" "$direction_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
# The skills Direction hands the editor it starts (docs/editor-runs.md).
cp -R "$direction_root/plugins/direction/skills" "$direction_app/Contents/Resources/Skills"
mkdir -p "$direction_app/Contents/Resources/Licenses"
# Libraries linked from a binary build have no checkout: their licenses are kept in Resources/Licenses.
cp -R "$direction_root/Resources/Licenses/." "$direction_app/Contents/Resources/Licenses/"
for direction_dependency in "$direction_root"/.build/checkouts/*; do
  if [ -d "$direction_dependency" ]; then
    direction_name="$(basename "$direction_dependency")"
    mkdir -p "$direction_app/Contents/Resources/Licenses/$direction_name"
    for direction_notice in "$direction_dependency"/LICENSE* "$direction_dependency"/NOTICE*; do
      if [ -f "$direction_notice" ]; then cp -f "$direction_notice" "$direction_app/Contents/Resources/Licenses/$direction_name/"; fi
    done
  fi
done
for direction_bundle in "$direction_bin"/*.bundle; do
  if [ -d "$direction_bundle" ]; then cp -R "$direction_bundle" "$direction_app/Contents/Resources/"; fi
done
# Sparkle, for updates to the copies we sign (docs/releasing.md). ditto keeps the framework's symlinks. The build
# copies it next to the app, but a release build doesn't always (0.3.2's didn't); the package's own copy of the pinned
# version is the same framework.
direction_sparkle="$direction_bin/Sparkle.framework"
[ -d "$direction_sparkle" ] || direction_sparkle="$direction_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$direction_sparkle" ] || { printf '%s\n' 'Packaging failed: no Sparkle.framework. Run: swift package resolve' >&2; exit 1; }
ditto "$direction_sparkle" "$direction_app/Contents/Frameworks/Sparkle.framework"
# SwiftPM leaves search paths into this checkout's build folder; the app finds Sparkle in Contents/Frameworks.
for direction_executable in "$direction_app/Contents/MacOS/Direction" "$direction_app/Contents/Helpers/direction"; do
  for direction_rpath in $(otool -l "$direction_executable" | awk '/LC_RPATH/ { getline; getline; print $2 }' | grep "^$direction_root/" || true); do
    install_name_tool -delete_rpath "$direction_rpath" "$direction_executable" 2>/dev/null
  done
done
codesign --force --sign - "$direction_app/Contents/Helpers/direction"
codesign --force --deep --sign - "$direction_app"
printf '%s\n' "$direction_app"
