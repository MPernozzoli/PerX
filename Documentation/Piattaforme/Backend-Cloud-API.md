---
tags: [perx, piattaforma, backend, api]
updated: 2026-11-26
---

# Backend Cloud API

Backend **FastAPI** (Python), cuore dati/API della piattaforma. Struttura in `backend/app/`:

```
app/
├── main.py              # entry point FastAPI
├── core/                # config, database (SQLAlchemy async), security (JWT), logging
├── models/              # modelli SQLAlchemy (~45 file)
├── schemas/              # schemi Pydantic
├── services/             # business logic (~38 servizi)
└── api/v1/               # route HTTP (~32 file)
migrations/                # migrazioni Alembic (41+ revisioni)
```

Stack e deploy → [[03-Stack-Tecnologico]], [[04-Infrastruttura-e-Deploy]]. Setup locale
dettagliato → `backend/README.md`.

## Test e CI

`backend/requirements-dev.txt` estende le dipendenze runtime con pytest, pytest-asyncio,
pytest-cov e Ruff; `pyproject.toml` contiene configurazione, marker e coverage. La baseline del
2026-11-07 è di 28 test verdi, principalmente helper puri più i contratti health/root. Il workflow
`backend-ci.yml` usa Python 3.11 e Postgres 16, applica tutte le migrazioni su database vuoto e
pubblica `coverage.xml`. La coverage globale osservata (38%) deriva anche dall'import di tutte le
route e non va interpretata come copertura funzionale: test API/DB/auth restano il prossimo passo.
Al 2026-11-26 i test sono 67 (inclusi `test_security_hardening.py` e i test dello storage S3).
Fino a quella data il job CI non era mai passato perché le migration non ricostruivano lo schema da
zero. La revisione `002b_legacy_core_tables` (tra `002` e `003`) ora crea le 22 tabelle e le 72
colonne di `claims`/`users` nate fuori da Alembic, in modo idempotente; non viene mai eseguita sui
database già oltre `003` (production), perché Alembic considera applicati gli antenati della head.
Il DDL è congelato nel file, generato dai modelli a partire dallo stato di `002`. Restano
differenze minori tra migration e modelli (nomi di indici/FK, `JSON` vs `JSONB`), da non correggere
alla cieca perché il DB production le ha a sua volta.

## Sicurezza applicativa (dal 2026-11-26)

- **Guardia di produzione** (`app/core/config.py`): con `ENV` = `prod`/`production`/`staging`
  l'avvio fallisce se `SECRET_KEY` è un placeholder o ha meno di 32 caratteri (errore senza eco
  dei valori, per non esporre segreti nei log); `DEBUG`, `PORTAL_DEBUG_PREVIEW_LINKS` e
  `PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH` vengono forzati a `False` con log critico. I default
  di tutti e tre sono ora `False` anche in sviluppo.
- **Documentazione API** (`/docs`, `/redoc`, `/openapi.json`) disattivata in produzione;
  riattivabile con `API_DOCS_ENABLED=True`.
- **Rate limiting** in memoria a finestra scorrevole (`app/core/rate_limit.py`) su login,
  refresh, inviti e auth pubblica del portale: limiti per IP (da `CF-Connecting-IP`, poi
  ultimo hop di `X-Forwarded-For`) e per identificativo (email o riferimento sinistro, salvato
  solo come hash). È per-istanza: sufficiente con l'unica istanza Render attuale, da spostare su
  uno store condiviso (es. Redis) prima di scalare orizzontalmente.
- **Webhook provider comunicazioni** (`POST /communications/provider-webhook`): disattivato
  (404) finché non è impostato `COMMUNICATIONS_WEBHOOK_SECRET`, poi richiede l'header
  `X-PerX-Webhook-Secret`. Resta da implementare la verifica della firma nativa del provider
  (`TelnyxAdapter.validate_webhook_signature` è ancora uno stub).
- Gli script `scripts/bootstrap_single_tenant.py` e `scripts/seed_data.py` si rifiutano di usare
  la password admin di default (pubblica nel repo) o di girare in ambienti production-like.
- Dipendenze aggiornate per CVE note: `python-jose` 3.5.0, `python-multipart` 0.0.20. Resta da
  aggiornare FastAPI/Starlette (0.115.6/0.41.3) e sostituire `passlib`, non più mantenuto.

## Storage del vault: provider S3 (predisposto, non attivo — 2026-11-26)
`VaultStorageService` (`app/services/vault_storage_service.py`) ha un terzo provider `s3`,
selezionato solo da `VAULT_STORAGE_PROVIDER=s3`; il default resta `local` e in produzione `mac_mini`,
quindi **il comportamento attuale non cambia**. Il contratto delle rotte `/api/v1/hub/vault/...` è
invariato (le app non parlano mai direttamente con lo storage).
- Implementazione: `S3ObjectStore` (boto3, chiamate bloccanti eseguite con `asyncio.to_thread`,
  client lazy e in cache). Stesse semantiche degli altri provider: `overwrite`, `missing_ok`,
  `FileNotFoundError`/`FileExistsError`, copy/move = CopyObject (+ DeleteObject). Scritture con
  SSE-S3 (`AES256`) e SHA-256 nei metadata dell'oggetto. `ensure_claim_folder` è un no-op (S3 non
  ha cartelle). Con `s3` senza bucket l'errore è esplicito.
- Settings (tutte opzionali): `VAULT_S3_BUCKET`, `VAULT_S3_REGION` (default `eu-south-1`),
  `VAULT_S3_ENDPOINT_URL` (vuoto = AWS; moto server locale o endpoint S3 di Supabase), `VAULT_S3_PREFIX`,
  `VAULT_S3_FORCE_PATH_STYLE` (endpoint locali), `VAULT_S3_PRESIGNED_URL_TTL_SECONDS` (300). Credenziali
  solo dalla catena AWS standard (variabili `AWS_*`, profili, IAM role): mai nel repo.
- Download presigned **opt-in**: `generate_download_url()` + flag `VAULT_S3_PRESIGNED_DOWNLOADS`
  (default `False`). Spento, la rotta di download continua a restituire i byte; acceso (e solo con
  provider `s3`) risponde con redirect 307 all'URL firmato.
- Migrazione: `backend/scripts/migrate_vault_to_s3.py`. Il Mac mini non ha un endpoint di listing,
  quindi l'elenco file viene dal DB (`documents.storage_path` + `document_versions.storage_path`,
  esclusi i documenti `deleted`, filtrati per `storage_provider`). Dry-run di default, `--execute`
  richiede sorgente e destinazione esplicite; idempotente (salta se size + SHA-256 coincidono),
  verifica SHA-256 post-upload, riprendibile (`--state-file`), concorrenza limitata, report JSON
  (copied / skipped / missing at source / failed); non cancella mai nulla alla sorgente.
- Test: `tests/test_vault_storage_s3.py` e `tests/test_migrate_vault_to_s3.py` (moto, niente
  Docker). Simulazione locale con moto server in Docker (`backend/docker-compose.storage.yml`), verificata end-to-end il 2026-11-26; MinIO è stato scartato perché le sue immagini community non sono più distribuite pubblicamente.
Contesto e decisione → [[06-Decisioni-e-Intenzioni-Future]]; variabili → [[04-Infrastruttura-e-Deploy]].

## Aree funzionali principali (da `api/v1/`)

| Area | File route | Note |
| --- | --- | --- |
| Autenticazione & utenti | `routes_auth.py`, `routes_profiles.py`, `routes_invitations.py`, `routes_user_settings.py`, `routes_user_directory.py`, `routes_devices.py` | Base per il login unificato — vedi [[Login-Unificato-SSO]] |
| Tenant & admin | `routes_tenants.py`, `routes_admin.py`, `routes_admin_errors.py` | Multi-tenant nel codice, `SINGLE_TENANT_MODE=False` in produzione (vedi [[05-Stato-Sviluppo-e-Roadmap]]). `routes_admin*` accetta anche un bridge API key per PynkStudio, vedi sotto |
| Sinistri | `routes_claims.py`, `routes_actors.py`, `routes_documents.py`, `routes_folder_packages.py`, `routes_attachments.py`, `routes_diary.py`, `routes_inspections.py` | Vedi [[Gestione-Sinistri]] |
| Comunicazioni | `routes_communications.py`, `routes_emails.py`, `routes_email_processing.py`, `routes_processed_emails_sync.py`, `routes_whatsapp.py`, `routes_internal_chat.py`, `routes_realtime.py` | Vedi [[Comunicazioni]] |
| Task | `routes_tasks.py` | Vedi [[Sistema-Task]] |
| AI | `routes_ai_chat.py`, `routes_ai_prompts.py`, `routes_ai_routing.py` | Vedi [[AI-Locale-e-Cloud]] |
| Portale assicurati | `routes_portal.py`, `routes_portal_me.py` | Vedi [[Portal-Web-Assicurati]] |
| CAT Dispatcher | `routes_cat_dispatcher.py` | Vedi [[CatDispatcher]] |
| Videoperizia | `routes_videoperizia.py` | Vedi [[Videoperizia]] |
| Process jobs (Mac mini) | `routes_process_jobs.py` | Vedi [[04-Infrastruttura-e-Deploy]] |
| Pianificazione | `routes_planning.py`, `routes_reporting.py`, `routes_routing.py`, `routes_rubrica.py` | Agenda, reportistica, instradamento, rubrica contatti |
| Bignami | `routes_bignami.py` | Ponte verso lo schema Postgres `bignami` — vedi [[Altre-Web-App]] |
| Hub | `routes_hub_compat.py` | Compatibilità verso [[PerXHub]]. Il vault passa da `VaultStorageService` (provider `local`, `mac_mini`, `s3`) |

Per l'elenco esaustivo degli endpoint con verbo HTTP, vedi `backend/README.md` (mantenuto
aggiornato per l'uso pratico/setup; i concetti architetturali restano qui).

## Modelli dati principali (`app/models/`)

Domini principali: `claim*` (sinistro, stato, eventi, assegnazioni, diario), `document*`
(documenti e versioni), `communication`, `email`, `internal_chat`, `portal*` (perimetro
assicurati, sessioni, notifiche, privacy), `videoperizia`, `case_task`, `process_job`,
`ai_*` (chat, prompt template + versioning, routing policy), `route_planning`, `inspection`,
`invitation`, `tenant`, `user*`, `role`, `audit_log`, `rubrica`, `compagnia`, `actor`,
`automation`, `device_token`, `platform_error_log`.

## Multi-tenant e platform admin

- Il default nel codice (`Settings`) è `SINGLE_TENANT_MODE=True`, ma `render.yaml` lo imposta
  esplicitamente a `False` in produzione: la piattaforma prod **non** è ristretta a un singolo
  tenant. Bootstrap del tenant singolo (uso locale/dev) via `scripts/bootstrap_single_tenant.py`;
  provisioning di un tenant reale via `scripts/bootstrap_tenant.py` (usato per Studio Randa, tenant
  `randa-srl` — vedi [[Altre-Web-App]]).
- **Platform admin** (`User.is_platform_admin=True`) ha accesso cross-tenant completo via
  `/api/v1/admin/*` (`routes_admin.py`, `routes_admin_errors.py`): tenant, settings (incluse le
  secret provider/AI), utenti, domain-routes, error log.
- **Snapshot del control plane** (2026-11-25): `GET /api/v1/admin/overview` restituisce in una
  sola risposta modalità single/multi-tenant, conteggi di tenant, utenti attivi, domain route ed
  errori aperti/critici, più l'inventario esplicito delle capability CRUD realmente supportate.
  La lista utenti è dichiarata read-only; il portale centrale non deve mostrare azioni che il
  backend non può ancora eseguire.
- **Tenant admin** (ruolo `admin_tenant`) è scoped al proprio tenant via `/api/v1/tenants/me/*`
  (`routes_tenants.py`) — bloccato esplicitamente da slug/domini/branding/secrets, che restano
  platform-admin-only anche da quell'endpoint.
- **Bridge per sistemi esterni** (2026-09-06, vedi [[06-Decisioni-e-Intenzioni-Future]]): tutte le
  route `/api/v1/admin/*` accettano, in alternativa al JWT platform-admin, un header
  `X-PerX-Admin-Key` verificato contro `PLATFORM_ADMIN_API_KEY` (dependency
  `require_platform_admin_or_api_key` in `app/core/security.py`) — usato dal portale PerX su
  `admin.pynkstudio.eu` (repo BePork). Non tocca `get_current_platform_admin`/`oauth2_scheme`
  esistenti.

## Error tracking (platform_error_log)

Introdotto il 2026-09-06, **solo per il backend cloud** — vedi
[[06-Decisioni-e-Intenzioni-Future]] per l'intenzione dichiarata di estenderlo a web app satellite,
app native e [[PerXHub]] (non ancora iniziato).

- Tabella `platform_error_log` (migrazione `038_platform_error_log`): `tenant_id` nullable,
  `source` (stringa libera, oggi sempre `"backend"`), `severity`, `message`, `stack_trace`,
  `path`/`method`/`status_code`, `context_json`, `resolved`/`resolved_at`/`resolved_by_user_id`.
- Popolata da un `@app.exception_handler(Exception)` globale in `app/main.py` su ogni eccezione non
  gestita (best-effort: un fallimento nella scrittura del log non altera la risposta 500).
- Esposta via `GET /api/v1/admin/errors` (filtri `tenant_id`/`severity`/`resolved`/`since`),
  `GET /api/v1/admin/errors/{id}`, `PATCH /api/v1/admin/errors/{id}` (segna risolto) —
  `app/api/v1/routes_admin_errors.py`, stessa auth di `routes_admin.py`.

## Aree di sviluppo recenti (da cronologia migrazioni)

Le revisioni Alembic più recenti indicano un focus su: **videoperizia** (sessioni, media,
location ping, consolidamento stato, disconnessione assicurato), **comunicazioni** (core +
estensioni), **device token/push**, **AI prompt versioning & routing runs**, **route planning**
(CAT), **GDPR** (portale e actor), **domain routing per le app web**. Vedi
[[05-Stato-Sviluppo-e-Roadmap]].

---
Ultimo aggiornamento: 2026-11-26 (provider S3 predisposto; migrazioni ricostruibili da zero)
