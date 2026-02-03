import Foundation
import CoreData
import SwiftUI

/// Gestisce la logica di creazione, associazione e recupero dei Tag.
class TagManager: ObservableObject {
    
    static let shared = TagManager()
    private let context: NSManagedObjectContext
    
    @Published var tags: [Tag] = []
    @Published var emailTags: [String: [Tag]] = [:] // messageId: [Tag]
    
    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        loadTags()
    }
    
    enum TagType: Int16 {
        case sinistro = 0
        case studio = 1
    }
    
    // MARK: - Creazione Tag
    
    /// Crea e salva un nuovo tag di tipo "Studio".
    func createStudioTag(name: String, color: Color = .gray) throws -> Tag {
        let newTag = Tag(context: context)
        newTag.id = UUID()
        newTag.name = name
        newTag.type = TagType.studio.rawValue
        newTag.color = colorToHex(color)
        
        try context.save()
        objectWillChange.send()
        loadTags()
        return newTag
    }
    
    /// Crea un tag associato a un sinistro specifico. Se esiste già, lo restituisce.
    func createOrGetSinistroTag(for sinistro: Sinistro) throws -> Tag {
        if let existingTag = sinistro.tags?.allObjects.first as? Tag {
            return existingTag
        }
        
        let newTag = Tag(context: context)
        newTag.id = UUID()
        newTag.name = sinistro.riferimento ?? "Sinistro"
        newTag.type = TagType.sinistro.rawValue
        newTag.sinistro = sinistro
        newTag.color = colorToHex(.blue) // Colore di default per i sinistri
        
        try context.save()
        objectWillChange.send()
        loadTags()
        return newTag
    }
    
    // MARK: - Associazione Tag
    
    /// Associa un tag a un'email, identificata dal suo messageId.
    func addTag(_ tag: Tag, toEmailWithMessageId messageId: String) throws {
        let emailMetadata = try getOrCreateEmailMetadata(withMessageId: messageId)
        emailMetadata.addToTags(tag)
        try context.save()
        objectWillChange.send()
        loadEmailTags(forMessageId: messageId)
    }
    
    /// Rimuove un'associazione tra tag e email.
    func removeTag(_ tag: Tag, fromEmailWithMessageId messageId: String) throws {
        let emailMetadata = try getOrCreateEmailMetadata(withMessageId: messageId)
        emailMetadata.removeFromTags(tag)
        try context.save()
        objectWillChange.send()
        loadEmailTags(forMessageId: messageId)
    }
    
    // MARK: - Recupero Tag
    
    /// Restituisce tutti i tag associati a un'email.
    func getTags(forEmailWithMessageId messageId: String) -> [Tag] {
        if let cachedTags = emailTags[messageId] {
            return cachedTags
        }
        
        guard let emailMetadata = try? getEmailMetadata(withMessageId: messageId) else {
            return []
        }
        
        let tags = emailMetadata.tags?.allObjects as? [Tag] ?? []
        emailTags[messageId] = tags
        return tags
    }
    
    /// Restituisce tutti i tag di un certo tipo.
    func getAllTags(ofType type: TagType) -> [Tag] {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "type == %d", type.rawValue)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Errore nel recupero dei tag: \(error)")
            return []
        }
    }
    
    // MARK: - Helpers
    
    private func loadTags() {
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        
        do {
            tags = try context.fetch(request)
        } catch {
            print("Errore nel caricamento dei tag: \(error)")
            tags = []
        }
    }
    
    private func loadEmailTags(forMessageId messageId: String) {
        emailTags[messageId] = getTags(forEmailWithMessageId: messageId)
    }
    
    /// Recupera o crea un'entità EmailMetadata per un dato messageId.
    private func getOrCreateEmailMetadata(withMessageId messageId: String) throws -> EmailMetadata {
        if let existing = try getEmailMetadata(withMessageId: messageId) {
            return existing
        }
        
        let newEmailMetadata = EmailMetadata(context: context)
        newEmailMetadata.messageId = messageId
        return newEmailMetadata
    }
    
    private func getEmailMetadata(withMessageId messageId: String) throws -> EmailMetadata? {
        let request: NSFetchRequest<EmailMetadata> = EmailMetadata.fetchRequest()
        request.predicate = NSPredicate(format: "messageId == %@", messageId)
        request.fetchLimit = 1
        
        return try context.fetch(request).first
    }
    
    // MARK: - Color Helpers
    
    private func colorToHex(_ color: Color) -> String {
        return color.toHex() ?? "#808080"
    }
    
    func hexToColor(_ hex: String) -> Color {
        return Color(hex: hex) ?? .gray
    }
}

// Estensione per convertire Color in Hex e viceversa
extension Color {
    func toHex() -> String? {
        // Implementazione per convertire Color in una stringa esadecimale
        // ... da completare
        return ""
    }
} 