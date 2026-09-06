---
tags: [perx, piattaforma, backend, api]
updated: 2026-09-05
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
| Hub | `routes_hub_compat.py` | Compatibilità verso [[PerXHub]] |

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
Ultimo aggiornamento: 2026-09-06
