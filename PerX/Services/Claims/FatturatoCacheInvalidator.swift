import Foundation
import CoreData
import Combine

/// Gestisce l'invalidazione automatica della cache del fatturato quando cambiano i dati
@MainActor
class FatturatoCacheInvalidator {
    static let shared = FatturatoCacheInvalidator()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Ascolta i cambiamenti di stato dei sinistri
        NotificationCenter.default.publisher(for: .sinistroStatoChanged)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let sinistroID = notification.userInfo?["sinistroID"] as? String else {
                    return
                }
                self.handleSinistroChange(sinistroID: sinistroID)
            }
            .store(in: &cancellables)
        
        // Ascolta i salvataggi del Core Data context per rilevare cambiamenti a definizione
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleContextSave(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleSinistroChange(sinistroID: String) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        
        guard let sinistro = try? context.fetch(request).first,
              let dataChiusura = sinistro.dataChiusura else {
            return
        }
        
        // Invalida e ricalcola per il mese della chiusura, usando l'email dell'utente assegnato
        let userEmail = sinistro.assignedToUserEmail?.lowercased()
        FatturatoCacheService.shared.invalidaCacheERicalcolaInBackground(
            for: dataChiusura,
            context: context,
            userEmail: userEmail
        )
    }
    
    private func handleContextSave(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let context = notification.object as? NSManagedObjectContext,
              context == PersistenceController.shared.container.viewContext else {
            return
        }
        
        // Controlla se ci sono oggetti Sinistro modificati
        if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updatedObjects {
                guard let sinistro = object as? Sinistro else { continue }
                
                // Verifica se è cambiato qualcosa che impatta il fatturato
                // Nota: changedValues() non funziona dopo il save, quindi controlliamo sempre se c'è dataChiusura
                if let dataChiusura = sinistro.dataChiusura {
                    // Invalida e ricalcola per il mese della chiusura, usando l'email dell'utente assegnato
                    let userEmail = sinistro.assignedToUserEmail?.lowercased()
                    FatturatoCacheService.shared.invalidaCacheERicalcolaInBackground(
                        for: dataChiusura,
                        context: context,
                        userEmail: userEmail
                    )
                }
            }
        }
    }
}

