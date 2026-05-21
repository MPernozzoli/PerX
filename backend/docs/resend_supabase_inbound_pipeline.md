# Resend + Supabase inbound email pipeline

Questa infrastruttura affianca il worker IMAP/SMTP esistente e permette di migrare gradualmente verso:

```text
Resend email.received webhook
  -> Supabase Edge Function resend-inbound
  -> inbound_email_events + email_processing_jobs
  -> daemon locale Mac mini
  -> backend /api/v1/email-processing/*
  -> Supabase/Postgres + client realtime/automatismi
```

## Tabelle

- `tenant_email_domains`: domini email gestiti per tenant. Per Resend inbound deve contenere il dominio destinatario, ad esempio `cliente.com` o `mail.cliente.com`.
- `email_aliases`: indirizzi operativi virtuali, assegnati a utenti, team, sinistri o bucket. Gli alias utente vengono mantenuti automaticamente quando cambia la mail professionale.
- `inbound_email_events`: copia normalizzata e raw del webhook Resend.
- `email_processing_jobs`: coda persistente reclamata dal daemon IA locale.

## Identita' utente

- `users.personal_email`: email personale usata per invito, login e recovery.
- `users.professional_email`: email operativa sul dominio tenant usata per comunicazioni esterne e routing.

La generazione automatica usa `nome.cognome@tenant_domain`. Se esiste gia' un omonimo, viene provato `ruolo.nome.cognome@tenant_domain`, dove il ruolo arriva dai ruoli applicativi (`perito`, `segreteria`, `cat`, ecc.). Gli ulteriori conflitti ricevono un suffisso numerico.

## Edge Function

La funzione si trova in `supabase/functions/resend-inbound`.

Secret richiesti nel progetto Supabase:

```bash
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
RESEND_WEBHOOK_SECRET=...
```

La funzione e' pubblica a livello gateway (`verify_jwt = false`) perche' Resend non invia JWT Supabase. L'autenticazione applicativa avviene verificando la firma Svix/Resend sui header `svix-id`, `svix-timestamp` e `svix-signature`.

## Contratto daemon locale

Il daemon deve usare `X-PerX-Worker-Secret` con lo stesso valore configurato nel backend:

```bash
LOCAL_AI_WORKER_SHARED_SECRET=...
```

Nel worker Python esiste il client `perx_email_worker/services/cloud_queue_service.py`. Variabili lato daemon:

```bash
CLOUD_API_URL=https://api.perx.example
LOCAL_AI_WORKER_ID=mac-mini-local-ai
LOCAL_AI_WORKER_SHARED_SECRET=...
CLOUD_JOB_POLL_INTERVAL=5
```

Endpoint disponibili:

- `GET /api/v1/email-processing/jobs/claim?worker_id=<id>&limit=5`
- `POST /api/v1/email-processing/jobs/{job_id}/complete`
- `POST /api/v1/email-processing/jobs/{job_id}/fail`

Il claim usa lease temporanei e `FOR UPDATE SKIP LOCKED`, quindi in futuro possono girare piu' daemon senza processare lo stesso job in parallelo.

## Note operative

- Il webhook risponde appena l'email e' salvata e accodata: il processamento IA resta asincrono.
- `provider_event_id` e `inbound_event_id` garantiscono idempotenza sui retry Resend.
- Se il dominio destinatario non e' censito in `tenant_email_domains`, la funzione risponde `202 ignored` per evitare retry infiniti.
- Gli allegati per ora sono salvati come metadata nel payload. Il download/salvataggio su Storage va implementato nella fase daemon, usando l'API Resend Receiving se serve recuperare il contenuto completo.
