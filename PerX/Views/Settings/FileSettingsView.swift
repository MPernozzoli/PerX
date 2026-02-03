import SwiftUI
import AppKit
import CoreData

struct FileSettingsView: View {
    @AppStorage("exportDirectory") private var exportDirectory = ""
    
    // Import state
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importMessage = ""
    @State private var importedCount = 0
    @State private var scheduledForDeletionCount = 0
    @State private var detectedFolders: [(path: String, riferimento: String)] = []
    @State private var showingFolderSelection = false
    
    private let fileService = FileService.shared
    private let claimSync = ClaimSyncService.shared
    
    var body: some View {
        VStack(spacing: 24) {
            // Storage Info
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Storage Interno")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text("I file dei sinistri sono gestiti internamente dall'app")
                                .font(.subheadline)
                        }
                        
                        Text("Posizione: \(fileService.getInternalClaimsPath())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding()
            }
            
            // Esportazione
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Esportazione")
                            .font(.headline)
                        Spacer()
                    }
                    
                    DirectoryPicker(
                        title: "Cartella di esportazione (opzionale)",
                        selectedPath: $exportDirectory
                    )
                    
                    Text("Se non specificata, i file verranno esportati in ~/Downloads/PerX_Export/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Importazione cartelle sinistri
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                            .foregroundColor(.blue)
                        Text("Importa cartelle sinistri")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text("Seleziona una cartella contenente le cartelle dei sinistri. Le sottocartelle con nome a 7 cifre (es. 1234567) verranno importate automaticamente.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if isImporting {
                        VStack(spacing: 8) {
                            ProgressView(value: importProgress)
                            Text(importMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if importedCount > 0 || scheduledForDeletionCount > 0 {
                                HStack(spacing: 16) {
                                    if importedCount > 0 {
                                        Label("\(importedCount) importati", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                    if scheduledForDeletionCount > 0 {
                                        Label("\(scheduledForDeletionCount) in eliminazione", systemImage: "clock.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    } else {
                        Button {
                            selectAndImportFolder()
                        } label: {
                            Label("Seleziona cartella", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            
            // Firme
            SignatureSettingsView()
        }
        .padding()
    }
    
    // MARK: - Import Functions
    
    private func selectAndImportFolder() {
        let panel = NSOpenPanel()
        panel.message = "Seleziona la cartella contenente i sinistri"
        panel.prompt = "Importa"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        
        // Salva il bookmark per accesso
        do {
            let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: "FolderScanBookmarks") as? [String: Data] ?? [:]
            bookmarks[selectedURL.path] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: "FolderScanBookmarks")
        } catch {
            print("[Import] Errore salvataggio bookmark: \(error)")
        }
        
        // Avvia l'importazione
        isImporting = true
        importProgress = 0
        importMessage = "Analisi cartella..."
        importedCount = 0
        scheduledForDeletionCount = 0
        
        Task {
            await performImport(from: selectedURL)
        }
    }
    
    private func performImport(from rootURL: URL) async {
        let fm = FileManager.default
        let rootPath = rootURL.path
        
        // Cerca le sottocartelle con nome a 7 cifre
        var folders: [(path: String, riferimento: String)] = []
        
        // Accedi con security scope
        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }
        
        do {
            let contents = try fm.contentsOfDirectory(atPath: rootPath)
            for item in contents {
                // Verifica se è un riferimento valido (7 cifre)
                if item.count == 7 && item.allSatisfy({ $0.isNumber }) {
                    let fullPath = (rootPath as NSString).appendingPathComponent(item)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue {
                        folders.append((path: fullPath, riferimento: item))
                    }
                }
            }
        } catch {
            await MainActor.run {
                importMessage = "Errore lettura cartella: \(error.localizedDescription)"
                isImporting = false
            }
            return
        }
        
        if folders.isEmpty {
            await MainActor.run {
                importMessage = "Nessuna cartella sinistro trovata (cercavo cartelle con nome a 7 cifre)"
                isImporting = false
            }
            return
        }
        
        await MainActor.run {
            importMessage = "Trovate \(folders.count) cartelle sinistri..."
        }
        
        let context = PersistenceController.shared.container.viewContext
        var imported = 0
        var scheduledDeletion = 0
        
        for (index, folder) in folders.enumerated() {
            await MainActor.run {
                importProgress = Double(index) / Double(folders.count)
                importMessage = "Importazione \(folder.riferimento) (\(index + 1)/\(folders.count))..."
            }
            
            // Ottieni il nuovo path interno
            guard let newPath = fileService.getSinistroPath(riferimento: folder.riferimento) else {
                continue
            }
            
            // Copia ricorsivamente
            var success = false
            do {
                if let enumerator = fm.enumerator(atPath: folder.path) {
                    while let relativePath = enumerator.nextObject() as? String {
                        let sourcePath = (folder.path as NSString).appendingPathComponent(relativePath)
                        let destPath = (newPath as NSString).appendingPathComponent(relativePath)
                        
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: sourcePath, isDirectory: &isDir) {
                            if isDir.boolValue {
                                try? fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                            } else {
                                let parentDir = (destPath as NSString).deletingLastPathComponent
                                try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                                
                                if !fm.fileExists(atPath: destPath) {
                                    try fm.copyItem(atPath: sourcePath, toPath: destPath)
                                }
                            }
                        }
                    }
                }
                success = true
                imported += 1
            } catch {
                print("[Import] Errore importazione \(folder.riferimento): \(error)")
            }
            
            if success {
                // Verifica se il sinistro deve essere schedulato per eliminazione
                let shouldSchedule = await checkAndScheduleForDeletion(riferimento: folder.riferimento, context: context)
                if shouldSchedule {
                    scheduledDeletion += 1
                }
            }
            
            await MainActor.run {
                importedCount = imported
                scheduledForDeletionCount = scheduledDeletion
            }
        }
        
        await MainActor.run {
            importProgress = 1.0
            importMessage = "Importazione completata!"
            
            // Delay per mostrare il risultato
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isImporting = false
            }
        }
    }
    
    /// Verifica se un sinistro appena importato deve essere schedulato per eliminazione
    private func checkAndScheduleForDeletion(riferimento: String, context: NSManagedObjectContext) async -> Bool {
        // Cerca il sinistro nel database
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        do {
            let results = try context.fetch(request)
            guard let sinistro = results.first else {
                // Sinistro non esiste nel database - non schedulare (potrebbe essere importato per consultazione)
                return false
            }
            
            // Verifica se il sinistro è in uno stato terminale
            let stato = sinistro.stato ?? ""
            let statiTerminali = [
                StatoManager.StatoSinistro.chiusa.descrizione,
                StatoManager.StatoSinistro.revocata.descrizione,
                StatoManager.StatoSinistro.annullata.descrizione
            ]
            
            if statiTerminali.contains(stato) {
                // Il sinistro è in stato terminale, verrà automaticamente rilevato
                // da getPendingDeletions() di ClaimSyncService grazie alla scansione
                print("[Import] Sinistro \(riferimento) in stato terminale '\(stato)', sarà in lista eliminazione")
                return true
            }
            
            // Verifica se il sinistro è assegnato all'utente corrente
            let currentUserEmail = AppState.shared.googleAuthService.userEmail ?? ""
            let assignedTo = sinistro.assignedToUserEmail ?? ""
            
            if !assignedTo.isEmpty && !assignedTo.lowercased().contains(currentUserEmail.lowercased()) {
                // Non assegnato a noi - sarà gestito dalla scansione automatica
                print("[Import] Sinistro \(riferimento) non assegnato all'utente corrente")
                return true
            }
            
        } catch {
            print("[Import] Errore verifica sinistro \(riferimento): \(error)")
        }
        
        return false
    }
}

struct DirectoryPicker: View {
    let title: String
    @Binding var selectedPath: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(selectedPath.isEmpty ? "Nessuna cartella selezionata" : selectedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if !selectedPath.isEmpty {
                Button {
                    selectedPath = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Button("Sfoglia") {
                openDirectoryPicker()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            selectedPath = panel.url?.path ?? ""
        }
    }
}
