import Foundation
import CoreData

/// Centralizza la ricerca di `SinistroEmailThread` a partire da un `emailId`.
/// La view deve limitarsi a richiedere il thread e reagire al risultato.
@MainActor
final class ThreadSearchService {
    static let shared = ThreadSearchService()
    private init() {}
    
    /// Cerca un thread che contenga `emailId`.
    /// - Parameters:
    ///   - emailId: messageId dell'email
    ///   - maxWaitSeconds: attesa massima (per supportare caricamento streaming thread)
    ///   - pollIntervalSeconds: intervallo polling interno
    func findThread(
        forEmailId emailId: String,
        maxWaitSeconds: TimeInterval = 5,
        pollIntervalSeconds: TimeInterval = 0.5
    ) async -> SinistroEmailThread? {
        guard !emailId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        
        // 1) Primo tentativo immediato sui thread già disponibili (veloce)
        if let immediate = findInMemory(forEmailId: emailId) {
            return immediate
        }
        
        // 2) Polling breve: utile mentre i thread arrivano in streaming
        let maxAttempts = max(1, Int((maxWaitSeconds / pollIntervalSeconds).rounded(.down)))
        var attempt = 0
        
        while attempt < maxAttempts {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
            if Task.isCancelled { return nil }
            
            if let found = findInMemory(forEmailId: emailId, onlyNewestSuffix: true) {
                return found
            }
            
            attempt += 1
        }
        
        return nil
    }
    
    /// Variante callback (comoda per chi non vuole gestire Task/cancellazioni).
    func findThreadAsync(
        forEmailId emailId: String,
        maxWaitSeconds: TimeInterval = 5,
        pollIntervalSeconds: TimeInterval = 0.5,
        completion: @escaping (SinistroEmailThread?) -> Void
    ) {
        Task { @MainActor in
            let thread = await findThread(
                forEmailId: emailId,
                maxWaitSeconds: maxWaitSeconds,
                pollIntervalSeconds: pollIntervalSeconds
            )
            completion(thread)
        }
    }
    
    private func findInMemory(forEmailId emailId: String, onlyNewestSuffix: Bool = false) -> SinistroEmailThread? {
        let principaleViewModel = PrincipaleViewModel.shared
        
        // 1) Thread già visualizzati (più probabili)
        for thread in principaleViewModel.displayedThreads {
            if thread.messageIds.contains(emailId) {
                return thread
            }
        }
        
        // 2) Thread già caricati ma non visualizzati
        let all = principaleViewModel.emailThreads
        if all.isEmpty { return nil }
        
        if onlyNewestSuffix {
            let slice = Array(all.suffix(min(50, all.count)))
            for thread in slice {
                if thread.messageIds.contains(emailId) {
                    return thread
                }
            }
            return nil
        } else {
            for thread in all {
                if thread.messageIds.contains(emailId) {
                    return thread
                }
            }
            return nil
        }
    }
}

