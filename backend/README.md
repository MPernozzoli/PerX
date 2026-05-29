# PerX Cloud API Backend

Backend FastAPI per la piattaforma cloud-first di gestione sinistri PerX.

## Supabase

Il backend e' predisposto per usare Supabase come database Postgres gestito.

1. Copia `backend/.env.example` in `backend/.env` se non esiste.
2. Imposta `DATABASE_URL` con la connection string Postgres di Supabase.
3. Imposta `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`.
4. Esegui le migration Alembic dal folder `backend/`.

Esempio:

```bash
cd backend
alembic upgrade head
python scripts/bootstrap_single_tenant.py
uvicorn app.main:app --reload
```

## Struttura

```
backend/
├── app/
│   ├── main.py              # Entry point FastAPI
│   ├── core/                # Configurazione core
│   │   ├── config.py        # Settings
│   │   ├── database.py      # DB session
│   │   ├── security.py      # JWT, password hashing
│   │   └── logging.py       # Logging setup
│   ├── models/              # SQLAlchemy models
│   ├── schemas/             # Pydantic schemas
│   ├── services/            # Business logic
│   └── api/
│       └── v1/              # API routes
├── migrations/              # Alembic migrations
├── requirements.txt
├── Dockerfile
└── .env.example
```

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure environment:
```bash
cp .env.example .env
# Edit .env with your settings / Supabase credentials
```

3. Run migrations:
```bash
alembic upgrade head
```

4. Bootstrap primo tenant:
```bash
python scripts/bootstrap_single_tenant.py
```

5. Configura Resend per email in ingresso/uscita:
```bash
RESEND_API_KEY=...
RESEND_DEFAULT_FROM_EMAIL=admin@example.com
RESEND_SCHEDULED_EMAILS_ENABLED=True
```

6. Run development server:
```bash
uvicorn app.main:app --reload
```

## API Endpoints

- `POST /api/v1/auth/login` - Login
- `GET /api/v1/auth/me` - Current user info
- `GET /api/v1/admin/tenants` - Lista tenant, solo platform admin
- `GET /api/v1/admin/users` - Lista utenti cross-tenant, solo platform admin
- `GET /api/v1/tenants/me/settings` - Legge le impostazioni tenant per tenant admin o platform admin
- `PUT /api/v1/tenants/me/settings` - Aggiorna le impostazioni tenant per tenant admin o platform admin
- `GET /api/v1/claims` - List claims
- `POST /api/v1/claims` - Create claim
- `GET /api/v1/claims/{id}` - Get claim
- `PUT /api/v1/claims/{id}` - Update claim
- `POST /api/v1/claims/{id}/state-transitions` - Change state
- `GET /api/v1/claims/{id}/events` - Get timeline
- `POST /api/v1/cat-dispatcher/address-to-cat` - Lookup CAT da indirizzo o comune tramite servizio CatDispatcher
- `POST /api/v1/cat-dispatcher/get-cat-by-commune` - Lookup CAT economico da comune/provincia tramite servizio CatDispatcher
- `GET /api/v1/cat-dispatcher/dispatch/availability?cat_id=...` - Disponibilita operativa del CAT gestita da CatDispatcher
- `POST /api/v1/cat-dispatcher/dispatch/{action}` - API del modulo dispatch indipendente di CatDispatcher
- `POST /api/v1/portal/claims/{id}/access-links` - Genera link di accesso portale per un assicurato
- `POST /api/v1/portal/auth/start` - Avvia challenge pubblico per accesso assicurato
- `POST /api/v1/portal/auth/exchange` - Scambia magic link con sessione portale
- `GET /api/v1/portal/claims` - Elenca tutti i sinistri accessibili allo stesso assicurato
- `GET /api/v1/portal/claim` - Dashboard assicurato sul proprio sinistro
- `GET /api/v1/portal/claim/inspection-scheduling` - Restituisce stato, posizione e disponibilita sopralluogo
- `PUT /api/v1/portal/claim/inspection-scheduling/location` - Conferma indirizzo e coordinate del sopralluogo
- `PUT /api/v1/portal/claim/inspection-scheduling/preferences` - Salva le finestre preferite dell'assicurato
- `POST /api/v1/process-jobs/jobs` - Accoda un job di processo server-side
- `GET /api/v1/process-jobs/jobs/claim` - Il worker Mac mini prende pochi job disponibili in lease
- `POST /api/v1/process-jobs/jobs/{id}/heartbeat` - Il worker estende il lease mentre lavora
- `POST /api/v1/process-jobs/jobs/{id}/complete` - Il worker salva il risultato del job
- `POST /api/v1/process-jobs/jobs/{id}/fail` - Il worker registra errore e retry/backoff

## Portale assicurati

Il backend include ora un perimetro dedicato al portale web assicurati:

- modelli separati per accessi portale, challenge, documentale, firma, IBAN e chat esterna;
- token di sessione distinti rispetto agli utenti interni;
- endpoint dedicati sotto `/api/v1/portal`;
- instradamento dei messaggi assicurato -> team interno tramite il sistema chat esistente;
- integrazione del workflow CAT per fissazione sopralluoghi lato assicurato;
- architettura pronta per integrare invio e-mail automatico, SMS OTP e upload firmati storage.

In ambiente `dev` e con `PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH=True`, il portale puo creare al volo un accesso partendo dal solo riferimento sinistro e mostrare direttamente il magic link di anteprima senza ulteriori verifiche. Questa scorciatoia e pensata solo per sviluppo locale.

Per il dettaglio funzionale e dei flussi, vedere anche `Documentation/insured-portal-architecture.md`.

## CatDispatcher

La gestione delle associazioni CAT-Comune e del dispatch vive come modulo applicativo separato, ma dentro lo stesso backend e lo stesso database Supabase di PerX. Il confine resta API-first sotto `/api/v1/cat-dispatcher`: CatDispatcher, portale assicurati e app PerX usano token PerX e non accedono direttamente alle tabelle operative.

## Process jobs e Mac mini

Le automazioni restano sul backend e persistono lo stato su Supabase. Quando serve una capacita locale del Mac mini, ad esempio analisi IA con modello MLX, il backend accoda un record in `process_jobs` invece di eseguire lavoro pesante nel processo API.

Il worker locale usa `X-PerX-Worker-Secret` con il valore di `LOCAL_AI_WORKER_SHARED_SECRET`, chiama `GET /api/v1/process-jobs/jobs/claim?worker_id=<id>&limit=3`, processa i job con stato `processing`, invia heartbeat se il lavoro dura a lungo, poi chiude con `complete` o `fail`. Le automazioni accodano gia `local_ai.diary_entry_analysis` per comunicazioni e allegati collegati a un sinistro.

## Deployment

Build Docker image:
```bash
docker build -t perx-cloud-api .
```

Run container:
```bash
docker run -p 8080:8080 --env-file .env perx-cloud-api
```

## Multi-tenant e platform admin

- Per la V1 limitata usare `SINGLE_TENANT_MODE=True` e creare un solo tenant con `scripts/bootstrap_single_tenant.py`.
- L'admin configurato via `SINGLE_TENANT_ADMIN_EMAIL` e' sia platform admin sia admin tenant, cosi puo' configurare credenziali provider e impostazioni studio.
- Gli utenti standard restano filtrati sul proprio tenant.
- Il codice conserva il supporto multi-tenant, ma la messa in produzione iniziale deve creare e usare un solo tenant.
