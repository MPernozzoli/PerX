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
        sinistro.stato = StatoManager.StatoSinistro.daScaricare.descrizione
        sinistro.dataAperturaGestione = Date()
        
        try? viewContext.save()
        
        return controller
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PerX")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("❌ Errore caricamento Core Data: \(error.localizedDescription)")

                guard let storeURL = description.url ?? self.container.persistentStoreDescriptions.first?.url else {
                    fatalError("Impossibile ottenere l'URL dello store per la cancellazione: \(error)")
                }

                do {
                    print("🧹 Sto eliminando il vecchio database a: \(storeURL.path)")
                    try FileManager.default.removeItem(at: storeURL)
                    
                    let shmFile = storeURL.path.appending("-shm")
                    let walFile = storeURL.path.appending("-wal")

                    try? FileManager.default.removeItem(atPath: shmFile)
                    try? FileManager.default.removeItem(atPath: walFile)
                    
                    print("✅ Database eliminato. L'app verrà terminata. Riavvia per creare un nuovo database.")
                    fatalError("Database eliminato, riavvia l'app. Errore originale: \(error)")
                } catch {
                    fatalError("❌ Impossibile eliminare il database a \(storeURL.path). Errore: \(error)")
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

