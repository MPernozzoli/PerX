#!/bin/bash
#
# PerX Hub - Status dei servizi
# Mostra lo stato di tutti i servizi PerX sul Mac Mini
#

# Colori
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                 PerX Hub - Status Report                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Funzione per verificare servizio
check_service() {
    local name=$1
    local label=$2
    local port=$3
    
    # Verifica launchd
    local pid=$(launchctl print system/$label 2>/dev/null | grep "pid" | awk '{print $3}')
    
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        # Verifica HTTP health
        local health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" 2>/dev/null || echo "000")
        
        if [ "$health" == "200" ]; then
            echo -e "  ${GREEN}●${NC} $name (PID: $pid, port $port) - ${GREEN}RUNNING${NC}"
        else
            echo -e "  ${YELLOW}●${NC} $name (PID: $pid, port $port) - ${YELLOW}RUNNING (HTTP: $health)${NC}"
        fi
    else
        echo -e "  ${RED}●${NC} $name (port $port) - ${RED}STOPPED${NC}"
    fi
}

echo -e "${YELLOW}SERVIZI:${NC}"
check_service "PerX Hub" "com.perx.hub" 8080
check_service "Email Worker" "com.perx.email-worker" 5001
check_service "WA Bridge" "com.perx.wa-bridge" 5002
check_service "AutoUpdater" "com.perx.autoupdater" 8084

echo ""
echo -e "${YELLOW}POWER MANAGEMENT:${NC}"
sleep_setting=$(pmset -g | grep "^[ ]*sleep" | head -1 | awk '{print $2}')
if [ "$sleep_setting" == "0" ]; then
    echo -e "  ${GREEN}●${NC} Sleep disabilitato"
else
    echo -e "  ${RED}●${NC} Sleep abilitato (valore: $sleep_setting)"
fi

womp_setting=$(pmset -g | grep "womp" | awk '{print $2}')
if [ "$womp_setting" == "1" ]; then
    echo -e "  ${GREEN}●${NC} Wake on LAN abilitato"
else
    echo -e "  ${YELLOW}●${NC} Wake on LAN disabilitato"
fi

echo ""
echo -e "${YELLOW}UTILIZZO RISORSE:${NC}"
# CPU e Memoria per processi PerX
ps aux | grep -E "PerXHub|email-worker|wa-bridge|autoupdater" | grep -v grep | while read line; do
    user=$(echo $line | awk '{print $1}')
    pid=$(echo $line | awk '{print $2}')
    cpu=$(echo $line | awk '{print $3}')
    mem=$(echo $line | awk '{print $4}')
    cmd=$(echo $line | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-40)
    echo "  PID $pid: CPU ${cpu}% MEM ${mem}% - $cmd"
done

echo ""
echo -e "${YELLOW}SPAZIO DISCO:${NC}"
vault_size=$(du -sh /opt/perx-hub/vault 2>/dev/null | awk '{print $1}' || echo "N/A")
logs_size=$(du -sh /opt/perx-hub/logs 2>/dev/null | awk '{print $1}' || echo "N/A")
data_size=$(du -sh /opt/perx-hub/data 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "  Vault: $vault_size"
echo "  Logs:  $logs_size"
echo "  Data:  $data_size"

echo ""
echo -e "${YELLOW}UPTIME SISTEMA:${NC}"
uptime

echo ""
