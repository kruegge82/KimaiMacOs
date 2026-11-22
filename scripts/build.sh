#!/bin/bash
# Builds Kimai Timer. Usage: scripts/build.sh [Debug|Release]
# Signs with the first local "Apple Development" identity if there is one (stable Keychain
# access across rebuilds), otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-Release}"
IDENTITY="${CODE_SIGN_IDENTITY_OVERRIDE:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
SIGN_ARGS=()
if [[ -n "$IDENTITY" ]]; then
    SIGN_ARGS=("CODE_SIGN_IDENTITY=$IDENTITY")
fi

xcodebuild -project KimaiTimer.xcodeproj -scheme KimaiTimer -configuration "$CONFIGURATION" \
    -derivedDataPath build -destination 'platform=macOS' \
    "${SIGN_ARGS[@]}" build | { grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true; }

echo "App: $(pwd)/build/Build/Products/$CONFIGURATION/Kimai Timer.app"
