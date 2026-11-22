#!/bin/bash
# Renders the main views with sample data into PNG files.
# Usage: scripts/snapshots.sh <output-folder> [language, e.g. de or en]
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:?output folder required}"
LANGUAGE="${2:-en}"
mkdir -p "$OUTPUT"

# Unsandboxed debug build in its own folder, so it can write to OUTPUT.
xcodebuild -project KimaiTimer.xcodeproj -scheme KimaiTimer -configuration Debug \
    -derivedDataPath build/snapshots -destination 'platform=macOS' \
    CODE_SIGN_ENTITLEMENTS= build | { grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true; }

"build/snapshots/Build/Products/Debug/Kimai Timer.app/Contents/MacOS/Kimai Timer" \
    --snapshot "$(cd "$OUTPUT" && pwd)" -AppleLanguages "($LANGUAGE)"
