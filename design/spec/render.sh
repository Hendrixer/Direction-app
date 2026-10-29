#!/bin/zsh
# Renders every frame in screens/ (or the ones named) to renders/<id>@1x.png, @2x.png and <id>.layout.json.
# usage: ./render.sh                 all frames
#        ./render.sh 13-screening    one frame (basename without .html)
set -e
cd "${0:A:h}"
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p renders
files=()
if (( $# )); then for a in "$@"; do files+=("screens/${a%.html}.html"); done; else files=(screens/*.html); fi
for f in $files; do
  id=${f:t:r}
  size=$(grep -o 'name="frame" content="[0-9]*x[0-9]*"' "$f" | grep -o '[0-9]*x[0-9]*' || echo 1440x900)
  w=${size%x*}; h=${size#*x}
  prof=$(mktemp -d)
  for scale in 1 2; do
    "$C" --headless=new --hide-scrollbars --force-device-scale-factor=$scale --window-size=$w,$h --virtual-time-budget=3000 \
      --run-all-compositor-stages-before-draw --user-data-dir="$prof" --screenshot="$PWD/renders/$id@${scale}x.png" "file://$PWD/$f" >/dev/null 2>&1
  done
  "$C" --headless=new --window-size=$w,$h --virtual-time-budget=3000 --user-data-dir="$prof" --dump-dom "file://$PWD/$f?layout" 2>/dev/null \
    | python3 -I -c 'import sys,re,html; m=re.search(r"<pre id=\"layout\">(.*?)</pre>", sys.stdin.read(), re.S); print(html.unescape(m.group(1)) if m else "[]")' > "renders/$id.layout.json"
  rm -rf "$prof"
  echo "rendered $id ($size)"
done
