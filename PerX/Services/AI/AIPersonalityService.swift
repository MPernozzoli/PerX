import Foundation

/// Servizio per gestire le personalità AI (Elettra e Sparky)
class AIPersonalityService {
    static let shared = AIPersonalityService()
    
    private let ragService = RAGService.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Seleziona la personalità appropriata per un task
    func selectPersonality(for taskType: AITaskType) -> AIPersonality {
        switch taskType {
        case .emailSummary, .chat:
            return .elettra
        case .documentAnalysis, .textAnalysis, .documentExtraction:
            return .sparky
        case .textGeneration:
            // Default a Elettra, può essere sovrascritto
            return .elettra
        case .imageAnalysis:
            return .sparky
        case .guardrailing:
            return .elettra
        }
    }
    
    /// Costruisce un prompt con la personalità appropriata
    func buildPrompt(
        basePrompt: String,
        personality: AIPersonality,
        context: String? = nil,
        taskType: AITaskType
    ) -> String {
        let personalityContext = getPersonalitySystemPrompt(personality: personality)
        let ragContext = context ?? ragService.buildContext(for: basePrompt, personality: personality)
        
        var fullPrompt = personalityContext
        
        if !ragContext.isEmpty {
            fullPrompt += "\n\n" + ragContext
        }
        
        fullPrompt += "\n\nRichiesta utente: \(basePrompt)"
        
        // Aggiungi istruzioni specifiche per tipo di task
        fullPrompt += "\n\n" + getTaskSpecificInstructions(taskType: taskType, personality: personality)
        
        return fullPrompt
    }
    
    /// Ottiene il prompt di sistema per una personalità
    func getPersonalitySystemPrompt(personality: AIPersonality) -> String {
        switch personality {
        case .elettra:
            return """
            Sei Elettra, l'assistente front desk professionale per un'azienda di perizie assicurative in Italia.
            
            Il tuo ruolo:
            - Gestire comunicazioni con clienti e compagnie assicurative
            - Organizzare e pianificare attività
            - Fornire supporto amministrativo
            - Essere il punto di contatto principale per informazioni generali
            
            Il tuo stile:
            - Professionale ma amichevole
            - Chiaro e conciso
            - Orientato all'efficienza
            - Empatico quando necessario
            - Sempre cortese e rispettoso
            
            Usa sempre l'italiano e mantieni un tono appropriato per il contesto aziendale.
            """
            
        case .sparky:
            return """
            Sei Sparky, l'assistente tecnico specializzato per un'azienda di perizie assicurative in Italia.
            
            Il tuo ruolo:
            - Analizzare documenti tecnici e perizie
            - Valutare danni e stime
            - Fornire analisi tecniche dettagliate
            - Supportare nella redazione di perizie tecniche
            - Verificare conformità normative e tecniche
            
            Il tuo stile:
            - Tecnico e preciso
            - Dettagliato e approfondito
            - Basato su dati e fatti
            - Professionale e obiettivo
            - Focalizzato sulla qualità tecnica
            
            Usa sempre l'italiano e mantieni un linguaggio tecnico appropriato quando necessario.
            """
        }
    }
    
    // MARK: - Private Implementation
    
    private func getTaskSpecificInstructions(taskType: AITaskType, personality: AIPersonality) -> String {
        switch (taskType, personality) {
        case (.emailSummary, .elettra):
            return "Genera un riassunto conciso dell'email, evidenziando i punti chiave e le azioni richieste. Mantieni un tono professionale."
            
        case (.documentAnalysis, .sparky):
            return "Analizza il documento in dettaglio. Estrai tutte le informazioni tecniche rilevanti: importi, date, descrizioni tecniche, riferimenti normativi. Fornisci un'analisi strutturata e completa."
            
        case (.textGeneration, .elettra):
            return "Genera una risposta appropriata per il contesto. Mantieni un tono professionale e amichevole, sii conciso ma completo."
            
        case (.textGeneration, .sparky):
            return "Genera una risposta tecnica dettagliata. Fornisci informazioni precise, verificate e ben strutturate."
            
        case (.imageAnalysis, .sparky):
            return "Analizza l'immagine in dettaglio. Identifica danni, componenti, anomalie. Fornisci una descrizione tecnica precisa e strutturata."
            
        case (.chat, .elettra):
            return "Rispondi in modo professionale e utile. Se non conosci qualcosa, ammettilo e offri di cercare informazioni."
            
        case (.chat, .sparky):
            return "Fornisci una risposta tecnica precisa. Se necessario, fai riferimento a normative o procedure specifiche."
            
        default:
            return "Completa il task in modo appropriato per il tuo ruolo."
        }
    }
}

