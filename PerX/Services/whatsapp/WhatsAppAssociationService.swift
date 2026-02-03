import Foundation
import CoreData

@MainActor
class WhatsAppAssociationService {
    static let shared = WhatsAppAssociationService()
    
    private init() {}
    
    // MARK: - Estrazione dati dai messaggi
    
    /// Estrae il riferimento interno (7 cifre) dai messaggi della chat
    func extractRiferimentoSinistro(from messages: [WhatsAppMessage]) -> String? {
        let pattern = #"\b([0-9]{7})\b"# // 7 cifre consecutive
        
        for message in messages.reversed() { // Controlla dai più recenti
            if let riferimento = trovaPattern(pattern, in: message.body) {
                if isValidRiferimentoInterno(riferimento) {
                    return riferimento
                }
            }
        }
        
        return nil
    }
    
    /// Estrae il numero sinistro compagnia dai messaggi
    func extractNumeroSinistroCompagnia(from messages: [WhatsAppMessage]) -> String? {
        let patterns = [
            #"sinistro\s+n[°.]?\s*([0-9A-Z\-/]+)"#,
            #"sinistro\s+([0-9A-Z\-/]+)"#,
            #"pratica\s+n[°.]?\s*([0-9A-Z\-/]+)"#,
            #"pratica\s+([0-9A-Z\-/]+)"#,
            #"numero\s+sinistro[:\s]+([0-9A-Z\-/]+)"#,
            #"n[°.]?\s*sinistro[:\s]+([0-9A-Z\-/]+)"#,
        ]
        
        for message in messages.reversed() {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: message.body.utf16.count)
                    if let match = regex.firstMatch(in: message.body, range: range) {
                        let matchRange = match.range(at: 1)
                        if matchRange.location != NSNotFound {
                            let numero = (message.body as NSString).substring(with: matchRange)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !numero.isEmpty && numero.count >= 3 {
                                return numero
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Estrae il nome assicurato dai messaggi
    func extractNomeAssicurato(from messages: [WhatsAppMessage], chatName: String) -> String? {
        // Pattern per nome assicurato
        let patterns = [
            #"assicurato\s+([A-Za-z\s]+?)(?:\s+-\s+|$)"#,
            #"cliente\s+([A-Za-z\s]+?)(?:\s+-\s+|$)"#,
            #"sig\.?\s+([A-Za-z\s]+?)(?:\s+-\s+|$)"#,
            #"sig\.ra\s+([A-Za-z\s]+?)(?:\s+-\s+|$)"#,
        ]
        
        for message in messages.reversed() {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: message.body.utf16.count)
                    if let match = regex.firstMatch(in: message.body, range: range) {
                        let matchRange = match.range(at: 1)
                        if matchRange.location != NSNotFound {
                            let nome = (message.body as NSString).substring(with: matchRange)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nome.isEmpty && nome.count >= 3 {
                                return nome
                            }
                        }
                    }
                }
            }
        }
        
        // Se non trovato nei messaggi, prova con il nome della chat
        if !chatName.isEmpty && chatName.count >= 3 {
            // Rimuovi numeri e caratteri speciali
            let cleaned = chatName.replacingOccurrences(of: "[0-9\\-\\+\\s\\(\\)]", with: "", options: .regularExpression)
            if cleaned.count >= 3 {
                return cleaned
            }
        }
        
        return nil
    }
    
    // MARK: - Associazione automatica
    
    /// Trova i sinistri corrispondenti a una chat WhatsApp analizzando i messaggi
    func checkChatAssociation(_ chat: WhatsAppChat, messages: [WhatsAppMessage], context: NSManagedObjectContext) -> [Sinistro] {
        var matchingSinistri: [Sinistro] = []
        
        // FASE 1: Estrai riferimento interno (priorità massima)
        let riferimentoInterno = extractRiferimentoSinistro(from: messages)
        
        // FASE 2: Estrai numero sinistro compagnia
        let numeroCompagnia = extractNumeroSinistroCompagnia(from: messages)
        
        // FASE 3: Estrai nome assicurato
        let nomeAssicurato = extractNomeAssicurato(from: messages, chatName: chat.name)
        
        // Cerca sinistri con match
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        let allSinistri = (try? context.fetch(request)) ?? []
        
        var exactMatches: [Sinistro] = [] // Riferimento interno esatto
        var numeroMatches: [Sinistro] = [] // Numero compagnia
        var nomeMatches: [Sinistro] = [] // Nome assicurato
        
        for sinistro in allSinistri {
            // PRIORITÀ 1: Match per riferimento interno (più preciso)
            if let riferimento = riferimentoInterno,
               let sinistroRiferimento = sinistro.riferimento,
               sinistroRiferimento == riferimento {
                if !exactMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                    exactMatches.append(sinistro)
                }
                continue
            }
            
            // PRIORITÀ 2: Match per numero sinistro compagnia
            if let numero = numeroCompagnia,
               let sinistroNumero = sinistro.numeroSinistroCompagnia,
               !sinistroNumero.isEmpty {
                let normalizedNumero = normalizeNumber(numero)
                let normalizedSinistroNumero = normalizeNumber(sinistroNumero)
                
                // Match diretto normalizzato
                if normalizedNumero == normalizedSinistroNumero {
                    if !numeroMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                        numeroMatches.append(sinistro)
                    }
                    continue
                }
                
                // Match con segmentazioni via CompagniaService
                let compagnia = Compagnia.detect(
                    gruppo: sinistro.gruppo,
                    compagnia: sinistro.nomeCompagnia
                )
                
                // Verifica se il numero estratto è un segmento valido del numero sinistro
                let segmenti = CompagniaService.shared.segmentaNumeroSinistro(
                    numeroCompleto: sinistroNumero,
                    compagnia: compagnia
                )
                
                for segmento in segmenti {
                    if normalizedNumero == normalizeNumber(segmento) {
                        if !numeroMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                            numeroMatches.append(sinistro)
                        }
                        break
                    }
                }
            }
            
            // PRIORITÀ 3: Match per nome assicurato (meno preciso, solo se non ci sono match migliori)
            if riferimentoInterno == nil && numeroCompagnia == nil,
               let nome = nomeAssicurato,
               let sinistroNome = sinistro.nomeAssicurato,
               !sinistroNome.isEmpty {
                let normalizedNome = nome.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedSinistroNome = sinistroNome.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Match parziale (contiene o è contenuto)
                if normalizedNome.contains(normalizedSinistroNome) || normalizedSinistroNome.contains(normalizedNome) {
                    if !nomeMatches.contains(where: { $0.objectID == sinistro.objectID }) {
                        nomeMatches.append(sinistro)
                    }
                }
            }
        }
        
        // Restituisci in ordine di priorità
        matchingSinistri.append(contentsOf: exactMatches)
        matchingSinistri.append(contentsOf: numeroMatches)
        matchingSinistri.append(contentsOf: nomeMatches)
        
        return matchingSinistri
    }
    
    /// Associa una chat WhatsApp a uno o più sinistri
    func associateChatToSinistri(_ chatId: String, sinistri: [Sinistro], context: NSManagedObjectContext) {
        guard !sinistri.isEmpty else { return }
        
        for sinistro in sinistri {
            // Cerca o crea thread per questo sinistro
            let request = NSFetchRequest<SinistroWhatsAppThread>(entityName: "SinistroWhatsAppThread")
            request.predicate = NSPredicate(format: "sinistro == %@", sinistro)
            
            let existingThreads = (try? context.fetch(request)) ?? []
            let thread: SinistroWhatsAppThread
            
            if let existing = existingThreads.first {
                thread = existing
            } else {
                thread = SinistroWhatsAppThread(context: context)
                thread.sinistro = sinistro
                thread.dataCreazione = Date()
            }
            
            thread.dataUltimaModifica = Date()
            thread.addWhatsAppChatId(chatId)
        }
        
        do {
            try context.save()
            print("[WhatsAppAssociation] ✅ Chat \(chatId) associata a \(sinistri.count) sinistro/i")
        } catch {
            print("[WhatsAppAssociation] ❌ Errore salvataggio associazione: \(error)")
        }
    }
    
    /// Rimuove l'associazione di una chat WhatsApp da tutti i sinistri
    func disassociateChat(chatId: String, context: NSManagedObjectContext) {
        // Cerca tutti i thread che contengono questa chatId
        let request = NSFetchRequest<SinistroWhatsAppThread>(entityName: "SinistroWhatsAppThread")
        
        do {
            let allThreads = try context.fetch(request)
            var modified = false
            
            for thread in allThreads {
                // Verifica se il thread contiene questa chatId
                if thread.chatIds.contains(chatId) {
                    thread.removeWhatsAppChatId(chatId)
                    modified = true
                    
                    // Se il thread non ha più chat associate, eliminalo
                    if thread.chatIds.isEmpty {
                        context.delete(thread)
                    }
                }
            }
            
            if modified {
                try context.save()
                print("[WhatsAppAssociation] ✅ Chat \(chatId) disassociata da tutti i sinistri")
            }
        } catch {
            print("[WhatsAppAssociation] ❌ Errore disassociazione chat: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func trovaPattern(_ pattern: String, in testo: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: testo.utf16.count)
        if let match = regex.firstMatch(in: testo, range: range) {
            let matchRange = match.range(at: 1)
            if matchRange.location != NSNotFound {
                return (testo as NSString).substring(with: matchRange)
            }
        }
        
        return nil
    }
    
    private func isValidRiferimentoInterno(_ riferimento: String) -> Bool {
        guard riferimento.count == 7, riferimento.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        let annoString = String(riferimento.prefix(2))
        guard let anno = Int(annoString) else { return false }
        
        return anno >= 20 && anno <= 30
    }
    
    private func normalizeNumber(_ number: String) -> String {
        return number.replacingOccurrences(of: "[^0-9A-Za-z]", with: "", options: .regularExpression)
    }
}

