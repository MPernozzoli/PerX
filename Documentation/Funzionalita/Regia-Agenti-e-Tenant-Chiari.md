---
tags: [perx, funzionalita, ai, agenti, chiari, in-corso]
updated: 2026-11-27
---

# Regia agenti e tenant Chiari — piano di implementazione

> [!note] Stato al 2026-11-27 (revisione dei commit `17fe7bb`…`0e87d10`)
> - **F0** non fatta: manca l'accordo sul trattamento dati, il corpus e il benchmark. Il consenso
>   Workspace è di fatto risolto (il client OAuth è interno al Workspace Chiari).
> - **F1 fatta**: login Google (Supabase PKCE) su Mac, iPad e Lite; il backend accetta JWT legacy e
>   Supabase. Da irrobustire: vedi P0 in §10.
> - **F2 quasi fatta**: sync Gmail lato server, allegati, invio con firma, abbinamento mail→pratica,
>   route push con verifica OIDC. Manca il topic Pub/Sub: oggi vale il polling (~90 s).
> - **F3 parziale**: 273 pratiche importate una volta sola. Mancano dossier nel vault, polizze
>   `bignami`, test golden e un import periodico.
> - **F4/F5 solo struttura**: tabelle, API, scala e invarianti ci sono, ma nessun produttore di
>   lavori e nessun modello chiamato (né FoundationModels, né Ollama, né Claude).
> - **F6** solo vista minima; **F7–F9** non iniziate.
>
> Il piano di intervento con le priorità è in [[#10. Piano di intervento aggiornato (2026-11-27)]].

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

## 10. Piano di intervento aggiornato (2026-11-27)

Nasce dalla revisione dei commit `17fe7bb`…`0e87d10` (`git log d2fe5c6..HEAD`), controllata sul
codice punto per punto. Cosa va corretto e come si prosegue. Le fasi F0–F9 restano valide: questo
piano dice in che ordine toccarle. Voce di log: [[06-Decisioni-e-Intenzioni-Future]].

Legenda: **Chi** = *codice* (lo fa una sessione di sviluppo), *utente-console* (azione in una
dashboard o console), *decisione* (serve una scelta tua). **Dim.** = S (meno di mezza giornata),
M (1–2 giorni), L (più di 2).

Il problema 1 della revisione (secret Google nella storia git) non è pianificato: il progetto e
l'account Google sono stati cancellati.

### P0 — Integrità e sicurezza

Da fare prima di dare al perito (o a un agente) qualunque lavoro automatico.

**P0.1 — Distinguere il perito da un agente**
- *Problema (verificato).* `change_state` in `routes_regia.py` fissa `source = "perito"` e quindi il
  ramo «un agente cambia stato solo dentro un lavoro aperto» di `RegiaService.set_state` non è
  raggiungibile. `approve_revision` accetta qualunque utente del tenant e anche una revisione già
  superata (`superseded_at`): non vale «solo l'ultima stima vale». `save_revision` passa
  `amount_exception_reason` a chiunque e scavalca la regola dell'importo già proposto. Tutte le
  route usano `get_current_active_user`: worker, agenti e futuro MCP userebbero lo stesso token del
  perito.
- *Intervento.* Due tipi di token. Il perito ha il token di sessione di oggi (Supabase o legacy).
  Worker e agenti ricevono un **token agente**: JWT PerX di breve durata con claim `act=agent`,
  emesso da un endpoint che richiede il token del perito (`POST /auth/agent-token`). Una
  dipendenza `require_perito` rifiuta i token agente e protegge: approvazione di una revisione,
  stato «come perito», `amount_exception_reason`, conferma di una regola, risposta a una
  Questione, registrazione IBAN firmato. Le altre route accettano entrambi e ricavano `source`
  dal claim. `approve_revision` rifiuta le revisioni superate e quelle con hash economico diverso
  dall'ultima. `RegiaWorker` usa solo il token agente. I token senza claim valgono come perito
  (compatibilità), quindi gli utenti esistenti non cambiano.
- *File.* `backend/app/core/security.py`, `backend/app/api/v1/routes_auth.py`,
  `backend/app/api/v1/routes_regia.py`, `backend/app/services/regia_service.py`,
  `PerX/Services/Regia/RegiaWorker.swift` (solo la sorgente del token, da coordinare con chi lavora
  sui file Swift).
- *Test.* Token agente: 403 su approva, su stato come perito, su eccezione importo; 200 su lavoro
  e revisione. Approvare una revisione superata → errore. Un agente non cambia stato fuori da un
  lavoro aperto né dopo una scelta manuale del perito (oggi non coperto).
- *Fatto quando.* Con il solo token agente non esiste nessun percorso API che approvi una stima,
  prenda lo stato o forzi un importo; i test lo dimostrano.
- *Chi.* codice + decisione (D2). *Dim.* M. *Dip.* nessuna; sblocca P2 e F8.

**P0.2 — Stati coerenti: un campo per il codice del tenant**
- *Problema (verificato).* La voce «Stati Chiari rimappati sugli stati PerX» dice: `stato_corrente`
  = slug PerX, codice Chiari a parte, mappatura `perx_state()` (`chiari_states.py`). Il codice fa
  altro. `set_state` scrive il codice Chiari in `claim.stato_corrente` e lo salva in
  `manual_state_code` solo se è il perito. `_apply_review_state` scrive `da_revisionare` e perde
  quale esito Chiari vale (`DAL_PERITO`, `STIMA_DA_RIVEDERE`, `CHIUSURA_DA_RIVEDERE`: resta solo in
  `job.outcome`). In più l'import (`import_chiari_sinistri.py`) scrive il codice Chiari
  proprio in `manual_state_code` per tutte le 273 pratiche, come se fosse una scelta del perito.
- *Intervento.* Nuova colonna `claim_workflows.tenant_state_code` (migrazione `045`, additiva, con
  backfill da `manual_state_code`; poi `manual_state_code` e `manual_state_at` tornano a significare
  solo «scelta del perito» e il backfill li azzera dove `manual_state_at` è vuoto). `set_state`
  scrive `stato_corrente = perx_state(code)` e `tenant_state_code = code`; `manual_*` solo se
  `source == "perito"`. `_apply_review_state` scrive `da_revisionare` e `tenant_state_code` = esito
  del lavoro. L'import scrive `tenant_state_code`. Le viste leggono il codice del tenant da lì.
- *File.* `backend/app/models/regia.py`, nuova `backend/migrations/versions/045_*.py`,
  `backend/app/services/regia_service.py`, `backend/app/domain/chiari_import.py`,
  `backend/scripts/import_chiari_sinistri.py`, `backend/app/api/v1/routes_regia.py`
  (risposta di `change_state`). Poi correggere la voce «Stati Chiari rimappati» in 06 con una nuova voce.
- *Test.* Parametrizzato sui 14 codici: `set_state` produce lo slug atteso e conserva il codice;
  tre esiti di fine tentativi → tre codici distinti; la scelta del perito dopo l'inizio del
  lavoro non viene sovrascritta; round-trip dell'import.
- *Fatto quando.* Per ogni pratica si legge senza ambiguità slug PerX, codice del tenant e
  «ultima scelta manuale»; i conteggi per stato coincidono con il cruscotto locale.
- *Chi.* codice. *Dim.* M. *Dip.* P0.1 (stessa `set_state`); precede P1.3.

**P0.3 — Login Supabase: provider e verifica del token**
- *Problema (verificato).* `get_current_user` e `google_session` legano l'utente alla sola mail del
  token (`email`, `personal_email`, `professional_email`), senza controllare che l'identità venga
  da Google né che la mail sia verificata. Se in Supabase il provider email/password è attivo,
  chiunque registri quella mail può entrare come il perito. In più `get_supabase_user` chiama
  Supabase via HTTP a ogni richiesta: lento e dipendente dalla rete.
- *Intervento.* (a) In dashboard Supabase: disattiva il provider Email e le iscrizioni libere,
  lascia solo Google. (b) Nel codice: accetta il token solo se `app_metadata.provider == "google"`
  (o `identities` contiene Google) ed `email_verified` è vero; dopo il primo accesso lega per
  `idp_subject`, non per mail. (c) Verifica locale del JWT con JWKS (`/auth/v1/.well-known/jwks.json`
  del progetto), cache di 10 minuti, controllo di `iss`, `aud`, `exp`; ricarico delle chiavi solo se
  il `kid` è sconosciuto; se il progetto firma ancora con il segreto condiviso, usa quello. La
  chiamata HTTP resta solo nello scambio PKCE di `google_session`.
- *File.* `backend/app/core/security.py` (`get_supabase_user`, `get_current_user`),
  `backend/app/api/v1/routes_auth.py` (`google_session`), `backend/app/core/config.py`.
- *Test.* Token con provider `email` → 401; mail non verificata → 401; stesso `idp_subject` con mail
  cambiata → ok; JWKS in cache non richiama la rete; `kid` nuovo → una sola richiesta.
- *Fatto quando.* Provider Email spento e controllo attivo; una richiesta autenticata non fa più una
  chiamata a Supabase.
- *Chi.* utente-console (a) + codice (b, c). *Dim.* M. *Dip.* nessuna.

**P0.4 — Repo pubblico: dati reali nel vault e nel codice**
- *Problema (verificato).* La mail Chiari del perito compare in
  [[05-Stato-Sviluppo-e-Roadmap]] e in [[06-Decisioni-e-Intenzioni-Future]], ma anche in
  `backend/scripts/bootstrap_chiari.py` (solo il dominio), `backend/tests/test_chiari_tenant.py`
  e `backend/tests/test_gmail_sync.py`. Un numero sinistro Vittoria reale è in 06 (voce
  sull'abbinamento mail→pratica). La storia git conserva tutto. Questa nota non li ripete.
- *Intervento.* Due strade, la scelta è tua (D1). **Consigliata:** rendere il repo privato (azione in
  GitHub; poi controlla l'integrazione Vercel e i minuti di GitHub Actions). In ogni caso, nel vault:
  sostituire la mail con `perito@studio-chiari.example` e il numero con `NNN.YY.NNNNN` nelle due
  note; nel codice, sostituire gli indirizzi nei test con indirizzi fittizi e far leggere a
  `bootstrap_chiari.py` la mail da variabile d'ambiente. Riscrivere la storia
  (`git filter-repo` e force push) solo se il repo deve restare pubblico.
- *File.* `Documentation/05-Stato-Sviluppo-e-Roadmap.md`,
  `Documentation/06-Decisioni-e-Intenzioni-Future.md` (le voci passate sono append-only: qui è
  l'unica eccezione, una correzione di dati personali, e va dichiarata in una nuova voce),
  `backend/scripts/bootstrap_chiari.py`, i due test.
- *Test.* Un controllo CI che cerca nel repo i domini e i formati di numero reali noti (lista
  locale non committata) è facoltativo.
- *Fatto quando.* Repo privato oppure nessun dato reale in `HEAD` e storia ripulita.
- *Chi.* decisione (D1) + utente-console (privato) + codice (pulizia). *Dim.* S (privato) o M
  (con riscrittura). *Dip.* nessuna.

**P0.5 — Test mancanti sui percorsi critici**
- *Problema (verificato).* Esistono solo `test_chiari_tenant`, `test_gmail_sync`,
  `test_google_workspace_auth`, `test_regia_scala` (31 test, passano). Mancano test per
  `regia_service` (lease, stati, approvazione, gruppi, tentativi → Questione), per
  `google_session` e per la route `POST /emails/gmail/push`. Nel venv locale manca Pillow
  (ambiente, non codice).
- *Intervento.* Un file di test per ciascuno, con i casi elencati in P0.1, P0.2, P0.3 e P1.5;
  per la route push: token OIDC valido, token con audience errata, evento duplicato, errore
  transitorio che risponde 2xx senza perdere l'evento. Installare Pillow nel venv.
- *File.* `backend/tests/test_regia_service.py`, `test_google_session.py`, `test_gmail_push_route.py`.
- *Fatto quando.* I tre file passano in locale e in CI; la copertura di `regia_service.py` supera
  l'80%.
- *Chi.* codice. *Dim.* M. *Dip.* in parallelo a P0.1–P0.3 (ogni intervento porta i suoi test);
  qui si chiude il resto.

### P1 — Basi affidabili

**P1.1 — CI backend verde**
- *Problema.* `alembic upgrade head` su database vuoto fallisce (`relation "documents" does not
  exist`): una migrazione storica presuppone tabelle create fuori da Alembic. Le migrazioni `043` e
  `044` non vengono mai verificate in CI.
- *Intervento.* Individuare la prima migrazione che nomina `documents` e scegliere: (a) baseline
  — una migrazione iniziale che crea lo schema attuale — oppure (b) in CI, partire da uno schema
  di produzione (`pg_dump --schema-only`, senza dati), fare `alembic stamp` alla revisione
  corrispondente e `upgrade head`. Consigliata (b): non tocca la storia delle migrazioni. Aggiungere
  alla CI un passo che verifica `043`/`044`/`045` e il downgrade di `045`.
- *File.* `.github/workflows/backend-ci.yml`, `backend/migrations/versions/`, nuova
  `backend/tests/schema_baseline.sql`.
- *Test.* La CI stessa: `upgrade head` da baseline, poi `pytest`.
- *Fatto quando.* La CI backend su `main` è verde e include `043`–`045`.
- *Chi.* codice (+ utente-console per estrarre lo schema di produzione). *Dim.* L. *Dip.* nessuna.

**P1.2 — CI web verde**
- *Problema (verificato).* In `apps/perx-insight-studio` due commenti
  `eslint-disable-next-line @next/next/no-img-element` (`src/components/SiteHeader.tsx:31`,
  `src/components/story/StoryFrame.tsx:89`) citano una regola che la configurazione condivisa
  `packages/eslint-config/react-vite.mjs` non definisce. ESLint segnala «rule not found».
- *Intervento.* Togliere i due commenti (il progetto non usa `eslint-config-next`), oppure sostituire
  `<img>` con `next/image` e aggiungere la regola. Consigliato: togliere i commenti.
- *Test.* `npm run lint` e `npm run build` in `apps/perx-insight-studio`.
- *Fatto quando.* La CI Web è verde su `main`.
- *Chi.* codice. *Dim.* S. *Dip.* nessuna.

**P1.3 — Import periodico delle pratiche, idempotente, con report**
- *Problema (verificato).* La copia è ferma a ieri e il sistema locale cambia ogni giorno.
  `import_chiari_sinistri.py --apply` fa `ON CONFLICT DO UPDATE` su `stato_corrente`,
  `stato_substati`, importi e `manual_state_code`: rilanciato, **sovrascriverebbe** quello che PerX
  ha cambiato nel frattempo (stato scelto dal perito, esiti della Regia).
- *Intervento.* Modalità `--sync` (prova a vuoto di default). Regole: il locale vince finché non
  passa la fonte di verità (§8.1, F9) **tranne** dove PerX ha una scelta più recente
  (`manual_state_at` dopo l'ultimo import) o un lavoro aperto: lì il campo non si tocca e finisce
  nel report come «in conflitto». Per ogni pratica un `import_hash` dei campi di origine, così si
  aggiorna solo ciò che è cambiato. Eventi e revisioni restano append-only
  (`ON CONFLICT DO NOTHING`). Report JSON e testo: nuove, cambiate (campo, prima, dopo), in
  conflitto, sparite dal locale. Pianificazione: `launchd` sul Mac del perito, ogni ora, perché il
  JSON sta lì; all'avvio del sync verifica che il backend sia raggiungibile.
- *File.* `backend/scripts/import_chiari_sinistri.py`, `backend/app/domain/chiari_import.py`,
  nuova migrazione per `import_hash` (può stare nella `045`), `.plist` launchd fuori repo.
- *Test.* Secondo lancio senza modifiche → zero differenze; stato scelto dal perito dopo
  l'import → non sovrascritto e segnalato; pratica cancellata in locale → «sparita», non
  cancellata.
- *Fatto quando.* Per una settimana il report orario non mostra differenze inattese e i conteggi
  per stato coincidono con il cruscotto.
- *Chi.* codice + utente-console (installare il launchd). *Dim.* M. *Dip.* P0.2; decisione D4.

**P1.4 — Chiave del token Gmail dedicata e ruotabile**
- *Problema (verificato).* `_fernet()` in `google_workspace_auth.py` deriva la chiave da
  `SECRET_KEY` con SHA-256: ruotare il secret rende illeggibile il token della casella.
- *Intervento.* Variabile `GOOGLE_TOKEN_KEYS` (lista separata da virgole di chiavi Fernet; la prima
  cifra, tutte decifrano) con `MultiFernet`. Finché è vuota resta la derivazione attuale (solo per
  leggere). Script `rotate_google_tokens.py` che ricifra le righe con la prima chiave.
- *File.* `backend/app/services/google_workspace_auth.py`, `backend/app/core/config.py`, nuovo
  script in `backend/scripts/`.
- *Test.* Cifro con A, aggiungo B in testa, leggo ancora; ricifro; tolgo A, leggo ancora;
  token legacy ancora leggibile.
- *Fatto quando.* In produzione c'è la chiave dedicata, i token sono ricifrati e ruotare
  `SECRET_KEY` non li rompe.
- *Chi.* codice + utente-console (generare la chiave e inserirla nelle variabili di Render).
  *Dim.* S. *Dip.* nessuna.

**P1.5 — Topic Pub/Sub per la push Gmail**
- *Problema (verificato).* `GMAIL_PUBSUB_TOPIC` è vuoto: `users.watch` non parte e il server fa
  polling ogni ~90 s (`GMAIL_SYNC_POLL_SECONDS`). La route e la verifica OIDC (`GMAIL_PUSH_AUDIENCE`,
  `GMAIL_PUSH_SERVICE_ACCOUNT`) sono pronte.
- *Intervento.* Nel progetto Google di Chiari: creare il topic, dare il ruolo Publisher a
  `gmail-api-push@system.gserviceaccount.com`, creare una sottoscrizione push verso
  `/api/v1/emails/gmail/push` con token OIDC (account di servizio dedicato), impostare su Render
  `GMAIL_PUBSUB_TOPIC`, `GMAIL_PUSH_SERVICE_ACCOUNT` e, se serve, `GMAIL_PUSH_AUDIENCE`. Tenere il
  polling come ripiego.
- *File.* Nessuno (variabili d'ambiente); aggiornare [[04-Infrastruttura-e-Deploy]].
- *Test.* Invio una mail alla casella: compare in `emails` entro pochi secondi, senza aspettare il
  polling; spegnendo la sottoscrizione il polling la recupera.
- *Fatto quando.* È vero il criterio di F2 (arrivo immediato, tetto di 60 s sul Mac).
- *Chi.* utente-console. *Dim.* S. *Dip.* P0.3 non serve; meglio dopo P0.5 (test della route).

**P1.6 — Lease con lock vero**
- *Problema (verificato).* `lease_next` legge i job `pending` e poi scrive, senza
  `SELECT … FOR UPDATE SKIP LOCKED`: due worker possono prendere lo stesso job e superare la
  capacità di `chrome` e `modello_locale`. L'indice `uq_regia_one_open_job_per_claim` evita due job
  aperti sulla stessa pratica, ma non la doppia presa di uno stesso job né il limite per risorsa.
- *Intervento.* Dentro la transazione: `pg_advisory_xact_lock` su (tenant, risorsa) per serializzare
  il conteggio della capacità, poi `SELECT … FOR UPDATE SKIP LOCKED LIMIT 1` sul candidato; stessa
  cosa per il rilascio dei lease scaduti. Il conteggio dei job occupati si rifà dopo il lock.
- *File.* `backend/app/services/regia_service.py` (`lease_next`).
- *Test.* Due sessioni concorrenti su Postgres: un solo job per risorsa con capacità 1; nessun job
  preso due volte; lease scaduto ripreso da un solo worker.
- *Fatto quando.* Il test di concorrenza passa 100 volte di fila.
- *Chi.* codice. *Dim.* M. *Dip.* P1.1 (serve Postgres in CI).

### P2 — Far lavorare davvero la Regia

**P2.1 — Primo produttore: mail → `classifica_mail`**
- *Problema (verificato).* I lavori nascono solo da `POST /regia/lavori`; la sync Gmail non
  accoda nulla (`classifica_mail` compare solo in `regia_scala.py`).
- *Intervento.* In `GmailSyncService._import_message`, per ogni mail **in arrivo e nuova** (non
  inviata, non spam) accodare un lavoro `classifica_mail` con `idempotency_key =
  "mail:{email_id}"`, risorsa decisa al lease (vedi P2.4), `claim_id` vuoto: la pratica trovata da
  `claim_mail_match` va in `input_json` e non occupa il «un lavoro per pratica». Il lavoro non cambia
  stati: salva classificazione, confidenza e pratica proposta in `result_json`, e la Sala regia la
  mostra. Le azioni (atto firmato → DA_CHIUDERE ecc., §3.2) arrivano dopo, dietro Questione.
- *File.* `backend/app/services/gmail_sync_service.py`, `backend/app/services/regia_service.py`
  (`enqueue_job` con chiave), `backend/app/domain/regia_scala.py`.
- *Test.* Sync di due mail → due lavori; secondo passaggio sulle stesse mail → nessun duplicato;
  mail inviata o spam → nessun lavoro; errore di accodamento non blocca l'import della mail.
- *Fatto quando.* Ogni mail nuova ha un lavoro `classifica_mail` visibile nella Sala regia.
- *Chi.* codice. *Dim.* M. *Dip.* P0.1, P1.6.

**P2.2 — Primo compito L1 reale: classificazione con FoundationModels**
- *Problema (verificato).* `RegiaWorker` per L0 rimanda indietro i campi dell'input e per L1–L3
  risponde «rinviato»: nessun modello viene chiamato.
- *Intervento.* Per `classifica_mail`: sessione `SystemLanguageModel` con istruzioni dalle regole
  attive (`GET /regia/compiti/classifica_mail`), uscita `@Generable` (`categoria` come enum chiuso,
  `riferimentoChiari`, `numeroSinistro`, `importi`, `confidenza`). Validatore L0 sul backend
  (`controllo_l0`) e sul Mac: categoria nell'enum; ogni riferimento, importo o IBAN dichiarato
  deve comparire nel testo della mail (nessun dato inventato); mod-97 sugli IBAN. Se non passa →
  sale a L3 (scala di §3.1), se L1 non è disponibile (`SystemLanguageModel.availability`) → «rinviato»
  senza consumare tentativi. Tutto dietro `#available` (deployment target macOS 26 / iOS 26.2).
  Registrare livello e durata nel lavoro.
- *File.* `PerX/Services/Regia/RegiaWorker.swift` e un nuovo file per il compito,
  `backend/app/domain/regia_scala.py` (`controllo_l0`). Sono file Swift: farlo solo quando la sessione
  attiva sull'app ha finito, o in un ramo separato.
- *Test.* Protocollo `ModelRunner` con un modello finto: uscita valida, uscita con IBAN inventato
  (→ salita), modello assente (→ rinviato). Backend: casi del validatore.
- *Fatto quando.* 50 mail reali dal corpus (anche solo da P2.5) sono classificate da L1 con
  un'accuratezza misurata e annotata nella tabella «compito → livello» di F0.
- *Chi.* codice. *Dim.* L. *Dip.* P2.1; P2.5 per la misura.

**P2.3 — `mac_idle` vero**
- *Problema (verificato).* Il worker invia `mac_idle: !NSApp.isActive`: significa «l'app non è in
  primo piano», non «il Mac è libero». La coda locale usa `HIDIdleTime` (soglia `CODA_IDLE_SEC`,
  300 s) e il carico (`getloadavg` oltre `max(cpu·0,7; 2,5)`).
- *Intervento.* Funzione `MacActivity.isIdle()` con `IOHIDSystem` (`HIDIdleTime`) sopra soglia e
  `getloadavg` sotto soglia, stessi valori della coda; soglie configurabili nelle impostazioni
  della Regia. Spiegare nella Sala regia perché un lavoro aspetta («Mac in uso»).
- *File.* `PerX/Services/Regia/RegiaWorker.swift`, nuovo `PerX/Services/Regia/MacActivity.swift`.
- *Test.* Funzione pura `isIdle(hidSeconds:load:cpus:)` con casi limite; prova manuale: muovere il
  mouse sposta il lavoro in attesa.
- *Fatto quando.* Un lavoro `modello_locale` non parte mentre il perito usa il Mac.
- *Chi.* codice. *Dim.* S. *Dip.* nessuna (Swift: stessa avvertenza di P2.2).

**P2.4 — Risorsa coerente con il livello (L2)**
- *Problema (verificato).* In `regia_scala.py` L2 usa sempre `modello_locale`, anche se L2 è prima di
  tutto Private Cloud Compute (che non occupa il Mac e ha una quota).
- *Intervento.* La risorsa si decide al lease dal livello e dal motore scelto: L1 e L2-Ollama →
  `modello_locale`; L2-PCC → `pcc` (quota); L3 → `cloud`; L4 → `perito`. `enqueue_job` lascia la
  risorsa vuota per i compiti con scala.
- *File.* `backend/app/domain/regia_scala.py`, `backend/app/services/regia_service.py`.
- *Test.* Tabella livello → risorsa; salita da L1 a L2 cambia risorsa e ricontrolla la capacità.
- *Fatto quando.* Un compito L2-PCC non resta bloccato da un lavoro `modello_locale`.
- *Chi.* codice. *Dim.* S. *Dip.* P1.6.

**P2.5 — Benchmark F0 sul corpus**
- *Problema.* Non c'è il corpus né la tabella «compito → livello minimo affidabile».
- *Intervento.* Dalle pratiche di «sinistri chiari» estrarre in locale (mai nel repo): mail già
  classificate dagli eventi, atti firmati con IBAN verificato, foto classificate, revisioni
  approvate. Un piccolo strumento locale lancia ogni compito di §3.4 su L1, L2 (PCC e Ollama) e L3 e
  scrive precisione, tempo e costo. Il risultato (solo i numeri) va in §3.4.
- *File.* Strumento fuori repo (cartella «sinistri chiari»); nota aggiornata: §3.4 di questo piano.
- *Test.* Il corpus ha un sottoinsieme «difficile» (mail ambigue, IBAN sbagliati) per misurare i
  falsi positivi.
- *Fatto quando.* La tabella ha i numeri per mail, atto firmato e foto (i compiti L1) e per polizza
  e input stima (L2).
- *Chi.* codice + decisione (D3, D5). *Dim.* L. *Dip.* D5 per L2/L3 con dati reali; L1 on-device no.

### P3 — Il resto, in ordine

1. **Dossier e polizze nel vault (F3).** Caricare i file dei dossier su Storage con struttura
   `chiari/{riferimento}/…`; importare le polizze nello schema `bignami`. *Codice + utente-console
   (credenziali Storage). L.* Dip. P1.3.
2. **Test golden (F3).** Ogni revisione approvata del corpus deve dare gli stessi importi, lo
   stesso modello ReClaim, le stesse spunte con `ChiariStimaWorkflow.swift` e con
   `chiari_stima.py`; le differenze volute si scrivono. Rimuove il rischio dei «due motori»
   (§7). *Codice. L.* Dip. P2.5 (corpus).
3. **Sala regia completa (F6).** Agenti al lavoro, Questioni con prove e opzioni, approvazioni
   (solo con token perito, P0.1), Kanban, Per oggi, notifiche. *Codice. L.* Dip. P0.1, P2.1.
4. **Estensione collegata (F7).** URL del backend configurabile e autenticazione con l'utente PerX,
   poi native messaging. *Codice. L.* Dip. P0.1.
5. **MCP e agenti esterni (F8).** Server MCP remoto senza strumenti di approvazione; usa il token
   agente di P0.1. *Codice + decisione (8.3, 8.5). L.* Dip. P0.1, P2.2.
6. **Passaggio e dismissione (F9).** Un mese in parallelo, poi PerX come fonte di verità. *Decisione
   (8.1) + utente-console. M.* Dip. P1.3, P3.2, P3.3, P3.4.

Igiene dei commit (punto 9 della revisione, senza intervento sul codice): `0e87d10` mescola sito
marketing, Gmail e Regia. Da ora un commit per argomento (backend Regia, backend Gmail, app, sito
web). Non riscrivere `main`.

### Ordine consigliato

1. **Subito, in parallelo:** P0.4 (decisione D1 e pulizia) · P0.3(a) (spegnere il provider
   Email) · P1.2 (CI Web, 10 minuti) · P1.4 con la chiave nuova · P1.5 (topic).
2. **Backend, in sequenza:** P0.1 → P0.2 → P0.3(b,c) → P0.5. Sono tre aree che toccano
   `regia_service.py` e `security.py`: meglio non farle in parallelo.
3. **Basi:** P1.1 (CI backend) → P1.6 (lease) → P1.3 (import periodico).
4. **Regia viva:** P2.4 e P2.3 (piccoli) → P2.1 → P2.2, con P2.5 che parte appena c'è D5.
5. **Poi P3** nell'ordine elencato.

Regola di sicurezza del piano: **nessun lavoro automatico che cambi stati o importi gira in
produzione prima della chiusura di P0.1 e P0.2.**

### Decisioni che servono da te

- **D1 — Repo.** Lo rendiamo privato (consigliato) o resta pubblico con pulizia della storia?
- **D2 — Agente o perito.** Va bene il token agente separato di P0.1 (consigliato), con approvazione
  solo dall'app del perito? L'alternativa è la conferma interattiva per ogni azione sensibile, che non
  funziona per MCP e worker.
- **D3 — Corpus.** Posso estrarre dalle pratiche locali un campione per il benchmark, che resta sul
  tuo Mac? Quante pratiche, e per le mail vuoi oscurare i nomi?
- **D4 — Import periodico.** Ogni ora va bene? In caso di conflitto vince il locale (consigliato fino
  a F4) o PerX? Richiama §8.1, non la riscrive.
- **D5 — Dati di Chiari ai livelli L2/L3.** L'accordo sul trattamento dati (§8.6, F0) copre PCC e
  Claude? Finché non è firmato, il benchmark e i compiti con dati reali restano a L1 e Ollama.

Restano aperte, senza cambiare, le decisioni 8.1, 8.2, 8.3, 8.5 e 8.7. La 8.4 (progetto Google della
posta) è di fatto risolta: il client OAuth è interno al Workspace Chiari.

---
Ultimo aggiornamento: 2026-11-27 (piano di intervento aggiornato, §10)
