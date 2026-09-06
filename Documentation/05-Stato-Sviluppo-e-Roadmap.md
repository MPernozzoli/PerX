---
tags: [perx, stato, roadmap]
updated: 2026-09-06
---

# Stato di sviluppo e roadmap

> Nota per chi aggiorna questa pagina: quando un elemento passa da "da fare" a "in corso" o da "in
> corso" a "implementato", spostalo di sezione invece di lasciarlo duplicato. Aggiungi la data
> quando è rilevante. Vedi anche l'obbligo di aggiornamento in [[Istruzioni-AI-Agenti]].

## In sintesi

PerX è in **sviluppo attivo** e in uso interno controllato. Storia git: primo commit
2024-11-13, poi ripresa e forte accelerazione da inizio 2026 (circa 100 commit su `main` al
2026-06, con punte di attività a giugno 2026 concentrate su portale assicurati, videoperizia,
comunicazioni e CAT dispatcher). La struttura della repo può ancora essere riorganizzata.

## Per componente

| Componente | Stato |
| --- | --- |
| [[PerX-App-Principale]] | Uso interno attivo, sviluppo continuo (modulo più grande della repo, ~505 file Swift) |
| [[Varianti-iOS]] | Attive, subset di funzionalità rispetto all'app principale |
| [[PerXHub]] | Operativo su Mac mini, direzione verso Supabase come source of truth dei dati (Hub resta nodo vault/AI locale) |
| [[Backend-Cloud-API]] | Cuore attivo dello sviluppo: ~40 tabelle/modelli, 41+ migrazioni Alembic, aree recenti: videoperizia, comunicazioni, device token/push, AI prompt versioning, route planning CAT, GDPR, bridge platform-admin + error-tracking backend-only per PynkStudio (2026-09-06) |
| [[Portal-Web-Assicurati]] | Architettura iniziale implementata (vedi sezione dedicata sotto) |
| [[CatDispatcher]] | Sviluppo attivo, migrato a Next.js App Router, dispatch engine deterministico come primo passo |
| [[Altre-Web-App]] (Bignami, Insight Studio, Randa) | Migrate a Next.js App Router; grado di integrazione nel gateway variabile |
| [[Login-Unificato-SSO]] | **Pianificato, non implementato**: solo le basi lato backend esistono (`/auth/login`, `/auth/me`, tabella `users` con i campi necessari) |
| [[PerX-Lite-Extension]] | Implementata 2026-09-06, non ancora testata contro il DOM live di JFish; standalone, fuori dal resto della piattaforma |

## Portale assicurati — dettaglio stato

### Implementato
- Backend `portal`: modelli, API, token flow, migration dedicate.
- Web app dedicata (`apps/portal-web`) con pagine, sessione locale, integrazione API — contratto
  frontend↔backend riconciliato il 2026-09-05 (vedi [[06-Decisioni-e-Intenzioni-Future]]):
  `lib/api.ts`/`lib/types.ts` ora rispecchiano esattamente gli schemi Pydantic del backend.
  `tsc --noEmit` pulito su tutta l'app.
- Schedulazione sopralluogo: conferma posizione, pin interattivo, selezione multi-slot.
- Invio e-mail automatico del magic link, sia per link generati dallo staff sia per il resend
  self-service dall'assicurato (via `ResendEmailService`, richiede `RESEND_API_KEY` configurata).
- Signed upload URL reali verso Supabase Storage (con fallback al proxy server quando Supabase
  non è configurato).
- Canalizzazione delle risposte staff → assicurato nella chat portale (mirror in
  `PortalConversationMessage` + notifica push/email all'assicurato).
- Antifrode di base per la documentale fotografica (EXIF/GPS, hash percettivo per duplicati) —
  segnalazione non bloccante, dietro `FF_PORTAL_PHOTO_ANTIFRAUD_ENABLED`.

### Non ancora collegato
- OTP SMS: nessun provider (Twilio/Vonage/...) integrato nel backend — solo preview in ambiente
  dev. Decisione esplicita dell'utente (2026-09-05) di rimandarlo; da riprendere quando si sceglie
  un provider e si configurano le relative credenziali.

## Migrazione web → Next.js App Router — dettaglio stato

- Le app precedentemente basate su Vite (CatDispatcher, Bignami, Insight Studio) sono state
  portate a Next.js App Router, mantenendo temporaneamente `react-router-dom` come client
  boundary interno per preservare percorsi e comportamento.
- **Prossimo passo pianificato**: convertire gradualmente le rotte in App Router nativo e spostare
  nel gateway (`apps/portal-web`) i portali operativi che devono essere serviti dal singolo
  progetto Vercel `perx` (vedi [[04-Infrastruttura-e-Deploy]]).

## Login unificato / SSO — dettaglio stato

Vedi [[Login-Unificato-SSO]] per il piano completo (5 fasi). Ad oggi:
- Ogni app fa login autonomo verso `/api/v1/auth/login` (CatDispatcher e pannello admin incluse,
  con form email/password locali — non ancora SSO).
- Nessuna delle 5 fasi del piano di migrazione è stata avviata in modo strutturato: è un lavoro
  pianificato, non ancora iniziato.

## Feature flag e default reali (`backend/app/core/config.py`)

| Flag | Default | Significato |
| --- | --- | --- |
| `SINGLE_TENANT_MODE` | `True` | Produzione iniziale a singolo tenant (vedi [[02-Architettura]]) |
| `FF_CLOUD_AUTH_ENABLED` | `False` | Supporto Supabase Auth presente nel codice ma non attivo |
| `FF_TASKS_ENABLED` | `False` | API `case_tasks` presente ma non abilitata di default — vedi [[Sistema-Task]] |
| `FF_LOCAL_AI_PROCESS_JOBS_ENABLED` | `True` | Worker AI locale via `process_jobs` **attivo di default** |

## Qualità, test e CI/CD

- **Nessuna pipeline CI/CD**: non esiste una cartella `.github/workflows` né altro sistema di CI
  nel repo. Le build/deploy (Render, Vercel) partono da push/hook della piattaforma, senza gate
  automatico di test prima del deploy.
- **Copertura di test minima**: `backend/tests` contiene solo 4 file di test; i target Apple
  (`PerXTests`, `PerXUITests`, varianti Lite/iPad) hanno solo i file di test boilerplate generati
  da Xcode (1 unit test + 2 UI test per target), non una suite reale. Nessuna delle app
  `apps/*` ha uno script `test` in `package.json`.
- **Implicazione pratica**: le verifiche di "funziona/non funziona" oggi si basano su uso reale e
  controllo manuale (typecheck TS, audit occasionali), non su test automatizzati — un'area di
  debito tecnico da tenere presente prima di refactoring ampi.
- Debito minore noto nel codice: ~16 `TODO`/`FIXME` in `backend/app`, ~32 in `PerX/` (non
  triagati in questa nota; utile un passaggio dedicato se si vuole ridurre il debito).

## Integrazione PynkStudio (admin.pynkstudio.eu) — dettaglio stato

Vedi [[06-Decisioni-e-Intenzioni-Future]] (2026-09-06) per contesto e motivazione completi.

- **Implementato**: bridge `X-PerX-Admin-Key` su `/api/v1/admin/*` (`require_platform_admin_or_api_key`
  in `backend/app/core/security.py`), tabella `platform_error_log` + route
  `/api/v1/admin/errors*` (solo eccezioni non gestite del backend cloud), portale
  `admin.pynkstudio.eu/perx` lato BePork (tenant, utenti, errori, domain-routes), gate ristretto ai
  ruoli `superadmin`/`admin`.
- **Non ancora fatto** (richiede l'utente, fuori da questo repo): impostare
  `PLATFORM_ADMIN_API_KEY` su Render e `PERX_ADMIN_API_KEY`/`PERX_ADMIN_API_URL` su Vercel
  (BePork), applicare la migration `038_platform_error_log` in produzione, verifica sul campo del
  portale con una sessione `superadmin` reale.
- **Intenzione dichiarata, non pianificata**: estendere `platform_error_log` oltre il backend
  cloud — ingestion da web app satellite, app iOS/macOS/iPad e [[PerXHub]], per coprire davvero
  "tutto il flusso di errori del progetto" come richiesto dall'utente. La colonna `source` è già
  pronta per questo (stringa libera, non enum).

## Decisioni ancora aperte

- Provider di identità definitivo per il login unificato: Supabase Auth vs Auth0/Okta/Cognito vs
  IdP custom (raccomandazione attuale: Supabase Auth, vedi [[Login-Unificato-SSO]]).
- Metodo di primo accesso utente: password, magic link, OTP o passkey.
- Dominio mail interna definitivo (`@perx.it` o dominio tenant-specific).
- Dove ospitare le sessioni web (cookie HttpOnly centralizzati vs token per-app).
- Integrazione completa di CatDispatcher, Bignami e Insight Studio nel gateway unico
  `apps/portal-web`.

---
Ultimo aggiornamento: 2026-09-06 (aggiunta sezione integrazione PynkStudio)
