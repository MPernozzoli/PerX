# Observability e Sicurezza - Configurazione

## Logging

### Struttura Logging

Usare logging strutturato con correlation ID per tracciare richieste end-to-end.

**Implementazione**:
```python
import logging
import uuid
from contextvars import ContextVar

request_id_var: ContextVar[str] = ContextVar('request_id', default=None)

class RequestIDFilter(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_var.get() or 'no-request'
        return True

# In middleware FastAPI
@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = str(uuid.uuid4())
    request_id_var.set(request_id)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response
```

### Livelli Log

- **DEBUG**: Dettagli sviluppo, query SQL, payload completi
- **INFO**: Operazioni business (create claim, state change, assignment)
- **WARNING**: Operazioni fallite ma recuperabili (retry, fallback)
- **ERROR**: Errori non recuperabili, eccezioni
- **CRITICAL**: Errori che richiedono intervento immediato

### Destinazione Log

- **Development**: stdout/stderr
- **Staging/Production**: Cloud Logging (GCP) o equivalente, con retention 30 giorni

---

## Metrics

### Metriche Principali

1. **HTTP Metrics**:
   - `http_requests_total` (counter, labels: method, endpoint, status)
   - `http_request_duration_seconds` (histogram, labels: endpoint)

2. **Business Metrics**:
   - `claims_created_total` (counter)
   - `claims_state_transitions_total` (counter, labels: from_state, to_state)
   - `emails_ingested_total` (counter)
   - `tasks_created_total` (counter)

3. **System Metrics**:
   - `db_connection_pool_size` (gauge)
   - `db_query_duration_seconds` (histogram)
   - `pubsub_messages_published_total` (counter)

### Implementazione

Usare Prometheus client library:
```python
from prometheus_client import Counter, Histogram, Gauge

http_requests = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
http_duration = Histogram('http_request_duration_seconds', 'HTTP request duration', ['endpoint'])
```

Esporre endpoint `/metrics` per scraping Prometheus.

---

## Tracing

### OpenTelemetry

Configurare OpenTelemetry per tracing distribuito:

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

otlp_exporter = OTLPSpanExporter(endpoint="http://otel-collector:4317")
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)
```

### Spans Principali

- `api.request` - Richiesta HTTP completa
- `db.query` - Query database
- `pubsub.publish` - Pubblicazione evento
- `storage.upload` - Upload file
- `mail.ingest` - Ingestion email

---

## Row-Level Security (RLS) Postgres

### Policy Base

Ogni tabella deve avere policy RLS che filtra automaticamente per `tenant_id`:

```sql
-- Abilita RLS
ALTER TABLE claims ENABLE ROW LEVEL SECURITY;

-- Policy: utenti vedono solo dati del proprio tenant
CREATE POLICY tenant_isolation ON claims
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id')::text);

-- Impostare tenant_id in ogni sessione
SET app.current_tenant_id = 'tenant-123';
```

### Implementazione in FastAPI

Middleware per impostare `current_tenant_id` da JWT:

```python
@app.middleware("http")
async def set_tenant_context(request: Request, call_next):
    # Estrai tenant_id da JWT
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if token:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        tenant_id = payload.get("tenant_id")
        # Imposta in variabile di sessione (da passare a query)
        request.state.tenant_id = tenant_id
    response = await call_next(request)
    return response
```

Modificare tutte le query per includere `tenant_id`:

```python
query = select(Claim).where(Claim.tenant_id == request.state.tenant_id)
```

---

## Gestione Segreti

### Secret Manager (GCP Secret Manager o equivalente)

**Segreti da gestire**:
- `SECRET_KEY` - JWT signing key
- `DATABASE_PASSWORD` - Password DB
- `mailbox-oauth-tokens` - Token OAuth caselle email
- `mailbox-passwords` - Password caselle (se non OAuth)

### Accesso Segreti

```python
from google.cloud import secretmanager

def get_secret(secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")
```

### Rotazione

- **SECRET_KEY**: Rotazione ogni 90 giorni, invalidare token esistenti
- **Database password**: Rotazione ogni 180 giorni
- **OAuth tokens**: Refresh automatico quando scadono

---

## Backup e Restore

### Database Postgres

**Backup automatici**:
- Giornalieri: Full backup + WAL archiving
- Retention: 30 giorni
- Point-in-time recovery: Abilitato

**Script restore**:
```bash
# Restore da backup
pg_restore -d perx_cloud backup.dump

# Point-in-time recovery
psql -c "SELECT pg_recovery_to_time('2024-01-15 10:00:00');"
```

### Object Storage

**Versioning**: Abilitato su bucket critici
**Lifecycle rules**:
- Dopo 90 giorni: Move to Nearline storage
- Dopo 365 giorni: Move to Coldline storage
- Dopo 5 anni: Delete (se non marcato come retention)

---

## Rate Limiting

### Implementazione

Usare middleware FastAPI con Redis per tracking:

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.get("/api/v1/claims")
@limiter.limit("100/minute")
async def list_claims(request: Request):
    ...
```

### Limiti Proposti

- **Auth endpoints**: 10/min per IP
- **Read endpoints**: 100/min per utente
- **Write endpoints**: 30/min per utente
- **Upload endpoints**: 10/min per utente

---

## Monitoring e Alerting

### Dashboard (Grafana o equivalente)

**Panels principali**:
1. Request rate e latency (p50, p95, p99)
2. Error rate per endpoint
3. Database connection pool usage
4. Pub/Sub message lag
5. Email ingestion rate
6. Active users per tenant

### Alert Rules

1. **Error rate > 5% per 5 minuti** → PagerDuty/Slack
2. **Latency p95 > 2s per 10 minuti** → Warning
3. **Database connections > 80%** → Warning
4. **Email ingestion lag > 1 ora** → Warning
5. **API downtime** → Critical

---

## Compliance e Audit

### Audit Log

Tutte le operazioni critiche loggate in `audit_log`:
- Create/Update/Delete claim
- State transitions
- Assignments
- User login/logout
- Permission changes

### Retention Audit

- **Audit log**: 7 anni (compliance)
- **Application logs**: 30 giorni
- **Metrics**: 90 giorni

### Accesso Audit

Solo ruoli `admin_tenant` possono accedere a audit log, con logging dell'accesso stesso.

