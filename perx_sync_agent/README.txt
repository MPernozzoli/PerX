PerX Sync Agent (Windows)
=========================

Prerequisiti
------------
- Python 3.10+
- Accesso alla cartella del gestionale (es. `G:\Gestionale\Sinistri`)

Installazione
-------------
1. Apri PowerShell nella cartella `perx_sync_agent`.
2. Crea virtualenv:
   `python -m venv .venv`
3. Attiva:
   `.venv\Scripts\activate`
4. Installa dipendenze:
   `pip install -r requirements.txt`

Configurazione
--------------
1. Copia `config.example.env` in `.env` e personalizza:
   - `GESTIONALE_ROOT_PATH`: path radice sinistri.
   - `USER_MAPPING`: mapping `user_id=sottocartella` separato da `;`.
   - `API_TOKEN`: chiave per header `X-API-Key`.
   - `PORT`: porta di ascolto (default 8000).
   - `HUB_URL`: URL dell'Hub centralizzato (es. http://mac-mini.tailnet:8080).
2. Assicurati che la cartella `logs/` esista o sarà creata automaticamente.

Convenzione ID Utente (user_id)
-------------------------------
Il parametro `user_id` in tutte le API deve essere la **local-part dell'email**
dell'utente (es. `massimo.pernozzoli` per `massimo.pernozzoli@dominio.it`).

Questo stesso ID è usato in:
- Email worker (account_id)
- Hub heartbeat (user_id)

Questo permette la correlazione tra tutti i servizi PerX.

Avvio
-----
`python -m perx_sync_agent.main`

Endpoint principali
-------------------
- POST `/api/monitoring/register`
- POST `/api/monitoring/unregister`
- GET  `/api/claims/{claim_id}/metadata`
- GET  `/api/claims/{claim_id}/download`
- POST `/api/claims/{claim_id}/upload`
- GET  `/api/status/summary`
- GET  `/dashboard`

Note
----
- Logging su stdout + file rotanti in `logs/`.
- Watchdog opzionale per rilevare nuovi file e notificare l'app macOS.
- Download ZIP in streaming, gestione file fino a ~1.5 GB.

