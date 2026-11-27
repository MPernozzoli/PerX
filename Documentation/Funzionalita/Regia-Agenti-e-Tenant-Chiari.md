---
tags: [perx, funzionalita, ai, agenti, chiari, in-corso]
updated: 2026-11-27
---

# Regia agenti e tenant Chiari — piano di implementazione

> [!note] Stato: avviato il 2026-11-26, non concluso.
> Nel codice ci sono il profilo del tenant, il blocco delle funzioni esterne, gli stati Chiari,
> revisioni/questioni/regole/job, l'import delle 273 pratiche e la sincronizzazione Gmail sul
> backend. Non sono ancora fatti l'accordo sul trattamento dati, il benchmark dei modelli, la
> push Pub/Sub, il worker sul Mac, l'estensione collegata e l'MCP. I file dei dossier restano
> nella cartella locale.

## 1. Obiettivo

Due obiettivi, legati tra loro:

1. **Portare in PerX il flusso «sinistri chiari»** per un nuovo tenant `chiari` (Chiari S.r.l.),
   con una sola utenza (il perito) e accesso Google Workspace. Lo studio non sostituisce il suo
   gestionale: PerX **coesiste** con Salesforce e ReClaim, non li rimpiazza.
2. **Fare della «coda» il cuore di PerX.** L'orchestratore che oggi in «sinistri chiari» prende le
   pratiche, le lavora con l'IA locale e le porta al perito diventa la **Regia**: il gestore
   primario dei sinistri. Lavora con il livello di modello più piccolo che basta (Apple
   Intelligence sul dispositivo, poi modelli più grandi, anche cloud) e porta al perito solo le
   decisioni apicali.

Principio guida: **il perito diventa il supervisore del lavoro degli agenti.** Gli agenti mostrano
cosa stanno facendo e perché, evidenziano i problemi con le prove e le opzioni, e ricevono
istruzioni su come gestirli. Un'istruzione data una volta può diventare una regola.

## 2. Punto di partenza

### «sinistri chiari» (oggi, fuori repo: `~/Downloads/sinistri chiari`)

| Componente | Cosa fa |
|---|---|
| `db/sinistri.json` (~270 pratiche), `dbio.py`, `db.py` | stato pratiche, eventi, note, lock `lavoro start/end`, controlli, collegati |
| `db/stati.json` | 14 stati (2 meta-stati), unico elenco per cruscotto, agenti ed estensione |
| `db/polizze.json` + `bignami.py` | modelli di polizza, polizze viste, blocco `bignami` che alimenta Bignami Online |
| `stima.py` + `frasi.py` | motore deterministico: importi, IVA, franchigie, modello ReClaim (Light/Over/Senza stima), testi, allegati; revisioni con hash economico e approvazione |
| `cruscotto/server.py` (porta 8765, launchd) | Kanban, dettaglio pratica, approvazioni, prospetto PNG, API per l'estensione |
| `coda.py`, `runner.py`, `elabora.py`, `stima_ollama.py` | **la coda**: prende DA_LAVORARE e DA_CHIUDERE, una pratica alla volta per il modello locale (Ollama `qwen2.5:32b`) e una per Chrome; testi e foto in parallelo; aspetta che il Mac sia inattivo; 3 tentativi, poi DAL_PERITO / STIMA_DA_RIVEDERE / CHIUSURA_DA_RIVEDERE |
| Estensione Chrome «Sinistri Chiari» (MV3) | compila SF e ReClaim dal payload approvato, scarica documenti, osserva gli stati SF |
| `dossier.py`, `chrome-js.sh`, `ext.py`, `sf-*.js`, `reclaim-*.js` | download, script nel Chrome del perito via AppleScript |
| Skill `sx-triage`/`sx-nuovo`/`sx-chiusura`, agenti `pratica`/`esegui` | flusso Claude Code: prepara → OK del perito → esegue |
| ChiariBot (Grok, remoto) | solleciti giornalieri, atti firmati in arrivo, cambi di stato da mail |
| `CLAUDE.md` del progetto | le regole del perito, datate («perito 25/11», «Ramona 11/11»…) |

### PerX (oggi, pezzi riusabili)

- Multi-tenant nel modello dati (`tenants`, `tenant_id` ovunque); in produzione
  `SINGLE_TENANT_MODE=False`.
- `process_jobs` con lease, heartbeat e worker esterno: è già lo scheletro di una coda di job.
- `ai_routing_policy`, `ai_prompt_template(_version)`, `ai_analysis_run`: routing e versioning dei
  prompt.
- `mailboxes` (provider, `oauth_token_ref`), `inbound_email_events`, `email_processing_jobs` ed
  Edge Function `resend-inbound`: lo schema da copiare per Gmail.
- Local Agent XPC + Ollama; `AppleAIService` usa già `FoundationModels`.
- Motore di stima in Swift (`PerX/Services/Claims/Stima/`), generico, senza le parti specifiche
  del gestionale Chiari → [[Motore-di-Stima]].
- Schema `bignami` e Bignami Online → [[Altre-Web-App]].
- Framing di prodotto Elettra/Sparky → [[AI-Locale-e-Cloud]].

## 3. Architettura target

```
        Perito — Sala regia (Mac · iPhone · iPad)
  approva · risponde alle Questioni · dà istruzioni e regole
                         ▲   attività live, notifiche
                         │
┌────────────────────────┴─────────────────────────────┐
│ Backend PerX (API) + Supabase (Postgres, Storage)     │
│ pratiche · stati del tenant · revisioni di stima ·    │
│ job e lease · Questioni · Regolario · posta ·         │
│ invarianti · server MCP remoto                        │
└───▲──────────────────▲───────────────────▲───────────┘
    │ job (lease)      │ Gmail push        │ MCP
┌───┴──────────────┐ ┌─┴──────────────┐ ┌──┴────────────────┐
│ Regia            │ │ Edge Function  │ │ Agenti esterni    │
│ (Mac del perito) │ │ gmail-inbound  │ │ Claude Code / SDK,│
│ L0 regole/motore │ └────────────────┘ │ Claude su iPhone, │
│ L1 on-device     │                    │ ChiariBot         │
│ L2 PCC / Ollama  │                    └───────────────────┘
│ L3 cloud         │
└───┬──────────────┘
    │ native messaging
┌───┴──────────────────────┐
│ Estensione Chrome        │
│ Salesforce · ReClaim     │
└──────────────────────────┘
```

### 3.1 La scala di escalation

| Livello | Chi | Cosa fa | Esempi |
|---|---|---|---|
| L0 | Regole e motore deterministico (nessuna IA) | tutto ciò che si può calcolare o verificare | importi, IVA, franchigie, modello ReClaim, mod-97 IBAN, stati, controlli relazione, guardie |
| L1 | Apple Intelligence sul dispositivo | compiti brevi, privati, gratuiti, ad alto volume | classificare una mail, estrarre IBAN/numeri/importi, tipo di una foto, riassunto di una nota |
| L2 | Private Cloud Compute (Apple), in alternativa Ollama/MLX locale | documenti lunghi, preparazione strutturata | leggere polizza e appendici, preparare l'input della stima (oggi `elabora.py` con Ollama) |
| L3 | Modelli cloud di frontiera (Claude, via backend, zero data retention) e agenti con strumenti | giudizio, casi nuovi, procedure da imparare | scostamento oltre il 10%, polizza nuova o ambigua, negative, contestazioni |
| L4 | Perito | decisioni apicali | approvazione dell'economia, IBAN di terzi, contestazioni, nuove regole |

Regole della scala:

- si parte sempre dal livello più basso indicato per quel compito (vedi §3.4);
- si sale quando l'uscita non supera i controlli L0 (schema non valido, IBAN che non torna,
  importo oltre la richiesta, fonti mancanti), quando il modello dichiara un dubbio, quando il
  contesto non basta (`contextSizeExceeded`) o quando la quota PCC è finita;
- un dubbio che nessun livello automatico risolve diventa una **Questione** per il perito;
- 3 tentativi falliti sullo stesso passo → Questione (come la coda di oggi).

### 3.2 La Regia (orchestratore)

**Dove gira.** Sul Mac del perito, dentro l'app PerX e in un helper registrato con
`SMAppService` (continua a lavorare ad app chiusa, come oggi la coda via launchd; è anche il
«futuro LaunchAgent» citato in [[AI-Locale-e-Cloud]]). Il Mac serve per tre motivi: Apple
Intelligence gira sul dispositivo, Chrome con le sessioni SF (passkey) e ReClaim (OTP, sessione
unica) è lì, e i file grandi si elaborano in locale. **Lo stato e la coda stanno sul backend**:
così iPhone e iPad vedono tutto, le mail arrivate di notte restano in fila e più worker possono
collaborare senza pestarsi i piedi.

**Job.** Ogni lavoro è un job sul backend (estensione di `process_jobs`, vedi §4) con tipo,
pratica, fase, risorsa richiesta, lease con heartbeat, tentativi, livello di modello usato ed
esito. Un solo job per pratica alla volta (sostituisce `lavoro start/end` e `db/live`).

**Risorse e arbitraggio** (le stesse regole che `coda.py` applica oggi):

| Risorsa | Capacità | Regola |
|---|---|---|
| `chrome` | 1 | un solo job alla volta sul Chrome del perito; gli agenti esterni hanno la precedenza; sessione SF/ReClaim assente → il job aspetta senza errore |
| `modello_locale` | 1 | parte solo se il Mac è inattivo e il carico è basso |
| `pcc` | quota | si legge `quotaUsage`; vicino al limite si scende a Ollama o si sale a L3 |
| `cloud` | budget | tetto di spesa per tenant e per pratica |
| `perito` | asincrona | le Questioni non bloccano le altre pratiche |

**Fasi.**

- *Nuovo incarico:* importa (dal rapporto SF) → scarica documenti e foto (`chrome`) → testi
  (PDFKit, OCR con Vision al posto di `pdftotext`/`ocr.sh`) e foto ridotte (ImageIO) in parallelo
  → classificazione foto (L1) → lettura polizza (L2) → input della stima (L2) → motore (L0, salva
  la revisione) → controlli (L0) → ATTO_PRONTO o Questione → approvazione del perito → compila il
  Documentale (`chrome`) → il perito clicca «Salva e invia documento».
- *Chiusura:* atto firmato (dalla posta) → estrazione e verifica IBAN (L1 + mod-97) → revisione
  di chiusura (eredita l'approvazione se l'economia non cambia) → ReClaim e SF (`chrome`) →
  controllo del PDF della relazione (L0) → CHIUSO.
- *Posta in arrivo:* classificazione (L1) → collegamento alla pratica (L0: riferimento Chiari,
  numero compagnia, ID SF) → azione secondo le regole (atto firmato → DA_CHIUDERE; rifiuto o
  nuovi documenti → STIMA_DA_RIVEDERE; richiesta di chiamata → DA_CONTATTARE; cambio IBAN o
  beneficiario → Questione).
- *Periodici* (oggi ChiariBot, estensione e launchd): solleciti degli atti inviati alle 9 dei
  giorni feriali, rapporto SF ogni 15 minuti, ispettorati, rinnovo del `watch` Gmail, pulizia dei
  file locali delle pratiche chiuse da oltre 30 giorni.

**Uscite.** Identiche a quelle della coda: prima dell'invio dell'atto → DAL_PERITO; dopo l'invio →
STIMA_DA_RIVEDERE; da quando si chiude → CHIUSURA_DA_RIVEDERE. Un job non porta mai una pratica
in uno stato che il perito ha scelto a mano dopo l'inizio del job.

### 3.3 Apple Intelligence in OS 27 — cosa c'è davvero

Verificato il 2026-11-26 leggendo l'interfaccia di `FoundationModels` nell'SDK macOS 27.2
(Xcode 27.2) installato su questo Mac:

- `SystemLanguageModel`: il modello sul dispositivo (già usato da `AppleAIService`).
- **`PrivateCloudComputeLanguageModel`** (iOS/macOS 27): modello più grande su Private Cloud
  Compute, usabile dalle app, con quota (`quotaUsage`, `isLimitReached`, `resetDate`) ed errori
  dedicati (`QuotaLimitReached`, `NetworkFailure`, `ServiceUnavailable`).
- Protocollo **`LanguageModel`** con `LanguageModelExecutor` pubblico: la stessa sessione può
  lavorare su modelli diversi. Da verificare con un prototipo se un executor nostro (Ollama,
  Claude via backend) si integra con sessione, tool e `@Generable`; se sì, tutti i livelli
  parlano la stessa lingua nel codice.
- `LanguageModelCapabilities`: `vision`, `guidedGeneration`, `reasoning`.
- Da 27.2: allegati di dati nel prompt (`supportsDataAttachmentType(UTType)`), utili per PDF e
  foto; quali tipi supporta ciascun modello va chiesto a runtime.
- `contextSize` esposto; errori `contextSizeExceeded` e `rateLimited`.
- `DynamicInstructions` / `DynamicProfile` / `SessionProperty`: istruzioni composte a runtime,
  adatte a iniettare le regole del tenant (§3.6).

Da misurare in F0, non dato per scontato: contesto reale dei due modelli, qualità in italiano sui
nostri documenti, quote PCC, uso di `FoundationModels` da un helper in background, comportamento
su iPhone. I deployment target attuali sono macOS 26.0 / iOS 26.2: le funzioni della Regia che
usano API 27 vanno dietro `#available` con ripiego su Ollama o cloud.

### 3.4 Chi fa cosa (ipotesi iniziale, da confermare con il benchmark di F0)

| Compito | Oggi | Livello di partenza | Sale a |
|---|---|---|---|
| Classificare una mail (atto firmato, sollecito, incarico, contestazione, IBAN…) | Claude/Grok via connettore Gmail | L1 | L3 |
| Estrarre IBAN, intestatario, importo, firma dall'atto | agente Sonnet | L1 + mod-97 | L2 → L4 |
| Tipo della foto, bene, marca, modello | agente Sonnet | L1 (se `vision`) | L2 |
| Leggere polizza, appendici, franchigie FE | Sonnet / Opus | L2 | L3 |
| Preparare l'input della stima (partite, beni, voci con fonti) | Sonnet / Ollama 32b | L2 | L3 |
| Importi, testi, modello ReClaim, allegati | `stima.py` | L0 | — |
| Casi da giudizio (scostamento >10%, negative, polizza nuova) | Opus | L3 | L4 |
| Compilare SF e ReClaim | estensione | L0 (estensione) | Questione su ERR |
| Approvazione, IBAN di terzi, contestazioni | perito | L4 | — |

### 3.5 Sala regia (l'interfaccia del supervisore)

Porta in PerX quello che oggi fa il cruscotto, con al centro gli agenti:

- **Agenti al lavoro**: chi sta facendo cosa, su quale pratica, in quale fase, da quanto, con quale
  livello di modello e con quali fonti (documento e pagina).
- **Questioni**: ogni problema arriva con descrizione, prove, opzioni proposte e quella
  raccomandata. Il perito risponde con un tocco, un testo o la voce, e sceglie «solo per questa
  pratica» o «fai sempre così» (→ regola, §3.6).
- **Approvazioni**: revisioni di stima da approvare, con il confronto con la revisione precedente.
- **Kanban** con gli stati del tenant: trascinare una tessera resta una decisione del perito che
  prevale sugli agenti.
- **Dettaglio pratica**: timeline, documenti, note SF, esito economico (richiesto → accertato →
  liquidabile), prospetto per il cliente, controlli, collegati e riaperture.
- **Per oggi**: DA_CONTATTARE, scadenze, click «Salva e invia» in attesa.
- **Notifiche** su iPhone e Watch per le Questioni urgenti; approvazioni e risposte anche da
  iPhone.

Mac come postazione principale; iPhone e iPad per supervisione, Questioni e approvazioni.

### 3.6 Questioni e Regolario

- **Questione**: problema aperto da un agente (tipo, livello che l'ha sollevata, prove, opzioni,
  raccomandazione, risposta del perito, esito). È l'unico canale con cui un agente chiede al
  perito; sostituisce il «riepilogo in chat + OK citato».
- **Regolario**: le regole del perito per tenant, datate e con la pratica d'origine (oggi le righe
  «perito 25/11» del `CLAUDE.md`). Due tipi: *istruzioni* (testo iniettato nei prompt con
  `DynamicInstructions`) e *codificate* (diventano controlli L0 o parti del motore, con un task di
  sviluppo). Una risposta «fai sempre così» crea una regola proposta che il perito conferma.
- Import iniziale: le regole attuali di «sinistri chiari» entrano nel Regolario del tenant
  `chiari` con la loro data.

### 3.7 Invarianti imposte dal backend (non dal prompt)

- Una revisione di stima si approva **solo** con un'azione del perito (nessuno strumento MCP o
  agente può approvare).
- Una nuova revisione con lo stesso hash economico eredita l'approvazione della precedente.
- Nessun atto con liquidabile inferiore a quello già proposto, salvo eccezione del perito.
- Cambi di IBAN o beneficiario verso terzi → sempre Questione; l'IBAN sull'atto firmato prevale
  dopo la verifica mod-97.
- Un solo job per pratica, un solo job su Chrome.
- Sinistri collegati: niente esecuzione finché tutte le stime del gruppo non sono approvate.
- Gli stati scelti dal perito non vengono toccati dagli agenti; le transizioni automatiche
  dell'estensione seguono le stesse guardie di oggi.

### 3.8 Posta (Gmail → Supabase → client)

Gmail API `users.watch` → Pub/Sub (push con token OIDC) → `POST /api/v1/emails/gmail/push` sul
backend (il token della casella non esce dal server: per questo non passa da una Edge Function) →
`history.list` e `messages.get` → righe `emails` del tenant, evento in `inbound_email_events` e
allegati su Supabase Storage. Se un allegato non si scarica dopo tre tentativi, la mail resta e
l’hub segnala che i file sono ancora su Gmail. I client non sincronizzano Gmail: il Mac scarica
dal backend ogni 60 secondi e lo stream `mail_updated` avvisa chi è collegato. Token della casella solo lato server.
Invio dal backend via Gmail API (parte dall’account Workspace e resta nel thread), con la firma
letta da `sendAs` perché Gmail non la aggiunge ai messaggi inviati via API. Scope: `gmail.modify`,
`gmail.send`, `gmail.settings.basic`.

### 3.9 Browser (estensione Chrome)

L'estensione resta l'unico esecutore su SF e ReClaim. Cambia con chi parla:

- con la **Regia** tramite *native messaging* (host registrato dall'app PerX), al posto di
  AppleScript e `chrome-js.sh`: comandi ed esiti diretti, senza schede in primo piano;
- con il **backend** per payload approvati, file scaricati da SF (nel vault) e cambi di stato,
  autenticata con l'utente PerX invece del controllo sull'ID dell'estensione.

### 3.10 MCP e agenti esterni

Server MCP remoto sul backend (OAuth), con gli strumenti che oggi danno `db.py`, `stima.py`,
`bignami.py` e il connettore Gmail: pratiche, stati (con le guardie), eventi e note, job e lease,
testi dei documenti già estratti, posta, polizze e Bignami, Regolario in lettura, apertura di una
Questione. **Nessuno strumento di approvazione.** Lo usano Claude Code, Claude da iPhone e, se
resta, ChiariBot. Per i compiti L3 che richiedono strumenti, la Regia avvia un agente con Claude
Agent SDK che lavora su questo MCP e chiude con un esito o una Questione.

## 4. Modello dati (backend)

| Oggetto | Contenuto |
|---|---|
| `tenants.settings_json` | metodi di accesso, domini ammessi, profilo di workflow (`chiari`), parametri (soglie, orari solleciti) |
| stati per tenant | codice, etichetta, quando, chi, meta, ordine (da `stati.json`) |
| campi Chiari della pratica | ID Salesforce, riferimento Chiari (`external_ref`), numero compagnia, ispettorato, liquidatore, stato SF, `chiuso_su`, esito e chiusura prevista, passaggi, controlli |
| gruppi di pratiche | collegati (stesso fabbricato) e riaperture |
| revisioni di stima | numero, input, calcolo, hash calcolo ed economico, liquidabile, approvazione, ereditata da, superata, eccezione importo |
| atti | atti inviati con importo, atto firmato, verifica |
| job | `process_jobs` esteso: pratica, fase, risorsa, tentativi, livello di modello, durata, costo, esito, attività (passi con fonti) |
| Questioni | pratica, job, tipo, livello, prove, opzioni, raccomandazione, risposta, esito |
| Regolario | testo, tipo (istruzione/codificata), ambito, autore, data, pratica d'origine, stato, versione |
| posta | `mailboxes` con provider `gmail`, stato di sincronizzazione (`historyId`, scadenza del `watch`) |
| polizze | schema `bignami` per i prodotti; polizze viste private del tenant |

Tutte le tabelle nuove con `tenant_id`, RLS attiva e accesso solo dal backend.

## 5. Fasi

### F0 — Prerequisiti, sicurezza, misure
- Accordo con Chiari sul trattamento dei dati; consenso dell'amministratore Workspace (app PerX
  attendibile, oppure client OAuth in un progetto Google di Chiari).
- Sicurezza: migrazione RLS `041` applicata in produzione (vedi la voce RLS del 2026-11-26 in
  [[06-Decisioni-e-Intenzioni-Future]]); test di isolamento tra tenant su tutte le route; CI
  backend verde (drift delle migration, [[04-Infrastruttura-e-Deploy]]).
- Corpus di valutazione dalle pratiche di «sinistri chiari»: mail già classificate dagli eventi,
  atti firmati con IBAN verificato, foto classificate, revisioni approvate. Resta in locale.
- Benchmark dei livelli (on-device, PCC, Ollama, Claude) sui compiti di §3.4.
- **Fatto quando:** c'è una tabella «compito → livello minimo affidabile» con i numeri, e i
  consensi sono scritti.

### F1 — Tenant Chiari e accesso Google
- Il backend accetta in parallelo i JWT attuali e quelli Supabase (oggi `FF_CLOUD_AUTH_ENABLED`
  è globale e spegnerebbe il login degli utenti esistenti).
- Provider Google in Supabase Auth; dominio ammesso nelle impostazioni del tenant.
- Script idempotente che crea il tenant `chiari` e l'utenza del perito.
- App Mac, iPhone, iPad: «Accedi con Google» con `ASWebAuthenticationSession` + PKCE. Il client
  secret Google oggi scritto in `GoogleAuthService.swift` va tolto dal sorgente e ruotato.
- **Fatto quando:** il perito entra con Google su Mac e iPhone e vede solo il tenant Chiari; gli
  utenti esistenti entrano come prima; i test di isolamento passano.

### F2 — Posta Gmail su Supabase
- Collegamento della casella (OAuth lato backend, accesso offline), token cifrato. Fatto.
- `users.watch`, rinnovo quando manca meno di un giorno, push su
  `POST /api/v1/emails/gmail/push`, recupero se lo `historyId` è troppo vecchio. Il codice c’è;
  il topic Pub/Sub sul progetto Google no.
- API backend: elenco, dettaglio, allegati su Storage, invio con firma `sendAs` e thread,
  letto/etichette. Segnale `mail_updated`. Il Mac legge ogni 60 secondi.
- **Fatto quando:** una mail nuova fa scattare subito `history.list` e compare sul Mac al giro
  successivo verso il backend, entro 60 secondi, senza sincronizzazione Gmail sui client; una mail
  inviata da PerX è in Gmail «Inviata», con firma, nel thread giusto. Manca ancora il topic,
  quindi oggi il limite è il polling di 90 secondi.

### F3 — Dati Chiari e motore di stima
- Stati per tenant, campi Chiari, gruppi, revisioni, atti (§4).
- Import idempotente con prova a vuoto e report: pratiche, eventi, revisioni, polizze, documenti
  nel vault.
- Motore: il core Swift già deciso ([[Motore-di-Stima]]), spostato in `PerXCore` per i test, più
  un **profilo Chiari** portato da `stima.py`/`frasi.py` (Light/Over/Senza stima, payload SF e
  ReClaim, selezione allegati, collegati, catalogo frasi).
- Test «golden»: ogni revisione approvata del corpus deve dare gli stessi importi, lo stesso
  modello ReClaim e le stesse spunte; le differenze volute vanno scritte.
- **Fatto quando:** le pratiche sono importate, i conteggi per stato coincidono con il cruscotto
  locale e i test golden passano.

### F4 — Regia v1: porting della coda, a parità
Vale per ogni tenant. Chiari è il primo caso, non un flusso a parte.
Il backend assegna i lavori (un solo lavoro per pratica, un solo Chrome, il modello locale
solo a Mac libero), tiene il lease e dopo tre tentativi apre una Questione. L’esito è quello
della coda: `DAL_PERITO`, `STIMA_DA_RIVEDERE`, `CHIUSURA_DA_RIVEDERE`, e lo stato PerX diventa
`da_revisionare` se il perito non ha scelto lui lo stato. Il Mac prende i lavori con
`RegiaWorker`. La settimana di paragone con la coda locale non è ancora stata misurata.
- Job, lease e arbitraggio delle risorse sul backend; worker Swift nell'app e nell'helper.
- Fasi di §3.2 con gli stessi esiti di `coda.py`; testi con PDFKit e Vision.
- L2 ancora su Ollama, come oggi, per confrontare a parità.
- Attività live verso la Sala regia (anche una prima vista semplice).
- **Fatto quando:** per una settimana la Regia gestisce nuovi incarichi e chiusure con risultati
  almeno pari alla coda (pratiche arrivate ad ATTO_PRONTO, chiusure senza rimandi della
  segreteria).

### F5 — Livelli di modello e Apple Intelligence
Come F4: è il modo in cui lavora PerX, per ogni tenant.
Ogni compito ha un livello di partenza e una scala (`regia_scala`). Si sale se il controllo L0
non passa. Le regole attive del regolario entrano nel prompt (`GET /api/v1/regia/compiti/{compito}`).
Il worker registra livello e durata. L1–L3 non chiamano ancora il modello: il lavoro resta in coda
e non diventa Questione solo perché Apple Intelligence o Ollama non hanno risposto.
- Astrazione sul protocollo `LanguageModel` (prototipo prima: executor per Ollama e Claude).
- Router per tipo di compito con livello di partenza e condizioni di salita, configurato in
  `ai_routing_policy` per tenant.
- Uscite strutturate `@Generable` per ogni compito (classificazione mail, atto firmato, foto,
  input stima) e validatori L0.
- Regolario iniettato nei prompt; tracciamento di livello, durata, quota e costo per job.
- **Fatto quando:** i compiti assegnati a L1/L2 raggiungono in produzione i valori misurati in F0
  e la quota di compiti risolti senza L3 è nota.

### F6 — Sala regia
- Agenti al lavoro, Questioni, approvazioni, Kanban, dettaglio pratica, Per oggi (§3.5).
- Notifiche iPhone/Watch; risposta e approvazione da iPhone.
- Regolario: «fai sempre così» → regola proposta → conferma.
- **Fatto quando:** il perito lavora una giornata intera senza il cruscotto locale.

### F7 — Estensione collegata a PerX
- Native messaging con la Regia; autenticazione con l'utente PerX; endpoint backend equivalenti a
  `/api/estensione/*` e `/api/stima/payload`; file da SF nel vault; osservatore degli stati verso
  il backend con le stesse guardie.
- URL del backend nelle opzioni; compatibilità con `127.0.0.1:8765` fino a F9.
- **Fatto quando:** l'estensione lavora senza il cruscotto locale.

### F8 — MCP e agenti esterni
- Server MCP remoto (§3.10); worker Claude Agent SDK per i compiti L3; skill `sx-*` riscritte
  sugli strumenti MCP; destino di ChiariBot.
- **Fatto quando:** un caso da giudizio viene preparato da L3 tramite MCP e arriva al perito come
  Questione.

### F9 — Passaggio e dismissione
- Periodo in parallelo, poi PerX diventa la fonte di verità: il DB JSON passa in sola lettura,
  con backup.
- Spenti cruscotto, coda e pulizia locali (launchd); l'estensione abbandona `localhost`;
  la cartella «sinistri chiari» va in archivio.
- **Fatto quando:** per un mese nessun lavoro passa più dal sistema locale.

Ordine: F0 → F1 → F2 → F3 → F4 → F5 → F6 → F7 → F8 → F9. F6 può partire in versione minima già con
F4; F7 può anticipare la parte di autenticazione e URL configurabile.

## 6. Mappatura «sinistri chiari» → PerX

| Oggi | In PerX |
|---|---|
| `db/sinistri.json`, `dbio.py`, `db.py` | pratiche, eventi e tabelle Chiari via API backend |
| `db/stati.json` | stati per tenant |
| `db/polizze.json`, `bignami.py` | schema `bignami` + polizze viste del tenant |
| `stima.py`, `frasi.py` | motore Swift + profilo Chiari |
| `cruscotto/server.py`, `index.html` | Sala regia |
| `coda.py`, `runner.py`, `elabora.py`, `stima_ollama.py` | Regia |
| `dossier.py`, `sf-*.js`, `reclaim-*.js`, `chrome-js.sh`, `ext.py` | azioni dell'estensione via native messaging |
| `ocr.sh`, `pdftotext`, `img-piccole.sh` | PDFKit, Vision, ImageIO |
| `relazione-controlla.py` | controllo L0 prima della chiusura |
| `ispettorati.py`, sincronizzazione del rapporto SF | job periodici |
| `pulisci_sinistri.py` | regola di conservazione dei file nel vault |
| `db/live`, `lavoro start/end`, `db/coda.json` | job e lease sul backend |
| ChiariBot (solleciti, atti firmati, stati da mail) | job periodici e triage della posta nella Regia |
| skill `sx-*`, agenti `pratica`/`esegui` | worker L3 con MCP |
| regole in `CLAUDE.md` | Regolario del tenant |
| connettore Gmail, Gmail in Chrome `/mail/u/2/` | posta su Supabase via API |

## 7. Rischi

- **Limiti di Apple Intelligence**: contesto piccolo sul dispositivo, quote PCC sconosciute,
  disponibilità per dispositivo e lingua, uso in background. Mitigazione: benchmark in F0 e
  ripiego automatico su Ollama o cloud.
- **Dati di terzi**: primo tenant reale di un altro titolare; l'audit del 2026-11-26 ha trovato
  tabelle `public` leggibili senza RLS. Nessun dato Chiari va importato prima della `041` in
  produzione e dei test di isolamento.
- **Collo di bottiglia Chrome**: una sola sessione ReClaim; la Regia serializza, non accelera.
- **Cambi del DOM di SF/ReClaim**: rompono l'estensione come oggi; i collaudi «senza modificare»
  dell'estensione restano.
- **Due motori** (Python e Swift) durante la transizione: i test golden sono il contratto.
- **Troppe Questioni**: soglie e raggruppamento, altrimenti il perito torna a fare tutto a mano.
- **Mac spento**: i job che richiedono Chrome o il dispositivo aspettano.

## 8. Decisioni aperte

1. **Fonte di verità durante la transizione.** Raccomandazione: PerX come copia fino a F4, passaggio
   in F9.
2. **Mac spento.** Raccomandazione: il Mac del perito resta il worker principale; un worker cloud
   di riserva esegue solo i compiti senza Chrome e senza dispositivo (triage posta con L3,
   solleciti).
3. **Motore lato server.** MCP ed estensione hanno bisogno di revisioni calcolate: core Swift
   compilato anche per Linux (servizio di calcolo) oppure calcolo sempre sulla Regia, con il
   backend che conserva e protegge le revisioni.
4. **Progetto Google della posta**: client PerX reso attendibile da Chiari, o client in un progetto
   di Chiari.
5. **ChiariBot**: worker sull'MCP o dismesso a favore della Regia.
6. **Uso di PCC e Claude per i dati Chiari**: da coprire nell'accordo sul trattamento dati.
7. **Profilo Chiari come «pacchetto di workflow»** riusabile per altri studi con gestionali diversi.

## 9. Misure di successo

- Obiettivo dichiarato di «sinistri chiari»: almeno 100 sinistri al mese, con meno tempo del
  perito per pratica.
- Quota di nuovi incarichi che arrivano ad ATTO_PRONTO senza Questioni.
- Questioni per pratica e tempo medio di risposta del perito.
- Rimandi della segreteria (CHIUSURA_DA_RIVEDERE) ogni 100 chiusure.
- Quota di compiti risolti a L0–L2; costo cloud e quota PCC per pratica.
- Tempo tra l'arrivo di una mail e l'aggiornamento della pratica.

---
Ultimo aggiornamento: 2026-11-27 (watch Gmail sull’API; F4 e F5 per ogni tenant)
