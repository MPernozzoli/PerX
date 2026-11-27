---
tags: [perx, stato, roadmap]
updated: 2026-11-27
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
| [[PerX-App-Principale]] | Uso interno attivo, sviluppo continuo (modulo più grande della repo, ~505 file Swift). Motore di stima deterministico integrato nel wizard della perizia il 2026-11-26 (vedi sezione dedicata) |
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

## Motore di stima della perizia — dettaglio stato

### Implementato (2026-11-26)
- [[Motore-di-Stima]] in `PerX/Services/Claims/Stima/`: calcolo Decimal, validazione, avvisi,
  scomposizione richiesto → accertato → liquidabile, testi per l'atto e per le conclusioni,
  soglia di controllo, revisioni con approvazione, hash economico e approvazione ereditata,
  verifica dell'atto firmato. `CalcoliService` delega al motore.
- Pagine del wizard aggiornate senza cambiare la navigazione: voci con richiesta, giustificativo e
  motivo d'esclusione; scheda bene con genere e bene comune; Liquidazione riscritta; Riepilogo e
  Atto sugli importi del motore; valore reale della partita e indennizzo virtuale delle
  coassicurazioni indirette nel Quadro contrattuale.
- Core Data versionato (`PerX v2`), migrazione leggera verificata su uno store di prova; backup
  dello store al posto della cancellazione. Dal 2026-11-27 il modello corrente è `PerX v3`,
  con `tenantId` sul sinistro: la lista mostra solo l'utente connesso e il suo tenant.
- 91 verifiche del motore superate in esecuzione standalone (`swiftc`) con i casi di
  `test_stima.py`; suite `StimaEngineTests` compilata nel target `PerXTests`.

## Regia e tenant Chiari — dettaglio stato

### In corso (2026-11-27)
- Profilo `chiari`: un solo perito, senza portale assicurati, Cat Dispatcher e funzioni verso
  colleghi o assicurati. Vedi [[Regia-Agenti-e-Tenant-Chiari]] e la decisione dello stesso giorno.
- Import delle 273 pratiche Chiari sul tenant (2026-11-27): riferimenti nel formato
  `26-602322`, 658 revisioni, 259 atti, 6357 eventi. I file dei dossier restano nella cartella locale.
- Migrazione `043` applicata sul database (2026-11-27). Tenant `chiari` e utente
  `massimo.pernozzoli@chiarisrl.it` creati: entra con Google, senza password.
- Posta Gmail sul backend (2026-11-27): storico e mail nuove in `emails`, allegati sul bucket
  `perx-portal-uploads`. Il bucket non esisteva e Storage rispondeva 400: creato lo stesso giorno
  (migrazione `044`). Le mail già salvate senza file si riprendono a gruppi di 20. Invio dalla casella Workspace con la firma `sendAs`. La mail si abbina prima al riferimento
  `YY-NNNNNN`, poi al numero compagnia, poi al nome assicurato. Il watch Pub/Sub è nel codice
  (`POST /api/v1/emails/gmail/push`); parte quando su Render c’è `GMAIL_PUBSUB_TOPIC`. Fino ad
  allora il recupero resta il polling ogni 90 secondi. Il Mac legge dal backend ogni 60 secondi.
  Un allegato che non si scarica viene ritentato tre volte; se resta su Gmail la mail compare
  comunque, con l’avviso in elenco e dettaglio.

### Ancora da fare
- Consenso e benchmark (F0), topic Pub/Sub Gmail da creare sul progetto Google, copia dei dossier
  nel vault, estensione, MCP. La Regia assegna i lavori e la scala L0–L4 è nel backend, per ogni
  tenant; il worker sul Mac prende i lavori L0. Resta da collegare Apple Intelligence, Ollama e
  Claude ai livelli L1–L3, e da misurare una settimana di chiusure contro la coda locale.

### Da fare / da verificare
- Prova a mano nell'app delle sei pagine su perizie reali (non ancora fatta: l'avvio migra lo store locale).
- Annualità del massimale (più sinistri dello stesso assicurato nella stessa annualità).
- Sinistri collegati multi-pratica con bene comune identico su più perizie.
- Esito derivato dalla `definizione` del sinistro per le pratiche già chiuse.
- Motore condiviso con il backend/MCP o spostato in `PerXCore` per `swift test` in CI.

## Qualità, test e CI/CD

- **Fondazioni CI implementate il 2026-11-07**: tre workflow GitHub Actions separati per backend,
  web e Apple con path filtering, cache e concorrenza cancellabile. Dettagli e distinzione tra
  gate bloccanti/osservativi in [[04-Infrastruttura-e-Deploy]].
- **Backend**: 28 test pytest verdi nella baseline locale, coverage misurata (38% risultante dalle
  importazioni dell'intera app, ancora poco rappresentativa delle route), smoke contract per
  `/` e `/health`, migrazioni verificate in CI su Postgres vuoto. Mancano ancora fixture DB e test
  API/auth/tenant reali.
- **Web**: Vitest configurato in tutti i workspace; 7 test iniziali verdi su routing tenant del
  portale e utility province CAT. Typecheck, test, lint e build production sono bloccanti su tutti
  i workspace; Bignami usa ora tipi Supabase coerenti con lo schema `bignami`. Tre app accettano
  ancora temporaneamente una suite vuota. Il lint è verde ma conserva warning non bloccanti su
  dipendenze hook e Fast Refresh.
- **Swift**: `PerXCore` ha ora un test target con 3 test verdi su stati sinistro e parsing HTML;
  `PerXHub` e il target Xcode `PerX` compilano come gate CI. I duplicati videoperizia sono esclusi
  dal target in favore di `Shared/Videoperizia/`. I target XCTest dell'app/varianti restano
  boilerplate.
- **CD non ancora protetta dai check**: Render e Vercel continuano a partire dai propri hook. Il
  passo successivo è far eseguire i workflow su GitHub, stabilizzare i nomi dei check, impostare
  branch protection su `main` e subordinare i deploy di produzione ai gate verdi.
- Debito minore noto nel codice: ~16 `TODO`/`FIXME` in `backend/app`, ~32 in `PerX/` (non
  triagati in questa nota; utile un passaggio dedicato se si vuole ridurre il debito).

## Integrazione PynkStudio (admin.pynkstudio.eu) — dettaglio stato

Vedi [[06-Decisioni-e-Intenzioni-Future]] (2026-09-06) per contesto e motivazione completi.

- **Implementato**: bridge `X-PerX-Admin-Key` su `/api/v1/admin/*` (`require_platform_admin_or_api_key`
  in `backend/app/core/security.py`), tabella `platform_error_log` + route
  `/api/v1/admin/errors*` (solo eccezioni non gestite del backend cloud), portale
  `admin.pynkstudio.eu/perx` lato BePork (tenant, utenti, errori, domain-routes), gate ristretto ai
  ruoli `superadmin`/`admin`. Dal 2026-11-25 è disponibile anche `GET /api/v1/admin/overview`,
  snapshot unico con KPI e inventario delle capability; la dashboard BePork lo usa come fonte
  autorevole e segnala esplicitamente che gli utenti sono ancora in sola lettura.
- **Intenzione dichiarata, non pianificata**: estendere `platform_error_log` oltre il backend
  cloud — ingestion da web app satellite, app iOS/macOS/iPad e [[PerXHub]], per coprire davvero
  "tutto il flusso di errori del progetto" come richiesto dall'utente. La colonna `source` è già
  pronta per questo (stringa libera, non enum).
- **Target deciso il 2026-11-25, fase 1 applicativa completata**: il dual-host è implementato per
  PerX pubblico, CAT Dispatcher e Bignami Online; tre origin Vercel production sono online, il
  gateway è configurato e la migration `040_pynkstudio_domains` è applicata in production con i
  tre alias attivi. Dal 2026-11-26 anche `app-perx.pynkstudio.eu` e
  `login-perx.pynkstudio.eu` sono associati al progetto Vercel `perx`, per un totale di cinque
  ingressi web; app e login servono temporaneamente la landing PerX. I record DNS Register.it
  sono propagati e i cinque host risolvono sulla rete Vercel. Il resolver remoto non è
  ancora usato dal gateway perché URL/secret non sono coordinati tra Vercel e Render; il fallback
  dual-host copre i tre prodotti. Il control plane API completo non è ancora realizzato:
  il bridge PerX attuale copre tenant, impostazioni, utenti in sola lettura, errori e
  domain-routes e usa una API key globale; l'inventario capability è ora implementato, mentre
  restano mutazioni utenti, audit delle scritture e credenziali scoped/ruotabili. Vedi
  [[06-Decisioni-e-Intenzioni-Future]] (2026-11-25).

## Decisioni ancora aperte

- Provider di identità definitivo per il login unificato: Supabase Auth vs Auth0/Okta/Cognito vs
  IdP custom (raccomandazione attuale: Supabase Auth, vedi [[Login-Unificato-SSO]]).
- Metodo di primo accesso utente: password, magic link, OTP o passkey.
- Dominio mail interna definitivo (`@perx.it` o dominio tenant-specific).
- Dove ospitare le sessioni web (cookie HttpOnly centralizzati vs token per-app).
- Integrazione completa di CatDispatcher, Bignami e Insight Studio nel gateway unico
  `apps/portal-web`.

---
Ultimo aggiornamento: 2026-11-27 (bucket Storage degli allegati Gmail)
