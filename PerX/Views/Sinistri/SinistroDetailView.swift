import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit

// MARK: - SinistroDetailView (Container principale con tabs)

struct SinistroDetailView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var statoManager = StatoManager.shared
    @StateObject private var notificationManager = SinistroNotificationManager.shared
    @EnvironmentObject private var appState: AppState
    private let fileService = FileService.shared
    
    // Stato per il debounce
    @State private var autoCheckTask: Task<Void, Never>?
    @State private var iCloudDownloadTask: Task<Void, Never>?
    @State private var iCloudMaintenanceTimer: Timer?
    
    @StateObject private var claimSyncService = ClaimSyncService.shared
    
    private let tabs = ["Dettagli", "Diario", "Fulminazione", "Cartella", "Perizia"]
    
    // Stato locale sincronizzato con TabInfo
    @State private var currentTab: String = "Dettagli"
    
    // Evidenziazione da notifica
    @State private var isHighlighted = false
    
    // MARK: - Tab Management
    
    private func getSelectedTab() -> String {
        // Cerca nella finestra principale
        if let tab = appState.openTabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
            return tab.selectedTab
        }
        // Cerca nelle finestre detached
        for windowState in appState.detachedWindows.values {
            if let tab = windowState.tabs.first(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                return tab.selectedTab
            }
        }
        return "Dettagli"
    }
    
    private func updateSelectedTab(_ newTab: String) {
        currentTab = newTab
        
        // Azzera le notifiche per questa sezione
        if let riferimento = sinistro.riferimento,
           let section = notificationManager.section(fromTabName: newTab) {
            notificationManager.clearNotifications(riferimento: riferimento, section: section)
        }
        
        // Aggiorna nella finestra principale
        if let index = appState.openTabs.firstIndex(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
            appState.openTabs[index].selectedTab = newTab
            appState.saveTabs()
        }
        // Aggiorna nelle finestre detached
        for (windowId, var windowState) in appState.detachedWindows {
            if let index = windowState.tabs.firstIndex(where: { $0.sinistro.riferimento == sinistro.riferimento }) {
                windowState.tabs[index].selectedTab = newTab
                appState.detachedWindows[windowId] = windowState
            }
        }
    }
    
    /// Ottiene il conteggio badge per un tab
    private func badgeCount(for tab: String) -> Int? {
        guard let riferimento = sinistro.riferimento,
              let section = notificationManager.section(fromTabName: tab) else {
            return nil
        }
        let count = notificationManager.getCount(riferimento: riferimento, section: section)
        return count > 0 ? count : nil
    }
    
    // MARK: - Owner Check
    
    /// Email utente corrente (lowercased)
    private var currentUserEmail: String? {
        GoogleAuthService.shared.userEmail?.lowercased()
    }
    
    /// Owner effettivo: assignedToUserEmail con fallback a ownerEmail
    private var ownerEmailEffettivo: String? {
        (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased()
    }
    
    /// Nome display dell'owner
    private var ownerDisplayName: String {
        sinistro.assignedToUserName ?? sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "Sconosciuto"
    }
    
    /// true se l'utente corrente NON è l'owner
    private var isViewingAsNonOwner: Bool {
        guard let current = currentUserEmail,
              let owner = ownerEmailEffettivo,
              !owner.isEmpty else {
            return false
        }
        return current != owner
    }
    
    /// true se l'utente corrente è assegnato al sinistro
    private var isSinistroAssignedToCurrentUser: Bool {
        guard let current = currentUserEmail,
              !current.isEmpty else {
            return false
        }
        let assigned = ownerEmailEffettivo ?? ""
        return assigned == current && !assigned.isEmpty
    }
    
    /// true se il sinistro è in uno stato terminale (chiusa, revocata, annullata)
    private var isSinistroInTerminalState: Bool {
        let terminalStates = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        guard let stato = sinistro.stato else { return false }
        return terminalStates.contains(stato)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Banner "Sinistro assegnato a …" se l'utente corrente non è l'owner
            if isViewingAsNonOwner {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .foregroundColor(.orange)
                    Text("Sinistro assegnato a \(ownerDisplayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    
                    // Pulsante "Reclama" per assumere la gestione del sinistro
                    Button(action: {
                        Task {
                            await reclaimSinistro()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.raised.fill")
                            Text("Reclama")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Richiedi la gestione di questo sinistro")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.orange.opacity(0.3)),
                    alignment: .bottom
                )
            }
            
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs, id: \.self) { tab in
                        TabButton(
                            title: tab,
                            isSelected: currentTab == tab,
                            canClose: false,
                            onSelect: { updateSelectedTab(tab) },
                            onClose: nil,
                            badgeCount: badgeCount(for: tab)
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
            
            // Contenuto in base alla tab selezionata
            switch currentTab {
            case "Dettagli":
                SinistroDetailContentView(sinistro: sinistro, onOpenCollegato: nil)
            case "Diario":
                DiarioView(sinistro: sinistro)
            case "Fulminazione":
                FulminazioneView(sinistro: sinistro)
            case "Cartella":
                CartellaView(sinistro: sinistro)
            case "Perizia":
                PeriziaView(sinistro: sinistro)
            default:
                EmptyView()
            }
        }
        .overlay(
            // Overlay di evidenziazione quando aperto da notifica
            Group {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 3)
                        .shadow(color: Color.blue.opacity(0.5), radius: 10, x: 0, y: 0)
                        .animation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true), value: isHighlighted)
                }
            }
        )
        .onAppear {
            // Traccia interazione per filtro "Ultimi"
            SinistroInteractionTracker.shared.recordInteraction(sinistroId: sinistro.id)
            
            // Sincronizza lo stato locale con TabInfo
            currentTab = getSelectedTab()
            
            // Azzera le notifiche per la sezione corrente
            if let riferimento = sinistro.riferimento,
               let section = notificationManager.section(fromTabName: currentTab) {
                notificationManager.clearNotifications(riferimento: riferimento, section: section)
            }
            
            // Cancella i task precedenti se esistono
            autoCheckTask?.cancel()
            iCloudDownloadTask?.cancel()
            iCloudMaintenanceTimer?.invalidate()
            
            // Avvia download iCloud se la cartella esiste
            if let riferimento = sinistro.riferimento,
               let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) {
                startiCloudDownload(for: sinistroPath)
                startiCloudMaintenance(for: sinistroPath)
            }
            
            // Fetch dati completi da CloudKit (on-demand)
            if let riferimento = sinistro.riferimento {
                Task {
                    await CloudKitSinistroSyncService.shared.fetchFullSinistro(riferimento: riferimento)
                }
            }
            
            // Trigger Hub sync per cartella (se in modalità Hub)
            if let riferimento = sinistro.riferimento,
               HubModeService.shared.fileMode == .hub {
                Task {
                    await triggerHubFolderSync(riferimento: riferimento)
                }
            }
            
            // Verifica numeri WhatsApp (in background, solo se connesso)
            if WhatsAppService.shared.isConnected {
                Task {
                    await checkWhatsAppNumbers()
                }
            }
            
            // Avvia sync temporaneo se sinistro non proprio o in stato terminale
            if let riferimento = sinistro.riferimento {
                let isNonOwner = !isSinistroAssignedToCurrentUser
                let isTerminalState = isSinistroInTerminalState
                
                if isNonOwner || isTerminalState {
                    Task {
                        await claimSyncService.startTemporarySync(for: sinistro)
                    }
                }
            }
            
            // Crea un nuovo task con debounce
            autoCheckTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
                guard !Task.isCancelled else { return }
                
                print("[SinistroDetailView] 🔍 Avvio AutoCheck per sinistro \(sinistro.riferimento ?? "N/A")")
                await AutoCheckService.shared.performAutoChecks(for: sinistro, context: viewContext)
                print("[SinistroDetailView] ✅ AutoCheck completato")
            }
        }
        .onChange(of: appState.openTabs) { _, _ in
            currentTab = getSelectedTab()
        }
        .onChange(of: appState.detachedWindows) { _, _ in
            currentTab = getSelectedTab()
        }
        .onChange(of: currentTab) { oldTab, newTab in
            if newTab == "Cartella" || newTab == "Dettagli" {
                autoCheckTask?.cancel()
                autoCheckTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    print("[SinistroDetailView] 🔄 Refresh AutoCheck per tab \(newTab)")
                    await AutoCheckService.shared.performAutoChecks(for: sinistro, context: viewContext)
                }
            }
        }
        .onDisappear {
            autoCheckTask?.cancel()
            iCloudDownloadTask?.cancel()
            iCloudMaintenanceTimer?.invalidate()
            
            // Ferma sync temporaneo se attivo
            if let riferimento = sinistro.riferimento,
               claimSyncService.hasTemporarySync(for: riferimento) {
                Task {
                    await claimSyncService.stopTemporarySync(for: riferimento)
                }
            }
        }
        // Dialog rimosso: la sync viene sospesa automaticamente quando il sinistro viene chiuso
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HighlightSinistroFromNotification"))) { note in
            guard let rif = note.userInfo?["riferimento"] as? String,
                  rif == sinistro.riferimento else { return }
            
            // Evidenzia il sinistro con animazione
            withAnimation(.easeInOut(duration: 0.3)) {
                isHighlighted = true
            }
            
            // Rimuovi evidenziazione dopo 2 secondi
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isHighlighted = false
                }
            }
        }
    }
    
    // MARK: - Hub Folder Sync
    
    /// Trigger sync cartella tramite Hub (DB Legacy -> Vault -> Client)
    private func triggerHubFolderSync(riferimento: String) async {
        do {
            // Richiedi disponibilità cartella all'Hub
            let result = try await HubAPIClient.shared.ensureFolderAvailable(sinistroRef: riferimento)
            
            switch result.status {
            case "available":
                // Cartella già disponibile, scarica dal Vault
                print("[SinistroDetailView] Folder available, syncing from Vault...")
                await claimSyncService.downloadClaimFolder(riferimento: riferimento)
                
            case "importing":
                // Import in corso, mostra stato
                print("[SinistroDetailView] Folder importing from FS Legacy...")
                // La UI mostrerà "Cartella in preparazione"
                
            case "error":
                print("[SinistroDetailView] Folder sync error")
            default:
                break
            }
        } catch {
            print("[SinistroDetailView] Hub folder sync failed: \(error)")
        }
    }
    
    // MARK: - iCloud Management
    
    private func startiCloudDownload(for sinistroPath: String) {
        iCloudDownloadTask?.cancel()
        
        iCloudDownloadTask = Task { @MainActor in
            await Task.detached(priority: .utility) {
                fileService.downloadAlliCloudFiles(inDirectory: sinistroPath) { count in
                    if count > 0 {
                        print("[SinistroDetailView] 📥 Avviati download per \(count) file iCloud")
                    }
                }
            }.value
        }
    }
    
    private func startiCloudMaintenance(for sinistroPath: String) {
        iCloudMaintenanceTimer?.invalidate()
        
        let riferimento = sinistro.riferimento
        
        iCloudMaintenanceTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { timer in
            Task { @MainActor in
                let isOpen = appState.openTabs.contains { $0.sinistro.riferimento == riferimento } ||
                            appState.detachedWindows.values.contains { windowState in
                                windowState.tabs.contains { $0.sinistro.riferimento == riferimento }
                            }
                
                if isOpen {
                    await Task.detached(priority: .utility) {
                        fileService.downloadAlliCloudFiles(inDirectory: sinistroPath)
                    }.value
                } else {
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - Reclama Sinistro
    
    /// Verifica quali numeri di telefono del sinistro sono su WhatsApp
    private func checkWhatsAppNumbers() async {
        // Raccogli tutti i numeri di telefono dal sinistro
        var allNumbers: [String] = []
        
        // Telefoni assicurato
        allNumbers.append(contentsOf: sinistro.telefoniAssicuratoArray)
        if let tel = sinistro.telefonoAssicurato, !tel.isEmpty {
            allNumbers.append(tel)
        }
        
        // Telefono contraente
        if let tel = sinistro.telefonoContraente, !tel.isEmpty {
            allNumbers.append(tel)
        }
        
        // Telefono danneggiato
        if let tel = sinistro.telefonoDanneggiato, !tel.isEmpty {
            allNumbers.append(tel)
        }
        
        // Telefono agenzia
        if let tel = sinistro.telefonoAgenzia, !tel.isEmpty {
            allNumbers.append(tel)
        }
        
        // Filtra numeri vuoti e verifica in batch
        let validNumbers = allNumbers.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validNumbers.isEmpty else { return }
        
        await WhatsAppNumberCacheService.shared.checkNumbers(validNumbers)
    }
    
    /// Reclama il sinistro: cambia l'assegnatario all'utente corrente e sincronizza immediatamente su CloudKit
    private func reclaimSinistro() async {
        guard let currentUsername = CurrentUserService.shared.currentUsername,
              !currentUsername.isEmpty else {
            print("[SinistroDetailView] ❌ Impossibile reclamare: utente non autenticato")
            return
        }
        let currentName = UserProfileService.shared.currentProfile?.displayName ?? currentUsername
        let currentEmail = CurrentUserService.shared.currentEmail?.lowercased()
        
        let previousEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased()
        let previousName = sinistro.assignedToUserName ?? sinistro.ownerEmail ?? "Utente precedente"
        
        let oggi = Date()
        let riferimento = sinistro.riferimento ?? "N/A"
        let nomeAssicurato = sinistro.nomeAssicurato ?? "Assicurato"
        
        await viewContext.perform {
            sinistro.assignedToUserEmail = currentUsername
            sinistro.assignedToUserName = currentName
            sinistro.dataAssegnazione = oggi
            sinistro.cloudKitLastModified = oggi
            
            // Aggiungi entry al diario
            let diarioEntry = DiarioEntry(
                timestamp: oggi,
                tipo: .sistema,
                titolo: "Sinistro reclamato",
                riassunto: "\(currentName) ha reclamato la gestione del sinistro",
                contenutoCompleto: "Utente: \(currentName) (\(currentEmail))\nPrecedente assegnatario: \(previousName)\nData e ora: \(DateUtils.formatDetail(oggi))"
            )
            sinistro.addDiarioEntry(diarioEntry)
            
            try? viewContext.save()
        }
        
        print("[SinistroDetailView] ✅ Sinistro \(riferimento) reclamato da \(currentName)")
        
        // Push immediato su CloudKit
        await CloudKitSinistroSyncService.shared.pushSinistro(sinistro)
        
        if let prevEmail = previousEmail, !prevEmail.isEmpty, prevEmail != currentUsername, prevEmail != (currentEmail ?? "") {
            await SinistroReclaimNotificationService.shared.sendReclaimNotification(
                toUserEmail: prevEmail,
                reclaimedByName: currentName,
                riferimento: riferimento,
                nomeAssicurato: nomeAssicurato
            )
        }
        
        // Emetti notifica locale per aggiornare UI
        NotificationCenter.default.post(
            name: NotificationNames.sinistroReclaimed,
            object: nil,
            userInfo: [
                "sinistroID": riferimento,
                "newOwnerEmail": currentEmail,
                "previousOwnerEmail": previousEmail ?? ""
            ]
        )
    }
}

// MARK: - SinistroTabView (usata altrove per visualizzare tab sinistro)

struct SinistroTabView: View {
    let sinistro: Sinistro
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    let isMainTab: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if !isMainTab {
                Circle()
                    .fill(getStatoColor(sinistro.stato))
                    .frame(width: 8, height: 8)
            }
            
            Text(isMainTab ? "Dettagli" : sinistro.riferimentoVisualizzato)
                .lineLimit(1)
            
            if !isMainTab && onClose != nil {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
        )
        .onTapGesture(perform: onSelect)
    }
    
    private func getStatoColor(_ stato: String?) -> Color {
        switch stato {
        case "Da Scaricare": return .orange
        case "In Gestione": return .blue
        case "Atto Inviato": return .purple
        case "Chiuso": return .green
        case "Revocato": return .red
        default: return .gray
        }
    }
}

// MARK: - DateRow (legacy, mantenuto per compatibilità)

struct DateRow: View {
    let title: String
    @Binding var date: Date
    let placeholder: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            if date == Date() {
                Text(placeholder)
                    .italic()
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
                    .disabled(true)
            }
        }
    }
}
