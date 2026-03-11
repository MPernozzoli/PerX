//
//  RubricaContainerView.swift
//  PerX
//
//  Vista rubrica agenzie/liquidatori integrata in ComunicazioniView
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit

// MARK: - Statistiche Agenzia

/// Statistiche per un'agenzia (numero sinistri, liquidato medio, % negative)
struct AgenziaStats {
    let codiceAgenzia: String
    let totaleSinistri: Int
    let liquidatoMedio: Double
    let percentualeNegative: Double
    
    static let empty = AgenziaStats(codiceAgenzia: "", totaleSinistri: 0, liquidatoMedio: 0, percentualeNegative: 0)
}

/// Servizio per calcolare statistiche agenzie
@MainActor
class AgenziaStatsService: ObservableObject {
    static let shared = AgenziaStatsService()
    
    @Published private(set) var statsCache: [String: AgenziaStats] = [:] // codice -> stats
    @Published private(set) var statsCachePerUtente: [String: AgenziaStats] = [:] // codice -> stats (solo utente)
    @Published private(set) var isLoading = false
    
    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }
    
    private init() {}
    
    /// Calcola statistiche per un codice agenzia (tutti i sinistri)
    func statsFor(codiceAgenzia: String) -> AgenziaStats {
        if let cached = statsCache[codiceAgenzia.uppercased()] {
            return cached
        }
        // Se non in cache, calcola in background
        Task { await loadStats(codiceAgenzia: codiceAgenzia, soloUtente: false) }
        return .empty
    }
    
    /// Calcola statistiche per un codice agenzia (solo sinistri dell'utente corrente)
    func statsForUtente(codiceAgenzia: String) -> AgenziaStats {
        if let cached = statsCachePerUtente[codiceAgenzia.uppercased()] {
            return cached
        }
        Task { await loadStats(codiceAgenzia: codiceAgenzia, soloUtente: true) }
        return .empty
    }
    
    /// Carica statistiche per tutte le agenzie
    func preloadStats(codiciAgenzie: [String]) async {
        isLoading = true
        defer { isLoading = false }
        
        for codice in codiciAgenzie {
            await loadStats(codiceAgenzia: codice, soloUtente: false)
        }
    }
    
    private func loadStats(codiceAgenzia: String, soloUtente: Bool) async {
        let codiceUpper = codiceAgenzia.uppercased()
        guard !codiceUpper.isEmpty else { return }
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
            
            // Predicate base: codice agenzia
            var predicates: [NSPredicate] = [
                NSPredicate(format: "codiceAgenzia ==[c] %@", codiceUpper)
            ]
            
            // Filtro utente se richiesto
            if soloUtente, let userEmail = GoogleAuthService.shared.userEmail?.lowercased() {
                predicates.append(NSPredicate(format: "ownerEmail ==[c] %@", userEmail))
            }
            
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            
            do {
                let sinistri = try context.fetch(fetchRequest)
                
                let totale = sinistri.count
                
                // Sinistri con liquidazione
                let conLiquidazione = sinistri.filter { $0.haLiquidazione }
                
                // Liquidato medio (solo sinistri con importo > 0)
                let importi = conLiquidazione.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.filter { $0 > 0 }
                let liquidatoMedio = importi.isEmpty ? 0 : importi.reduce(0, +) / Double(importi.count)
                
                // % negative
                let negative = sinistri.filter { $0.isNegativa }
                let percentualeNegative = totale > 0 ? (Double(negative.count) / Double(totale)) * 100 : 0
                
                let stats = AgenziaStats(
                    codiceAgenzia: codiceUpper,
                    totaleSinistri: totale,
                    liquidatoMedio: liquidatoMedio,
                    percentualeNegative: percentualeNegative
                )
                
                Task { @MainActor in
                    if soloUtente {
                        self.statsCachePerUtente[codiceUpper] = stats
                    } else {
                        self.statsCache[codiceUpper] = stats
                    }
                }
            } catch {
                print("[AgenziaStatsService] Errore fetch: \(error)")
            }
        }
    }
    
    /// Invalida cache per ricaricare
    func invalidateCache() {
        statsCache.removeAll()
        statsCachePerUtente.removeAll()
    }
}

/// Vista di caricamento rubrica: mostra progresso e messaggio senza bloccare la UI principale.
struct RubricaLoadingView: View {
    var isSyncing: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(isSyncing ? "Sincronizzazione rubrica..." : "Caricamento rubrica...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor).opacity(0.85))
    }
}

struct RubricaContainerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @StateObject private var userProfileService = UserProfileService.shared
    @State private var searchText = ""
    @State private var selectedGruppo: GruppoAssicurativo?
    @State private var selectedCompagnia: Compagnia?
    @State private var selectedAgenziaId: String?
    @State private var selectedUserId: String? // Per utenti studio
    @State private var showingAddAgenzia = false
    @State private var showingAddFiliale = false
    @State private var parentAgenziaForFiliale: RubricaAgenzia?
    @State private var showingImport = false
    @State private var showingImportPreview = false
    @State private var importFileData: Data?
    @State private var showingDeleteConfirmation = false
    @State private var copiedMessage: String?
    @AppStorage("rubricaSidebarWidth") private var sidebarWidth: Double = 320
    
    /// Agenzie non abbinate a nessuna compagnia conosciuta
    private var agenzieNonAbbinate: [RubricaAgenzia] {
        let compagnieConosciute = Set(Compagnia.allCases.filter { $0 != .unknown }.map { $0.rubricaId })
        return service.agenzie.filter { agenzia in
            !compagnieConosciute.contains(agenzia.compagniaId) && !agenzia.isFiliale
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar gerarchica
                sidebarView
                    .frame(width: sidebarWidth)
                    .background(Color(.controlBackgroundColor))
                
                // Divisore ridimensionabile
                ResizableDivider(
                    width: $sidebarWidth,
                    minWidth: 280,
                    maxWidth: min(450, geometry.size.width * 0.5)
                )
                
                // Dettaglio agenzia
                detailView
                    .frame(maxWidth: .infinity)
                    .background(Color(.textBackgroundColor))
            }
        }
        .overlay(alignment: .bottom) {
            if let message = copiedMessage {
                toastView(message)
            }
        }
        .sheet(isPresented: $showingAddAgenzia) {
            AgenziaEditorSheet(
                agenzia: nil,
                compagniaId: selectedCompagnia?.rubricaId ?? ""
            ) { nuovaAgenzia in
                Task { try? await service.saveAgenzia(nuovaAgenzia) }
            }
        }
        .sheet(item: $parentAgenziaForFiliale) { parent in
            AgenziaEditorSheet(
                agenzia: nil,
                compagniaId: parent.compagniaId,
                agenziaParentId: parent.id,
                parentName: parent.nomeCompleto
            ) { nuovaFiliale in
                Task { try? await service.saveAgenzia(nuovaFiliale) }
            }
        }
        .sheet(isPresented: $showingImportPreview) {
            if let data = importFileData {
                AgenziaImportPreviewView(
                    fileData: data,
                    onImport: { items in
                        showingImportPreview = false
                        Task {
                            let count = await service.importFromPreview(items)
                            await MainActor.run {
                                copiedMessage = "Importate \(count) agenzie"
                                importFileData = nil
                            }
                        }
                    },
                    onCancel: {
                        showingImportPreview = false
                        importFileData = nil
                    }
                )
            }
        }
        .onChange(of: showingImport) { _, show in
            if show {
                showingImport = false
                openFilePanel()
            }
        }
        .confirmationDialog(
            "Cancellare tutta la rubrica?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancella tutto", role: .destructive) {
                Task {
                    await service.deleteAllData()
                }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Questa azione cancellerà tutte le agenzie, agenti e liquidatori dalla rubrica. L'operazione non può essere annullata.")
        }
        .task {
            await service.loadInitial()
            // Avvia scansione automatica in background per abbinare agenzie
            service.startBackgroundScan(context: viewContext)
        }
        .overlay {
            if service.isLoading || (service.agenzie.isEmpty && service.isSyncing) {
                RubricaLoadingView(isSyncing: service.isSyncing)
            }
        }
    }
    
    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header con titolo e azioni
            sidebarHeader
            
            // Barra di ricerca
            searchBar
            
            // Lista gerarchica o risultati ricerca
            if searchText.isEmpty {
                hierarchyList
            } else {
                searchResultsList
            }
            
            // Footer con sync status
            syncStatusFooter
        }
    }
    
    private var sidebarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rubrica")
                    .font(.title3.bold())
                Text("\(service.agenzie.count) agenzie")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Azioni rapide
            HStack(spacing: 4) {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Importa agenzie da JSON")
                
                Button {
                    showingAddAgenzia = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Aggiungi agenzia")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Cerca agenzia, codice, città...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Color(.controlBackgroundColor))
    }
    
    private var syncStatusFooter: some View {
        HStack(spacing: 8) {
            if service.isSyncing {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Sincronizzazione...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if service.isScanning {
                ProgressView()
                    .scaleEffect(0.6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scansione sinistri...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(service.scanProgress.current), total: max(1, Double(service.scanProgress.total)))
                        .scaleEffect(y: 0.5)
                }
                if service.scanProgress.associated > 0 {
                    Text("+\(service.scanProgress.associated)")
                        .font(.caption2.bold())
                        .foregroundColor(.green)
                }
            } else {
                // Sync status
                if let date = service.lastSyncDate {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.7))
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Azioni footer
                HStack(spacing: 6) {
                    Button {
                        service.startBackgroundScan(context: viewContext)
                    } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Scansiona sinistri per abbinare agenzie")
                    
                    Button {
                        Task { await service.syncAll() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Sincronizza rubrica")
                    
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("DEBUG: Cancella tutta la rubrica")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Hierarchy List
    private var hierarchyList: some View {
        List {
            // SEZIONE STUDIO
            Section {
                DisclosureGroup {
                    ForEach(userProfileService.allProfiles) { user in
                        RubricaUserRowView(user: user, isSelected: selectedUserId == user.id)
                            .tag(user.id)
                            .onTapGesture {
                                selectedUserId = user.id
                                selectedAgenziaId = nil
                            }
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                        
                        Text("Studio")
                            .font(.subheadline.bold())
                        
                        Spacer()
                        
                        Text("\(userProfileService.allProfiles.count)")
                            .font(.caption2.bold())
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            
            // SEZIONE AGENZIE
            Section {
                ForEach(service.gruppi, id: \.self) { gruppo in
                    let compagnie = service.compagniePer(gruppo: gruppo)
                    
                    // Se il gruppo ha una sola compagnia, mostra direttamente la compagnia
                    if compagnie.count == 1, let compagnia = compagnie.first {
                        RubricaCompagniaDisclosureView(
                            compagnia: compagnia,
                            gruppo: gruppo,
                            service: service,
                            selectedAgenziaId: $selectedAgenziaId,
                            selectedCompagnia: $selectedCompagnia,
                            selectedGruppo: $selectedGruppo,
                            showingAddAgenzia: $showingAddAgenzia,
                            showingAddFiliale: $showingAddFiliale,
                            parentAgenziaForFiliale: $parentAgenziaForFiliale,
                            onSelect: { selectedUserId = nil }
                        )
                    } else {
                        // Gruppo con più compagnie - mostra disclosure group
                        RubricaGruppoDisclosureView(
                            gruppo: gruppo,
                            service: service,
                            selectedAgenziaId: $selectedAgenziaId,
                            selectedCompagnia: $selectedCompagnia,
                            selectedGruppo: $selectedGruppo,
                            showingAddAgenzia: $showingAddAgenzia,
                            showingAddFiliale: $showingAddFiliale,
                            parentAgenziaForFiliale: $parentAgenziaForFiliale,
                            onSelect: { selectedUserId = nil }
                        )
                    }
                }
            } header: {
                Text("Agenzie")
            }
            
            // SEZIONE NON ABBINATI - sempre visibile
            if !agenzieNonAbbinate.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(agenzieNonAbbinate) { agenzia in
                            RubricaAgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id)
                                .tag(agenzia.id)
                                .onTapGesture {
                                    selectedAgenziaId = agenzia.id
                                    selectedUserId = nil
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { try? await service.deleteAgenzia(agenzia.id) }
                                    } label: {
                                        Label("Elimina", systemImage: "trash")
                                    }
                                }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "questionmark.folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                            
                            Text("Non abbinati")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                            
                            Spacer()
                            
                            Text("\(agenzieNonAbbinate.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    private var searchResultsList: some View {
        let results = service.searchAgenzie(searchText)
        return VStack(spacing: 0) {
            // Risultati header
            HStack {
                Text("\(results.count) risultat\(results.count == 1 ? "o" : "i")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            
            List(results, selection: $selectedAgenziaId) { agenzia in
                RubricaAgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id)
                    .tag(agenzia.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { try? await service.deleteAgenzia(agenzia.id) }
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.plain)
        }
    }
    
    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        if let userId = selectedUserId,
           let user = userProfileService.allProfiles.first(where: { $0.id == userId }) {
            // Mostra dettaglio utente studio
            RubricaUserDetailView(user: user, onCopy: showCopied)
        } else if let agenziaId = selectedAgenziaId,
           let agenzia = service.agenzie.first(where: { $0.id == agenziaId }) {
            RubricaAgenziaDetailView(agenzia: agenzia, onCopy: showCopied) { parent in
                parentAgenziaForFiliale = parent
            }
        } else {
            emptyStateView
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Color.accentColor.opacity(0.05))
                    .frame(width: 90, height: 90)
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor.opacity(0.4))
            }
            
            VStack(spacing: 8) {
                Text("Seleziona un contatto")
                    .font(.title3.bold())
                    .foregroundColor(.primary.opacity(0.6))
                Text("Scegli un utente o un'agenzia dalla sidebar,\noppure usa la ricerca")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Seleziona il file JSON delle agenzie"
        panel.prompt = "Importa"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("[Import] File selezionato: \(url.path)")
                
                // NSOpenPanel gestisce automaticamente i permessi sandbox
                do {
                    let fileData = try Data(contentsOf: url)
                    print("[Import] Letti \(fileData.count) bytes")
                    
                    // Mostra la preview invece di importare direttamente
                    importFileData = fileData
                    showingImportPreview = true
                } catch {
                    print("[Import] Errore lettura file: \(error)")
                    copiedMessage = "Errore lettura: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func showCopied(_ text: String) {
        copiedMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedMessage = nil
        }
    }
    
    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor).opacity(0.95))
            .cornerRadius(8)
            .shadow(radius: 4)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut, value: copiedMessage)
    }
}

// MARK: - Gruppo Disclosure View
private struct RubricaGruppoDisclosureView: View {
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddAgenzia: Bool
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    var onSelect: () -> Void = {}
    
    var body: some View {
        DisclosureGroup {
            ForEach(service.compagniePer(gruppo: gruppo), id: \.self) { compagnia in
                RubricaCompagniaDisclosureView(
                    compagnia: compagnia,
                    gruppo: gruppo,
                    service: service,
                    selectedAgenziaId: $selectedAgenziaId,
                    selectedCompagnia: $selectedCompagnia,
                    selectedGruppo: $selectedGruppo,
                    showingAddAgenzia: $showingAddAgenzia,
                    showingAddFiliale: $showingAddFiliale,
                    parentAgenziaForFiliale: $parentAgenziaForFiliale,
                    onSelect: onSelect
                )
            }
        } label: {
            gruppoLabel
        }
    }
    
    private var gruppoLabel: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(gruppo.color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: gruppo.uiIconSystemName)
                    .font(.system(size: 12))
                    .foregroundColor(gruppo.color)
            }
            
            Text(gruppo.rawValue)
                .font(.subheadline.bold())
            
            Spacer()
            
            Text("\(agenzieCount)")
                .font(.caption2.bold())
                .foregroundColor(gruppo.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(gruppo.color.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private var agenzieCount: Int {
        service.compagniePer(gruppo: gruppo)
            .flatMap { service.tutteAgenziePer(compagniaId: $0.rubricaId) }
            .count
    }
}

// MARK: - Compagnia Disclosure View
private struct RubricaCompagniaDisclosureView: View {
    let compagnia: Compagnia
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddAgenzia: Bool
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    var onSelect: () -> Void = {}
    
    var body: some View {
        DisclosureGroup {
            agenzieContent
            addAgenziaButton
        } label: {
            compagniaLabel
        }
    }
    
    private var agenzieContent: some View {
        ForEach(service.agenziePer(compagniaId: compagnia.rubricaId)) { agenzia in
            RubricaAgenziaItemView(
                agenzia: agenzia,
                compagnia: compagnia,
                gruppo: gruppo,
                service: service,
                selectedAgenziaId: $selectedAgenziaId,
                selectedCompagnia: $selectedCompagnia,
                selectedGruppo: $selectedGruppo,
                showingAddFiliale: $showingAddFiliale,
                parentAgenziaForFiliale: $parentAgenziaForFiliale,
                onSelect: onSelect
            )
        }
    }
    
    private var addAgenziaButton: some View {
        Button {
            selectedCompagnia = compagnia
            showingAddAgenzia = true
        } label: {
            Label("Aggiungi agenzia", systemImage: "plus.circle")
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }
    
    private var compagniaLabel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(compagnia.color)
                .frame(width: 10, height: 10)
            
            Text(compagnia.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            let count = service.tutteAgenziePer(compagniaId: compagnia.rubricaId).count
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

// MARK: - Agenzia Item View
private struct RubricaAgenziaItemView: View {
    let agenzia: RubricaAgenzia
    let compagnia: Compagnia
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    var onSelect: () -> Void = {}
    
    private var filiali: [RubricaAgenzia] {
        service.filialiPer(agenziaId: agenzia.id)
    }
    
    var body: some View {
        if filiali.isEmpty {
            agenziaSenzaFiliali
        } else {
            agenziaConFiliali
        }
    }
    
    private var agenziaSenzaFiliali: some View {
        RubricaAgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id)
            .tag(agenzia.id)
            .onTapGesture { selectAgenzia() }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task { try? await service.deleteAgenzia(agenzia.id) }
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
    }
    
    private var agenziaConFiliali: some View {
        DisclosureGroup {
            filialiContent
            addFilialeButton
        } label: {
            RubricaAgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id, hasFiliali: true)
                .badge(filiali.count)
        }
        .tag(agenzia.id)
        .onTapGesture { selectAgenzia() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Elimina agenzia madre e tutte le filiali
                Task { try? await service.deleteAgenzia(agenzia.id) }
            } label: {
                Label("Elimina tutto", systemImage: "trash")
            }
        }
    }
    
    private var filialiContent: some View {
        ForEach(filiali) { filiale in
            RubricaAgenziaRowView(agenzia: filiale, isSelected: selectedAgenziaId == filiale.id, isFiliale: true)
                .tag(filiale.id)
                .onTapGesture { selectFiliale(filiale) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { try? await service.deleteAgenzia(filiale.id) }
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }
        }
    }
    
    private var addFilialeButton: some View {
        Button {
            parentAgenziaForFiliale = agenzia
        } label: {
            Label("Aggiungi filiale", systemImage: "plus.circle")
                .font(.caption2)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
    }
    
    private func selectAgenzia() {
        selectedAgenziaId = agenzia.id
        selectedCompagnia = compagnia
        selectedGruppo = gruppo
        onSelect()
    }
    
    private func selectFiliale(_ filiale: RubricaAgenzia) {
        selectedAgenziaId = filiale.id
        selectedCompagnia = compagnia
        selectedGruppo = gruppo
        onSelect()
    }
}

// MARK: - Agenzia Row View (Redesigned)
struct RubricaAgenziaRowView: View {
    let agenzia: RubricaAgenzia
    var isSelected: Bool = false
    var isFiliale: Bool = false
    var hasFiliali: Bool = false
    
    @ObservedObject private var statsService = AgenziaStatsService.shared
    @State private var showOnlyUserStats = false
    
    private var stats: AgenziaStats {
        if showOnlyUserStats {
            return statsService.statsForUtente(codiceAgenzia: agenzia.codice)
        } else {
            return statsService.statsFor(codiceAgenzia: agenzia.codice)
        }
    }
    
    private var compagnia: Compagnia? {
        Compagnia(rawValue: agenzia.compagniaId)
    }
    
    private var compagniaColor: Color {
        if let c = compagnia {
            return CompagniaSettingsService.shared.effectiveUiColor(c)
        }
        return .secondary
    }
    
    private var activeFlags: [RubricaAgenziaFlag] {
        RubricaAgenziaFlag.allCases.filter { $0.isOn(in: agenzia) }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icona colorata
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFiliale ? Color.secondary.opacity(0.1) : compagniaColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: isFiliale ? "building.2" : "building.columns.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isFiliale ? .secondary : compagniaColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                // Nome + suffisso
                HStack(spacing: 4) {
                    Text(agenzia.nome)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .bold : .medium)
                        .lineLimit(1)
                    
                    if let suffisso = agenzia.suffissoNome, !suffisso.isEmpty {
                        Text(suffisso)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Riga info
                HStack(spacing: 5) {
                    // Codice
                    Text(agenzia.codice)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(compagniaColor.opacity(0.8))
                    
                    // Città
                    if let citta = agenzia.citta, !citta.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(citta)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Flag icons (compatti)
                    if !activeFlags.isEmpty {
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(activeFlags.prefix(3)) { flag in
                                Image(systemName: flag.icon)
                                    .font(.system(size: 8))
                                    .foregroundColor(flag.color)
                            }
                        }
                    }
                }
                
                // Stats inline (se ha sinistri)
                if stats.totaleSinistri > 0 {
                    AgenziaStatsInlineView(stats: stats, nomeAgenzia: agenzia.nome, compagnia: compagnia, showOnlyUser: showOnlyUserStats)
                }
            }
            
            Spacer(minLength: 4)
            
            // Right side: stato apertura
            VStack(alignment: .trailing, spacing: 4) {
                if let orari = agenzia.orariApertura {
                    let stato = orari.statoAperturaAttuale()
                    Circle()
                        .fill(stato.swiftUIColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: stato.swiftUIColor.opacity(0.5), radius: 3)
                }
                
                if hasFiliali {
                    let count = CloudKitRubricaSyncService.shared.countFiliali(agenzia.id)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(compagniaColor.opacity(0.6))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .padding(.leading, isFiliale ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? compagniaColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Toggle(isOn: $showOnlyUserStats) {
                Label("Solo miei sinistri", systemImage: "person.fill")
            }
            
            Divider()
            
            Button {
                statsService.invalidateCache()
            } label: {
                Label("Aggiorna statistiche", systemImage: "arrow.clockwise")
            }
        }
    }
}

// MARK: - Stats Inline View
struct AgenziaStatsInlineView: View {
    let stats: AgenziaStats
    let nomeAgenzia: String
    let compagnia: Compagnia?
    var showOnlyUser: Bool = false
    
    /// Target liquidato medio dalla compagnia (sotto = verde)
    private var targetLiquidato: Double {
        guard let c = compagnia else { return 1000 }
        return CompagniaSettingsService.shared.effectiveTargetLiquidatoMedio(c)
    }
    
    /// Target % negative dalla compagnia (sopra = verde)
    private var targetNegative: Double {
        guard let c = compagnia else { return 10 }
        return CompagniaSettingsService.shared.effectiveTargetNegative(c)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Numero sinistri — cliccabile
            Button {
                openSinistriWindow()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 8))
                    Text("\(stats.totaleSinistri)")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Sinistri \(showOnlyUser ? "(tuoi)" : "(tutti)") — Clicca per aprire lista")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // Liquidato medio
            if stats.liquidatoMedio > 0 {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.5))
                
                HStack(spacing: 1) {
                    Image(systemName: "eurosign")
                        .font(.system(size: 7))
                    Text(formattedLiquidato)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(liquidatoColor)
                .help("Liquidato medio (target: €\(Int(targetLiquidato)))")
            }
            
            // % negative
            if stats.percentualeNegative > 0 {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("\(Int(stats.percentualeNegative))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(negativeColor)
                    .help("% negative (target: \(Int(targetNegative))%)")
            }
            
            // Indicatore filtro utente
            if showOnlyUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    /// Apre la finestra FilteredSinistriWindow con i sinistri dell'agenzia
    private func openSinistriWindow() {
        let codice = stats.codiceAgenzia.uppercased()
        let soloUtente = showOnlyUser
        let userEmail = GoogleAuthService.shared.userEmail?.lowercased()
        
        let config = FilterConfig(
            title: "Sinistri — \(nomeAgenzia)",
            subtitle: soloUtente ? "Solo i tuoi sinistri" : "Tutti i sinistri",
            iconName: "doc.text.fill",
            iconColor: compagnia?.color ?? .blue,
            customFilter: { sinistro in
                guard let sinCodice = sinistro.codiceAgenzia else { return false }
                if sinistro.stato?.lowercased() == "eliminato" { return false }
                if sinCodice.uppercased() != codice { return false }
                if soloUtente, let email = userEmail {
                    guard sinistro.ownerEmail?.lowercased() == email else { return false }
                }
                return true
            },
            dynamicColumns: DynamicColumn.defaultColumns
        )
        FilteredSinistriWindowHelper.open(config: config)
    }
    
    private var formattedLiquidato: String {
        if stats.liquidatoMedio >= 1000 {
            return String(format: "%.1fk", stats.liquidatoMedio / 1000)
        }
        return String(format: "%.0f", stats.liquidatoMedio)
    }
    
    /// Colore liquidato: verde se sotto target, rosso se sopra
    private var liquidatoColor: Color {
        if stats.liquidatoMedio <= targetLiquidato {
            return .green
        } else if stats.liquidatoMedio <= targetLiquidato * 1.5 {
            return .orange
        }
        return .red
    }
    
    /// Colore negative: verde se sopra/uguale target, rosso se sotto
    private var negativeColor: Color {
        if stats.percentualeNegative >= targetNegative {
            return .green
        } else if stats.percentualeNegative >= targetNegative * 0.5 {
            return .orange
        }
        return .red
    }
}

// MARK: - Agenzia Detail View (Redesigned)
struct RubricaAgenziaDetailView: View {
    let agenzia: RubricaAgenzia
    let onCopy: (String) -> Void
    let onAddFiliale: (RubricaAgenzia) -> Void
    
    @ObservedObject private var service = CloudKitRubricaSyncService.shared
    @State private var isEditing = false
    @State private var showingAddAgente = false
    @State private var expandedSections: Set<String> = ["contatti", "orari", "agenti"]
    
    private var filiali: [RubricaAgenzia] {
        service.filialiPer(agenziaId: agenzia.id)
    }
    
    private var compagniaAgenzia: Compagnia? {
        Compagnia(rawValue: agenzia.compagniaId)
    }
    
    private var statoApertura: StatoApertura? {
        agenzia.orariApertura?.statoAperturaAttuale()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Header
                heroHeader
                
                // Quick Actions Bar
                quickActionsBar
                
                // Content Cards
                VStack(spacing: 16) {
                    // Flag/Badge Bar
                    if !activeFlags.isEmpty {
                        flagsBar
                    }
                    
                    // Contatti Card
                    DetailCard(
                        title: "Contatti",
                        icon: "phone.bubble.fill",
                        isExpanded: expandedSections.contains("contatti")
                    ) {
                        withAnimation { toggleSection("contatti") }
                    } content: {
                        contattiContent
                    }
                    
                    // Indirizzo Card
                    if !agenzia.indirizzoCompleto.isEmpty {
                        DetailCard(
                            title: "Indirizzo",
                            icon: "mappin.and.ellipse",
                            isExpanded: expandedSections.contains("indirizzo")
                        ) {
                            withAnimation { toggleSection("indirizzo") }
                        } content: {
                            indirizzoContent
                        }
                    }
                    
                    // Orari Card
                    if agenzia.orariApertura != nil {
                        DetailCard(
                            title: "Orari di Apertura",
                            icon: "clock.fill",
                            badge: statoApertura.map { ($0.label, $0.swiftUIColor) },
                            isExpanded: expandedSections.contains("orari")
                        ) {
                            withAnimation { toggleSection("orari") }
                        } content: {
                            orariContent
                        }
                    }
                    
                    // Agenti Card
                    DetailCard(
                        title: "Agenti",
                        icon: "person.2.fill",
                        count: service.agentiPer(agenziaId: agenzia.id).count,
                        isExpanded: expandedSections.contains("agenti"),
                        action: {
                            showingAddAgente = true
                        },
                        actionIcon: "plus.circle.fill"
                    ) {
                        withAnimation { toggleSection("agenti") }
                    } content: {
                        agentiContent
                    }
                    
                    // Filiali Card (solo per agenzie madre)
                    if agenzia.agenziaParentId == nil {
                        DetailCard(
                            title: "Filiali",
                            icon: "building.2.fill",
                            count: filiali.count,
                            isExpanded: expandedSections.contains("filiali"),
                            action: {
                                onAddFiliale(agenzia)
                            },
                            actionIcon: "plus.circle.fill"
                        ) {
                            withAnimation { toggleSection("filiali") }
                        } content: {
                            filialiContent
                        }
                    }
                    
                    // Statistiche Card
                    DetailCard(
                        title: "Statistiche",
                        icon: "chart.bar.fill",
                        isExpanded: expandedSections.contains("stats")
                    ) {
                        withAnimation { toggleSection("stats") }
                    } content: {
                        AgenziaStatisticheView(
                            codiceAgenzia: agenzia.codice,
                            nomeAgenzia: agenzia.nome,
                            compagnia: compagniaAgenzia
                        )
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $isEditing) {
            AgenziaEditorSheet(
                agenzia: agenzia,
                compagniaId: agenzia.compagniaId
            ) { agenziaAggiornata in
                Task { try? await service.saveAgenzia(agenziaAggiornata) }
            }
        }
        .sheet(isPresented: $showingAddAgente) {
            AggiungiAgenteSheet(agenziaId: agenzia.id, agenziaNome: agenzia.nomeCompleto) { agente in
                Task { try? await service.saveAgente(agente) }
                showingAddAgente = false
            } onCancel: {
                showingAddAgente = false
            }
        }
    }
    
    // MARK: - Hero Header
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Background gradient
            LinearGradient(
                colors: [
                    (compagniaAgenzia?.color ?? .accentColor).opacity(0.8),
                    (compagniaAgenzia?.color ?? .accentColor).opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)
            
            // Content
            HStack(alignment: .bottom, spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: agenzia.agenziaParentId != nil ? "building.2" : "building.columns.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    // Nome
                    HStack(spacing: 8) {
                        Text(agenzia.nome)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        if let suffisso = agenzia.suffissoNome, !suffisso.isEmpty {
                            Text(suffisso)
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    // Sottotitolo
                    HStack(spacing: 12) {
                        // Codice
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.caption)
                            Text(agenzia.codice)
                                .font(.subheadline.monospaced())
                        }
                        .foregroundColor(.white.opacity(0.9))
                        
                        // Compagnia
                        if let comp = compagniaAgenzia, comp != .unknown {
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            Text(comp.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        // Badge filiale
                        if agenzia.agenziaParentId != nil {
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            Label("Filiale", systemImage: "arrow.branch")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.2))
                                .cornerRadius(4)
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Spacer()
                
                // Stato apertura badge
                if let stato = statoApertura {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(stato == .aperta ? .green : stato == .chiudePresto ? .yellow : .red)
                                .frame(width: 10, height: 10)
                                .shadow(color: stato == .aperta ? .green : stato == .chiudePresto ? .yellow : .red, radius: 4)
                            Text(stato.label)
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        
                        if let prossimo = agenzia.orariApertura?.prossimaApertura() {
                            Text(prossimo)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                
                // Edit button
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }
    
    // MARK: - Quick Actions Bar
    private var quickActionsBar: some View {
        HStack(spacing: 0) {
            // Telefoni - un pulsante per numero
            ForEach(Array(agenzia.telefoni.enumerated()), id: \.offset) { index, tel in
                if !tel.isEmpty {
                    if index > 0 {
                        Divider().frame(height: 40)
                    }
                    QuickActionButton(
                        icon: "phone.fill",
                        label: agenzia.telefoni.count > 1 ? "Tel \(index + 1)" : "Chiama",
                        color: .green
                    ) {
                        let cleaned = tel.replacingOccurrences(of: " ", with: "")
                        if let url = URL(string: "tel:\(cleaned)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            
            Divider().frame(height: 40)
            
            // Email - apre ComposeEmailView
            ForEach(Array(agenzia.email.enumerated()), id: \.offset) { index, email in
                if !email.isEmpty {
                    if index > 0 {
                        Divider().frame(height: 40)
                    }
                    QuickActionButton(
                        icon: "envelope.fill",
                        label: agenzia.email.count > 1 ? "Email \(index + 1)" : "Email",
                        color: .blue
                    ) {
                        ComposeEmailWindowManager.shared.openComposeEmail(
                            mode: .new(to: email, subject: nil)
                        )
                    }
                }
            }
            
            Divider().frame(height: 40)
            
            // Copia tutto
            QuickActionButton(
                icon: "doc.on.doc.fill",
                label: "Copia",
                color: .orange
            ) {
                let info = [
                    agenzia.nomeCompleto,
                    "Codice: \(agenzia.codice)",
                    agenzia.telefoni.isEmpty ? nil : "Tel: \(agenzia.telefoni.joined(separator: ", "))",
                    agenzia.email.isEmpty ? nil : "Email: \(agenzia.email.joined(separator: ", "))",
                    agenzia.indirizzoCompleto.isEmpty ? nil : "Indirizzo: \(agenzia.indirizzoCompleto)"
                ].compactMap { $0 }.joined(separator: "\n")
                copyToClipboard(info)
            }
            
            Divider().frame(height: 40)
            
            // Mappa
            if !agenzia.indirizzoCompleto.isEmpty {
                QuickActionButton(
                    icon: "map.fill",
                    label: "Mappa",
                    color: .red
                ) {
                    let query = agenzia.indirizzoCompleto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://maps.apple.com/?q=\(query)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Flags Bar
    private var activeFlags: [RubricaAgenziaFlag] {
        RubricaAgenziaFlag.allCases.filter { $0.isOn(in: agenzia) }
    }
    
    private var flagsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeFlags) { flag in
                    HStack(spacing: 6) {
                        Image(systemName: flag.icon)
                            .font(.caption)
                        Text(flag.rawValue)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(flag.color.opacity(0.15))
                    .foregroundColor(flag.color)
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Contatti Content
    private var contattiContent: some View {
        VStack(spacing: 12) {
            // Telefoni
            if !agenzia.telefoni.isEmpty {
                ForEach(Array(agenzia.telefoni.enumerated()), id: \.offset) { index, tel in
                    if !tel.isEmpty {
                        ContactRow(
                            icon: "phone.fill",
                            label: index == 0 ? "Principale" : "Secondario",
                            value: tel,
                            color: .green,
                            onCopy: { copyToClipboard(tel) },
                            onAction: {
                                if let url = URL(string: "tel:\(tel.replacingOccurrences(of: " ", with: ""))") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                    }
                }
            }
            
            // Email
            if !agenzia.email.isEmpty {
                ForEach(Array(agenzia.email.enumerated()), id: \.offset) { index, email in
                    if !email.isEmpty {
                        ContactRow(
                            icon: "envelope.fill",
                            label: index == 0 ? "Principale" : "Secondaria",
                            value: email,
                            color: .blue,
                            onCopy: { copyToClipboard(email) },
                            onAction: {
                                ComposeEmailWindowManager.shared.openComposeEmail(
                                    mode: .new(to: email, subject: nil)
                                )
                            }
                        )
                    }
                }
            }
            
            // Fax
            if let fax = agenzia.fax, !fax.isEmpty {
                ContactRow(
                    icon: "fax",
                    label: "Fax",
                    value: fax,
                    color: .secondary,
                    onCopy: { copyToClipboard(fax) }
                )
            }
            
            // Vuoto
            if agenzia.telefoni.isEmpty && agenzia.email.isEmpty && (agenzia.fax ?? "").isEmpty {
                EmptyStateView(message: "Nessun contatto registrato", icon: "phone.slash")
            }
        }
    }
    
    // MARK: - Indirizzo Content
    private var indirizzoContent: some View {
        HStack(spacing: 16) {
            // Map preview placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "map.fill")
                    .font(.title)
                    .foregroundColor(.red.opacity(0.5))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let via = agenzia.indirizzo, !via.isEmpty {
                    Text(via)
                        .font(.body)
                }
                
                HStack(spacing: 8) {
                    if let cap = agenzia.cap, !cap.isEmpty {
                        Text(cap)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let citta = agenzia.citta, !citta.isEmpty {
                        Text(citta)
                            .font(.subheadline.bold())
                    }
                    if let prov = agenzia.provincia, !prov.isEmpty {
                        Text("(\(prov))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button {
                    copyToClipboard(agenzia.indirizzoCompleto)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Button {
                    let query = agenzia.indirizzoCompleto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://maps.apple.com/?q=\(query)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Orari Content
    private var orariContent: some View {
        Group {
            if let orari = agenzia.orariApertura {
                ModernOrariGridView(orari: orari)
            }
        }
    }
    
    // MARK: - Agenti Content
    private var agentiContent: some View {
        let agentiList = service.agentiPer(agenziaId: agenzia.id)
        
        return Group {
            if agentiList.isEmpty {
                EmptyStateView(message: "Nessun agente registrato", icon: "person.slash")
            } else {
                VStack(spacing: 8) {
                    ForEach(agentiList) { agente in
                        AgentRow(
                            agente: agente,
                            onCopyPhone: { if let t = agente.telefoni.first { copyToClipboard(t) } },
                            onCopyEmail: { if let e = agente.email.first { copyToClipboard(e) } }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Filiali Content
    private var filialiContent: some View {
        Group {
            if filiali.isEmpty {
                EmptyStateView(message: "Nessuna filiale", icon: "building.2")
            } else {
                VStack(spacing: 8) {
                    ForEach(filiali) { filiale in
                        FilialeRow(filiale: filiale)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func toggleSection(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        onCopy("Copiato: \(text)")
    }
}

// MARK: - Supporting Views

private struct DetailCard<Content: View>: View {
    let title: String
    let icon: String
    var badge: (String, Color)? = nil
    var count: Int? = nil
    var isExpanded: Bool = true
    var action: (() -> Void)? = nil
    var actionIcon: String = "plus.circle.fill"
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 28)
                    
                    Text(title)
                        .font(.headline)
                    
                    if let count = count, count > 0 {
                        Text("\(count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(10)
                    }
                    
                    if let badge = badge {
                        Text(badge.0)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(badge.1.opacity(0.15))
                            .foregroundColor(badge.1)
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    if let action = action {
                        Button(action: action) {
                            Image(systemName: actionIcon)
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                content()
                    .padding(16)
            }
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct ContactRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let onCopy: () -> Void
    var onAction: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if let action = onAction {
                    Button(action: action) {
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AgentRow: View {
    let agente: RubricaAgente
    var onCopyPhone: () -> Void
    var onCopyEmail: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text(agente.iniziali)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(agente.nomeCompleto)
                    .font(.subheadline.bold())
                if let ruolo = agente.ruolo, !ruolo.isEmpty {
                    Text(ruolo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if !agente.telefoni.isEmpty {
                    Button(action: onCopyPhone) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.green)
                }
                
                if !agente.email.isEmpty {
                    Button(action: onCopyEmail) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

private struct FilialeRow: View {
    let filiale: RubricaAgenzia
    
    private var stato: StatoApertura? {
        filiale.orariApertura?.statoAperturaAttuale()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "building.2")
                    .foregroundColor(.blue)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(filiale.suffissoNome ?? filiale.citta ?? "Filiale")
                    .font(.subheadline.bold())
                if let citta = filiale.citta {
                    Text(citta)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Stato
            if let stato = stato {
                Circle()
                    .fill(stato.swiftUIColor)
                    .frame(width: 10, height: 10)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

private struct EmptyStateView: View {
    let message: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct ModernOrariGridView: View {
    let orari: OrariApertura
    
    var body: some View {
        VStack(spacing: 8) {
            OrarioGiornoRow(giorno: "Lun", orarioGiorno: orari.lunedi)
            OrarioGiornoRow(giorno: "Mar", orarioGiorno: orari.martedi)
            OrarioGiornoRow(giorno: "Mer", orarioGiorno: orari.mercoledi)
            OrarioGiornoRow(giorno: "Gio", orarioGiorno: orari.giovedi)
            OrarioGiornoRow(giorno: "Ven", orarioGiorno: orari.venerdi)
            OrarioGiornoRow(giorno: "Sab", orarioGiorno: orari.sabato)
            OrarioGiornoRow(giorno: "Dom", orarioGiorno: orari.domenica)
        }
    }
}

private struct OrarioGiornoRow: View {
    let giorno: String
    let orarioGiorno: OrarioGiorno
    
    private var isToday: Bool {
        let dayIndex = Calendar.current.component(.weekday, from: Date())
        let giornoIndex: [String: Int] = ["Lun": 2, "Mar": 3, "Mer": 4, "Gio": 5, "Ven": 6, "Sab": 7, "Dom": 1]
        return giornoIndex[giorno] == dayIndex
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Giorno
            Text(giorno)
                .font(.subheadline.bold())
                .foregroundColor(isToday ? .accentColor : .primary)
                .frame(width: 40, alignment: .leading)
            
            // Orari
            if orarioGiorno.aperto && !orarioGiorno.fasce.isEmpty {
                HStack(spacing: 8) {
                    ForEach(orarioGiorno.fasce) { fascia in
                        Text("\(fascia.aperturaString) - \(fascia.chiusuraString)")
                            .font(.subheadline.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isToday ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                            .foregroundColor(isToday ? .accentColor : .primary)
                            .cornerRadius(6)
                    }
                }
            } else {
                Text("Chiuso")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(isToday ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Statistiche Agenzia View
struct AgenziaStatisticheView: View {
    let codiceAgenzia: String
    let nomeAgenzia: String
    let compagnia: Compagnia?
    
    @ObservedObject private var statsService = AgenziaStatsService.shared
    @State private var showOnlyUserStats = false
    
    private var stats: AgenziaStats {
        if showOnlyUserStats {
            return statsService.statsForUtente(codiceAgenzia: codiceAgenzia)
        } else {
            return statsService.statsFor(codiceAgenzia: codiceAgenzia)
        }
    }
    
    /// Target liquidato medio dalla compagnia
    private var targetLiquidato: Double {
        guard let c = compagnia else { return 1000 }
        return CompagniaSettingsService.shared.effectiveTargetLiquidatoMedio(c)
    }
    
    /// Target % negative dalla compagnia
    private var targetNegative: Double {
        guard let c = compagnia else { return 10 }
        return CompagniaSettingsService.shared.effectiveTargetNegative(c)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistiche")
                    .font(.headline)
                
                Spacer()
                
                // Toggle filtro
                Button {
                    showOnlyUserStats.toggle()
                } label: {
                    Label(
                        showOnlyUserStats ? "Miei" : "Tutti",
                        systemImage: showOnlyUserStats ? "person.fill" : "person.2"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(showOnlyUserStats ? .accentColor : .secondary)
            }
            
            if stats.totaleSinistri == 0 {
                Text("Nessun sinistro per questa agenzia")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                HStack(spacing: 24) {
                    // Sinistri totali — cliccabile per aprire la lista
                    Button {
                        openSinistriWindow()
                    } label: {
                        StatisticaBox(
                            titolo: "Sinistri",
                            valore: "\(stats.totaleSinistri)",
                            icona: "doc.text.fill",
                            colore: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    // Liquidato medio (verde se sotto target)
                    StatisticaBox(
                        titolo: "Liquidato medio",
                        valore: formattedCurrency(stats.liquidatoMedio),
                        sottotitolo: "target: €\(Int(targetLiquidato))",
                        icona: "eurosign.circle.fill",
                        colore: liquidatoColor
                    )
                    
                    // % negative (verde se sopra target)
                    StatisticaBox(
                        titolo: "% Negative",
                        valore: String(format: "%.1f%%", stats.percentualeNegative),
                        sottotitolo: "target: \(Int(targetNegative))%",
                        icona: "xmark.circle.fill",
                        colore: negativeColor
                    )
                }
            }
        }
    }
    
    /// Apre la finestra FilteredSinistriWindow con i sinistri dell'agenzia
    private func openSinistriWindow() {
        let codice = codiceAgenzia.uppercased()
        let soloUtente = showOnlyUserStats
        let userEmail = GoogleAuthService.shared.userEmail?.lowercased()
        
        var predicateFilters: [NSPredicate] = [
            NSPredicate(format: "codiceAgenzia ==[c] %@", codice)
        ]
        if soloUtente, let email = userEmail {
            predicateFilters.append(NSPredicate(format: "ownerEmail ==[c] %@", email))
        }
        
        let config = FilterConfig(
            title: "Sinistri — \(nomeAgenzia)",
            subtitle: soloUtente ? "Solo i tuoi sinistri" : "Tutti i sinistri",
            iconName: "doc.text.fill",
            iconColor: compagnia?.color ?? .blue,
            customFilter: { sinistro in
                guard let sinCodice = sinistro.codiceAgenzia else { return false }
                if sinistro.stato?.lowercased() == "eliminato" { return false }
                if sinCodice.uppercased() != codice { return false }
                if soloUtente, let email = userEmail {
                    guard sinistro.ownerEmail?.lowercased() == email else { return false }
                }
                return true
            },
            dynamicColumns: DynamicColumn.defaultColumns
        )
        FilteredSinistriWindowHelper.open(config: config)
    }
    
    private func formattedCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "€"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "€0"
    }
    
    /// Colore liquidato: verde se sotto target, rosso se sopra
    private var liquidatoColor: Color {
        if stats.liquidatoMedio <= targetLiquidato {
            return .green
        } else if stats.liquidatoMedio <= targetLiquidato * 1.5 {
            return .orange
        }
        return .red
    }
    
    /// Colore negative: verde se sopra/uguale target, rosso se sotto
    private var negativeColor: Color {
        if stats.percentualeNegative >= targetNegative {
            return .green
        } else if stats.percentualeNegative >= targetNegative * 0.5 {
            return .orange
        }
        return .red
    }
}

// MARK: - Statistica Box
struct StatisticaBox: View {
    let titolo: String
    let valore: String
    var sottotitolo: String? = nil
    let icona: String
    let colore: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icona)
                    .foregroundColor(colore)
                Text(valore)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 1) {
                Text(titolo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let sub = sottotitolo {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(colore.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Orari Grid View
struct OrariAperturaGridView: View {
    let orari: OrariApertura
    
    private var giorniOrari: [(nome: String, orario: OrarioGiorno)] {
        [
            ("Lunedì", orari.lunedi),
            ("Martedì", orari.martedi),
            ("Mercoledì", orari.mercoledi),
            ("Giovedì", orari.giovedi),
            ("Venerdì", orari.venerdi),
            ("Sabato", orari.sabato),
            ("Domenica", orari.domenica)
        ]
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(giorniOrari, id: \.nome) { giorno in
                HStack {
                    Text(giorno.nome)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    
                    if !giorno.orario.aperto {
                        Text("Chiuso")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if giorno.orario.fasce.isEmpty {
                        Text("-")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(giorno.orario.descrizione)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

// MARK: - StatoApertura Extension
extension StatoApertura {
    var swiftUIColor: Color {
        switch self {
        case .aperta: return .green
        case .chiudePresto: return .yellow
        case .chiusa: return .red
        }
    }
    
    var label: String {
        switch self {
        case .aperta: return "Aperta"
        case .chiudePresto: return "Chiude a breve"
        case .chiusa: return "Chiusa"
        }
    }
}

// MARK: - User Row View (Studio)
struct RubricaUserRowView: View {
    let user: UserProfile
    var isSelected: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            userAvatar
            
            VStack(alignment: .leading, spacing: 2) {
                // Nome
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                // Ruolo
                if let firstRole = user.roles.first {
                    Text(firstRole.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Compleanno oggi
            if user.birthdayToday {
                Image(systemName: "birthday.cake.fill")
                    .foregroundColor(.pink)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var userAvatar: some View {
        switch user.avatarType {
        case .photo:
            if let image = user.avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } else {
                generatedAvatarView
            }
        case .generated, .gif:
            generatedAvatarView
        }
    }
    
    private var generatedAvatarView: some View {
        Circle()
            .fill(Color(hex: user.generatedAvatar.backgroundColor) ?? .accentColor)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: user.generatedAvatar.icon)
                    .font(.caption)
                    .foregroundColor(.white)
            )
    }
}

// MARK: - User Detail View (Studio)
struct RubricaUserDetailView: View {
    let user: UserProfile
    let onCopy: (String) -> Void
    
    @ObservedObject private var profileService = UserProfileService.shared
    
    /// Verifica se l'utente corrente può vedere il compleanno
    private var canSeeBirthday: Bool {
        switch user.birthdayVisibility {
        case .everyone:
            return true
        case .adminsOnly:
            return profileService.currentProfile?.isAdmin ?? false
        case .hidden:
            return false
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                Divider()
                
                // Contatti
                contattiSection
                
                Divider()
                
                // Info lavorative
                lavoroSection
                
                // Compleanno (se visibile)
                if canSeeBirthday, let birthDate = user.birthDate {
                    Divider()
                    compleanoSection(birthDate)
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Avatar grande
            largeAvatar
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Ruoli
                if !user.roles.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(user.roles, id: \.self) { role in
                            Label(role.displayName, systemImage: role.icon)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Compleanno oggi badge
            if user.birthdayToday {
                VStack {
                    Image(systemName: "birthday.cake.fill")
                        .font(.title)
                        .foregroundColor(.pink)
                    Text("Buon compleanno!")
                        .font(.caption)
                        .foregroundColor(.pink)
                }
                .padding()
                .background(Color.pink.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private var largeAvatar: some View {
        switch user.avatarType {
        case .photo:
            if let image = user.avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                largeGeneratedAvatar
            }
        case .generated, .gif:
            largeGeneratedAvatar
        }
    }
    
    private var largeGeneratedAvatar: some View {
        Circle()
            .fill(Color(hex: user.generatedAvatar.backgroundColor) ?? .accentColor)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: user.generatedAvatar.icon)
                    .font(.title)
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Contatti
    private var contattiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contatti")
                .font(.headline)
            
            // Email
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(user.email)
                    .font(.body)
                
                Spacer()
                
                Button {
                    copyToClipboard(user.email)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Lavoro
    private var lavoroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info Lavorative")
                .font(.headline)
            
            if let contract = user.contractType {
                HStack {
                    Image(systemName: contract.icon)
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    Text(contract.displayName)
                        .font(.body)
                }
            }
            
            if !user.roles.isEmpty {
                HStack {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    
                    Text(user.roles.map { $0.displayName }.joined(separator: ", "))
                        .font(.body)
                }
            }
        }
    }
    
    // MARK: - Compleanno
    private func compleanoSection(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compleanno")
                .font(.headline)
            
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundColor(.pink)
                    .frame(width: 24)
                
                // Mostra solo giorno e mese (privacy)
                Text(formattedBirthday(date))
                    .font(.body)
            }
        }
    }
    
    private func formattedBirthday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        onCopy("Copiato: \(text)")
    }
}

// MARK: - Aggiungi Agente Sheet
struct AggiungiAgenteSheet: View {
    let agenziaId: String
    let agenziaNome: String
    let onSave: (RubricaAgente) -> Void
    let onCancel: () -> Void
    
    @State private var nome = ""
    @State private var cognome = ""
    @State private var ruolo = ""
    @State private var telefono = ""
    @State private var email = ""
    @State private var note = ""
    
    private var canSave: Bool {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = cognome.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !c.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Nuovo agente")
                .font(.headline)
            Text(agenziaNome)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
            
            Form {
                Section("Anagrafica") {
                    TextField("Nome", text: $nome)
                    TextField("Cognome", text: $cognome)
                    TextField("Ruolo (opzionale)", text: $ruolo)
                }
                Section("Contatti") {
                    TextField("Telefono", text: $telefono)
                    TextField("Email", text: $email)
                }
                Section("Note") {
                    TextField("Note (opzionale)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Annulla") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Salva") {
                    let agente = RubricaAgente(
                        agenziaId: agenziaId,
                        nome: nome.trimmingCharacters(in: .whitespacesAndNewlines),
                        cognome: cognome.trimmingCharacters(in: .whitespacesAndNewlines),
                        ruolo: ruolo.isEmpty ? nil : ruolo.trimmingCharacters(in: .whitespacesAndNewlines),
                        telefoni: telefono.isEmpty ? [] : [telefono.trimmingCharacters(in: .whitespacesAndNewlines)],
                        email: email.isEmpty ? [] : [email.trimmingCharacters(in: .whitespacesAndNewlines)],
                        note: note.isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(agente)
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 320, minHeight: 340)
    }
}

// MARK: - Preview
#Preview {
    RubricaContainerView()
        .frame(width: 1000, height: 700)
}
