//
//  UserScopedPersistenceController.swift
//  PerX per iPad
//
//  CoreData store separato per ogni utente.
//  Ogni utente ha il proprio file .sqlite per garantire isolamento totale.
//

import CoreData
import Foundation

final class UserScopedPersistenceController {
    let container: NSPersistentContainer
    let userEmail: String
    
    init(userEmail: String, inMemory: Bool = false) {
        self.userEmail = userEmail
        
        // Usa lo stesso model di PerX Mac
        container = NSPersistentContainer(name: "PerX")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Store per-utente: PerX_<hash>.sqlite
            let storeURL = Self.storeURL(for: userEmail)
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("[UserScopedPersistence] ❌ Errore caricamento store per \(userEmail): \(error.localizedDescription)")
                
                // Prova a eliminare store corrotto e ricrearlo
                if let url = description.url {
                    try? FileManager.default.removeItem(at: url)
                    // Riprova
                    do {
                        try self.container.persistentStoreCoordinator.addPersistentStore(
                            ofType: NSSQLiteStoreType,
                            configurationName: nil,
                            at: url,
                            options: nil
                        )
                        print("[UserScopedPersistence] ✅ Store ricreato per \(userEmail)")
                    } catch {
                        print("[UserScopedPersistence] ❌ Impossibile ricreare store: \(error)")
                    }
                }
            } else {
                print("[UserScopedPersistence] ✅ Store caricato per \(userEmail) @ \(description.url?.lastPathComponent ?? "?")")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Store URL
    
    private static func storeURL(for email: String) -> URL {
        let hash = abs(email.lowercased().hash)
        let fileName = "PerX_\(hash).sqlite"
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PerX", isDirectory: true)
        
        // Crea directory se non esiste
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        return appDir.appendingPathComponent(fileName)
    }
    
    // MARK: - Save
    
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("[UserScopedPersistence] ❌ Errore salvataggio: \(error)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    /// Elimina lo store per un utente specifico (usato per reset completo)
    static func deleteStore(for email: String) {
        let url = storeURL(for: email)
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: shmURL)
        try? FileManager.default.removeItem(at: walURL)
        
        print("[UserScopedPersistence] 🗑️ Store eliminato per \(email)")
    }
}
