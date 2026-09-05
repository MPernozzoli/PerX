---
tags: [perx, funzionalita, ai, ollama]
updated: 2026-09-05
---

# AI locale e cloud

PerX combina AI locale (privacy, nessuna dipendenza da rete/costi cloud per certi task) e AI
cloud (modelli più capaci per compiti che lo richiedono).

## Agenti AI applicativi: Elettra e Sparky

Sul piano di prodotto (fonte: `Documentation/Studio_Randa_Process_Deck.pptx`, 2026-06) l'AI di
PerX è presentata all'utente come due agenti dedicati:

- **⚡ Elettra — la segretaria virtuale dello studio**: triage automatico di mail, WhatsApp e
  Telegram con generazione dei task corretti (vedi [[Comunicazioni]], [[Gestione-Sinistri]]);
  bozze di risposta pronte per approvazione del perito; verifica di conformità della perizia ai
  protocolli di compagnia; coordinamento di assegnazioni e calendario di lavoro; può operare sui
  portali delle compagnie per integrarli in PerX.
- **✦ Sparky — il perito esperto dello studio**: assiste nella compilazione guidata della perizia
  tecnica; accede al database normativo, tabelle e precedenti per le stime di danno; suggerisce
  completamenti automatici basati su sinistri analoghi; effettua il controllo "authority" (segnala
  se l'importo richiede passaggio al controllore — vedi [[Gestione-Sinistri]]); supporta i CAT
  nelle verifiche e nei sopralluoghi su iPad.

Questi nomi sono il framing di prodotto rivolto a periti/compagnie; a livello tecnico si
appoggiano ai componenti descritti sotto (`AIManager`, `CloudAIService`/`ClaudeAIService`,
`LocalModelService`, servizi backend `ai_*`). Se nel codice emerge una mappatura esplicita
nome-agente ↔ servizio, aggiornare questa nota con il collegamento preciso.

## Local Agent (AI locale su macOS)

`PerXLocalAgentClient` è **l'unico confine** tra l'app e le dipendenze locali esterne: i servizi
applicativi non lanciano comandi, non ispezionano path di installazione tool, non chiamano
direttamente gli endpoint HTTP di Ollama.

Responsabilità del Local Agent:
- discovery e stato strutturato delle dipendenze: Homebrew, Python, Node.js, Ollama, ZIP/Unzip;
- monitoraggio periodico delle dipendenze;
- installazione/aggiornamento via Homebrew dove supportato;
- esecuzione script Python per compatibilità Excel, bridging MLX legacy, build RAG;
- creazione archivi ZIP;
- lifecycle di Ollama (avvio/health check/lista modelli/import GGUF/generazione testo, streaming
  e richieste vision).

Funzionalità Swift-native e chiamate a API remote (Cloud, Hub, OAuth) **restano nell'app** e non
sono proxate dal Local Agent.

### Route Ollama

Solo il Local Agent parla con Ollama:
- `GET http://localhost:11434/api/tags` — health check + lista modelli.
- `POST http://localhost:11434/api/generate` — generazione testo locale (lo stesso endpoint
  riceve un array `images` per l'analisi vision locale).

`LocalAIService` è la facciata app-facing: valida la configurazione del modello e delega ogni
operazione Ollama a `PerXLocalAgentClient`.

### Architettura XPC

`PerX Local Agent` è un servizio XPC embedded, bundle id `it.pernozzoli.PerX.LocalAgent`. Xcode lo
impacchetta sotto `PerX.app/Contents/XPCServices` e lo firma insieme all'app.

- L'app compila solo `XPCPerXLocalAgentClient`: serializza richieste via `NSXPCConnection`, riceve
  errori strutturati e usa un endpoint XPC di callback per i token Ollama in streaming.
- Il target helper (`PerXLocalAgentService/`) compila `InProcessPerXLocalAgent`: è l'unico
  componente che lancia processi, ispetta path eseguibili locali o contatta endpoint Ollama su
  localhost.
- `PerXLocalAgentShared/` contiene i contratti condivisi tra client e servizio.
- Il servizio XPC avvia il monitoraggio delle dipendenze quando viene attivato: refresh delle
  versioni installate a ogni heartbeat, controllo aggiornamenti Homebrew a cadenza più lenta. Un
  futuro LaunchAgent potrebbe adottare lo stesso contratto `PerXLocalAgentClient` per continuare
  il monitoraggio anche a PerX chiuso (non ancora implementato).

### Distribuzione
Target principale per Developer ID diretto, hardened runtime, no assunzioni sandbox App Store.
Per il rilascio: archiviare e notarizzare l'intero bundle (app + XPC service annidato), mantenendo
hardened runtime attivo sull'XPC service, con lo stesso workflow Developer ID.

## AI lato app (`PerX/Services/AI/`)

- `AIManager` — orchestratore.
- `CloudAIService` / `ClaudeAIService` — AI cloud.
- `LocalModelService` — AI locale (si appoggia al Local Agent per Ollama).

## AI lato backend

- `routes_ai_chat.py`, `routes_ai_prompts.py`, `routes_ai_routing.py`.
- Modelli: `ai_chat.py`, `ai_prompt_template.py`, `ai_prompt_template_version.py` (versioning dei
  prompt), `ai_routing_policy.py`, `ai_analysis_run.py`.
- `communication_ai_triage.py` — triage assistito da AI sulle comunicazioni in ingresso.
- Sviluppo recente (da migrazioni Alembic): **AI prompt versioning & routing runs**, seed di
  default prompt AI per sinistri.

## Process jobs verso il Mac mini

Per lavoro pesante o legato a risorse locali (es. analisi con modello MLX), il backend non esegue
il lavoro nel processo API: accoda un record in `process_jobs`. Un worker sul Mac mini fa polling
(`GET /api/v1/process-jobs/jobs/claim?worker_id=<id>&limit=3` con header
`X-PerX-Worker-Secret`), invia heartbeat se il lavoro dura a lungo, poi chiude con `complete` o
`fail`. Automazione già accodata: `local_ai.diary_entry_analysis` (comunicazioni/allegati legati a
un sinistro). Feature flag: `FF_LOCAL_AI_PROCESS_JOBS_ENABLED`. Vedi anche
[[04-Infrastruttura-e-Deploy]].

---
Ultimo aggiornamento: 2026-09-05
