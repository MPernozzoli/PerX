import Foundation

/// Feature flags per la distribuzione macOS diretta con Developer ID.
enum BuildFeatures {
    // La route Ollama locale e disponibile anche in Release fuori Mac App Store.
    static let localOllamaEnabled: Bool = true
    
    // WhatsApp sempre abilitato (funziona tramite Hub remoto)
    static let localWhatsAppServerEnabled: Bool = true
}
