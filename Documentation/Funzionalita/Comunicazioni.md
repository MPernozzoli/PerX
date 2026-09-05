---
tags: [perx, funzionalita, comunicazioni]
updated: 2026-09-05
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
Ultimo aggiornamento: 2026-09-05
