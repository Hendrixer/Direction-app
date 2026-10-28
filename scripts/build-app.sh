#!/bin/bash
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
direction_configuration="${1:-debug}"
cd "$direction_root"
swift build -c "$direction_configuration" --product DirectionApp
swift build -c "$direction_configuration" --product direction
direction_bin="$(swift build -c "$direction_configuration" --show-bin-path)"
direction_app="$direction_root/build/Direction.app"
rm -rf "$direction_app"
mkdir -p "$direction_app/Contents/MacOS" "$direction_app/Contents/Helpers" "$direction_app/Contents/Resources"
cp "$direction_bin/DirectionApp" "$direction_app/Contents/MacOS/Direction"
cp "$direction_bin/direction" "$direction_app/Contents/Helpers/direction"
if cmp -s "$direction_app/Contents/MacOS/Direction" "$direction_app/Contents/Helpers/direction"; then
  printf '%s\n' 'Packaging failed: GUI and CLI must be distinct executables.' >&2
  exit 1
fi
cp "$direction_root/Resources/Info.plist" "$direction_app/Contents/Info.plist"
cp "$direction_root/Resources/AppIcon.icns" "$direction_app/Contents/Resources/AppIcon.icns"
cp "$direction_root/THIRD_PARTY_NOTICES.md" "$direction_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
mkdir -p "$direction_app/Contents/Resources/Licenses"
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
codesign --force --sign - "$direction_app/Contents/Helpers/direction"
codesign --force --deep --sign - "$direction_app"
printf '%s\n' "$direction_app"
