---
tags: [perx, piattaforma, web, portale, assicurati]
updated: 2026-09-05
---

> [!note] Contratto API frontend↔backend riconciliato (2026-09-05)
> Fino a questa data `apps/portal-web/lib/api.ts`/`lib/types.ts` non corrispondevano al backend
> reale (URL, metodi, casing dei body tutti sbagliati) — vedi la voce datata in
> [[06-Decisioni-e-Intenzioni-Future]]. Ora sono allineati; `tsc --noEmit` è pulito su tutta l'app.

# Portale Web Assicurati (`apps/portal-web`)

Applicazione **Next.js App Router** dedicata agli assicurati, per consultare e gestire il proprio
sinistro senza passare dal team interno per ogni interazione. In produzione è pensata per
`assicurati.<dominio_tenant>` (e, secondo la regola del gateway unico, funge anche da progetto
Vercel principale — vedi [[04-Infrastruttura-e-Deploy]]).

## Routing multi-tenant

- Opera sul sottodominio `assicurati.[dominio_tenant]`; logica di auth/dashboard/documenti/
  IBAN/chat/sopralluogo/firma condivisa tra tutti i tenant.
- Il tenant viene risolto dal backend tramite la tabella `tenant_portal_domains`, popolata dalle
  impostazioni tenant `portal_domains`.
- Il frontend deriva lo stesso contesto dall'host della richiesta e carica un CSS tenant-specifico
  da `public/tenant-themes/{themeId}.css` (`themeId` = primo label del dominio, es.
  `assicurati.demo.it` → `demo.css`).

## Variabili ambiente principali

- `NEXT_PUBLIC_PORTAL_API_BASE_URL` — base URL del backend portale.
- `NEXT_PUBLIC_PORTAL_USE_MOCKS` — se `true`, usa dati demo e permette di navigare senza backend
  attivo.

## Componenti backend dedicati

- `backend/app/api/v1/routes_portal.py`, `routes_portal_me.py` — endpoint pubblici/autenticati.
- `backend/app/models/portal.py` — modelli dedicati al perimetro portale.
- `backend/app/core/portal_security.py` — token sessione e challenge, separati dall'auth interna.
- Tabelle introdotte: `portal_claim_accesses`, `portal_auth_challenges`,
  `portal_document_collection_submissions`, `portal_bank_account_submissions`,
  `portal_signature_requests`, `portal_conversations`, `portal_conversation_messages`.

## Flussi principali

1. **Accesso**: link generato da staff (`POST /api/v1/portal/claims/{id}/access-links`) →
   assicurato avvia challenge pubblico (`POST /api/v1/portal/auth/start`) → scambio magic link con
   sessione (`POST /api/v1/portal/auth/exchange`). In dev con
   `PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH=True` è possibile creare l'accesso al volo dal solo
   riferimento sinistro (solo sviluppo locale).
2. **Dashboard**: elenco sinistri accessibili, macrostato assicurato (mappato dagli stati interni
   `SVxxx`, mai esposto grezzo), dati essenziali, perito assegnato, prossimo appuntamento, quadro
   economico di base, stato atto.
3. **Fissazione sopralluogo**: stati di ingresso `SV052`/`SV053`; flusso in due passi — conferma
   indirizzo con pin/coordinate, poi selezione di finestre da due ore calcolate sui CAT
   compatibili con l'area (filtrando disponibilità/sopralluoghi/appuntamenti pendenti). Eventi
   timeline dedicati: `inspection_scheduling_requested`, `inspection_location_confirmed`,
   `inspection_preferences_confirmed`. Resta pending fino a conferma del motore appuntamenti.
4. **Interazioni**: upload intent documenti, documentale guidata, IBAN, chat (instradata verso
   thread interno dedicato, non condivide le tabelle chat interne), firma atto con challenge di
   conferma.
5. **Videoperizia**: stessa sezione del sopralluogo ma modalità alternativa esclusiva — dettaglio
   completo → [[Videoperizia]].

## Scelte architetturali

- Nessun accesso diretto del browser alle tabelle interne claims/documents/chat.
- Sessione portale separata dalla sessione degli utenti interni.
- Stato assicurato basato su mapping a macrostati, mai sugli `SVxxx` grezzi.
- Schedulazione sopralluogo agganciata al workflow CAT esistente e ai calendari interni.
- Upload documenti: se Supabase Storage è configurato, il browser carica direttamente su uno
  signed upload URL (`create_upload_intent` → `upload_mode: "signed-url"`), poi conferma con
  `POST /claim/documents/{id}/confirm-upload`; altrimenti fallback al proxy multipart esistente
  attraverso il backend (`upload_mode: "server-proxy"`).
- Antifrode fotografica: controllo offline non bloccante ad ogni upload immagine (EXIF/GPS
  confrontato con la posizione di sopralluogo confermata, hash percettivo per rilevare foto
  riciclate sullo stesso sinistro), risultato salvato in `Document.metadata_json.antifraud` per il
  perito. Dietro `FF_PORTAL_PHOTO_ANTIFRAUD_ENABLED` (default `True`).

## Stato

Vedi il dettaglio "Implementato / Non ancora collegato" in
[[05-Stato-Sviluppo-e-Roadmap]]. In sintesi: architettura, API, migration, contratto frontend↔backend
e web app sono implementati e verificati; invio e-mail del magic link, signed upload URL,
canalizzazione risposte staff→assicurato in chat e antifrode di base sono collegati. Resta fuori
scope solo l'OTP via SMS (nessun provider integrato).

---
Ultimo aggiornamento: 2026-09-05
