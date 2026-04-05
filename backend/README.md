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

4. Run development server:
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
- `POST /api/v1/portal/claims/{id}/access-links` - Genera link di accesso portale per un assicurato
- `POST /api/v1/portal/auth/start` - Avvia challenge pubblico per accesso assicurato
- `POST /api/v1/portal/auth/exchange` - Scambia magic link con sessione portale
- `GET /api/v1/portal/claim` - Dashboard assicurato sul proprio sinistro

## Portale assicurati

Il backend include ora un perimetro dedicato al portale web assicurati:

- modelli separati per accessi portale, challenge, documentale, firma, IBAN e chat esterna;
- token di sessione distinti rispetto agli utenti interni;
- endpoint dedicati sotto `/api/v1/portal`;
- instradamento dei messaggi assicurato -> team interno tramite il sistema chat esistente;
- architettura pronta per integrare invio e-mail automatico, SMS OTP e upload firmati storage.

Per il dettaglio funzionale e dei flussi, vedere anche `Documentation/insured-portal-architecture.md`.

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

- Ogni studio peritale corrisponde a un tenant applicativo.
- Gli utenti standard vedono solo i dati del proprio tenant.
- L'account `info@pynkstudio.it` viene inizializzato come `is_platform_admin=true` e puo' accedere ai dati di tutti i tenant.
- Gli endpoint claims supportano il query param `tenant_id` solo per il platform admin; senza parametro il platform admin vede tutti i tenant.
