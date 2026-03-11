import Foundation
import PerXCore
import SQLite

// ============================================================================
// MARK: - StatoManager (Hub version)
// Gestisce transizioni di stato e validazioni per i sinistri sull'Hub
// ============================================================================

public actor HubStatoManager {
    public static let shared = HubStatoManager()
    
    private let db = DatabaseManager.shared
    
    private init() {
        print("[HubStatoManager] ✅ Inizializzato sull'Hub")
    }
    
    // MARK: - State Transitions
    
    /// Cambia lo stato di un sinistro
    public func changeState(
        sinistroRef: String,
        to newState: StatoSinistro,
        reason: String? = nil,
        userEmail: String? = nil
    ) async throws {
        let conn = try await db.db()
        
        // Ottieni stato corrente
        let currentState = try await getCurrentState(sinistroRef: sinistroRef)
        
        // Valida transizione
        if let current = currentState {
            guard canTransition(from: current, to: newState) else {
                throw StatoManagerError.invalidTransition(
                    from: current.descrizione,
                    to: newState.descrizione
                )
            }
        }
        
        // Aggiorna stato nel database sinistri (se esiste tabella)
        // Per ora log solo - la tabella sinistri sarà aggiunta in Fase 4
        print("[HubStatoManager] 🔄 Stato cambiato: \(sinistroRef) → \(newState.descrizione)")
        
        // Aggiorna date automatiche in base allo stato
        let now = Date()
        try await updateDatesForState(
            sinistroRef: sinistroRef,
            newState: newState,
            date: now
        )
        
        // Log cambio stato
        print("[HubStatoManager] ✅ \(sinistroRef): \(currentState?.descrizione ?? "N/A") → \(newState.descrizione)")
        
        // Trigger sync CloudKit
        await syncToCloudKit(sinistroRef: sinistroRef)
    }
    
    /// Ottiene lo stato corrente di un sinistro
    public func getCurrentState(sinistroRef: String) async throws -> StatoSinistro? {
        // TODO: Query da database
        // Per ora restituisce nil (implementazione in Fase 4)
        return nil
    }
    
    // MARK: - Validation
    
    /// Verifica se una transizione è valida
    public func canTransition(from: StatoSinistro, to: StatoSinistro) -> Bool {
        return from.validTransitions.contains(to)
    }
    
    /// Valida transizione con motivazione
    public func validateTransition(
        from: StatoSinistro,
        to: StatoSinistro,
        sinistroRef: String
    ) async -> TransitionValidation {
        // Verifica base
        guard canTransition(from: from, to: to) else {
            return TransitionValidation(
                isValid: false,
                reason: "Transizione non permessa da \(from.descrizione) a \(to.descrizione)"
            )
        }
        
        // Validazioni condizionali
        switch to {
        case .periziaDaEseguireDocumentale:
            // Solo da inAttesaDocumentale
            if from != .inAttesaDocumentale {
                return TransitionValidation(
                    isValid: false,
                    reason: "Perizia documentale solo da stato 'In attesa documentale'"
                )
            }
            
        case .videoperiziaFissata:
            // Solo da videoperiziaDaFissare
            if from != .videoperiziaDaFissare {
                return TransitionValidation(
                    isValid: false,
                    reason: "Videoperizia fissata solo da stato 'Videoperizia da fissare'"
                )
            }
            
        case .richiestaRevisione:
            // Solo da chiusa
            if from != .chiusa {
                return TransitionValidation(
                    isValid: false,
                    reason: "Richiesta revisione solo da stato 'Chiusa'"
                )
            }
            
        default:
            break
        }
        
        return TransitionValidation(isValid: true, reason: nil)
    }
    
    // MARK: - Automatic Date Updates
    
    private func updateDatesForState(
        sinistroRef: String,
        newState: StatoSinistro,
        date: Date
    ) async throws {
        // Determina quali date aggiornare in base al nuovo stato
        switch newState {
        case .attoInviato:
            // TODO: Aggiorna dataInvioAtto
            print("[HubStatoManager] 📅 dataInvioAtto → \(date)")
            
        case .esitoComunicato:
            // TODO: Aggiorna dataComunicazioneEsito
            print("[HubStatoManager] 📅 dataComunicazioneEsito → \(date)")
            
        case .attoRicevutoSottoscritto:
            // TODO: Aggiorna dataRitornoAtto, dataRicezioneAttoSottoscritto
            print("[HubStatoManager] 📅 dataRitornoAtto, dataRicezioneAttoSottoscritto → \(date)")
            
        case .accettataVerbalmente:
            // TODO: Aggiorna dataAccettazioneVerbale
            print("[HubStatoManager] 📅 dataAccettazioneVerbale → \(date)")
            
        case .chiusa:
            // TODO: Aggiorna dataChiusura
            print("[HubStatoManager] 📅 dataChiusura → \(date)")
            
        case .revocata:
            // TODO: Aggiorna dataRevoca
            print("[HubStatoManager] 📅 dataRevoca → \(date)")
            
        default:
            break
        }
    }
    
    // MARK: - CloudKit Sync
    
    private func syncToCloudKit(sinistroRef: String) async {
        // TODO: Trigger sync CloudKit
        print("[HubStatoManager] ☁️ Sync CloudKit scheduled: \(sinistroRef)")
    }
    
    // MARK: - State Resolution
    
    /// Risolve la variante corretta di uno stato in base al contesto
    public func resolveStateVariant(
        for targetGroup: StateGroup,
        currentState: StatoSinistro
    ) -> StatoSinistro {
        let currentVariant = currentState.variant
        
        switch targetGroup {
        case .inGestione:
            switch currentVariant {
            case .videoperizia: return .inGestioneVideoperizia
            case .documentale: return .inGestioneDocumentale
            default: return .inGestione
            }
            
        case .periziaDaEseguire:
            switch currentVariant {
            case .documentale: return .periziaDaEseguireDocumentale
            case .noResidui: return .periziaDaEseguireNoResidui
            default: return .periziaDaEseguire
            }
            
        case .inAttesa:
            return .inAttesaDocumentale
            
        default:
            return targetGroup.members.first ?? .daScaricare
        }
    }
    
    /// Stati disponibili per transizione da uno stato corrente
    public func availableTransitions(from state: StatoSinistro) -> [StatoSinistro] {
        return state.validTransitions
    }
    
    // MARK: - Filtri per Tipo Perizia (Documentale vs Tradizionale)
    
    /// Restituisce gli stati disponibili filtrati in base al tipo di perizia del sinistro
    /// - Parameter isTradizionale: true se il sinistro prevede sopralluogo (ha cartella Sopralluogo)
    /// - Returns: Array di stati compatibili con il tipo di perizia
    public func availableStatesForTipoPerizia(isTradizionale: Bool) -> [StatoSinistro] {
        return StatoSinistro.allCases.filter { $0.isCompatible(withTipoPerizia: isTradizionale) }
    }
    
    /// Restituisce le transizioni valide filtrate in base al tipo di perizia
    /// - Parameters:
    ///   - state: Lo stato corrente
    ///   - isTradizionale: true se il sinistro prevede sopralluogo
    /// - Returns: Transizioni valide e compatibili con il tipo di perizia
    public func validTransitionsForTipoPerizia(from state: StatoSinistro, isTradizionale: Bool) -> [StatoSinistro] {
        return state.validTransitions.filter { $0.isCompatible(withTipoPerizia: isTradizionale) }
    }
    
    /// Determina lo stato iniziale appropriato in base al tipo di perizia e presenza foto
    /// - Parameters:
    ///   - hasSopralluogoFolder: true se è stata rilevata la cartella "Sopralluogo"
    ///   - hasFoto: true se sono presenti foto nella cartella
    /// - Returns: Lo stato iniziale appropriato
    public func determineInitialState(hasSopralluogoFolder: Bool, hasFoto: Bool) -> StatoSinistro {
        if hasSopralluogoFolder {
            // Sinistro TRADIZIONALE (con sopralluogo)
            return .periziaDaEseguire
        } else {
            // Sinistro DOCUMENTALE (senza sopralluogo)
            if hasFoto {
                return .periziaDaEseguireDocumentale
            } else {
                return .inAttesaDocumentale
            }
        }
    }
    
    /// Trova lo stato equivalente quando cambia il tipo di perizia
    /// - Parameters:
    ///   - currentState: Lo stato corrente
    ///   - isTradizionale: Il nuovo tipo di perizia (true = tradizionale con sopralluogo)
    /// - Returns: Lo stato equivalente per il nuovo tipo, o nil se non esiste
    public func equivalentStateForTipoPerizia(
        currentState: StatoSinistro,
        isTradizionale: Bool
    ) -> StatoSinistro? {
        // Se già compatibile, restituisci lo stesso stato
        if currentState.isCompatible(withTipoPerizia: isTradizionale) {
            return currentState
        }
        
        // Usa la funzione del modello StatoSinistro
        return currentState.equivalentState(forTipoPerizia: isTradizionale)
    }
}

// MARK: - Types

/// Risultato validazione transizione
public struct TransitionValidation: Sendable {
    public let isValid: Bool
    public let reason: String?
    
    public init(isValid: Bool, reason: String?) {
        self.isValid = isValid
        self.reason = reason
    }
}

/// Errori StatoManager
public enum StatoManagerError: Error, LocalizedError {
    case invalidTransition(from: String, to: String)
    case sinistroNotFound(String)
    case databaseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Transizione non valida: da '\(from)' a '\(to)'"
        case .sinistroNotFound(let ref):
            return "Sinistro non trovato: \(ref)"
        case .databaseError(let msg):
            return "Errore database: \(msg)"
        }
    }
}
