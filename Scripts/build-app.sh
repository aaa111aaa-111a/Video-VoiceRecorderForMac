#!/usr/bin/env bash
# Assembles dist/Aizuchi.app from the SwiftPM executable.
#
# There is no Xcode project on purpose: SwiftPM is the single source of truth and
# this script does the three things an .app needs that `swift build` does not —
# the bundle layout, Info.plist, and a signature that TCC will remember.
set -euo pipefail

CONFIGURATION="release"
SIGN_IDENTITY="-"   # ad-hoc by default

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration|-c) CONFIGURATION="$2"; shift 2 ;;
        --sign|-s)          SIGN_IDENTITY="$2"; shift 2 ;;
        -h|--help)
            echo "usage: $0 [--configuration debug|release] [--sign IDENTITY]"
            exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Aizuchi"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VERSION="$(sed -n 's/.*public static let version = "\(.*\)"/\1/p' Sources/AizuchiCore/AppInfo.swift | head -1)"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER) [$CONFIGURATION]"
swift build -c "$CONFIGURATION" --arch arm64

BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
    echo "error: executable not found at $BINARY" >&2
    exit 1
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# SwiftPM emits resource bundles next to the binary; carry them along.
BIN_DIR="$(dirname "$BINARY")"
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -e "$bundle" ]] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "==> Signing ($SIGN_IDENTITY)"
# Screen Recording and Microphone permissions are keyed to the bundle id plus the
# signature. With an ad-hoc signature macOS may re-ask after each rebuild.
codesign --force --deep --options runtime \
    --entitlements Resources/Aizuchi.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"

codesign --verify --verbose "$APP"

echo ""
echo "Built $APP"
echo "  open $APP        # run it"
echo "  cp -R $APP /Applications/   # install"
