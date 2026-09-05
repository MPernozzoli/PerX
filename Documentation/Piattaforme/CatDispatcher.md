---
tags: [perx, piattaforma, web, catdispatcher]
updated: 2026-09-05
---

# CAT Dispatcher (`apps/catdispatcher`)

Piattaforma per l'assegnazione, il coordinamento e il monitoraggio geografico degli incarichi
peritali sul territorio nazionale, con focus sui **Centri di Assistenza Tecnica (CAT)** e sulle
reti di periti/tecnici sul campo. Nasce per sostituire assegnazioni manuali, mappe statiche e
fogli di calcolo con una visione unica di dove sono i sinistri, dove sono le risorse e come sono
distribuiti i carichi.

## Nuclei funzionali

1. **Mappatura territoriale**: visualizzazione geografica di periti/zone/aree operative.
2. **Gestione risorse**: anagrafica periti, associazione a province/regioni/cluster, attributi
   operativi, disponibilità.
3. **Supporto all'assegnazione**: individuazione della risorsa più adatta per zona, riduzione
   delle assegnazioni arbitrarie.
4. **Monitoraggio operativo**: visione del presidio territoriale, aree scoperte/sovraccariche.
5. **Evoluzioni previste**: dispatch automatico/semiassistito, analisi storica, dashboard di
   sintesi, integrazioni gestionali esterne.

## Integrazione con PerX

CatDispatcher è un frontend separato nella stessa repo, ma usa **il backend PerX** e lo stesso
database Supabase — nessun accesso diretto alle tabelle. Configura
`NEXT_PUBLIC_PERX_API_BASE_URL` e chiama solo `/api/v1/cat-dispatcher/*`.

Endpoint principali: `map-data`, `search`, `communes/{id}`, `get-cat-by-commune`,
`dispatch/requests`, `dispatch/insured-windows`, `dispatch/availability-rules`,
`dispatch/availability-overrides`, `dispatch/availability`, `dispatch/assignments`,
`dispatch/route-plans`. Elenco completo → [[Backend-Cloud-API]] / `backend/README.md`.

Il primo algoritmo di route planning è **volutamente deterministico** (ordina appuntamenti già
schedulati poi richieste per priorità): la struttura dati è pronta per sostituirlo con un
ottimizzatore geografico senza cambiare il contratto API.

## Stack

- Next.js 16 App Router (migrato da Vite/SPA — `react-router-dom` ancora presente come routing
  interno durante la transizione, vedi [[05-Stato-Sviluppo-e-Roadmap]]), React 18, TypeScript.
- Tailwind CSS + shadcn/UI su Radix UI.
- `@tanstack/react-query` per data fetching/cache.
- `maplibre-gl` + `@turf/*` per la componente mappa/geografica.
- `react-hook-form` + `zod` per i form, `recharts` per i grafici, `sonner` per le notifiche.

> Nota: il vecchio `README.md` del modulo cita ancora comandi Vite (`npm run dev` come "ambiente
> Vite"); è testo non aggiornato dopo la migrazione — gli script reali in `package.json` sono
> `next dev` / `next build` / `next start`.

## Stato e roadmap indicativa

Sviluppo attivo. Roadmap dichiarata: definizione modello territoriale → anagrafica risorse →
visualizzazione/interrogazione mappa → supporto assegnazione geografica → filtri/criteri dispatch
→ dashboard/analisi → integrazioni gestionali esterne. Vedi anche
[[05-Stato-Sviluppo-e-Roadmap]] per lo stato di integrazione nel gateway Vercel unico.

---
Ultimo aggiornamento: 2026-09-05
