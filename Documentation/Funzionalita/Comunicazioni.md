---
tags: [perx, funzionalita, comunicazioni]
updated: 2026-11-27
---

# Comunicazioni

Gestione unificata delle comunicazioni legate a un sinistro: email, WhatsApp, Telegram, chiamate/
Webex, chat interna e chat verso l'assicurato. Il principio prodotto (da
`Documentation/Studio_Randa_Process_Deck.pptx`, 2026-06) è un **thread unificato per sinistro**:
ogni comunicazione — mail, messaggio, chiamata — viene collegata al sinistro di riferimento e
mostrata in una vista ibrida cronologica unica, indipendentemente dal canale. Una rubrica
integrata mantiene assicurati, agenzie, agenti e liquidatori sempre disponibili nel contesto del
sinistro.

## Componenti lato app (`PerX/Services/`, `PerX/Views/Comunicazioni/`)

- `Services/mail/`, `Views/Comunicazioni/Mail/` — client mail.
- `Services/whatsapp/`, `Views/Comunicazioni/WhatsApp/` — bridge WhatsApp (via PerXHub, vedi
  [[PerXHub]]).
- `Services/Chat/`, `Views/Comunicazioni/Messages/` — chat interna/messaggistica.

## Componenti lato backend

- `routes_communications.py` — API di comunicazione generiche.
- `routes_emails.py`, `routes_email_processing.py`, `routes_processed_emails_sync.py` — ricezione,
  elaborazione e sync delle email.
- `routes_whatsapp.py` — integrazione WhatsApp.
- `routes_internal_chat.py` — chat interna al team.
- `routes_realtime.py` — canale realtime (probabile base per notifiche/chat live).
- Servizi: `communication_service.py`, `communication_ai_triage.py` (triage assistito da AI),
  `communication_contact_resolver.py`, `communication_destination_resolver.py`,
  `communication_routing_engine.py`, `communication_extension_service.py`,
  `email_routing_service.py`, `resend_email_service.py`, `scheduled_email_service.py`,
  `user_email_service.py`.
- Modelli: `communication.py`, `email.py`, `internal_chat.py`.

## Email in ingresso/uscita

Provider **Resend**: invio via `RESEND_API_KEY`/`RESEND_DEFAULT_FROM_EMAIL`, scheduling opzionale
(`RESEND_SCHEDULED_EMAILS_ENABLED`). Pipeline di inbound documentata separatamente in
`backend/docs/resend_supabase_inbound_pipeline.md` (non ancora incorporata in questo vault — da
fare se questa pipeline viene toccata).

Lato app c’è un solo polling, `HubEmailService`, verso `GET /api/v1/hub/emails`, con il token e l’email dell’account connesso. Al cambio account la lista e i thread in memoria si svuotano: non resta la posta dell’account precedente. La cache locale delle mail non viene più ridisegnata sopra l’elenco.
Gmail sul Mac e `MailManager` non scaricano più la posta. Il server, all’accesso Google, recupera
la posta in arrivo e inviata e poi le mail nuove. Se `GMAIL_PUBSUB_TOPIC` è impostato, Gmail
avvisa `POST /api/v1/emails/gmail/push` e lo scarico parte subito; altrimenti il server ricontrolla
ogni 90 secondi. Gli allegati fino a 15 MB finiscono su Supabase Storage. L’abbinamento alla pratica
è in cascata: prima il riferimento `26-602322`, poi il numero sinistro compagnia, poi il nome
dell’assicurato. L’invio dall’app usa Gmail se la casella è collegata, con la firma della casella,
altrimenti Resend. Il rinnovo del token sta sul server (`GOOGLE_OAUTH_CLIENT_ID` /
`GOOGLE_OAUTH_CLIENT_SECRET`). Il Mac interroga il backend ogni 60 secondi.
Il watch viene registrato prima del backfill; un singolo allegato rifiutato da Storage viene
registrato nei log ma non blocca l’import della mail né il rinnovo del watch.
Il webhook Pub/Sub salva inoltre l’evento padre prima di accodare il relativo job, rispettando la
chiave esterna anche senza una relazione ORM esplicita tra i due modelli.

## Chat assicurato → team interno

Il portale assicurati non condivide le tabelle chat interne: i messaggi dell'assicurato vengono
**instradati verso un thread interno dedicato** tramite `communication_routing_engine.py` /
`communication_destination_resolver.py`. Vedi [[Portal-Web-Assicurati]]. La canalizzazione delle
risposte staff → assicurato nella chat portale **non è ancora collegata** (vedi
[[05-Stato-Sviluppo-e-Roadmap]]).

## Automazione sui canali (triage AI)

Mail, WhatsApp e Telegram vengono classificati automaticamente e generano il task corretto
(sollecito, documentazione pervenuta, ricontatto, contestazione, ecc. — vedi
[[Gestione-Sinistri]]); una chiamata o un Webex in agenda genera un evento collegato al sinistro.
Questo triage è responsabilità dell'agente AI applicativo **Elettra** — vedi
[[AI-Locale-e-Cloud]].

## Notifiche push

`push_notifier.py`, `apns_service.py`, `web_push_service.py`, modello `device_token.py`,
route `routes_devices.py` — notifiche push verso app native (APNs) e web.

---
Ultimo aggiornamento: 2026-11-27 (watch Gmail e push sull’API)
