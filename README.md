# PerX

**PerX** è una piattaforma operativa per studi peritali e strutture tecniche che gestiscono sinistri property, con forte focus su gestione documentale, flussi operativi e supporto AI al lavoro del perito.

Questa repo è strutturata come **monorepo** e contiene sia l’applicazione desktop/iPad (Swift), sia componenti di integrazione (hub, agent, estensioni) sia un backend cloud FastAPI.

---

## Panoramica della repo

- **`PerX/`**: applicazione principale (macOS / iPad) per la gestione delle pratiche, basata su Swift/SwiftUI.
- **`PerX per iPad/`**: viste e servizi specifici per l’esperienza iPad.
- **`PerXCore/`**: moduli core riutilizzabili (modelli, logica condivisa).
- **`PerXHub/`**: servizi di integrazione/sync verso fonti esterne (es. e‑mail, cloud).
- **`PerXHubMonitor/`**: tool di monitoraggio e diagnostica per l’hub.
- **`perx_sync_agent/`**: agent dedicato alla sincronizzazione/sorveglianza di directory e file locali.
- **`perx_chrome_extension/`**: estensione browser per integrazioni lato web.
- **`backend/`**: backend FastAPI per servizi cloud (API sinistri, autenticazione, ecc.).
- **Altri moduli/tools**: cartelle ausiliarie per test, varianti “lite”, script e materiali di supporto.

Ogni componente più complesso ha (o può avere) un proprio `README` locale con dettagli specifici.

---

## Applicazione PerX (macOS / iPad)

- **Codice principale**: in `PerX/` e `PerX per iPad/`.
- **Progetto Xcode**: `PerX.xcodeproj`.

### Avvio rapido (locale)

1. **Apri il progetto**  
   Apri `PerX.xcodeproj` in Xcode.

2. **Seleziona il target**  
   Scegli il target desiderato (es. app principale macOS, build per iPad, eventuali varianti “Lite”).

3. **Esegui**  
   Lancia l’app direttamente da Xcode su simulatore o dispositivo configurato.

La configurazione dettagliata di schemi, bundle id, profili di provisioning e ambienti è gestita internamente al progetto Xcode e nella configurazione di sviluppo dello studio.

---

## Backend cloud (`backend/`)

Il backend è implementato in **FastAPI** e fornisce API per:

- autenticazione e gestione utente;
- gestione sinistri e loro stato;
- eventi, timeline, servizi ausiliari.

Per dettagli su setup, dipendenze, migrazioni e comandi:

- **vedi `backend/README.md`**, che contiene:
  - struttura del progetto;
  - comandi `pip`, `uvicorn`, `alembic`;
  - istruzioni per build e run Docker.

---

## Altri componenti

- **`PerXHub/`**  
  Componenti di integrazione (es. sincronizzazione e-mail, servizi cloud, comunicazioni) a supporto dell’ecosistema PerX.

- **`PerXHubMonitor/`**  
  Strumenti per monitorare e diagnosticare lo stato dell’hub, code di sync e job di integrazione.

- **`perx_sync_agent/`**  
  Agent per sincronizzazione locale di directory, monitoraggio file e instradamento verso PerX.

- **`perx_chrome_extension/`**  
  Estensione Chrome per catturare contenuti dal browser e collegarli alle pratiche PerX (dettagli nel relativo `README`).

---

## Stato del progetto

PerX è in **sviluppo attivo** e in uso interno controllato.  
Le funzionalità evolvono in modo iterativo (prototipazione, sviluppo, validazione su casi reali) e la struttura della repo può subire riorganizzazioni.

---

## Contributi

Il progetto non accetta contributi pubblici aperti.  
Per collaborazioni tecniche, integrazioni o valutazioni progettuali, fare riferimento ai canali interni del team responsabile.

---

## Riservatezza e utilizzo

Questo repository può contenere codice, documentazione, modelli dati e concetti proprietari.

Salvo diversa indicazione esplicita:

- il contenuto **non** è da considerarsi liberamente riutilizzabile;
- non è autorizzata la redistribuzione non concordata;
- parti del progetto possono essere soggette a revisione, riorganizzazione o migrazione.

---

## Nome del progetto

**PerX**  
Piattaforma operativa per la gestione evoluta delle pratiche peritali.
