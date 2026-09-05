---
tags: [perx, decisioni, adr]
updated: 2026-09-05
---

# Decisioni architetturali e intenzioni di sviluppo future

Log **datato e append-only**: aggiungi una nuova voce in cima quando si prende una decisione
architetturale, oppure quando si discute con l'utente un'intenzione di sviluppo futuro — anche se
non ancora implementata. Non riscrivere/rimuovere voci passate: se una decisione viene superata,
aggiungi una nuova voce che lo dice esplicitamente e linka quella vecchia. Vedi
[[Istruzioni-AI-Agenti]] per la regola completa.

Formato consigliato per ogni voce:

```
## AAAA-MM-GG — Titolo breve
Contesto: ...
Decisione / intenzione: ...
Motivazione: ...
```

---

## 2026-06 — Un solo progetto Vercel come gateway multi-dominio
Contesto: più app Next.js (`portal-web`, `catdispatcher`, `bignami-online`, `perx-insight-studio`,
`randa`) devono convivere nello stesso repo e condividere SSO/policy.
Decisione: tutti i portali web devono essere Next.js App Router; il progetto Vercel pubblico
principale (`perx`, Root Directory = root del repo) riceve i domini che richiedono routing
applicativo e risolve tenant/prodotto dall'host della richiesta. Le app ancora autonome sono unità
di migrazione temporanee.
Motivazione: gestire routing per host, SSO, cookie HttpOnly e autorizzazione server-side in modo
uniforme, servendo domini multipli da un unico progetto invece che duplicare configurazione e
autenticazione. Vedi [[04-Infrastruttura-e-Deploy]].

## 2026-06-04 — Fix crash `idealTree` su Vercel
Contesto: build Vercel falliva istantaneamente per un override `installCommand` con `--prefix` in
dashboard, incompatibile con npm workspaces.
Decisione: aggiunto `vercel.json` in root del repo con `installCommand: "npm install"` per
sovrascrivere l'override dashboard; un solo `package-lock.json` a livello root.
Motivazione: i `vercel.json` dentro le singole app non vengono letti quando `rootDirectory` di
progetto è `null`. Vedi [[04-Infrastruttura-e-Deploy]].

## (data non nota, da ricostruire se serve) — Supabase solo storage/edge, non accesso diretto ai dati PerX
Contesto: Supabase offre sia Postgres gestito sia SDK client-side per accedervi direttamente.
Decisione: il backend FastAPI resta l'unico punto di accesso ai dati applicativi PerX; Supabase
viene usato direttamente solo per storage file e per schemi Postgres dedicati di app satellite
(es. `bignami`), mai per dati PerX core dal client.
Motivazione: mantenere un solo layer di autorizzazione/business logic (il backend) invece di
distribuire regole di accesso tra RLS Supabase e codice applicativo. Vedi [[02-Architettura]].

## (data non nota) — Single-tenant mode per la V1
Contesto: il modello dati supporta multi-tenant fin dall'inizio.
Decisione: la messa in produzione iniziale usa `SINGLE_TENANT_MODE=True` con un solo tenant
bootstrap; il codice multi-tenant resta nel backend per uso futuro ma non è la configurazione di
produzione corrente.
Motivazione: ridurre la complessità operativa iniziale senza chiudere la porta al multi-tenant.
Vedi [[Backend-Cloud-API]], [[05-Stato-Sviluppo-e-Roadmap]].

## (data non nota) — Login unificato pianificato, Supabase Auth come IdP raccomandato
Contesto: oggi ogni app (PerX API, CatDispatcher, pannello admin) gestisce login e token in modo
proprio; si vuole un identity layer unico su `login.perx.it`.
Intenzione: adottare OAuth 2.1/OIDC con Authorization Code + PKCE; usare Supabase Auth come
provider di password/magic-link/refresh/MFA, lasciando al backend PerX la responsabilità di
inviti, tenant, ruoli e autorizzazione applicativa.
Motivazione: evitare di costruire un sistema di password custom, ottenere SSO reale tra le app
mantenendo il backend PerX come autorità sui ruoli/tenant. Non ancora implementato — vedi
[[Login-Unificato-SSO]] per il piano completo in 5 fasi e le decisioni ancora aperte.

## (data non nota) — Videoperizia come modalità alternativa al sopralluogo, non aggiuntiva
Contesto: la videoperizia condivide la sezione portale del sopralluogo fisico.
Decisione: sopralluogo, videoperizia e documentale non vengono mai presentati insieme
all'assicurato; è sempre una modalità alternativa esclusiva per quella pratica.
Motivazione: evitare ambiguità nel flusso assicurato su quale canale usare per quel sinistro.
Vedi [[Videoperizia]].

---
Ultimo aggiornamento: 2026-09-05
