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

    let container: NSPersistentContainer
    @Published private(set) var viewContext: NSManagedObjectContext

    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: "PerX")
        self.container = container
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.viewContext = context

        let url = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : (container.persistentStoreDescriptions.first?.url ?? URL(fileURLWithPath: "/dev/null"))
        do {
            try openStore(at: url)
        } catch {
            handleUnreadableStore(at: url, error: error)
        }
    }

    var storeURL: URL? {
        container.persistentStoreCoordinator.persistentStores.first?.url
    }

    /// Sposta l'archivio aperto su un altro percorso, senza lasciare il contesto senza entità.
    func relocateOpenStore(to url: URL) throws {
        let coordinator = container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first else { return }
        if store.url?.standardizedFileURL == url.standardizedFileURL { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try coordinator.migratePersistentStore(
            store,
            to: url,
            options: Self.storeOptions,
            withType: NSSQLiteStoreType
        )
        viewContext.reset()
    }

    /// Chiude l'archivio corrente e apre quello dell'account. L'aggiunta avviene prima di ogni fetch.
    func replaceStore(with url: URL) throws {
        let coordinator = container.persistentStoreCoordinator
        if coordinator.persistentStores.first?.url?.standardizedFileURL == url.standardizedFileURL {
            return
        }
        let previous = coordinator.persistentStores.first?.url
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
        do {
            try openStore(at: url)
        } catch {
            if let previous {
                try? openStore(at: previous)
            }
            throw error
        }
        viewContext.reset()
    }

    private func openStore(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try container.persistentStoreCoordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: Self.storeOptions
        )
    }

    private static let storeOptions: [String: Any] = [
        NSMigratePersistentStoresAutomaticallyOption: true,
        NSInferMappingModelAutomaticallyOption: true
    ]

    private func handleUnreadableStore(at url: URL, error: Error) -> Never {
        print("❌ Errore caricamento Core Data: \(error.localizedDescription)")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffisso = "backup-\(formatter.string(from: Date()))"
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension(suffisso)
            .appendingPathExtension(url.pathExtension)
        print("🧹 Sposto il database non apribile in: \(backupURL.path)")
        try? FileManager.default.moveItem(at: url, to: backupURL)
        for estensione in ["-shm", "-wal"] {
            let sorgente = URL(fileURLWithPath: url.path + estensione)
            let destinazione = URL(fileURLWithPath: backupURL.path + estensione)
            try? FileManager.default.moveItem(at: sorgente, to: destinazione)
        }
        fatalError("Database spostato in backup (\(backupURL.lastPathComponent)), riavvia l'app. Errore originale: \(error)")
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ Errore salvataggio context: \(error)")
        }
    }
}
