import Foundation

struct DiarioEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let testo: String
    let tipo: TipoEntry
    var titolo: String?
    var riassunto: String?
    var contenutoCompleto: String?
    var emailMessageId: String? // Per associare l'entry all'email originale
    var processedEmailDate: Date? // Data dell'email processata (per evitare doppioni)
    var whatsAppChatId: String? // Per associare l'entry alla chat WhatsApp
    var whatsAppMessageIds: [String]? // ID dei messaggi inclusi in questa entry
    var processedWhatsAppDate: Date? // Data dell'ultimo messaggio processato
    var generatedTaskId: UUID? // ID del task generato da questa entry (se presente)
    var createdByEmail: String? // Email di chi ha creato la entry (per notifiche a owner)
    
    enum TipoEntry: String, Codable {
        case assegnazione = "Assegnazione"
        case aggiornamento = "Aggiornamento"
        case email = "Email"
        case whatsapp = "WhatsApp"
        case notaUtente = "Nota Utente"
        case cambioStato = "Cambio Stato"
        case sistema = "Sistema"
    }
    
    init(testo: String, tipo: TipoEntry, createdByEmail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.testo = testo
        self.tipo = tipo
        self.titolo = nil
        self.riassunto = nil
        self.contenutoCompleto = nil
        self.emailMessageId = nil
        self.processedEmailDate = nil
        self.whatsAppChatId = nil
        self.whatsAppMessageIds = nil
        self.processedWhatsAppDate = nil
        self.generatedTaskId = nil
        self.createdByEmail = createdByEmail
    }
    
    init(id: UUID = UUID(), timestamp: Date, tipo: TipoEntry, titolo: String?, riassunto: String, contenutoCompleto: String, emailMessageId: String? = nil, processedEmailDate: Date? = nil, whatsAppChatId: String? = nil, whatsAppMessageIds: [String]? = nil, processedWhatsAppDate: Date? = nil, generatedTaskId: UUID? = nil, createdByEmail: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.tipo = tipo
        self.testo = riassunto // Per retrocompatibilità
        self.titolo = titolo
        self.riassunto = riassunto
        self.contenutoCompleto = contenutoCompleto
        self.emailMessageId = emailMessageId
        self.processedEmailDate = processedEmailDate
        self.whatsAppChatId = whatsAppChatId
        self.whatsAppMessageIds = whatsAppMessageIds
        self.processedWhatsAppDate = processedWhatsAppDate
        self.generatedTaskId = generatedTaskId
        self.createdByEmail = createdByEmail
    }
} 