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
codesign --verify --deep --strict "$APP"

ZIP="$OUT/Kimai-Timer-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "Archive: $(pwd)/$ZIP"
