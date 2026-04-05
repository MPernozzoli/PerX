# PerX Assicurati - Architettura iniziale

## Obiettivo

Realizzare un portale web dedicato agli assicurati, separato dall'area interna PerX ma collegato allo stesso dominio sinistri e allo stesso backend cloud.

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

- `GET /api/v1/portal/claim`
- `GET /api/v1/portal/claim/timeline`
- `GET /api/v1/portal/claim/documents`

La dashboard restituisce:

- macrostato assicurato derivato dallo stato interno `SVxxx`;
- dati essenziali del sinistro;
- perito assegnato e finestra di disponibilita;
- requisiti pendenti;
- prossimo appuntamento noto.

### 3. Interazioni

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
- Upload firmati storage predisposti ma non ancora collegati.

## Stato attuale

### Implementato

- backend `portal` con modelli, API, token flow e migration;
- web app dedicata con pagine, sessione locale e integrazione API;
- typecheck frontend completato;
- audit frontend pulito.

### Non ancora collegato

- invio e-mail automatico del magic link;
- OTP SMS;
- signed upload URL reali verso Supabase Storage;
- canalizzazione di risposte staff -> assicurato nella chat portale;
- antifrode forte per documentale fotografica.
