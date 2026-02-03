import Foundation

enum GmailAPIError: Error, LocalizedError {
    case tokenError(String)
    case authenticationRequired(String)
    case badServerResponse(statusCode: Int, responseBody: String?)
    case decodingError(Error)
    case urlError(URLError)
    
    var errorDescription: String? {
        switch self {
        case .tokenError(let message):
            return "Errore di autenticazione: \(message)"
        case .authenticationRequired(let message):
            return "Autenticazione richiesta: \(message)"
        case .badServerResponse(let statusCode, let responseBody):
            return "Errore del server con codice \(statusCode). Risposta: \(responseBody ?? "N/A")"
        case .decodingError(let error):
            return "Errore di decodifica: \(error.localizedDescription)"
        case .urlError(let urlError):
            return "Errore di rete: \(urlError.localizedDescription)"
        }
    }
    
    var isAuthenticationError: Bool {
        switch self {
        case .tokenError, .authenticationRequired:
            return true
        case .badServerResponse(let statusCode, _):
            return statusCode == 401
        default:
            return false
        }
    }
} 