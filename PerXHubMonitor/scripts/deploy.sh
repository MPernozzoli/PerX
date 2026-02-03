#!/bin/bash
#
# PerX Hub Monitor Deploy Script
# Installa l'app menu bar per monitorare l'Hub
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="PerXHubMonitor"
TARGET_DIR="$HOME/Applications"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.perx.hub-monitor.plist"

echo "=== PerX Hub Monitor Deploy ==="
echo "Source: $MONITOR_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Build
echo "[1/4] Building PerXHubMonitor..."
cd "$MONITOR_DIR"
swift build -c release
echo "Build complete."

# Create app bundle
echo "[2/4] Creating app bundle..."
mkdir -p "$TARGET_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$TARGET_DIR/$APP_NAME.app/Contents/Resources"

# Copy executable
cp "$MONITOR_DIR/.build/release/$APP_NAME" "$TARGET_DIR/$APP_NAME.app/Contents/MacOS/"
chmod +x "$TARGET_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$TARGET_DIR/$APP_NAME.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PerXHubMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.perx.hub-monitor</string>
    <key>CFBundleName</key>
    <string>PerX Hub Monitor</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "App bundle created."

# Install LaunchAgent for auto-start at login
echo "[3/4] Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.perx.hub-monitor</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

echo "LaunchAgent installed."

# Start app
echo "[4/4] Starting PerX Hub Monitor..."
launchctl unload "$LAUNCH_AGENT_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_DIR/$PLIST_NAME"

echo ""
echo "=== Deploy Complete ==="
echo ""
echo "PerX Hub Monitor è ora installato e attivo nella menu bar."
echo ""
echo "L'app si avvierà automaticamente al login."
echo ""
echo "Posizione app: $TARGET_DIR/$APP_NAME.app"
echo ""
echo "Comandi utili:"
echo "  Stop:   launchctl unload $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Start:  launchctl load $LAUNCH_AGENT_DIR/$PLIST_NAME"
echo "  Apri:   open $TARGET_DIR/$APP_NAME.app"
echo ""
