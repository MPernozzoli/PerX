#!/bin/bash
# Script di installazione per PerX AutoUpdater

set -e

echo "=== PerX AutoUpdater - Installazione ==="

# Directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_FILE="$SCRIPT_DIR/com.perx.autoupdater.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Installa dipendenze Python
echo "[1/4] Installazione dipendenze Python..."
pip3 install -r "$SCRIPT_DIR/requirements.txt" --quiet

# Crea directory LaunchAgents se non esiste
echo "[2/4] Configurazione launchd..."
mkdir -p "$LAUNCH_AGENTS_DIR"

# Copia plist
cp "$PLIST_FILE" "$LAUNCH_AGENTS_DIR/"

# Aggiorna percorsi nel plist con il percorso corretto
PLIST_TARGET="$LAUNCH_AGENTS_DIR/com.perx.autoupdater.plist"
sed -i '' "s|/Users/mpernozzoli/Documents/Attività Peritali/App/PerX BKP16 - fulminazioni Recupero|$SCRIPT_DIR/..|g" "$PLIST_TARGET"

# Scarica agent se già caricato
echo "[3/4] Avvio servizio..."
launchctl unload "$PLIST_TARGET" 2>/dev/null || true

# Carica agent
launchctl load "$PLIST_TARGET"

echo "[4/4] Verifica..."
sleep 2

# Verifica che sia in esecuzione
if launchctl list | grep -q "com.perx.autoupdater"; then
    echo ""
    echo "✅ PerX AutoUpdater installato e avviato con successo!"
    echo ""
    echo "Endpoint: http://localhost:8084/health"
    echo "Log:      /tmp/perx-autoupdater.log"
    echo ""
else
    echo ""
    echo "⚠️ Il servizio non risulta avviato. Controlla i log:"
    echo "   cat /tmp/perx-autoupdater-error.log"
    echo ""
fi
