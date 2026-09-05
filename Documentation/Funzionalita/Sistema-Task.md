---
tags: [perx, funzionalita, task, offline-first]
updated: 2026-09-05
---

# Sistema Task

Architettura **offline-first** a due livelli, con sincronizzazione tramite coda.

## Due livelli di task

### DailyTask (locale, iOS)
- Struct Swift salvata in `UserDefaults` via `JSONEncoder`.
- Gestita da `TaskManager` (singleton `@MainActor`).
- Include task AI-generate, reminder, attività legate a sinistro, task manuali.
- Campi chiave: `priority: Double`, `status: TaskStatus`, `sinistroID`, `deadline`.

### CaseTask (server, tabella `case_tasks`)
- Persistente, multi-utente, visibile a tutti i colleghi del tenant.
- API: `GET/POST /api/v1/tasks`, `PUT /api/v1/tasks/{id}`,
  `POST /api/v1/tasks/{id}/complete`, `DELETE /api/v1/tasks/{id}` (`routes_tasks.py`,
  modello `case_task.py`).
- Campo `metadata_json` usato per `clientId` (idempotenza offline).
- Dietro il feature flag `FF_TASKS_ENABLED` (default `False`, da abilitare in produzione).

## Sync offline-first

File chiave lato app:
- `PerX/Models/Tasks/PendingTaskOperation.swift` — modello dell'operazione in coda.
- `PerX/Services/Tasks/TaskSyncQueue.swift` — coda + `NWPathMonitor`.
- `PerX/Models/Adapters/AdapterDTOs.swift` — `CreateTaskRequest` con campo `clientId`.

Flusso:
1. L'utente crea/modifica un task in `CreateTaskView` / `EditTaskView`.
2. `TaskManager.addTask()` salva localmente (UI immediata).
3. `TaskSyncQueue.enqueueCreate/Update/Delete()` prova la chiamata immediata.
4. Se offline, l'operazione viene salvata come `PendingTaskOperation` in `UserDefaults`.
5. `NWPathMonitor` rileva la connessione → `flush()` processa la coda.
6. Dopo una `create` andata a buon fine, `cloudIdMap[localId] = cloudId` viene popolato per le
   operazioni successive sullo stesso task.

### Idempotenza
- iOS passa `clientId: localId.uuidString` nel body della create.
- Il backend controlla `metadata_json["clientId"]` prima di inserire: se già presente, restituisce
  il record esistente invece di duplicarlo.

### Punti di sync coperti
- `TaskManager.markTaskCompleted` → `enqueueComplete` (completamento manuale).
- `TaskManager.completeTaskWithEvent` → `enqueueComplete` (auto-completamento da eventi).
- `TaskManager.cancelTask` → `enqueueUpdate(status: .cancelled)`.
- `TaskManager.checkStateBasedCompletion` (batch loop) → `enqueueComplete` per ogni task.
- `LocalManagerExtensions.completeTaskForAdapter` → `enqueueComplete`.
- `CreateTaskView.createTask` → `enqueueCreate`.
- `EditTaskView.updateTask` → `enqueueUpdate`; pulsante delete → `enqueueDelete`.

### Nota sui task generati da AI
I task di tipo `aiGenerated`, `sinistroActivity`, ecc. non hanno un `cloudId` in `cloudIdMap`:
ogni `enqueue*` su di essi è quindi un no-op — nessun traffico di rete inutile, nessuna rottura del
flusso locale.

---
Ultimo aggiornamento: 2026-09-05
