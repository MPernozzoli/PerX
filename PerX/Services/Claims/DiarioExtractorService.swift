import Foundation

/// Servizio per estrarre comunicazioni rilevanti dal diario per la generazione di relazioni
class DiarioExtractorService {
    static let shared = DiarioExtractorService()
    
    private init() {}
    
    // MARK: - Tipi di entry rilevanti
    
    /// Tipi di entry del diario da includere nell'estrazione
    private let tipiRilevanti: Set<String> = [
        "Email",
        "WhatsApp",
        "Nota Utente"
    ]
    
    /// Tipi di entry da escludere
    private let tipiDaEscludere: Set<String> = [
        "Assegnazione",
        "Cambio Stato",
        "Sistema",
        "Aggiornamento"
    ]
    
    // MARK: - Estrazione Comunicazioni
    
    /// Estrae le comunicazioni rilevanti dal diario del sinistro
    /// - Parameter sinistro: Il sinistro da cui estrarre le comunicazioni
    /// - Returns: Array di comunicazioni estratte, ordinate per data (più recenti prima)
    func estraiComunicazioniRilevanti(da sinistro: Sinistro) -> [ComunicazioneEstratta] {
        let entries = sinistro.diarioArray
        
        return entries
            .filter { isEntryRilevante($0) }
            .map { convertToEstrazione($0) }
            .sorted { $0.data > $1.data }
    }
    
    /// Estrae le comunicazioni filtrate per parole chiave specifiche
    /// - Parameters:
    ///   - sinistro: Il sinistro da cui estrarre
    ///   - paroleChiave: Parole chiave da cercare nel contenuto
    /// - Returns: Array di comunicazioni che contengono le parole chiave
    func estraiComunicazioniConParoleChiave(da sinistro: Sinistro, paroleChiave: [String]) -> [ComunicazioneEstratta] {
        let comunicazioni = estraiComunicazioniRilevanti(da: sinistro)
        
        return comunicazioni.filter { comunicazione in
            let contenutoLower = comunicazione.contenuto.lowercased()
            return paroleChiave.contains { contenutoLower.contains($0.lowercased()) }
        }
    }
    
    /// Cerca comunicazioni che indicano un rifiuto dell'assicurato
    /// - Parameter sinistro: Il sinistro da analizzare
    /// - Returns: Comunicazioni che indicano rifiuto, se presenti
    func cercaComunicazioniRifiuto(da sinistro: Sinistro) -> [ComunicazioneEstratta] {
        let paroleChiaveRifiuto = [
            "rifiuta", "non accetta", "non intende", "respinge",
            "non concorda", "contesta", "non è d'accordo", "reclama"
        ]
        return estraiComunicazioniConParoleChiave(da: sinistro, paroleChiave: paroleChiaveRifiuto)
    }
    
    /// Cerca comunicazioni con l'agenzia
    /// - Parameter sinistro: Il sinistro da analizzare
    /// - Returns: Comunicazioni che coinvolgono l'agenzia
    func cercaComunicazioniAgenzia(da sinistro: Sinistro) -> [ComunicazioneEstratta] {
        let comunicazioni = estraiComunicazioniRilevanti(da: sinistro)
        
        return comunicazioni.filter { comunicazione in
            let contenutoLower = comunicazione.contenuto.lowercased()
            return contenutoLower.contains("agenzia") ||
                   contenutoLower.contains("agente") ||
                   comunicazione.titolo?.lowercased().contains("agenzia") == true
        }
    }
    
    /// Estrae un sunto delle ragioni addotte dall'assicurato per il rifiuto
    /// - Parameter sinistro: Il sinistro da analizzare
    /// - Returns: Stringa con il sunto delle ragioni, nil se non trovate
    func estraiRagioniRifiuto(da sinistro: Sinistro) -> String? {
        let comunicazioniRifiuto = cercaComunicazioniRifiuto(da: sinistro)
        
        guard !comunicazioniRifiuto.isEmpty else { return nil }
        
        // Prendi la comunicazione più recente che contiene le ragioni
        for comunicazione in comunicazioniRifiuto {
            let estratto = estraiMotivazione(da: comunicazione.contenuto)
            if !estratto.isEmpty {
                return sintetizzaMotivazione(estratto)
            }
        }
        
        return nil
    }
    
    /// Cerca la data di comunicazione con l'agenzia riguardo il rifiuto
    /// - Parameter sinistro: Il sinistro da analizzare
    /// - Returns: Data della comunicazione con l'agenzia, nil se non trovata
    func cercaDataComunicazioneAgenzia(da sinistro: Sinistro) -> Date? {
        let comunicazioniAgenzia = cercaComunicazioniAgenzia(da: sinistro)
        
        // Cerca comunicazioni che parlano di rifiuto o conferma
        let paroleChiave = ["conferma", "rifiuto", "non accetta", "esito"]
        
        for comunicazione in comunicazioniAgenzia {
            let contenutoLower = comunicazione.contenuto.lowercased()
            if paroleChiave.contains(where: { contenutoLower.contains($0) }) {
                return comunicazione.data
            }
        }
        
        return comunicazioniAgenzia.first?.data
    }
    
    /// Genera un riassunto delle comunicazioni per la relazione peritale
    /// - Parameters:
    ///   - sinistro: Il sinistro da analizzare
    ///   - maxCaratteri: Limite massimo di caratteri per il riassunto
    /// - Returns: Riassunto delle comunicazioni
    func generaRiassuntoComunicazioni(da sinistro: Sinistro, maxCaratteri: Int = 500) -> String {
        let comunicazioni = estraiComunicazioniRilevanti(da: sinistro)
        
        guard !comunicazioni.isEmpty else { return "" }
        
        var riassunto = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        for comunicazione in comunicazioni.prefix(5) { // Max 5 comunicazioni
            let dataStr = dateFormatter.string(from: comunicazione.data)
            
            // Non usare emoji - sono documenti professionali
            var riga = "\(dataStr): "
            
            if let titolo = comunicazione.titolo, !titolo.isEmpty {
                riga += titolo
            } else {
                // Prendi prime parole del contenuto
                let preview = String(comunicazione.contenuto.prefix(80))
                riga += preview.replacingOccurrences(of: "\n", with: " ")
                if comunicazione.contenuto.count > 80 { riga += "..." }
            }
            
            if riassunto.count + riga.count + 2 > maxCaratteri { break }
            
            riassunto += (riassunto.isEmpty ? "" : "\n") + riga
        }
        
        return riassunto
    }
    
    // MARK: - Helpers privati
    
    private func isEntryRilevante(_ entry: DiarioEntry) -> Bool {
        let tipoRaw = entry.tipo.rawValue
        return tipiRilevanti.contains(tipoRaw) && !tipiDaEscludere.contains(tipoRaw)
    }
    
    private func convertToEstrazione(_ entry: DiarioEntry) -> ComunicazioneEstratta {
        let contenuto = entry.contenutoCompleto ?? entry.riassunto ?? entry.testo
        
        return ComunicazioneEstratta(
            id: entry.id,
            data: entry.timestamp,
            tipo: entry.tipo.rawValue,
            titolo: entry.titolo,
            contenuto: contenuto,
            emailMessageId: entry.emailMessageId,
            whatsAppChatId: entry.whatsAppChatId
        )
    }
    
    private func estraiMotivazione(da contenuto: String) -> String {
        // Cerca pattern comuni per le motivazioni
        let patterns = [
            "perché", "in quanto", "poiché", "dato che", "visto che",
            "motivo", "ragione", "ritiene che", "sostiene che"
        ]
        
        let contenutoLower = contenuto.lowercased()
        
        for pattern in patterns {
            if let range = contenutoLower.range(of: pattern) {
                let startIndex = range.lowerBound
                let endIndex = contenuto.index(startIndex, offsetBy: min(200, contenuto.distance(from: startIndex, to: contenuto.endIndex)))
                return String(contenuto[startIndex..<endIndex])
            }
        }
        
        // Fallback: prendi le prime 150 parole rilevanti
        return String(contenuto.prefix(200))
    }
    
    private func sintetizzaMotivazione(_ motivazione: String) -> String {
        // Pulisci e sintetizza la motivazione
        var risultato = motivazione
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        
        // Rimuovi punteggiatura finale incompleta
        while risultato.hasSuffix(",") || risultato.hasSuffix(";") {
            risultato = String(risultato.dropLast())
        }
        
        // Aggiungi punteggiatura se manca
        if !risultato.hasSuffix(".") && !risultato.hasSuffix("!") && !risultato.hasSuffix("?") {
            risultato += "."
        }
        
        return risultato
    }
    
    private func emojiPerTipo(_ tipo: String) -> String {
        switch tipo {
        case "Email": return "📧"
        case "WhatsApp": return "💬"
        case "Nota Utente": return "📝"
        default: return "•"
        }
    }
}

// MARK: - Modello Comunicazione Estratta

struct ComunicazioneEstratta: Identifiable {
    let id: UUID
    let data: Date
    let tipo: String
    let titolo: String?
    let contenuto: String
    let emailMessageId: String?
    let whatsAppChatId: String?
    
    /// Formatta la data in italiano
    var dataFormattata: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: data)
    }
}
