---
tags: [perx, stack, tecnologia]
updated: 2026-09-05
---

# Stack tecnologico

## App Apple (client nativo)

| Aspetto | Tecnologia |
| --- | --- |
| Linguaggio/UI | Swift, SwiftUI |
| Persistenza locale | CoreData (sinistri, `PerX.xcdatamodeld`), `UserDefaults` (task, settings) |
| Rete | `HubAPIAdapterClient` (HTTP verso backend cloud, refresh token automatico) |
| Pattern applicativo | Adapter (`TaskAdapter`, `ClaimAdapter`, `EmailAdapter`) per routing locale/hub/cloud |
| AI locale | Ollama, raggiunto solo tramite `PerX Local Agent` (XPC service, bundle `it.pernozzoli.PerX.LocalAgent`) |
| AI cloud | `CloudAIService` / `ClaudeAIService` (`Services/AI/`) |
| Distribuzione | Developer ID diretto, hardened runtime, no sandbox App Store |
| Moduli | `PerX/` (app principale, ~505 file Swift), `PerXCore/` (~17 file, modelli condivisi), `PerX Lite/` (~24, iPhone), `PerX per iPad/` (~46) |

Dettagli → [[PerX-App-Principale]], [[Varianti-iOS]].

## PerXHub (Mac mini)

| Aspetto | Tecnologia |
| --- | --- |
| Linguaggio/framework | Swift 5.9+, Vapor 4.x |
| Requisiti | macOS 14.0+ |
| Storage locale | SQLite (`vault.sqlite`) + vault documentale su filesystem |
| Deploy | LaunchDaemon (`/opt/perx-hub`, `com.perx.hub.plist`) |
| Integrazione dati | Supabase (service-role, solo lato server) |

Dettagli → [[PerXHub]].

## Backend cloud

| Aspetto | Tecnologia |
| --- | --- |
| Framework | FastAPI (Python) |
| ORM | SQLAlchemy async |
| Database | PostgreSQL (gestito su Supabase), migrazioni Alembic (41+ revisioni in `backend/migrations/versions/`) |
| Auth | JWT Bearer, hashing password in `app/core/security.py`; supporto opzionale a Supabase Auth (`FF_CLOUD_AUTH_ENABLED`) |
| Storage file | Supabase Storage (bucket `perx-portal-uploads`) |
| Email | Resend (invio/ricezione, pipeline webhook) |
| Deploy | Docker, hosting su Render (`render.yaml`, servizio `perx-api`) |
| Feature flag | `FF_TASKS_ENABLED`, `FF_LOCAL_AI_PROCESS_JOBS_ENABLED`, `SINGLE_TENANT_MODE`, `PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH`, ecc. |

Dettagli → [[Backend-Cloud-API]].

## Web app (monorepo `apps/*`)

| Aspetto | Tecnologia |
| --- | --- |
| Build system | Turborepo (`turbo.json`) + npm workspaces (`workspaces: ["apps/*"]`) |
| Framework | Next.js 16 App Router (tutte le app, dopo migrazione da Vite/SPA) |
| Linguaggio | TypeScript, React 18 |
| Routing legacy | `react-router-dom` ancora presente come client boundary temporaneo in alcune app durante la migrazione a route App Router native |
| UI kit | Tailwind CSS, componenti shadcn/UI su Radix UI (in CatDispatcher) |
| Data fetching | `@tanstack/react-query` |
| Mappe (CatDispatcher) | `maplibre-gl`, `@turf/*` |
| Deploy | Vercel, progetto singolo `perx` con Root Directory = root del repo |

Dettagli → [[Portal-Web-Assicurati]], [[CatDispatcher]], [[Altre-Web-App]], [[04-Infrastruttura-e-Deploy]].

## Dati condivisi

| Aspetto | Tecnologia |
| --- | --- |
| Database primario | PostgreSQL su Supabase, unico punto di accesso: backend FastAPI |
| Storage file | Supabase Storage |
| Edge functions Supabase | `find-policy`, `ai-extract-policy`, `resend-inbound`, `process-excel-import` (`supabase/functions/`) |
| Schemi dedicati per app satellite | es. `bignami` (Postgres schema separato da `public`) |

---
Ultimo aggiornamento: 2026-09-05
