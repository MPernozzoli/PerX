import SwiftUI
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default)
    private var sinistri: FetchedResults<Sinistro>
    @StateObject private var appState = AppState.shared
    @StateObject private var taskManager = TaskManager.shared
    @State private var isRefreshing = false
    @State private var showingCreateManualTask = false
    @State private var revocationEvents: [RevocationEvent] = []
    @State private var selectedEvent: RevocationEvent?
    @State private var lastRefreshTime: Date?
    
    var body: some View {
        HStack(spacing: 0) {
            // Sezione sinistra (2/3) - Calendario giornaliero
            VStack(spacing: 0) {
                // Header con pulsante refresh
                HStack {
                    Text("Calendario Lavoro")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: {
                        showingCreateManualTask = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Nuova Task")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Button(action: {
                            refreshTasks()
                        }) {
                            HStack(spacing: 4) {
                                if isRefreshing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Aggiorna")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing)
                        
                        if let lastRefresh = lastRefreshTime {
                            Text(timeAgoString(from: lastRefresh))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                Divider()
                
                DailyScheduleView()
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
            
            Divider()
            
            // Sezione destra (1/3) - Notizie e Cruscotto AI
            VStack(spacing: 0) {
                // Notizie (alto)
                StudioNewsView()
                    .frame(height: 300)
                
                Divider()
                
                // Cruscotto AI (basso)
                AIActivityDashboard()
                    .frame(maxHeight: .infinity)
                
                if !revocationEvents.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Azioni automatiche IA")
                                .font(.headline)
                            Spacer()
                        }
                        ForEach(revocationEvents) { event in
                            Button {
                                selectedEvent = event
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(event.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding()
                }
            }
            .frame(width: 350)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(taskManager.$updateCounter.dropFirst()) { _ in
            // Forza aggiornamento quando cambiano le task
            // dropFirst evita trigger iniziale che causa loop
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskCreated)) { _ in
            // Quando viene creata una nuova task, verifica se va mostrata
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailReceived)) { _ in
            Task {
                await taskManager.regenerateBaseTasks(triggeredByEmail: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workScheduleChanged)) { _ in
            // Quando cambiano gli orari lavorativi, forza riorganizzazione
            Task {
                await ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revocationCompleted)) { notification in
            guard let info = notification.userInfo,
                  let ids = info["sinistroIDs"] as? [String],
                  let subject = info["emailSubject"] as? String else { return }
            let title: String
            if ids.count == 1, let ref = ids.first {
                title = "Aggiornamento stato: revoca sinistro \(ref)"
            } else {
                title = "Aggiornamento stato: revoca \(ids.count) sinistri"
            }
            let subtitle = "Da mail: \(subject)"
            let event = RevocationEvent(id: UUID(), sinistroIDs: ids, title: title, subtitle: subtitle, emailSubject: subject, emailId: info["emailId"] as? String)
            revocationEvents.insert(event, at: 0)
        }
        .onAppear {
            // Rigenera task di base all'apertura
            Task {
                // Rigenera i titoli delle task esistenti (una volta)
                await TaskManager.shared.regenerateTaskTitles()
                await TaskManager.shared.regenerateBaseTasks()
            }
        }
        .sheet(isPresented: $showingCreateManualTask) {
            CreateTaskView(
                email: nil,
                whatsAppChat: nil,
                whatsAppMessage: nil
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $selectedEvent) { event in
            RevocationEventDetailView(event: event, sinistri: sinistri)
        }
    }
    
    private func refreshTasks() {
        isRefreshing = true
        lastRefreshTime = Date()
        Task { @MainActor in
            // Prima verifica validità task esistenti (rimuove/completa quelle non più valide)
            await TaskManager.shared.validateAndCleanupExistingTasks()
            
            // Pulisci task scadute da troppo tempo
            await TaskManager.shared.cleanupExpiredTasks()
            
            // Rigenera task di base (genera solo quelle mancanti)
            await TaskManager.shared.regenerateBaseTasks()
            
            // Assicura che tutte le task base siano schedulate
            await TaskManager.shared.ensureBaseTasksAreScheduled()
            
            // Riorganizza tutte le task con gli orari aggiornati (bypassa cooldown 30s)
            ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule(userInitiated: true)
            
            isRefreshing = false
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "adesso"
        } else if timeInterval < 120 {
            return "un minuto fa"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minuti fa"
        } else if timeInterval < 7200 {
            return "un'ora fa"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) ore fa"
        } else if timeInterval < 172800 {
            return "ieri"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days) giorni fa"
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 

// MARK: - Revocation Event Models/UI
private struct RevocationEvent: Identifiable, Equatable {
    let id: UUID
    let sinistroIDs: [String]
    let title: String
    let subtitle: String
    let emailSubject: String
    let emailId: String?
}

private struct RevocationEventDetailView: View {
    let event: RevocationEvent
    let sinistri: FetchedResults<Sinistro>
    @StateObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.headline)
            Text("Trigger: \(event.emailSubject)")
                .font(.subheadline)
            Divider()
            ForEach(event.sinistroIDs, id: \.self) { id in
                if let sinistro = sinistri.first(where: { $0.riferimento == id }) {
                    SinistroEventRow(
                        sinistro: sinistro,
                        onOpenInNewWindow: {
                            appState.openSinistro(sinistro, openInNewWindow: true)
                            dismiss()
                        },
                        onOpenInCurrentWindow: {
                            appState.openSinistro(sinistro, openInNewWindow: false)
                            dismiss()
                        }
                    )
                } else {
                    Text(id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 240, alignment: .topLeading)
    }
}

/// Riga sinistro cliccabile con context menu
private struct SinistroEventRow: View {
    let sinistro: Sinistro
    let onOpenInNewWindow: () -> Void
    let onOpenInCurrentWindow: () -> Void
    
    var body: some View {
        Button(action: onOpenInNewWindow) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sinistro.riferimentoVisualizzato)
                        .fontWeight(.semibold)
                    Text(sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "Assicurato non noto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onOpenInNewWindow()
            } label: {
                Label("Apri in nuova finestra", systemImage: "rectangle.split.2x1")
            }
            
            Button {
                onOpenInCurrentWindow()
            } label: {
                Label("Apri in questa finestra", systemImage: "rectangle")
            }
        }
    }
}
