---
tags: [perx, infrastruttura, deploy]
updated: 2026-11-26
---

# Infrastruttura e deploy

## Continuous integration (GitHub Actions)

Dal 2026-11-07 la root contiene tre workflow con path filtering e cancellazione delle esecuzioni
superseded:

- `backend-ci.yml`: Python 3.11, Postgres 16 isolato, installazione da `requirements-dev.txt`,
  applicazione completa delle migration Alembic su DB vuoto, pytest con coverage XML; Ruff misura
  ancora una baseline non bloccante. **Verifica 2026-11-26: il workflow non è mai passato (6 run
  su 6 falliti su GitHub)** — `alembic upgrade head` su DB vuoto si interrompe perché la catena di
  migration non crea 22 tabelle core (es. `documents`, `emails`, `attachments`, `audit_log`,
  `case_tasks`, `internal_chat_*`) che i modelli usano e che il DB production ha ottenuto fuori da
  Alembic. Vedi [[06-Decisioni-e-Intenzioni-Future]] (2026-11-26, audit). **Corretto lo stesso
  giorno (PR #5)**: la revisione `002b_legacy_core_tables`, inserita tra `002` e `003`, ricrea in
  modo idempotente le 22 tabelle e 72 colonne legacy di `claims`/`users`, e `024` aggiunge
  `wa_messages` alla publication `supabase_realtime` solo se esiste. `upgrade head` su Postgres 16
  vuoto è verificato fino a `040`;
- `web-ci.yml`: Node 22/npm cache; typecheck, test Vitest, lint e build production sono gate
  bloccanti per tutti e cinque i workspace. Le app prive di test accettano ancora temporaneamente
  una suite vuota, mentre `portal-web` e `catdispatcher` contengono i primi 7 test reali;
- `apple-ci.yml`: test `PerXCore`, build `PerXHub` e build unsigned completa del target Xcode
  `PerX` sono gate bloccanti su runner macOS. I duplicati videoperizia sono stati esclusi dalla
  membership del target principale, mantenendo come sorgente canonica `Shared/Videoperizia/`.

I workflow scattano su pull request, push a `main` e manualmente. La branch protection e il
collegamento dei check al deploy di produzione vanno attivati dopo il primo run GitHub verde;
Render e Vercel continuano nel frattempo a gestire il deploy con i meccanismi esistenti.
Comandi equivalenti per l'esecuzione locale sono nel `README.md` root e in `backend/README.md`.

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

Vincoli di configurazione introdotti il 2026-11-26 (dettagli → [[Backend-Cloud-API]], sezione
"Sicurezza applicativa"): con `ENV=prod` il servizio **non si avvia** se `SECRET_KEY` su Render è
un placeholder o ha meno di 32 caratteri (Render mantiene in esercizio il deploy precedente); i flag
`DEBUG`, `PORTAL_DEBUG_PREVIEW_LINKS` e `PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH` vengono forzati a
`False` anche se impostati in dashboard; `/docs` e `/openapi.json` sono spenti salvo
`API_DOCS_ENABLED=True`; il webhook comunicazioni richiede `COMMUNICATIONS_WEBHOOK_SECRET`.
Il backend Render raggiunge l'Hub del Mac mini per lo storage del vault
(`VAULT_STORAGE_PROVIDER=mac_mini`, `MAC_MINI_STORAGE_URL`, `MAC_MINI_STORAGE_TOKEN`): il token
deve coincidere con `PERX_STORAGE_SHARED_SECRET` configurato sull'Hub (vedi [[PerXHub]]).

**Storage S3 del vault: predisposto, NON attivo.** Variabili opzionali (nessuna da impostare oggi
su Render): `VAULT_S3_BUCKET`, `VAULT_S3_REGION` (`eu-south-1`), `VAULT_S3_ENDPOINT_URL`,
`VAULT_S3_PREFIX`, `VAULT_S3_FORCE_PATH_STYLE`, `VAULT_S3_PRESIGNED_URL_TTL_SECONDS`,
`VAULT_S3_PRESIGNED_DOWNLOADS` (default `False`); credenziali via `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` (o IAM role) come secret Render, mai nel repo. Passaggio futuro, in
ordine: creare bucket e utente IAM a privilegi minimi → eseguire
`scripts/migrate_vault_to_s3.py` in dry-run, poi `--execute`, e rieseguirlo subito prima dello
switch → impostare le variabili `VAULT_S3_*` e portare `VAULT_STORAGE_PROVIDER=s3` → verificare
upload/download dalle app → lasciare il Mac mini in sola lettura per un periodo di sicurezza.
Nota: i `Document` esistenti conservano `storage_provider=mac_mini`; l'adattatore legge per
`storage_path`, non per provider, quindi dopo la migrazione dei file i download funzionano senza
riscrivere il DB. Simulazione locale: `backend/docker-compose.storage.yml` (moto server, API S3 in memoria).

In locale: `alembic upgrade head` → `python scripts/bootstrap_single_tenant.py` →
`uvicorn app.main:app --reload`. Dettagli → [[Backend-Cloud-API]].

Drift rilevato il 2026-11-25: il database production era marcato Alembic a
`037_videoperizia_disconnect` ma non conteneva `domain_routes`, pur essendo questa prevista da
`013_domain_routing`. `014_domain_routing_apps` è stato reso tollerante alla tabella assente e
`040_pynkstudio_domains` la ricrea con schema/indici/constraint completi prima di inserire gli
alias PynkStudio. Anche `039_bignami_policy_type_condominio` è idempotente quando lo schema
satellite opzionale `bignami` non è installato nel database PerX. Non usare `alembic stamp` per
aggirare questo drift.

Upgrade production completato manualmente il 2026-11-25: `alembic_version` è a
`040_pynkstudio_domains`, `platform_error_log` e `domain_routes` esistono, i tre alias prodotto
sono attivi e `/health` risponde HTTP 200. Il gateway Vercel usa ancora il fallback locale per
questi host perché `ROUTING_API_URL`/`ROUTING_RESOLVE_SECRET` non sono valorizzati in modo
coordinato tra Vercel e Render; l'allineamento del secret server-to-server resta un'attività di
configurazione dashboard, non un valore da inserire nel repository.

## Web app (Vercel)

**Regola architetturale**: tutti i portali web devono essere Next.js App Router. Non si
introducono nuove SPA Vite o runtime incompatibili col gateway Next.js (vedi anche
[[06-Decisioni-e-Intenzioni-Future]]).

### Migrazione domini PynkStudio

Dal 2026-11-25 i prodotti proprietari espongono anche ingressi sotto `pynkstudio.eu`:
`perx.pynkstudio.eu`, `catdispatcher.pynkstudio.eu` e `bignamionline.pynkstudio.eu`. La decisione
del 2026-11-26 mantiene però `catdispatcher.perx.it` e `bignami.perx.it` come domini principali;
gli equivalenti `pynkstudio.eu` sono alias secondari. Per compatibilità con il pannello DNS Register.it, i servizi PerX
usano nomi piatti (`app-perx.pynkstudio.eu`, `api-perx.pynkstudio.eu`,
`login-perx.pynkstudio.eu`). `admin.pynkstudio.eu` rimane il pannello unico cross-product e
dialoga con i backend esclusivamente tramite API server-to-server.

I domini tenant e i loro prefissi (`admin`, `assicurati`, `riunioni`, ecc.) non vengono migrati
sotto PynkStudio. I domini storici restano alias/redirect fino alla verifica di tutti i consumer.

**Stato operativo 2026-11-26:** il codice dual-host e i deploy origin dei tre portali sono pronti;
i cinque host web previsti sono associati al progetto Vercel `perx` e il DNS è propagato:

| Host | Record richiesto | Stato |
|---|---|---|
| `perx.pynkstudio.eu` | `A 76.76.21.21` | attivo su Vercel, landing PerX |
| `app-perx.pynkstudio.eu` | `A 76.76.21.21` | attivo; fallback temporaneo alla landing PerX |
| `catdispatcher.perx.it` | CNAME Vercel indicato dal progetto | dominio principale CAT Dispatcher |
| `catdispatcher.pynkstudio.eu` | `A 76.76.21.21` | alias secondario CAT Dispatcher |
| `bignami.perx.it` | CNAME Vercel indicato dal progetto | dominio principale Bignami Online |
| `bignamionline.pynkstudio.eu` | `A 76.76.21.21` | alias secondario Bignami Online |
| `login-perx.pynkstudio.eu` | `A 76.76.21.21` | attivo; fallback temporaneo alla landing PerX finché manca SSO |
| `perx.it` | sostituire l'A attuale con `76.76.21.21` | DNS/certificato non validi |

Gli origin Vercel production sono `perx-insight-studio.vercel.app`,
`catdispatcher.vercel.app` e `bignami-online.vercel.app`; non sono gli URL canonici da mostrare
agli utenti. `catdispatcher.it` non risolve al 2026-11-25. Dettagli →
[[06-Decisioni-e-Intenzioni-Future]] (2026-11-25).

Correzione runtime del 2026-11-26: l'origin Insight Studio restituiva HTML 200 ma il bundle
browser andava in crash con `supabaseUrl is required` perché il progetto origin non aveva le env
pubbliche Supabase. Il client Supabase è ora opzionale: la landing resta renderizzabile senza
configurazione, mentre modulo contatti e disiscrizione mostrano un errore controllato finché
`NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` non vengono configurate.

Diagnosi runtime CatDispatcher/Bignami del 2026-11-26: anche questi origin restituivano HTML 200
ma mostravano `This page couldn't load`. Le env Vercel esistevano con valore vuoto: CatDispatcher
falliva con `supabaseUrl is required`, Bignami con `Missing NEXT_PUBLIC_SUPABASE_URL or
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Gli origin richiedono un nuovo deploy dopo aver impostato
le env pubbliche Supabase; CatDispatcher richiede inoltre
`NEXT_PUBLIC_PERX_API_BASE_URL=https://api.perx.it/api/v1` e Bignami
`NEXT_PUBLIC_SUPABASE_DB_SCHEMA=bignami` più `NEXT_PUBLIC_SITE_URL=https://bignami.perx.it`.

L'ingresso pubblico web gira sul progetto gateway Vercel **`perx`**
(`prj_4GoA9R3qLkHjnu7DgmBmcS7KmlR3`, team `team_Y4HXMUA0RyX5rQO1GZNOmmSc`); le app non ancora
integrate nello stesso runtime usano progetti origin tecnici dietro al gateway:

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
- Dal 2026-11-25 il gateway inoltra le app prodotto verso tre progetti origin dedicati, configurati
  tramite `INSIGHT_STUDIO_ORIGIN`, `CATDISPATCHER_ORIGIN` e `BIGNAMI_ORIGIN` server-side. Questi
  progetti sono unità tecniche di deploy, non nuovi ingressi pubblici o nuovi control plane.
- Il portale `admin.pynkstudio.eu` è sul progetto Vercel **`menuary`** del repo BePork, separato
  dal gateway PerX e integrato via API server-to-server.

### Vincolo del gateway singolo

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

- **Postgres primario**: raggiunto solo dal backend (vedi [[02-Architettura]]). Lo schema `public`
  è però esposto dalla Data API di Supabase: **ogni tabella creata da una migrazione Alembic deve
  abilitare RLS** (`ALTER TABLE … ENABLE ROW LEVEL SECURITY`), altrimenti la chiave anon la
  espone. Le migrazioni `041_enable_rls_public` e `042_enable_rls_remaining` l'applicano a tutte
  le tabelle esistenti che ne sono prive (vedi [[06-Decisioni-e-Intenzioni-Future]], voci
  2026-11-26 «RLS sulle tabelle `public`»).
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
Ultimo aggiornamento: 2026-11-26 (provider S3 predisposto; migrazioni ricostruibili da zero)
