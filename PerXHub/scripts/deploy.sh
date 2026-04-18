#!/bin/bash
#
# PerX Hub Deploy Script
# Builds and deploys PerXHub to /opt/perx-hub
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="/opt/perx-hub"
PLIST_NAME="com.perx.hub.plist"

echo "=== PerX Hub Deploy ==="
echo "Source: $HUB_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Check if running as root for system-wide install
if [ "$EUID" -ne 0 ]; then
    echo "Note: Running without sudo. Some operations may fail."
    echo "For full system install, run: sudo $0"
    echo ""
fi

# Build
echo "[1/6] Building PerXHub..."
cd "$HUB_DIR"
swift build -c release
echo "Build complete."

# Stop existing daemon
echo "[2/6] Stopping existing daemon (if any)..."
if [ -f "/Library/LaunchDaemons/$PLIST_NAME" ]; then
    sudo launchctl unload "/Library/LaunchDaemons/$PLIST_NAME" 2>/dev/null || true
    echo "Daemon stopped."
else
    echo "No existing daemon found."
fi

# Create directories
echo "[3/6] Creating directories..."
sudo mkdir -p "$TARGET_DIR"/{data,vault,logs}
sudo mkdir -p "$TARGET_DIR/vault/sinistri"
echo "Directories created."

# Copy executable
echo "[4/6] Copying executable..."
HUB_BIN=""
for cand in "$HUB_DIR/.build/release/PerXHub" "$HUB_DIR/.build/arm64-apple-macosx/release/PerXHub" "$HUB_DIR/.build/x86_64-apple-macosx/release/PerXHub"; do
    if [ -f "$cand" ]; then HUB_BIN="$cand"; break; fi
done
if [ -z "$HUB_BIN" ]; then
    HUB_BIN="$(ls "$HUB_DIR/.build/"*/release/PerXHub 2>/dev/null | head -1)"
fi
if [ -z "$HUB_BIN" ] || [ ! -f "$HUB_BIN" ]; then
    echo "ERRORE: eseguibile PerXHub non trovato dopo swift build (cerca in .build/*-apple-macosx/release/)."
    exit 1
fi
sudo cp "$HUB_BIN" "$TARGET_DIR/"
sudo chmod +x "$TARGET_DIR/PerXHub"
sudo codesign -s - --force "$TARGET_DIR/PerXHub" 2>/dev/null || true
echo "Executable copied."

# Copy plist
echo "[5/6] Installing LaunchDaemon..."
sudo cp "$HUB_DIR/Resources/$PLIST_NAME" "/Library/LaunchDaemons/"
sudo chown root:wheel "/Library/LaunchDaemons/$PLIST_NAME"
sudo chmod 644 "/Library/LaunchDaemons/$PLIST_NAME"
echo "LaunchDaemon installed."

# Start daemon
echo "[6/6] Starting daemon..."
sudo launchctl load "/Library/LaunchDaemons/$PLIST_NAME"
echo "Daemon started."

echo ""
echo "=== Deploy Complete ==="
echo ""
echo "PerX Hub is now running at http://0.0.0.0:8080"
echo ""
echo "Useful commands:"
echo "  Check status:  curl http://localhost:8080/health"
echo "  View logs:     tail -f $TARGET_DIR/logs/hub.log"
echo "  Stop daemon:   sudo launchctl unload /Library/LaunchDaemons/$PLIST_NAME"
echo "  Start daemon:  sudo launchctl load /Library/LaunchDaemons/$PLIST_NAME"
echo ""
