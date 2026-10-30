#!/bin/bash
# Build a local test app without installing, publishing, or changing its version.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

swift test
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
TEST_ROOT="$(mktemp -d "$PROJECT_DIR/.build/manual-test.XXXXXX")"
TEST_APP="$TEST_ROOT/MacSnap.app"

SIGNING_IDENTITY="${MACSNAP_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -p codesigning -v | awk '/"Apple Development:/ {print $2; exit}')"
fi
# Local development can be ad-hoc signed when no development certificate is available.
python3 scripts/update-distribution.py assemble --binary "$BUILD_DIR/MacSnap" --output "$TEST_APP" \
    --identity "${SIGNING_IDENTITY:--}" --allow-unconfigured
printf 'Local test build: %s\n' "$TEST_APP"
printf 'Quit the installed MacSnap, then open this app to test. No installation was replaced.\n'
