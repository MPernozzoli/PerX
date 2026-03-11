# PerX Hub Monitor

App menu bar per monitorare lo stato dell'Hub PerX sul Mac Mini.

## Funzionalità

- **Icona nella menu bar** che cambia colore in base allo stato (verde = online, rosso = offline)
- **Popover al clic** con:
  - Stato connessione Hub
  - Uptime e versione
  - Job in coda (import/export/scan)
  - Statistiche email e allegati
- **Polling automatico** ogni 30 secondi
- **Avvio al login** (opzionale)

## Screenshot

```
┌─────────────────────────────────┐
│ 🖥 PerX Hub             [⚙️]    │
│    Online                       │
├─────────────────────────────────┤
│ ● Stato: Attivo     🕐 Uptime   │
│                        2h 45m   │
│ 🏷 Versione: 1.0    🔄 14:32    │
│                                 │
│ 📋 Job in coda              [3] │
│ ├── 📥 Import  abc123...  14:30 │
│ ├── 📤 Export  def456...  14:28 │
│ └── 🔍 Scan    ghi789...  14:25 │
│                                 │
│ 📊 Statistiche                  │
│ ┌────────┬─────────┬──────────┐ │
│ │ 📧 12  │ 📎 3    │ 🔄 3     │ │
│ │ oggi   │ attesa  │ pending  │ │
│ └────────┴─────────┴──────────┘ │
├─────────────────────────────────┤
│ [Aggiorna]              [Esci] │
└─────────────────────────────────┘
```

## Installazione

### Build & Deploy

```bash
cd PerXHubMonitor
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Lo script:
1. Compila l'app in release
2. Crea un bundle `.app` in `~/Applications/`
3. Installa un LaunchAgent per l'avvio automatico
4. Avvia l'app

### Sviluppo

```bash
cd PerXHubMonitor
chmod +x scripts/run-dev.sh
./scripts/run-dev.sh
```

### Build manuale

```bash
cd PerXHubMonitor
swift build -c release
.build/release/PerXHubMonitor
```

## Configurazione

Al primo avvio, clicca sull'icona nella menu bar e poi su ⚙️ per configurare l'URL dell'Hub.

Default: `http://localhost:8080`

Per Hub su Tailscale: `http://mac-mini.tailnet-name.ts.net:8080`

## Gestione

| Azione | Comando |
|--------|---------|
| **Stop** | `launchctl unload ~/Library/LaunchAgents/com.perx.hub-monitor.plist` |
| **Start** | `launchctl load ~/Library/LaunchAgents/com.perx.hub-monitor.plist` |
| **Apri manualmente** | `open ~/Applications/PerXHubMonitor.app` |
| **Disinstalla** | Rimuovi app e plist, poi `launchctl unload` |

## Requisiti

- macOS 14.0+
- Swift 5.9+
- Hub PerX attivo (per visualizzare dati)

## Note

- L'app vive solo nella menu bar (nessuna icona nel Dock)
- Il polling avviene ogni 30 secondi in background
- Quando apri il popover, i dati vengono aggiornati immediatamente
