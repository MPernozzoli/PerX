# ACT CAT Dispatcher - Chrome Extension

Estensione Chrome per l'assegnazione automatica dei CAT nel gestionale ACT Jellyfish.

## Funzionalità

- **Controllo autenticazione**: richiede login con credenziali Cat Dispatcher
- **Lettura automatica** dell'Ubicazione Rischio dalla pagina del sinistro
- **Assegnazione CAT automatica**: chiama l'API per ottenere il CAT corretto in base all'ubicazione
- **Mappa CAT**: apre una mappa interattiva per la selezione visuale del CAT
- **Gestione sospensioni**: mostra un avviso se il CAT è temporaneamente sospeso (malattia, ferie, ecc.) con possibilità di "Assegna comunque"

## Autenticazione

L'estensione richiede il login con le credenziali di **Cat Dispatcher**:

- Al primo utilizzo, inserisci email e password del tuo account Cat Dispatcher
- I token vengono salvati in modo sicuro in `chrome.storage.local`
- La sessione viene mantenuta e refreshata automaticamente
- Puoi fare logout cliccando sull'icona 🚪 accanto alla tua email

## Installazione

### Opzione 1: Chrome Web Store (consigliata)

1. Vai alla pagina dell'estensione sul Chrome Web Store
2. Clicca "Aggiungi a Chrome"
3. Conferma l'installazione
4. Clicca sull'icona del puzzle (estensioni) nella barra di Chrome, trova CAT Dispatcher e clicca sul pin per tenerla sempre visibile

### Opzione 2: Installazione manuale (sviluppo)

1. Apri Chrome e vai a `chrome://extensions/`
2. Attiva "Modalità sviluppatore" (toggle in alto a destra)
3. Clicca "Carica estensione non pacchettizzata"
4. Seleziona la cartella `chrome-extension` (o la cartella estratta dallo ZIP)
5. Clicca sull'icona del puzzle (estensioni) nella barra di Chrome, trova CAT Dispatcher e clicca sul pin per tenerla sempre visibile

> **Importante:** La cartella dell'estensione deve rimanere sul dispositivo. Chrome carica l'estensione direttamente da quella posizione, non crea una copia. Se elimini o sposti la cartella, l'estensione smetterà di funzionare.

## Utilizzo

1. Apri un sinistro nel gestionale ACT (https://act.jfish.it/...)
2. Clicca sull'icona dell'estensione nella barra di Chrome
3. Effettua il login con le tue credenziali Cat Dispatcher (solo la prima volta)
4. Visualizza i dati dell'Ubicazione Rischio e il CAT corrente
5. Usa uno dei pulsanti:
   - **Assegna CAT automaticamente**: assegnazione via API
   - **Apri mappa CAT**: selezione visuale dalla mappa

## Struttura file

```
chrome-extension/
├── manifest.json          # Configurazione estensione (Manifest V3)
├── background.js          # Service worker per chiamate API e auth
├── content-script.js      # Script iniettato nella pagina ACT
├── popup/
│   ├── popup.html         # UI del popup
│   ├── popup.css          # Stili
│   └── popup.js           # Logica popup
├── icons/
│   ├── icon16.png         # Icona 16x16
│   ├── icon48.png         # Icona 48x48
│   └── icon128.png        # Icona 128x128
├── store/
│   ├── privacy-policy.html # Privacy policy per Chrome Web Store
│   ├── description.txt     # Descrizione per lo store
│   └── PUBLISHING.md       # Guida alla pubblicazione
└── README.md              # Questo file
```

## Come funziona l'API

### Endpoint Edge Function: address-to-cat

L'estensione chiama `POST /functions/v1/address-to-cat` con payload flessibile:

**Lookup diretto (senza geocoding):**
```json
{
  "comune": "Milano",
  "provincia": "MI",
  "intervention_type": "sopralluogo"
}
```

**Geocoding (con indirizzo completo):**
```json
{
  "address": "VIA GINO SEVERINI 1, Milano, 20138, MI, Italia",
  "intervention_type": "sopralluogo"
}
```

**Cosa fa l'Edge Function:**
1. Se `comune`+`provincia`: lookup diretto senza geocoding
2. Se `address`: geocodifica con Google Places API
3. Trova il CAT assegnato (filtrato per `intervention_type` e stato attivo)
4. Esclude i CAT con sospensione attiva
5. Restituisce JSON con info CAT o info sospensione

**Risposta successo:**
```json
{
  "success": true,
  "cat_name": "Luciano Di Munno",
  "cat_alias": "LOMBARDIA - Luciano Di Munno",
  "commune_name": "Milano"
}
```

**Risposta CAT sospeso:**
```json
{
  "success": false,
  "suspended": true,
  "cat_name": "Luciano Di Munno",
  "commune_name": "Milano",
  "suspension_reason": "malattia",
  "suspension_end_date": "2026-02-15"
}
```

L'estensione gestisce entrambi i casi: assegnazione normale o messaggio sospensione con "Assegna comunque".

## Troubleshooting

**"Content script non caricato"**
- Ricarica la pagina ACT (F5)
- Verifica che l'URL sia `https://act.jfish.it/*`

**"Credenziali non valide"**
- Verifica email e password
- Assicurati di usare le credenziali Cat Dispatcher, non ACT

**"Errore API"**
- Verifica di essere loggato
- Controlla i log nella console del service worker (chrome://extensions/ > Ispeziona)

**"Sito non supportato"**
- L'estensione funziona solo su act.jfish.it
- Assicurati di essere sul gestionale ACT
