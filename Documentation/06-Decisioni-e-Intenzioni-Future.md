---
tags: [perx, decisioni, adr]
updated: 2026-11-26
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

## 2026-11-26 — Motore di stima deterministico nell'app, portato da «sinistri chiari»
Contesto: nell'app macOS il calcolo della perizia era sparso tra `CalcoliService` (Double),
`VociCostoView` e `LiquidazioneView`, con risultati diversi tra pagine (interruttore «massimale
prima» non salvato, arrotondamento sommato a valle, deprezzamento per riga ignorato, Riepilogo
laterale con 20%/22% fissi). L'utente ha chiesto di aggiornare stima e gestione peritale prendendo
spunto dal motore di «sinistri chiari» (vedi la voce «Intenzione: tenant Chiari» dello stesso
giorno), **mantenendo il flusso di compilazione a pagine** dell'app.

Decisione:
- un solo motore puro in Swift (`PerX/Services/Claims/Stima/`), `Decimal` al centesimo, input come
  fotografia di valori e hash del calcolo; tutte le pagine (Elaborato Calcoli, Riepilogo, Atto,
  relazione, Importi) leggono da lì. Le sei pagine del wizard restano invariate come navigazione;
- portati dal riferimento: motivo d'esclusione delle voci e frasi sobrie per l'atto, richiesta da
  giustificativo con priorità sinistro → bene → voci, somme assicurate per partita con trattenuta
  scontata prima sulle eccedenze, arrotondamento ±100 € prima della franchigia, esiti (incluso
  danno non accertato con stima conservativa a riserva), avvisi non bloccanti, scomposizione
  richiesto → accertato → liquidabile, riparto art. 1910, bene comune con quota, revisioni con
  approvazione, hash economico, approvazione ereditata, «solo l'ultima stima vale», verifica
  dell'atto firmato;
- mantenuti i criteri PerX (VSU/SI con limiti, migliorie/illesi, forzature, IVA a saldo, quota
  differita a ripristini ultimati, rettifiche manuali dopo i limiti) e aggiunta la regola
  proporzionale (art. 1907) quando si indica il valore reale di una partita a valore intero;
- **non** portato ciò che è specifico del gestionale Chiari: payload Salesforce/ReClaim,
  Light/Over (sostituito da una soglia di controllo configurabile, default 5.000 €), selezione
  allegati, collegati multi-pratica, catalogo frasi completo;
- correzioni di dominio volute: a «Valore a nuovo» non si applica il deprezzamento; deprezzamento
  0% vale 0%; lo scoperto si calcola sul danno comprensivo dell'IVA riconosciuta; la liquidazione
  forzata del bene è l'importo finale IVA riconosciuta compresa (come già mostrava la scheda bene);
  la somma assicurata della partita si legge in formato italiano e fa da tetto;
- schema Core Data **versionato** (`PerX v2`, migrazione leggera) invece di modificare la versione
  unica, e `Persistence.swift` sposta in backup lo store non apribile invece di cancellarlo.

Motivazione: un solo calcolo verificabile e ripetibile, approvato dal perito e congelato in
revisioni, elimina gli scarti tra pagine e rende difendibile l'importo dell'atto.

Intenzioni aperte: annualità del massimale per più sinistri dello stesso assicurato (da fare anche
nel riferimento); collegati multi-pratica; esito suggerito dalla `definizione` per le pratiche già
chiuse; motore condiviso con backend/MCP (o in `PerXCore` per `swift test`) tenendo gli stessi
casi di test del motore Python finché ne esistono due. Dettagli → [[Motore-di-Stima]].

---

## 2026-11-26 — Cinque ingressi web PynkStudio associati al gateway Vercel PerX
Contesto: i domini prodotto storici non sono più considerati ingressi affidabili; l'utente ha
confermato che la migrazione deve usare esclusivamente la gerarchia sotto `pynkstudio.eu`, mentre
i tenant mantengono i propri domini custom.

Stato attuato: sul progetto Vercel `pynkstudio/perx` risultano associati
`perx.pynkstudio.eu`, `app.perx.pynkstudio.eu`, `catdispatcher.pynkstudio.eu`,
`bignamionline.pynkstudio.eu` e `login.perx.pynkstudio.eu`. Vercel richiede per ciascuno un record
`A` verso `76.76.21.21` nella zona autorevole Register.it. L'associazione Vercel non rende da sola
operativi `app` e `login`: il primo attende l'instradamento applicativo definitivo e il secondo
l'implementazione SSO. `api.perx.pynkstudio.eu` resta destinato al backend Render e non è stato
associato al gateway Vercel. I domini tenant, incluso `randapro.it` con i prefissi operativi,
restano invariati.

Motivazione: separare con chiarezza gli ingressi prodotto PynkStudio dai domini tenant e
predisporre il DNS senza attribuire ai nuovi host servizi non ancora implementati.

## 2026-11-25 — Consolidamento dei portali prodotto sotto `pynkstudio.eu` e control plane admin unico
Contesto: l'utente vuole ricondurre i portali di proprietà PynkStudio oggi distribuiti su domini
separati (`perx.it`, `catdispatcher.it`, Bignami Online e gli altri prodotti da inventariare) sotto
il dominio corporate `pynkstudio.eu`. I domini custom dei tenant, per esempio Studio Randa,
devono invece restare indipendenti e continuare a esporre i propri sottodomini operativi.

Decisione / intenzione:

- ogni prodotto PynkStudio avrà un host di primo livello sotto il dominio corporate: target
  iniziali `perx.pynkstudio.eu`, `catdispatcher.pynkstudio.eu` e
  `bignamionline.pynkstudio.eu`;
- i servizi appartenenti a un prodotto diventano sottodomini del relativo host prodotto, quindi
  per PerX il target è `app.perx.pynkstudio.eu`, `api.perx.pynkstudio.eu` e
  `login.perx.pynkstudio.eu`; eventuali altri host devono seguire lo stesso schema dopo
  l'inventario completo;
- `admin.pynkstudio.eu` è il **control plane unico** di PynkStudio: non va replicato come pannello
  indipendente per ogni prodotto. Da qui gli amministratori PynkStudio devono poter osservare e
  controllare integralmente tutti i prodotti tramite API server-to-server esposte dai rispettivi
  backend;
- il pannello centrale non deve accedere direttamente ai database dei prodotti e non deve
  incorporare segreti nel browser. Ogni backend resta source of truth e authority delle proprie
  regole di dominio; il portale BePork orchestra le API admin con credenziali server-only,
  autorizzazioni per prodotto/azione e audit delle scritture. Il bridge statico
  `X-PerX-Admin-Key` esistente è una base transitoria da evolvere verso credenziali ruotabili e
  scoped, senza interrompere l'integrazione già presente;
- i domini dei tenant non vengono assorbiti in `pynkstudio.eu`: per Studio Randa e gli altri
  tenant restano il dominio custom e i relativi host (`admin.<dominio-tenant>`,
  `assicurati.<dominio-tenant>`, `riunioni.<dominio-tenant>`, ecc.). La gerarchia
  `servizio.prodotto.pynkstudio.eu` riguarda solo i prodotti PynkStudio;
- i domini storici devono restare attivi durante la transizione come alias o redirect permanenti,
  con migrazione graduale di callback OAuth, cookie, CORS/CSP, link email, canonical SEO,
  configurazioni Vercel/Render/Supabase/Resend e client nativi. Il cambio dei portali web non
  implica automaticamente la dismissione dei domini email (per esempio `@perx.it`), che richiede
  una decisione separata.

Prima dell'attuazione va prodotto un inventario completo di host, DNS, certificati, redirect URI,
webhook e dipendenze hardcoded in tutti i repository. La sequenza raccomandata è: aggiungere e
validare i nuovi host in parallelo; rendere configurabili le origini; aggiornare callback e
integrazioni; eseguire smoke test; introdurre redirect dai domini storici; osservare traffico ed
errori; dismettere i vecchi host solo con evidenza che non abbiano più consumer. Il portale admin
centrale va esteso per capability, non tramite accesso indiscriminato: inventario/health,
tenant/utenti/configurazione, errori e audit, operazioni mutative idempotenti, quindi funzioni più
sensibili con approvazioni e rollback dove necessario.

Motivazione: presentare PynkStudio come casa comune dei prodotti, ridurre la frammentazione di
domini e pannelli amministrativi e mantenere al tempo stesso l'isolamento dei tenant e dei dati.
Vedi [[04-Infrastruttura-e-Deploy]], [[Login-Unificato-SSO]], [[Backend-Cloud-API]] e la guida
`docs/perx-integration.md` nel repo BePork.

Stato di attuazione al 2026-11-25: completata la prima fase applicativa per i tre portali già
esistenti. Il gateway riconosce sia gli host storici sia `perx.pynkstudio.eu`,
`catdispatcher.pynkstudio.eu` e `bignamionline.pynkstudio.eu`; i tre runtime origin sono stati
creati e distribuiti su Vercel (`perx-insight-studio`, `catdispatcher`, `bignami-online`) e il
progetto `perx` usa origin server-side configurati. La migration `040_pynkstudio_domains` unifica
i due head Alembic preesistenti, ripara in modo idempotente l'assenza di `domain_routes` rilevata
nel database production e inserisce gli alias nel resolver backend. I domini nuovi sono
associati al progetto Vercel `perx`, ma non sono ancora pubblici: il DNS autorevole è su
Register.it e richiede record A verso `76.76.21.21`. Anche `perx.it` richiede la correzione del
record A attuale; `catdispatcher.it` non risolve e il certificato di `bignami.perx.it` risulta
scaduto. `app/api/login.perx.pynkstudio.eu` e il completamento del control plane admin restano
nelle fasi successive.

Verifica production dello stesso giorno: upgrade riuscito a `040_pynkstudio_domains`, tre route
attive e health backend HTTP 200. Il gateway usa per ora il fallback locale perché il secret del
resolver non è coordinato tra Render e Vercel; nessun secret è stato aggiunto al repository.

Secondo incremento applicativo dello stesso giorno: aggiunto `GET /api/v1/admin/overview` come
contratto di discovery del control plane. Restituisce KPI aggregati e capability CRUD esplicite;
la dashboard `admin.pynkstudio.eu/perx` usa questo snapshot invece di ricostruire i conteggi con
quattro chiamate separate. L'inventario rende visibile anche il limite corrente: la gestione
utenti è ancora read-only. Restano quindi da implementare, in ordine, mutazioni utenti sicure,
audit trail delle scritture e credenziali scoped/ruotabili prima di considerare il controllo
PerX integralmente coperto.

## 2026-11-07 — Piano incrementale per test automatici e CI/CD
Contesto: dopo la valutazione sulla portabilità, l'utente ha chiesto di pianificare l'introduzione
di test e CI/CD. La baseline verificata è debole: nessun workflow CI root, quattro file pytest con
soli test helper e senza configurazione/dipendenze test dedicate, nessun test runner nelle web app,
target XCTest dell'app Apple ancora boilerplate, nessun test target nei package `PerXCore` e
`PerXHub`. Render e Vercel costruiscono dai push/hook senza un gate di test comune.

Intenzione approvata per la pianificazione: procedere per gate progressivi, senza pretendere subito
copertura uniforme su tutto il monorepo e senza bloccare `main` su problemi legacy non ancora
misurati.

1. **Baseline riproducibile e CI osservativa**: aggiungere comandi locali canonici e workflow
   GitHub Actions separati per backend, web e Apple, con cache e path filtering. All'inizio i nuovi
   controlli fotografano lo stato; diventano required checks solo quando verdi e stabili.
2. **Backend come prima area bloccante**: separare dipendenze runtime/dev; introdurre pytest con
   coverage, lint/format e type checking graduale; aggiungere fixture DB Postgres isolata e test di
   API/auth/tenant/migrazioni oltre agli helper puri. Gate iniziale basato su test verdi e nessuna
   riduzione della baseline di coverage, non su una percentuale arbitraria globale.
3. **Web app**: standardizzare `lint`, `check`, `test` e `build` in ogni workspace; usare test
   unitari/componenti per contratti API, trasformazioni e flussi critici, poi Playwright per pochi
   smoke test end-to-end del gateway/portale. Build senza segreti reali tramite configurazioni di
   test e mock espliciti.
4. **Swift/Apple e Hub**: creare test target in `PerXCore` e `PerXHub`, spostando verso il core la
   logica pura più importante; aggiungere unit test dell'app per adapter, parsing/import e state
   machine. Mantenere una suite UI macOS minima e deterministica (avvio, login simulato, apertura
   pratica), eseguita su runner macOS; evitare inizialmente test UI estesi e fragili.
5. **Integrazione e contratti**: testare compatibilità backend-client con schema OpenAPI versionato
   o validato in CI, migration Alembic `upgrade head` su database vuoto e workflow verticali
   essenziali (auth, sinistro, documento, chat/portale).
6. **CD controllata**: preservare inizialmente Vercel e Render come sistemi di deploy, ma consentire
   la promozione da `main` solo dopo i required checks; usare preview web per le pull request,
   smoke test post-deploy e rollback della piattaforma. Firma/notarizzazione dell'app Apple resta
   una pipeline release separata, introdotta dopo la stabilizzazione della CI e con segreti fuori
   dal repository.

Ordine operativo raccomandato: fondazioni CI → backend → web → core Swift/Hub → E2E/contratti →
CD e release native. Ogni fase deve consegnare test reali su rischi di prodotto, documentazione dei
comandi locali, artefatti/report in caso di fallimento e branch protection aggiornata. Metriche:
tempo e affidabilità della pipeline, regressioni intercettate, flakiness e coverage delle aree
modificate; la percentuale globale di coverage non è l'obiettivo primario. Stima iniziale:
circa 20–30 giornate-persona per arrivare ai gate principali e agli smoke E2E, da affinare dopo la
prima baseline verde. Vedi [[04-Infrastruttura-e-Deploy]], [[05-Stato-Sviluppo-e-Roadmap]],
[[Backend-Cloud-API]] e [[PerX-App-Principale]].

Stato di attuazione al 2026-11-07: completata la prima fondazione. Sono presenti tre workflow;
backend pytest/migrazioni, intera pipeline web e build/test Swift sono gate CI. Il web è stato
portato a typecheck/build verdi anche sulle app satellite e le dipendenze con advisory critici o
alti sono state aggiornate. Restano da realizzare le fasi di profondità: fixture DB e test
API/auth/tenant, test reali nelle tre web app con suite vuota, test Hub/app, E2E/contratti e CD
protetta da branch protection. Ruff backend resta una baseline osservativa per debito legacy.

## 2026-11-07 — Valutazione Rust e portabilità desktop/web: no alla riscrittura integrale
Contesto: l'utente ha chiesto se convertire PerX in Rust per renderlo compatibile anche con
Windows, Linux e web, oltre a macOS, e quali vantaggi reali ne deriverebbero. L'app principale è
oggi fortemente nativa Apple: SwiftUI, CoreData, CloudKit, XPC/Local Agent, integrazioni AppKit e
gestione finestre macOS. Il backend FastAPI e le web app Next.js sono invece già multipiattaforma
e accessibili da qualunque sistema tramite browser/API.

Valutazione / intenzione: **non è raccomandata una riscrittura integrale in Rust**. Rust da solo
non fornisce una UI unica per desktop e web e non rende portabile il codice SwiftUI: richiederebbe
comunque la riscrittura della UI, della persistenza e delle integrazioni di sistema, con una lunga
fase di parità funzionale e alto rischio di regressioni, aggravato dall'attuale copertura di test
minima. La direzione raccomandata, se Windows/Linux diventano un requisito commerciale reale, è:

- mantenere backend/API e portali web come superficie multipiattaforma principale;
- separare progressivamente la logica di dominio dalle dipendenze Apple e colmare prima i test;
- realizzare un client desktop multipiattaforma solo per i workflow che richiedono filesystem,
  offline o integrazioni locali, valutando una shell Tauri con frontend web;
- introdurre Rust in modo selettivo per un core condiviso o servizi locali dove sicurezza della
  memoria, concorrenza o prestazioni siano misurabilmente utili, esposto a Swift e alla shell
  desktop tramite API/FFI, senza riscrivere backend e web app;
- mantenere adapter nativi per capacità non portabili (XPC/CloudKit su Apple e alternative per
  Windows/Linux), accettando che la parità assoluta tra piattaforme potrebbe non essere utile.

Motivazione: i vantaggi reali di Rust sarebbero binari nativi efficienti, buon controllo di
memoria/concorrenza e riuso di logica non-UI tra desktop; non includono la portabilità automatica
dell'intero prodotto. Per PerX il costo dominante è la riscrittura delle circa 500 sorgenti Swift
dell'app principale e delle integrazioni Apple, non il linguaggio del core. Prima di avviare una
migrazione va validata la domanda Windows/Linux, definito il sottoinsieme di funzioni necessario e
costruito un proof of concept verticale; il web resta il percorso più economico per coprire subito
tutte le piattaforme. Vedi [[02-Architettura]], [[03-Stack-Tecnologico]],
[[PerX-App-Principale]] e [[05-Stato-Sviluppo-e-Roadmap]].

## 2026-09-06 — PerX integrato come piattaforma nel pannello admin PynkStudio; primo giro di error-tracking backend-only
Contesto: l'utente ha chiesto di aggiungere **PerX** e **Studio Randa** come "ambiti di controllo"
nel pannello admin di PynkStudio (repo BePork, `admin.pynkstudio.eu`), con accesso qualificato da
platform admin e visibilità sul flusso di errori — riservato a noi, non ai singoli tenant admin.
PerX entra come piattaforma di pari livello a Menuary (non come suo verticale, perché ha un
backend/DB del tutto separato), sullo stesso pattern già usato per il portale Security (prodotto
esterno con proprio backend, integrato via API key). Randa è un tenant già esistente su PerX
(confermato dall'utente) e compare automaticamente nella lista tenant del nuovo portale, senza
bisogno di essere creato o cablato a mano.

Decisione / intenzione:
- **Bridge di autenticazione**: nuova dependency `require_platform_admin_or_api_key` in
  `backend/app/core/security.py`, che accetta o il JWT umano esistente (invariato) o un header
  `X-PerX-Admin-Key` verificato contro la nuova env var `PLATFORM_ADMIN_API_KEY`
  (`backend/app/core/config.py`). Applicata a tutte le route di `routes_admin.py` e alle nuove
  route errori. Non è stato toccato `get_current_platform_admin`/`oauth2_scheme`: zero rischio di
  regressione sulle route JWT-based esistenti.
- **Error-tracking — solo backend FastAPI al primo giro**: nuova tabella `platform_error_log`
  (migrazione `038_platform_error_log`), scritta da un `@app.exception_handler(Exception)` globale
  in `backend/app/main.py` su ogni eccezione non gestita, più route `GET/PATCH
  /api/v1/admin/errors*` in `backend/app/api/v1/routes_admin_errors.py`. **Richiesta esplicita
  dell'utente da registrare qui**: l'obiettivo finale dichiarato è tracciare *tutto* il flusso di
  errori del monorepo, non solo il backend cloud — quindi in futuro va estesa l'ingestion anche a
  web app satellite (`apps/portal-web`, `apps/catdispatcher`, `apps/randa`, ecc.), all'app
  iOS/macOS/iPad e a [[PerXHub]]. La colonna `source` sulla tabella è già una stringa libera (non
  un enum) proprio per non richiedere una nuova migrazione quando si aggiungeranno queste fonti.
  Questo secondo giro **non è ancora pianificato né iniziato**.
- **Lato PynkStudio (repo BePork)**: nuovo portale `/admin-pynkstudio/perx/*` (client server-only
  `src/lib/perx/client.ts`, mai esposto al browser — a differenza del client Security esistente
  che usa una chiave `NEXT_PUBLIC_`), gate ristretto ai ruoli `superadmin`/`admin` in
  `src/middleware.ts` (non a tutti i ruoli siteadmin, diversamente da come funziona oggi Security).
  Dettagli completi → `docs/perx-integration.md` nel repo BePork.

Motivazione: separare gli accessi privilegiati trasversali (solo il team PynkStudio) da quelli dei
singoli tenant admin (es. staff di Studio Randa, che restano scoped al proprio tenant via
`/api/v1/tenants/me/*`, invariato) — la separazione platform-admin/tenant-admin esisteva già nel
backend PerX, qui viene solo esposta a un pannello esterno invece di essere ricostruita. Vedi
[[Backend-Cloud-API]] per il dettaglio delle nuove route e [[04-Infrastruttura-e-Deploy]] per la
nuova env var.

## 2026-09-06 — Prima versione di PerX Lite implementata: solo estensione Chrome, niente pagina web
Contesto: seguito diretto della valutazione del 2026-09-05 (vedi voce sotto). L'utente ha chiesto
una "nuova versione" più stupida del vecchio `perx_chrome_extension` (mai arrivato su `main`): via
sync cloud, via Hub, via OAuth — solo Excel + una foto → compilazione della pagina JFish aperta.
Decisione: implementata in `perx_lite_extension/` (nuova cartella, non sovrascrive/riusa i branch
con `perx_chrome_extension`). Manifest V3 minimale: solo `activeTab` + `scripting` + `storage`,
nessun `background`, nessun `content_scripts` dichiarato, nessun `host_permissions` — tutto gira
nel popup, `filler.js` viene iniettato nella tab attiva solo al click su "Compila pagina". Il
parsing Excel usa SheetJS vendorizzato localmente (`vendor/xlsx.full.min.js`, nessuna chiamata di
rete). Dettagli tecnici e rischi noti (upload foto su widget Syncfusion non ancora testato contro
il DOM live) → [[PerX-Lite-Extension]].
Motivazione: le due domande aperte nella valutazione del giorno prima sono state risolte
dall'utente in chat: la foto va allegata a un campo upload della pagina (non OCR), e l'Excel è lo
stesso Elaborato Peritale ma con una mappatura di campi diversa da quella già gestita da
`ImportService.swift` — quindi serve una mappatura configurabile dall'utente (etichetta Excel →
campo pagina), non una lista fissa: per questo l'estrazione riconosce coppie etichetta/valore
generiche invece di assumere un layout di colonne noto a priori. Vedi anche [[CatDispatcher]] per
il prototipo di estensione gemello (ACT CAT Dispatcher) rimasto fuori scope in questa iterazione.

## 2026-09-05 — Idea discussa: "PerX Lite Web" (pagina web + estensione Chrome, Excel → DOM)
Contesto: l'utente ha chiesto quanto sarebbe complesso realizzare una versione "Lite" puramente
web di PerX, limitata a una pagina web più un'estensione Chrome che prende in ingresso un file
Excel e compila con quei dati il DOM di un sito target — senza app native, senza Hub, senza il
resto della piattaforma. Sarebbe un'evoluzione delle due estensioni già scritte:
`perx_chrome_extension` (PerX JFish Sync) e `catdispatcher/chrome-extension` (ACT CAT Dispatcher).

Stato del codice riusabile (rilevato il 2026-09-05): **nessuna delle due estensioni è su `main`**.
`perx_chrome_extension` esiste sui branch `worktree-agent-acdf3bb97ccd74251`, `FS_SFW` e
`claude/crazy-pike-887058`; `catdispatcher/chrome-extension` solo su
`worktree-agent-acdf3bb97ccd74251`. Prima di qualunque lavoro su questa idea vanno consolidate su
`main`, altrimenti si riparte da zero.

Intenzione (non ancora pianificata, solo valutata):
- Riuso previsto: `fillField()` / `triggerSyncfusionEvents()` di `content.js` (compilazione dei
  controlli Syncfusion di JFish: input, datepicker con data italiana, dropdown per value/label,
  rich text editor), la gestione SPA (`observeDOMChanges`, MutationObserver + popstate + polling),
  il contesto multi-tab di `content-script.js` (`getActiveTabContent`, `queryInActiveContext`) e
  la logica di dominio già collaudata in `PerX/Services/Import/ImportService.swift` (mapping
  colonna→campo con matching fuzzy e mapping persistiti, mapping degli stati, parsing date
  italiane e seriali Excel, parsing decimali, preview delle differenze prima di applicare).
- Da scrivere ex novo: parsing `.xlsx` lato browser (SheetJS/ExcelJS, tutto client-side, nessun
  backend), UI di mapping colonne→campi, e il concetto di **profilo di sito dichiarativo** (JSON:
  match dell'URL, per ogni campo selettore + tipo di controllo + trasformazione) in modo che
  aggiungere un sito target sia dato e non codice da rilasciare.
- Impostazione consigliata per la v1: nessun backend e nessuna pagina web: options page
  dell'estensione + `chrome.storage`. La pagina web (in `apps/`, sul progetto Vercel `perx`
  esistente) ha senso solo dopo, come editor e distributore dei profili condivisi tra utenti.
- Ordine di grandezza stimato: pochi giorni se il target resta JFish (i selettori esistono già);
  2-3 settimane se serve un selector picker generico "clicca il campo → registra il selettore" con
  profili multi-sito; ulteriore tempo per la pubblicazione sul Chrome Web Store (percorso già
  affrontato una volta per CAT Dispatcher, vedi `chrome-extension/store/`).
- Rischio tecnico principale segnalato: `fillField()` assegna `element.value` direttamente, cosa
  che funziona su Syncfusion ma viene ignorata da React/Vue; per un compilatore realmente generico
  serve il setter nativo (`Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set`)
  più eventi `input`/`change`. Secondo rischio: fragilità dei selettori sul DOM del sito target
  (manutenzione perpetua).

Motivazione: valutare un prodotto autonomo, vendibile e installabile senza Mac mini, Hub, Tailscale
o app native — cioè senza la superficie operativa che oggi rende PerX distribuibile solo internamente.
Nessuna decisione presa: al 2026-09-05 è solo una valutazione di fattibilità. Vedi [[CatDispatcher]]
e [[PerXHub]] per le estensioni esistenti.

## 2026-09-05 — Riconciliazione contratto API portale assicurati + completamento gap documentati
Contesto: nel completare i gap "non ancora collegato" del portale assicurati (vedi
[[Portal-Web-Assicurati]]) è emerso che `apps/portal-web/lib/api.ts` e `lib/types.ts` non
corrispondevano affatto al backend reale (`routes_portal.py`/`routes_portal_me.py`): URL (plurale
`/claims/{id}/...` invece di `/claim/...` con `claim_id` opzionale in query), metodi HTTP, e body
in camelCase invece di snake_case (nessun alias generator nei modelli Pydantic). `tsc --noEmit`
falliva già prima di qualunque modifica (confermato: l'affermazione "typecheck puliti" nello stato
del progetto non era più vera). La maggior parte dei componenti pagina (`claim-chat-page`,
`claim-iban-page`, `claim-act-page`, `claim-documentation-page`, `claim-inspection-page`,
`auth-entry`, `push-prompt`, videoperizia) usava già i campi reali corretti: il problema era
isolato quasi interamente in `lib/api.ts`/`lib/types.ts`/`lib/claim-ui.ts`.
Decisione: riscritti `lib/types.ts` e `lib/api.ts` per rispecchiare esattamente gli schemi Pydantic
del backend (percorso, metodo, snake_case, gestione 204). Riscritte le funzioni derivate in
`lib/claim-ui.ts` (riepiloghi documentazione/IBAN/sopralluogo/atto) per usare solo campi realmente
esposti dal backend invece di campi mai esistiti (`documentation_uploaded`, `iban_status`,
`inspection_mode` su `PortalClaimSummary`, ecc.) — erano bug silenziosi, non solo errori di tipo.
Rimossi (spostati fuori repo, non eliminati) `lib/mocks.ts` e un `claim-dashboard 2.tsx` non
tracciati in git, entrambi già rotti e non referenziati da nessun import. `tsc --noEmit` ora è
pulito su tutto `apps/portal-web`.
Contestualmente completati i gap approvati dall'utente: invio email reale del magic link (sia
per link generati dallo staff sia per il resend self-service — riusa `ResendEmailService`), signed
upload URL reali verso Supabase Storage con endpoint di conferma dedicato (fallback al proxy
server esistente quando Supabase non è configurato), canalizzazione delle risposte staff→assicurato
nella chat portale (mirroring in `PortalConversationMessage` + notifica push/email), e un primo
livello di antifrode offline sulle foto caricate (EXIF/GPS vs posizione sopralluogo confermata,
hash percettivo per duplicati — dietro `FF_PORTAL_PHOTO_ANTIFRAUD_ENABLED`, default `True`; solo
segnalazione, nessun blocco). OTP SMS resta esplicitamente fuori scope: nessun provider integrato,
da decidere con l'utente quando servirà.
Motivazione: senza questa riconciliazione nessuna funzionalità del portale (dashboard, documenti,
chat, IBAN, sopralluogo) avrebbe mai funzionato contro il backend reale — priorità più alta dei
gap stessi. Vedi [[Portal-Web-Assicurati]] e [[05-Stato-Sviluppo-e-Roadmap]] per lo stato aggiornato.

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
Ultimo aggiornamento: 2026-11-25
