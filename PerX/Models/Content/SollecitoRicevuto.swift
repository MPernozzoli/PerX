import Foundation

/// Rappresenta un singolo sollecito ricevuto con dettagli
public struct SollecitoRicevuto: Codable, Identifiable {
    public let id: UUID
    public let dataRicezione: Date
    public let tipoMittente: TipoMittenteSollecito
    public var note: String?
    public var emailMessageId: String? // Riferimento all'email da cui è stato rilevato
    public var isManuale: Bool // true se loggato manualmente dall'utente
    
    public init(
        id: UUID = UUID(),
        dataRicezione: Date = Date(),
        tipoMittente: TipoMittenteSollecito,
        note: String? = nil,
        emailMessageId: String? = nil,
        isManuale: Bool = false
    ) {
        self.id = id
        self.dataRicezione = dataRicezione
        self.tipoMittente = tipoMittente
        self.note = note
        self.emailMessageId = emailMessageId
        self.isManuale = isManuale
    }
    
    /// Formatta la data in formato leggibile
    public var dataFormattata: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: dataRicezione)
    }
    
    /// Formatta la data in formato compatto
    public var dataCompatta: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: dataRicezione)
    }
}
