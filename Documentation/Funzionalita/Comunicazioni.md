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

Lato app c’è un solo polling, `HubEmailService`, verso `GET /api/v1/hub/emails`, con il token e l’email dell’account connesso. Al cambio account la lista e i thread in memoria si svuotano: non resta la posta dell’account precedente. La cache locale delle mail non viene più ridisegnata sopra l’elenco. Dal 2026-11-27 un salvataggio Core Data qualunque non ricarica più tutti i thread: il reload parte da `reloadThreads()` quando cambia la posta.
Gmail sul Mac e `MailManager` non scaricano più la posta. Il server, all’accesso Google, recupera
la posta in arrivo e inviata e poi le mail nuove. Se `GMAIL_PUBSUB_TOPIC` è impostato, Gmail
avvisa `POST /api/v1/emails/gmail/push` e lo scarico parte subito; altrimenti il server ricontrolla
ogni 90 secondi. Gli allegati fino a 15 MB finiscono nel bucket privato `perx-portal-uploads`
(prefisso `gmail/`). Le mail già entrate senza file vengono riprese a gruppi di 20 a ogni ciclo.
L’abbinamento alla pratica
è in cascata: prima il riferimento `26-602322`, poi il numero sinistro compagnia, poi il nome
dell’assicurato. L’invio dall’app usa Gmail se la casella è collegata, con la firma della casella,
altrimenti Resend. Il rinnovo del token sta sul server (`GOOGLE_OAUTH_CLIENT_ID` /
`GOOGLE_OAUTH_CLIENT_SECRET`). Il Mac interroga il backend ogni 60 secondi.
Il watch viene registrato prima del backfill. Il download di ogni allegato (push Pub/Sub e polling
usano lo stesso import) viene ritentato tre volte, con attese di 0,4 e 0,8 secondi. Se dopo i retry
Gmail o Storage non consegnano il file, oppure l’allegato supera i 15 MB o lo storage non è
configurato, la mail resta in elenco. In `emails.raw_headers` finiscono `attachmentsOnGmail`,
`attachmentsNotice` («Allegati non scaricati, apribili su Gmail.») e `gmailWebUrl`.
`GET /api/v1/hub/emails` e `GET /api/v1/hub/emails/detail/{id}` espongono gli stessi tre campi.
L’app Mac li mostra in lista e nel dettaglio, con il link per aprire il messaggio su Gmail.
Le sync successive riprendono le mail senza `attachmentsChecked`, a gruppi di 20, con lo stesso
download. Dopo tre passaggi falliti il recupero si ferma e l’avviso resta.
Il webhook Pub/Sub salva inoltre l’evento padre prima di accodare il relativo job, rispettando la
chiave esterna anche senza una relazione ORM esplicita tra i due modelli. I retry concorrenti
della stessa casella vengono serializzati con un lock sul record `Mailbox`; l’idempotenza viene
ricontrollata dopo il lock, evitando import simultanei della stessa email.
Una push autenticata viene sempre confermata a Pub/Sub: se Gmail o il database falliscono in modo
transitorio, il server registra `deferred` e lascia il recupero al polling ordinario, evitando una
tempesta di retry. Un singolo messaggio Gmail non leggibile viene saltato senza perdere il resto
della pagina o della history.

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
Ultimo aggiornamento: 2026-11-27 (retry allegati Gmail e avviso se restano su Gmail)
