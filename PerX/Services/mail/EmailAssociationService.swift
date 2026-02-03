import Foundation
import CoreData

/// Service per gestire l'associazione email-sinistro usando pattern matching
@MainActor
class EmailAssociationService {
    static let shared = EmailAssociationService()
    
    private let patternMatcher = EmailPatternMatcher.shared
    private let disassociationService = EmailDisassociationService.shared
    private let threadCustomizationService = ThreadCustomizationService.shared
    
    private init() {}
    
    // MARK: - Associazione Automatica
    
    /// Verifica se un'email può essere associata a sinistri e restituisce i sinistri candidati
    /// - Parameters:
    ///   - email: L'email da associare
    ///   - context: Il contesto Core Data
    /// - Returns: Array di sinistri candidati ordinati per priorità (riferimento > numero > nome)
    func checkEmailAssociation(_ email: Email, context: NSManagedObjectContext) -> [Sinistro] {
        // Estrai pattern dall'email (oggetto prima, corpo se oggetto vuoto)
        let patterns = patternMatcher.extractPatterns(subject: email.subject, body: email.body)
        
        // Se non ci sono pattern, non può essere associata
        guard patterns.hasAnyPattern else {
            return []
        }
        
        // Verifica se l'email è esclusa
        if threadCustomizationService.isEmailExcluded(emailId: email.id) {
            return []
        }
        
        // Cerca sinistri con match
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        let allSinistri = (try? context.fetch(request)) ?? []
        
        // Dizionario per tracciare match per priorità
        var riferimentoMatches: [Sinistro] = [] // PRIORITÀ 1: Riferimento interno esatto
        var numeroMatches: [Sinistro] = [] // PRIORITÀ 2: Numero compagnia normalizzato
        var nomeMatches: [Sinistro] = [] // PRIORITÀ 3: Nome assicurato (match parziale)
        
        for sinistro in allSinistri {
            let sinistroId = sinistro.objectID.uriRepresentation().absoluteString
            if disassociationService.isDisassociated(emailId: email.id, sinistroId: sinistroId) {
                continue
            }
            
            // PRIORITÀ 1: Match per riferimento interno esatto
            if let riferimento = patterns.riferimento,
               let sinistroRiferimento = sinistro.riferimento,
               sinistroRiferimento == riferimento {
                if !riferimentoMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                    riferimentoMatches.append(sinistro)
                }
                continue // Riferimento è la priorità più alta
            }
            
            // PRIORITÀ 2: Match per numero sinistro compagnia (normalizzato)
            if let numero = patterns.numeroAgenzia,
               let sinistroNumero = sinistro.numeroSinistroCompagnia,
               !sinistroNumero.isEmpty {
                let normalizedNumero = patternMatcher.normalizeNumber(numero)
                let normalizedSinistroNumero = patternMatcher.normalizeNumber(sinistroNumero)
                
                if normalizedNumero == normalizedSinistroNumero {
                    if !numeroMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                        numeroMatches.append(sinistro)
                    }
                    continue
                }
            }
            
            // PRIORITÀ 3: Match per nome assicurato (match più restrittivo per evitare falsi positivi)
            if let nome = patterns.nomeAssicurato,
               let sinistroNome = sinistro.nomeAssicurato,
               !sinistroNome.isEmpty {
                let normalizedEmailNome = nome.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedSinistroNome = sinistroNome.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Match parziale (contiene) - più restrittivo
                if normalizedSinistroNome.contains(normalizedEmailNome) || normalizedEmailNome.contains(normalizedSinistroNome) {
                    // Verifica che non sia solo una parola comune
                    if normalizedEmailNome.split(separator: " ").count >= 2 {
                        if !nomeMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                            nomeMatches.append(sinistro)
                        }
                    }
                }
            }
        }
        
        // Restituisci i match ordinati per priorità
        var result: [Sinistro] = []
        result.append(contentsOf: riferimentoMatches)
        result.append(contentsOf: numeroMatches)
        result.append(contentsOf: nomeMatches)
        
        return result
    }
    
    /// Associa un'email a uno o più sinistri creando/aggiornando i thread
    /// - Parameters:
    ///   - email: L'email da associare
    ///   - sinistri: I sinistri a cui associare l'email
    ///   - context: Il contesto Core Data
    func associateEmailToSinistri(_ email: Email, sinistri: [Sinistro], context: NSManagedObjectContext) async {
        guard !sinistri.isEmpty else { return }
        
        for sinistro in sinistri {
            let sinistroId = sinistro.objectID.uriRepresentation().absoluteString
            
            // Rimuovi la disassociazione se presente (associazione manuale)
            disassociationService.removeDisassociation(emailId: email.id, sinistroId: sinistroId)
            
            // Cerca o crea thread per questo sinistro
            let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
            request.predicate = NSPredicate(format: "sinistro == %@", sinistro)
            
            let existingThreads = (try? context.fetch(request)) ?? []
            let thread: SinistroEmailThread
            
            if let existing = existingThreads.first {
                thread = existing
            } else {
                thread = SinistroEmailThread(context: context)
                thread.sinistro = sinistro
                thread.dataCreazione = Date()
            }
            
            thread.dataUltimaModifica = Date()
            thread.addEmailMessageId(email.id)
        }
        
        do {
            try context.save()
            print("[EmailAssociationService] ✅ Email \(email.id) associata a \(sinistri.count) sinistro/i")
            
            // Notifica che l'associazione è stata creata
            NotificationCenter.default.post(
                name: .emailAssociated,
                object: nil,
                userInfo: [
                    "emailId": email.id,
                    "sinistroRiferimenti": sinistri.compactMap { $0.riferimento }
                ]
            )
        } catch {
            print("[EmailAssociationService] ❌ Errore salvataggio associazione: \(error)")
        }
    }
    
    /// Verifica se un'email può essere associata automaticamente (match esatto di riferimento)
    /// - Parameters:
    ///   - email: L'email da verificare
    ///   - context: Il contesto Core Data
    /// - Returns: I sinistri con match esatto di riferimento (massimo 1 per associazione automatica)
    func findExactMatches(_ email: Email, context: NSManagedObjectContext) -> [Sinistro] {
        let suggested = checkEmailAssociation(email, context: context)
        
        // Estrai riferimento dall'email
        let riferimento = extractRiferimentoSinistro(from: email.subject, body: email.body)
        
        // Filtra solo match esatti di riferimento
        let exactMatches = suggested.filter { sinistro in
            if let riferimento = riferimento,
               let sinistroRiferimento = sinistro.riferimento,
               sinistroRiferimento == riferimento {
                return true
            }
            return false
        }
        
        return exactMatches
    }
    
    /// Associa automaticamente un'email se c'è un solo match esatto di riferimento
    /// - Parameters:
    ///   - email: L'email da associare
    ///   - context: Il contesto Core Data
    ///   - forceReassociation: Se true, ignora le disassociazioni manuali e riassocia (per riprocessamento)
    /// - Returns: true se l'associazione è stata effettuata, false altrimenti
    func tryAutomaticAssociation(_ email: Email, context: NSManagedObjectContext, forceReassociation: Bool = false) async -> Bool {
        // Verifica se l'email è esclusa
        if threadCustomizationService.isEmailExcluded(emailId: email.id) {
            return false
        }
        
        // Verifica se l'email è già associata
        let threadRequest = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        guard let allThreads = try? context.fetch(threadRequest) else {
            return false
        }
        let isAlreadyAssociated = allThreads.contains { $0.messageIds.contains(email.id) }
        if isAlreadyAssociated {
            // Email già associata, skip
            return false
        }
        
        // Trova match esatti (ignorando disassociazioni manuali se forceReassociation)
        let exactMatches: [Sinistro]
        if forceReassociation {
            // Per riprocessamento: trova match ignorando disassociazioni manuali
            let suggested = checkEmailAssociation(email, context: context)
            let riferimento = extractRiferimentoSinistro(from: email.subject, body: email.body)
            
            exactMatches = suggested.filter { sinistro in
                if let riferimento = riferimento,
                   let sinistroRiferimento = sinistro.riferimento,
                   sinistroRiferimento == riferimento {
                    // Se forceReassociation, rimuovi la disassociazione manuale
                    let sinistroId = sinistro.objectID.uriRepresentation().absoluteString
                    if disassociationService.isDisassociated(emailId: email.id, sinistroId: sinistroId) {
                        print("[EmailAssociationService] 🔄 Rimozione disassociazione manuale per riprocessamento: \(email.id) -> \(sinistroRiferimento)")
                        disassociationService.removeDisassociation(emailId: email.id, sinistroId: sinistroId)
                    }
                    return true
                }
                return false
            }
        } else {
            // Comportamento normale: rispetta disassociazioni manuali
            exactMatches = findExactMatches(email, context: context)
        }
        
        if exactMatches.count == 1 {
            // Un solo match esatto: associa automaticamente
            await associateEmailToSinistri(email, sinistri: exactMatches, context: context)
            print("[EmailAssociationService] ✅ Email \(email.id) associata automaticamente a sinistro \(exactMatches.first?.riferimento ?? "N/A") (match riferimento esatto)")
            
            // Notifica che l'associazione è stata creata
            NotificationCenter.default.post(
                name: .emailAssociated,
                object: nil,
                userInfo: [
                    "emailId": email.id,
                    "sinistroRiferimento": exactMatches.first?.riferimento ?? ""
                ]
            )
            
            return true
        } else if exactMatches.count > 1 {
            // Più match esatti: richiesta conferma manuale
            print("[EmailAssociationService] ⚠️ Email \(email.id) ha \(exactMatches.count) match esatti, richiesta conferma manuale")
            return false
        }
        
        // Nessun match trovato (log solo in debug per non intasare i log)
        // Le email senza pattern vengono ignorate silenziosamente
        return false
    }
    
    // MARK: - Helper
    
    private func extractRiferimentoSinistro(from subject: String, body: String?) -> String? {
        let text = "\(subject) \(body ?? "")"
        let pattern = #"\b([0-9]{7})\b"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: text.utf16.count)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            let matchRange = match.range(at: 1)
            if matchRange.location != NSNotFound {
                return (text as NSString).substring(with: matchRange)
            }
        }
        
        return nil
    }
}
