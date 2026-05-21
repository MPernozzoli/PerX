import Foundation
import CoreData
import SwiftUI
import Combine

// MARK: - Message Tag Category

/// Categorie di tag per i messaggi WhatsApp
enum WhatsAppMessageTag: String, CaseIterable, Codable, Identifiable {
    case sopralluogo = "sopralluogo"
    case documentazione = "documentazione"
    case informazione = "informazione"
    case sollecito = "sollecito"
    case conferma = "conferma"
    case importante = "importante"
    case daRispondere = "da_rispondere"
    case archiviato = "archiviato"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sopralluogo: return "Sopralluogo"
        case .documentazione: return "Documentazione"
        case .informazione: return "Informazione"
        case .sollecito: return "Sollecito"
        case .conferma: return "Conferma"
        case .importante: return "Importante"
        case .daRispondere: return "Da Rispondere"
        case .archiviato: return "Archiviato"
        }
    }
    
    var iconName: String {
        switch self {
        case .sopralluogo: return "car.fill"
        case .documentazione: return "doc.fill"
        case .informazione: return "info.circle.fill"
        case .sollecito: return "exclamationmark.circle.fill"
        case .conferma: return "checkmark.circle.fill"
        case .importante: return "star.fill"
        case .daRispondere: return "arrow.turn.up.left.fill"
        case .archiviato: return "archivebox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .sopralluogo: return .blue
        case .documentazione: return .teal
        case .informazione: return .indigo
        case .sollecito: return .orange
        case .conferma: return .green
        case .importante: return .red
        case .daRispondere: return .purple
        case .archiviato: return .gray
        }
    }
}

// MARK: - Message Tag Data

/// Dati del tag applicato a un messaggio
struct WhatsAppMessageTagData: Identifiable, Codable, Equatable {
    let messageId: String
    var tags: Set<WhatsAppMessageTag>
    var sinistroRiferimento: String?
    var note: String?
    var appliedDate: Date
    var isManual: Bool
    
    var id: String { messageId }
    
    init(
        messageId: String,
        tags: Set<WhatsAppMessageTag> = [],
        sinistroRiferimento: String? = nil,
        note: String? = nil,
        appliedDate: Date = Date(),
        isManual: Bool = true
    ) {
        self.messageId = messageId
        self.tags = tags
        self.sinistroRiferimento = sinistroRiferimento
        self.note = note
        self.appliedDate = appliedDate
        self.isManual = isManual
    }
}

// MARK: - WhatsApp Message Tag Manager

/// Manager per la gestione dei tag dei messaggi WhatsApp
@MainActor
class WhatsAppMessageTagManager: ObservableObject {
    
    static let shared = WhatsAppMessageTagManager()
    
    // MARK: - Published State
    
    /// Cache dei tag per messaggio (messageId -> TagData)
    @Published var messageTags: [String: WhatsAppMessageTagData] = [:]
    
    /// Ultimo errore
    @Published var lastError: String?
    
    // MARK: - Private
    
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var loadedScope: String?
    
    // MARK: - Initialization
    
    private init() {
        loadAllTags()
        setupAutosave()
    }
    
    // MARK: - Tag Application
    
    /// Aggiungi un tag a un messaggio
    func addTag(_ tag: WhatsAppMessageTag, toMessageId messageId: String, sinistroRif: String? = nil) {
        ensureTagsLoadedForCurrentScope()
        if var existing = messageTags[messageId] {
            existing.tags.insert(tag)
            if let rif = sinistroRif {
                existing.sinistroRiferimento = rif
            }
            messageTags[messageId] = existing
        } else {
            let newData = WhatsAppMessageTagData(
                messageId: messageId,
                tags: [tag],
                sinistroRiferimento: sinistroRif
            )
            messageTags[messageId] = newData
        }
        
        saveTags()
        print("[WhatsAppTagManager] ✅ Tag '\(tag.displayName)' aggiunto a messaggio \(messageId)")
    }
    
    /// Rimuovi un tag da un messaggio
    func removeTag(_ tag: WhatsAppMessageTag, fromMessageId messageId: String) {
        ensureTagsLoadedForCurrentScope()
        guard var existing = messageTags[messageId] else { return }
        
        existing.tags.remove(tag)
        
        if existing.tags.isEmpty && existing.note == nil {
            messageTags.removeValue(forKey: messageId)
        } else {
            messageTags[messageId] = existing
        }
        
        saveTags()
        print("[WhatsAppTagManager] 🗑️ Tag '\(tag.displayName)' rimosso da messaggio \(messageId)")
    }
    
    /// Imposta tutti i tag per un messaggio
    func setTags(_ tags: Set<WhatsAppMessageTag>, forMessageId messageId: String, sinistroRif: String? = nil, note: String? = nil) {
        ensureTagsLoadedForCurrentScope()
        if tags.isEmpty && note == nil {
            messageTags.removeValue(forKey: messageId)
        } else {
            let tagData = WhatsAppMessageTagData(
                messageId: messageId,
                tags: tags,
                sinistroRiferimento: sinistroRif,
                note: note
            )
            messageTags[messageId] = tagData
        }
        
        saveTags()
    }
    
    /// Associa un messaggio a un sinistro
    func associateMessageToSinistro(messageId: String, sinistroRif: String) {
        ensureTagsLoadedForCurrentScope()
        if var existing = messageTags[messageId] {
            existing.sinistroRiferimento = sinistroRif
            messageTags[messageId] = existing
        } else {
            let newData = WhatsAppMessageTagData(
                messageId: messageId,
                sinistroRiferimento: sinistroRif
            )
            messageTags[messageId] = newData
        }
        
        saveTags()
        print("[WhatsAppTagManager] 🔗 Messaggio \(messageId) associato a sinistro \(sinistroRif)")
    }
    
    /// Rimuovi associazione sinistro
    func disassociateMessageFromSinistro(messageId: String) {
        ensureTagsLoadedForCurrentScope()
        guard var existing = messageTags[messageId] else { return }
        
        existing.sinistroRiferimento = nil
        
        if existing.tags.isEmpty && existing.note == nil {
            messageTags.removeValue(forKey: messageId)
        } else {
            messageTags[messageId] = existing
        }
        
        saveTags()
    }
    
    // MARK: - Tag Retrieval
    
    /// Ottieni i tag di un messaggio
    func getTags(forMessageId messageId: String) -> Set<WhatsAppMessageTag> {
        ensureTagsLoadedForCurrentScope()
        return messageTags[messageId]?.tags ?? []
    }
    
    /// Ottieni tutti i dati del tag di un messaggio
    func getTagData(forMessageId messageId: String) -> WhatsAppMessageTagData? {
        ensureTagsLoadedForCurrentScope()
        return messageTags[messageId]
    }
    
    /// Verifica se un messaggio ha un tag specifico
    func hasTag(_ tag: WhatsAppMessageTag, messageId: String) -> Bool {
        ensureTagsLoadedForCurrentScope()
        return messageTags[messageId]?.tags.contains(tag) ?? false
    }
    
    /// Verifica se un messaggio ha almeno un tag
    func hasAnyTag(messageId: String) -> Bool {
        ensureTagsLoadedForCurrentScope()
        guard let data = messageTags[messageId] else { return false }
        return !data.tags.isEmpty || data.sinistroRiferimento != nil
    }
    
    /// Ottieni il riferimento sinistro per un messaggio
    func getSinistroRif(forMessageId messageId: String) -> String? {
        ensureTagsLoadedForCurrentScope()
        return messageTags[messageId]?.sinistroRiferimento
    }
    
    // MARK: - Batch Operations
    
    /// Ottieni tutti i messaggi con un tag specifico
    func getMessages(withTag tag: WhatsAppMessageTag) -> [String] {
        ensureTagsLoadedForCurrentScope()
        return messageTags.filter { $0.value.tags.contains(tag) }.map { $0.key }
    }
    
    /// Ottieni tutti i messaggi associati a un sinistro
    func getMessages(forSinistro sinistroRif: String) -> [String] {
        ensureTagsLoadedForCurrentScope()
        return messageTags.filter { $0.value.sinistroRiferimento == sinistroRif }.map { $0.key }
    }
    
    /// Ottieni statistiche sui tag
    func getTagStats() -> [WhatsAppMessageTag: Int] {
        ensureTagsLoadedForCurrentScope()
        var stats: [WhatsAppMessageTag: Int] = [:]
        
        for tagData in messageTags.values {
            for tag in tagData.tags {
                stats[tag, default: 0] += 1
            }
        }
        
        return stats
    }
    
    // MARK: - Persistence
    
    private func loadAllTags() {
        loadedScope = currentAccountScope
        guard let data = userDefaults.data(forKey: tagsKey) else { return }
        
        do {
            let decoded = try JSONDecoder().decode([String: WhatsAppMessageTagData].self, from: data)
            messageTags = decoded
            print("[WhatsAppTagManager] 📥 Caricati \(messageTags.count) tag messaggi")
        } catch {
            print("[WhatsAppTagManager] ❌ Errore caricamento tag: \(error)")
        }
    }
    
    private func saveTags() {
        do {
            loadedScope = currentAccountScope
            let data = try JSONEncoder().encode(messageTags)
            userDefaults.set(data, forKey: tagsKey)
        } catch {
            lastError = error.localizedDescription
            print("[WhatsAppTagManager] ❌ Errore salvataggio tag: \(error)")
        }
    }
    
    private func setupAutosave() {
        // Salvataggio automatico quando cambiano i tag
        $messageTags
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveTags()
            }
            .store(in: &cancellables)
    }

    private func ensureTagsLoadedForCurrentScope() {
        guard loadedScope != currentAccountScope else { return }
        messageTags.removeAll()
        loadAllTags()
    }

    private var tagsKey: String {
        "whatsapp_message_tags.\(currentAccountScope)"
    }

    private var currentAccountScope: String {
        let accountId = WhatsAppService.shared.selectedAccountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !accountId.isEmpty {
            return accountId
        }
        return CurrentUserService.shared.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "anonymous"
    }
}

// MARK: - Tag Badge View

/// Vista badge per mostrare un tag
struct WhatsAppTagBadge: View {
    let tag: WhatsAppMessageTag
    var isCompact: Bool = false
    var showRemove: Bool = false
    var onRemove: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.iconName)
                .font(.system(size: isCompact ? 10 : 12))
            
            if !isCompact {
                Text(tag.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if showRemove, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(tag.color.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(tag.color)
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 3 : 4)
        .background(tag.color.opacity(0.12))
        .cornerRadius(isCompact ? 6 : 8)
    }
}

// MARK: - Tags Row View

/// Vista per mostrare una riga di tag
struct WhatsAppTagsRowView: View {
    let messageId: String
    @StateObject private var tagManager = WhatsAppMessageTagManager.shared
    var showSinistro: Bool = true
    
    var body: some View {
        let tagData = tagManager.getTagData(forMessageId: messageId)
        
        if let data = tagData, (!data.tags.isEmpty || (showSinistro && data.sinistroRiferimento != nil)) {
            HStack(spacing: 6) {
                // Badge sinistro
                if showSinistro, let sinistroRif = data.sinistroRiferimento {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(sinistroRif)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                }
                
                // Tag
                ForEach(Array(data.tags).sorted(by: { $0.displayName < $1.displayName })) { tag in
                    WhatsAppTagBadge(tag: tag, isCompact: true)
                }
            }
        }
    }
}
