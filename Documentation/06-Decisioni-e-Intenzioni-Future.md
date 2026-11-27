---
tags: [perx, decisioni, adr]
updated: 2026-11-27
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

## 2026-11-27 — Ogni account ha calendario, impostazioni e archivio propri
Contesto: separare solo i sinistri lasciava calendario, orari, impostazioni e preferenze
nello stesso archivio del Mac.
Decisione: all'accesso l'app apre l'archivio e le preferenze di quell'account. Calendario,
orari, impostazioni dello studio, filtri e notizie locali non passano all'account successivo.
L'archivio che c'era già sul Mac resta all'account precedente, non a chi entra dopo.
Motivazione: ogni account si porta le proprie cose.

## 2026-11-27 — Le pratiche Chiari non passavano dalla lista API
Contesto: gli stati Chiari (`CHIUSO`, `ATTO_INVIATO`, …) non sono gli stati dello studio.
La lista sinistri li rifiutava, quindi l'app restava vuota.
Decisione: la risposta della lista accetta lo stato del tenant così com'è.
Motivazione: il tenant Chiari ha un suo elenco di stati.

## 2026-11-27 — Utente e tenant sempre separati
Contesto: la prima chiusura mostrava i sinistri dell'altro account solo quando si entrava con
Chiari. La divisione non è una regola di quel tenant.
Decisione: vale per ogni accesso. La lista Sinistri e la dashboard mostrano solo le pratiche
dell'utente connesso e del suo tenant. All'ingresso si scaricano le pratiche di quel tenant e si
segna `tenantId` sulla copia locale. Senza accesso non si mostra l'archivio di un altro utente.
Sul server, se non si indica un tenant, anche l'amministratore di piattaforma resta nel proprio.
Motivazione: due studi sulla stessa macchina non possono mescolare le pratiche.

## 2026-11-27 — La sessione Chiari non mostra i sinistri dell'altro account
Contesto: sul Mac la lista Sinistri legge l'archivio locale, condiviso fra gli account aperti
su quella macchina. Entrando con `massimo.pernozzoli@chiarisrl.it` comparivano le pratiche
dell'altro tenant.
Decisione: con l'account Chiari la lista mostra solo le pratiche di quella mail. Le pratiche
Chiari arrivano dal server e restano segnate con quella mail. L'altro account non le vede.
Il perito può leggere le impostazioni del proprio tenant: prima l'endpoint le riservava
all'amministratore, quindi l'app restava sul profilo dello studio precedente.
Motivazione: un tenant con un solo perito non deve vedere i sinistri di un altro studio.

## 2026-11-27 — Abbinamento mail al sinistro: riferimento, numero compagnia, nome
Contesto: la sincronizzazione Gmail collegava la mail solo se nel testo c'era il riferimento
`YY-NNNNNN`.
Decisione: l'abbinamento è in cascata e si ferma al primo livello che trova una pratica.
1. Riferimento interno `YY-NNNNNN` (`claims.external_ref`).
2. Numero sinistro compagnia (`claims.numero_sinistro`, anche nella forma senza l'`1.` iniziale,
   per esempio `825.26.00637` oltre a `1.825.26.00637`).
3. Nome assicurato, solo se nel testo c'è un solo nominativo di quella lunghezza. Se due pratiche
   hanno lo stesso nome, la mail si collega a entrambe.
Motivazione: è l'ordine con cui lo studio riconosce la pratica. Il riferimento vince sul numero
e sul nome anche se nella stessa mail compaiono gli altri.

## 2026-11-27 — Posta Gmail operativa sul backend, login Google da pubblicare
Contesto: l'app Mac chiama `https://api.perx.it`. Il bottone «Accedi con Google» riceveva
`Not Found` perché `POST /api/v1/auth/google/session` esisteva solo nel codice locale.
Decisione: la posta del tenant Chiari la sincronizza il backend, non l'app. All'accesso Google
si conserva il token della casella e parte il recupero di posta in arrivo e inviata, poi le mail
nuove tramite `history.list`. Il riferimento `26-602322` nel testo collega la mail alla pratica.
Gli allegati fino a 15 MB vanno su Supabase Storage. L'invio dall'app, se la casella Gmail è
collegata, parte da Gmail e non da Resend. Il rinnovo del token richiede sul server le variabili
`GOOGLE_OAUTH_CLIENT_ID` e `GOOGLE_OAUTH_CLIENT_SECRET`, gli stessi valori già messi nel
provider Google di Supabase: non stanno nel sorgente. La push Pub/Sub del piano F2 resta
successiva: per ora il server interroga Gmail circa ogni 90 secondi.
Motivazione: senza la rotta pubblicata l'accesso non può funzionare, e senza sync sul server
la posta vecchia e nuova non arriva in PerX.

## 2026-11-27 — Riferimento Chiari `26-602322` e import delle pratiche
Contesto: tutte le 273 pratiche locali usano il riferimento `anno-sei cifre` (es. `26-602322`).
L'import dell'app accettava solo 7 cifre consecutive.
Decisione: il riferimento si conserva così com'è, in `claims.external_ref`. Il validatore accetta
sia le 7 cifre sia `26-602322`, e lo stesso formato si riconosce in mail e nei nomi cartella.
Le 273 pratiche sono sul tenant `chiari`. I documenti dei dossier non sono stati copiati.
Motivazione: è il numero con cui lo studio identifica la pratica; non va schiacciato sulle 7 cifre.

## 2026-11-27 — Migrazione 043 applicata e utente Chiari creato
Contesto: l'utente ha chiesto di applicare le migrazioni e creare l'accesso Google.
Esito: il database è a `043_chiari_regia`. Il tenant `chiari` esiste, con l'utente
`massimo.pernozzoli@chiarisrl.it` (senza password: entra con Google), dominio ammesso
`chiarisrl.it`, portale e Cat Dispatcher spenti, 14 stati e 34 regole.
Motivazione: senza la riga utente il bottone «Accedi con Google» rifiuta la mail.

## 2026-11-26 — Accesso Chiari: Google Workspace interno, client web su Supabase
Contesto: il perito del tenant Chiari è `massimo.pernozzoli@chiarisrl.it`. Ha creato su Google
Workspace Chiari, uso interno, un client OAuth di tipo applicazione web, pensando a un bottone
«Accedi con Google» che apre Safari, riceve il token e lo tiene nel portachiavi, senza rifare
l'accesso a ogni apertura.
Decisione: Client ID e secret di quel client stanno nel provider Google di Supabase Auth del
progetto PerX (`wqcqiaojdflbmqyamndt`), non nel sorgente dell'app. In Google l'unico redirect è
`https://wqcqiaojdflbmqyamndt.supabase.co/auth/v1/callback`. L'app apre
`ASWebAuthenticationSession` verso Supabase e riceve la sessione sul proprio scheme
(`com.pernozzoli.perx://login-callback`). Nel portachiavi restano access token e refresh token:
all'avvio, se l'access è scaduto, si rinnova in silenzio. Gli ambiti del consenso sono identità,
`gmail.modify` (leggere, inviare, allegati), `gmail.settings.basic` (firma) e `calendar.events`.
Il refresh token di Google della casella viene cifrato sul server e non resta nell'app.
L'utente PerX con quella mail va creato prima: un login Google di una mail sconosciuta non apre
un account.
Motivazione: il client web ha un secret, e il secret può stare solo sul server. La sessione lunga
è il refresh token, non la pagina di Google lasciata aperta.

## 2026-11-26 — Tenant Chiari: un solo perito, niente funzioni verso l'esterno
Contesto: parte l'implementazione del piano [[Regia-Agenti-e-Tenant-Chiari]]. L'utente precisa che
l'uso è di un solo perito, non di tutto lo studio Chiari.
Decisione: il profilo `workflow_profile = chiari` spegne, anche se qualcuno le riaccende nelle
impostazioni, portale assicurati, Cat Dispatcher, videoperizia, inviti, rubrica colleghi, chat
interna, WhatsApp, Telegram, chiamate PerX, link pubblici e programmazione di rete. Restano
sinistri, stima, documenti, posta operativa, rubrica della pratica, consuntivo e Sala regia.
Gli altri studi, senza quel profilo, tengono il prodotto completo.
Motivazione: PerX non deve presentarsi a colleghi o assicurati di Chiari. Lo studio continua a
lavorare su Salesforce e ReClaim.

## 2026-11-26 — Intenzione: la Regia agenti come cuore di PerX, il perito come supervisore
Contesto: completa la voce «Intenzione: tenant Chiari» dello stesso giorno. L'utente vuole che la
«coda» di «sinistri chiari» (orchestratore locale con IA, oggi Ollama) diventi il cuore pulsante
di PerX: orchestratore e gestore primario dei sinistri, in buona parte affidato ad Apple
Intelligence con gli OS 27, con modelli più grandi (anche cloud) per i casi complessi e il perito
per le decisioni apicali. Il perito diventa il supervisore del lavoro degli agenti, che mostrano
cosa fanno, evidenziano i problemi e ricevono istruzioni su come gestirli.
Intenzione: la **Regia** gira sul Mac del perito (app + helper `SMAppService`) con stato, job e
lease sul backend; scala L0 regole/motore → L1 on-device → L2 Private Cloud Compute o Ollama →
L3 cloud di frontiera → L4 perito; **Questioni** come unico canale verso il perito e
**Regolario** per trasformare le sue istruzioni in regole; invarianti (approvazione solo del
perito, importo già proposto, IBAN di terzi) imposte dal backend. Verificato sull'SDK macOS 27.2
installato: `FoundationModels` espone `PrivateCloudComputeLanguageModel` (con quota) e un
protocollo `LanguageModel` con executor pubblico. Piano completo in 10 fasi (F0–F9), rischi e
decisioni aperte → [[Regia-Agenti-e-Tenant-Chiari]]. L'ordine qui sostituisce quello proposto
nella voce «tenant Chiari».
Motivazione: oggi il flusso funziona perché il perito tiene insieme a mano agenti, cruscotto,
estensione e regole sparse; portarlo in PerX con un orchestratore unico rende il lavoro visibile,
controllabile e ripetibile anche per altri studi.

---

## 2026-11-26 — RLS: la 041 era già in effetto con l'allowlist, la 042 chiude `tenants` e `user_roles` (corregge la voce «RLS sulle tabelle `public`»)
Contesto: ho letto lo stato reale del progetto Supabase `PerX` con notebook SQL in sola lettura.
Prima: **93 tabelle in `public`, nessuna con RLS, zero policy, `anon` e `authenticated` con
`SELECT` su tutte** (tra cui `users`, `portal_sessions`, `actor_ibans`, `device_tokens`,
`user_invitations`, `claims`, `emails`). Dopo (verifica delle 22:45): **94 tabelle con RLS; senza
RLS solo `tenants` e `user_roles`**. La prima versione della 041, con l'allowlist
`LEGACY_DIRECT_ACCESS_TABLES` (11 tabelle del frontend CAT Dispatcher), era su `origin/main` dalle
17:46 ed era già in effetto sul database. L'allowlist era superflua: 9 delle 11 tabelle (`cats`,
`communes`, `regions`, `provinces`, `cat_commune`, `cat_suspensions`, `allowed_domains`,
`geojson_backup_log`, `user_tenants`) non esistono in `public`; le due presenti sono tabelle core
PerX usate solo dal backend e lasciarle aperte manteneva l'esposizione.
Decisione (confermata dall'utente: includere anche `tenants` e `user_roles`): **nuova migrazione
`042_enable_rls_remaining`**, stessa logica della 041 senza esclusioni. La 041 non si modifica
perché già applicata (Alembic non la rieseguirebbe e `tenants`/`user_roles` resterebbero aperte).
Backend, PerXHub ed edge function bypassano RLS; gli altri client Supabase del repo usano lo
schema `bignami` o le tabelle di Insight Studio, entrambi con RLS. Testata su Postgres
usa-e-getta nella sequenza 041 → 042 e riesecuzione idempotente.
Aperto: (1) il frontend `apps/catdispatcher` fa ancora `supabase.from('cats'|…)` su tabelle che
qui non esistono — va allineato a `/api/v1/cat-dispatcher/*` o verificato verso quale progetto
Supabase punta; (2) restano da eliminare dal dashboard Supabase tre notebook temporanei (audit e
due «Apply 041»), che il client MCP non può cancellare.
Esito: dopo il push di `bc5d3c6` e il deploy Render, verifica in sola lettura (22:52): **96
tabelle su 96 in `public` con RLS**, nessuna senza; `api.perx.it/health` risponde 200.

## 2026-11-26 — Landing: home brand, storytelling in `/come-funziona`
Contesto: lo storytelling a schermate come unica home risultava troppo grezzo (placeholder
senza catture) e poco adatto all'ingresso su `perx.it`.
Decisione: la home (`/`) è presentazione brand + CTA; il racconto della pratica inventata vive
in `/come-funziona`. Resta ferma la scelta screenshot (non clone HTML) di cui sotto.
Motivazione: l'ingresso non dipende dalle catture; il percorso dettagliato resta raggiungibile
da nav e CTA. Vedi [[Altre-Web-App]].

## 2026-11-26 — Landing PerX: storytelling con screenshot, non clone HTML
Contesto: la pagina marketing in `apps/perx-insight-studio` andava riscritta (tono da brochure
con gradienti/card) per mostrare le interfacce reali delle app lungo il ciclo di una pratica.
Decisione: una pratica inventata unica (`src/content/pratica-demo.ts`); sequenza a capitoli
(elenco → dettaglio → bignami → Studio/Team → dispatcher → portale → Lite → stima); ogni vista
è uno **screenshot** dell'app vera (Mac, Lite, browser), non una ricostruzione HTML/Tailwind
della UI nativa o dei portali (non sarebbe indistinguibile e divergerebbe subito). Finché i PNG
non sono in `src/assets/story/`, i frame usano un placeholder silhouette (non un clone UI).
Motivazione: fedeltà al prodotto e manutenzione; le schermate web (portale, Cat Dispatcher,
Bignami) dipendono da auth/dati e non vanno duplicate nella landing.
Vedi [[Altre-Web-App]].

## 2026-11-26 — Domini principali PerX per CatDispatcher e Bignami
Contesto: dopo l'attivazione degli alias sotto `pynkstudio.eu`, l'utente ha precisato quale
gerarchia deve essere mostrata come canonica per i due prodotti.

Decisione: `catdispatcher.perx.it` è il dominio principale di CatDispatcher e
`bignami.perx.it` è il dominio principale di Bignami Online. Gli host
`catdispatcher.pynkstudio.eu` e `bignamionline.pynkstudio.eu` restano attivi come alias
secondari sullo stesso gateway; non sostituiscono i canonical principali. Studio Randa resta un
tenant con dominio proprio `randapro.it`.

Impatto: gateway, metadata/canonical, manifest dell'estensione CAT, configurazioni Vercel e smoke
test devono accettare entrambi gli host, ma link pubblici e integrazioni nuove devono preferire i
domini `*.perx.it` indicati sopra. Questa decisione supera, per CatDispatcher e Bignami, la
precedente indicazione del 2026-11-25 che presentava gli host `pynkstudio.eu` come target primari.

## 2026-11-26 — Domini PerX piatti attivati su Vercel
Contesto: il pannello DNS Register.it in uso non accetta le etichette annidate `app.perx` e
`login.perx`; l'utente ha approvato la variante piatta e ha configurato i record DNS.

Decisione / stato: i target sono `app-perx.pynkstudio.eu`, `login-perx.pynkstudio.eu` e, per il
backend Render, `api-perx.pynkstudio.eu`. I primi due sono associati al progetto Vercel
`pynkstudio/perx`; insieme a `perx.pynkstudio.eu`, `catdispatcher.pynkstudio.eu` e
`bignamionline.pynkstudio.eu` risolvono sulla rete Vercel e rispondono HTTPS. Finché app e SSO
dedicati non saranno implementati, `app-perx` e `login-perx` servono esplicitamente la landing
PerX invece di cadere sul portale assicurati generico. Gli alias annidati restano temporaneamente
associati fino alla pulizia finale della configurazione.

Motivazione: completare la migrazione con nomi compatibili con Register.it e garantire una pagina
coerente su ogni nuovo ingresso durante l'implementazione dei servizi futuri.

Verifica browser reale: Chrome e Safari mostravano `This page couldn't load` anche se gli health
check HTTP restituivano 200. La console ha isolato la causa nell'inizializzazione immediata del
client Supabase (`supabaseUrl is required`) sull'origin Insight Studio privo delle env pubbliche.
Il client è stato reso opzionale e le sole funzioni dipendenti da Supabase degradano con errore
controllato; la landing marketing non dipende più dalla presenza di quelle variabili.

## 2026-11-26 — RLS sulle tabelle `public` (Advisor Supabase `sensitive_columns_exposed`)
Contesto: l'Advisor di sicurezza del progetto Supabase `PerX` ha segnalato
`sensitive_columns_exposed`: tabelle con colonne sensibili (`users.password_hash`, `token_hash` di
portale/inviti/sessioni, IBAN, device token…) raggiungibili dalla Data API senza restrizioni.
Causa: lo schema `public` è esposto da PostgREST e le migrazioni Alembic 001–040 creano le
tabelle **senza** `ENABLE ROW LEVEL SECURITY` (solo lo schema `bignami`, in `018`, lo fa); con i
grant di default di Supabase la chiave anon/publishable ha quindi accesso pieno. Contraddice la
decisione «il backend è l'unico punto di accesso ai dati» (vedi [[02-Architettura]]): era vera per
i nostri client, non per chi usa la chiave pubblica.
Decisione: migrazione `backend/migrations/versions/041_enable_rls_public_tables.py` — abilita RLS
(senza policy e senza `FORCE`) su ogni tabella di `public` che ne è priva, saltando tabelle di
estensioni, tabelle non possedute dal ruolo di migrazione e `LEGACY_DIRECT_ACCESS_TABLES` (vedi
sotto). Backend (`DATABASE_URL`, ruolo proprietario), PerXHub ed edge function (service-role)
bypassano RLS: nessun impatto. Verificata su Postgres usa-e-getta: `anon` passa da leggere
`users`/`portal_sessions`/`actor_ibans` a 0 righe; seconda esecuzione idempotente. `downgrade()`
è volutamente vuoto (disabilitare RLS riesporrebbe i dati).
Da fare / aperto:
1. **CAT Dispatcher legacy.** Il frontend `apps/catdispatcher/src` interroga ancora direttamente
   via PostgREST (`supabase.from(...)`/`rpc`) 11 tabelle: `allowed_domains`, `cat_commune`,
   `cat_suspensions`, `cats`, `communes`, `geojson_backup_log`, `provinces`, `regions`, `tenants`,
   `user_roles`, `user_tenants` (rotte `/`, `/admin`, `/admin/gis-editor`, `/api`). La migrazione
   non le tocca per non rompere quelle schermate. Se in produzione sono senza RLS restano
   esposte (incluse `tenants`, `user_tenants`, `user_roles`): o si migrano le schermate al backend
   `/api/v1/cat-dispatcher/*` (come già dichiarato in [[CatDispatcher]]), o si scrivono policy
   RLS esplicite; poi si tolgono le tabelle da `LEGACY_DIRECT_ACCESS_TABLES`. Prima verificare lo
   stato reale nel SQL editor di Supabase.
2. **Regola per le nuove migrazioni:** ogni tabella creata in `public` deve abilitare RLS nella
   stessa migrazione. Idea non implementata: event trigger Supabase che abilita RLS alle nuove
   tabelle, oppure un test CI che fallisce se una tabella `public` è senza RLS.
3. **Non ancora applicata in produzione:** la 041 parte al prossimo deploy Render
   (`scripts/start-render.sh` esegue `alembic upgrade head`).

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

## 2026-11-26 — Intenzione: tenant «Chiari» e porting del flusso sinistri «sinistri chiari» in PerX
Contesto: l'utente lavora come perito per Chiari S.r.l. (sinistri fenomeno elettrico Vittoria,
gestionale dello studio = Salesforce Classic + ReClaim/NewAge, posta = Google Workspace Chiari)
con un sistema "light" locale, fuori da questa repo (`~/Downloads/sinistri chiari`): DB JSON
(`db/sinistri.json` ~270 pratiche, `polizze.json` con blocco `bignami`), cruscotto Python locale
(`cruscotto/server.py`, porta 8765, launchd), motore di stima deterministico in Python
(`stima.py` + `frasi.py`, revisioni con hash economico e approvazione del perito), estensione
Chrome MV3 «Sinistri Chiari» che compila SF/ReClaim dal payload approvato, agenti Claude Code
(`sx-triage` regista → `pratica` prepara → OK del perito → `esegui`) e un agente remoto
(ChiariBot/Grok) per solleciti e atti firmati. Lo studio non sostituirà il suo gestionale: PerX
deve **coesistere** con SF/ReClaim, non rimpiazzarli. Bignami Online è già alimentato da qui.

Intenzione (discussa, non approvata per l'implementazione; nessun codice scritto):

1. **Tenant e accesso.** Nuovo tenant `chiari` con una sola utenza (il perito), accesso «Accedi
   con Google» con l'account Google Workspace Chiari. Strada proposta: provider Google di Supabase
   Auth (coerente con [[Login-Unificato-SSO]]), dominio ammesso per tenant nelle impostazioni del
   tenant. **Correzione necessaria:** `get_current_user` oggi è *o* JWT legacy *o* Supabase
   (`FF_CLOUD_AUTH_ENABLED` globale): accendere Supabase spegnerebbe il login degli utenti
   esistenti. Serve accettare entrambi i token in parallelo. Lato app: `GoogleAuthService.swift`
   ha già un flusso Google (solo `openid email`) con client secret scritto nel sorgente: va
   rifatto con `ASWebAuthenticationSession` + PKCE e il secret va ruotato.
2. **Posta Gmail → Supabase → client.** Ripristinare il flusso Google per la posta, ma lato
   server: Gmail API `users.watch` → Pub/Sub push → nuova Edge Function `gmail-inbound` (stesso
   schema di `resend-inbound`: idempotenza, `inbound_email_events`, `email_processing_jobs`) →
   `history.list`/`messages.get` → righe `emails` del tenant + allegati su Supabase Storage. I
   client (Mac, iPhone, iPad) **non** sincronizzano più Gmail: scaricano dal backend in modo
   incrementale (`GET /api/v1/emails?since=…`) e ricevono un segnale realtime/push per sapere
   quando farlo (resta valido il principio «i client non leggono Postgres direttamente», vedi
   [[02-Architettura]]). Token OAuth della casella solo lato server (`mailboxes.oauth_token_ref`,
   provider `gmail`), rinnovo del `watch` entro 7 giorni (cron) e poll di recupero. Invio via
   Gmail API dal backend (così la mail parte dall'account Workspace e resta nel thread); la firma
   automatica di Gmail **non** si applica ai messaggi inviati via API: va letta da `sendAs` e
   aggiunta. Segnare come letto/etichette → scope `gmail.modify`.
3. **Estensione Chrome collegata a PerX.** Resta operativa; invece del cruscotto locale parla con
   l'API PerX (token utente, non più il controllo sull'ID estensione), con endpoint equivalenti a
   `/api/estensione/*` e `/api/stima/payload`; i file scaricati da SF vanno nel vault PerX invece
   che nella cartella locale. Transizione con URL backend configurabile nelle opzioni.
4. **Dati e motore.** Import idempotente (dry-run di default) di pratiche, eventi, revisioni di
   stima, polizze e documenti nel tenant; stati Chiari (`stati.json`) come insieme di stati
   configurabile per tenant invece della mappatura forzata sugli `SVxxx`. Un solo motore di stima
   autorevole lato server, con le regole già collaudate (Light/Over/Senza stima, collegati,
   importo già proposto, ereditarietà dell'approvazione); approvazione **solo** da UI del perito,
   imposta dal backend e non più dalla disciplina del prompt.
5. **Flusso IA-centrico via MCP.** Server MCP remoto di PerX (OAuth) con gli strumenti oggi in
   `db.py`/`stima.py`/`bignami.py` e la posta (cerca, thread, testi già estratti dei documenti,
   lock `lavoro start/end`), senza strumento di approvazione. Le azioni nel Chrome del perito
   (SF con passkey, ReClaim con OTP e sessione unica) restano locali tramite l'estensione. Lo
   stesso MCP serve Claude Code, Claude da iPhone e ChiariBot; i solleciti giornalieri e il
   triage delle mail (atti firmati, solleciti, incarichi) possono diventare regole di Elettra per
   il tenant (vedi [[AI-Locale-e-Cloud]]).

Prerequisiti e rischi da chiarire prima di partire: consenso di Chiari (dati di terzi in
infrastruttura PynkStudio → accordo sul trattamento dati) e del suo amministratore Workspace
(scope Gmail «restricted»: app da segnare come attendibile nella console Workspace oppure client
OAuth in un progetto Google interno a Chiari; un'app esterna in stato «Testing» perde il refresh
token ogni 7 giorni); verifica dell'isolamento tra tenant, perché sarebbe il primo tenant reale
con dati di un altro titolare; CI backend ancora rossa per il drift delle migration (vedi
[[04-Infrastruttura-e-Deploy]]). Da decidere: fonte di verità durante la transizione (PerX come
specchio del sistema locale o subito autorevole) e se il motore autorevole resta quello Python
o il porting Swift in corso in `PerX/Services/Claims/Stima/` (due motori vanno tenuti allineati
con gli stessi casi di test). Ordine proposto: 1 → 2 → 4 → 3 → 5, poi il cruscotto come vista
PerX e la dismissione di quello locale.

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

## 2026-11-26 — Niente `application-identifier` nei file entitlements (firma automatica)
Contesto: Xcode segnalava «Entitlement com.apple.application-identifier not found and could not be
included in profile» sul target `PerX`, perché la chiave era dichiarata a mano in
`PerX.entitlements` e `PerX-Debug.entitlements`.
Decisione: rimossa la chiave da entrambi i file; l'identificatore applicazione lo inietta Xcode in
firma a partire da team e bundle ID. Non reintrodurre né `application-identifier` né
`com.apple.developer.team-identifier` nei file entitlements gestiti con firma automatica.
Motivazione: non sono capability del profilo di provisioning, quindi Xcode non può includerle.
Da verificare (non toccato): `aps-environment` e `com.apple.developer.aps-environment` coesistono
nello stesso file perché il target è multipiattaforma; se compaiono errori analoghi su macOS
valutare di tenere solo la chiave `com.apple.developer.*`. Vedi [[PerX-App-Principale]].

---
Ultimo aggiornamento: 2026-11-26
