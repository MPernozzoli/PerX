---
tags: [perx, panoramica]
updated: 2026-09-05
---

# Panoramica

PerX è una piattaforma operativa per **studi peritali e strutture tecniche** che gestiscono
sinistri property (danni a immobili/beni assicurati). Copre l'intero ciclo di vita di una
pratica: apertura sinistro, gestione documentale, comunicazioni con assicurato/compagnia/CAT,
sopralluogo o videoperizia, redazione atti e consuntivo, con supporto AI trasversale al lavoro
del perito.

Il progetto è nato a fine 2024 ed è in **sviluppo attivo** con uso interno controllato; la
struttura della repo evolve iterativamente (prototipazione → sviluppo → validazione su casi
reali). Vedi [[05-Stato-Sviluppo-e-Roadmap]] per il dettaglio.

## Struttura del monorepo

La repo contiene sia l'applicazione nativa Apple sia una costellazione di servizi cloud e web:

| Cartella | Cos'è |
| --- | --- |
| `PerX/` | App principale macOS/iPad (Swift/SwiftUI) — vedi [[PerX-App-Principale]] |
| `PerX per iPad/`, `PerX Lite/` | Varianti iOS — vedi [[Varianti-iOS]] |
| `PerXCore/` | Modelli e logica condivisa tra i target Apple |
| `PerXHub/`, `PerXHubMonitor/` | Daemon Mac mini e suo monitor — vedi [[PerXHub]] |
| `PerXLocalAgentService/`, `PerXLocalAgentShared/` | Servizio XPC per dipendenze locali (Ollama, script Python) — vedi [[AI-Locale-e-Cloud]] |
| `backend/` | Backend cloud FastAPI — vedi [[Backend-Cloud-API]] |
| `apps/portal-web/` | Portale web assicurati — vedi [[Portal-Web-Assicurati]] |
| `apps/catdispatcher/` | Dispatch geografico periti — vedi [[CatDispatcher]] |
| `apps/bignami-online/`, `apps/perx-insight-studio/`, `apps/randa/` | Web app satellite — vedi [[Altre-Web-App]] |
| `supabase/` | Configurazione progetto Supabase condiviso (storage, edge functions) |

Ogni componente più complesso ha (o può avere) un proprio `README.md` locale con istruzioni
pratiche di setup/build; i contenuti architetturali e di prodotto vivono invece in questo vault
(regola in [[Istruzioni-AI-Agenti]]).

## A chi si rivolge

- Periti e strutture tecniche che gestiscono sinistri property su incarico di compagnie
  assicurative.
- Centri di Assistenza Tecnica (CAT) e reti di tecnici sul territorio ([[CatDispatcher]]).
- Assicurati, tramite il portale self-service ([[Portal-Web-Assicurati]]).

**Studio Randa** è il contesto cliente/utente di riferimento documentato nel vault: uno studio
peritale specializzato in sinistri property (focus fenomeno elettrico) che opera interamente su
PerX. Vedi [[Altre-Web-App]] per il dettaglio e la fonte.

## Materiali di riferimento

Oltre alle note di questo vault, `Documentation/` conserva alcuni materiali sorgente non
testuali, citati dalle note pertinenti:

- `Workflow PerX.pdf`, `Workflow PerX AI.pdf` — diagrammi originali (2024-11) del workflow stati/
  task del sinistro, base di [[Gestione-Sinistri]].
- `Studio_Randa_Process_Deck.pptx` — pitch deck di prodotto (2026-06), base di più sezioni tra cui
  [[AI-Locale-e-Cloud]], [[Comunicazioni]], [[Altre-Web-App]].

Se questi materiali cambiano o ne arrivano di nuovi, aggiorna questa lista e le note che li citano
(vedi [[Istruzioni-AI-Agenti]]).

## Riservatezza

Il repository contiene codice, dati modello e concetti proprietari dello studio. Il contenuto non
è liberamente riutilizzabile né redistribuibile senza autorizzazione esplicita.

---
Ultimo aggiornamento: 2026-09-05
