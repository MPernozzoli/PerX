import Foundation
import CoreData

/// Indice in memoria per decidere rapidamente se una mail (messageId) e' associata a un sinistro chiuso.
/// Serve per skippare processamento di email storiche senza dover scansionare thread/email ogni volta.
@MainActor
final class ClosedSinistroEmailIndex: ObservableObject {
    static let shared = ClosedSinistroEmailIndex()
    
    private let container = PersistenceController.shared.container
    private var observer: NSObjectProtocol?
    
    private var closedEmailIds = Set<String>()
    private var isReady = false
    private var rebuildTask: Task<Void, Never>?
    
    private init() {
        startObserving()
        
        // Warm-up: costruisci l'indice in background dopo l'avvio (non blocca UI).
        rebuildAsyncDebounced()
    }
    
    /// Ritorna true se conviene SKIP: email letta e associata a sinistro in stato "Chiusa".
    func shouldSkipProcessing(emailId: String, isRead: Bool) async -> Bool {
        guard isRead else { return false }
        
        // Se non pronto, avvia rebuild ma non bloccare: meglio processare una volta che bloccare l'app.
        if !isReady {
            rebuildAsyncDebounced()
            return false
        }
        
        return closedEmailIds.contains(emailId)
    }
    
    // MARK: - Observation
    
    private func startObserving() {
        let viewContext = container.viewContext
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: viewContext,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            // Se sono stati salvati thread o sinistri, ricostruisci (debounced).
            if self.didChangeThreadsOrSinistri(note: note) {
                self.rebuildAsyncDebounced()
            }
        }
    }
    
    private func didChangeThreadsOrSinistri(note: Notification) -> Bool {
        func containsEntity(_ set: Set<NSManagedObject>?, name: String) -> Bool {
            guard let set else { return false }
            return set.contains { $0.entity.name == name }
        }
        
        let inserted = note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>
        let updated = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>
        let deleted = note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>
        
        return containsEntity(inserted, name: "SinistroEmailThread")
            || containsEntity(updated, name: "SinistroEmailThread")
            || containsEntity(deleted, name: "SinistroEmailThread")
            || containsEntity(inserted, name: "Sinistro")
            || containsEntity(updated, name: "Sinistro")
            || containsEntity(deleted, name: "Sinistro")
    }
    
    // MARK: - Rebuild
    
    private func rebuildAsyncDebounced() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            // Debounce per accorpare salvataggi ravvicinati.
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            if Task.isCancelled { return }
            await self.rebuildIndex()
        }
    }
    
    /// Ricostruisce l'indice completo (chiamare all'avvio o dopo modifiche significative)
    func rebuildIndex() async {
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        do {
            let ids: Set<String> = try await backgroundContext.perform {
                let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
                request.predicate = NSPredicate(format: "sinistro.stato ==[c] %@", "Chiusa")
                request.returnsObjectsAsFaults = true
                
                let threads = try backgroundContext.fetch(request)
                var result = Set<String>()
                result.reserveCapacity(threads.reduce(0) { $0 + $1.messageIds.count })
                
                for thread in threads {
                    for id in thread.messageIds {
                        result.insert(id)
                    }
                }
                return result
            }
            
            // Aggiorna su MainActor (siamo gia' su MainActor).
            closedEmailIds = ids
            isReady = true
            // Log leggero (non spam).
            print("[ClosedSinistroEmailIndex] ✅ Indice aggiornato: \(ids.count) email in sinistri chiusi")
        } catch {
            // In caso di errore, non bloccare pipeline: riproveremo al prossimo save.
            print("[ClosedSinistroEmailIndex] ⚠️ Errore rebuild indice: \(error)")
        }
    }
}

