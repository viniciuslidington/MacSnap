#!/bin/bash
# Build a local test app without installing, publishing, or changing its version.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

swift test
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
TEST_APP="$PROJECT_DIR/.build/manual-test/MacSnap.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
cp "$BUILD_DIR/MacSnap" "$TEST_APP/Contents/MacOS/MacSnap"
cp Resources/Info.plist "$TEST_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$TEST_APP/Contents/Resources/AppIcon.icns"
chmod +x "$TEST_APP/Contents/MacOS/MacSnap"

SIGNING_IDENTITY="${MACSNAP_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -p codesigning -v | awk '/"Apple Development:/ {print $2; exit}')"
fi
# Local development can be ad-hoc signed when no development certificate is available.
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$TEST_APP"
codesign --verify --strict --deep "$TEST_APP"
cmp Resources/Info.plist "$TEST_APP/Contents/Info.plist"
printf 'Local test build: %s\n' "$TEST_APP"
printf 'Quit the installed MacSnap, then open this app to test. No installation was replaced.\n'
