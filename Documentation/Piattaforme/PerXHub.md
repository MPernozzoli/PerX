---
tags: [perx, piattaforma, hub, mac-mini]
updated: 2026-11-27
---

# PerXHub

Daemon Swift/Vapor 4.x che gira su un **Mac mini** (macOS 14.0+), storicamente pensato come
"Single Source of Truth" documentale per PerX. ~31 file Swift propri (il resto della cartella
`.build/` sono dipendenze SPM vendored).

## Architettura direzionale

- **Supabase/Postgres è il source of truth dei dati applicativi** (via backend, vedi
  [[02-Architettura]]).
- **PerXHub resta il nodo operativo** per: vault documentale su filesystem, job
  import/export/scan verso percorsi legacy, AI locale, bridge WhatsApp.
- Le credenziali Supabase dell'Hub (service role) restano solo lato server e non vengono mai
  condivise con i client.

## Responsabilità esposte via HTTP REST

- **Vault**: storage centralizzato dei file sinistro (`/vault/sinistri/:ref/...`), struttura
  cartelle per sinistro: `da_mail/`, `da_whatsapp/`, `documenti/`, `perizia/`, `atti/`,
  `gestione/`, `_export/`.
- **Jobs**: coda per import/export/scan (`/jobs/...`), con stati pending → in progress →
  completed/failed.
- **Health**: `/health` per uptime/monitoring; `/stats` include `connectedUsers`.

## Ruoli effettivi (inventario del 2026-11-26)

Le app non chiamano più l'Hub direttamente: passano dal backend cloud (`/api/v1/hub/*`). Sul Mac
mini restano attivi:

1. **Storage dei file del vault**: il backend, con `VAULT_STORAGE_PROVIDER=mac_mini`, legge e
   scrive i byte tramite `/internal/storage/*`; i metadati sono su Postgres. È l'unico uso
   dell'Hub da parte del backend (`VaultStorageService`, chiamato solo da
   `routes_hub_compat.py`). Con il default `local` i file finirebbero invece in
   `/tmp/perx-hub-compat` sul disco effimero di Render.
2. **WhatsApp**: `workers/wa_bridge` (client non ufficiale basato su WhatsApp Web) più
   `WAOutboxPoller`, che invia i `wa_messages` in stato `pending` letti da Supabase.
3. **AI locale**: Ollama e `workers/mlx_vision_bridge.py` (solo Apple Silicon). Il worker che
   consuma la coda backend `process_jobs` non è presente in questo repository.
4. **Strumenti di contorno**: job di import/export da cartelle legacy, planner assegnazioni,
   heartbeat/statistiche, `perx_autoupdater` (strumento di sviluppo che osserva il repo locale).

Codice non referenziato da nessun'altra parte dell'Hub (candidato alla rimozione):
`HubAutoCheckService`, `ClosureOrchestrator`, `StatoManager`, `EmailReconciliationService`,
`AICategorizationService`, `WhatsAppService` (circa 2.200 righe). Piano di dismissione del Mac
mini → [[06-Decisioni-e-Intenzioni-Future]] (2026-11-26).

## Controllo accessi (dal 2026-11-26)

Introdotto con l'hardening seguito all'audit del 2026-11-26 (vedi
[[06-Decisioni-e-Intenzioni-Future]]): `Server/HubAccessMiddleware.swift` applica una regola
globale a tutte le route:

- `GET /health` resta pubblico (health check di Monitor, AutoUpdater, launchd);
- `/internal/storage/*` mantiene il controllo `X-PerX-Storage-Token` (usato dal backend cloud
  con `MAC_MINI_STORAGE_TOKEN`), ora con confronto a tempo costante;
- le richieste **dirette da loopback** (`127.0.0.1`/`::1`) senza header di proxy sono ammesse,
  così WA Bridge, AutoUpdater e Monitor sullo stesso Mac continuano a funzionare senza
  configurazione;
- ogni altra richiesta (LAN, VPN, tunnel o reverse proxy, riconosciuti dagli header di
  forwarding) deve presentare `PERX_HUB_API_TOKEN` in `X-PerX-Hub-Token` o
  `Authorization: Bearer`, oppure il token del bridge (`WA_BRIDGE_INTERNAL_TOKEN`) in
  `X-PerX-WA-Bridge-Token`; altrimenti HTTP 401.

Segreti: i valori reali non sono più nel plist versionato (`Resources/com.perx.hub.plist`
contiene solo placeholder `REPLACE-WITH-*`, che l'Hub ignora). Si impostano dal Monitor in
`data/monitor-secrets.json` (priorità sull'env; il Monitor preserva `hubAPIToken` quando salva)
o nel plist installato in `/Library/LaunchDaemons`. Attenzione: `scripts/deploy.sh` copia il plist
del repo sopra quello installato, quindi i segreti vanno tenuti in `monitor-secrets.json`.
L'host di bind predefinito in assenza di `PERX_HUB_HOST` è ora `127.0.0.1`; il plist di deploy
continua a impostare `0.0.0.0`, protetto dal middleware. Il daemon gira ancora come `root`:
ridurne i privilegi resta un passo successivo.

## Convenzione ID utente

`user_id = local-part dell'email` (es. `massimo.pernozzoli@dominio.it` → `massimo.pernozzoli`),
usato in modo coerente da client PerX ed Email Worker. Il daemon storico contava gli utenti
connessi tramite `POST /heartbeat` ogni 60s. Dal 2026-11-27 l’app Mac non invia più quel
heartbeat: l’endpoint compat sul backend (`POST /api/v1/hub/heartbeat`) risponde senza
salvare la presenza. Lo stato online dell’Hub per l’app è il solo `GET /health` di
`HubConfigService`, ogni 5 minuti.

## Deploy

Installato come **LaunchDaemon** (`sudo ./scripts/deploy.sh`): build release → copia in
`/opt/perx-hub/` → installazione plist → avvio. Gestione via `launchctl load/unload
com.perx.hub.plist`; log in `/opt/perx-hub/logs/`.

## Build e CI

Dal 2026-11-07 `apple-ci.yml` compila `PerXHub` su runner macOS a ogni modifica pertinente. La
baseline è verde ma segnala warning che diventeranno errori in Swift 6 (API Vapor sincrone usate
da contesto async e un tipo `Status` non `Sendable`); sono debito noto da correggere prima del
passaggio del package alla language mode Swift 6. Un test target Hub dedicato resta da aggiungere.

## Componenti satellite

- **`PerXHubMonitor/`** (~4 file Swift): tool di monitoraggio/diagnostica per lo stato dell'hub,
  delle code di sync e dei job di integrazione.
- **`PerXLocalAgentService/`** e **`PerXLocalAgentShared/`** (~3 file ciascuno): implementazione e
  contratti condivisi del servizio locale usato per Ollama/dipendenze locali — questi sono
  concettualmente parte della funzionalità AI locale dell'app principale, non dell'Hub stesso.
  Dettaglio → [[AI-Locale-e-Cloud]].

---
Ultimo aggiornamento: 2026-11-27 (controllo accessi Hub, segreti fuori dal plist)
