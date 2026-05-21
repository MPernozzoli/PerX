# PerX Assicurati - Architettura iniziale

## Obiettivo

Realizzare un portale web dedicato agli assicurati, separato dall'area interna PerX ma collegato allo stesso dominio sinistri e allo stesso backend cloud.

## Routing tenant

Il portale assicurati opera sul sottodominio `assicurati.[dominio_tenant]`.
La logica di autenticazione, dashboard, documenti, IBAN, chat, sopralluogo e firma resta condivisa tra tutti i tenant.
Il tenant viene risolto dal backend tramite la tabella `tenant_portal_domains`, popolata dalle impostazioni tenant `portal_domains`.

Il front-end Next.js deriva lo stesso contesto dall'host della richiesta e carica un CSS tenant-specifico da
`portal-web/public/tenant-themes/{themeId}.css`. In questo modo i processi restano comuni e ogni tenant puo avere stile, colori e brand gestiti in un file separato.

## Componenti introdotti

- `portal-web/`
  Applicazione Next.js dedicata agli assicurati.
- `backend/app/api/v1/routes_portal.py`
  Endpoint pubblici e autenticati del portale.
- `backend/app/models/portal.py`
  Modelli dati dedicati al perimetro portale.
- `backend/app/core/portal_security.py`
  Token sessione e challenge separati dall'autenticazione interna.
- `backend/migrations/versions/003_portal_architecture.py`
  Migration iniziale del dominio portale.

## Flussi coperti

### 1. Accesso iniziale e accessi successivi

- Access link interno generabile via API staff:
  - `POST /api/v1/portal/claims/{claim_id}/access-links`
- Accesso pubblico:
  - `POST /api/v1/portal/auth/start`
- Scambio magic link -> sessione:
  - `POST /api/v1/portal/auth/exchange`

Per ora il canale outbound reale non viene inviato: il backend genera challenge e link ed espone la preview in ambiente di sviluppo.

### 2. Dashboard assicurato

- `GET /api/v1/portal/claims`
- `GET /api/v1/portal/claim`
- `GET /api/v1/portal/claim/timeline`
- `GET /api/v1/portal/claim/documents`

La dashboard restituisce:

- elenco di tutti i sinistri accessibili allo stesso assicurato, anche senza azioni pendenti;
- macrostato assicurato derivato dallo stato interno `SVxxx`;
- dati essenziali del sinistro;
- perito assegnato e finestra di disponibilita;
- requisiti pendenti;
- prossimo appuntamento noto;
- quadro economico di base e stato atto.

### 3. Fissazione sopralluogo

- Stato di ingresso:
  - `SV052` sopralluogo da fissare
  - `SV053` sopralluogo da concordare
- Endpoint portale:
  - `GET /api/v1/portal/claim/inspection-scheduling`
  - `PUT /api/v1/portal/claim/inspection-scheduling/location`
  - `PUT /api/v1/portal/claim/inspection-scheduling/preferences`

Il flusso lato assicurato e strutturato in due passaggi:

- conferma indirizzo sopralluogo con punto esatto di incontro, coordinate e dati territoriali;
- selezione di una o piu finestre da due ore calcolate sui CAT compatibili con quell'area, filtrando disponibilita, sopralluoghi fissati e appuntamenti gia in pending.

Il sistema salva le preferenze nel metadata workflow del sinistro, registra eventi dedicati in timeline (`inspection_scheduling_requested`, `inspection_location_confirmed`, `inspection_preferences_confirmed`) e rimane in stato pending fino alla conferma dell'appuntamento da parte del motore appuntamenti.

### 4. Interazioni

- Upload intent documenti:
  - `POST /api/v1/portal/claim/upload-intents`
- Documentale guidata:
  - `POST /api/v1/portal/claim/document-collection-submissions`
- IBAN:
  - `POST /api/v1/portal/claim/bank-accounts`
- Chat:
  - `GET /api/v1/portal/claim/chat/messages`
  - `POST /api/v1/portal/claim/chat/messages`
- Firma atto:
  - `POST /api/v1/portal/claim/signature-requests`
  - `POST /api/v1/portal/claim/signature-requests/{id}/confirm`

## Tabelle introdotte

- `portal_claim_accesses`
- `portal_auth_challenges`
- `portal_document_collection_submissions`
- `portal_bank_account_submissions`
- `portal_signature_requests`
- `portal_conversations`
- `portal_conversation_messages`

## Scelte architetturali

- Nessun accesso diretto del browser alle tabelle interne claims/documents/chat.
- Sessione portale separata dalla sessione utenti interni.
- Chat assicurato separata dalla chat interna, con instradamento verso thread interno dedicato.
- Stato assicurato basato su mapping a macrostati, non sugli `SVxxx` grezzi.
- Schedulazione sopralluogo portale agganciata al workflow CAT esistente e ai calendari interni.
- Upload firmati storage predisposti ma non ancora collegati.

## Stato attuale

### Implementato

- backend `portal` con modelli, API, token flow e migration;
- web app dedicata con pagine, sessione locale e integrazione API;
- schedulazione sopralluogo con conferma posizione, pin interattivo e selezione multi-slot;
- typecheck frontend completato;
- audit frontend pulito.

### Non ancora collegato

- invio e-mail automatico del magic link;
- OTP SMS;
- signed upload URL reali verso Supabase Storage;
- canalizzazione di risposte staff -> assicurato nella chat portale;
- antifrode forte per documentale fotografica.
