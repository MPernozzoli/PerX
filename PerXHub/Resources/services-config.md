# PerX Hub - Configurazione Servizi

## Porte Standard

| Servizio        | Porta | Protocollo | Posizione       | URL Tailscale                                |
|-----------------|-------|------------|-----------------|---------------------------------------------|
| PerX Hub        | 8080  | HTTPS      | Mac Mini        | https://mac-mini-di-massimo.tailca58be.ts.net |
| Email Worker    | 5001  | HTTP       | Mac Mini        | (locale)                                    |
| WA Bridge       | 5002  | HTTP       | Mac Mini        | (locale)                                    |
| AutoUpdater     | 8084  | HTTP       | Mac Mini        | (locale)                                    |

## Struttura Directory (/opt/perx-hub)

```
/opt/perx-hub/
├── PerXHub                    # Eseguibile principale
├── data/
│   ├── vault.sqlite           # Database SQLite
│   └── monitor-secrets.json   # Opzionale: Supabase + storage token (scritto da Hub Monitor; ha priorità sul plist)
├── logs/
│   ├── hub.log
│   ├── hub-error.log
│   ├── email-worker.log
│   ├── email-worker-error.log
│   ├── wa-bridge.log
│   ├── wa-bridge-error.log
│   ├── autoupdater.log
│   └── autoupdater-error.log
├── vault/                     # File sinistri
│   └── {riferimento}/
├── workers/
│   ├── email/                 # perx_email_worker
│   ├── wa-bridge/             # perx_wa_bridge
│   └── autoupdater/           # perx_autoupdater
└── repo/                      # Repository sorgente (per AutoUpdater)
```

## Variabili d'Ambiente Hub

```bash
PERX_ENV=production
PERX_HUB_PATH=/opt/perx-hub
PERX_HUB_HOST=0.0.0.0
PERX_HUB_PORT=8080
PERX_EMAIL_WORKER_URL=http://localhost:5001
PERX_WA_BRIDGE_URL=http://localhost:5002
PERX_AUTO_UPDATER_URL=http://localhost:8084
PERX_REPO_PATH=/opt/perx-hub/repo
SUPABASE_URL=https://wqcqiaojdflbmqyamndt.supabase.co
SUPABASE_SERVICE_ROLE_KEY=replace-with-service-role-key
```

Il daemon (`com.perx.hub`) **non legge** file `.env`: le variabili devono essere in `Resources/com.perx.hub.plist` (o export manuali). Usa sempre la chiave **service_role**, non la **anon**.

## Supabase

- Il database applicativo principale deve risiedere su Supabase/Postgres.
- L'Hub usa Supabase come nodo server-side, non come client anonimo.
- I file binari restano nel vault dell'Hub; su Supabase vanno metadata e stati di elaborazione.

## Installazione Servizi

### 1. Hub
```bash
cd PerXHub
swift build -c release
sudo cp .build/release/PerXHub /opt/perx-hub/
sudo cp Resources/com.perx.hub.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.perx.hub.plist
```

### 2. Email Worker
```bash
cd perx_email_worker
pip3 install -r requirements.txt
sudo cp -r . /opt/perx-hub/workers/email/
cp com.perx.email-worker.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.perx.email-worker.plist
```

### 3. WA Bridge
```bash
cd perx_wa_bridge
npm install
sudo cp -r . /opt/perx-hub/workers/wa-bridge/
cp com.perx.wa-bridge.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.perx.wa-bridge.plist
```

### 4. AutoUpdater
```bash
cd perx_autoupdater
pip3 install -r requirements.txt
sudo cp -r . /opt/perx-hub/workers/autoupdater/
cp com.perx.autoupdater.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.perx.autoupdater.plist
```

## Comandi Utili

```bash
# Stato servizi
launchctl list | grep perx

# Log in tempo reale
tail -f /opt/perx-hub/logs/hub.log

# Riavvio servizio
launchctl kickstart -k gui/$(id -u)/com.perx.hub

# Health check
curl http://localhost:8080/health
curl http://localhost:5001/health
curl http://localhost:5002/health
curl http://localhost:8084/health
```
