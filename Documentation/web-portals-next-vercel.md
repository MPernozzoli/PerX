# Portali web PerX: standard Next.js e deploy Vercel

## Regola architetturale

Tutti i portali web gestiti nella repository PerX devono usare Next.js App Router.

Non devono essere introdotte nuove applicazioni Vite, SPA statiche o frontend con un runtime
incompatibile con il gateway Next.js. Questa regola consente di:

- gestire il routing per host tramite `proxy.ts`;
- risolvere tenant e prodotto dal dominio richiesto;
- applicare SSO, cookie HttpOnly e autorizzazione server-side in modo uniforme;
- servire domini multipli da un unico progetto Vercel;
- integrare progressivamente le UI nello stesso runtime senza riscriverne il design.

## Progetto Vercel principale

Il progetto Vercel pubblico principale usa come Root Directory:

```text
apps/portal-web
```

Questo progetto riceve i domini che richiedono routing applicativo:

```text
admin.perx.it
admin.<tenant_domain>
assicurati.<tenant_domain>
riunioni.<tenant_domain>
catdispatcher.it
www.catdispatcher.it
```

Il gateway legge l'host, interroga il resolver backend e seleziona il portale corretto.

## Vincolo del singolo progetto

Convertire ogni cartella `apps/*` a Next.js non fa sì che Vercel compili automaticamente più
applicazioni indipendenti come un unico progetto. Un progetto Vercel ha una sola Root Directory
e una sola build Next.js.

Per essere pubblicato realmente dal solo progetto `apps/portal-web`, un portale deve essere
integrato nel runtime di `portal-web`, come route, modulo o package condiviso. Le app Next.js
ancora presenti come cartelle autonome sono unità di migrazione temporanee e possono richiedere
un progetto Vercel tecnico separato finché l'integrazione nel gateway non è completata.

## Portali e domini

| Portale | Dominio previsto | Strategia |
| --- | --- | --- |
| PerX Superadmin | `admin.perx.it` | Route del gateway |
| Admin tenant | `admin.<tenant_domain>` | Route del gateway con tenant da host |
| Portale assicurati | `assicurati.<tenant_domain>` | Route del gateway con tenant da host |
| Riunioni esterne | `riunioni.<tenant_domain>` | Route del gateway con invito firmato e token LiveKit |
| CatDispatcher | `catdispatcher.it` | Da integrare nel gateway |
| Bignami Online | `bignami.perx.it` | Da integrare nel gateway se deve condividere SSO e policy |
| PerX Insight Studio | dominio marketing PerX | Può restare progetto Next.js separato |
| Randa | `randapro.it` | Può restare progetto Next.js separato |

## Routing automatico

Il routing applicativo deve essere automatico dopo che DNS e dominio sono associati al progetto
Vercel. Il resolver backend deve riconoscere almeno i prefissi riservati:

```text
admin.
assicurati.
riunioni.
```

e risolvere il dominio base tramite i domini registrati per il tenant.

DNS, verifica del dominio e certificato TLS restano prerequisiti esterni al middleware. Questi
passaggi devono essere automatizzati nel flusso di onboarding tenant tramite API Vercel quando
si vogliono supportare domini arbitrari dei clienti.

## Migrazione corrente

Le applicazioni precedentemente basate su Vite sono state portate a Next.js App Router mantenendo
temporaneamente React Router all'interno di un client boundary. Questo preserva percorsi, design e
comportamento durante il cambio di runtime.

La fase successiva consiste nel convertire gradualmente i percorsi in route App Router native e
spostare nel gateway i portali operativi che devono essere pubblicati dal singolo progetto Vercel.
