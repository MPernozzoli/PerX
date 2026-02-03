#!/bin/bash
#
# PerX Email Worker Deploy Script
# Installa e avvia il worker email su Mac Mini
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="/opt/perx-hub/email-worker"
PLIST_NAME="com.perx.email-worker.plist"
VENV_DIR="$TARGET_DIR/venv"

echo "=== PerX Email Worker Deploy ==="
echo "Source: $WORKER_DIR"
echo "Target: $TARGET_DIR"
echo ""

# Check if running as root for system-wide install
if [ "$EUID" -ne 0 ]; then
    echo "Note: Running without sudo. Some operations may fail."
    echo "For full system install, run: sudo $0"
    echo ""
fi

# Create directories
echo "[1/5] Creating directories..."
sudo mkdir -p "$TARGET_DIR"
sudo mkdir -p "$TARGET_DIR/logs"
sudo mkdir -p "/opt/perx-hub/tokens"
echo "Directories created."

# Copy files
echo "[2/5] Copying worker files..."
sudo cp -r "$WORKER_DIR"/*.py "$TARGET_DIR/"
sudo cp -r "$WORKER_DIR"/services "$TARGET_DIR/"
sudo cp "$WORKER_DIR/requirements.txt" "$TARGET_DIR/"
sudo cp "$WORKER_DIR/accounts.example.json" "$TARGET_DIR/"

# Create accounts.json if not exists
if [ ! -f "$TARGET_DIR/accounts.json" ]; then
    echo "Note: accounts.json not found. Copy from accounts.example.json and configure."
    sudo cp "$TARGET_DIR/accounts.example.json" "$TARGET_DIR/accounts.json"
fi
echo "Files copied."

# Create/update virtual environment
echo "[3/5] Setting up Python virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    sudo python3 -m venv "$VENV_DIR"
fi
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r "$TARGET_DIR/requirements.txt"
echo "Virtual environment ready."

# Create .env file if not exists
if [ ! -f "$TARGET_DIR/.env" ]; then
    echo "[4/5] Creating default .env file..."
    sudo tee "$TARGET_DIR/.env" > /dev/null <<EOF
# PerX Email Worker Configuration
HUB_URL=http://localhost:8080
IMAP_POLL_INTERVAL=60
SCHEDULED_CHECK_INTERVAL=30
LOG_LEVEL=INFO
LOG_FILE=/opt/perx-hub/email-worker/logs/email_worker.log
ACCOUNTS_FILE=/opt/perx-hub/email-worker/accounts.json
EOF
    echo ".env file created. Edit as needed."
else
    echo "[4/5] .env file already exists, skipping..."
fi

# Install LaunchDaemon
echo "[5/5] Installing LaunchDaemon..."
sudo tee "/Library/LaunchDaemons/$PLIST_NAME" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.perx.email-worker</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$VENV_DIR/bin/python</string>
        <string>$TARGET_DIR/main.py</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
    <key>WorkingDirectory</key>
    <string>$TARGET_DIR</string>
    
    <key>StandardOutPath</key>
    <string>/opt/perx-hub/email-worker/logs/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>/opt/perx-hub/email-worker/logs/stderr.log</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PYTHONUNBUFFERED</key>
        <string>1</string>
    </dict>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

sudo chown root:wheel "/Library/LaunchDaemons/$PLIST_NAME"
sudo chmod 644 "/Library/LaunchDaemons/$PLIST_NAME"
echo "LaunchDaemon installed."

# Start daemon
echo ""
echo "=== Deploy Complete ==="
echo ""
echo "To start the worker:"
echo "  sudo launchctl load /Library/LaunchDaemons/$PLIST_NAME"
echo ""
echo "To stop the worker:"
echo "  sudo launchctl unload /Library/LaunchDaemons/$PLIST_NAME"
echo ""
echo "Logs:"
echo "  tail -f $TARGET_DIR/logs/email_worker.log"
echo ""
echo "IMPORTANT: Configure accounts.json before starting!"
echo "  sudo nano $TARGET_DIR/accounts.json"
echo ""
