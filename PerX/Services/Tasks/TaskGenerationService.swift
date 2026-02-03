import Foundation

/// Servizio per la generazione automatica di task da transizioni di stato
class TaskGenerationService {
    static let shared = TaskGenerationService()
    
    private let workScheduleManager = WorkScheduleManager.shared
    
    private init() {}
    
    /// Struttura per definire una task da generare
    struct TaskDefinition {
        let title: String
        let description: String
        let metadata: [String: AnyCodable]
    }
    
    /// Ottiene la task da generare per una transizione di stato
    func getTaskForTransition(
        from oldState: StatoManager.StatoSinistro,
        to newState: StatoManager.StatoSinistro,
        sinistro: Sinistro
    ) -> TaskDefinition? {
        // Verifica assegnazione: se non assegnato a nessun perito, non generare task
        let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assignedEmail.isEmpty else {
            return nil
        }
        
        switch (oldState, newState) {
        case (.inAttesaDocumentale, .inGestioneDocumentale),
             (.inAttesaDaAssicurato, .inGestione),
             (.inAttesaDaAgenzia, .inGestione):
            return TaskDefinition(
                title: "Riprendere gestione sinistro",
                description: "Riprendere la gestione del sinistro \(sinistro.riferimento ?? "")",
                metadata: ["transition": AnyCodable("attesa_to_gestione")]
            )
            
        case (.attoRicevutoSottoscritto, .inControllo):
            return TaskDefinition(
                title: "Verificare atto sottoscritto",
                description: "Verificare l'atto sottoscritto per il sinistro \(sinistro.riferimento ?? "")",
                metadata: ["transition": AnyCodable("attoRicevuto_to_inControllo")]
            )
            
        case (.controllata, .chiusa):
            return TaskDefinition(
                title: "Chiudere sinistro",
                description: "Completare la chiusura del sinistro \(sinistro.riferimento ?? "")",
                metadata: ["transition": AnyCodable("controllata_to_chiusa")]
            )
            
        case (.inAttesaDocumentale, .periziaDaEseguireDocumentale),
             (.inAttesaDocumentale, .inGestioneDocumentale):
            return TaskDefinition(
                title: "Verificare documentazione",
                description: "Verificare la documentazione ricevuta per il sinistro \(sinistro.riferimento ?? "")",
                metadata: ["transition": AnyCodable("attesaDoc_to_doc"), "reason": AnyCodable("documentazione_ricevuta")]
            )
            
        case (.attoInviato, .attoRicevutoSottoscritto):
            return TaskDefinition(
                title: "Verificare atto sottoscritto",
                description: "Verificare che l'atto sia stato restituito correttamente sottoscritto per \(sinistro.riferimento ?? "")",
                metadata: ["transition": AnyCodable("attoInviato_to_attoSottoscritto")]
            )
            
        // Transizioni verso stati di autorizzazione
        case (_, .richiestaAutorizzazione):
            return TaskDefinition(
                title: "Sollecitare autorizzazione",
                description: "Sollecitare l'autorizzazione per il sinistro \(sinistro.riferimento ?? "")",
                metadata: [
                    "transition": AnyCodable("to_richiestaAutorizzazione"),
                    "pendingApproval": AnyCodable(true)
                ]
            )
            
        case (_, .supervisioneNonConcordata):
            return TaskDefinition(
                title: "Sollecitare supervisione non concordata",
                description: "Sollecitare la supervisione per perizia non concordata - sinistro \(sinistro.riferimento ?? "")",
                metadata: [
                    "transition": AnyCodable("to_supervisioneNonConcordata"),
                    "pendingApproval": AnyCodable(true),
                    "nonConcordata": AnyCodable(true)
                ]
            )
            
        default:
            return nil
        }
    }
    
    // MARK: - Task Sollecito Fine Mese
    
    /// Genera una task di sollecito controllo se il sinistro è in stato di autorizzazione
    /// e mancano 5 giorni lavorativi o meno alla fine del mese
    func shouldGenerateSollecitoControlloTask(for sinistro: Sinistro) -> TaskDefinition? {
        // Verifica assegnazione: se non assegnato a nessun perito, non generare task
        let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assignedEmail.isEmpty else {
            return nil
        }
        
        guard let statoDesc = sinistro.stato else { return nil }
        
        // Verifica se il sinistro è in uno stato di autorizzazione
        let statiAutorizzazione = [
            StatoManager.StatoSinistro.richiestaAutorizzazione.descrizione,
            StatoManager.StatoSinistro.supervisioneNonConcordata.descrizione
        ]
        
        guard statiAutorizzazione.contains(statoDesc) else { return nil }
        
        // Verifica se siamo a 5 giorni lavorativi dalla fine del mese
        guard isWithinWorkingDaysFromEndOfMonth(days: 5) else { return nil }
        
        return TaskDefinition(
            title: "Sollecitare controllo (fine mese)",
            description: "Sollecitare il controllo per chiusura/fatturazione entro fine mese - sinistro \(sinistro.riferimento ?? "")",
            metadata: [
                "type": AnyCodable("sollecito_fine_mese"),
                "pendingApproval": AnyCodable(true)
            ]
        )
    }
    
    /// Verifica se siamo entro X giorni lavorativi dalla fine del mese corrente
    /// Usa WorkScheduleManager che integra ItalianCalendarService per festività italiane
    private func isWithinWorkingDaysFromEndOfMonth(days: Int) -> Bool {
        let workingDaysRemaining = workScheduleManager.workingDaysUntilEndOfMonth(from: Date())
        return workingDaysRemaining <= days
    }
}

