#!/bin/bash
set -e

PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
APP_DEST="/Applications/MacSnap.app"

echo "=========================================================="
echo "🛑 Desinstalando o MacSnap e removendo do início automático..."
echo "=========================================================="

pkill -x "MacSnap" 2>/dev/null || true

if [ -f "$LAUNCH_AGENT_PATH" ]; then
    launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT_PATH"
    echo "✓ Removido do LaunchAgents ($LAUNCH_AGENT_PATH)"
fi

if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
    echo "✓ Removido de $APP_DEST"
fi

echo "=========================================================="
echo "✅ MacSnap desinstalado com sucesso."
echo "=========================================================="
