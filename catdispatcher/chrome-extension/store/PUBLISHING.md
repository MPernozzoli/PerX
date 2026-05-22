# Guida alla pubblicazione su Chrome Web Store

## Prerequisiti

1. **Account Google Developer** - Registrati su https://chrome.google.com/webstore/devconsole
2. **Quota di registrazione** - $5 una tantum
3. **Privacy Policy** - Già inclusa in `store/privacy-policy.html` (hostala online)

## Preparazione del pacchetto

### 1. Crea il file ZIP

```bash
cd chrome-extension

# Crea una cartella temporanea con solo i file necessari
mkdir -p build
cp manifest.json build/
cp background.js build/
cp content-script.js build/
cp -r popup build/
cp -r icons build/

# Crea lo ZIP
cd build
zip -r ../cat-dispatcher-extension.zip .
cd ..
rm -rf build
```

### 2. Screenshot richiesti

Prepara questi screenshot (1280x800 o 640x400 pixel):

1. **Screenshot 1**: Popup dell'estensione con dati ubicazione visibili
2. **Screenshot 2**: Popup dopo assegnazione CAT riuscita
3. **Screenshot 3**: Form di login dell'estensione

Salva gli screenshot nella cartella `store/screenshots/`.

### 3. Icone per lo store

- **Icona 128x128** - Già presente come `icons/icon128.png`
- **Tile promozionale (opzionale)** - 440x280 pixel

## Pubblicazione

### 1. Accedi alla Developer Console

Vai su https://chrome.google.com/webstore/devconsole

### 2. Crea nuovo elemento

1. Clicca "Nuovo elemento"
2. Carica il file `cat-dispatcher-extension.zip`

### 3. Compila le informazioni

**Scheda Store listing:**

- **Lingua**: Italiano
- **Nome**: ACT CAT Dispatcher
- **Descrizione breve**: Assegnazione automatica CAT per ACT Jellyfish
- **Descrizione completa**: Copia da `store/description.txt`
- **Categoria**: Produttività
- **Screenshot**: Carica quelli preparati

**Scheda Privacy:**

- **Uso singolo**: Seleziona le funzionalità usate
- **Permessi**: Spiega perché servono (vedi sotto)
- **Privacy Policy URL**: URL dove hai hostato `privacy-policy.html`

**Giustificazione permessi:**

| Permesso | Giustificazione |
|----------|-----------------|
| activeTab | Necessario per leggere i dati del sinistro dalla pagina ACT attualmente aperta |
| scripting | Necessario per iniettare lo script che legge l'ubicazione rischio e imposta il CAT |
| storage | Necessario per salvare i token di autenticazione dell'utente localmente |
| act.jfish.it | Dominio del gestionale ACT dove l'estensione deve funzionare |
| supabase.co | API backend di Cat Dispatcher per autenticazione e ricerca CAT |

### 4. Imposta visibilità

Per un'estensione riservata:

1. Vai su "Distribuzione" 
2. Seleziona **"Non in elenco"** (Unlisted)
3. Solo chi ha il link diretto potrà trovare e installare l'estensione

### 5. Invia per revisione

1. Clicca "Invia per revisione"
2. La revisione richiede solitamente 1-3 giorni lavorativi
3. Riceverai un'email quando l'estensione è approvata

## Dopo la pubblicazione

### Ottieni l'URL dello store

Dopo l'approvazione, l'URL sarà tipo:
```
https://chrome.google.com/webstore/detail/act-cat-dispatcher/EXTENSION_ID
```

### Aggiorna l'app Cat Dispatcher

Aggiungi il link dello store nell'app per permettere agli utenti di installare facilmente l'estensione.

## Aggiornamenti futuri

Per aggiornare l'estensione:

1. Incrementa la `version` in `manifest.json`
2. Crea un nuovo ZIP
3. Vai sulla Developer Console
4. Seleziona l'estensione esistente
5. Clicca "Carica nuova versione"
6. Carica il nuovo ZIP
7. Invia per revisione

## Note importanti

- **Tempo di revisione**: 1-3 giorni lavorativi
- **Rifiuti**: Se viene rifiutata, leggi il motivo e correggi
- **Visibilità "Non in elenco"**: L'estensione non appare nelle ricerche, solo tramite link diretto
- **Utenti esistenti**: Gli aggiornamenti vengono distribuiti automaticamente
