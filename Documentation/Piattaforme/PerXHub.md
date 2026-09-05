---
tags: [perx, piattaforma, hub, mac-mini]
updated: 2026-09-05
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

## Convenzione ID utente

`user_id = local-part dell'email` (es. `massimo.pernozzoli@dominio.it` → `massimo.pernozzoli`),
usato in modo coerente da client PerX, Email Worker e heartbeat (`POST /heartbeat` ogni 60s per
tracciare gli utenti connessi).

## Deploy

Installato come **LaunchDaemon** (`sudo ./scripts/deploy.sh`): build release → copia in
`/opt/perx-hub/` → installazione plist → avvio. Gestione via `launchctl load/unload
com.perx.hub.plist`; log in `/opt/perx-hub/logs/`.

## Componenti satellite

- **`PerXHubMonitor/`** (~4 file Swift): tool di monitoraggio/diagnostica per lo stato dell'hub,
  delle code di sync e dei job di integrazione.
- **`PerXLocalAgentService/`** e **`PerXLocalAgentShared/`** (~3 file ciascuno): implementazione e
  contratti condivisi del servizio locale usato per Ollama/dipendenze locali — questi sono
  concettualmente parte della funzionalità AI locale dell'app principale, non dell'Hub stesso.
  Dettaglio → [[AI-Locale-e-Cloud]].

---
Ultimo aggiornamento: 2026-09-05
