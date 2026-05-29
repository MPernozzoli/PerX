# Resend + Supabase inbound email pipeline

Questa infrastruttura sostituisce il vecchio worker IMAP/SMTP. Resend diventa il punto di ingresso e uscita per le email dei tenant e per le comunicazioni interne.

```text
Resend email.received webhook
  -> Supabase Edge Function resend-inbound
  -> inbound_email_events + email_processing_jobs
  -> Supabase/Postgres + client realtime/automatismi
```

## Tabelle

- `tenant_email_domains`: domini email gestiti per tenant. Per Resend inbound deve contenere il dominio destinatario, ad esempio `cliente.com` o `mail.cliente.com`.
- `email_aliases`: indirizzi operativi virtuali, assegnati a utenti, team, sinistri o bucket. Gli alias utente vengono mantenuti automaticamente quando cambia la mail professionale.
- `inbound_email_events`: copia normalizzata e raw del webhook Resend.
- `email_processing_jobs`: coda persistente per processamento asincrono lato backend/automazioni.

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

## Invio email

L'invio immediato deve passare dal backend/Resend, non da worker locali. Configurare `RESEND_API_KEY` e `RESEND_DEFAULT_FROM_EMAIL`; la compat route `/api/v1/hub/emails/send` invia via Resend e registra l'evento outbound su `emails` con `provider_id` valorizzato con l'id Resend.

Le email programmate sono persistite come `scheduled` e inviate dal runtime backend `ScheduledEmailRuntime`, sempre tramite lo stesso servizio Resend usato dall'invio immediato. Variabili operative: `RESEND_SCHEDULED_EMAILS_ENABLED`, `RESEND_SCHEDULED_EMAIL_POLL_SECONDS`, `RESEND_SCHEDULED_EMAIL_BATCH_SIZE`.

## Note operative

- Il webhook risponde appena l'email e' salvata e accodata: il processamento resta asincrono.
- `provider_event_id` e `inbound_event_id` garantiscono idempotenza sui retry Resend.
- Se il dominio destinatario non e' censito in `tenant_email_domains`, la funzione risponde `202 ignored` per evitare retry infiniti.
- Gli allegati per ora sono salvati come metadata nel payload. Il download/salvataggio su Storage va implementato lato backend, usando l'API Resend Receiving se serve recuperare il contenuto completo.
