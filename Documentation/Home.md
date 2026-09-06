---
tags: [perx, moc]
updated: 2026-09-06
---

# PerX — Vault di documentazione

> [!important] Regola per chiunque (persona o IA) lavori su questo repo
> Questo vault è la **fonte di verità** su architettura, funzionalità e stato di avanzamento di PerX.
> Ogni modifica al codice, ogni decisione presa e ogni intenzione di sviluppo futuro discussa con l'utente
> **deve** riflettersi qui, nello stesso giro di lavoro in cui viene fatta o discussa.
> Regole complete e checklist → **[[Istruzioni-AI-Agenti]]**.

## Cos'è PerX

PerX è una piattaforma operativa per studi peritali e strutture tecniche che gestiscono sinistri
property, con forte focus su gestione documentale, flussi operativi e supporto AI al lavoro del
perito. È organizzata come monorepo: app iOS/macOS/iPad, un hub Mac mini, un backend cloud FastAPI
e diverse web app satellite (portale assicurati, dispatch CAT, ecc.).

Dettagli → [[01-Panoramica]].

## Indice

### Fondamenta
- [[01-Panoramica]] — cos'è PerX, moduli del monorepo, a chi si rivolge
- [[02-Architettura]] — principi architetturali, flusso dati, confini tra i componenti
- [[03-Stack-Tecnologico]] — linguaggi, framework, database, hosting per ogni componente
- [[04-Infrastruttura-e-Deploy]] — Vercel, Render, Supabase, Docker, domini
- [[05-Stato-Sviluppo-e-Roadmap]] — cosa è implementato, cosa è in corso, cosa manca
- [[06-Decisioni-e-Intenzioni-Future]] — log datato di decisioni architetturali e intenzioni discusse con l'utente

### Piattaforme e componenti
- [[PerX-App-Principale]] — app macOS/iPad principale (Swift/SwiftUI) + PerXCore
- [[Varianti-iOS]] — PerX Lite (iPhone) e PerX per iPad
- [[PerXHub]] — daemon Mac mini (Vapor): vault documentale, job, monitor, local agent
- [[Backend-Cloud-API]] — backend FastAPI/PostgreSQL, cuore dei dati e delle API
- [[Portal-Web-Assicurati]] — portale self-service per gli assicurati (Next.js)
- [[CatDispatcher]] — piattaforma di dispatch geografico dei periti (Next.js)
- [[Altre-Web-App]] — Bignami Online, PerX Insight Studio, Randa
- [[PerX-Lite-Extension]] — estensione Chrome standalone: Excel → compilazione pagina JFish

### Funzionalità trasversali
- [[Gestione-Sinistri]] — ciclo di vita del sinistro, stati SVxxx, documentale
- [[Comunicazioni]] — mail, WhatsApp, chat interna/esterna, routing
- [[Sistema-Task]] — task locali (iOS) + task server condivisi, sync offline-first
- [[AI-Locale-e-Cloud]] — AI locale (Ollama via Local Agent XPC) e AI cloud
- [[Videoperizia]] — perizia da remoto via videochiamata
- [[Login-Unificato-SSO]] — identity layer unico pianificato (`login.perx.it`)

---
Ultimo aggiornamento: 2026-09-06
