---
tags: [perx, piattaforma, web]
updated: 2026-09-05
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
  `https://bignami.perx.it`).
- Lo schema `bignami` deve essere esposto nella Data API di Supabase e avere grant/RLS applicati
  dalle migrazioni PerX.
- Stack: Next.js App Router (migrato da Vite, `react-router-dom` ancora presente), React,
  TypeScript.
- Dominio previsto: `bignami.perx.it`, da integrare nel gateway se deve condividere SSO/policy con
  gli altri portali (vedi [[05-Stato-Sviluppo-e-Roadmap]]).

## PerX Insight Studio (`apps/perx-insight-studio`)

App con proprie `supabase/migrations` e `supabase/functions` dedicate (in
`apps/perx-insight-studio/supabase/`), quindi con un perimetro dati più autonomo rispetto alle
altre app satellite. Struttura interna: `src/app`, `src/screens`, `src/integrations`,
`src/components`, `src/hooks`, `src/lib`. Stack: Next.js 16 App Router, React 18, TypeScript
(migrata da Vite come le altre). Dominio previsto: dominio marketing PerX; secondo
`web-portals-next-vercel` può restare come progetto Next.js separato invece di confluire nel
gateway unico.

> Contenuto funzionale non ancora documentato in dettaglio in questo vault: se lavori su questa
> app, aggiungi qui una descrizione di cosa fa concretamente (nome "Insight Studio" suggerisce
> analisi/reportistica, da confermare leggendo `src/screens`).

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
Ultimo aggiornamento: 2026-09-05
