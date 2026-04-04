import Foundation

/// Manager centralizzato per le regole di business delle compagnie e agenzie
/// Estende e centralizza la logica di CompagniaService con regole più complesse
@MainActor
class RuleManager: ObservableObject {
    static let shared = RuleManager()
    
    private let compagniaService = CompagniaService.shared
    
    private init() {
        loadCustomRules()
        print("[RuleManager] ✅ Inizializzato")
    }
    
    // MARK: - Custom Rules Storage
    
    private var customCompanyRules: [String: CompanyRuleSet] = [:]
    private var customAgencyRules: [String: AgencyRuleSet] = [:]
    
    private let customRulesKey = "customBusinessRules"
    
    // MARK: - Rule Sets
    
    /// Regole specifiche per compagnia
    struct CompanyRuleSet: Codable {
        let companyId: String
        var closureDeadlineDays: Int                    // Giorni target per chiusura
        var reminderAfterDays: Int                      // Giorni prima di sollecitare
        var requiresActSignature: Bool                  // Richiede atto firmato
        var useOutcomeAsActDate: Bool                   // Usa data esito come data atto
        var alwaysAttachLightningReport: Bool           // Allega sempre fulminazione
        var nomenclatureType: NomenclatureType          // Tipo nomenclatura file
        var allowedFileTypes: [String]                  // Tipi file accettati
        var maxFileSizeMB: Int                          // Dimensione max file in MB
        var requiresDocumentation: [DocumentationType]  // Documentazione obbligatoria
        
        enum NomenclatureType: String, Codable {
            case numeric = "numeric"                    // Zurich: riferimento_1, riferimento_2
            case descriptive = "descriptive"            // Generali: riferimento_concordata, riferimento_foto
            case hybrid = "hybrid"                      // Unipol: riferimento_perizia, riferimento_altro1
        }
        
        enum DocumentationType: String, Codable {
            case policy = "polizza"
            case photos = "foto"
            case locationPhotos = "foto_ubicazione"
            case receipts = "giustificativi"
            case estimate = "preventivo"
            case invoice = "fattura"
        }
    }
    
    /// Regole specifiche per agenzia (future)
    struct AgencyRuleSet: Codable {
        let agencyId: String
        var preferredContactMethod: ContactMethod       // Metodo contatto preferito
        var workingHours: WorkingHours?                 // Orari lavorativi
        var specialInstructions: String?                // Istruzioni speciali
        var priorityMultiplier: Double                  // Moltiplicatore priorità
        
        enum ContactMethod: String, Codable {
            case email = "email"
            case phone = "phone"
            case whatsapp = "whatsapp"
            case any = "any"
        }
        
        struct WorkingHours: Codable {
            let startHour: Int
            let endHour: Int
            let workDays: [Int]  // 1 = Domenica, 2 = Lunedì, etc.
        }
    }
    
    // MARK: - Default Rules
    
    /// Regole di default per compagnie
    private func getDefaultRules(for compagnia: Compagnia) -> CompanyRuleSet {
        switch compagnia {
        case .zurichItalia:
            return CompanyRuleSet(
                companyId: compagnia.rawValue,
                closureDeadlineDays: 20,
                reminderAfterDays: 7,
                requiresActSignature: false,
                useOutcomeAsActDate: true,
                alwaysAttachLightningReport: false,
                nomenclatureType: .numeric,
                allowedFileTypes: ["pdf", "jpg", "jpeg", "png"],
                maxFileSizeMB: 10,
                requiresDocumentation: [.policy, .photos]
            )
            
        case .cattolica, .generaliItalia:
            return CompanyRuleSet(
                companyId: compagnia.rawValue,
                closureDeadlineDays: 20,
                reminderAfterDays: 7,
                requiresActSignature: true,
                useOutcomeAsActDate: false,
                alwaysAttachLightningReport: false,
                nomenclatureType: .descriptive,
                allowedFileTypes: ["pdf", "jpg", "jpeg", "png", "doc", "docx"],
                maxFileSizeMB: 15,
                requiresDocumentation: [.policy, .photos, .receipts]
            )
            
        case .unipolItalia:
            return CompanyRuleSet(
                companyId: compagnia.rawValue,
                closureDeadlineDays: 15,
                reminderAfterDays: 5,
                requiresActSignature: true,
                useOutcomeAsActDate: false,
                alwaysAttachLightningReport: true,
                nomenclatureType: .hybrid,
                allowedFileTypes: ["pdf", "jpg", "jpeg"],
                maxFileSizeMB: 8,
                requiresDocumentation: [.policy, .photos, .estimate]
            )
            
        case .unknown:
            return CompanyRuleSet(
                companyId: compagnia.rawValue,
                closureDeadlineDays: 30,
                reminderAfterDays: 10,
                requiresActSignature: true,
                useOutcomeAsActDate: false,
                alwaysAttachLightningReport: false,
                nomenclatureType: .numeric,
                allowedFileTypes: ["pdf", "jpg", "jpeg", "png"],
                maxFileSizeMB: 10,
                requiresDocumentation: []
            )
        }
    }
    
    // MARK: - Rule Access
    
    /// Ottiene le regole per una compagnia
    func getRules(for compagnia: Compagnia) -> CompanyRuleSet {
        if let custom = customCompanyRules[compagnia.rawValue] {
            return custom
        }
        return getDefaultRules(for: compagnia)
    }
    
    /// Ottiene le regole per un sinistro (determina la compagnia dal sinistro)
    func getRules(for sinistro: Sinistro) -> CompanyRuleSet {
        let compagnia = Compagnia.detect(
            gruppo: sinistro.gruppo,
            compagnia: nil
        )
        return getRules(for: compagnia)
    }
    
    /// Ottiene le regole per un'agenzia
    func getAgencyRules(agencyId: String) -> AgencyRuleSet? {
        return customAgencyRules[agencyId]
    }
    
    // MARK: - State Transition Validation
    
    /// Valida una transizione di stato
    func validateStateTransition(
        from oldState: StatoManager.StatoSinistro,
        to newState: StatoManager.StatoSinistro,
        sinistro: Sinistro
    ) -> TransitionValidation {
        // Verifica se la transizione è permessa dallo StatoManager
        guard oldState.validTransitions.contains(newState) else {
            return TransitionValidation(
                isValid: false,
                requiresAction: false,
                reason: "Transizione da \(oldState.descrizione) a \(newState.descrizione) non permessa"
            )
        }
        
        let rules = getRules(for: sinistro)
        
        // Verifica regole specifiche per la transizione
        switch (oldState, newState) {
        case (_, .chiusa):
            // Verifica documentazione obbligatoria prima di chiudere
            if !hasRequiredDocumentation(sinistro, rules: rules) {
                return TransitionValidation(
                    isValid: false,
                    requiresAction: true,
                    reason: "Documentazione obbligatoria mancante",
                    requiredAction: .createTask,
                    taskDescription: "Completare documentazione prima della chiusura"
                )
            }
            
        case (_, .attoInviato):
            // Verifica se è richiesto atto firmato
            if rules.requiresActSignature {
                return TransitionValidation(
                    isValid: true,
                    requiresAction: true,
                    reason: "Atto richiede firma",
                    requiredAction: .createTask,
                    taskDescription: "Attendere atto firmato"
                )
            }
            
        default:
            break
        }
        
        return TransitionValidation(isValid: true, requiresAction: false)
    }
    
    struct TransitionValidation {
        let isValid: Bool
        let requiresAction: Bool
        var reason: String = ""
        var requiredAction: ActionType?
        var taskDescription: String?
        
        enum ActionType {
            case createTask
            case notify
            case block
        }
    }
    
    // MARK: - Deadline Calculation
    
    /// Calcola la deadline per un sinistro
    func calculateDeadline(for sinistro: Sinistro) -> Date? {
        let rules = getRules(for: sinistro)
        
        // Usa dataAssegnazione se disponibile, altrimenti dataIncarico
        let referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico ?? Date()
        
        return Calendar.current.date(
            byAdding: .day,
            value: rules.closureDeadlineDays,
            to: referenceDate
        )
    }
    
    /// Calcola quando inviare un sollecito
    func calculateReminderDate(for sinistro: Sinistro, from referenceDate: Date = Date()) -> Date? {
        let rules = getRules(for: sinistro)
        
        return Calendar.current.date(
            byAdding: .day,
            value: rules.reminderAfterDays,
            to: referenceDate
        )
    }
    
    /// Calcola la priorità basata sulla vicinanza alla deadline
    func calculatePriority(for sinistro: Sinistro) -> Double {
        guard let deadline = calculateDeadline(for: sinistro) else {
            return 0.5
        }
        
        let now = Date()
        let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0
        
        if daysRemaining <= 0 {
            return 1.0 // Scaduto
        } else if daysRemaining <= 3 {
            return 0.9
        } else if daysRemaining <= 7 {
            return 0.7
        } else if daysRemaining <= 14 {
            return 0.5
        } else {
            return 0.3
        }
    }
    
    // MARK: - File Nomenclature
    
    /// Delega la nomenclatura file a CompagniaService
    func generateFileName(
        sinistro: Sinistro,
        tipoFile: TipoFileCompagnia,
        progressivo: Int? = nil,
        concordata: Bool? = nil
    ) -> String {
        let compagnia = Compagnia.detect(
            gruppo: sinistro.gruppo,
            compagnia: nil
        )
        
        return compagniaService.generaNomeFile(
            compagnia: compagnia,
            riferimento: sinistro.riferimento ?? "",
            tipoFile: tipoFile,
            progressivo: progressivo,
            concordata: concordata
        )
    }
    
    // MARK: - Documentation Check
    
    /// Verifica se il sinistro ha la documentazione obbligatoria
    func hasRequiredDocumentation(_ sinistro: Sinistro, rules: CompanyRuleSet? = nil) -> Bool {
        let ruleSet = rules ?? getRules(for: sinistro)
        
        // Per ora ritorna sempre true - implementazione futura con FileTagManager
        // TODO: Integrare con FileTagManager per verificare i tag dei file
        return true
    }
    
    /// Ottiene la lista di documentazione mancante
    func getMissingDocumentation(_ sinistro: Sinistro) -> [CompanyRuleSet.DocumentationType] {
        let rules = getRules(for: sinistro)
        // TODO: Implementare verifica con FileTagManager
        return []
    }
    
    // MARK: - Intent to Action Mapping
    
    /// Mappa un intent evento a un'azione
    func mapIntentToAction(
        intent: ClaimEventIntent,
        sinistro: Sinistro,
        currentState: StatoManager.StatoSinistro
    ) -> ActionRecommendation {
        let rules = getRules(for: sinistro)
        
        switch intent {
        case .assignment:
            return ActionRecommendation(
                actionType: .autoStateChange,
                targetState: .istruzione,
                createTask: true,
                taskTitle: "Prendere in carico il triage del nuovo sinistro",
                priority: 0.8
            )
            
        case .revocation:
            return ActionRecommendation(
                actionType: .autoStateChange,
                targetState: .revocata,
                createTask: false,
                priority: 0.5
            )
            
        case .documentation:
            // Se in attesa documentale, potrebbe passare a perizia da eseguire
            if currentState == .inAttesaDocumentale {
                return ActionRecommendation(
                    actionType: .createTask,
                    targetState: nil,
                    createTask: true,
                    taskTitle: "Verificare documentazione ricevuta",
                    priority: 0.7
                )
            }
            return ActionRecommendation.noAction
            
        case .actReceived:
            return ActionRecommendation(
                actionType: .autoStateChange,
                targetState: .attoRicevutoSottoscritto,
                createTask: true,
                taskTitle: "Verificare atto e chiudere",
                priority: 0.9
            )
            
        case .reminder:
            return ActionRecommendation(
                actionType: .createTask,
                targetState: nil,
                createTask: true,
                taskTitle: "Gestire sollecito",
                priority: 0.8
            )
            
        case .userTask:
            return ActionRecommendation(
                actionType: .createTask,
                targetState: nil,
                createTask: true,
                priority: 0.7
            )
            
        default:
            return ActionRecommendation.noAction
        }
    }
    
    struct ActionRecommendation {
        enum ActionType {
            case noAction
            case autoStateChange
            case createTask
            case notify
        }
        
        let actionType: ActionType
        let targetState: StatoManager.StatoSinistro?
        let createTask: Bool
        var taskTitle: String?
        var taskDescription: String?
        var priority: Double
        
        static let noAction = ActionRecommendation(
            actionType: .noAction,
            targetState: nil,
            createTask: false,
            priority: 0.0
        )
    }
    
    // MARK: - Persistence
    
    private func loadCustomRules() {
        if let data = UserDefaults.standard.data(forKey: customRulesKey) {
            do {
                let decoded = try JSONDecoder().decode(CustomRulesStorage.self, from: data)
                customCompanyRules = decoded.companyRules
                customAgencyRules = decoded.agencyRules
            } catch {
                print("[RuleManager] ⚠️ Errore caricamento regole custom: \(error)")
            }
        }
    }
    
    private func saveCustomRules() {
        let storage = CustomRulesStorage(
            companyRules: customCompanyRules,
            agencyRules: customAgencyRules
        )
        
        if let encoded = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(encoded, forKey: customRulesKey)
        }
    }
    
    private struct CustomRulesStorage: Codable {
        let companyRules: [String: CompanyRuleSet]
        let agencyRules: [String: AgencyRuleSet]
    }
    
    // MARK: - Rule Management
    
    /// Aggiorna le regole per una compagnia
    func updateCompanyRules(_ rules: CompanyRuleSet) {
        customCompanyRules[rules.companyId] = rules
        saveCustomRules()
        objectWillChange.send()
    }
    
    /// Aggiorna le regole per un'agenzia
    func updateAgencyRules(_ rules: AgencyRuleSet) {
        customAgencyRules[rules.agencyId] = rules
        saveCustomRules()
        objectWillChange.send()
    }
    
    /// Resetta le regole di una compagnia ai default
    func resetCompanyRules(for compagnia: Compagnia) {
        customCompanyRules.removeValue(forKey: compagnia.rawValue)
        saveCustomRules()
        objectWillChange.send()
    }
}
