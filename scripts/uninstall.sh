#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for INSTALLED_APP in "/Applications/MacSnap.app" "$HOME/Applications/MacSnap.app"; do
    INSTALLED_HELPER="$INSTALLED_APP/Contents/Helpers/MacSnapUninstaller"
    if [ -x "$INSTALLED_HELPER" ]; then
        exec "$INSTALLED_HELPER" --app "$INSTALLED_APP" "$@"
    fi
done

# A source checkout can build the same native helper without installing or launching MacSnap.
cd "$PROJECT_DIR"
swift build -c release --product MacSnapUninstaller
BUILD_DIR="$(swift build -c release --show-bin-path)"
exec "$BUILD_DIR/MacSnapUninstaller" "$@"
