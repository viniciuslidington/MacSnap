#!/usr/bin/env bash
set -e

# ==============================================================================
#  __  __            ____                  
# |  \/  | __ _  ___/ ___| _ __   __ _ _ __ 
# | |\/| |/ _` |/ __\___ \| '_ \ / _` | '__|
# | |  | | (_| | (__ ___) | | | | (_| | |   
# |_|  |_|\__,_|\___|____/|_| |_|\__,_|_|   
#
# Automated command-line installer for macOS
# Repository: https://github.com/viniciuslidington/MacSnap
# ==============================================================================

REPO="viniciuslidington/MacSnap"
APP_NAME="MacSnap.app"
DEST_DIR="/Applications"
APP_DEST="$DEST_DIR/$APP_NAME"
PLIST_LABEL="com.viniciuslidington.MacSnap"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$PLIST_LABEL.plist"
RELEASE_URL="https://github.com/$REPO/releases/latest/download/MacSnap.app.zip"

# Terminal colors
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Uninstall support (--uninstall / -u)
if [[ "$1" == "--uninstall" ]] || [[ "$1" == "-u" ]]; then
    echo -e "${YELLOW}🛑 Uninstalling MacSnap...${NC}"
    pkill -x "MacSnap" 2>/dev/null || true
    if [ -f "$LAUNCH_AGENT_PATH" ]; then
        launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PATH"
        echo -e "  ${GREEN}✓${NC} Launch at Login removed from LaunchAgents"
    fi
    if [ -d "$APP_DEST" ]; then
        rm -rf "$APP_DEST"
        echo -e "  ${GREEN}✓${NC} $APP_DEST removed"
    fi
    echo -e "\n${GREEN}${BOLD}✅ MacSnap successfully uninstalled!${NC}\n"
    exit 0
fi

# 2. Operating System check
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}❌ Error: MacSnap is exclusively designed for macOS.${NC}"
    exit 1
fi

echo -e "${BLUE}${BOLD}"
echo "  __  __            ____                  "
echo " |  \/  | __ _  ___/ ___| _ __   __ _ _ __ "
echo " | |\/| |/ _\` |/ __\___ \| '_ \ / _\` | '__|"
echo " | |  | | (_| | (__ ___) | | | | (_| | |   "
echo " |_|  |_|\__,_|\___|____/|_| |_|\__,_|_|   "
echo -e "${NC}"
echo -e "${BOLD}🪟 Installing MacSnap on your Mac...${NC}"
echo "----------------------------------------------------------"

INSTALLED=false

# 3. If running inside a local cloned repo, run local install script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/Package.swift" ] && [ -f "$SCRIPT_DIR/scripts/install.sh" ]; then
    echo -e "${BLUE}ℹ️  Running local project installer...${NC}"
    bash "$SCRIPT_DIR/scripts/install.sh"
    exit 0
fi

# 4. Remote mode: attempt to download pre-compiled release binary from GitHub Releases
echo -e "📥 Downloading latest official release..."
TMP_DIR=$(mktemp -d /tmp/macsnap-install-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT
ZIP_FILE="$TMP_DIR/MacSnap.app.zip"

if curl -f -L --progress-bar "$RELEASE_URL" -o "$ZIP_FILE" 2>/dev/null; then
    echo -e "📦 Unpacking application..."
    unzip -q -o "$ZIP_FILE" -d "$TMP_DIR"
    
    if [ -d "$TMP_DIR/$APP_NAME" ]; then
        # Validate before stopping/removing the installed copy. Preserve the shipped signature.
        test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TMP_DIR/$APP_NAME/Contents/Info.plist")" = "$PLIST_LABEL"
        test -x "$TMP_DIR/$APP_NAME/Contents/MacOS/MacSnap"
        codesign --verify --strict --deep "$TMP_DIR/$APP_NAME"
        INSTALL_STAGE=$(mktemp -d "$DEST_DIR/.macsnap-install-XXXXXX")
        ditto "$TMP_DIR/$APP_NAME" "$INSTALL_STAGE/$APP_NAME"
        codesign --verify --strict --deep "$INSTALL_STAGE/$APP_NAME"
        pkill -x "MacSnap" 2>/dev/null || true
        if [ -e "$APP_DEST" ]; then
            mv "$APP_DEST" "$INSTALL_STAGE/previous.app"
        fi
        if ! mv "$INSTALL_STAGE/$APP_NAME" "$APP_DEST"; then
            if [ -e "$INSTALL_STAGE/previous.app" ]; then
                mv "$INSTALL_STAGE/previous.app" "$APP_DEST"
            fi
            echo -e "${RED}❌ Installation failed; the previous app was preserved.${NC}"
            exit 1
        fi
        rm -rf "$INSTALL_STAGE"
        INSTALLED=true
        echo -e "  ${GREEN}✓${NC} Application installed in $APP_DEST"
    fi
fi

# 5. Fallback: if release download fails, compile from source code
if [ "$INSTALLED" = false ]; then
    echo -e "${YELLOW}⚡ Pre-compiled package not found. Building from source...${NC}"
    
    if ! command -v swift >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: Swift compiler not found on your system.${NC}"
        echo -e "Install command-line tools via: ${BOLD}xcode-select --install${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    SRC_DIR="$TMP_DIR/source"
    git clone --depth 1 "https://github.com/$REPO.git" "$SRC_DIR"
    bash "$SRC_DIR/scripts/install.sh"
    rm -rf "$TMP_DIR"
    exit 0
fi

rm -rf "$TMP_DIR"

# 6. Keep the release's bundle and signature unchanged after download.
codesign --verify --strict --deep "$APP_DEST"

# 7. Configure LaunchAgent for Launch at Login
echo -e "⚙️  Configuring Launch at Login..."
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

launchctl unload "$LAUNCH_AGENT_PATH" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PATH" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} LaunchAgent registered ($LAUNCH_AGENT_PATH)"

# 8. Start application
open "$APP_DEST" 2>/dev/null || "$APP_DEST/Contents/MacOS/MacSnap" &

echo "----------------------------------------------------------"
echo -e "${GREEN}${BOLD}🎉 MacSnap successfully installed and started!${NC}"
echo "----------------------------------------------------------"
echo -e "\n${BOLD}⚠️  ATTENTION (Accessibility Permission):${NC}"
echo "MacSnap requires Accessibility permission to manage window positions."
echo -e "If this is your first installation, enable ${BOLD}MacSnap${NC} in:"
echo -e "   👉 ${BLUE}System Settings > Privacy & Security > Accessibility${NC}\n"

# Open Accessibility settings pane automatically for user convenience
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
