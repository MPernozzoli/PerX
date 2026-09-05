---
tags: [perx, funzionalita, sinistri]
updated: 2026-09-05
---

# Gestione sinistri

Funzionalità centrale della piattaforma: copre l'intero ciclo di vita di un sinistro property,
dalla presa in carico alla chiusura pratica.

## Modello di stato

I sinistri seguono una macchina a stati con codici interni **`SVxxx`** (es. `SV052` sopralluogo da
fissare, `SV053` sopralluogo da concordare). Il portale assicurati non espone mai gli `SVxxx`
grezzi: li traduce in **macrostati** più leggibili per l'utente finale (vedi
[[Portal-Web-Assicurati]]).

Gli stati principali "umani" del ciclo di vita (documentati fin dal disegno originale del 2024 in
`Documentation/Workflow PerX.pdf` e `Documentation/Workflow PerX AI.pdf`, materiale di
riferimento conservato nel vault) sono:

`Da scaricare` (incarico ricevuto) → `Da gestire` (documenti verificati) → `In gestione`
(lavorazione attiva) → `Atto inviato` (in firma) → `Atto ricevuto` (atto firmato) → `Chiusa`
(concordata / non concordata).

Stati di attesa/deviazione, ognuno dei quali genera automaticamente un **task di sollecito a 7
giorni** così che nessuna pratica resti ferma senza un'azione pianificata:
`In Attesa Polizza`, `In Attesa Foto`, `In Attesa Documentazione`, `Revocato`.

### Automazioni sugli eventi mail (disegno originale, da verificare rispetto all'implementazione corrente)

- Mail di sollecito in ingresso → genera task di sollecito.
- Mail con documentazione/foto/polizza → rimuove il task di sollecito e genera task
  "documentazione pervenuta".
- Mail con richiesta di ricontatto → genera task "ricontatto".
- Mail con contestazione/richiesta chiarimenti sull'atto (stato `atto inviato`) → genera task
  "gestisci contestazione".
- Mail con atto firmato (stato `atto ricevuto`) → genera task "chiudere a sistema".
- Mail di incarico revocato → genera report dello stato di avanzamento e task "comunica report".
- Bozze di risposta generate dall'AI per le mail non automatiche, con approvazione/modifica
  dell'utente prima dell'invio; le impostazioni AI definiscono a quali tipi di mail rispondere in
  automatico. Vedi anche [[AI-Locale-e-Cloud]] (agente "Elettra").

### Fulminazione integrata (verifica automatica fenomeno elettrico)

Per i sinistri da fenomeno elettrico, PerX integra una verifica geospaziale automatica delle
scariche atmosferiche Cloud-to-Ground nei **10 km e 11 giorni** intorno a data/luogo del sinistro,
eseguita prima del sopralluogo (fonte: pitch deck `Documentation/Studio_Randa_Process_Deck.pptx`,
2026-06 — vedi anche [[Altre-Web-App]] per il contesto "Studio Randa").

### Authority check

La perizia elaborata include un controllo automatico ("authority check") e una verifica di
conformità ai protocolli della compagnia mandante prima dell'invio dell'atto: se l'importo
richiede un passaggio al controllore, il sistema lo segnala (fonte: stesso pitch deck).

## Componenti coinvolti

- **App PerX principale**: gestione completa della pratica (`Views/Sinistri/` con sotto-sezioni
  `Perizia`, `ElaboratoCalcoli`, `Detail`, `Cartella`; `Services/Claims/`). Vedi
  [[PerX-App-Principale]].
- **Backend**: `routes_claims.py` (CRUD sinistro, transizioni di stato, timeline eventi),
  `routes_actors.py`, `routes_documents.py`, `routes_folder_packages.py`,
  `routes_attachments.py`, `routes_diary.py` (diario di lavorazione), `routes_inspections.py`
  (sopralluoghi). Modelli: `claim.py`, `claim_state.py`, `claim_event.py`,
  `claim_assignment.py`, `claim_diary_entry.py`, `claim_folder.py`, `claim_photo_analysis.py`.
  Vedi [[Backend-Cloud-API]].
- **PerXHub**: vault documentale su filesystem per i file del sinistro, organizzato per
  riferimento pratica (`da_mail/`, `da_whatsapp/`, `documenti/`, `perizia/`, `atti/`, `gestione/`,
  `_export/`). Vedi [[PerXHub]].
- **Portale assicurati**: dashboard, timeline, documenti, IBAN, chat, firma atto — vedi
  [[Portal-Web-Assicurati]].
- **CAT Dispatcher**: assegnazione del perito/CAT più adatto per zona, gestione appuntamenti di
  sopralluogo — vedi [[CatDispatcher]].

## Endpoint principali (sintesi)

- `GET/POST /api/v1/claims`, `GET/PUT /api/v1/claims/{id}`
- `POST /api/v1/claims/{id}/state-transitions`
- `GET /api/v1/claims/{id}/events` (timeline)

Elenco completo → [[Backend-Cloud-API]] / `backend/README.md`.

## Analisi AI su sinistro

`claim_photo_analysis.py` e i servizi in `Services/AI/` (lato app) e `routes_ai_chat.py` /
`routes_ai_prompts.py` (lato backend) supportano analisi assistita da AI su foto e comunicazioni
legate al sinistro (es. job `local_ai.diary_entry_analysis` accodato per comunicazioni/allegati).
Vedi [[AI-Locale-e-Cloud]].

---
Ultimo aggiornamento: 2026-09-05
