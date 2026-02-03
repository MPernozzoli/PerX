# PerX Hub

Mac Mini Hub - Single Source of Truth per PerX.

## Architettura

PerXHub è un daemon Swift che espone API HTTP REST per:
- **Vault**: Storage centralizzato file sinistri
- **Jobs**: Job queue per Windows Agent (import/export)
- **Health**: Monitoring e status

## Requisiti

- macOS 14.0+
- Swift 5.9+
- Vapor 4.x

## Sviluppo

### Build

```bash
swift build
```

### Run in development

```bash
./scripts/run-dev.sh
```

Questo crea una directory `~/perx-hub-dev` con la struttura del vault.

### Test API

```bash
# Health check
curl http://localhost:8080/health

# Lista file sinistro
curl http://localhost:8080/vault/sinistri/2024-001/files

# Job pendenti
curl http://localhost:8080/jobs/pending
```

## Deploy

### Installazione come LaunchDaemon

```bash
sudo ./scripts/deploy.sh
```

Questo:
1. Builda il release
2. Copia l'executable in `/opt/perx-hub/`
3. Installa il LaunchDaemon
4. Avvia il servizio

### Struttura directory

```
/opt/perx-hub/
├── PerXHub              # Executable
├── data/
│   └── vault.sqlite     # Database SQLite
├── vault/
│   └── sinistri/
│       └── {riferimento}/
│           ├── da_mail/
│           ├── da_whatsapp/
│           ├── documenti/
│           ├── perizia/
│           ├── atti/
│           ├── gestione/
│           └── _export/
└── logs/
    ├── hub.log
    └── hub-error.log
```

### Gestione daemon

```bash
# Stop
sudo launchctl unload /Library/LaunchDaemons/com.perx.hub.plist

# Start
sudo launchctl load /Library/LaunchDaemons/com.perx.hub.plist

# Logs
tail -f /opt/perx-hub/logs/hub.log
```

## API Endpoints

### Health

- `GET /health` - Status e uptime

### Vault

- `GET /vault/sinistri/:ref/files` - Lista file sinistro
- `GET /vault/sinistri/:ref/status` - Stato cartella sinistro
- `POST /vault/sinistri/:ref` - Crea cartella sinistro
- `GET /vault/files/:id/download` - Download file
- `POST /vault/sinistri/:ref/upload` - Upload file (JSON con base64)
- `DELETE /vault/files/:id` - Elimina file
- `POST /vault/files/:id/export` - Sposta in _export

### Jobs

- `GET /jobs/pending` - Lista job pendenti
- `GET /jobs/:id` - Dettaglio job
- `POST /jobs/:id/start` - Marca in progress
- `POST /jobs/:id/complete` - Marca completato
- `POST /jobs/:id/fail` - Marca fallito
- `POST /jobs/import/folder` - Crea job import cartella
- `POST /jobs/export/file` - Crea job export file
- `POST /jobs/scan/legacy` - Crea job scan legacy
- `POST /jobs/:id/upload` - Upload file da job

## Configurazione

Variabili d'ambiente:

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| PERX_ENV | development | Ambiente (development/production) |
| PERX_HUB_PATH | /opt/perx-hub | Path base |
| PERX_HUB_HOST | 0.0.0.0 | Host binding |
| PERX_HUB_PORT | 8080 | Porta HTTP |

---

## Convenzione ID Utente Univoco

L'Hub utilizza un **ID utente univoco** (`user_id`) per identificare gli utenti in tutti i servizi: Email, WhatsApp e File Sync.

### Formato

```
user_id = local-part dell'email
```

**Esempio:** per `massimo.pernozzoli@dominio.it` → `user_id = massimo.pernozzoli`

### Utilizzo nei servizi

| Servizio | Campo | Esempio |
|----------|-------|---------|
| **Email** | `account_id` | `massimo.pernozzoli` |
| **File Sync (perx_sync_agent)** | `user_id` | `massimo.pernozzoli` |
| **Heartbeat** | `user_id` | `massimo.pernozzoli` |

### Implementazione

- **Client PerX**: usa `currentUserId()` = local-part dell'email autenticata
- **Email Worker**: configura `user_id` = local-part in `accounts.json`
- **Sync Agent**: riceve `user_id` in ogni richiesta API

### Heartbeat e Monitoraggio

I client inviano heartbeat periodici (ogni 60s) con il proprio `user_id`:

```bash
POST /heartbeat
Content-Type: application/json

{ "user_id": "massimo.pernozzoli" }
```

L'Hub traccia gli utenti connessi e li espone in `/stats`:

```bash
GET /stats
→ { ..., "connectedUsers": 3 }
```

