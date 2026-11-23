#!/bin/bash
# Regenerates Resources/AppIcon.icns (and Resources/AppIcon.png) from tools/MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift tools/MakeIcon.swift "$WORK/icon-1024.png"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for px in 16 32 128 256 512; do
  sips -z $px $px "$WORK/icon-1024.png" --out "$SET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$WORK/icon-1024.png" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$WORK/icon-1024.png" Resources/AppIcon.png
echo "==> Resources/AppIcon.icns"
