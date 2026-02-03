import SwiftUI
import CoreData
import Combine

struct ClaimsSettingsView: View {
    @State private var showingStatiSettings = false
    @State private var showingImportView = false
    @State private var showingGenerazioneAtti = false
    @Environment(\.managedObjectContext) private var viewContext
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
    @State private var templateNome: String = ""
    @State private var templateContenuto: String = ""
    @State private var templateCondSopralluogo: Bool? = nil
    @State private var templateCondFulminazione: Bool? = nil
    @State private var templateCondLiquidiamo: Bool? = nil
    @State private var showTemplateSheet = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Template relazioni
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Gestione Template Relazioni")
                            .font(.headline)
                        Spacer()
                        Button {
                            startEditing(template: nil)
                        } label: {
                            Label("Nuovo Template", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if templates.isEmpty {
                        Text("Nessun template configurato")
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(templates) { template in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(template.nome)
                                            .font(.headline)
                                        Spacer()
                                        Text(conditionLabel(for: template))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(template.contenuto.prefix(120) + (template.contenuto.count > 120 ? "..." : ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { startEditing(template: template) }
                            }
                            .onDelete { indexSet in
                                indexSet.map { templates[$0] }.forEach(viewContext.delete)
                                try? viewContext.save()
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .padding()
            }
            
            // Sezione Stati
            GroupBox {
                HStack {
                    Text("Gestione Stati")
                        .font(.headline)
                    Spacer()
                    Button("Configura Stati") {
                        showingStatiSettings = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Sezione Generazione Atti
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generazione Atti")
                            .font(.headline)
                        Text("Gestisci i template per la generazione automatica degli atti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Gestisci Template") {
                        showingGenerazioneAtti = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Sezione Import
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Import Dati")
                            .font(.headline)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Importa dati dei sinistri da file esterni")
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        Button("Importa da JFISH") {
                            showingImportView = true
                        }
                        .buttonStyle(.bordered)
                        .help("Importa dati sinistri da file CSV o Excel")
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Limita importazione sinistri a recenti", isOn: $limitaImportazioneRecenti)
                            .help("Permette solo l'import di sinistri dell'anno corrente e dell'anno precedente. I sinistri più vecchi verranno rifiutati.")
                        
                        if limitaImportazioneRecenti {
                            let currentYear = Calendar.current.component(.year, from: Date())
                            let previousYear = currentYear - 1
                            Text("Sinistri accettati: \(previousYear) e \(currentYear) (es. 24xxxxx, 25xxxxx)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding()
            }
            
            // Sezione Validazione Date
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Validazione Date")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controlla e correggi le date di assegnazione che violano i vincoli di sicurezza")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Button("Ricontrolla Date Assegnazione") {
                            Task {
                                await ricontrollaDate()
                            }
                        }
                        .buttonStyle(.bordered)
                        .help("Esegue una validazione completa di tutte le date di assegnazione e corregge quelle errate")
                    }
                }
                .padding()
            }
            
            // Sezione Pulizia Sinistri Vecchi
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "calendar.badge.minus")
                            .foregroundColor(.orange)
                        Text("Pulizia Sinistri Vecchi")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Rimuovi sinistri vecchi senza data chiusura", isOn: $rimuoviSinistriVecchi)
                            .help("Rimuove automaticamente sinistri non recenti (anni precedenti) che non hanno data chiusura. I sinistri vecchi con data chiusura vengono mantenuti.")
                        
                        if rimuoviSinistriVecchi {
                            let currentYear = Calendar.current.component(.year, from: Date())
                            let previousYear = currentYear - 1
                            Text("Sinistri mantenuti: solo quelli dell'anno corrente (\(currentYear)) e precedente (\(previousYear)) O con data chiusura")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                            
                            Text("La pulizia viene eseguita automaticamente all'avvio e settimanalmente")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                            
                            Button("Esegui Pulizia Ora") {
                                Task {
                                    await eseguiPuliziaSinistriVecchi()
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("Esegue manualmente la pulizia dei sinistri vecchi senza data chiusura")
                        }
                    }
                }
                .padding()
            }
            
            // Sezione Indicizzazione
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Indicizzazione Sinistri")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Legge e aggiorna i sinistri dai file Excel 'Elaborato Peritale'")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        if indexingService.isIndexing {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: indexingService.indexingProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                                
                                HStack {
                                    Text("Processati: \(indexingService.indexingCurrent) / \(indexingService.indexingTotal)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        
                        HStack {
                            Button("Indicizza Sinistri") {
                                indexingService.startIndexing(context: viewContext)
                            }
                            .buttonStyle(.bordered)
                            .disabled(indexingService.isIndexing)
                            
                            if indexingService.isIndexing {
                                Button("Interrompi") {
                                    indexingService.stopIndexing()
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        .help("Legge i file Excel per tutti i sinistri non chiusi o revocati")
                    }
                }
                .padding()
            }
            
            // Sezione Automatismi File
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Text("Automatismi File")
                            .font(.headline)
                        Spacer()
                    }
                    
                    // Cambio stato automatico
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Cambio stato automatico in base ai file", isOn: $enableAutoStateChange)
                            .help("Aggiorna automaticamente lo stato del sinistro quando vengono trovati file specifici (atto da inviare.pdf, file di chiusura)")
                        
                        if enableAutoStateChange {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Rileva 'atto da inviare.pdf' → stato 'Atto Inviato'")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Rileva file nella cartella 'da chiudere' → stato 'Chiuso'")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    
                    Divider()
                    
                    // AutoCheck
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Controlli automatici file", isOn: $enableAutoCheck)
                            .help("Esegue controlli automatici sui file della cartella sinistro (sopralluogo, giustificativi, tag)")
                        
                        if enableAutoCheck {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Lettura automatica dati Excel", isOn: $enableAutoCheckExcel)
                                    .help("Legge automaticamente i dati dal file Excel 'Elaborato Peritale' e aggiorna il sinistro")
                                
                                Toggle("Applicazione automatica tag file", isOn: $enableAutoCheckTags)
                                    .help("Applica automaticamente tag ai file in base al loro contenuto e tipo")
                            }
                            .padding(.leading, 20)
                        }
                    }
                    
                    Divider()
                    
                    // Visualizzazione riferimento
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Includi codice compagnia nel riferimento", isOn: $includiCodiceCompagnia)
                            .help("Mostra il riferimento come [SIGLA]-[numero] es. ZUR-2500123")
                        
                        if includiCodiceCompagnia {
                            Text("Esempio: ZUR-2500123, CAT-2400456, GEN-2500789")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding()
            }
            
            // Sezione Eliminazione Automatica Cartelle
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "trash.circle")
                            .foregroundColor(.orange)
                        Text("Eliminazione Automatica Cartelle")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Toggle("Elimina automaticamente le cartelle dei sinistri chiusi/revocati", isOn: $enableAutoDelete)
                        .help("Elimina le cartelle locali dopo un periodo di tempo dalla chiusura o revoca")
                    
                    if enableAutoDelete {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                Label("Sinistri chiusi: \(ClaimSyncService.deletionDaysClosed) giorni", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Label("Sinistri revocati: \(ClaimSyncService.deletionDaysRevoked) giorni", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                            
                            Text("Prima dell'eliminazione viene eseguito un upload automatico dei file locali non presenti sul server.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                        
                        Divider()
                        
                        // Lista cartelle in scadenza
                        if pendingDeletions.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Nessuna cartella in scadenza")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Cartelle in scadenza")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text("\(pendingDeletions.count)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(8)
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
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Spacer()
                                                
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    if info.daysRemaining <= 0 {
                                                        Text("In eliminazione")
                                                            .font(.subheadline)
                                                            .foregroundColor(.red)
                                                    } else if info.daysRemaining == 1 {
                                                        Text("Domani")
                                                            .font(.subheadline)
                                                            .foregroundColor(.orange)
                                                    } else {
                                                        Text("Fra \(info.daysRemaining) giorni")
                                                            .font(.subheadline)
                                                            .foregroundColor(info.daysRemaining <= 7 ? .orange : .secondary)
                                                    }
                                                    Text(formatDate(info.expirationDate))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Button {
                                                    Task {
                                                        await claimSyncService.deleteImmediately(riferimento: info.riferimento)
                                                        loadPendingDeletions()
                                                    }
                                                } label: {
                                                    Image(systemName: "trash.fill")
                                                        .foregroundColor(.red)
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
                                .frame(maxHeight: 250)
                            }
                        }
                    }
                }
                .padding()
            }
            .onChange(of: enableAutoDelete) { _ in
                loadPendingDeletions()
            }
            
            Spacer()
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
        .onAppear {
            loadPendingDeletions()
        }
    }
    
    private func loadPendingDeletions() {
        pendingDeletions = claimSyncService.getPendingDeletions()
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatLong(date)
    }
    
    
    // MARK: - Template Relazioni
    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingTemplate == nil ? "Nuovo Template" : "Modifica Template")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { showTemplateSheet = false }
            }
            TextField("Nome", text: $templateNome)
                .textFieldStyle(.roundedBorder)
            Picker("Sopralluogo", selection: bindingOptionalBool($templateCondSopralluogo)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Si").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            Picker("Fulminazione", selection: bindingOptionalBool($templateCondFulminazione)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Si").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            Picker("Liquidiamo", selection: bindingOptionalBool($templateCondLiquidiamo)) {
                Text("Qualsiasi").tag(Optional<Bool>.none)
                Text("Si").tag(Optional(true))
                Text("No").tag(Optional(false))
            }
            .pickerStyle(.segmented)
            
            Text("Contenuto (usa [campo_da_compilare])")
                .font(.caption)
                .foregroundColor(.secondary)
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
    
    private func conditionLabel(for template: RelazioneTemplate) -> String {
        func symbol(_ val: NSNumber?) -> String {
            guard let v = val else { return "?" }
            return v.boolValue ? "Si" : "No"
        }
        return "Sopralluogo: \(symbol(template.condSopralluogo)) | Fulminazione: \(symbol(template.condFulminazione)) | Liquidiamo: \(symbol(template.condLiquidiamo))"
    }
    
    private func bindingOptionalBool(_ binding: Binding<Bool?>) -> Binding<Bool?> {
        Binding<Bool?>(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0 }
        )
    }
    
    // MARK: - Validazione Date
    
    @State private var isValidatingDates = false
    
    private func ricontrollaDate() async {
        guard !isValidatingDates else { return }
        isValidatingDates = true
        
        // Reset del flag per permettere nuova esecuzione
        UserDefaults.standard.removeObject(forKey: "assignmentDateValidation_v1_done")
        
        await MainActor.run {
            AssignmentDateValidationService.shared.runIfNeeded(context: viewContext)
            isValidatingDates = false
        }
    }
    
    // MARK: - Pulizia Sinistri Vecchi
    
    @State private var isCleaningUp = false
    @State private var cleanupResult: OldSinistriCleanupService.CleanupResult?
    
    private func eseguiPuliziaSinistriVecchi() async {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        await MainActor.run {
            OldSinistriCleanupService.shared.isEnabled = rimuoviSinistriVecchi
            let result = OldSinistriCleanupService.shared.runManualCleanup(context: viewContext)
            cleanupResult = result
            
            if result.removed > 0 {
                print("[ClaimsSettings] ✅ Pulizia completata: \(result.removed) sinistri rimossi, \(result.skipped) mantenuti")
            }
            
            isCleaningUp = false
        }
    }
} 