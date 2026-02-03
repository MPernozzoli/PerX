import SwiftUI
import CoreData

struct AIActivityDashboard: View {
    @StateObject private var aiManager = AIManager.shared
    @State private var expandedGroups: Set<String> = []

    // Helper visibile a tutto il file
    fileprivate func extractSinistroID(from task: AITask) -> String? {
        if let ref = task.context?["sinistroID"]?.value as? String, !ref.isEmpty {
            return ref
        }
        if let ref = task.parameters["sinistroID"]?.value as? String, !ref.isEmpty {
            return ref
        }
        return nil
    }
    
    /// Converte il sinistroID nel formato visualizzato con sigla compagnia se abilitato
    fileprivate func riferimentoVisualizzato(for sinistroID: String) -> String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        guard showSigla else { return sinistroID }
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        request.fetchLimit = 1
        
        if let sinistro = try? context.fetch(request).first {
            return sinistro.riferimentoVisualizzato
        }
        
        return sinistroID
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Cronologia Eventi Automatici")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Lista task completate (ultimi 3 giorni) raggruppate per sinistro+tipo
            ScrollView {
                VStack(spacing: 8) {
                    let completedTasks = aiManager.getCompletedTasks(lastDays: 3)
                    let grouped = groupTasks(completedTasks)
                    
                    if grouped.isEmpty {
                        Text("Nessuna attività AI negli ultimi 3 giorni")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(grouped, id: \.id) { group in
                            AIActivityGroupedView(title: group.title, items: group.items)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private struct GroupedTasks {
        let id: String
        let title: String
        let items: [AITaskInfo]
    }
    
    private func groupTasks(_ tasks: [AITaskInfo]) -> [GroupedTasks] {
        let dict = Dictionary(grouping: tasks) { info -> String in
            let type = info.task.type.rawValue
            let sin = extractSinistroID(from: info.task) ?? "generico"
            return "\(sin)|\(type)"
        }
        return dict.map { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let sinistroID = parts.first ?? "generico"
            let typeRaw = parts.count > 1 ? parts[1] : ""
            // Usa riferimento visualizzato con sigla compagnia
            let sinistroDisplay = sinistroID == "generico" ? sinistroID : riferimentoVisualizzato(for: sinistroID)
            let title = "\(descriptionForType(typeRaw)) • \(sinistroDisplay)"
            return GroupedTasks(id: key, title: title, items: value)
        }
        .sorted { lhs, rhs in
            let lDate = lhs.items.first?.completedAt ?? .distantPast
            let rDate = rhs.items.first?.completedAt ?? .distantPast
            return lDate > rDate
        }
    }
    
    private func descriptionForType(_ raw: String) -> String {
        switch AITaskType(rawValue: raw) {
        case .emailSummary: return "Riassunto email"
        case .documentAnalysis: return "Analisi documento"
        case .textGeneration: return "Generazione testo"
        case .imageAnalysis: return "Analisi immagine"
        case .textAnalysis: return "Analisi testo"
        case .documentExtraction: return "Estrazione dati"
        case .guardrailing: return "Guardrailing"
        case .chat: return "Chat"
        case .none: return "Attività AI"
        }
    }
}

// MARK: - Raggruppamento card
struct AIActivityGroupedView: View {
    let title: String
    let items: [AITaskInfo]
    @State private var showPopover = false
    
    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline).bold()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(items.count) azioni")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items.sorted(by: { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })) { item in
                        AIActivityRow(taskInfo: item, grouped: true)
                            .padding(8)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                .padding()
                .frame(minWidth: 380, maxWidth: 440)
            }
        }
    }
}

struct AIActivityRow: View {
    let taskInfo: AITaskInfo
    var grouped: Bool = false
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: taskInfo.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(taskInfo.status == .completed ? .green : .yellow)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                Text(descriptionForTask(taskInfo.task))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let sinistroID = extractSinistroID(from: taskInfo.task) {
                        Text(riferimentoVisualizzato(for: sinistroID))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if let result = taskInfo.result {
                        ProviderBadge(provider: result.provider)
                    }
                }
                
                if let completedAt = taskInfo.completedAt {
                    Text(timestampLabel(completedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                }
                
                if let result = taskInfo.result {
                    let meta = result.metadata
                    DisclosureGroup("Dettagli") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let input = inputPreview(taskInfo.task) {
                                Text("Input:")
                                    .font(.caption).bold()
                                Text(input)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(5)
                            }
                            if let output = outputPreview(result) {
                                Text("Output:")
                                    .font(.caption).bold()
                                Text(output)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(6)
                            }
                            if !meta.isEmpty {
                                Text("Metadata:")
                                    .font(.caption).bold()
                                Text(meta.map { "\($0.key): \($0.value.value)" }.joined(separator: "\n"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, grouped ? 4 : 8)
        .padding(.horizontal, grouped ? 0 : 12)
        .background(grouped ? Color.clear : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func descriptionForTask(_ task: AITask) -> String {
        let base: String
        switch task.type {
        case .emailSummary: base = "Riassunto email"
        case .documentAnalysis: base = "Analisi documento"
        case .textGeneration: base = "Generazione testo"
        case .imageAnalysis: base = "Analisi immagine"
        case .textAnalysis: base = "Analisi testo"
        case .documentExtraction: base = "Estrazione dati"
        case .guardrailing: base = "Guardrailing"
        case .chat: base = "Chat"
        }
        if let sinistroID = extractSinistroID(from: task) {
            return "\(base) • \(riferimentoVisualizzato(for: sinistroID))"
        }
        return base
    }
    
    private func extractSinistroID(from task: AITask) -> String? {
        if let ref = task.context?["sinistroID"]?.value as? String, !ref.isEmpty {
            return ref
        }
        if let ref = task.parameters["sinistroID"]?.value as? String, !ref.isEmpty {
            return ref
        }
        return nil
    }
    
    /// Converte il sinistroID nel formato visualizzato con sigla compagnia se abilitato
    private func riferimentoVisualizzato(for sinistroID: String) -> String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        guard showSigla else { return sinistroID }
        
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        request.fetchLimit = 1
        
        if let sinistro = try? context.fetch(request).first {
            return sinistro.riferimentoVisualizzato
        }
        
        return sinistroID
    }
    
    private func inputPreview(_ task: AITask) -> String? {
        let candidates = ["text", "body", "subject", "prompt", "content"]
        for key in candidates {
            if let value = task.parameters[key]?.value as? String, !value.isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let ctx = task.context,
           let value = ctx["text"]?.value as? String,
           !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func outputPreview(_ result: AIResult) -> String? {
        if let text = result.result as? String {
            return text
        }
        if let dict = result.result as? [String: AnyCodable] {
            // Evita type-check costoso: costruisci manualmente
            return dict
                .map { key, val in "\(key): \(val.value)" }
                .joined(separator: "\n")
        }
        if let arr = result.result as? [Any] {
            return arr.map { "\($0)" }.joined(separator: "\n")
        }
        return nil
    }
    
    private func timestampLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Ieri, \(timeFormatter.string(from: date))"
        }
        return dateFormatter.string(from: date)
    }
}

struct ProviderBadge: View {
    let provider: AIModelProvider
    
    var body: some View {
        Text(providerName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(providerColor.opacity(0.2))
            .foregroundColor(providerColor)
            .cornerRadius(4)
    }
    
    private var providerName: String {
        switch provider {
        case .localMultimodal:
            return "Local MM"
        case .localText:
            return "Local"
        case .appleIntelligence:
            return "Apple AI"
        case .cloudOpenAI:
            return "OpenAI"
        }
    }
    
    private var providerColor: Color {
        switch provider {
        case .localMultimodal, .localText:
            return .blue
        case .appleIntelligence:
            return .purple
        case .cloudOpenAI:
            return .green
        }
    }
}

