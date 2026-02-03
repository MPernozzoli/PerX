import Foundation

/// Servizio globale per inviare messaggi WhatsApp da qualsiasi parte dell'app
@MainActor
class WhatsAppMessagingService {
    static let shared = WhatsAppMessagingService()
    
    private let whatsappService = WhatsAppService.shared
    
    private init() {}
    
    /// Invia un messaggio WhatsApp
    /// - Parameters:
    ///   - phoneNumber: Numero di telefono (formato: 393123456789)
    ///   - message: Testo del messaggio
    /// - Returns: ID del messaggio inviato
    func sendMessage(to phoneNumber: String, message: String) async throws -> String {
        guard whatsappService.isConnected else {
            throw WhatsAppError.notConnected
        }
        
        return try await whatsappService.sendMessage(to: phoneNumber, body: message)
    }
    
    /// Verifica se WhatsApp è connesso
    var isConnected: Bool {
        whatsappService.isConnected
    }
}

