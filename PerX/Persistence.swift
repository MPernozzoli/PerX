//
//  Persistence.swift
//  PerX
//
//  Created by Massimo Pernozzoli on 13/11/24.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext
        
        let sinistro = Sinistro(context: viewContext)
        sinistro.riferimento = "2405747"
        sinistro.stato = StatoManager.StatoSinistro.istruzione.descrizione
        sinistro.dataAperturaGestione = Date()
        
        try? viewContext.save()
        
        return controller
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PerX")
        
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("❌ Errore caricamento Core Data: \(error.localizedDescription)")

                guard let storeURL = description.url ?? self.container.persistentStoreDescriptions.first?.url else {
                    fatalError("Impossibile ottenere l'URL dello store per la cancellazione: \(error)")
                }

                // Il database non si cancella: si sposta in una copia di backup accanto all'originale
                // (es. migrazione fallita dopo un cambio di modello), così perizie e stime sono recuperabili.
                do {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyyMMdd-HHmmss"
                    let suffisso = "backup-\(formatter.string(from: Date()))"
                    let backupURL = storeURL.deletingPathExtension()
                        .appendingPathExtension(suffisso)
                        .appendingPathExtension(storeURL.pathExtension)
                    print("🧹 Sposto il database non apribile in: \(backupURL.path)")
                    try FileManager.default.moveItem(at: storeURL, to: backupURL)

                    for estensione in ["-shm", "-wal"] {
                        let sorgente = URL(fileURLWithPath: storeURL.path + estensione)
                        let destinazione = URL(fileURLWithPath: backupURL.path + estensione)
                        try? FileManager.default.moveItem(at: sorgente, to: destinazione)
                    }

                    print("✅ Database salvato in backup. L'app verrà terminata. Riavvia per creare un nuovo database.")
                    fatalError("Database spostato in backup (\(backupURL.lastPathComponent)), riavvia l'app. Errore originale: \(error)")
                } catch {
                    fatalError("❌ Impossibile spostare il database a \(storeURL.path). Errore: \(error)")
                }
            } else {
                print("✅ Core Data caricato correttamente")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("💾 Context salvato correttamente")
            } catch {
                print("❌ Errore salvataggio context: \(error)")
            }
        }
    }
}
