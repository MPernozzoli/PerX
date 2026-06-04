# Bignami Online

Web app React/Vite per consultare e gestire i bignami di polizza.

## Integrazione PerX

Questo progetto usa lo stesso progetto Supabase/Postgres di PerX. Le tabelle
Bignami vivono nello schema Postgres `bignami`, cosi' non collidono con le
tabelle applicative PerX in `public`.

Configura l'ambiente locale partendo da `.env.example`:

```sh
cp .env.example .env
```

Poi valorizza:

- `NEXT_PUBLIC_SUPABASE_URL`: URL del progetto Supabase di PerX.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: publishable/anon key client-side dello stesso progetto.
- `NEXT_PUBLIC_SUPABASE_DB_SCHEMA`: lascia `bignami`.
- `NEXT_PUBLIC_SITE_URL`: URL pubblico canonico, in produzione `https://bignami.perx.it`.

Per il progetto Supabase hosted, lo schema `bignami` deve essere esposto nella
Data API oltre ad avere grant/RLS applicati dalle migrazioni PerX.

## Sviluppo

```sh
npm i
npm run dev
```
