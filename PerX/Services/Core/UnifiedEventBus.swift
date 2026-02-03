import Foundation
import Combine

/// Bus centralizzato per la pubblicazione di eventi da tutti i canali
/// Sostituisce EmailEventBus con un sistema unificato per Email, WhatsApp e Note Utente
@MainActor
class UnifiedEventBus: ObservableObject {
    static let shared = UnifiedEventBus()
    
    // MARK: - Publishers
    
    /// Publisher principale per tutti gli eventi
    let eventPublisher = PassthroughSubject<any ClaimEvent, Never>()
    
    /// Publisher per eventi email
    let emailEventPublisher = PassthroughSubject<EmailClaimEvent, Never>()
    
    /// Publisher per eventi assegnazione
    let assignmentPublisher = PassthroughSubject<EmailAssignmentEvent, Never>()
    
    /// Publisher per eventi revoca
    let revocationPublisher = PassthroughSubject<EmailRevocationEvent, Never>()
    
    /// Publisher per eventi WhatsApp
    let whatsAppEventPublisher = PassthroughSubject<WhatsAppClaimEvent, Never>()
    
    /// Publisher per eventi nota utente
    let userNoteEventPublisher = PassthroughSubject<UserNoteClaimEvent, Never>()
    
    /// Publisher per eventi di sistema
    let systemEventPublisher = PassthroughSubject<SystemClaimEvent, Never>()
    
    // MARK: - Filtered Publishers
    
    /// Publisher per eventi che richiedono azione (filtrati)
    var actionableEventsPublisher: AnyPublisher<any ClaimEvent, Never> {
        eventPublisher
            .filter { event in
                // Filtra eventi che richiedono potenzialmente azione
                switch event {
                case let emailEvent as EmailClaimEvent:
                    return emailEvent.intent != .generic
                case let waEvent as WhatsAppClaimEvent:
                    return waEvent.intent != .generic
                case let noteEvent as UserNoteClaimEvent:
                    return !noteEvent.parsedTags.isEmpty
                case is SystemClaimEvent:
                    return true
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher per eventi di un sinistro specifico
    func eventsForSinistro(_ sinistroId: String) -> AnyPublisher<any ClaimEvent, Never> {
        eventPublisher
            .filter { $0.sinistroId == sinistroId }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Event History
    
    /// Ultimi eventi per debug/monitoring (max 100)
    @Published private(set) var recentEvents: [any ClaimEvent] = []
    private let maxHistorySize = 100
    
    /// Statistiche eventi
    @Published private(set) var eventStats: EventStats = EventStats()
    
    struct EventStats {
        var totalEvents: Int = 0
        var eventsBySource: [ClaimEventSource: Int] = [:]
        var eventsByIntent: [ClaimEventIntent: Int] = [:]
        var lastEventDate: Date?
        
        mutating func reset() {
            totalEvents = 0
            eventsBySource = [:]
            eventsByIntent = [:]
            lastEventDate = nil
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        print("[UnifiedEventBus] ✅ Inizializzato")
    }
    
    // MARK: - Publishing
    
    /// Pubblica un evento generico sul bus
    func publish(_ event: any ClaimEvent) {
        // Pubblica sul bus principale
        eventPublisher.send(event)
        
        // Routing su publisher specifici
        routeToSpecificPublisher(event)
        
        // Aggiorna storia
        addToHistory(event)
        
        // Aggiorna statistiche
        updateStats(event)
        
        // Log
        let eventType = String(describing: type(of: event))
        print("[UnifiedEventBus] 📬 Pubblicato: \(eventType) | Source: \(event.source.rawValue) | Sinistro: \(event.sinistroId ?? "N/A")")
    }
    
    /// Pubblica evento email
    func publishEmail(_ event: EmailClaimEvent) {
        emailEventPublisher.send(event)
        publish(event)
    }
    
    /// Pubblica evento assegnazione
    func publishAssignment(_ event: EmailAssignmentEvent) {
        print("[UnifiedEventBus] 📤 Pubblicazione evento assegnazione: \(event.riferimento) - data: \(event.assignmentDate)")
        assignmentPublisher.send(event)
        publish(event)
        print("[UnifiedEventBus] ✅ Evento assegnazione inviato a assignmentPublisher")
    }
    
    /// Pubblica evento revoca
    func publishRevocation(_ event: EmailRevocationEvent) {
        revocationPublisher.send(event)
        publish(event)
    }
    
    /// Pubblica evento WhatsApp
    func publishWhatsApp(_ event: WhatsAppClaimEvent) {
        whatsAppEventPublisher.send(event)
        publish(event)
    }
    
    /// Pubblica evento nota utente
    func publishUserNote(_ event: UserNoteClaimEvent) {
        userNoteEventPublisher.send(event)
        publish(event)
    }
    
    /// Pubblica evento di sistema
    func publishSystem(_ event: SystemClaimEvent) {
        systemEventPublisher.send(event)
        publish(event)
    }
    
    // MARK: - Private Methods
    
    private func routeToSpecificPublisher(_ event: any ClaimEvent) {
        switch event {
        case let e as EmailClaimEvent:
            emailEventPublisher.send(e)
        case let e as EmailAssignmentEvent:
            assignmentPublisher.send(e)
        case let e as EmailRevocationEvent:
            revocationPublisher.send(e)
        case let e as WhatsAppClaimEvent:
            whatsAppEventPublisher.send(e)
        case let e as UserNoteClaimEvent:
            userNoteEventPublisher.send(e)
        case let e as SystemClaimEvent:
            systemEventPublisher.send(e)
        default:
            break
        }
    }
    
    private func addToHistory(_ event: any ClaimEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxHistorySize {
            recentEvents.removeLast()
        }
    }
    
    private func updateStats(_ event: any ClaimEvent) {
        eventStats.totalEvents += 1
        eventStats.eventsBySource[event.source, default: 0] += 1
        eventStats.lastEventDate = Date()
        
        // Aggiorna statistiche per intent se disponibile
        if let emailEvent = event as? EmailClaimEvent {
            eventStats.eventsByIntent[emailEvent.intent, default: 0] += 1
        } else if let waEvent = event as? WhatsAppClaimEvent {
            eventStats.eventsByIntent[waEvent.intent, default: 0] += 1
        } else if let noteEvent = event as? UserNoteClaimEvent {
            eventStats.eventsByIntent[noteEvent.primaryIntent, default: 0] += 1
        }
    }
    
    // MARK: - Utility
    
    /// Pulisce la storia degli eventi
    func clearHistory() {
        recentEvents.removeAll()
        eventStats.reset()
        print("[UnifiedEventBus] 🗑️ Storia eventi cancellata")
    }
    
    /// Ottiene gli ultimi N eventi
    func getRecentEvents(limit: Int = 10) -> [any ClaimEvent] {
        Array(recentEvents.prefix(limit))
    }
    
    /// Ottiene eventi per sinistro
    func getEventsForSinistro(_ sinistroId: String, limit: Int = 20) -> [any ClaimEvent] {
        recentEvents
            .filter { $0.sinistroId == sinistroId }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Legacy Compatibility

extension UnifiedEventBus {
    /// Converte un EmailEvent legacy in EmailClaimEvent
    func publishLegacyEmailEvent(_ legacyEvent: any EmailEvent) {
        let intent = mapLegacyEventToIntent(legacyEvent)
        
        let claimEvent = EmailClaimEvent(
            emailId: legacyEvent.emailId,
            sinistroId: legacyEvent.sinistroId,
            direction: legacyEvent.direction == .inbound ? .inbound : .outbound,
            intent: intent,
            senderType: .unknown,
            subject: "",
            hasAttachments: false,
            attachmentCount: 0,
            metadata: legacyEvent.metadata
        )
        
        publishEmail(claimEvent)
    }
    
    private func mapLegacyEventToIntent(_ event: any EmailEvent) -> ClaimEventIntent {
        switch event {
        case is EmailAssignmentReceived:
            return .assignment
        case is EmailRevocationReceived:
            return .revocation
        case is EmailSignedActReceived:
            return .actReceived
        case is EmailActToSignSent:
            return .actSent
        case is EmailReminderReceived, is EmailReminderSent:
            return .reminder
        case is EmailDocumentationReceived:
            return .documentation
        case is EmailDocumentationRequested:
            return .documentationRequest
        case is EmailSurveyScheduled:
            return .surveyScheduled
        case is EmailSurveyReturned:
            return .surveyReturned
        case is EmailVideocallScheduled:
            return .videocallScheduled
        case is EmailClarificationRequested:
            return .clarification
        case is EmailControlled:
            return .control
        case is EmailRevisionRequested:
            return .revision
        case is EmailOutcomeSent:
            return .outcomeSent
        default:
            return .generic
        }
    }
}

