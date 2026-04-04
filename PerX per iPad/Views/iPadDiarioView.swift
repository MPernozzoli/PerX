//
//  iPadDiarioView.swift
//  PerX per iPad
//
//  Vista diario sinistro stile chat ottimizzata per touch.
//

import SwiftUI

struct iPadDiarioView: View {
    let riferimento: String
    @Binding var entries: [DiarioEntryDTO]
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var newNoteText = ""
    @State private var isSending = false
    @State private var expandedEntries: Set<String> = []
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nessun messaggio",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Le comunicazioni e note appariranno qui")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(groupedEntriesByDate, id: \.date) { group in
                                // Date separator
                                dateSeparator(group.date)
                                
                                ForEach(group.entries) { entry in
                                    DiarioBubble(
                                        entry: entry,
                                        isExpanded: expandedEntries.contains(entry.id),
                                        onToggleExpand: {
                                            toggleExpand(entry.id)
                                        }
                                    )
                                    .id(entry.id)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: entries.count) { _ in
                        if let lastId = entries.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Input bar
            inputBar
        }
    }
    
    // MARK: - Date Separator
    
    @ViewBuilder
    private func dateSeparator(_ date: Date) -> some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
            
            Text(formatDateHeader(date))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Input Bar
    
    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Scrivi una nota...", text: $newNoteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...5)
                .focused($isInputFocused)
            
            Button {
                Task { await sendNote() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .accentColor : .gray)
            }
            .disabled(!canSend || isSending)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private var canSend: Bool {
        !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Grouped Entries
    
    private struct DayGroup {
        let date: Date
        let entries: [DiarioEntryDTO]
    }
    
    private var groupedEntriesByDate: [DayGroup] {
        let calendar = Calendar.current
        var groups: [Date: [DiarioEntryDTO]] = [:]
        
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let day = calendar.startOfDay(for: entry.timestamp)
            groups[day, default: []].append(entry)
        }
        
        return groups.map { DayGroup(date: $0.key, entries: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    // MARK: - Actions
    
    private func toggleExpand(_ id: String) {
        if expandedEntries.contains(id) {
            expandedEntries.remove(id)
        } else {
            expandedEntries.insert(id)
        }
    }
    
    private func sendNote() async {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isSending = true
        newNoteText = ""
        isInputFocused = false
        
        if let syncService = session.cloudKitSyncService {
            do {
                let entry = try await syncService.addDiarioEntry(riferimento: riferimento, testo: text, tipo: "nota")
                entries.append(entry)
            } catch {
                let fallback = DiarioEntryDTO(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    tipo: "nota",
                    titolo: "Nota",
                    riassunto: text,
                    contenutoCompleto: text,
                    createdBy: session.currentUserEmail
                )
                entries.append(fallback)
                print("[iPadDiarioView] sync nota fallita: \(error)")
            }
        }

        isSending = false
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Oggi"
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE d MMMM"
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: date).capitalized
        }
    }
}

// Estensione per init locale
extension DiarioEntryDTO {
    init(id: String, timestamp: Date, tipo: String, titolo: String?, riassunto: String, contenutoCompleto: String?, createdBy: String?) {
        self.id = id
        self.timestamp = timestamp
        self.tipo = tipo
        self.titolo = titolo
        self.riassunto = riassunto
        self.contenutoCompleto = contenutoCompleto
        self.createdBy = createdBy
    }
}

// MARK: - Diario Bubble

struct DiarioBubble: View {
    let entry: DiarioEntryDTO
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    private var isUserNote: Bool {
        entry.tipo.lowercased() == "nota" || entry.tipo.lowercased() == "nota utente"
    }
    
    private var bubbleColor: Color {
        switch entry.tipo.lowercased() {
        case "email":
            return Color.blue.opacity(0.1)
        case "whatsapp":
            return Color.green.opacity(0.1)
        case "nota", "nota utente":
            return Color.purple.opacity(0.15)
        case "sistema", "cambio stato":
            return Color.gray.opacity(0.15)
        default:
            return Color.gray.opacity(0.1)
        }
    }
    
    private var iconName: String {
        switch entry.tipo.lowercased() {
        case "email": return "envelope.fill"
        case "whatsapp": return "message.fill"
        case "nota", "nota utente": return "note.text"
        case "cambio stato": return "arrow.triangle.2.circlepath"
        default: return "doc.text"
        }
    }
    
    private var iconColor: Color {
        switch entry.tipo.lowercased() {
        case "email": return .blue
        case "whatsapp": return .green
        case "nota", "nota utente": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let titolo = entry.titolo, !titolo.isEmpty {
                            Text(titolo)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                        }
                        
                        HStack(spacing: 4) {
                            Text(entry.tipo.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let createdBy = entry.createdBy {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(createdBy.components(separatedBy: "@").first ?? createdBy)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(formatTime(entry.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Body
                Text(isExpanded ? (entry.contenutoCompleto ?? entry.riassunto) : entry.riassunto)
                    .font(.subheadline)
                    .lineLimit(isExpanded ? nil : 3)
                
                // Expand button
                if (entry.contenutoCompleto ?? "").count > entry.riassunto.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onToggleExpand()
                        }
                    } label: {
                        Text(isExpanded ? "Mostra meno" : "Mostra tutto")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(bubbleColor)
            .cornerRadius(16)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
}
