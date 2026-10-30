#!/bin/bash
set -e

# ==============================================================================
# MacSnap - Installation and Launch at Login Script for macOS
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacSnap.app"
DEST_DIR="/Applications"
APP_DEST="$DEST_DIR/$APP_NAME"
PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$PLIST_LABEL.plist"

echo "=========================================================="
echo "🚀 Installing MacSnap on macOS"
echo "=========================================================="

# 1. Compile optimized Release binary (Universal arm64 + x86_64 when supported)
echo "📦 Building production binary (Release)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

RELEASE_BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacSnap"

if [ ! -f "$RELEASE_BIN" ]; then
    echo "❌ Error: Compiled binary was not found."
    exit 1
fi

# 2. Create .app bundle structure
echo "📁 Assembling $APP_NAME bundle..."
BUILD_STAGE="$(mktemp -d /tmp/macsnap-local-install.XXXXXX)"
TMP_APP="$BUILD_STAGE/$APP_NAME"
trap 'rm -rf "$BUILD_STAGE"' EXIT

# 3. Code signature (codesign)
# Look for local Apple Development certificate in keychain for a stable
# Designated Requirement (preventing macOS from resetting Accessibility permission on every rebuild).
DEV_CERT=$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
if [ -n "$DEV_CERT" ]; then
    echo "🔏 Signing with stable developer certificate: $DEV_CERT..."
    SIGNING_IDENTITY="$DEV_CERT"
else
    echo "🔏 Applying ad-hoc codesign signature..."
    SIGNING_IDENTITY="-"
fi
python3 scripts/update-distribution.py assemble --binary "$RELEASE_BIN" --output "$TMP_APP" \
    --identity "$SIGNING_IDENTITY" --allow-unconfigured

# 4. Install in /Applications
echo "📂 Copying to $DEST_DIR..."
# Terminate running instance if any
pkill -x "MacSnap" || true
rm -rf "$APP_DEST"
cp -R "$TMP_APP" "$APP_DEST"
rm -rf "$TMP_APP"

# 5. Configure LaunchAgent for Launch at Login
echo "⚙️ Configuring Launch at Login..."
mkdir -p "$LAUNCH_AGENT_DIR"

cat <<EOF > "$LAUNCH_AGENT_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DEST/Contents/MacOS/MacSnap</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/MacSnap.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/MacSnap.log</string>
</dict>
</plist>
EOF

# Register and load LaunchAgent (which launches the app)
launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PATH"

echo "=========================================================="
echo "✅ MacSnap successfully installed in: $APP_DEST"
echo "✅ Launch at Login configured in: $LAUNCH_AGENT_PATH"
echo "=========================================================="
echo ""
echo "💡 Tip: MacSnap operates from the macOS menu bar."
echo "If this is your first run, ensure Accessibility permission is granted in:"
echo "   👉 System Settings > Privacy & Security > Accessibility"
echo ""
