---
tags: [perx, piattaforma, ios, macos]
updated: 2026-11-27
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
| `Claims/` | Logica sinistri lato client — vedi [[Gestione-Sinistri]]; `Claims/Stima/` contiene il motore di stima deterministico, unica fonte degli importi della perizia — vedi [[Motore-di-Stima]] |
| `Chat/`, `mail/`, `whatsapp/` | Client delle comunicazioni — vedi [[Comunicazioni]] |
| `Videoperizia/` | Client della videoperizia — vedi [[Videoperizia]] |
| `Hub/` | Comunicazione con PerXHub — vedi [[PerXHub]] |
| `CloudKit/` | Sincronizzazione/backup via CloudKit |
| `Cache/`, `Core/`, `Errors/`, `Files/`, `Import/`, `Knowledge/`, `News/`, `Notifications/`,
  `Settings/`, `Team/`, `Triggers/`, `Windows/`, `Atti/`, `Consuntivo/`, `API/`, `Dashboard/`,
  `excel/` | Servizi di supporto per le rispettive aree funzionali |

`HubConfigService` gestisce URL base e tenant slug (switch locale/cloud) e l’unico health
check verso `/health`, ogni 5 minuti. `HubModeService` non fa un secondo polling: legge
`isHubReachable`. `CurrentUserService` espone email/username correnti. Perdere il focus
della finestra non ferma posta, WhatsApp e sync cartelle: quella pausa scatta solo a sleep
e wake del Mac. La sidebar principale (`ContentView`) è un pannello affiancato alla pagina scelta:
in memoria c’è solo quella pagina, non la lista sinistri sotto le altre sezioni.
`NavigationSplitView` all’avvio terminava il processo (`EXC_BAD_ACCESS` nel body).
Il calcolo dei task non blocca il disegno: fetch e conteggi stanno su un contesto
Core Data di background, la scansione file è staccata, e `UIActivity` mostra
ingranaggio e scheletro finché il risultato non è pronto.
Dettaglio della decisione → [[06-Decisioni-e-Intenzioni-Future]].

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

**Entitlements e firma automatica.** Il target `PerX` usa `CODE_SIGN_STYLE = Automatic` con due file:
`PerX/PerX-Debug.entitlements` (config Debug) e `PerX/PerX.entitlements` (Release). Non vanno
dichiarati a mano `com.apple.application-identifier` (iOS: `application-identifier`) né
`com.apple.developer.team-identifier`: li inietta Xcode in firma, e dichiararli nel file produce
l'errore «Entitlement com.apple.application-identifier not found and could not be included in
profile». Dal 2026-11-26 la chiave è stata rimossa da entrambi i file; restano `aps-environment`,
`com.apple.developer.aps-environment` e `keychain-access-groups`.

## Test e CI

Dal 2026-11-07 `PerXCore` contiene un test target Swift Testing con una prima copertura delle
regole sugli stati del sinistro e dell'utility HTML. Il workflow Apple esegue `swift test` sul core
e compila `PerXHub`. Anche la build unsigned completa del target `PerX` è bloccante: le vecchie
copie in `PerX/Services/Videoperizia/` sono escluse dalla membership, mentre le implementazioni
canoniche restano in `Shared/Videoperizia/`. `PerXTests` contiene dal 2026-11-26 la suite Swift
Testing del motore di stima (`StimaEngineTests`); `PerXUITests` resta boilerplate. I test di
`PerXTests` sono ospitati nell'app (`TEST_HOST`): eseguirli apre lo store Core Data locale.

## Persistenza locale

Modello Core Data versionato: dal 2026-11-26 la versione corrente è `PerX v2.xcdatamodel`
(campi del motore di stima ed entità `StimaRevisione`, migrazione leggera automatica da `PerX`).
Ogni modifica di schema va fatta aggiungendo una nuova versione, mai modificando quella corrente.
Nomi delle versioni: `PerX v2`, `PerX v3`… e non quelli proposti da Xcode («PerX 2»): il
`.gitignore` esclude `* 2.*` come duplicati del Finder e la versione non verrebbe committata.
Se lo store non si apre, `Persistence.swift` lo sposta in un file di backup invece di cancellarlo.

---
Ultimo aggiornamento: 2026-11-27
