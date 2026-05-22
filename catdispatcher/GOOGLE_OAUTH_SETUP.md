# Configurazione Google OAuth per Cat Dispatcher

Questa guida spiega come configurare Google OAuth per permettere il login con account Google.

## Prerequisiti

- Account Google (può essere personale, non serve essere admin Workspace)
- Accesso a Google Cloud Console
- Accesso alla dashboard Supabase

---

## Passo 1: Crea progetto su Google Cloud Console

1. Vai su https://console.cloud.google.com/
2. Clicca su **Seleziona progetto** → **Nuovo progetto**
3. Nome: `Cat Dispatcher`
4. Clicca **Crea**

---

## Passo 2: Configura OAuth Consent Screen

1. Nel menu laterale, vai su **API e servizi** → **Schermata consenso OAuth**
2. Seleziona **Esterno** (funziona per tutti gli account Google)
3. Clicca **Crea**
4. Compila i campi:
   - **Nome app**: Cat Dispatcher
   - **Email assistenza utenti**: la tua email
   - **Logo app**: (opzionale) carica il logo
   - **Dominio app**: catdispatcher.it
   - **Link alla privacy policy**: https://catdispatcher.it/privacy
   - **Email contatto sviluppatore**: la tua email
5. Clicca **Salva e continua**
6. **Ambiti**: clicca **Aggiungi o rimuovi ambiti**
   - Seleziona: `email`, `profile`, `openid`
   - Clicca **Aggiorna**
7. Clicca **Salva e continua**
8. **Utenti test**: aggiungi le email per il testing (durante lo sviluppo)
9. Clicca **Salva e continua**

---

## Passo 3: Crea credenziali OAuth - Web App (per il sito)

1. Vai su **API e servizi** → **Credenziali**
2. Clicca **+ Crea credenziali** → **ID client OAuth**
3. Tipo applicazione: **Applicazione web**
4. Nome: `Cat Dispatcher Web`
5. **Origini JavaScript autorizzate**:
   ```
   https://catdispatcher.it
   http://localhost:5173
   http://localhost:3000
   ```
6. **URI di reindirizzamento autorizzati**:
   ```
   https://rqrwzfenmxklmcxskfek.supabase.co/auth/v1/callback
   ```
7. Clicca **Crea**
8. **SALVA** il `Client ID` e `Client Secret` (ti serviranno per Supabase)

---

## Passo 4: Crea credenziali OAuth - Chrome Extension

1. Clicca **+ Crea credenziali** → **ID client OAuth**
2. Tipo applicazione: **Estensione di Chrome**
3. Nome: `Cat Dispatcher Extension`
4. **ID applicazione**: 
   - Se hai già l'ID dell'estensione pubblicata, inseriscilo
   - Se non ancora pubblicata, lascia vuoto per ora (lo aggiornerai dopo)
5. Clicca **Crea**
6. **SALVA** il `Client ID` (formato: `xxxxx.apps.googleusercontent.com`)

---

## Passo 5: Configura Supabase

1. Vai sulla dashboard Supabase: https://supabase.com/dashboard
2. Seleziona il progetto `rqrwzfenmxklmcxskfek`
3. Vai su **Authentication** → **Providers**
4. Trova **Google** e clicca per abilitarlo
5. Inserisci:
   - **Client ID**: quello creato per Web App (passo 3)
   - **Client Secret**: quello creato per Web App (passo 3)
6. **Salva**

---

## Passo 6: Configura l'estensione Chrome

1. Apri `chrome-extension/manifest.json`
2. Sostituisci i placeholder:

```json
{
  "oauth2": {
    "client_id": "IL_TUO_CLIENT_ID_CHROME.apps.googleusercontent.com",
    "scopes": [
      "openid",
      "email",
      "profile"
    ]
  },
  "key": "LA_TUA_EXTENSION_KEY"
}
```

### Come ottenere la Extension Key

1. Carica l'estensione in Chrome (chrome://extensions/ in modalità sviluppatore)
2. Copia l'**ID** dell'estensione (es. `abcdefghijklmnopqrstuvwxyz123456`)
3. Vai su https://nickclaw.github.io/crx-keys/
4. Inserisci l'ID e genera la key
5. Copia la key nel manifest.json

---

## Passo 7: Pubblica in produzione

### Google Cloud Console

1. Vai su **Schermata consenso OAuth**
2. Clicca **Pubblica app**
3. Conferma la pubblicazione

> ⚠️ **Nota**: Per app pubbliche con utenti esterni, Google potrebbe richiedere una verifica (richiede qualche giorno). Durante la fase di test, aggiungi gli utenti come "Utenti test".

### Chrome Web Store

1. Dopo aver pubblicato l'estensione, ottieni l'ID definitivo
2. Aggiorna le credenziali OAuth su Google Cloud Console con l'ID corretto
3. Rigenera le credenziali se necessario

---

## Test

1. Apri https://catdispatcher.it/login
2. Clicca "Accedi con Google"
3. Seleziona un account Google
4. Se l'email è nella whitelist, verrai autenticato
5. Altrimenti, vedrai un errore "Email non autorizzata"

### Test estensione

1. Apri https://act.jfish.it
2. Clicca sull'icona dell'estensione
3. Clicca "Accedi con Google"
4. Autorizza l'accesso
5. Se tutto funziona, vedrai i dati della pagina

---

## Troubleshooting

### "redirect_uri_mismatch"
- Verifica che l'URI di redirect in Google Cloud Console corrisponda esattamente a quello di Supabase
- Il formato corretto è: `https://[PROJECT_ID].supabase.co/auth/v1/callback`

### "access_denied"
- L'utente ha rifiutato l'autorizzazione
- Oppure l'email non è autorizzata

### "invalid_client"
- Client ID non corretto
- Verifica di usare il Client ID giusto (Web per il sito, Chrome per l'estensione)

### L'estensione non funziona
- Verifica che il `key` nel manifest.json sia corretto
- Ricarica l'estensione dopo ogni modifica
- Controlla la console del service worker (chrome://extensions/ → Ispeziona)
