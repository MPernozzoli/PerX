import SwiftUI

/// Vista per l'autocompletamento di menzioni (@) e hashtag (#)
struct MentionAutocompleteView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSelect: (AutocompleteSuggestion) -> Void
    
    @State private var selectedIndex = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(suggestion)
                }
                .onHover { hovering in
                    if hovering {
                        selectedIndex = index
                    }
                }
                
                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            selectedIndex = 0
        }
        .onChange(of: suggestions) { _, _ in
            selectedIndex = 0
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: AutocompleteSuggestion
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icona
            Image(systemName: suggestion.icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconBackgroundColor)
                .clipShape(Circle())
            
            // Contenuto
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Badge tipo
            Text(typeBadge)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.2))
                .foregroundColor(badgeColor)
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
    
    // MARK: - Computed Properties
    
    private var primaryText: String {
        switch suggestion.type {
        case .user(_, let name):
            return name
        case .sinistro(let riferimento, _):
            return riferimento
        case .assicurato(_, let nome):
            return nome
        case .hashtag(let tag, _):
            return "#\(tag)"
        }
    }
    
    private var secondaryText: String? {
        switch suggestion.type {
        case .user(let email, _):
            return email
        case .sinistro(_, let assicurato):
            return assicurato
        case .assicurato(let riferimento, _):
            return "Sinistro \(riferimento)"
        case .hashtag(_, let description):
            return description
        }
    }
    
    private var typeBadge: String {
        switch suggestion.type {
        case .user:
            return "Utente"
        case .sinistro:
            return "Sinistro"
        case .assicurato:
            return "Assicurato"
        case .hashtag:
            return "Tag"
        }
    }
    
    private var iconColor: Color {
        switch suggestion.type {
        case .user:
            return .blue
        case .sinistro:
            return .orange
        case .assicurato:
            return .green
        case .hashtag:
            return .purple
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }
    
    private var badgeColor: Color {
        iconColor
    }
}

// MARK: - Hashtag Filter View

/// Vista per mostrare i risultati di un hashtag (es. #chiusure)
struct HashtagResultsView: View {
    let hashtag: ChatHashtag
    let onSelectSinistro: (Sinistro) -> Void
    let onDismiss: () -> Void
    
    @State private var sinistri: [Sinistro] = []
    @State private var isLoading = true
    @State private var filterType: FilterType = .tutti
    
    enum FilterType: String, CaseIterable {
        case tutti = "Tutti"
        case studio = "Studio"
        case utente = "Miei"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("#\(hashtag.tag)")
                    .font(.headline)
                    .foregroundColor(.purple)
                
                Spacer()
                
                Picker("Filtro", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Lista sinistri
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sinistri.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Nessun sinistro trovato")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSinistri, id: \.objectID) { sinistro in
                    SinistroHashtagRow(sinistro: sinistro)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectSinistro(sinistro)
                        }
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadSinistri()
        }
        .onChange(of: filterType) { _, _ in
            // Il filtro è applicato via computed property
        }
    }
    
    private var filteredSinistri: [Sinistro] {
        switch filterType {
        case .tutti:
            return sinistri
        case .studio:
            return sinistri // Tutti sono dello studio
        case .utente:
            let currentEmail = GoogleAuthService.shared.userEmail?.lowercased()
            return sinistri.filter { $0.assignedToUserEmail?.lowercased() == currentEmail }
        }
    }
    
    private func loadSinistri() {
        isLoading = true
        
        Task {
            let context = PersistenceController.shared.container.viewContext
            let results = await context.perform {
                let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
                
                // Applica filtro in base all'hashtag
                switch hashtag.tag.lowercased() {
                case "chiusure":
                    request.predicate = NSPredicate(format: "stato == %@ OR stato == %@", "Chiuso", "chiuso")
                case "aperti":
                    request.predicate = NSPredicate(format: "stato == %@ OR stato == %@", "Aperto", "aperto")
                case "assegnati":
                    if let email = GoogleAuthService.shared.userEmail?.lowercased() {
                        request.predicate = NSPredicate(format: "assignedToUserEmail == %@", email)
                    }
                case "urgenti":
                    // Sinistri con scadenza imminente (prossimi 7 giorni)
                    let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    request.predicate = NSPredicate(format: "dataChiusura <= %@ AND dataChiusura >= %@", nextWeek as NSDate, Date() as NSDate)
                default:
                    // Tutti i sinistri
                    break
                }
                
                request.sortDescriptors = [NSSortDescriptor(key: "dataAssegnazione", ascending: false)]
                request.fetchLimit = 50
                
                return (try? context.fetch(request)) ?? []
            }
            
            await MainActor.run {
                sinistri = results
                isLoading = false
            }
        }
    }
}

// MARK: - Sinistro Hashtag Row

struct SinistroHashtagRow: View {
    let sinistro: Sinistro
    
    var body: some View {
        HStack(spacing: 12) {
            // Stato badge
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sinistro.riferimento ?? "N/D")
                    .font(.system(size: 13, weight: .medium))
                
                Text(sinistro.nomeAssicurato ?? "Assicurato non disponibile")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let compagnia = sinistro.nomeCompagnia {
                Text(compagnia)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let data = sinistro.dataAssegnazione {
                Text(data.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch sinistro.stato?.lowercased() {
        case "aperto":
            return .green
        case "chiuso":
            return .gray
        case "sospeso":
            return .orange
        default:
            return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    MentionAutocompleteView(
        suggestions: [
            AutocompleteSuggestion(
                id: "user_1",
                type: .user(email: "m.pernozzoli@actsrl.it", name: "Marco Pernozzoli"),
                displayText: "Marco Pernozzoli",
                insertText: "@m.pernozzoli@actsrl.it",
                icon: "person.circle.fill"
            ),
            AutocompleteSuggestion(
                id: "sin_1",
                type: .sinistro(riferimento: "24/12345", assicurato: "Mario Rossi"),
                displayText: "24/12345 - Mario Rossi",
                insertText: "@24/12345",
                icon: "doc.text.fill"
            ),
            AutocompleteSuggestion(
                id: "hash_1",
                type: .hashtag(tag: "chiusure", description: "Sinistri chiusi"),
                displayText: "#chiusure - Sinistri chiusi",
                insertText: "#chiusure",
                icon: "number"
            )
        ],
        onSelect: { _ in }
    )
    .frame(width: 350)
}
