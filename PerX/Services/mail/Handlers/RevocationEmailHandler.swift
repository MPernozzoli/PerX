import Foundation
import CoreData

/// Handler per email di revoca incarico
/// Nota: chiamato RevocationEmailHandler per evitare conflitto con il RevocationHandler esistente
class RevocationEmailHandler: BaseEmailHandler {
    
    private let taskManager = TaskManager.shared
    
    init() {
        super.init(
            handlerId: "revocation",
            supportedCategories: [.revocation]
        )
    }
    
    override func handle(_ email: ClassifiedEmail, context: NSManagedObjectContext, isUnread: Bool) async -> (any EmailEvent)? {
        print("[RevocationHandler] 📧 Processamento email di revoca: \(email.originalEmail.subject)")
        
        // Applica tag di categoria
        await applyEmailTag(for: email)
        
        // Verifica mittente (sempre info@actsrl.it)
        guard email.originalEmail.sender.email.lowercased() == "info@actsrl.it" else {
            print("[RevocationHandler] ⚠️ Mittente non valido: \(email.originalEmail.sender.email)")
            return nil
        }
        
        // Estrai riferimento dall'oggetto (tre varianti)
        let riferimento = extractRevocationReference(from: email.originalEmail.subject)
        
        guard let riferimento = riferimento else {
            print("[RevocationHandler] ⚠️ Impossibile estrarre riferimento sinistro dalla revoca")
            return nil
        }
        
        // Trova il sinistro
        guard let sinistro = findSinistro(riferimento: riferimento, context: context) else {
            print("[RevocationHandler] ⚠️ Sinistro \(riferimento) non trovato per revoca")
            return EmailRevocationReceived(
                emailId: email.originalEmail.id,
                riferimento: riferimento,
                reason: "Sinistro non trovato"
            )
        }
        
        // Se già revocato, ignora
        if sinistro.stato == StatoManager.StatoSinistro.revocata.descrizione {
            print("[RevocationHandler] ℹ️ Sinistro \(riferimento) già revocato")
            // Aggiungi comunque al diario
            sinistro.addDiarioEntry(DiarioEntry(
                testo: "Email di revoca ricevuta (sinistro già revocato)",
                tipo: .email
            ))
            return nil
        }
        
        // Estrai motivo se presente
        let reason = extractRevocationReason(from: email.originalEmail.body ?? "")
        
        // Aggiungi sempre entry nel diario (anche se email letta)
        var diarioText = "Email di revoca ricevuta"
        if let reason = reason, !reason.isEmpty {
            diarioText += ": \(reason)"
        }
        sinistro.addDiarioEntry(DiarioEntry(
            testo: diarioText,
            tipo: .email
        ))
        
        // Genera revoca solo se email è unread
        if isUnread {
            // Usa il RevocationHandler esistente per la logica
            await RevocationHandler.shared.processRevocation(
                for: sinistro,
                email: email.originalEmail,
                context: context
            )
            
            print("[RevocationHandler] ✅ Sinistro \(riferimento) revocato")
        }
        
        return EmailRevocationReceived(
            emailId: email.originalEmail.id,
            riferimento: riferimento,
            reason: reason
        )
    }
    
    // MARK: - Pattern Extraction
    
    private func extractRevocationReference(from subject: String) -> String? {
        // Variante 1: "Revoca incarico videoperizia per sinistro [riferimento] - Assicurato [nome]"
        // Variante 2: "Revoca incarico per sinistro [riferimento] - Assicurato [nome]"
        // Variante 3: "Sinistro n. [numero] - Assicurato [nome] - ns. rif. [riferimento] REVOCA INCARICO"
        
        let patterns = [
            // Variante 1 e 2: "revoca incarico [videoperizia] per sinistro [riferimento]"
            #"revoca\s+incarico\s+(?:videoperizia\s+)?per\s+sinistro\s+([0-9]{7})"#,
            // Variante 3: "ns. rif. [riferimento] REVOCA INCARICO"
            #"ns[.]?\s*rif[.]?\s+([0-9]{7})\s+REVOCA\s+INCARICO"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: subject.utf16.count)
                if let match = regex.firstMatch(in: subject, range: range),
                   match.range(at: 1).location != NSNotFound {
                    let riferimento = (subject as NSString).substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !riferimento.isEmpty && riferimento.count == 7 {
                        return riferimento
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractRevocationReason(from body: String) -> String? {
        // Pattern per estrarre motivo revoca
        let patterns = [
            "motivo[:\\s]+(.+?)(?:\\n|\\.|$)",
            "causa[:\\s]+(.+?)(?:\\n|\\.|$)",
            "perch[eé][:\\s]+(.+?)(?:\\n|\\.|$)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(body.startIndex..<body.endIndex, in: body)
                if let match = regex.firstMatch(in: body, options: [], range: range),
                   let reasonRange = Range(match.range(at: 1), in: body) {
                    return String(body[reasonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return nil
    }
}

