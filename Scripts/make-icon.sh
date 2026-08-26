#!/usr/bin/env bash
# Turns a 1024x1024 PNG into Resources/AppIcon.icns. macOS only (uses sips + iconutil).
#
# OptiRecord is a menu bar app (LSUIElement), so this icon only shows up in Finder,
# the About panel, and System Settings' privacy panes — which is exactly where
# the user looks when granting Screen Recording, so it is worth having.
set -euo pipefail

SOURCE="${1:-}"
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
    echo "usage: $0 path/to/icon-1024.png" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z $size $size          "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
    sips -z $((size*2)) $((size*2)) "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
