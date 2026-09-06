---
tags: [perx, decisioni, adr]
updated: 2026-09-06
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
Ultimo aggiornamento: 2026-09-06
