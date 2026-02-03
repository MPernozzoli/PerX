#!/bin/bash
#
# PerX Hub - Mac Mini Server Setup
# Configura il Mac Mini come server h24 per PerX Hub e tutti i worker
#
# REQUISITI:
# - macOS 12+ (Monterey o successivo)
# - Accesso root (sudo)
# - Python 3.11+
# - Node.js 18+
#
# ESEGUIRE CON: sudo ./setup-mac-mini-server.sh
#

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           PerX Hub - Mac Mini Server Setup              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verifica root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Questo script richiede privilegi root.${NC}"
    echo "Esegui: sudo $0"
    exit 1
fi

# Directory base
HUB_BASE="/opt/perx-hub"
REPO_BASE="$(cd "$(dirname "$0")/.." && pwd)"

echo -e "${YELLOW}[1/8] Creazione directory...${NC}"
mkdir -p "$HUB_BASE"/{bin,logs,data,vault,workers/{email,wa-bridge,autoupdater},repo}
chmod -R 755 "$HUB_BASE"

echo -e "${YELLOW}[2/8] Configurazione Power Management (anti-sleep)...${NC}"
# Previeni TUTTI i tipi di sonno
pmset -a sleep 0           # Disabilita sonno
pmset -a disksleep 0       # Disabilita sonno disco
pmset -a displaysleep 0    # Disabilita sonno display
pmset -a womp 1            # Wake on network access
pmset -a networkoversleep 1 # Network mentre in sonno
pmset -a powernap 1        # Power Nap per aggiornamenti
pmset -a autopoweroff 0    # No auto power off
pmset -a standby 0         # No standby

# Verifica impostazioni
echo "  Power settings configurati:"
pmset -g | grep -E "sleep|womp|standby|autopoweroff" | head -10

echo -e "${YELLOW}[3/8] Configurazione login automatico...${NC}"
# Abilita riavvio automatico dopo power failure
pmset -a autorestart 1

# Nota: il login automatico richiede configurazione manuale in System Preferences
echo "  ⚠️  Per login automatico, configura in: System Preferences > Users & Groups > Login Options"

echo -e "${YELLOW}[4/8] Installazione PerX Hub...${NC}"
if [ -f "$REPO_BASE/PerXHub/.build/release/PerXHub" ]; then
    cp "$REPO_BASE/PerXHub/.build/release/PerXHub" "$HUB_BASE/PerXHub"
    chmod +x "$HUB_BASE/PerXHub"
    echo "  ✓ PerXHub binary installato"
else
    echo "  ⚠️  Build PerXHub non trovata. Esegui: cd PerXHub && swift build -c release"
fi

echo -e "${YELLOW}[5/8] Installazione Email Worker...${NC}"
if [ -d "$REPO_BASE/perx_email_worker" ]; then
    cp -r "$REPO_BASE/perx_email_worker/"* "$HUB_BASE/workers/email/"
    
    # Crea virtual environment
    cd "$HUB_BASE/workers/email"
    python3 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install -r requirements.txt
    
    echo "  ✓ Email Worker installato"
fi

echo -e "${YELLOW}[6/8] Installazione WA Bridge...${NC}"
if [ -d "$REPO_BASE/perx_wa_bridge" ]; then
    cp -r "$REPO_BASE/perx_wa_bridge/"* "$HUB_BASE/workers/wa-bridge/"
    
    # Installa dipendenze Node
    cd "$HUB_BASE/workers/wa-bridge"
    npm install --production
    
    echo "  ✓ WA Bridge installato"
fi

echo -e "${YELLOW}[7/8] Installazione AutoUpdater...${NC}"
if [ -d "$REPO_BASE/perx_autoupdater" ]; then
    cp -r "$REPO_BASE/perx_autoupdater/"* "$HUB_BASE/workers/autoupdater/"
    
    # Crea virtual environment
    cd "$HUB_BASE/workers/autoupdater"
    python3 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install -r requirements.txt
    
    echo "  ✓ AutoUpdater installato"
fi

echo -e "${YELLOW}[8/8] Installazione Launch Daemons...${NC}"

# Copia plist come LaunchDaemons (non LaunchAgents!)
# LaunchDaemons girano come root al boot, senza bisogno di login utente

DAEMONS_DIR="/Library/LaunchDaemons"

# Hub
cp "$REPO_BASE/PerXHub/Resources/com.perx.hub.plist" "$DAEMONS_DIR/"
chown root:wheel "$DAEMONS_DIR/com.perx.hub.plist"
chmod 644 "$DAEMONS_DIR/com.perx.hub.plist"

# Email Worker
cp "$REPO_BASE/perx_email_worker/com.perx.email-worker.plist" "$DAEMONS_DIR/"
chown root:wheel "$DAEMONS_DIR/com.perx.email-worker.plist"
chmod 644 "$DAEMONS_DIR/com.perx.email-worker.plist"

# WA Bridge
cp "$REPO_BASE/perx_wa_bridge/com.perx.wa-bridge.plist" "$DAEMONS_DIR/"
chown root:wheel "$DAEMONS_DIR/com.perx.wa-bridge.plist"
chmod 644 "$DAEMONS_DIR/com.perx.wa-bridge.plist"

# AutoUpdater
cp "$REPO_BASE/perx_autoupdater/com.perx.autoupdater.plist" "$DAEMONS_DIR/"
chown root:wheel "$DAEMONS_DIR/com.perx.autoupdater.plist"
chmod 644 "$DAEMONS_DIR/com.perx.autoupdater.plist"

echo "  ✓ Launch Daemons installati in $DAEMONS_DIR"

# Carica i daemon
echo ""
echo -e "${YELLOW}Caricamento servizi...${NC}"

for plist in com.perx.hub com.perx.email-worker com.perx.wa-bridge com.perx.autoupdater; do
    # Scarica se già caricato
    launchctl bootout system/$plist 2>/dev/null || true
    
    # Carica
    launchctl bootstrap system "$DAEMONS_DIR/$plist.plist"
    
    # Verifica
    if launchctl print system/$plist &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $plist caricato"
    else
        echo -e "  ${RED}✗${NC} $plist FALLITO"
    fi
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Setup completato con successo!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Servizi installati:"
echo "  • PerX Hub        → http://localhost:8080"
echo "  • Email Worker    → http://localhost:5001"
echo "  • WA Bridge       → http://localhost:5002"
echo "  • AutoUpdater     → http://localhost:8084"
echo ""
echo "Directory:"
echo "  • Base:    $HUB_BASE"
echo "  • Logs:    $HUB_BASE/logs"
echo "  • Data:    $HUB_BASE/data"
echo "  • Vault:   $HUB_BASE/vault"
echo ""
echo "Comandi utili:"
echo "  • Stato servizi:    sudo launchctl list | grep perx"
echo "  • Log Hub:          tail -f $HUB_BASE/logs/hub.log"
echo "  • Log Email Worker: tail -f $HUB_BASE/logs/email-worker.log"
echo "  • Riavvia Hub:      sudo launchctl kickstart -k system/com.perx.hub"
echo ""
echo -e "${YELLOW}IMPORTANTE:${NC}"
echo "  Il Mac Mini NON andrà mai in sonno grazie a pmset e PreventsSleep."
echo "  I servizi si avvieranno automaticamente al boot, anche senza login."
echo ""
