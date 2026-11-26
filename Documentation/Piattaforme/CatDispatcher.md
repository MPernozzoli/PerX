---
tags: [perx, piattaforma, web, catdispatcher]
updated: 2026-11-26
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

CatDispatcher è un frontend separato nella stessa repo e usa **il backend PerX** e lo stesso
database Supabase. Configura `NEXT_PUBLIC_PERX_API_BASE_URL` e chiama `/api/v1/cat-dispatcher/*`.

> [!WARNING]
> Stato reale del codice (verificato 2026-11-26): le schermate `/`, `/admin`,
> `/admin/gis-editor` e `/api` (`apps/catdispatcher/src`) usano **ancora** il client Supabase con
> la chiave publishable e interrogano direttamente le tabelle `allowed_domains`, `cat_commune`,
> `cat_suspensions`, `cats`, `communes`, `geojson_backup_log`, `provinces`, `regions`, `tenants`,
> `user_roles`, `user_tenants` (più le RPC `get_user_role`, `find_commune_at_point`). Queste
> tabelle sono escluse dalla migrazione RLS `041_enable_rls_public` finché non migrano al backend
> o non hanno policy esplicite — vedi [[06-Decisioni-e-Intenzioni-Future]] (2026-11-26).

Endpoint principali: `map-data`, `search`, `communes/{id}`, `get-cat-by-commune`,
`dispatch/requests`, `dispatch/insured-windows`, `dispatch/availability-rules`,
`dispatch/availability-overrides`, `dispatch/availability`, `dispatch/assignments`,
`dispatch/route-plans`. Elenco completo → [[Backend-Cloud-API]] / `backend/README.md`.

Il primo algoritmo di route planning è **volutamente deterministico** (ordina appuntamenti già
schedulati poi richieste per priorità): la struttura dati è pronta per sostituirlo con un
ottimizzatore geografico senza cambiare il contratto API.

Dominio pubblico corrente: `catdispatcher.it`/`www.catdispatcher.it`. Target deciso il
2026-11-25: `catdispatcher.pynkstudio.eu`, mantenendo i domini storici come alias/redirect durante
la migrazione. Vedi [[06-Decisioni-e-Intenzioni-Future]].

Stato 2026-11-25: l'origin `catdispatcher.vercel.app` è distribuito e risponde HTTP 200; il
gateway e il manifest dell'estensione puntano al nuovo host. L'associazione Vercel è pronta, ma
manca il record DNS Register.it. Il dominio storico `catdispatcher.it` al momento non risolve.

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
Ultimo aggiornamento: 2026-11-25
