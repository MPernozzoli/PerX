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
    @StateObject private var summaryService = DashboardSummaryService.shared
    @StateObject private var newsService = StudioNewsService.shared
    @State private var isRefreshing = false
    @State private var showingCreateManualTask = false
    @State private var revocationEvents: [RevocationEvent] = []
    @State private var selectedEvent: RevocationEvent?
    @State private var lastRefreshTime: Date?
    @State private var aiSummaryText: String?
    @State private var aiSummaryLoading = false
    @State private var aiSummaryRequested = false
    @State private var showingCalendarDetail = false
    
    private var currentUserEmail: String? { CurrentUserService.shared.currentEmail }
    private var sinistriInGestione: Int {
        summaryService.sinistriInGestione(context: viewContext, userEmail: currentUserEmail)
    }
    private var assegnazioniRecenti: Int {
        summaryService.assegnazioniDallUltimoAccesso(context: viewContext, userEmail: currentUserEmail)
    }
    private var taskPerOggi: [ScheduledTask] { summaryService.taskPerOggi() }
    
    // Placeholder minimale per debug: disaccoppiamo temporaneamente la dashboard reale
    var body: some View {
        VStack(spacing: 16) {
            Text("Dashboard disattivata temporaneamente")
                .font(.title2)
            Text("Stiamo isolando il problema dei \"Publishing changes from within view updates\".\nQuesta vista è un placeholder.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // Corpo originale preservato per ripristino futuro (NON usato al momento)
    private var _realDashboardBody: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                summarySection
                statsGrid
                perOggiSection
                HStack(alignment: .top, spacing: 20) {
                    studioNewsSection
                        .frame(maxWidth: .infinity)
                    aiActivitySection
                        .frame(maxWidth: .infinity)
                }
                if !revocationEvents.isEmpty { revocationSection }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear { summaryService.markDashboardClosed() }
        .onReceive(taskManager.$updateCounter.dropFirst()) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .taskCreated)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .emailReceived)) { _ in
            Task { await taskManager.regenerateBaseTasks(triggeredByEmail: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workScheduleChanged)) { _ in
            Task { await ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revocationCompleted)) { notification in
            guard let info = notification.userInfo,
                  let ids = info["sinistroIDs"] as? [String],
                  let subject = info["emailSubject"] as? String else { return }
            let title = ids.count == 1 ? "Aggiornamento stato: revoca sinistro \(ids.first!)" : "Aggiornamento stato: revoca \(ids.count) sinistri"
            let event = RevocationEvent(id: UUID(), sinistroIDs: ids, title: title, subtitle: "Da mail: \(subject)", emailSubject: subject, emailId: info["emailId"] as? String)
            revocationEvents.insert(event, at: 0)
        }
        .onAppear {
            Task {
                await taskManager.regenerateTaskTitles()
                await taskManager.regenerateBaseTasks()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                requestAISummaryIfNeeded()
            }
        }
        .sheet(isPresented: $showingCreateManualTask) {
            CreateTaskView(email: nil, whatsAppChat: nil, whatsAppMessage: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $selectedEvent) { event in
            RevocationEventDetailView(event: event, sinistri: sinistri)
        }
        .sheet(isPresented: $showingCalendarDetail) {
            NavigationStack {
                DashboardCalendarDetailView()
                    .environment(\.managedObjectContext, viewContext)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { showingCalendarDetail = false }
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(CurrentUserService.shared.currentUsername ?? "Utente")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Text(Date(), style: .date)
                .font(.headline)
            Button(action: { showingCreateManualTask = true }) {
                Label("Nuova Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Button(action: { refreshTasks() }) {
                if isRefreshing {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
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
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "Buongiorno,"
        case 12..<18: return "Buon pomeriggio,"
        default: return "Buonasera,"
        }
    }
    
    // MARK: - Summary (AI o messaggio contestuale)
    
    private var summarySection: some View {
        Group {
            if summaryService.dashboardContext != .normal {
                Text(staticMessageForContext(summaryService.dashboardContext))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if aiSummaryLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Preparo il riepilogo...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else if let text = aiSummaryText {
                Text(text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("Apri il riquadro per vedere un riepilogo della giornata generato dall’assistente.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(alignment: .topLeading) {
            Label("In sintesi", systemImage: "text.quote")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(6)
                .offset(x: 12, y: -8)
        }
    }
    
    private func staticMessageForContext(_ context: DashboardSummaryService.DashboardContext) -> String {
        switch context {
        case .nonWorkingDay:
            let messages = [
                "Oggi non è un giorno lavorativo: approfitta per staccare.",
                "Niente lavoro in programma oggi. Buon riposo.",
                "Oggi lo studio è chiuso. Ci vediamo al prossimo turno.",
            ]
            return messages.randomElement() ?? messages[0]
        case .pastWorkingHours:
            let messages = [
                "Hai superato l’orario lavorativo. Per oggi puoi chiudere.",
                "Fuori orario: le task possono aspettare domani.",
                "La giornata lavorativa è finita. Buon relax.",
            ]
            return messages.randomElement() ?? messages[0]
        case .normal:
            return ""
        }
    }
    
    private func requestAISummaryIfNeeded() {
        guard summaryService.dashboardContext == .normal, !aiSummaryRequested else { return }
        aiSummaryRequested = true
        aiSummaryLoading = true
        let taskTitles = taskPerOggi.map { $0.task.title }
        let newsTitles = newsService.newsForDashboard(limit: 6).map { $0.title }
        let contextHint = "Giornata lavorativa, in orario."
        AIManager.shared.generateDailySummary(
            contextHint: contextHint,
            sinistriInGestione: sinistriInGestione,
            assegnazioniRecenti: assegnazioniRecenti,
            taskTitles: taskTitles,
            studioNewsTitles: newsTitles
        ) { result in
            aiSummaryLoading = false
            switch result {
            case .success(let text): aiSummaryText = text
            case .failure: aiSummaryText = nil
            }
        }
    }
    
    // MARK: - Stats grid
    
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            DashboardStatCard(
                title: "Sinistri in gestione",
                value: "\(sinistriInGestione)",
                icon: "folder.fill",
                color: .blue
            )
            DashboardStatCard(
                title: "Assegnazioni dall'ultimo accesso",
                value: "\(assegnazioniRecenti)",
                icon: "envelope.badge.fill",
                color: .orange
            )
        }
    }
    
    // MARK: - Per oggi
    
    private var perOggiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Per oggi", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button("Vedi calendario") {
                    showingCalendarDetail = true
                }
                .font(.caption)
            }
            if taskPerOggi.isEmpty {
                ContentUnavailableView(
                    "Nessuna task",
                    systemImage: "checkmark.circle",
                    description: Text("Non hai task programmate per oggi")
                )
                .frame(height: 120)
            } else {
                // Usa uno scope ID diverso dal solo task.id (può ripetersi su più ScheduledTask)
                ForEach(taskPerOggi.prefix(8), id: \.scheduledStartTime) { scheduled in
                    DashboardTaskRow(scheduled: scheduled, taskManager: taskManager, viewContext: viewContext)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Studio News (compatta)
    
    private var studioNewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notizie dello Studio", systemImage: "newspaper")
                .font(.headline)
            if newsService.newsForDashboard(limit: 4).isEmpty {
                Text("Nessuna notizia recente.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(newsService.newsForDashboard(limit: 4)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(item.summary)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - AI Activity (compatta)
    
    private var aiActivitySection: some View {
        AIActivityDashboard()
    }
    
    // MARK: - Revocation
    
    private var revocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Azioni automatiche IA")
                .font(.headline)
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
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func refreshTasks() {
        isRefreshing = true
        lastRefreshTime = Date()
        Task { @MainActor in
            await taskManager.validateAndCleanupExistingTasks()
            await taskManager.cleanupExpiredTasks()
            await taskManager.regenerateBaseTasks()
            await taskManager.ensureBaseTasksAreScheduled()
            ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule(userInitiated: true)
            isRefreshing = false
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let t = Date().timeIntervalSince(date)
        if t < 60 { return "adesso" }
        if t < 120 { return "un minuto fa" }
        if t < 3600 { return "\(Int(t / 60)) minuti fa" }
        if t < 7200 { return "un'ora fa" }
        if t < 86400 { return "\(Int(t / 3600)) ore fa" }
        if t < 172800 { return "ieri" }
        return "\(Int(t / 86400)) giorni fa"
    }
}

// MARK: - Stat card

private struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            HStack {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
            }
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Task row

private struct DashboardTaskRow: View {
    let scheduled: ScheduledTask
    @ObservedObject var taskManager: TaskManager
    let viewContext: NSManagedObjectContext
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: scheduled.task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(scheduled.task.status == .completed ? .green : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduled.task.title)
                    .font(.subheadline)
                    .strikethrough(scheduled.task.status == .completed)
                if let rif = scheduled.task.sinistroID {
                    Text(rif)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(timeFormatter.string(from: scheduled.scheduledStartTime))
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                taskManager.markTaskCompleted(taskID: scheduled.task.id, manually: true)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .opacity(scheduled.task.status == .completed ? 0.5 : 1)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Calendario dettaglio (vista separata con DailyScheduleView)

struct DashboardCalendarDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        DailyScheduleView()
            .environment(\.managedObjectContext, viewContext)
    }
}

// MARK: - Revocation Event

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
            Text(event.title).font(.headline)
            Text("Trigger: \(event.emailSubject)").font(.subheadline)
            Divider()
            ForEach(event.sinistroIDs, id: \.self) { id in
                if let sinistro = sinistri.first(where: { $0.riferimento == id }) {
                    SinistroEventRow(
                        sinistro: sinistro,
                        onOpenInNewWindow: { appState.openSinistro(sinistro, openInNewWindow: true); dismiss() },
                        onOpenInCurrentWindow: { appState.openSinistro(sinistro, openInNewWindow: false); dismiss() }
                    )
                } else {
                    Text(id).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 240, alignment: .topLeading)
    }
}

private struct SinistroEventRow: View {
    let sinistro: Sinistro
    let onOpenInNewWindow: () -> Void
    let onOpenInCurrentWindow: () -> Void
    
    var body: some View {
        Button(action: onOpenInNewWindow) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sinistro.riferimentoVisualizzato).fontWeight(.semibold)
                    Text(sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "Assicurato non noto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundColor(.blue).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onOpenInNewWindow() } label: { Label("Apri in nuova finestra", systemImage: "rectangle.split.2x1") }
            Button { onOpenInCurrentWindow() } label: { Label("Apri in questa finestra", systemImage: "rectangle") }
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
