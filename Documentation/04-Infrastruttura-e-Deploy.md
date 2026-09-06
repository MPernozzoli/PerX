---
tags: [perx, infrastruttura, deploy]
updated: 2026-09-05
---

# Infrastruttura e deploy

## Backend (Render)

Il backend FastAPI viene distribuito come immagine Docker su **Render** (`render.yaml`, root
`backend`, `Dockerfile`), servizio `perx-api`, health check su `/health`. Variabili sensibili
(`DATABASE_URL`, `SECRET_KEY`, credenziali Supabase) sono impostate come secret su Render, non nel
repo. `SINGLE_TENANT_MODE` è configurabile per ambiente (in produzione è `False`, vedi
[[Backend-Cloud-API]]).

`PLATFORM_ADMIN_API_KEY` (nuova, 2026-09-06): chiave server-to-server per il bridge platform-admin
usato dal portale PerX su `admin.pynkstudio.eu` (repo BePork). Va impostata su Render (dashboard,
non tracciata in `render.yaml`) e, con lo stesso valore, come `PERX_ADMIN_API_KEY` **server-only**
(non `NEXT_PUBLIC_`) sul progetto Vercel di BePork. Se assente/vuota il bridge è disabilitato e
`/api/v1/admin/*` resta accessibile solo via JWT platform-admin umano. Dettagli →
[[06-Decisioni-e-Intenzioni-Future]] e, lato BePork, `docs/perx-integration.md`.

In locale: `alembic upgrade head` → `python scripts/bootstrap_single_tenant.py` →
`uvicorn app.main:app --reload`. Dettagli → [[Backend-Cloud-API]].

## Web app (Vercel)

**Regola architetturale**: tutti i portali web devono essere Next.js App Router. Non si
introducono nuove SPA Vite o runtime incompatibili col gateway Next.js (vedi anche
[[06-Decisioni-e-Intenzioni-Future]]).

Il deploy web gira su un **unico progetto Vercel**, nome progetto **`perx`**
(`prj_4GoA9R3qLkHjnu7DgmBmcS7KmlR3`, team `team_Y4HXMUA0RyX5rQO1GZNOmmSc`):

- `rootDirectory: null` → la Root Directory è la **root del repo**, non una singola app. Di
  conseguenza eventuali `vercel.json` dentro `apps/<app>/` **non vengono letti**: la config va
  messa in `vercel.json` nella root del repo.
- `buildCommand` di progetto: `turbo run build` (a livello Vercel dashboard) — nel repo
  `vercel.json` root usa `buildCommand: "npm run build:vercel"` (script
  `scripts/vercel-build.mjs`) e `outputDirectory: "apps/portal-web/.next"`.
- `installCommand: "npm install"` (vedi gotcha sotto).
- Il progetto pubblico principale riceve i domini che richiedono routing applicativo:
  `admin.perx.it`, `admin.<tenant_domain>`, `assicurati.<tenant_domain>`,
  `riunioni.<tenant_domain>`, `catdispatcher.it`, `www.catdispatcher.it`. Il gateway
  (`apps/portal-web`) legge l'host, interroga il resolver backend e seleziona il portale corretto
  (prefissi riservati: `admin.`, `assicurati.`, `riunioni.`).
- Esiste un secondo progetto Vercel, **`be-pork`**, presumibilmente legato al backend (da
  verificare/documentare meglio se torna rilevante).

### Vincolo del progetto singolo

Convertire una cartella `apps/*` a Next.js **non** la rende automaticamente pubblicabile come
progetto Vercel indipendente all'interno dello stesso progetto: un progetto Vercel ha una sola
Root Directory e una sola build. Per essere servita dal solo progetto `apps/portal-web`, un'app
deve essere integrata nel runtime del gateway (route/modulo/package condiviso). Le cartelle
`apps/*` ancora autonome (CatDispatcher, Bignami, Insight Studio, Randa) sono unità di migrazione
temporanee e possono avere un proprio progetto Vercel tecnico finché l'integrazione nel gateway
non è completa.

### Gotcha noto: crash `idealTree` su Vercel (risolto)

Il 2026-06-04 il build su Vercel falliva con `npm error Tracker "idealTree" already exists` in
~0,6s, prima ancora di risolvere le dipendenze. Causa: un override `installCommand: "npm install
--prefix=../.."` impostato dalla dashboard Vercel, che combinato con npm workspaces innesca un bug
di Arborist in npm 10.x. Tentativi precedenti (spostare il lockfile, rimuovere riferimenti
`@perx/*`, usare `npm ci`, mettere `vercel.json` dentro la singola app) non avevano funzionato
perché non toccavano il flag `--prefix` o stavano nel path sbagliato (i `vercel.json` per-app non
vengono letti, vedi sopra).

**Fix** (commit `32a8c61`): `vercel.json` nella root del repo con `"installCommand": "npm
install"`. Il vercel.json di root viene letto e prevale sull'override dashboard; da root del
workspace `npm install` installa tutto senza `--prefix`.

Nota collegata: in un monorepo npm workspaces deve esistere **un solo** `package-lock.json` (alla
root); eventuali lockfile annidati in `apps/*` vanno rimossi e ignorati via `.gitignore`.

## Supabase

Progetto Supabase condiviso da backend e app satellite:

- **Postgres primario**: raggiunto solo dal backend (vedi [[02-Architettura]]).
- **Storage**: bucket `perx-portal-uploads` per i file del portale assicurati.
- **Edge functions** (`supabase/functions/`): `find-policy`, `ai-extract-policy`,
  `resend-inbound`, `process-excel-import`.
- **Schemi dedicati per app satellite**: es. Bignami Online usa lo schema Postgres `bignami`
  (deve essere esposto nella Data API e avere grant/RLS applicati dalle migrazioni PerX), Insight
  Studio ha proprie `supabase/migrations` in `apps/perx-insight-studio/supabase/`.

## Email

Provider **Resend** per invio/ricezione email dal backend (`RESEND_API_KEY`,
`RESEND_DEFAULT_FROM_EMAIL`, `RESEND_SCHEDULED_EMAILS_ENABLED`), con pipeline di inbound routing
(vedi `backend/docs/resend_supabase_inbound_pipeline.md` per il dettaglio tecnico non ancora
migrato in questo vault).

## Job locali / Mac mini

Il backend accoda lavori pesanti o legati a risorse locali (es. analisi AI con modello MLX) nella
tabella `process_jobs`; un worker sul Mac mini fa polling/lease con header
`X-PerX-Worker-Secret` (`LOCAL_AI_WORKER_SHARED_SECRET`) su
`GET /api/v1/process-jobs/jobs/claim`. Vedi [[Backend-Cloud-API]] e [[AI-Locale-e-Cloud]].

---
Ultimo aggiornamento: 2026-09-06
