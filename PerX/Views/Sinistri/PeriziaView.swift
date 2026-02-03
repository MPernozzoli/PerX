import SwiftUI
import CoreData

struct PeriziaView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var mediaViewerManager = MediaViewerWindowManager.shared
    @EnvironmentObject private var appState: AppState
    
    @State private var perizia: Perizia?
    @State private var hasLoadedPerizia = false
    
    // MARK: - Owner Check / Read-Only
    
    /// Email utente corrente (lowercased)
    private var currentUserEmail: String? {
        GoogleAuthService.shared.userEmail?.lowercased()
    }
    
    /// Owner effettivo: assignedToUserEmail con fallback a ownerEmail
    private var ownerEmailEffettivo: String? {
        (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased()
    }
    
    /// true se l'utente corrente può modificare la Perizia
    /// TODO: estendere per consentire modifiche ad admin e capoteam
    private var canEditPerizia: Bool {
        guard let current = currentUserEmail,
              let owner = ownerEmailEffettivo,
              !owner.isEmpty else {
            // Se non riesco a determinare owner, consenti (fallback permissivo)
            return true
        }
        return current == owner
    }
    
    private let tabs: [(title: String, icon: String)] = [
        ("Perxia", "sparkles"),
        ("Quadro Contrattuale", "doc.text"),
        ("Elaborato Calcoli", "function"),
        ("Relazione Peritale", "doc.text.magnifyingglass"),
        ("Riepilogo", "list.bullet"),
        ("Atto", "doc.richtext")
    ]
    
    private let fileService = FileService.shared
    
    // Stato locale sincronizzato con TabInfo
    @State private var currentTab: String = "Perxia"
    
    // Ottieni la sottotab corrente dalla TabInfo o usa default
    private func getSelectedTab() -> String {
        // Cerca nella finestra principale
        if let tab = appState.openTabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
            return tab.selectedSubTab ?? "Perxia"
        }
        // Cerca nelle finestre detached
        for windowState in appState.detachedWindows.values {
            if let tab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                return tab.selectedSubTab ?? "Perxia"
            }
        }
        return "Perxia"
    }
    
    private func updateSelectedTab(_ newTab: String) {
        currentTab = newTab
        // Aggiorna nella finestra principale
        if let index = appState.openTabs.firstIndex(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
            appState.openTabs[index].selectedSubTab = newTab
            appState.saveTabs()
        }
        // Aggiorna nelle finestre detached
        for (windowId, var windowState) in appState.detachedWindows {
            if let index = windowState.tabs.firstIndex(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                windowState.tabs[index].selectedSubTab = newTab
                appState.detachedWindows[windowId] = windowState
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs, id: \.title) { tab in
                        TabButton(
                            title: tab.title,
                            isSelected: currentTab == tab.title,
                            canClose: false,
                            onSelect: { updateSelectedTab(tab.title) },
                            onClose: nil,
                            icon: tab.icon
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 40)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(NSColor.windowBackgroundColor),
                        Color(NSColor.windowBackgroundColor).opacity(0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider()
            
            // Banner read-only per non-owner
            if !canEditPerizia {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                    Text("Perizia in sola lettura (sinistro non assegnato)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            // Contenuto in base alla tab selezionata
            Group {
                switch currentTab {
                case "Quadro Contrattuale":
                    QuadroContrattualeView(sinistro: sinistro, perizia: $perizia)
                case "Elaborato Calcoli":
                    ElaboratoCalcoliView(sinistro: sinistro, perizia: $perizia)
                case "Relazione Peritale":
                    RelazionePeritaleView(sinistro: sinistro, perizia: $perizia)
                case "Riepilogo":
                    RiepilogoView(sinistro: sinistro, perizia: $perizia)
                case "Atto":
                    AttoView(sinistro: sinistro, perizia: $perizia)
                case "Perxia":
                    PeriziaDetailView(sinistro: sinistro, perizia: $perizia)
                default:
                    EmptyView()
                }
            }
            .disabled(!canEditPerizia)
        }
        .onAppear {
            // Sincronizza lo stato locale con TabInfo
            currentTab = getSelectedTab()
        }
        .onChange(of: appState.openTabs) { _, _ in
            // Aggiorna quando cambiano le tab nella finestra principale
            currentTab = getSelectedTab()
        }
        .onChange(of: appState.detachedWindows) { _, _ in
            // Aggiorna quando cambiano le tab nelle finestre detached
            currentTab = getSelectedTab()
        }
        .task {
            if !hasLoadedPerizia {
                await loadOrCreatePerizia()
                hasLoadedPerizia = true
            }
        }
    }
    
    private func loadOrCreatePerizia() async {
        await viewContext.perform {
            if let existingPerizia = self.sinistro.perizia {
                self.perizia = existingPerizia
            } else {
                // Se l'utente non può modificare, NON creare una nuova Perizia
                guard self.canEditPerizia else {
                    print("[PeriziaView] ⚠️ Non creo Perizia: utente non è owner")
                    return
                }
                let newPerizia = Perizia(context: self.viewContext)
                newPerizia.id = UUID()
                newPerizia.sinistro = self.sinistro
                newPerizia.denunciaTardiva = false
                newPerizia.rivalsaPresente = false
                try? self.viewContext.save()
                self.perizia = newPerizia
            }
        }
    }
}

// Vista per il Quadro Contrattuale
struct QuadroContrattualeView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var perizia: Perizia?
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var mediaViewerManager = MediaViewerWindowManager.shared
    
    private let fileService = FileService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Polizza
                if let tipoPolizza = sinistro.tipoPolizza, !tipoPolizza.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tipoPolizza)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let numero = sinistro.numeroPolizza, !numero.isEmpty {
                                Text("Polizza n. \(numero)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                } else if let numeroPolizza = sinistro.numeroPolizza, !numeroPolizza.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        Text("Polizza n. \(numeroPolizza)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                }

                // Pulsanti azioni in alto
                HStack {
                    Spacer()
                    Button {
                        apriSimplo()
                    } label: {
                        Label("Apri Polizza", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        apriCGA()
                    } label: {
                        Label("Apri CGA", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        apriBignami()
                    } label: {
                        Label("Apri Bignami", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, (sinistro.tipoPolizza?.isEmpty == false || sinistro.numeroPolizza?.isEmpty == false) ? 0 : 10)
                
                if let perizia = perizia {
                    // Sezione Partite
                    PartiteSectionView(perizia: perizia)
                    
                    // Sezione Garanzie
                    GaranzieSectionView(perizia: perizia)
                    
                    // Descrizione Rischio
                    DescrizioneRischioView(perizia: perizia)
                    
                    // Obblighi
                    ObblighiView(perizia: perizia)
                    
                    // Coassicurazioni
                    CoassicurazioniView(sinistro: sinistro)
                    
                    // Rivalsa
                    RivalsaView(perizia: perizia)
                }
            }
            .padding(20)
        }
    }
    
    private func apriSimplo() {
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return }
        
        let files = fileService.listFilesRecursive(inDirectory: cartella)
        let simploTag = FileTagManager.FileTag.availableTags.first { $0.id == "simplo_di_polizza" }
        
        guard let simploTag = simploTag else { return }
        
        Task { @MainActor in
            var simploFiles: [URL] = []
            for file in files {
                let tags = await fileTagManager.getTagsForFile(at: file.path)
                if tags.contains(simploTag) {
                    simploFiles.append(file)
                }
            }
            
            if let firstFile = simploFiles.first {
                mediaViewerManager.openMediaViewer(for: firstFile, files: simploFiles)
            }
        }
    }
    
    private func apriCGA() {
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return }
        
        let files = fileService.listFilesRecursive(inDirectory: cartella)
        let cgaTag = FileTagManager.FileTag.availableTags.first { $0.id == "cga" }
        
        guard let cgaTag = cgaTag else { return }
        
        Task { @MainActor in
            var cgaFiles: [URL] = []
            for file in files {
                let tags = await fileTagManager.getTagsForFile(at: file.path)
                if tags.contains(cgaTag) {
                    cgaFiles.append(file)
                }
            }
            
            if let firstFile = cgaFiles.first {
                mediaViewerManager.openMediaViewer(for: firstFile, files: cgaFiles)
            }
        }
    }
    
    private func apriBignami() {
        // Implementazione futura: aprire portale Bignami online
        print("Apri Bignami - implementazione futura")
    }
}


