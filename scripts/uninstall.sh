#!/bin/bash
set -e

PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
APP_DEST="/Applications/MacSnap.app"

echo "=========================================================="
echo "🛑 Uninstalling MacSnap and removing Launch at Login..."
echo "=========================================================="

pkill -x "MacSnap" 2>/dev/null || true

if [ -f "$LAUNCH_AGENT_PATH" ]; then
    launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT_PATH"
    echo "✓ Removed from LaunchAgents ($LAUNCH_AGENT_PATH)"
fi

if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
    echo "✓ Removed from $APP_DEST"
fi

echo "=========================================================="
echo "✅ MacSnap successfully uninstalled."
echo "=========================================================="
