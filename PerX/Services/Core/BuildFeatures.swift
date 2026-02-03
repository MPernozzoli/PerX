import Foundation

/// Feature flags guidati dalla build (DEBUG vs Release).
///
/// Nota: in produzione disattiviamo solo Ollama locale.
/// WhatsApp ora funziona tramite Hub (remoto) quindi è sempre abilitato.
enum BuildFeatures {
    #if DEBUG
    static let localOllamaEnabled: Bool = true
    #else
    static let localOllamaEnabled: Bool = false
    #endif
    
    // WhatsApp sempre abilitato (funziona tramite Hub remoto)
    static let localWhatsAppServerEnabled: Bool = true
}

