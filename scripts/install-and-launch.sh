#!/bin/bash
#
# PerX Hub - Installazione e avvio completo
# Un solo script per installare tutto il sistema e avviare i servizi.
#
# Cartella di lavoro (repo): /Users/mpernozzoli/PerX HUB
#   Qui vanno clonati/copiati PerXHub, PerXHubMonitor, PerXCore,
#   perx_email_worker, perx_wa_bridge, perx_autoupdater, scripts, ecc.
#
# L'AutoUpdater scannerizza questa cartella; quando trovi aggiornamenti
# riesegui questo script per copiare i file in /opt/perx-hub e reinstallare.
#
# REQUISITI: macOS 12+, sudo, Python 3.11+, Node.js 18+, Swift (Xcode)
# USO: sudo ./scripts/install-and-launch.sh
#      (dalla root del repo, es: cd "/Users/mpernozzoli/PerX HUB" && sudo ./scripts/install-and-launch.sh)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cartella di lavoro: dove sono clonati hub, worker, monitor, scripts
# Override con: PERX_REPO_PATH="/altro/path" sudo ./scripts/install-and-launch.sh
REPO_BASE="${PERX_REPO_PATH:-/Users/mpernozzoli/PerX HUB}"
HUB_BASE="/opt/perx-hub"
DAEMONS_DIR="/Library/LaunchDaemons"
# Porte usate da Hub e worker (liberate prima dell'install)
PERX_PORTS="8080 5001 5002 8084"

# SwiftPM su Apple Silicon mette spesso l'eseguibile in .build/arm64-apple-macosx/release/, non in .build/release/
resolve_swift_release_binary() {
    local pkg_dir="$1"
    local exe_name="$2"
    if [ -f "$pkg_dir/.build/release/$exe_name" ]; then
        echo "$pkg_dir/.build/release/$exe_name"
        return 0
    fi
    local cand
    for cand in "$pkg_dir"/.build/*-apple-macosx/release/"$exe_name"; do
        if [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         PerX Hub - Installazione e avvio completo        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Repo (sorgente):  $REPO_BASE"
echo "  Installazione:    $HUB_BASE"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Richiesto root. Esegui: sudo $0${NC}"
    exit 1
fi

if [ ! -d "$REPO_BASE" ]; then
    echo -e "${RED}[ERROR] Cartella repo non trovata: $REPO_BASE${NC}"
    echo "  Crea la cartella e clona/copia dentro PerXHub, perx_email_worker, perx_wa_bridge, perx_autoupdater, scripts."
    exit 1
fi

echo -e "${YELLOW}[1/11] Liberazione porte $PERX_PORTS (arresto servizi esistenti)...${NC}"
# Arresta i daemon PerX così rilasciano le porte
for label in com.perx.hub com.perx.email-worker com.perx.wa-bridge com.perx.autoupdater; do
    launchctl bootout system/$label 2>/dev/null || true
done
# Termina qualsiasi processo in ascolto sulle porte PerX
for port in $PERX_PORTS; do
    pids=$(lsof -i ":$port" -t 2>/dev/null || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
        echo "  ✓ Porta $port liberata"
    fi
done
sleep 2
echo "  ✓ Porte pronte"

echo -e "${YELLOW}[2/11] Creazione directory in $HUB_BASE...${NC}"
mkdir -p "$HUB_BASE"/{bin,logs,data,vault,workers/{email,wa-bridge,autoupdater},repo}
chmod -R 755 "$HUB_BASE"
# Hub Monitor scrive monitor-secrets.json in data/ come utente del gruppo staff
chown root:staff "$HUB_BASE/data" 2>/dev/null || true
chmod 2775 "$HUB_BASE/data" 2>/dev/null || true
echo "  ✓ Directory pronte"

echo -e "${YELLOW}[3/11] Power Management (anti-sleep)...${NC}"
pmset -a sleep 0
pmset -a disksleep 0
pmset -a displaysleep 0
pmset -a womp 1
pmset -a networkoversleep 1
pmset -a powernap 1
pmset -a autopoweroff 0
pmset -a standby 0
pmset -a autorestart 1
echo "  ✓ Sonno disabilitato, Wake on LAN e autorestart attivi"

echo -e "${YELLOW}[4/11] Build PerX Hub (Swift)...${NC}"
if [ -d "$REPO_BASE/PerXHub" ] && command -v swift &>/dev/null; then
    (cd "$REPO_BASE/PerXHub" && swift build -c release 2>/dev/null) || true
fi
if HUB_BIN="$(resolve_swift_release_binary "$REPO_BASE/PerXHub" PerXHub)"; then
    cp "$HUB_BIN" "$HUB_BASE/PerXHub"
    chmod +x "$HUB_BASE/PerXHub"
    # Firma ad-hoc: senza questa riga launchd può rifiutare il binario (OS_REASON_CODESIGNING).
    codesign -s - --force "$HUB_BASE/PerXHub" 2>/dev/null || true
    echo "  ✓ PerXHub installato"
else
    echo "  ⚠ Build non trovata in .build/release/ né .build/*-apple-macosx/release/ per PerXHub"
fi

echo -e "${YELLOW}[5/11] Email Worker (copia + venv + pip)...${NC}"
if [ -d "$REPO_BASE/perx_email_worker" ]; then
    rsync -a --delete "$REPO_BASE/perx_email_worker/" "$HUB_BASE/workers/email/" 2>/dev/null || cp -r "$REPO_BASE/perx_email_worker/"* "$HUB_BASE/workers/email/"
    cd "$HUB_BASE/workers/email"
    python3 -m venv venv 2>/dev/null || true
    ./venv/bin/pip install --upgrade pip -q
    ./venv/bin/pip install -r requirements.txt -q
    echo "  ✓ Email Worker installato"
else
    echo "  ⚠ perx_email_worker non trovato in $REPO_BASE"
fi

echo -e "${YELLOW}[6/11] WA Bridge (copia + npm)...${NC}"
if [ -d "$REPO_BASE/perx_wa_bridge" ]; then
    rsync -a --delete "$REPO_BASE/perx_wa_bridge/" "$HUB_BASE/workers/wa-bridge/" 2>/dev/null || cp -r "$REPO_BASE/perx_wa_bridge/"* "$HUB_BASE/workers/wa-bridge/"
    chmod +x "$HUB_BASE/workers/wa-bridge/run-wa-bridge.sh"
    (cd "$HUB_BASE/workers/wa-bridge" && npm install --production --silent 2>/dev/null) || true
    echo "  ✓ WA Bridge installato"
else
    echo "  ⚠ perx_wa_bridge non trovato in $REPO_BASE"
fi

echo -e "${YELLOW}[7/11] PerX Hub Monitor (build + app in /Applications)...${NC}"
if [ -d "$REPO_BASE/PerXHubMonitor" ] && command -v swift &>/dev/null; then
    (cd "$REPO_BASE/PerXHubMonitor" && swift build -c release 2>/dev/null) || true
    if MONITOR_BIN="$(resolve_swift_release_binary "$REPO_BASE/PerXHubMonitor" PerXHubMonitor)"; then
        mkdir -p /Applications/PerXHubMonitor.app/Contents/MacOS
        mkdir -p /Applications/PerXHubMonitor.app/Contents/Resources
        cp "$MONITOR_BIN" /Applications/PerXHubMonitor.app/Contents/MacOS/PerXHubMonitor
        chmod +x /Applications/PerXHubMonitor.app/Contents/MacOS/PerXHubMonitor
        cat > /Applications/PerXHubMonitor.app/Contents/Info.plist << 'INFOPLIST'
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
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
INFOPLIST
        # Firma ad-hoc: evita il blocco "l'applicazione non è supportata sul Mac"
        codesign -s - --force --deep /Applications/PerXHubMonitor.app 2>/dev/null || true
        echo "  ✓ PerX Hub Monitor installato in /Applications/PerXHubMonitor.app"
    else
        echo "  ⚠ Build Monitor non riuscita"
    fi
else
    echo "  ⚠ PerXHubMonitor non trovato in $REPO_BASE o Swift assente"
fi

echo -e "${YELLOW}[8/11] AutoUpdater (copia + venv + pip)...${NC}"
if [ -d "$REPO_BASE/perx_autoupdater" ]; then
    rsync -a --delete "$REPO_BASE/perx_autoupdater/" "$HUB_BASE/workers/autoupdater/" 2>/dev/null || cp -r "$REPO_BASE/perx_autoupdater/"* "$HUB_BASE/workers/autoupdater/"
    cd "$HUB_BASE/workers/autoupdater"
    python3 -m venv venv 2>/dev/null || true
    ./venv/bin/pip install --upgrade pip -q
    ./venv/bin/pip install -r requirements.txt -q
    echo "  ✓ AutoUpdater installato"
else
    echo "  ⚠ perx_autoupdater non trovato in $REPO_BASE"
fi

echo -e "${YELLOW}[9/11] Mirror repo in $HUB_BASE/repo (opzionale, per riferimenti)...${NC}"
# Copia solo le sottocartelle usate dall'install (non l'intero progetto)
for dir in PerXHub PerXHubMonitor perx_email_worker perx_wa_bridge perx_autoupdater scripts; do
    if [ -d "$REPO_BASE/$dir" ]; then
        mkdir -p "$HUB_BASE/repo/$dir"
        rsync -a --exclude='.build' --exclude='node_modules' --exclude='venv' --exclude='.git' "$REPO_BASE/$dir/" "$HUB_BASE/repo/$dir/" 2>/dev/null || cp -r "$REPO_BASE/$dir/"* "$HUB_BASE/repo/$dir/"
    fi
done
echo "  ✓ Mirror aggiornato"

echo -e "${YELLOW}[10/11] Launch Daemons (plist in $DAEMONS_DIR)...${NC}"
for name in "PerXHub/Resources/com.perx.hub" "perx_email_worker/com.perx.email-worker" "perx_wa_bridge/com.perx.wa-bridge" "perx_autoupdater/com.perx.autoupdater"; do
    src="$REPO_BASE/${name}.plist"
    if [ -f "$src" ]; then
        base=$(basename "$name")
        cp "$src" "$DAEMONS_DIR/$base.plist"
        # AutoUpdater: imposta REPO_BASE nella cartella di lavoro usata da questo script
        if [ "$base" = "com.perx.autoupdater" ]; then
            /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:REPO_BASE \"$REPO_BASE\"" "$DAEMONS_DIR/$base.plist" 2>/dev/null || true
        fi
        chown root:wheel "$DAEMONS_DIR/$base.plist"
        chmod 644 "$DAEMONS_DIR/$base.plist"
        echo "  ✓ $base.plist"
    fi
done

echo -e "${YELLOW}[11/11] Caricamento servizi (launchctl)...${NC}"
for plist in com.perx.hub com.perx.email-worker com.perx.wa-bridge com.perx.autoupdater; do
    launchctl bootout system/$plist 2>/dev/null || true
    launchctl bootstrap system "$DAEMONS_DIR/$plist.plist" 2>/dev/null || true
    if launchctl print system/$plist &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $plist"
    else
        echo -e "  ${RED}✗${NC} $plist"
    fi
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installazione e avvio completati             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Hub:         http://localhost:8080"
echo "  Email:       http://localhost:5001"
echo "  WA Bridge:   http://localhost:5002"
echo "  AutoUpdater: http://localhost:8084"
echo "  Monitor:     /Applications/PerXHubMonitor.app (apri dalla barra dei menu o da Spotlight)"
echo ""
echo "  Per applicare aggiornamenti dopo git pull (o dopo notifica AutoUpdater):"
echo "    cd \"$REPO_BASE\" && sudo ./scripts/install-and-launch.sh"
echo ""
