# CloudKit Server-to-Server Setup per PerX Hub

Questa guida spiega come configurare l'autenticazione Server-to-Server (S2S) per CloudKit Web Services.

## Perché S2S?

L'Hub gira come daemon (servizio H24) e non ha accesso al contesto utente iCloud.
Con S2S, l'Hub può accedere al **database pubblico** di CloudKit usando chiavi crittografiche,
senza bisogno di login utente o entitlements dell'app.

## Requisiti

- Accesso all'Apple Developer Account (team owner o admin)
- Accesso al Mac Mini server

## Passaggi

### 1. Genera le chiavi ECDSA P-256

Sul Mac Mini (o qualsiasi Mac):

```bash
# Crea directory per le chiavi
sudo mkdir -p /opt/perx-hub/keys
cd /opt/perx-hub/keys

# Genera chiave privata ECDSA P-256
openssl ecparam -genkey -name prime256v1 -noout -out cloudkit_private_key.pem

# Estrai chiave pubblica (da caricare su Apple)
openssl ec -in cloudkit_private_key.pem -pubout -out cloudkit_public_key.pem

# Proteggi la chiave privata
sudo chmod 600 cloudkit_private_key.pem
sudo chown root:wheel cloudkit_private_key.pem

# Copia in posizione standard
sudo cp cloudkit_private_key.pem /opt/perx-hub/cloudkit_private_key.pem
```

### 2. Carica la chiave pubblica su CloudKit Dashboard

1. Vai su [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Seleziona il container `iCloud.it.pernozzoli.PerX`
3. Vai su **API Access** → **Server-to-Server Keys**
4. Clicca **Create Key**
5. Nome: `PerXHub-S2S`
6. Carica il contenuto di `cloudkit_public_key.pem`
7. **Copia il Key ID** generato (es: `abc123def456...`)

### 3. Configura l'Hub

Aggiungi le variabili d'ambiente al plist del LaunchDaemon:

```xml
<key>EnvironmentVariables</key>
<dict>
    <!-- ... altre variabili ... -->
    <key>CLOUDKIT_KEY_ID</key>
    <string>IL_TUO_KEY_ID_QUI</string>
    <key>CLOUDKIT_PRIVATE_KEY_PATH</key>
    <string>/opt/perx-hub/cloudkit_private_key.pem</string>
</dict>
```

Oppure modifica direttamente il file:

```bash
# Edita il plist
sudo nano /Library/LaunchDaemons/com.perx.hub.plist

# Ricarica il servizio
sudo launchctl unload /Library/LaunchDaemons/com.perx.hub.plist
sudo launchctl load /Library/LaunchDaemons/com.perx.hub.plist
```

### 4. Verifica

Controlla i log dell'Hub:

```bash
tail -f /opt/perx-hub/logs/hub.log
```

Dovresti vedere:
```
[Hub] CloudKitWebService initialized (S2S)
```

### 5. Test

```bash
curl "http://localhost:8080/sinistri?user=mpernozzoli"
```

Se configurato correttamente, dovresti ricevere un array JSON (anche vuoto).
Se non configurato, riceverai comunque una risposta ma i dati saranno vuoti.

## Troubleshooting

### "CloudKitWebService not configured"

- Verifica che `CLOUDKIT_KEY_ID` sia impostato
- Verifica che il file della chiave privata esista e sia leggibile

### Errore 401 Authentication

- Il Key ID potrebbe essere sbagliato
- La chiave pubblica potrebbe non corrispondere alla privata
- Verifica che la chiave sia stata creata correttamente nel Dashboard

### Errore "NOT_AUTHENTICATED"

- La firma potrebbe essere calcolata in modo errato
- Verifica che l'orologio del server sia sincronizzato (NTP)

## Note Importanti

- **Solo database pubblico**: S2S funziona SOLO con il database pubblico di CloudKit
- **Produzione vs Development**: Assicurati di usare l'ambiente corretto
- **Sicurezza**: La chiave privata deve rimanere segreta. Non commitarla mai in git.

## Schema CloudKit

Assicurati che i seguenti RecordType esistano nel database pubblico:

- `Sinistro`
- `DiarioEntry`
- `ProcessedEmail`
- `Task`
- `EmailEvent`

Con i campi appropriati (vedi `CloudKitWebService.swift` per i dettagli).
