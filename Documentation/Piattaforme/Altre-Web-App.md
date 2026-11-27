---
tags: [perx, piattaforma, web]
updated: 2026-11-26
---

# Altre web app satellite

App Next.js più piccole o meno "core" rispetto a [[Portal-Web-Assicurati]] e [[CatDispatcher]],
ma parte dello stesso monorepo/deploy Vercel (vedi [[04-Infrastruttura-e-Deploy]]).

## Bignami Online (`apps/bignami-online`)

Web app per consultare e gestire i "bignami" di polizza (riassunti/condizioni polizza).

- Usa lo **stesso progetto Supabase/Postgres** di PerX, ma le tabelle vivono nello schema
  dedicato **`bignami`** (non `public`), per non collidere con le tabelle applicative PerX.
- Variabili chiave: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`,
  `NEXT_PUBLIC_SUPABASE_DB_SCHEMA=bignami`, `NEXT_PUBLIC_SITE_URL` (produzione:
  `https://bignami.perx.it`; alias secondario: `https://bignamionline.pynkstudio.eu`).
- Lo schema `bignami` deve essere esposto nella Data API di Supabase e avere grant/RLS applicati
  dalle migrazioni PerX.
- Stack: Next.js App Router (migrato da Vite, `react-router-dom` ancora presente), React,
  TypeScript.
- Dal 2026-11-07 il client e i tipi generati puntano coerentemente allo schema `bignami` (incluse
  le mutation tipizzate); il typecheck globale è tornato verde.
- Dominio principale: `bignami.perx.it`; `bignamionline.pynkstudio.eu` resta alias secondario
  instradato dallo stesso gateway per condividere SSO/policy con gli altri portali (vedi
  [[05-Stato-Sviluppo-e-Roadmap]] e [[06-Decisioni-e-Intenzioni-Future]]).
- Dal 2026-11-25 l'origin Vercel `bignami-online.vercel.app` è in produzione e il gateway è
  configurato per inoltrarlo. Il canonical dell'app punta a `bignami.perx.it`.

## PerX Insight Studio (`apps/perx-insight-studio`)

Landing marketing di PerX (`perx.it` e alias collegati).

- **Home (`/`)** — presentazione brand + CTA verso il percorso e il contatto.
- **Come funziona (`/come-funziona`)** — storytelling di **una sola pratica inventata**
  (`PX-2026-0847`, danno da acqua a Padova): elenco → dettaglio → bignami → Studio/Team →
  Cat Dispatcher → portale → PerX Lite → elaborato calcoli.
- Le interfacce nel percorso sono **screenshot delle app reali** (dati demo), non clone HTML.
  Brief e numeri in `src/content/pratica-demo.ts`; PNG in `src/assets/story/` registrati in
  `src/components/story/story-assets.ts`.
- Form contatto (`info@perx.it`) e newsletter su Supabase dedicato
  (`apps/perx-insight-studio/supabase/`), client opzionale se mancano le env pubbliche.
- Struttura: `src/app`, `src/screens`, `src/components/story/`, `src/content/`,
  `src/integrations`. Stack: Next.js 16 App Router, React 18, TypeScript.
- Progetto Vercel separato rispetto al gateway portale (vedi [[04-Infrastruttura-e-Deploy]]).

## Randa / Studio Randa (`apps/randa`)

App Next.js 16 App Router minimale (`@supabase/supabase-js`, `@tanstack/react-query`,
`react-router-dom`, `zod`). Dominio previsto `randapro.it`. **Non ha un proprio `README.md`** nel
repo, ma il suo contesto è chiarito da un materiale di riferimento presente nel vault:
`Documentation/Studio_Randa_Process_Deck.pptx` (pitch deck datato 2026-06).

**Studio Randa** è uno **studio peritale specializzato in sinistri property**, con focus specifico
sulla garanzia da **fenomeno elettrico**, che opera con una rete di periti e tecnici (CAT)
coordinata sul territorio nazionale ed è interlocutore diretto delle compagnie mandanti. La sua
intera operatività gira su PerX ("PerX è la piattaforma operativa dello studio"). `apps/randa` è
quindi presumibilmente il **sito vetrina/commerciale di Studio Randa** (per presentarsi alle
compagnie mandanti), non un prodotto assicurativo separato — da confermare leggendo il codice di
`apps/randa/src` se questa nota va approfondita ulteriormente.

Il deck descrive anche, a livello di prodotto/marketing, l'intera value proposition di PerX
lato Studio Randa: piattaforma unica (app perito, hub comunicazioni, portale assicurati, AI
"Elettra & Sparky" — vedi [[AI-Locale-e-Cloud]]), ciclo di vita del sinistro tracciato (vedi
[[Gestione-Sinistri]]), vantaggi dichiarati verso la compagnia mandante: tempi certi, qualità
costante, scalabilità e trasparenza.

---
Ultimo aggiornamento: 2026-11-26
