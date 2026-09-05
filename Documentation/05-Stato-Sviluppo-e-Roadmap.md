---
tags: [perx, stato, roadmap]
updated: 2026-09-05
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
| [[Backend-Cloud-API]] | Cuore attivo dello sviluppo: ~40 tabelle/modelli, 41+ migrazioni Alembic, aree recenti: videoperizia, comunicazioni, device token/push, AI prompt versioning, route planning CAT, GDPR |
| [[Portal-Web-Assicurati]] | Architettura iniziale implementata (vedi sezione dedicata sotto) |
| [[CatDispatcher]] | Sviluppo attivo, migrato a Next.js App Router, dispatch engine deterministico come primo passo |
| [[Altre-Web-App]] (Bignami, Insight Studio, Randa) | Migrate a Next.js App Router; grado di integrazione nel gateway variabile |
| [[Login-Unificato-SSO]] | **Pianificato, non implementato**: solo le basi lato backend esistono (`/auth/login`, `/auth/me`, tabella `users` con i campi necessari) |

## Portale assicurati — dettaglio stato

### Implementato
- Backend `portal`: modelli, API, token flow, migration dedicate.
- Web app dedicata (`apps/portal-web`) con pagine, sessione locale, integrazione API.
- Schedulazione sopralluogo: conferma posizione, pin interattivo, selezione multi-slot.
- Typecheck frontend e audit puliti.

### Non ancora collegato
- Invio e-mail automatico del magic link (oggi solo preview in ambiente dev).
- OTP SMS.
- Signed upload URL reali verso Supabase Storage.
- Canalizzazione delle risposte staff → assicurato nella chat portale.
- Antifrode forte per la documentale fotografica.

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

## Decisioni ancora aperte

- Provider di identità definitivo per il login unificato: Supabase Auth vs Auth0/Okta/Cognito vs
  IdP custom (raccomandazione attuale: Supabase Auth, vedi [[Login-Unificato-SSO]]).
- Metodo di primo accesso utente: password, magic link, OTP o passkey.
- Dominio mail interna definitivo (`@perx.it` o dominio tenant-specific).
- Dove ospitare le sessioni web (cookie HttpOnly centralizzati vs token per-app).
- Integrazione completa di CatDispatcher, Bignami e Insight Studio nel gateway unico
  `apps/portal-web`.

---
Ultimo aggiornamento: 2026-09-05 (aggiunta sezione qualità/test/CI e default feature flag)
