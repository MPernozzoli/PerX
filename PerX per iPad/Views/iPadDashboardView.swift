//
//  iPadDashboardView.swift
//  PerX per iPad
//
//  Dashboard principale con statistiche, task del giorno e attività recenti.
//

import SwiftUI

struct iPadDashboardView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var isRefreshing = false
    @State private var stats: DashboardStats = .empty
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header con saluto
                headerSection
                
                // Statistiche principali
                statsGrid
                
                // Due colonne: Task e Attività
                HStack(alignment: .top, spacing: 20) {
                    // Task del giorno
                    taskSection
                        .frame(maxWidth: .infinity)
                    
                    // Attività recenti
                    activitySection
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .task {
            await loadStats()
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text(session.currentUserName ?? "Utente")
                    .font(.largeTitle.bold())
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(Date(), style: .date)
                    .font(.headline)
                
                if let lastSync = session.syncService?.lastSyncAt {
                    Text("Sync: \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "Buongiorno,"
        case 12..<18: return "Buon pomeriggio,"
        default: return "Buonasera,"
        }
    }
    
    // MARK: - Stats Grid
    
    @ViewBuilder
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Sinistri Aperti",
                value: "\(stats.sinistriAperti)",
                icon: "folder.fill",
                color: .blue
            )
            
            StatCard(
                title: "Da Lavorare Oggi",
                value: "\(stats.daLavorareOggi)",
                icon: "clock.fill",
                color: .orange
            )
            
            StatCard(
                title: "Comunicazioni",
                value: "\(stats.comunicazioniNonLette)",
                icon: "envelope.badge.fill",
                color: .green
            )
            
            StatCard(
                title: "In Scadenza",
                value: "\(stats.inScadenza)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }
    
    // MARK: - Task Section
    
    @ViewBuilder
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Task del giorno", systemImage: "checklist")
                    .font(.headline)
                
                Spacer()
                
                Button("Vedi tutte") {
                    // Navigate to programmazione
                }
                .font(.caption)
            }
            
            if stats.taskOggi.isEmpty {
                ContentUnavailableView(
                    "Nessuna task",
                    systemImage: "checkmark.circle",
                    description: Text("Non hai task programmate per oggi")
                )
                .frame(height: 200)
            } else {
                ForEach(stats.taskOggi.prefix(5)) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Activity Section
    
    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Attività recenti", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                
                Spacer()
            }
            
            if stats.attivitaRecenti.isEmpty {
                ContentUnavailableView(
                    "Nessuna attività",
                    systemImage: "tray",
                    description: Text("Le attività recenti appariranno qui")
                )
                .frame(height: 200)
            } else {
                ForEach(stats.attivitaRecenti.prefix(8)) { activity in
                    ActivityRow(activity: activity)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Actions
    
    private func refresh() async {
        isRefreshing = true
        await session.syncService?.syncNow()
        await loadStats()
        isRefreshing = false
    }
    
    private func loadStats() async {
        // Carica statistiche da CloudKit sync service
        let sinistri = session.syncService?.sinistri ?? []
        
        stats = DashboardStats(
            sinistriAperti: sinistri.filter { $0.isOpen }.count,
            daLavorareOggi: 0, // TODO: implementare con task manager
            comunicazioniNonLette: 0, // TODO: implementare
            inScadenza: 0, // TODO: implementare
            taskOggi: [], // TODO: implementare
            attivitaRecenti: [] // TODO: implementare
        )
    }
}

// MARK: - Stats Models

struct DashboardStats {
    let sinistriAperti: Int
    let daLavorareOggi: Int
    let comunicazioniNonLette: Int
    let inScadenza: Int
    let taskOggi: [DashboardTask]
    let attivitaRecenti: [DashboardActivity]
    
    static let empty = DashboardStats(
        sinistriAperti: 0,
        daLavorareOggi: 0,
        comunicazioniNonLette: 0,
        inScadenza: 0,
        taskOggi: [],
        attivitaRecenti: []
    )
}

struct DashboardTask: Identifiable {
    let id: String
    let title: String
    let sinistroRif: String?
    let deadline: Date?
    let isCompleted: Bool
}

struct DashboardActivity: Identifiable {
    let id: String
    let type: ActivityType
    let title: String
    let subtitle: String
    let timestamp: Date
    
    enum ActivityType {
        case email, whatsapp, nota, statoChanged
        
        var icon: String {
            switch self {
            case .email: return "envelope.fill"
            case .whatsapp: return "message.fill"
            case .nota: return "note.text"
            case .statoChanged: return "arrow.triangle.2.circlepath"
            }
        }
        
        var color: Color {
            switch self {
            case .email: return .blue
            case .whatsapp: return .green
            case .nota: return .purple
            case .statoChanged: return .orange
            }
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
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
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                
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
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct TaskRow: View {
    let task: DashboardTask
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? .green : .gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .strikethrough(task.isCompleted)
                
                if let rif = task.sinistroRif {
                    Text(rif)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let deadline = task.deadline {
                Text(deadline, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ActivityRow: View {
    let activity: DashboardActivity
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.icon)
                .foregroundColor(activity.type.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(activity.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(activity.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}
