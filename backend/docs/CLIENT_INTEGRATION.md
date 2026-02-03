# Piano Integrazione Client macOS → Backend Cloud

## Obiettivo

Trasformare gradualmente il client PerX macOS da applicazione standalone a thin client del backend cloud, mantenendo funzionalità durante la transizione.

## Fasi di Integrazione

### Fase 0: Preparazione (Nessuna modifica funzionale)

**Obiettivo**: Setup infrastruttura e test

**Modifiche client**:
1. Aggiungere `APIClient` service per comunicazione REST
2. Aggiungere `FeatureFlagManager` per gestire feature flags
3. Configurare URL backend da settings (default: staging)

**File da creare/modificare**:
- `PerX/Services/API/APIClient.swift` - Client REST generico
- `PerX/Services/API/FeatureFlagManager.swift` - Gestione feature flags
- `PerX/Services/Settings/CloudSettings.swift` - Configurazione cloud

**Testing**: Verifica connessione a backend staging, nessun impatto su funzionalità esistenti

---

### Fase 1: Email Read-Only da Cloud

**Obiettivo**: Client legge email da backend, ma sinistri restano locali

**Feature Flag**: `FF_CLOUD_EMAIL_READONLY`

**Modifiche client**:
1. Modificare `MailViewModel` per leggere da API `/emails` quando flag attivo
2. Mantenere fallback a lettura locale se API non disponibile
3. Email ingestion continua locale, ma anche backend (doppia ingestione temporanea)

**File da modificare**:
- `PerX/Services/mail/Core/MailManager.swift` - Aggiungere metodo `fetchFromCloud()`
- `PerX/ViewModels/MailViewModel.swift` - Toggle tra locale/cloud

**Rollback**: Disabilitare feature flag, tutto torna locale

---

### Fase 2: Claims Read-Through da Cloud

**Obiettivo**: Sinistri letti da cloud, scritture ancora locali (replicate)

**Feature Flag**: `FF_CLAIMS_READ_FROM_CLOUD`

**Modifiche client**:
1. Creare `CloudClaimService` che implementa interfaccia simile a `PersistenceController`
2. Modificare `PrincipaleViewModel` per usare `CloudClaimService` quando flag attivo
3. Implementare caching locale per offline
4. Replicare scritture locali → cloud (async, non bloccante)

**File da creare**:
- `PerX/Services/Claims/CloudClaimService.swift` - Service per lettura cloud
- `PerX/Services/Claims/ClaimSyncService.swift` - Replica locale → cloud

**File da modificare**:
- `PerX/ViewModels/PrincipaleViewModel.swift` - Usare CloudClaimService
- `PerX/Persistence.swift` - Aggiungere metodo `syncToCloud()`

**Rollback**: Disabilitare flag, lettura torna locale

---

### Fase 3: Write Path Cloud-Only

**Obiettivo**: Tutte le scritture sinistri passano via backend

**Feature Flag**: `FF_CLAIMS_WRITE_TO_CLOUD_ONLY`

**Modifiche client**:
1. Modificare tutte le operazioni di scrittura per chiamare API
2. Implementare optimistic locking (gestione 409 Conflict)
3. Rimuovere scritture dirette su CoreData per sinistri
4. Mantenere CoreData solo per cache/offline

**File da modificare**:
- `PerX/Services/Claims/ClaimEngine.swift` - Usare API per create/update
- `PerX/Managers/StatoManager.swift` - Chiamare API `/claims/{id}/state-transitions`
- `PerX/Views/Sinistri/*.swift` - Gestire conflitti e sync

**Gestione conflitti**:
- In caso di 409, mostrare diff e permettere merge manuale
- Ricaricare stato dal server prima di riprovare

**Rollback**: Finestra ristretta, solo se DB locale ancora aggiornato

---

### Fase 4: Multiutente e Task Cloud

**Obiettivo**: Abilitare assignment, task persistenti, automazioni

**Feature Flags**: `FF_TASKS_ENABLED`, `FF_AUTOMATIONS_ENABLED`

**Modifiche client**:
1. Implementare UI per assignment sinistri
2. Sostituire `DailyTask` locale con `case_tasks` cloud
3. Integrare notifiche push per assignment/task
4. Rimuovere `TaskManager` locale, usare API

**File da creare**:
- `PerX/Services/Tasks/CloudTaskService.swift`
- `PerX/Views/Components/AssignmentView.swift`

**File da modificare**:
- `PerX/Services/Tasks/TaskManager.swift` - Usare API
- `PerX/Views/DashboardView.swift` - Mostrare task cloud

---

## Architettura Client Post-Migrazione

```
┌─────────────────────────────────────┐
│         PerX macOS Client            │
├─────────────────────────────────────┤
│  UI Layer (SwiftUI)                  │
│  - Views, ViewModels                 │
├─────────────────────────────────────┤
│  Service Layer                       │
│  - CloudClaimService                 │
│  - CloudTaskService                  │
│  - CloudEmailService                 │
│  - APIClient (REST)                  │
├─────────────────────────────────────┤
│  Cache Layer (CoreData)              │
│  - Offline support                   │
│  - Sync queue                        │
├─────────────────────────────────────┤
│  Network Layer                       │
│  - JWT auth                          │
│  - Retry logic                       │
│  - Conflict resolution               │
└─────────────────────────────────────┘
           │
           │ HTTPS + JWT
           ▼
┌─────────────────────────────────────┐
│      PerX Cloud API (FastAPI)       │
└─────────────────────────────────────┘
```

## Gestione Offline

1. **Cache locale**: Mantenere copia recente sinistri in CoreData per offline
2. **Sync queue**: Coda operazioni da eseguire quando online
3. **Conflict resolution**: UI per risolvere conflitti al sync

## Autenticazione

1. **Login**: `POST /api/v1/auth/login` → JWT tokens
2. **Token storage**: Keychain macOS
3. **Refresh**: Automatico prima di scadenza
4. **Logout**: Invalida token lato server

## Testing Strategy

1. **Unit tests**: Mock APIClient per test logica
2. **Integration tests**: Test con backend staging
3. **E2E tests**: Test flussi completi con feature flags
4. **Rollback tests**: Verificare che disabilitare flag ripristini comportamento locale

## Timeline Stimata

- **Fase 0**: 1 settimana (setup)
- **Fase 1**: 2 settimane (email read-only)
- **Fase 2**: 3 settimane (claims read-through)
- **Fase 3**: 4 settimane (write cloud-only)
- **Fase 4**: 3 settimane (multiutente/task)

**Totale**: ~13 settimane con team dedicato

