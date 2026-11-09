#!/bin/sh
# Renders the share image and icons from tools/og.html with headless Chrome.
# Run from anywhere: sh site/tools/render-og.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
public="$here/../public"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
page="file://$here/og.html"
flags="--headless=new --hide-scrollbars --force-device-scale-factor=1 --allow-file-access-from-files --virtual-time-budget=3000"

"$chrome" $flags --window-size=1200,630 --screenshot="$here/og.png" "$page" 2>/dev/null
sips -s format jpeg -s formatOptions 86 "$here/og.png" --out "$public/og.jpg" >/dev/null
rm "$here/og.png"
"$chrome" $flags --window-size=512,512 --screenshot="$here/icon-512.png" "$page?icon" 2>/dev/null
sips -z 180 180 "$here/icon-512.png" --out "$public/apple-touch-icon.png" >/dev/null
sips -z 32 32 "$here/icon-512.png" --out "$public/favicon-32.png" >/dev/null
rm "$here/icon-512.png"
ls -la "$public/og.jpg" "$public/apple-touch-icon.png" "$public/favicon-32.png"
