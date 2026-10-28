#!/bin/bash
set -euo pipefail
direction_root="$(cd "$(dirname "$0")/.." && pwd)"
direction_binary="$direction_root/build/Direction.app/Contents/Helpers/direction"
direction_link="$HOME/.local/bin/direction"
if [ ! -x "$direction_binary" ]; then
  printf '%s\n' 'Build Direction first: ./scripts/build-app.sh release' >&2
  exit 1
fi
mkdir -p "$HOME/.local/bin"
if [ -e "$direction_link" ] || [ -L "$direction_link" ]; then
  if [ ! -L "$direction_link" ] || [ "$(readlink "$direction_link")" != "$direction_binary" ]; then
    printf '%s\n' "Refusing to replace existing $direction_link. Set DIRECTION_CLI instead." >&2
    exit 1
  fi
else
  ln -s "$direction_binary" "$direction_link"
fi
printf '%s\n' "Direction CLI ready at $direction_link" 'The plugin can now start its MCP server without a project.'
