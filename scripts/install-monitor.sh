#!/bin/bash
#
# Installa solo PerX Hub Monitor in /Applications
# Uso: dalla root del repo  →  sudo ./scripts/install-monitor.sh
#      oppure da PerX HUB  →  sudo ./scripts/install-monitor.sh
#
set -e

REPO_BASE="${PERX_REPO_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
MONITOR_DIR="$REPO_BASE/PerXHubMonitor"

if [ ! -d "$MONITOR_DIR" ]; then
    echo "Errore: PerXHubMonitor non trovato in $MONITOR_DIR"
    exit 1
fi

echo "Build PerX Hub Monitor da $MONITOR_DIR ..."
cd "$MONITOR_DIR"
rm -rf .build
swift build -c release

if [ ! -f "$MONITOR_DIR/.build/release/PerXHubMonitor" ]; then
    echo "Errore: build fallita"
    exit 1
fi

echo "Installazione in /Applications/PerXHubMonitor.app ..."
sudo mkdir -p /Applications/PerXHubMonitor.app/Contents/MacOS
sudo mkdir -p /Applications/PerXHubMonitor.app/Contents/Resources
sudo cp "$MONITOR_DIR/.build/release/PerXHubMonitor" /Applications/PerXHubMonitor.app/Contents/MacOS/
sudo chmod +x /Applications/PerXHubMonitor.app/Contents/MacOS/PerXHubMonitor

sudo tee /Applications/PerXHubMonitor.app/Contents/Info.plist > /dev/null << 'EOF'
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

# Firma ad-hoc: evita il blocco "l'applicazione non è supportata sul Mac"
sudo codesign -s - --force --deep /Applications/PerXHubMonitor.app 2>/dev/null || true

echo "Fatto. Apri con: open /Applications/PerXHubMonitor.app"
