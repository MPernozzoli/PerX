# PerX Cloud API Backend

Backend FastAPI per la piattaforma cloud-first di gestione sinistri PerX.

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
# Edit .env with your settings
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
- `GET /api/v1/claims` - List claims
- `POST /api/v1/claims` - Create claim
- `GET /api/v1/claims/{id}` - Get claim
- `PUT /api/v1/claims/{id}` - Update claim
- `POST /api/v1/claims/{id}/state-transitions` - Change state
- `GET /api/v1/claims/{id}/events` - Get timeline

## Deployment

Build Docker image:
```bash
docker build -t perx-cloud-api .
```

Run container:
```bash
docker run -p 8080:8080 --env-file .env perx-cloud-api
```

