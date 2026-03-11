# PerX JFish Sync - Estensione Chrome

Estensione Chrome per sincronizzare dati tra JFish (gestionale studio peritale) e PerX (gestionale interno perito).

## Funzionalità

- **Icone sync inline**: Su pagine JFish, mostra icone accanto ai campi che differiscono da PerX
- **Sync Diario**: Sincronizza entry del diario tra i due sistemi
- **Compilazione Perizia**: Compila automaticamente form JFish con dati da PerX
- **Import/Export**: Importa dati da JFish a PerX o esporta da PerX a JFish

## Requisiti

- Google Chrome (versione recente)
- Account Google aziendale (stesso usato in PerX)
- TailScale attivo per raggiungere l'Hub
- PerXHub attivo e raggiungibile

## Installazione (Modalità Sviluppatore)

1. Apri Chrome e vai a `chrome://extensions`
2. Attiva "Modalità sviluppatore" (toggle in alto a destra)
3. Clicca "Carica estensione non pacchettizzata"
4. Seleziona questa cartella (`perx_chrome_extension`)
5. L'estensione apparirà nella barra degli strumenti

## Configurazione

### 1. Google OAuth2

Prima di usare l'estensione, devi configurare le credenziali Google:

1. Vai su [Google Cloud Console](https://console.cloud.google.com/)
2. Seleziona il progetto PerX (o creane uno nuovo)
3. Vai a "API e servizi" → "Credenziali"
4. Crea credenziali → "ID client OAuth"
5. Tipo: "Estensione Chrome"
6. Inserisci l'ID dell'estensione: `hdoifboihnaocjbmbbopjngdgkiiiieo`
7. Copia il Client ID nel file `manifest.json`:

```json
"oauth2": {
  "client_id": "TUO_CLIENT_ID.apps.googleusercontent.com",
  "scopes": ["openid", "email", "profile"]
}
```

### 2. URL Hub

1. Clicca sull'icona dell'estensione
2. Vai in Impostazioni (icona ingranaggio)
3. Inserisci l'URL dell'Hub TailScale (es. `https://mac-mini-di-massimo.tailca58be.ts.net`)
4. Clicca "Salva e Verifica"

## Uso

### Login

1. Clicca sull'icona dell'estensione
2. Clicca "Accedi con Google"
3. Seleziona il tuo account aziendale

### Sincronizzazione

1. Naviga su una pagina sinistro JFish
2. L'estensione rileva automaticamente la pagina
3. Icone di sync appariranno accanto ai campi diversi
4. Clicca su un'icona per sincronizzare quel campo
5. Usa i pulsanti nel popup per azioni multiple

## Struttura File

```
perx_chrome_extension/
├── manifest.json       # Configurazione estensione
├── background.js       # Service Worker (auth, comunicazione Hub)
├── content.js          # Iniettato in pagine JFish
├── content-styles.css  # Stili per icone sync
├── hub-client.js       # Client API per Hub
├── popup.html          # UI popup
├── popup.js            # Logica popup
├── styles.css          # Stili popup
└── icons/              # Icone estensione
```

## Configurazione JFish (TODO)

Per funzionare con JFish, è necessario configurare i selettori DOM in `content.js`:

```javascript
const JFISH_CONFIG = {
  urlPatterns: [/* pattern URL JFish */],
  selectors: {
    riferimento: '/* selettore per riferimento sinistro */',
    stato: '/* selettore per stato */',
    // ... altri selettori
  }
};
```

## Note

- L'estensione non è distribuita su Chrome Web Store
- Richiede TailScale per raggiungere l'Hub
- Gli alias JFish sono configurati in `StatoManager.swift` (campo `jfishAlias`)
