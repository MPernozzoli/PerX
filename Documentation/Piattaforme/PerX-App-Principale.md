---
tags: [perx, piattaforma, ios, macos]
updated: 2026-09-05
---

# PerX — App principale (macOS / iPad)

App nativa Swift/SwiftUI, target `PerX/` (progetto Xcode `PerX.xcodeproj`), circa 505 file Swift:
è il componente più grande della repo e il client primario usato dai periti. Condivide modelli e
logica di base con `PerXCore/` (~17 file, moduli riutilizzabili).

## Struttura principale (`PerX/`)

- `Managers/`, `Models/`, `ViewModels/`, `Views/`, `Services/`, `Utils/`, `Extensions/`,
  `Resources/` — organizzazione MVVM-ish standard SwiftUI.
- Persistenza: **CoreData** (`PerX.xcdatamodeld`) per i sinistri, **UserDefaults** (via
  `JSONEncoder`) per task locali e impostazioni.
- `Models/` è suddiviso per dominio: `Core`, `Financial`, `Content`, `Adapters`, `AI`, `API`,
  `Communication`, `Sync`, `Tasks`, `UI`.
- `Views/` è organizzato per area funzionale: `Principale`, `Sinistri` (con `Perizia`,
  `ElaboratoCalcoli`, `Detail`, `Cartella`), `Comunicazioni` (con `Mail`, `WhatsApp`, `Messages`),
  `Atti`, `ConsuntivoView`, `Operations`, `Import`, `Settings`, `Components`, `Cells`, `Helpers`.

## Servizi chiave (`PerX/Services/`)

| Cartella | Ruolo |
| --- | --- |
| `Adapters/` | `HubAPIAdapterClient`, `TaskAdapter`, `ClaimAdapter` — instradano le operazioni verso locale/hub/cloud (vedi [[02-Architettura]]) |
| `Auth/` | Login, gestione token/refresh |
| `Tasks/` | `TaskManager`, `ScheduleManager`, `TaskGenerationService`, `TaskSyncQueue` — vedi [[Sistema-Task]] |
| `AI/` | `AIManager`, `CloudAIService`, `ClaudeAIService`, `LocalModelService` — vedi [[AI-Locale-e-Cloud]] |
| `LocalAgent/` | Client dell'app verso il servizio XPC `PerX Local Agent` — vedi [[AI-Locale-e-Cloud]] |
| `Claims/` | Logica sinistri lato client — vedi [[Gestione-Sinistri]] |
| `Chat/`, `mail/`, `whatsapp/` | Client delle comunicazioni — vedi [[Comunicazioni]] |
| `Videoperizia/` | Client della videoperizia — vedi [[Videoperizia]] |
| `Hub/` | Comunicazione con PerXHub — vedi [[PerXHub]] |
| `CloudKit/` | Sincronizzazione/backup via CloudKit |
| `Cache/`, `Core/`, `Errors/`, `Files/`, `Import/`, `Knowledge/`, `News/`, `Notifications/`,
  `Settings/`, `Team/`, `Triggers/`, `Windows/`, `Atti/`, `Consuntivo/`, `API/`, `Dashboard/`,
  `excel/` | Servizi di supporto per le rispettive aree funzionali |

`HubConfigService` gestisce URL base e tenant slug (switch locale/cloud); `CurrentUserService`
espone email/username correnti.

## Local Agent (XPC)

`PerX Local Agent` è un servizio XPC embedded (bundle `it.pernozzoli.PerX.LocalAgent`), unico
punto d'accesso a dipendenze locali (Homebrew, Python, Node.js, Ollama, ZIP/Unzip). Solo l'helper
target (`InProcessPerXLocalAgent`, in `PerXLocalAgentService/`) lancia processi o parla con
Ollama; l'app compila solo il client (`XPCPerXLocalAgentClient`). Dettaglio completo →
[[AI-Locale-e-Cloud]].

## macOS-specific

`Services/Windows/` gestisce finestre multiple su macOS, incluse finestre flottanti (es. finestra
di chiamata durante la videoperizia).

## Distribuzione

Target principale configurato per **Developer ID diretto** con hardened runtime, senza
assunzioni di sandbox App Store. Per il rilascio, l'intero bundle (app + XPC service annidato) va
archiviato e notarizzato insieme, mantenendo hardened runtime sull'XPC service.

---
Ultimo aggiornamento: 2026-09-05
