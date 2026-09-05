---
tags: [perx, funzionalita, videoperizia]
updated: 2026-09-05
---

# Videoperizia

Modalità di perizia da remoto via videochiamata, alternativa al sopralluogo fisico.

## Principio chiave

Videoperizia, sopralluogo e documentale **non vengono mai presentati insieme** all'assicurato:
condividono la stessa sezione del portale ma sono modalità alternative esclusive per quella
pratica (vedi [[06-Decisioni-e-Intenzioni-Future]]).

## Flusso

- Stato di ingresso: `videoperizia`, inizialmente con substato `da_fissare`.
- La UI mostra finestre da **30 minuti** e le indicazioni operative per preparare la chiamata.
- Il primo slot della giornata è configurabile dal tenant admin (default `10:00`).
- **Se la pratica ha già un perito incaricato**: il portale mostra solo le sue finestre di
  calendario libere; l'incarico resta con quel perito.
- **Se la pratica non ha un perito incaricato**: alle `09:00` del giorno scelto, il backend
  verifica i periti a calendario abilitati alla videoperizia, compatibili con compagnia e polizza,
  e assegna quello con minor carico attivo.
- L'assegnazione crea l'evento calendario, registra l'evento in timeline e invia
  all'assicurato una notifica e-mail con nome del perito e orario.
- **La videochiamata integrata nel portale non è coperta da questa prima implementazione** — vedi
  stato sotto.

## Abilitazione per singolo perito

Vive in `users.settings_json.video_inspection`:

```json
{
  "enabled": true,
  "companies": ["Compagnia Demo"],
  "excluded_policy_numbers": ["POL-123"]
}
```

## Componenti coinvolti

- **Backend**: `routes_videoperizia.py`; modello `videoperizia.py`; servizi
  `videoperizia_session_service.py`, `video_inspection_workflow_service.py`,
  `inspection_workflow_service.py`; `livekit_token_service.py` (token per la videochiamata, via
  **LiveKit**).
- **App PerX**: `Services/Videoperizia/`.
- **Portale assicurati**: sezione condivisa col sopralluogo — vedi [[Portal-Web-Assicurati]].
- **macOS**: finestra di chiamata flottante gestita da `Services/Windows/` nell'app principale.

## Comportamenti recenti implementati (da cronologia commit/migrazioni)

- Rilevamento di chiusura remota della chiamata con auto-chiusura su tutti e tre i client.
- Propagazione della fine sessione su hangup a tutti i client.
- Terminazione sessione lato backend quando chiamante o chiamato riaggancia.
- Fix stato chiamata, risposta a chiamata in arrivo su Mac, suonerie distinte.
- Finestra di chiamata flottante per macOS via `WindowManager`.
- Gestione disconnessione assicurato (`037_videoperizia_insured_disconnect.py`), consolidamento
  stato (`030_videoperizia_status_consolidation.py`), sessioni e media
  (`031_videoperizia_sessions_and_media.py`), location ping
  (`032_videoperizia_location_pings.py`).

## Stato

Implementata l'assegnazione, la schedulazione e la gestione sessione/chiamata end-to-end sui tre
client (app PerX, portale assicurati, presumibilmente riunioni/admin). La videochiamata
**integrata nel portale assicurati** come primissima esperienza resta esplicitamente fuori dalla
prima implementazione secondo la documentazione architetturale originale: verificare lo stato
corrente nel codice prima di assumere che sia ancora così, dato il volume di lavoro recente
sull'area (vedi [[05-Stato-Sviluppo-e-Roadmap]]).

---
Ultimo aggiornamento: 2026-09-05
