#!/bin/bash
# Builds the distributable archive: a universal (Apple silicon + Intel) Release build,
# signed ad hoc so that no personal signing identity ends up in the download.
# Usage: scripts/release.sh
# Result: build/release/Kimai-Timer-<version>.zip and its SHA-256 checksum.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/release-build
OUT=build/release
rm -rf "$DERIVED" "$OUT"
mkdir -p "$OUT"

xcodebuild -project KimaiTimer.xcodeproj -scheme KimaiTimer -configuration Release \
    -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- \
    build | { grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true; }

APP="$DERIVED/Build/Products/Release/Kimai Timer.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# An unstripped binary carries debug references with the absolute path of this checkout, and
# with it the name of the account that built it. Strip them, then sign again (ad hoc).
strip -S -x "$APP/Contents/MacOS/Kimai Timer"
codesign --force --sign - --options runtime --entitlements Config/KimaiTimer.entitlements "$APP"
codesign --verify --deep --strict "$APP"

# Refuse to package anything that still mentions this machine.
if grep -r -a -q -e "$HOME" -e "/Users/" "$APP"; then
    echo "error: the app bundle contains local paths; not packaging." >&2
    grep -r -a -l -e "$HOME" -e "/Users/" "$APP" >&2
    exit 1
fi

ZIP="$OUT/Kimai-Timer-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "Archive: $(pwd)/$ZIP"
