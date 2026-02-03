import Foundation
import Combine

/// Bus centralizzato per la pubblicazione di eventi email
/// Il ClaimEngine si sottoscriverà a questo bus per ricevere gli eventi
@MainActor
class EmailEventBus: ObservableObject {
    static let shared = EmailEventBus()
    
    // MARK: - Publishers
    
    /// Publisher principale per tutti gli eventi
    let eventPublisher = PassthroughSubject<any EmailEvent, Never>()
    
    /// Publisher per eventi di assegnazione
    let assignmentPublisher = PassthroughSubject<EmailAssignmentReceived, Never>()
    
    /// Publisher per eventi di revoca
    let revocationPublisher = PassthroughSubject<EmailRevocationReceived, Never>()
    
    /// Publisher per eventi atto
    let actPublisher = PassthroughSubject<any EmailEvent, Never>()
    
    /// Publisher per eventi documentazione
    let documentationPublisher = PassthroughSubject<any EmailEvent, Never>()
    
    /// Publisher per solleciti
    let reminderPublisher = PassthroughSubject<any EmailEvent, Never>()
    
    // MARK: - Event History
    
    /// Ultimi eventi per debug/monitoring (max 100)
    @Published private(set) var recentEvents: [any EmailEvent] = []
    private let maxHistorySize = 100
    
    /// Statistiche eventi
    @Published private(set) var eventStats: EventStats = EventStats()
    
    struct EventStats {
        var totalEvents: Int = 0
        var eventsByType: [String: Int] = [:]
        var lastEventDate: Date?
    }
    
    // MARK: - Initialization
    
    private init() {
        print("[EmailEventBus] Inizializzato")
    }
    
    // MARK: - Publishing
    
    /// Pubblica un evento generico
    func publish(_ event: any EmailEvent) {
        // Pubblica sul bus principale
        eventPublisher.send(event)
        
        // Pubblica su bus specifici
        routeToSpecificPublisher(event)
        
        // Aggiorna storia
        addToHistory(event)
        
        // Aggiorna statistiche
        updateStats(event)
        
        // Log
        let eventType = String(describing: type(of: event))
        print("[EmailEventBus] 📬 Pubblicato: \(eventType) | Email: \(event.emailId) | Sinistro: \(event.sinistroId ?? "N/A")")
    }
    
    /// Pubblica evento di assegnazione
    func publishAssignment(_ event: EmailAssignmentReceived) {
        assignmentPublisher.send(event)
        publish(event)
    }
    
    /// Pubblica evento di revoca
    func publishRevocation(_ event: EmailRevocationReceived) {
        revocationPublisher.send(event)
        publish(event)
    }
    
    // MARK: - Private Methods
    
    private func routeToSpecificPublisher(_ event: any EmailEvent) {
        switch event {
        case let e as EmailAssignmentReceived:
            assignmentPublisher.send(e)
        case let e as EmailRevocationReceived:
            revocationPublisher.send(e)
        case is EmailSignedActReceived, is EmailActToSignSent:
            actPublisher.send(event)
        case is EmailDocumentationReceived, is EmailDocumentationRequested:
            documentationPublisher.send(event)
        case is EmailReminderReceived, is EmailReminderSent:
            reminderPublisher.send(event)
        default:
            break
        }
    }
    
    private func addToHistory(_ event: any EmailEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxHistorySize {
            recentEvents.removeLast()
        }
    }
    
    private func updateStats(_ event: any EmailEvent) {
        eventStats.totalEvents += 1
        eventStats.lastEventDate = Date()
        
        let eventType = String(describing: type(of: event))
        eventStats.eventsByType[eventType, default: 0] += 1
    }
    
    // MARK: - Query Methods
    
    /// Ottieni eventi recenti per un sinistro
    func getEvents(forSinistro sinistroId: String, limit: Int = 20) -> [any EmailEvent] {
        return recentEvents
            .filter { $0.sinistroId == sinistroId }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Ottieni eventi recenti di un certo tipo
    func getEvents<T: EmailEvent>(ofType type: T.Type, limit: Int = 20) -> [T] {
        return recentEvents
            .compactMap { $0 as? T }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Pulisci la storia degli eventi
    func clearHistory() {
        recentEvents.removeAll()
        eventStats = EventStats()
        print("[EmailEventBus] Storia eventi pulita")
    }
}

