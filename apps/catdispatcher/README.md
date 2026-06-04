# CAT Dispatcher

**CAT Dispatcher** è una piattaforma operativa progettata per supportare l’assegnazione, il coordinamento e il monitoraggio degli incarichi peritali sul territorio nazionale, con particolare attenzione ai **Centri di Assistenza Tecnica (CAT)** e alle reti di tecnici e periti sul campo.

Il progetto nasce dall’esigenza concreta di **studi peritali** e **strutture che coordinano sopralluoghi** per superare una gestione frammentata e spesso manuale dell’assegnazione incarichi, introducendo uno strumento capace di integrare:

- dati territoriali;
- logiche operative;
- informazioni su CAT, periti e tecnici;
- visione d’insieme del presidio sul territorio

in un’unica interfaccia operativa.

---

## Contesto operativo

Nel dominio dei **CAT (Centri di Assistenza Tecnica)** e degli **studi peritali** che operano su tutto il territorio nazionale, la gestione dei sopralluoghi e delle uscite tecniche richiede di:

- coordinare reti di periti e tecnici distribuiti;
- presidiare eventi diffusi (ad esempio eventi atmosferici) o picchi di sinistrosità;
- garantire copertura territoriale coerente con gli SLA operativi;
- ridurre gli sprechi dovuti a assegnazioni poco efficienti o non bilanciate.

CAT Dispatcher è pensato come **“regia” geografica e operativa** di questo ecosistema: mette a fuoco dove sono i sinistri, dove sono le risorse, come vengono distribuiti i carichi e quali aree risultano scoperte o critiche.

---

## Visione

Nella gestione degli incarichi peritali, soprattutto in contesti ad alto volume o in presenza di eventi atmosferici diffusi, la distribuzione del lavoro sul territorio tende a diventare rapidamente inefficiente.

Le criticità più comuni sono note:

- assegnazioni gestite manualmente;
- visione parziale della copertura territoriale;
- difficoltà nel bilanciare carichi di lavoro e prossimità geografica;
- tempi decisionali rallentati;
- scarsa leggibilità complessiva del presidio operativo;
- dipendenza da fogli di calcolo, mappe statiche o conoscenza informale del territorio.

**CAT Dispatcher** nasce per affrontare questo problema in modo strutturato, offrendo un sistema che consenta di leggere il territorio, localizzare le risorse disponibili e facilitare l’assegnazione degli incarichi secondo criteri più razionali, tracciabili e scalabili.

---

## Obiettivi del progetto

- Centralizzare la gestione della distribuzione incarichi su base geografica.
- Migliorare la visibilità del presidio territoriale.
- Ridurre tempi e inefficienze nelle assegnazioni.
- Supportare decisioni più coerenti nella selezione del perito o della struttura operativa più adatta.
- Offrire una base dati territoriale interrogabile e aggiornabile.
- Rendere più leggibile il rapporto tra aree, carichi, disponibilità e copertura.

---

## Funzionalità previste

Le funzionalità di CAT Dispatcher possono evolvere nel tempo, ma il sistema ruota intorno ai seguenti nuclei principali.

### 1. Mappatura territoriale
- Visualizzazione geografica di periti, zone e aree operative
- Lettura della copertura territoriale
- Navigazione su mappa
- Supporto a livelli informativi territoriali

### 2. Gestione risorse
- Anagrafica periti e collaboratori
- Associazione a province, regioni, aree o cluster territoriali
- Attributi operativi e specializzazioni
- Disponibilità e criteri di assegnazione

### 3. Supporto all’assegnazione incarichi
- Individuazione della risorsa territorialmente più adatta
- Supporto alla distribuzione degli incarichi su base geografica
- Riduzione delle assegnazioni arbitrarie o non ottimizzate
- Possibilità di applicare logiche di prossimità, presidio e bilanciamento

### 4. Monitoraggio operativo
- Visione d’insieme del presidio sul territorio
- Individuazione di aree scoperte o sovraccariche
- Migliore controllo dei flussi in situazioni ordinarie o emergenziali
- Supporto alla lettura rapida del contesto operativo

### 5. Evoluzioni future
- Integrazione con sistemi gestionali esterni
- Filtri avanzati e criteri di dispatch automatico o semiassistito
- Analisi storica delle assegnazioni
- Dashboard di sintesi
- Automazioni su eventi CAT o picchi territoriali

## API PerX

CatDispatcher è integrato nella repo PerX come frontend separato, ma usa il backend PerX e lo stesso database Supabase. Il frontend configura `VITE_PERX_API_BASE_URL` e chiama solo endpoint `/api/v1/cat-dispatcher/*`.

Endpoint principali:

- `GET /api/v1/cat-dispatcher/map-data`: dati mappa, comuni, CAT e associazioni.
- `GET /api/v1/cat-dispatcher/search?query=...`: ricerca comuni, quartieri e CAT.
- `GET /api/v1/cat-dispatcher/communes/{id}`: dettaglio comune/quartiere, CAT associati e sospensioni.
- `POST /api/v1/cat-dispatcher/get-cat-by-commune`: lookup CAT economico da comune/provincia.
- `POST /api/v1/cat-dispatcher/dispatch/requests`: crea una richiesta di dispatch da PerX, portale assicurati o inserimento manuale.
- `POST /api/v1/cat-dispatcher/dispatch/insured-windows`: salva le finestre di disponibilità proposte dall'assicurato.
- `POST /api/v1/cat-dispatcher/dispatch/availability-rules`: sostituisce le regole settimanali di disponibilità di un CAT.
- `POST /api/v1/cat-dispatcher/dispatch/availability-overrides`: registra eccezioni giornaliere, blocchi o capacità ridotta.
- `GET /api/v1/cat-dispatcher/dispatch/availability?cat_id=...`: legge disponibilità ricorrenti ed eccezioni.
- `POST /api/v1/cat-dispatcher/dispatch/assignments`: crea o conferma una proposta CAT-richiesta.
- `POST /api/v1/cat-dispatcher/dispatch/route-plans`: crea un piano giro iniziale per un CAT e una data.

Il primo algoritmo di route planning è volutamente deterministico: ordina gli appuntamenti già schedulati e poi le richieste per priorità. La struttura dati è pronta per sostituire questo passaggio con un ottimizzatore geografico senza cambiare il contratto API.

---

## Filosofia del prodotto

CAT Dispatcher è costruito attorno ad alcuni principi chiave.

### Territorialità reale, non astratta
L’assegnazione degli incarichi non è solo un problema amministrativo: è un problema geografico, logistico e operativo. Il sistema deve quindi partire dalla mappa, non ignorarla.

### Supporto decisionale, non scatola nera
Il prodotto deve aiutare chi coordina le assegnazioni a decidere meglio, più velocemente e con maggiore coerenza, senza nascondere la logica dietro automatismi opachi.

### Integrazione con il lavoro esistente
CAT Dispatcher non nasce per sostituire con brutalità gli strumenti già in uso, ma per aggiungere un livello di controllo, chiarezza e capacità operativa dove oggi spesso esistono solo prassi manuali.

### Scalabilità operativa
Il sistema è pensato per funzionare sia in contesti ordinari sia in scenari ad alta intensità operativa, dove rapidità, copertura e leggibilità diventano essenziali.

---

## A chi si rivolge

CAT Dispatcher è pensato per:

- studi peritali;
- centrali operative;
- strutture che coordinano incarichi distribuiti sul territorio;
- organizzazioni che gestiscono reti di periti o tecnici esterni;
- team coinvolti nella gestione di eventi CAT o picchi di sinistrosità;
- realtà che necessitano di una lettura geografica del proprio presidio operativo.

---

## Perché CAT Dispatcher

CAT Dispatcher nasce da un’esigenza concreta:

**trasformare la distribuzione geografica degli incarichi da processo artigianale e dispersivo a flusso leggibile, governabile e supportato da dati territoriali.**

Dove oggi spesso esistono:
- assegnazioni decise “a memoria”;
- strumenti scollegati tra loro;
- mappe non operative;
- coperture territoriali poco chiare;
- sovraccarichi non visibili;

CAT Dispatcher punta a introdurre:
- ordine;
- visibilità;
- criterio;
- rapidità;
- tracciabilità;
- maggiore qualità decisionale.

---

## Stato del progetto

CAT Dispatcher è un progetto in fase di sviluppo ed evoluzione.

Alcune componenti possono trovarsi in una delle seguenti fasi:
- definizione concettuale;
- prototipazione;
- sviluppo attivo;
- test su casi d’uso reali;
- validazione operativa.

Roadmap, architettura e funzionalità vengono aggiornate progressivamente sulla base delle priorità di prodotto e delle esigenze riscontrate nei flussi reali.

---

## Tech direction

L’architettura di CAT Dispatcher è orientata a privilegiare:

- chiarezza visiva e operativa;
- centralità del dato geografico;
- modularità dell’applicazione;
- facilità di aggiornamento delle informazioni territoriali;
- integrazione con basi dati e strumenti esterni;
- possibilità di evoluzione verso logiche di dispatch assistito o automatizzato.

> Nota: stack tecnologico, componenti e modalità di integrazione possono evolvere nel corso dello sviluppo.

### Stack applicativo (frontend)

L’applicazione è attualmente sviluppata come **frontend web** basato su:

- **Vite** come tool di build (`vite`, `vite preview`);
- **React 18** + **TypeScript**;
- **React Router** per la navigazione interna;
- **Tailwind CSS** (con preset `tailwindcss-animate`, tipografia, utility) e componentistica **shadcn/UI** basata su **Radix UI**;
- **@tanstack/react-query** per la gestione delle chiamate dati e della cache;
- **Backend PerX** come unico accesso ad autenticazione, API e database Supabase condiviso;
- **maplibre-gl** e librerie **@turf** per la componente geografica / mappa;
- varie utility per form (`react-hook-form`, `zod`, `@hookform/resolvers`), grafici (`recharts`), notifiche (`sonner`) e layout (pannelli ridimensionabili, ecc.).

### Comandi principali

Dal root del progetto:

- `npm run dev` – avvio ambiente di sviluppo Vite;
- `npm run build` – build di produzione;
- `npm run build:dev` – build in modalità sviluppo;
- `npm run preview` – anteprima della build;
- `npm run lint` – esecuzione ESLint sul codice.

---

## Casi d’uso tipici

Tra i principali casi d’uso del progetto:

- localizzare i periti disponibili in una determinata area;
- verificare la copertura territoriale di una rete tecnica;
- supportare l’assegnazione di nuovi incarichi in base alla zona;
- leggere rapidamente concentrazioni territoriali e squilibri operativi;
- intervenire con maggiore rapidità in caso di eventi diffusi o picchi di attività;
- costruire una base informativa più solida per il coordinamento operativo.

---

## Contributi

Al momento il progetto è sviluppato in forma controllata e non accetta contributi pubblici aperti.

Per collaborazioni tecniche, partnership o richieste di approfondimento, fare riferimento ai contatti del team responsabile del progetto.

---

## Riservatezza e utilizzo

Questo repository può contenere codice, strutture dati, logiche operative, materiali tecnici e documentazione riservata o proprietaria.

Salvo diversa indicazione esplicita:
- il contenuto non è da considerarsi liberamente riutilizzabile;
- non è autorizzata la redistribuzione non concordata;
- parti del progetto possono essere soggette a revisione, riorganizzazione o sostituzione.

---

## Roadmap indicativa

- Definizione del modello territoriale
- Gestione anagrafica delle risorse operative
- Visualizzazione e interrogazione su mappa
- Supporto all’assegnazione geografica
- Filtri e criteri di dispatch
- Dashboard operative e analisi
- Integrazioni con sistemi gestionali esterni

---

## Disclaimer

CAT Dispatcher è un progetto in evoluzione.  
Le informazioni contenute in questo repository possono cambiare senza preavviso in funzione dello sviluppo tecnico, delle esigenze operative e delle scelte di prodotto.

---

## Nome del progetto

**CAT Dispatcher**  
Piattaforma per il coordinamento geografico e operativo degli incarichi sul territorio.
