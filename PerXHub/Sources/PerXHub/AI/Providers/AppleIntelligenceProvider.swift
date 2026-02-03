import Foundation

// ============================================================================
// MARK: - Apple Intelligence Provider
// Interfaccia per Apple Foundation Models (macOS 26+)
// NOTA: Disabilitato fino a quando macOS 26 non sarà disponibile
// ============================================================================

public actor AppleIntelligenceProvider {
    
    private var _isAvailable: Bool = false
    
    public init() {
        // Apple Intelligence non ancora disponibile
        _isAvailable = false
        print("[AppleIntelligenceProvider] ⚠️ Apple Intelligence non ancora disponibile (richiede macOS 26+)")
    }
    
    // MARK: - Availability
    
    public var isAvailable: Bool {
        get async {
            return _isAvailable
        }
    }
    
    // MARK: - Generation
    
    public func generate(prompt: String) async throws -> String {
        throw AppleIntelligenceError.notAvailable
    }
    
    // MARK: - Summarization
    
    public func summarize(text: String) async throws -> String {
        throw AppleIntelligenceError.notAvailable
    }
    
    // MARK: - Email Analysis
    
    public func analyzeEmailIntent(
        subject: String,
        body: String
    ) async throws -> String {
        throw AppleIntelligenceError.notAvailable
    }
}

// MARK: - Errors

public enum AppleIntelligenceError: Error, LocalizedError {
    case notAvailable
    case sessionError
    case generationFailed
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence non disponibile su questo sistema (richiede macOS 26+)"
        case .sessionError:
            return "Errore nella creazione della sessione"
        case .generationFailed:
            return "Generazione fallita"
        }
    }
}
