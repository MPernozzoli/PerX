import Foundation
import CoreData

/// Servizio per parsing e autocompletamento di menzioni (@) e hashtag (#)
@MainActor
final class MentionParserService: ObservableObject {
    static let shared = MentionParserService()
    
    // MARK: - Published Properties
    
    @Published var suggestions: [AutocompleteSuggestion] = []
    @Published var isSearching = false
    
    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    
    // Pattern regex per menzioni e hashtag
    // - Mention: @email / @24/12345 / @assicurato:24/12345 (senza [])
    // - Hashtag: #sinistri / #chiusure (il filtro non è visibile all'utente, viene gestito a parte)
    private let mentionPattern = #"@([A-Za-z0-9._%+\-@/:\-]+)"#
    private let hashtagPattern = #"#(\w+)"#
    
    // MARK: - Init
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Parsing
    
    /// Estrae tutte le menzioni da un testo
    func parseMentions(from text: String) -> [ChatMention] {
        var mentions: [ChatMention] = []
        
        guard let regex = try? NSRegularExpression(pattern: mentionPattern, options: []) else {
            return mentions
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let matchedText = String(text[matchRange]) // include @
            
            // Cattura solo il valore (gruppo 1)
            guard let valueRange = Range(match.range(at: 1), in: text) else { continue }
            let valueString = String(text[valueRange])
            
            let mention = categorizeMention(value: valueString, displayText: matchedText, range: matchRange)
            mentions.append(mention)
        }
        
        return mentions
    }
    
    /// Estrae tutti gli hashtag da un testo
    func parseHashtags(from text: String, overrides: [String: String] = [:]) -> [ChatHashtag] {
        var hashtags: [ChatHashtag] = []
        
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) else {
            return hashtags
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            
            var tag = ""
            if let tagRange = Range(match.range(at: 1), in: text) {
                tag = String(text[tagRange])
            }
            
            let normalized = tag.lowercased()
            let filter = overrides[normalized]
            
            let hashtag = ChatHashtag(tag: normalized, filter: filter, range: matchRange)
            hashtags.append(hashtag)
        }
        
        return hashtags
    }
    
    /// Categorizza una menzione in base al suo valore
    private func categorizeMention(value: String, displayText: String, range: Range<String.Index>) -> ChatMention {
        // Controllo se è un'email (utente)
        if value.contains("@") && value.contains(".") {
            return ChatMention(type: .user, value: value, displayText: displayText, range: range)
        }
        
        // Controllo se è formato "assicurato:riferimento"
        if value.lowercased().hasPrefix("assicurato:") {
            let riferimento = String(value.dropFirst("assicurato:".count))
            return ChatMention(type: .assicurato, value: riferimento, displayText: displayText, range: range)
        }
        
        // Controllo se è un riferimento sinistro (formato XX/XXXXX o simile)
        if value.contains("/") || value.allSatisfy({ $0.isNumber || $0 == "/" }) {
            return ChatMention(type: .riferimento, value: value, displayText: displayText, range: range)
        }
        
        // Default: tratta come riferimento
        return ChatMention(type: .riferimento, value: value, displayText: displayText, range: range)
    }
    
    // MARK: - Autocomplete
    
    /// Rileva se l'utente sta digitando una menzione o hashtag
    func detectAutocompleteContext(in text: String, cursorPosition: Int) -> AutocompleteContext? {
        guard cursorPosition > 0, cursorPosition <= text.count else { return nil }
        
        let index = text.index(text.startIndex, offsetBy: cursorPosition)
        let textBeforeCursor = String(text[..<index])
        
        // Cerca l'ultimo @ o # prima del cursore
        if let lastAt = textBeforeCursor.lastIndex(of: "@") {
            let query = String(textBeforeCursor[textBeforeCursor.index(after: lastAt)...])
            // Verifica che non ci siano spazi (menzione in corso)
            if !query.contains(" ") {
                return AutocompleteContext(type: .mention, query: query, startIndex: lastAt)
            }
        }
        
        if let lastHash = textBeforeCursor.lastIndex(of: "#") {
            let query = String(textBeforeCursor[textBeforeCursor.index(after: lastHash)...])
            if !query.contains(" ") {
                return AutocompleteContext(type: .hashtag, query: query, startIndex: lastHash)
            }
        }
        
        return nil
    }
    
    /// Genera suggerimenti per autocompletamento
    func generateSuggestions(for context: AutocompleteContext) async {
        isSearching = true
        defer { isSearching = false }
        
        switch context.type {
        case .mention:
            suggestions = await generateMentionSuggestions(query: context.query)
        case .hashtag:
            suggestions = generateHashtagSuggestions(query: context.query)
        }
    }
    
    /// Genera suggerimenti per menzioni
    private func generateMentionSuggestions(query: String) async -> [AutocompleteSuggestion] {
        var results: [AutocompleteSuggestion] = []
        let lowercaseQuery = query.lowercased()
        
        // 1. Suggerisci utenti (da CloudKit directory: solo chi ha sync iCloud attiva)
        let currentEmail = GoogleAuthService.shared.userEmail?.lowercased()
        let users = CloudKitUserDirectoryService.shared.users
            .filter { $0.email.lowercased() != currentEmail }
        
        for user in users {
            if user.email.contains(lowercaseQuery) ||
               user.displayName.lowercased().contains(lowercaseQuery) {
                results.append(AutocompleteSuggestion(
                    id: "user_\(user.email)",
                    type: .user(email: user.email, name: user.displayName),
                    displayText: "\(user.displayName) (\(user.email))",
                    insertText: "@\(user.email)",
                    icon: "person.circle.fill"
                ))
            }
        }
        
        // 2. Suggerisci sinistri
        let sinistri = await searchSinistri(query: lowercaseQuery)
        for sinistro in sinistri.prefix(10) {
            let riferimento = sinistro.riferimento ?? ""
            let assicurato = sinistro.nomeAssicurato
            
            // Suggerimento riferimento
            results.append(AutocompleteSuggestion(
                id: "sin_\(riferimento)",
                type: .sinistro(riferimento: riferimento, assicurato: assicurato),
                displayText: "\(riferimento) - \(assicurato ?? "N/D")",
                insertText: "@\(riferimento)",
                icon: "doc.text.fill"
            ))
            
            // Suggerimento assicurato (se presente)
            if let nome = assicurato, !nome.isEmpty {
                results.append(AutocompleteSuggestion(
                    id: "ass_\(riferimento)",
                    type: .assicurato(riferimento: riferimento, nome: nome),
                    displayText: "Assicurato: \(nome) (\(riferimento))",
                    insertText: "@assicurato:\(riferimento)",
                    icon: "person.fill"
                ))
            }
        }
        
        return results
    }
    
    /// Genera suggerimenti per hashtag
    private func generateHashtagSuggestions(query: String) -> [AutocompleteSuggestion] {
        var results: [AutocompleteSuggestion] = []
        let lowercaseQuery = query.lowercased()
        
        // Hashtag predefiniti
        for (tag, description) in ChatHashtag.predefinedTags {
            if tag.contains(lowercaseQuery) || lowercaseQuery.isEmpty {
                results.append(AutocompleteSuggestion(
                    id: "hash_\(tag)",
                    type: .hashtag(tag: tag, description: description),
                    displayText: "#\(tag) - \(description)",
                    insertText: "#\(tag)",
                    icon: "number"
                ))
            }
        }
        
        return results.sorted { $0.displayText < $1.displayText }
    }
    
    // MARK: - Data Fetching
    
    /// Cerca sinistri per riferimento o nome assicurato
    private func searchSinistri(query: String) async -> [Sinistro] {
        await context.perform { [context] in
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            
            if !query.isEmpty {
                request.predicate = NSPredicate(
                    format: "riferimento CONTAINS[cd] %@ OR nomeAssicurato CONTAINS[cd] %@",
                    query, query
                )
            }
            
            request.fetchLimit = 20
            request.sortDescriptors = [NSSortDescriptor(key: "dataAssegnazione", ascending: false)]
            
            return (try? context.fetch(request)) ?? []
        }
    }
    
    // MARK: - Rendering
    
    /// Converte il contenuto in AttributedString con menzioni e hashtag evidenziati
    func renderContent(_ content: String, mentions: [ChatMention], hashtags: [ChatHashtag]) -> AttributedString {
        var attributed = AttributedString(content)
        
        // Evidenzia menzioni
        for mention in mentions {
            if let range = content.range(of: mention.displayText) {
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .accentColor
                    attributed[attrRange].font = .body.bold()
                }
            }
        }
        
        // Evidenzia hashtag
        for hashtag in hashtags {
            let hashtagText = "#\(hashtag.tag)"
            if let range = content.range(of: hashtagText) {
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .purple
                    attributed[attrRange].font = .body.bold()
                }
            }
        }
        
        return attributed
    }
}

// MARK: - Supporting Types

struct AutocompleteContext {
    enum ContextType {
        case mention
        case hashtag
    }
    
    let type: ContextType
    let query: String
    let startIndex: String.Index
}
