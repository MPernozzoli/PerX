import Foundation
import CoreData
import SwiftUI
import Combine

/// Manager per la gestione dei tag email basati su EmailCategory
/// I tag sono visibili in UI e modificabili dall'utente
/// Quando un tag viene cambiato manualmente, riavvia la pipeline di processamento
@MainActor
class EmailTagManager: ObservableObject {
    
    static let shared = EmailTagManager()
    
    private let context: NSManagedObjectContext
    private let mailManager: MailManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published State
    
    /// Cache dei tag per email (messageId -> EmailCategoryTag)
    @Published var emailCategoryTags: [String: EmailCategoryTag] = [:]
    
    /// Ultimo errore
    @Published var lastError: String?
    
    // MARK: - Initialization
    
    private init(
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) {
        self.context = context
        self.mailManager = MailManager.shared
        // Ritarda loadAllTags per evitare modifiche @Published durante la costruzione della view
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms delay
            await self?.loadAllTags()
        }
    }
    
    // MARK: - Tag Application (chiamato dagli handler)
    
    /// Applica un tag automatico a un'email (chiamato dagli handler durante il processamento)
    /// - Parameters:
    ///   - category: Categoria email rilevata automaticamente
    ///   - emailId: ID del messaggio email
    ///   - confidence: Livello di confidenza della classificazione (0-1)
    ///   - sinistroId: Riferimento sinistro associato (opzionale)
    ///   - status: Stato di processamento iniziale (default: .inCoda)
    func applyAutomaticTag(
        category: EmailCategory,
        toEmailId emailId: String,
        confidence: Double,
        sinistroId: String? = nil,
        status: EmailProcessingStatus = .inCoda
    ) {
        let metadata = getOrCreateEmailMetadata(withMessageId: emailId)
        
        // Verifica se esiste già un tag manuale - non sovrascrivere
        if metadata.isManualTag {
            print("[EmailTagManager] ⚠️ Email \(emailId) ha tag manuale, skip automatico")
            
            // Se lo stato è inCoda o inCorso, imposta come processata per evitare loop infiniti
            let currentStatus = metadata.processingStatus.flatMap { EmailProcessingStatus(rawValue: $0) } ?? .inCoda
            if currentStatus == .inCoda || currentStatus == .inCorso {
                metadata.processingStatus = EmailProcessingStatus.processata.rawValue
                metadata.processingDate = Date()
                saveContext()
                
                // Aggiorna cache
                if var tag = emailCategoryTags[emailId] {
                    tag.processingStatus = .processata
                    emailCategoryTags[emailId] = tag
                }
                
                // Marca anche in ProcessedEmail per evitare loop infiniti in fetchFullEmail
                markAsProcessedInCoreData(emailId: emailId)
                
                print("[EmailTagManager] ✅ Email \(emailId) con tag manuale marcata come processata per evitare loop")
            }
            return
        }
        
        // Applica tag automatico
        metadata.categoryTag = category.rawValue
        metadata.tagConfidence = confidence
        metadata.isManualTag = false
        metadata.sinistroReference = sinistroId
        metadata.tagAppliedDate = Date()
        metadata.processingStatus = status.rawValue
        
        saveContext()
        
        // Aggiorna cache
        let tag = EmailCategoryTag(
            category: category,
            isManual: false,
            confidence: confidence,
            appliedDate: Date(),
            sinistroId: sinistroId,
            processingStatus: status
        )
        emailCategoryTags[emailId] = tag
        
        print("[EmailTagManager] ✅ Tag automatico '\(category.displayName)' applicato a \(emailId) [stato: \(status.displayName)]")
    }
    
    // MARK: - Manual Tag Change (UI)
    
    /// Cambia manualmente il tag di un'email e riavvia la pipeline
    /// - Parameters:
    ///   - category: Nuova categoria da applicare
    ///   - emailId: ID del messaggio email
    /// - Returns: true se il tag è stato cambiato e la pipeline riavviata
    @discardableResult
    func setManualTag(
        category: EmailCategory,
        toEmailId emailId: String
    ) async -> Bool {
        let metadata = getOrCreateEmailMetadata(withMessageId: emailId)
        
        // Ottieni categoria precedente
        let previousCategory = metadata.categoryTag.flatMap { EmailCategory(rawValue: $0) }
        
        // Se è la stessa categoria, non fare nulla
        if previousCategory == category && metadata.isManualTag {
            print("[EmailTagManager] ℹ️ Tag '\(category.displayName)' già impostato per \(emailId)")
            return false
        }
        
        // Applica nuovo tag manuale
        metadata.categoryTag = category.rawValue
        metadata.isManualTag = true
        metadata.tagConfidence = 1.0 // 100% confidenza per tag manuali
        metadata.tagAppliedDate = Date()
        
        saveContext()
        
        // Aggiorna cache - reset stato a inCoda per riprocessamento
        let tag = EmailCategoryTag(
            category: category,
            isManual: true,
            confidence: 1.0,
            appliedDate: Date(),
            sinistroId: metadata.sinistroReference,
            processingStatus: .inCoda
        )
        emailCategoryTags[emailId] = tag
        
        // Reset stato processamento per il riprocessamento
        metadata.processingStatus = EmailProcessingStatus.inCoda.rawValue
        metadata.processingError = nil
        metadata.processingResult = nil
        saveContext()
        
        print("[EmailTagManager] 🏷️ Tag manuale '\(category.displayName)' impostato per \(emailId)")
        
        // Riprocessa l'email con la nuova categoria
        await reprocessEmailWithCategory(emailId: emailId, category: category)
        
        return true
    }
    
    /// Rimuove il tag manuale e permette al sistema di riclassificare automaticamente
    func clearManualTag(forEmailId emailId: String) async {
        guard let metadata = getEmailMetadata(withMessageId: emailId) else { return }
        
        metadata.isManualTag = false
        metadata.categoryTag = nil
        metadata.tagConfidence = 0
        
        saveContext()
        
        // Rimuovi dalla cache
        emailCategoryTags.removeValue(forKey: emailId)
        
        print("[EmailTagManager] 🗑️ Tag manuale rimosso per \(emailId), riclassificazione...")
        
        // Riprocessa l'email per riclassificazione automatica
        await reprocessEmail(emailId: emailId)
    }
    
    // MARK: - Tag Retrieval
    
    /// Ottieni il tag di un'email
    func getTag(forEmailId emailId: String) -> EmailCategoryTag? {
        // Prima controlla cache
        if let cached = emailCategoryTags[emailId] {
            return cached
        }
        
        // Carica da Core Data
        guard let metadata = getEmailMetadata(withMessageId: emailId),
              let categoryRaw = metadata.categoryTag,
              let category = EmailCategory(rawValue: categoryRaw) else {
            return nil
        }
        
        let status = metadata.processingStatus.flatMap { EmailProcessingStatus(rawValue: $0) } ?? .inCoda
        
        let tag = EmailCategoryTag(
            category: category,
            isManual: metadata.isManualTag,
            confidence: metadata.tagConfidence,
            appliedDate: metadata.tagAppliedDate ?? Date(),
            sinistroId: metadata.sinistroReference,
            processingStatus: status,
            processingError: metadata.processingError,
            processingResult: metadata.processingResult
        )
        
        // Aggiorna cache
        emailCategoryTags[emailId] = tag
        
        return tag
    }
    
    /// Verifica se l'email ha un tag (automatico o manuale)
    func hasTag(emailId: String) -> Bool {
        return getTag(forEmailId: emailId) != nil
    }
    
    /// Verifica se l'email ha un tag manuale
    func hasManualTag(emailId: String) -> Bool {
        return getTag(forEmailId: emailId)?.isManual ?? false
    }
    
    // MARK: - Batch Operations
    
    /// Ottieni tutte le email con una specifica categoria
    func getEmails(withCategory category: EmailCategory) -> [String] {
        let request = NSFetchRequest<EmailMetadata>(entityName: "EmailMetadata")
        request.predicate = NSPredicate(format: "categoryTag == %@", category.rawValue)
        
        do {
            let results = try context.fetch(request)
            return results.compactMap { $0.messageId }
        } catch {
            print("[EmailTagManager] ❌ Errore recupero email per categoria: \(error)")
            return []
        }
    }
    
    /// Ottieni statistiche sui tag
    func getTagStats() -> [EmailCategory: Int] {
        var stats: [EmailCategory: Int] = [:]
        
        for category in EmailCategory.allCases {
            let request = NSFetchRequest<EmailMetadata>(entityName: "EmailMetadata")
            request.predicate = NSPredicate(format: "categoryTag == %@", category.rawValue)
            
            do {
                let count = try context.count(for: request)
                if count > 0 {
                    stats[category] = count
                }
            } catch {
                print("[EmailTagManager] ⚠️ Errore conteggio per \(category): \(error)")
            }
        }
        
        return stats
    }
    
    // MARK: - Processing Status Management
    
    /// Aggiorna lo stato di processamento di un'email
    /// - Parameters:
    ///   - emailId: ID del messaggio email
    ///   - status: Nuovo stato di processamento
    ///   - error: Messaggio di errore (se status == .errore)
    ///   - result: Risultato del processamento (es. "sinistro creato", "stato aggiornato")
    func updateProcessingStatus(
        forEmailId emailId: String,
        status: EmailProcessingStatus,
        error: String? = nil,
        result: String? = nil
    ) {
        guard let metadata = getEmailMetadata(withMessageId: emailId) else {
            print("[EmailTagManager] ⚠️ Metadata non trovato per \(emailId)")
            return
        }
        
        metadata.processingStatus = status.rawValue
        metadata.processingError = error
        metadata.processingResult = result
        metadata.processingDate = Date()
        
        saveContext()
        
        // Aggiorna cache
        if var tag = emailCategoryTags[emailId] {
            tag.processingStatus = status
            tag.processingError = error
            tag.processingResult = result
            emailCategoryTags[emailId] = tag
        }
        
        let statusEmoji = status == .processata ? "✅" : (status == .errore ? "❌" : "⏳")
        print("[EmailTagManager] \(statusEmoji) Stato processamento \(emailId): \(status.displayName)")
    }
    
    /// Marca l'email come processata con successo
    func markAsProcessed(emailId: String, result: String? = nil) {
        updateProcessingStatus(forEmailId: emailId, status: .processata, result: result)
    }
    
    /// Marca l'email come errore
    func markAsError(emailId: String, error: String) {
        updateProcessingStatus(forEmailId: emailId, status: .errore, error: error)
    }
    
    /// Marca l'email come in corso di processamento
    func markAsInProgress(emailId: String) {
        updateProcessingStatus(forEmailId: emailId, status: .inCorso)
    }
    
    /// Marca l'email come saltata (non processata volontariamente)
    func markAsSkipped(emailId: String, reason: String? = nil) {
        updateProcessingStatus(forEmailId: emailId, status: .saltata, error: reason ?? "Email saltata (sinistro chiuso o troppo vecchia)")
    }
    
    /// Forza il riprocessamento di un'email (priorità manuale)
    /// - Returns: true se l'email è stata messa in coda con priorità
    @discardableResult
    func forceReprocess(emailId: String) async -> Bool {
        guard let metadata = getEmailMetadata(withMessageId: emailId) else {
            print("[EmailTagManager] ⚠️ Metadata non trovato per \(emailId)")
            return false
        }
        
        // Verifica se lo stato corrente permette modifica manuale
        let currentStatus = metadata.processingStatus.flatMap { EmailProcessingStatus(rawValue: $0) } ?? .inCoda
        guard currentStatus.canBeManuallyChanged else {
            print("[EmailTagManager] ⚠️ Stato \(currentStatus.displayName) non può essere modificato manualmente")
            return false
        }
        
        // Reset stato a inCoda per riprocessamento
        metadata.processingStatus = EmailProcessingStatus.inCoda.rawValue
        metadata.processingError = nil
        metadata.processingResult = nil
        
        saveContext()
        
        // Aggiorna cache
        if var tag = emailCategoryTags[emailId] {
            tag.processingStatus = .inCoda
            tag.processingError = nil
            tag.processingResult = nil
            emailCategoryTags[emailId] = tag
        }
        
        // Prioritizza nella coda (questo triggererà il processamento che cambierà lo stato a inCorso)
        await EmailQueueService.shared.prioritizeEmail(emailId)
        
        print("[EmailTagManager] 🔄 Riprocessamento forzato per \(emailId) - stato reset a 'in coda'")
        return true
    }
    
    /// Ottieni lo stato di processamento di un'email
    func getProcessingStatus(forEmailId emailId: String) -> EmailProcessingStatus {
        return getTag(forEmailId: emailId)?.processingStatus ?? .inCoda
    }
    
    /// Ottieni tutte le email in errore
    func getEmailsWithError() -> [String] {
        return emailCategoryTags.filter { $0.value.processingStatus == .errore }.map { $0.key }
    }
    
    /// Ottieni tutte le email in coda
    func getEmailsInQueue() -> [String] {
        return emailCategoryTags.filter { $0.value.processingStatus == .inCoda }.map { $0.key }
    }
    
    /// Ottieni tutte le email in corso di processamento
    func getEmailsInProgress() -> [String] {
        return emailCategoryTags.filter { $0.value.processingStatus == .inCorso }.map { $0.key }
    }
    
    /// Ottieni tutte le email saltate
    func getEmailsSkipped() -> [String] {
        return emailCategoryTags.filter { $0.value.processingStatus == .saltata }.map { $0.key }
    }
    
    // MARK: - Reprocessing
    
    /// Riprocessa un'email con una categoria specifica (forzata)
    private func reprocessEmailWithCategory(emailId: String, category: EmailCategory) async {
        // Recupera l'email dal repository
        let repository = EmailRepository.shared
        guard let email = repository.getEmail(byId: emailId) else {
            print("[EmailTagManager] ⚠️ Email \(emailId) non trovata per riprocessamento")
            return
        }
        
        // Crea una ClassifiedEmail forzata con la categoria manuale
        let classifiedEmail = ClassifiedEmail(
            originalEmail: email,
            category: category,
            direction: determineDirection(for: email),
            senderType: determineSenderType(for: email),
            sinistroId: extractSinistroReference(from: email),
            confidence: 1.0, // Tag manuale = 100% confidenza
            matchedPatterns: ["manual_tag"]
        )
        
        // Trova l'handler appropriato per la nuova categoria
        guard let handler = EmailHandlerRegistry.shared.findHandler(for: classifiedEmail) else {
            print("[EmailTagManager] ⚠️ Nessun handler per categoria \(category)")
            return
        }
        
        // Processa l'email (sempre come unread per generare task/aggiornamenti)
        if let event = await handler.handle(classifiedEmail, context: context, isUnread: true) {
            // Pubblica evento
            EmailEventBus.shared.publish(event)
            print("[EmailTagManager] 📬 Email \(emailId) riprocessata con categoria \(category.displayName)")
        }
        
        // Riprova associazione automatica con forceReassociation=true (riassocia anche se rimossa manualmente)
        await EmailAssociationService.shared.tryAutomaticAssociation(email, context: context, forceReassociation: true)
    }
    
    /// Riprocessa un'email per riclassificazione automatica
    private func reprocessEmail(emailId: String) async {
        // Rimuovi dalla lista delle email processate per permettere riprocessamento
        removeFromProcessed(emailId: emailId)
        
        // Recupera l'email e riprocessa normalmente (con flag isReprocessing=true)
        do {
            guard let email = try await mailManager.fetchFullEmail(emailId: emailId, context: context) else {
                return
            }
            
            // Riprocessa l'email (con flag isReprocessing per forzare riassociazione)
            _ = await mailManager.processEmail(email, context: context, isReprocessing: true)
        } catch {
            print("[EmailTagManager] ⚠️ Errore recupero email \(emailId) per riprocessamento: \(error)")
        }
    }
    
    /// Rimuove un'email dalla lista delle processate
    private func removeFromProcessed(emailId: String) {
        let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
        request.predicate = NSPredicate(format: "messageId == %@", emailId)
        
        do {
            let results = try context.fetch(request)
            for processed in results {
                context.delete(processed)
            }
            try context.save()
        } catch {
            print("[EmailTagManager] ⚠️ Errore rimozione email processata: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadAllTags() {
        let request = NSFetchRequest<EmailMetadata>(entityName: "EmailMetadata")
        request.predicate = NSPredicate(format: "categoryTag != nil")
        
        do {
            let results = try context.fetch(request)
            for metadata in results {
                guard let messageId = metadata.messageId,
                      let categoryRaw = metadata.categoryTag,
                      let category = EmailCategory(rawValue: categoryRaw) else { continue }
                
                let status = metadata.processingStatus.flatMap { EmailProcessingStatus(rawValue: $0) } ?? .inCoda
                
                let tag = EmailCategoryTag(
                    category: category,
                    isManual: metadata.isManualTag,
                    confidence: metadata.tagConfidence,
                    appliedDate: metadata.tagAppliedDate ?? Date(),
                    sinistroId: metadata.sinistroReference,
                    processingStatus: status,
                    processingError: metadata.processingError,
                    processingResult: metadata.processingResult
                )
                emailCategoryTags[messageId] = tag
            }
            print("[EmailTagManager] 📥 Caricati \(emailCategoryTags.count) tag email")
        } catch {
            print("[EmailTagManager] ❌ Errore caricamento tag: \(error)")
        }
    }
    
    private func getOrCreateEmailMetadata(withMessageId messageId: String) -> EmailMetadata {
        if let existing = getEmailMetadata(withMessageId: messageId) {
            return existing
        }
        
        let newMetadata = EmailMetadata(context: context)
        newMetadata.messageId = messageId
        return newMetadata
    }
    
    private func getEmailMetadata(withMessageId messageId: String) -> EmailMetadata? {
        let request = NSFetchRequest<EmailMetadata>(entityName: "EmailMetadata")
        request.predicate = NSPredicate(format: "messageId == %@", messageId)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    private func saveContext() {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            lastError = error.localizedDescription
            print("[EmailTagManager] ❌ Errore salvataggio: \(error)")
        }
    }
    
    /// Marca un'email come processata in ProcessedEmail (Core Data)
    private func markAsProcessedInCoreData(emailId: String) {
        context.performAndWait {
            let request = NSFetchRequest<ProcessedEmail>(entityName: "ProcessedEmail")
            request.predicate = NSPredicate(format: "messageId == %@", emailId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                if let existing = results.first {
                    existing.processedDate = Date()
                } else {
                    let processed = ProcessedEmail(context: context)
                    processed.messageId = emailId
                    processed.processedDate = Date()
                }
                
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                print("[EmailTagManager] ⚠️ Errore marcatura ProcessedEmail per \(emailId): \(error)")
            }
        }
    }
    
    private func determineDirection(for email: Email) -> EmailDirection {
        TenantMailSettingsService.shared.isInternalEmail(email.sender.email) ? .outbound : .inbound
    }
    
    private func determineSenderType(for email: Email) -> EmailSenderType {
        let senderEmail = email.sender.email.lowercased()
        
        if TenantMailSettingsService.shared.isInternalEmail(senderEmail) {
            return .studio
        } else if senderEmail.contains("agenzia") {
            return .agency
        } else if senderEmail.contains("liquidator") {
            return .liquidator
        }
        
        return .insured
    }
    
    private func extractSinistroReference(from email: Email) -> String? {
        let text = "\(email.subject) \(email.body ?? "")"
        let patterns = [
            "per il sinistro \\[([^\\]]+)\\]",
            "sinistro n[°.]?\\s*([\\w\\-/]+)",
            "pratica[\\s:]+(\\w+[\\-/]?\\w*)",
            "riferimento[\\s:]+(\\w+[\\-/]?\\w*)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
}

// MARK: - Processing Status Enum

/// Stato di processamento dell'email
enum EmailProcessingStatus: String, Codable, CaseIterable {
    case inCoda = "in_coda"           // In attesa di essere processata
    case inCorso = "in_corso"         // In corso di processamento
    case processata = "processata"     // Processata con successo
    case errore = "errore"             // Errore durante il processamento
    case saltata = "saltata"           // Saltata volontariamente (es. vecchia, sinistro chiuso)
    
    var displayName: String {
        switch self {
        case .inCoda: return "In coda"
        case .inCorso: return "In corso"
        case .processata: return "Processata"
        case .errore: return "Errore"
        case .saltata: return "Saltata"
        }
    }
    
    var iconName: String {
        switch self {
        case .inCoda: return "clock.arrow.circlepath"
        case .inCorso: return "arrow.clockwise.circle.fill"
        case .processata: return "checkmark.circle.fill"
        case .errore: return "exclamationmark.triangle.fill"
        case .saltata: return "forward.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .inCoda: return .gray
        case .inCorso: return .blue
        case .processata: return .green
        case .errore: return .red
        case .saltata: return .orange
        }
    }
    
    /// Indica se lo stato può essere modificato manualmente dall'utente
    var canBeManuallyChanged: Bool {
        switch self {
        case .inCoda, .errore, .saltata:
            return true // Può essere forzato a riprocessare
        case .inCorso, .processata:
            return false // Non può essere modificato manualmente durante processamento/completato
        }
    }
}

// MARK: - EmailCategoryTag Model

/// Rappresenta un tag di categoria applicato a un'email
struct EmailCategoryTag: Identifiable, Equatable {
    var id: String { category.rawValue }
    
    let category: EmailCategory
    let isManual: Bool
    let confidence: Double
    let appliedDate: Date
    let sinistroId: String?
    var processingStatus: EmailProcessingStatus
    var processingError: String?
    var processingResult: String?
    
    /// Colore del tag basato sulla categoria
    var color: Color {
        switch category {
        case .assignment:
            return .green
        case .revocation:
            return .red
        case .controlled:
            return .purple
        case .revisionRequested:
            return .orange
        case .documentationRequest:
            return .blue
        case .documentationReceived:
            return .teal
        case .reminderReceived, .reminderSent:
            return .yellow
        case .surveyScheduled, .surveyReturned, .videocallScheduled:
            return .indigo
        case .actSent:
            return .mint
        case .actReceived:
            return .cyan
        case .clarificationRequest:
            return .pink
        case .outcomeSent:
            return .green
        case .verbalAcceptance:
            return .teal
        case .genericCommunication:
            return .gray
        // Studio categories
        case .studioNews:
            return Color(red: 0.2, green: 0.5, blue: 0.8) // Blu corporate
        case .internalInfo:
            return Color(red: 0.4, green: 0.6, blue: 0.4) // Verde info
        case .procedure:
            return Color(red: 0.6, green: 0.4, blue: 0.6) // Viola procedure
        case .meeting:
            return Color(red: 0.9, green: 0.5, blue: 0.2) // Arancione riunioni
        case .training:
            return Color(red: 0.3, green: 0.7, blue: 0.7) // Teal formazione
        case .administrative:
            return Color(red: 0.5, green: 0.5, blue: 0.3) // Oliva amministrativo
        case .newsletter:
            return Color(red: 0.6, green: 0.6, blue: 0.6) // Grigio newsletter
        case .spam:
            return Color(red: 0.4, green: 0.4, blue: 0.4) // Grigio scuro spam
        }
    }
    
    /// Icona del tag
    var iconName: String {
        category.iconName
    }
    
    /// Nome visualizzato
    var displayName: String {
        category.displayName
    }
    
    /// Badge per tag manuale
    var isManualBadge: String? {
        isManual ? "Manuale" : nil
    }
}

// MARK: - EmailMetadata Extension

extension EmailMetadata {
    
    /// Tag categoria email (rawValue di EmailCategory)
    @objc var categoryTag: String? {
        get { primitiveValue(forKey: "categoryTag") as? String }
        set { setPrimitiveValue(newValue, forKey: "categoryTag") }
    }
    
    /// True se il tag è stato impostato manualmente dall'utente
    var isManualTag: Bool {
        get { (primitiveValue(forKey: "isManualTag") as? Bool) ?? false }
        set { setPrimitiveValue(newValue, forKey: "isManualTag") }
    }
    
    /// Confidenza della classificazione (0-1)
    var tagConfidence: Double {
        get { (primitiveValue(forKey: "tagConfidence") as? Double) ?? 0 }
        set { setPrimitiveValue(newValue, forKey: "tagConfidence") }
    }
    
    /// Data applicazione tag
    var tagAppliedDate: Date? {
        get { primitiveValue(forKey: "tagAppliedDate") as? Date }
        set { setPrimitiveValue(newValue, forKey: "tagAppliedDate") }
    }
    
    /// Riferimento sinistro associato
    var sinistroReference: String? {
        get { primitiveValue(forKey: "sinistroReference") as? String }
        set { setPrimitiveValue(newValue, forKey: "sinistroReference") }
    }
    
    /// Stato di processamento (rawValue di EmailProcessingStatus)
    var processingStatus: String? {
        get { primitiveValue(forKey: "processingStatus") as? String }
        set { setPrimitiveValue(newValue, forKey: "processingStatus") }
    }
    
    /// Messaggio di errore (se stato == errore)
    var processingError: String? {
        get { primitiveValue(forKey: "processingError") as? String }
        set { setPrimitiveValue(newValue, forKey: "processingError") }
    }
    
    /// Data dell'ultimo tentativo di processamento
    var processingDate: Date? {
        get { primitiveValue(forKey: "processingDate") as? Date }
        set { setPrimitiveValue(newValue, forKey: "processingDate") }
    }
    
    /// Risultato del processamento (es. "sinistro creato", "stato aggiornato")
    var processingResult: String? {
        get { primitiveValue(forKey: "processingResult") as? String }
        set { setPrimitiveValue(newValue, forKey: "processingResult") }
    }
}
