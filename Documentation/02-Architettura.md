---
tags: [perx, architettura]
updated: 2026-09-05
---

# Architettura

## Principi guida

1. **Il backend FastAPI è l'unica autorità sui dati applicativi.** Nessun client (app iOS, web
   app satellite, PerXHub) accede direttamente alle tabelle Postgres: passa sempre da
   un'API `/api/v1/...`. Vedi [[Backend-Cloud-API]].
2. **Postgres gestito su Supabase, ma non "alla Supabase".** Il database primario gira su
   Supabase Postgres, però viene raggiunto solo dal backend via SQLAlchemy async + migrazioni
   Alembic (`backend/migrations/`) usando `DATABASE_URL`. I client non usano l'SDK Supabase per
   leggere/scrivere dati applicativi PerX.
   Supabase viene invece usato direttamente per: **storage file** (bucket
   `perx-portal-uploads`), alcune **edge functions** (`find-policy`, `ai-extract-policy`,
   `resend-inbound`, `process-excel-import`), e come **database dedicato con schema separato**
   per un paio di app satellite (es. Bignami usa lo schema Postgres `bignami`, non `public`, per
   non collidere con le tabelle PerX). Le credenziali service-role restano solo lato server
   (backend, PerXHub) e non vengono mai condivise con i client.
3. **PerXHub è il nodo operativo locale**, non il source of truth. Vive su un Mac mini, possiede
   il vault documentale su filesystem, gestisce job di import/export/scan e fa da bridge verso
   servizi locali (AI locale, WhatsApp). Il dato applicativo resta su Supabase/Postgres via
   backend. Vedi [[PerXHub]].
4. **Un solo gateway web per dominio.** Tutti i portali web pubblici sono Next.js App Router e,
   dove possibile, confluiscono in un unico progetto Vercel (`apps/portal-web`) che risolve
   tenant/prodotto dall'host della richiesta. Vedi [[04-Infrastruttura-e-Deploy]].
5. **Pattern adapter lato iOS.** L'app nativa instrada le operazioni (task, sinistri, email) verso
   locale, hub o cloud tramite adapter dedicati (`TaskAdapter`, `ClaimAdapter`, `EmailAdapter`),
   così la UI non dipende da dove il dato è effettivamente servito. Vedi [[PerX-App-Principale]].
6. **Il lavoro pesante/locale non blocca l'API.** Quando serve una capacità del Mac mini (es. AI
   locale via modello MLX), il backend accoda un record in `process_jobs`; il worker locale lo
   prende in lease, esegue e restituisce il risultato. Vedi [[Backend-Cloud-API]].
7. **Confini di sicurezza per il portale assicurati.** Il portale ha sessioni, token e modelli
   dati separati da quelli degli utenti interni; la chat assicurato è instradata verso un thread
   interno dedicato invece di condividere le tabelle chat interne. Vedi [[Portal-Web-Assicurati]].

## Flusso dati (vista semplificata)

```
                         ┌───────────────────────────┐
                         │   Backend FastAPI (cloud) │
                         │  SQLAlchemy async + Alembic│
                         └─────────────┬─────────────┘
                                        │ /api/v1/*
        ┌───────────────┬──────────────┼───────────────┬────────────────┐
        │               │              │               │                │
        ▼               ▼              ▼               ▼                ▼
┌───────────────┐ ┌───────────┐ ┌─────────────┐ ┌──────────────┐ ┌──────────────┐
│  App PerX iOS/ │ │  PerXHub  │ │ portal-web  │ │ catdispatcher│ │ altre web app│
│  macOS/iPad    │ │ (Mac mini)│ │ (assicurati)│ │  (periti)    │ │ (Bignami,    │
│  + adapter     │ │ vault +   │ │             │ │              │ │ Insight...)  │
│  locale/cloud  │ │ job + AI  │ │             │ │              │ │              │
└───────┬────────┘ └─────┬─────┘ └─────────────┘ └──────────────┘ └──────────────┘
        │                │
        ▼                ▼
  CoreData/UserDefaults  Vault filesystem + Ollama (via Local Agent XPC)
     (cache locale)         (dipendenze locali macOS)

Postgres/Supabase = database primario dietro al backend.
Supabase Storage = file (bucket perx-portal-uploads) + schemi dedicati per app satellite.
```

## Multi-tenant

Il modello dati supporta multi-tenant (`tenant_id` su `users`, `tenant_portal_domains`, ecc.), ma
la messa in produzione iniziale gira in **single-tenant mode** (`SINGLE_TENANT_MODE=True`, un solo
tenant creato via `scripts/bootstrap_single_tenant.py`). Vedi [[05-Stato-Sviluppo-e-Roadmap]].

## Identità e autenticazione

Oggi ogni app fa login autonomo verso `/api/v1/auth/login` (JWT Bearer). È pianificato un identity
layer unico (`login.perx.it`, OAuth2/OIDC + PKCE) per SSO tra app PerX, admin, CatDispatcher e
futuri servizi — vedi [[Login-Unificato-SSO]] per lo stato (pianificazione, non ancora
implementato).

---
Ultimo aggiornamento: 2026-09-05
