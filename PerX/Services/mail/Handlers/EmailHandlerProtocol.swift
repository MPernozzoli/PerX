import Foundation
import CoreData

/// Protocollo base per tutti gli handler di email
/// Ogni handler gestisce una o più categorie di email e produce eventi tipizzati
protocol EmailHandler {
    /// Identificatore univoco dell'handler
    var handlerId: String { get }
    
    /// Categorie di email supportate da questo handler
    var supportedCategories: [EmailCategory] { get }
    
    /// Verifica se l'handler può gestire questa email classificata
    func canHandle(_ email: ClassifiedEmail) -> Bool
    
    /// Gestisce l'email e restituisce un evento tipizzato
    /// - Parameters:
    ///   - email: Email classificata da processare
    ///   - context: Contesto Core Data per operazioni database
    ///   - isUnread: true se l'email ha label UNREAD (non letta), false altrimenti
    /// - Returns: Evento tipizzato da pubblicare sul bus, nil se non serve pubblicare
    /// - Note: Se isUnread == false, non generare task/aggiornamenti stato, ma aggiungere sempre al diario
    func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)?
}

// MARK: - Default Implementation

extension EmailHandler {
    /// Implementazione di default: verifica se la categoria è supportata
    func canHandle(_ email: ClassifiedEmail) -> Bool {
        return supportedCategories.contains(email.category)
    }
}

// MARK: - Handler Registry

/// Registry che mantiene tutti gli handler registrati
@MainActor
class EmailHandlerRegistry {
    static let shared = EmailHandlerRegistry()
    
    private var handlers: [EmailHandler] = []
    
    private init() {}
    
    /// Registra un handler
    func register(_ handler: EmailHandler) {
        // Evita duplicati
        if handlers.contains(where: { $0.handlerId == handler.handlerId }) {
            print("[HandlerRegistry] ⚠️ Handler \(handler.handlerId) già registrato")
            return
        }
        handlers.append(handler)
        print("[HandlerRegistry] ✅ Registrato handler: \(handler.handlerId)")
    }
    
    /// Trova tutti gli handler che possono gestire questa email
    func findHandlers(for email: ClassifiedEmail) -> [EmailHandler] {
        return handlers.filter { $0.canHandle(email) }
    }
    
    /// Trova il primo handler che può gestire questa email
    func findHandler(for email: ClassifiedEmail) -> EmailHandler? {
        return handlers.first { $0.canHandle(email) }
    }
    
    /// Ottieni tutti gli handler registrati
    func getAllHandlers() -> [EmailHandler] {
        return handlers
    }
    
    /// Rimuovi tutti gli handler (utile per test)
    func clearHandlers() {
        handlers.removeAll()
    }
}

// MARK: - Base Handler

/// Classe base che fornisce funzionalità comuni a tutti gli handler
class BaseEmailHandler: EmailHandler {
    let handlerId: String
    let supportedCategories: [EmailCategory]
    
    init(handlerId: String, supportedCategories: [EmailCategory]) {
        self.handlerId = handlerId
        self.supportedCategories = supportedCategories
    }
    
    func canHandle(_ email: ClassifiedEmail) -> Bool {
        return supportedCategories.contains(email.category)
    }
    
    func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        // Da implementare nelle sottoclassi
        fatalError("Deve essere implementato dalla sottoclasse")
    }
    
    /// Applica automaticamente il tag di categoria all'email
    /// Chiamare all'inizio di ogni handler per tracciare la classificazione
    @MainActor
    func applyEmailTag(for email: ClassifiedEmail) {
        EmailTagManager.shared.applyAutomaticTag(
            category: email.category,
            toEmailId: email.originalEmail.id,
            confidence: email.confidence,
            sinistroId: email.sinistroId
        )
    }
    
    // MARK: - Helper Methods
    
    /// Trova un sinistro per riferimento
    func findSinistro(riferimento: String, context: NSManagedObjectContext) -> Sinistro? {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("[BaseHandler] ❌ Errore ricerca sinistro: \(error)")
            return nil
        }
    }
    
    /// Estrae il riferimento sinistro dal corpo dell'email
    func extractSinistroReference(from email: ClassifiedEmail) -> String? {
        // Se già estratto dal classificatore
        if let sinistroId = email.sinistroId, !sinistroId.isEmpty {
            return sinistroId
        }
        
        // Prova a estrarre dal subject o body
        let text = "\(email.originalEmail.subject) \(email.originalEmail.body ?? "")"
        return extractReference(from: text)
    }
    
    /// Pattern matching per riferimento sinistro
    private func extractReference(from text: String) -> String? {
        let patterns = [
            "per il sinistro \\[([^\\]]+)\\]",
            "per il sinistro\\s+([\\w\\-/]+)",
            "sinistro n[°.]?\\s*([\\w\\-/]+)",
            "pratica[\\s:]+(\\w+[\\-/]?\\w*)",
            "riferimento[\\s:]+(\\w+[\\-/]?\\w*)",
            "\\bsinistro[\\s:]+(\\w+[\\-/]?\\w*)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let idRange = Range(match.range(at: 1), in: text) {
                    let foundID = String(text[idRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !foundID.isEmpty && foundID.count > 2 {
                        return foundID
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Salva modifiche al contesto
    func saveContext(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("[BaseHandler] ❌ Errore salvataggio contesto: \(error)")
            }
        }
    }
}

