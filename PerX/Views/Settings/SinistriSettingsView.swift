import SwiftUI
import AppKit
import CoreData
import Combine

// MARK: - Vista unificata Sinistri + File e cartelle

struct SinistriSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // File & storage
    @AppStorage("exportDirectory") private var exportDirectory = ""
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importMessage = ""
    @State private var importedCount = 0
    @State private var scheduledForDeletionCount = 0
    
    // Claims
    @State private var showingStatiSettings = false
    @State private var showingImportView = false
    @State private var showingGenerazioneAtti = false
    @AppStorage("enableAutoDeleteClosed") private var enableAutoDelete = false
    @AppStorage("enableAutoStateChange") private var enableAutoStateChange = true
    @AppStorage("enableAutoCheck") private var enableAutoCheck = true
    @AppStorage("enableAutoCheckExcel") private var enableAutoCheckExcel = true
    @AppStorage("enableAutoCheckTags") private var enableAutoCheckTags = true
    @AppStorage("includiCodiceCompagniaRiferimento") private var includiCodiceCompagnia = true
    @AppStorage("limitaImportazioneSinistriRecenti") private var limitaImportazioneRecenti = true
    @AppStorage("rimuoviSinistriVecchiSenzaChiusura") private var rimuoviSinistriVecchi = true
    
    @ObservedObject private var indexingService = SinistriIndexingService.shared
    @StateObject private var claimSyncService = ClaimSyncService.shared
    @State private var pendingDeletions: [ClaimSyncService.PendingDeletionInfo] = []
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RelazioneTemplate.dataCreazione, ascending: false)],
        animation: .default
    ) private var templates: FetchedResults<RelazioneTemplate>
    
    @State private var editingTemplate: RelazioneTemplate?
    @State private var templateNome = ""
    @State private var templateContenuto = ""
    @State private var templateCondSopralluogo: Bool?
    @State private var templateCondFulminazione: Bool?
    @State private var templateCondLiquidiamo: Bool?
    @State private var showTemplateSheet = false
    @State private var isValidatingDates = false
    @State private var isCleaningUp = false
    @State private var cleanupResult: OldSinistriCleanupService.CleanupResult?
    
    private let fileService = FileService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                storageSection
                importSection
                documentiSection
                statiValidazioneSection
                puliziaSection
                indicizzazioneSection
                automatismiSection
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingStatiSettings) {
            StatiSettingsView()
                .frame(width: 800, height: 600)
        }
        .sheet(isPresented: $showingImportView) {
            ImportJFISHView()
                .frame(width: 1000, height: 700)
        }
        .sheet(isPresented: $showTemplateSheet) {
            templateEditor
                .frame(width: 600, height: 520)
        }
        .sheet(isPresented: $showingGenerazioneAtti) {
            GenerazioneAttiView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .onAppear { loadPendingDeletions() }
        .onChange(of: enableAutoDelete) { _ in loadPendingDeletions() }
    }
    
    // MARK: - Storage e esportazione
    
    private var storageSection: some View {
        SettingsCard(icon: "folder.fill", title: "Storage e esportazione") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage interno")
                            .font(.subheadline.weight(.medium))
                        Text(fileService.getInternalClaimsPath())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                
                Divider()
                
                DirectoryPicker(
                    title: "Cartella di esportazione (opzionale)",
                    selectedPath: $exportDirectory
                )
                Text("Se non specificata: ~/Downloads/PerX_Export/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Import
    
    private var importSection: some View {
        SettingsCard(icon: "square.and.arrow.down.fill", title: "Import") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Importa cartelle sinistri")
                            .font(.subheadline.weight(.medium))
                        Text("Sottocartelle con nome a 7 cifre (es. 1234567) verranno importate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isImporting {
                        VStack(alignment: .trailing, spacing: 6) {
                            ProgressView(value: importProgress)
                                .frame(width: 160)
                            Text(importMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if importedCount > 0 || scheduledForDeletionCount > 0 {
                                HStack(spacing: 12) {
                                    if importedCount > 0 {
                                        Label("\(importedCount) importati", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                    if scheduledForDeletionCount > 0 {
                                        Label("\(scheduledForDeletionCount) in eliminazione", systemImage: "clock.fill")
                                            .foregroundStyle(.orange)
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
                
                Divider()
                
                HStack {
                    Text("Importa dati da file esterni (CSV/Excel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Importa da JFISH") {
                        showingImportView = true
                    }
                    .buttonStyle(.bordered)
                    .help("Importa dati sinistri da file CSV o Excel")
                }
                
                Toggle("Limita importazione a sinistri recenti", isOn: $limitaImportazioneRecenti)
                    .help("Solo anno corrente e precedente (es. 24xxxxx, 25xxxxx)")
                if limitaImportazioneRecenti {
                    let y = Calendar.current.component(.year, from: Date())
                    Text("Accettati: \(y - 1) e \(y)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 20)
                }
            }
        }
    }
    
    // MARK: - Documenti e template
    
    private var documentiSection: some View {
        SettingsCard(icon: "doc.richtext.fill", title: "Documenti e template") {
            VStack(alignment: .leading, spacing: 16) {
                // Template relazioni
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Template relazioni")
                            .font(.subheadline.weight(.medium))
                        Text("\(templates.count) template configurati")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        startEditing(template: nil)
                    } label: {
                        Label("Nuovo", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if !templates.isEmpty {
                    List {
                        ForEach(templates) { template in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(template.nome)
                                        .font(.headline)
                                    Spacer()
                                    Text(conditionLabel(for: template))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(template.contenuto.prefix(100) + (template.contenuto.count > 100 ? "..." : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { startEditing(template: template) }
                        }
                        .onDelete { indexSet in
                            indexSet.map { templates[$0] }.forEach(viewContext.delete)
                            try? viewContext.save()
                        }
                    }
                    .frame(maxHeight: 180)
                }
                
                Divider()
                
                HStack {
                    Text("Generazione atti")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Gestisci template atti") {
                        showingGenerazioneAtti = true
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                SignatureSettingsView()
            }
        }
    }
    
    // MARK: - Stati e validazione
    
    private var statiValidazioneSection: some View {
        SettingsCard(icon: "list.bullet.clipboard.fill", title: "Stati e validazione") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Stati sinistro e flussi")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Configura stati") {
                        showingStatiSettings = true
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date di assegnazione")
                        .font(.subheadline.weight(.medium))
                    Text("Controlla e correggi date che violano i vincoli di sicurezza.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Ricontrolla date assegnazione") {
                        Task { await ricontrollaDate() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isValidatingDates)
                }
            }
        }
    }
    
    // MARK: - Pulizia (sinistri vecchi + eliminazione cartelle)
    
    private var puliziaSection: some View {
        SettingsCard(icon: "trash.circle.fill", title: "Pulizia e manutenzione") {
            VStack(alignment: .leading, spacing: 16) {
                // Sinistri vecchi
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Rimuovi sinistri vecchi senza data chiusura", isOn: $rimuoviSinistriVecchi)
                        .help("Mantiene solo anno corrente e precedente, o sinistri con data chiusura.")
                    if rimuoviSinistriVecchi {
                        let y = Calendar.current.component(.year, from: Date())
                        Text("Pulizia automatica all'avvio e settimanalmente.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                        Button("Esegui pulizia ora") {
                            Task { await eseguiPuliziaSinistriVecchi() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningUp)
                        .padding(.leading, 20)
                    }
                }
                
                Divider()
                
                // Eliminazione cartelle
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Elimina automaticamente cartelle sinistri chiusi/revocati", isOn: $enableAutoDelete)
                        .help("Dopo un periodo dalla chiusura/revoca, con upload preventivo dei file.")
                    
                    if enableAutoDelete {
                        HStack(spacing: 16) {
                            Label("Chiusi: \(ClaimSyncService.deletionDaysClosed) gg", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("Revocati: \(ClaimSyncService.deletionDaysRevoked) gg", systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 20)
                        
                        if !pendingDeletions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Cartelle in scadenza")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(pendingDeletions.count)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(pendingDeletions) { info in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(info.riferimento)
                                                        .font(.headline.monospacedDigit())
                                                    Text(info.reason.rawValue)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    if info.daysRemaining <= 0 {
                                                        Text("In eliminazione")
                                                            .font(.subheadline)
                                                            .foregroundStyle(.red)
                                                    } else if info.daysRemaining == 1 {
                                                        Text("Domani")
                                                            .font(.subheadline)
                                                            .foregroundStyle(.orange)
                                                    } else {
                                                        Text("Fra \(info.daysRemaining) giorni")
                                                            .font(.subheadline)
                                                            .foregroundStyle(info.daysRemaining <= 7 ? .orange : .secondary)
                                                    }
                                                    Text(formatDate(info.expirationDate))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Button {
                                                    Task {
                                                        await claimSyncService.deleteImmediately(riferimento: info.riferimento)
                                                        loadPendingDeletions()
                                                    }
                                                } label: {
                                                    Image(systemName: "trash.fill")
                                                        .foregroundStyle(.red)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Elimina subito")
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(info.daysRemaining <= 1 ? Color.orange.opacity(0.1) : Color.clear)
                                            )
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Nessuna cartella in scadenza")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Indicizzazione
    
    private var indicizzazioneSection: some View {
        SettingsCard(icon: "doc.text.magnifyingglass", title: "Indicizzazione") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Legge e aggiorna i sinistri dai file Excel 'Elaborato Peritale'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if indexingService.isIndexing {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: indexingService.indexingProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        Text("Processati: \(indexingService.indexingCurrent) / \(indexingService.indexingTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Indicizza sinistri") {
                        indexingService.startIndexing(context: viewContext)
                    }
                    .buttonStyle(.bordered)
                    .disabled(indexingService.isIndexing)
                    
                    if indexingService.isIndexing {
                        Button("Interrompi") {
                            indexingService.stopIndexing()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
                .help("Sinistri non chiusi o revocati")
            }
        }
    }
    
    // MARK: - Automatismi
    
    private var automatismiSection: some View {
        SettingsCard(icon: "gearshape.2.fill", title: "Automatismi") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Cambio stato automatico da file", isOn: $enableAutoStateChange)
                    .help("Rileva 'atto da inviare.pdf' → Atto Inviato; file in 'da chiudere' → Chiuso")
                
                Toggle("Controlli automatici file", isOn: $enableAutoCheck)
                    .help("Sopralluogo, giustificativi, tag.")
                if enableAutoCheck {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Lettura automatica dati Excel", isOn: $enableAutoCheckExcel)
                        Toggle("Applicazione automatica tag file", isOn: $enableAutoCheckTags)
                    }
                    .padding(.leading, 20)
                }
                
                Divider()
                
                Toggle("Includi codice compagnia nel riferimento", isOn: $includiCodiceCompagnia)
                    .help("Es. ZUR-2500123, CAT-2400456")
                if includiCodiceCompagnia {
                    Text("Esempio: ZUR-2500123, GEN-2500789")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
    }
    
    // MARK: - Template editor
    
    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingTemplate == nil ? "Nuovo template" : "Modifica template")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { showTemplateSheet = false }
            }
            TextField("Nome", text: $templateNome)
                .textFieldStyle(.roundedBorder)
            Picker("Sopralluogo", selection: bindingOptionalBool($templateCondSopralluogo)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Sì").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            Picker("Fulminazione", selection: bindingOptionalBool($templateCondFulminazione)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Sì").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            Picker("Liquidiamo", selection: bindingOptionalBool($templateCondLiquidiamo)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Sì").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            Text("Contenuto (usa [campo_da_compilare])")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $templateContenuto)
                .frame(minHeight: 240)
                .border(Color.secondary.opacity(0.3))
            HStack {
                Spacer()
                Button("Salva") {
                    saveTemplate()
                    showTemplateSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(templateNome.trimmingCharacters(in: .whitespaces).isEmpty || templateContenuto.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func loadPendingDeletions() {
        pendingDeletions = claimSyncService.getPendingDeletions()
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatLong(date)
    }
    
    private func conditionLabel(for template: RelazioneTemplate) -> String {
        func symbol(_ val: NSNumber?) -> String {
            guard let v = val else { return "?" }
            return v.boolValue ? "Sì" : "No"
        }
        return "Sopralluogo: \(symbol(template.condSopralluogo)) | Fulminazione: \(symbol(template.condFulminazione)) | Liquidiamo: \(symbol(template.condLiquidiamo))"
    }
    
    private func bindingOptionalBool(_ binding: Binding<Bool?>) -> Binding<Bool?> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0 })
    }
    
    private func startEditing(template: RelazioneTemplate?) {
        editingTemplate = template
        templateNome = template?.nome ?? ""
        templateContenuto = template?.contenuto ?? ""
        templateCondSopralluogo = template?.condSopralluogo?.boolValue
        templateCondFulminazione = template?.condFulminazione?.boolValue
        templateCondLiquidiamo = template?.condLiquidiamo?.boolValue
        showTemplateSheet = true
    }
    
    private func saveTemplate() {
        let entity = editingTemplate ?? RelazioneTemplate(context: viewContext)
        entity.id = editingTemplate?.id ?? UUID()
        entity.nome = templateNome
        entity.contenuto = templateContenuto
        entity.condSopralluogo = templateCondSopralluogo as NSNumber?
        entity.condFulminazione = templateCondFulminazione as NSNumber?
        entity.condLiquidiamo = templateCondLiquidiamo as NSNumber?
        entity.dataCreazione = entity.dataCreazione ?? Date()
        entity.attivo = true
        try? viewContext.save()
    }
    
    private func ricontrollaDate() async {
        guard !isValidatingDates else { return }
        isValidatingDates = true
        UserDefaults.standard.removeObject(forKey: "assignmentDateValidation_v1_done")
        await MainActor.run {
            AssignmentDateValidationService.shared.runIfNeeded(context: viewContext)
            isValidatingDates = false
        }
    }
    
    private func eseguiPuliziaSinistriVecchi() async {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        await MainActor.run {
            OldSinistriCleanupService.shared.isEnabled = rimuoviSinistriVecchi
            cleanupResult = OldSinistriCleanupService.shared.runManualCleanup(context: viewContext)
            if (cleanupResult?.removed ?? 0) > 0 {
                print("[SinistriSettings] Pulizia: \(cleanupResult!.removed) rimossi, \(cleanupResult!.skipped) mantenuti")
            }
            isCleaningUp = false
        }
    }
    
    private func selectAndImportFolder() {
        let panel = NSOpenPanel()
        panel.message = "Seleziona la cartella contenente i sinistri"
        panel.prompt = "Importa"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: "FolderScanBookmarks") as? [String: Data] ?? [:]
            bookmarks[selectedURL.path] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: "FolderScanBookmarks")
        } catch {
            print("[Import] Errore bookmark: \(error)")
        }
        isImporting = true
        importProgress = 0
        importMessage = "Analisi cartella..."
        importedCount = 0
        scheduledForDeletionCount = 0
        Task { await performImport(from: selectedURL) }
    }
    
    private func performImport(from rootURL: URL) async {
        let fm = FileManager.default
        let rootPath = rootURL.path
        var folders: [(path: String, riferimento: String)] = []
        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try fm.contentsOfDirectory(atPath: rootPath)
            for item in contents {
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
                importMessage = "Errore: \(error.localizedDescription)"
                isImporting = false
            }
            return
        }
        if folders.isEmpty {
            await MainActor.run {
                importMessage = "Nessuna cartella sinistro (nome a 7 cifre)"
                isImporting = false
            }
            return
        }
        await MainActor.run { importMessage = "Trovate \(folders.count) cartelle..." }
        let context = PersistenceController.shared.container.viewContext
        var imported = 0, scheduledDeletion = 0
        for (index, folder) in folders.enumerated() {
            await MainActor.run {
                importProgress = Double(index) / Double(folders.count)
                importMessage = "Import \(folder.riferimento) (\(index + 1)/\(folders.count))..."
            }
            guard let newPath = fileService.getSinistroPath(riferimento: folder.riferimento) else { continue }
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
                                if !fm.fileExists(atPath: destPath) { try fm.copyItem(atPath: sourcePath, toPath: destPath) }
                            }
                        }
                    }
                }
                success = true
                imported += 1
            } catch { print("[Import] \(folder.riferimento): \(error)") }
            if success {
                if await checkAndScheduleForDeletion(riferimento: folder.riferimento, context: context) {
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
            importMessage = "Completato."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isImporting = false }
        }
    }
    
    private func checkAndScheduleForDeletion(riferimento: String, context: NSManagedObjectContext) async -> Bool {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        guard let sinistro = try? context.fetch(request).first else { return false }
        let stato = sinistro.stato ?? ""
        let terminali = [StatoManager.StatoSinistro.chiusa.descrizione, StatoManager.StatoSinistro.revocata.descrizione, StatoManager.StatoSinistro.annullata.descrizione]
        if terminali.contains(stato) { return true }
        let currentEmail = AppState.shared.googleAuthService.userEmail ?? ""
        let assignedTo = sinistro.assignedToUserEmail ?? ""
        if !assignedTo.isEmpty && !assignedTo.lowercased().contains(currentEmail.lowercased()) { return true }
        return false
    }
}

// MARK: - Card con icona e titolo

private struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        GroupBox {
            content
                .padding(.vertical, 4)
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
        }
    }
}

// MARK: - Directory Picker (usato in SinistriSettingsView)

struct DirectoryPicker: View {
    let title: String
    @Binding var selectedPath: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedPath.isEmpty ? "Nessuna cartella" : selectedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !selectedPath.isEmpty {
                Button {
                    selectedPath = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Sfoglia") { openDirectoryPicker() }
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
