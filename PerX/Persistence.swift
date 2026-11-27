//
//  Persistence.swift
//  PerX
//

import CoreData

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.viewContext

        let sinistro = Sinistro(context: viewContext)
        sinistro.riferimento = "2405747"
        sinistro.stato = StatoManager.StatoSinistro.istruzione.descrizione
        sinistro.dataAperturaGestione = Date()

        try? viewContext.save()

        return controller
    }()

    private(set) var container: NSPersistentContainer
    @Published private(set) var viewContext: NSManagedObjectContext

    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: "PerX")
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        self.container = container
        self.viewContext = container.viewContext
        load(container)
    }

    var storeURL: URL? {
        container.persistentStoreDescriptions.first?.url
    }

    func releaseStore() {
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }

    func useStore(at url: URL) {
        guard storeURL?.standardizedFileURL != url.standardizedFileURL else { return }
        let next = NSPersistentContainer(name: "PerX")
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        next.persistentStoreDescriptions = [description]
        load(next)
        container = next
        viewContext = next.viewContext
    }

    private func load(_ container: NSPersistentContainer) {
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                print("❌ Errore caricamento Core Data: \(error.localizedDescription)")
                guard let storeURL = description.url else {
                    fatalError("Impossibile ottenere l'URL dello store: \(error)")
                }
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
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("❌ Errore salvataggio context: \(error)")
            }
        }
    }
}
