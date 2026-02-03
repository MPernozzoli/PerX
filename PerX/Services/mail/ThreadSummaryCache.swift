import Foundation
import Combine

/// Cache persistente per i riassunti dei thread email con supporto streaming
/// Memorizza i riassunti su disco e li invalida solo quando cambiano le email del thread
@MainActor
class ThreadSummaryCache: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ThreadSummaryCache()
    
    // MARK: - Types
    
    struct CachedSummary: Codable {
        let threadId: UUID
        let summary: String
        let emailCount: Int
        let lastUpdated: Date
    }
    
    enum SummaryState: Equatable {
        case notRequested
        case loading
        case streaming(String)
        case ready(String)
        case error(String)
        
        var text: String? {
            switch self {
            case .streaming(let text), .ready(let text):
                return text
            default:
                return nil
            }
        }
        
        var isLoading: Bool {
            if case .loading = self { return true }
            if case .streaming = self { return true }
            return false
        }
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var summaryStates: [UUID: SummaryState] = [:]
    
    // MARK: - Private Properties
    
    private var cache: [UUID: CachedSummary] = [:]
    private var pendingRequests: Set<UUID> = []
    private let maxConcurrentRequests = 2
    private var activeRequests = 0
    private var requestQueue: [(UUID, [Email])] = []
    
    private let cacheURL: URL
    private let aiManager = AIManager.shared
    
    // MARK: - Init
    
    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let perxCacheDir = cachesDir.appendingPathComponent("PerX", isDirectory: true)
        
        // Crea directory se non esiste
        try? FileManager.default.createDirectory(at: perxCacheDir, withIntermediateDirectories: true)
        
        self.cacheURL = perxCacheDir.appendingPathComponent("threadSummaries.json")
        
        // Ritarda loadFromDisk per evitare modifiche @Published durante la costruzione della view
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms delay
            await self?.loadFromDisk()
        }
    }
    
    // MARK: - Public API
    
    /// Ottiene il riassunto per un thread se disponibile e valido
    func getSummary(for threadId: UUID, currentEmailCount: Int) -> String? {
        guard let cached = cache[threadId] else { return nil }
        
        // Invalida se il numero di email è cambiato
        if cached.emailCount != currentEmailCount {
            cache.removeValue(forKey: threadId)
            summaryStates[threadId] = .notRequested
            saveToDisk()
            return nil
        }
        
        return cached.summary
    }
    
    /// Stato corrente del riassunto
    func getState(for threadId: UUID) -> SummaryState {
        return summaryStates[threadId] ?? .notRequested
    }
    
    /// Soglia minima di caratteri per generare un riassunto
    static let minimumTextLength = 100
    
    /// Richiede la generazione del riassunto se necessario
    /// - Parameters:
    ///   - threadId: ID del thread
    ///   - emails: Email del thread
    ///   - force: Se true, rigenera anche se già presente
    func requestSummary(for threadId: UUID, emails: [Email], force: Bool = false) {
        let currentCount = emails.count
        
        // Calcola lunghezza totale del contenuto per verificare se vale la pena riassumere
        let totalTextLength = emails.reduce(0) { total, email in
            let bodyLength = email.body?.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            return total + bodyLength
        }
        
        // Se il contenuto totale è troppo corto, non ha senso riassumere
        if totalTextLength < Self.minimumTextLength {
            summaryStates[threadId] = .notRequested
            return
        }
        
        // Se già in cache e valido, usa quello
        if !force, let cached = cache[threadId], cached.emailCount == currentCount {
            summaryStates[threadId] = .ready(cached.summary)
            return
        }
        
        // Se già in coda o in elaborazione, ignora
        if pendingRequests.contains(threadId) {
            return
        }
        
        // Aggiungi alla coda
        pendingRequests.insert(threadId)
        requestQueue.append((threadId, emails))
        summaryStates[threadId] = .loading
        
        processQueue()
    }
    
    /// Verifica se un set di email ha abbastanza contenuto per generare un riassunto
    func canSummarize(emails: [Email]) -> Bool {
        let totalTextLength = emails.reduce(0) { total, email in
            let bodyLength = email.body?.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
            return total + bodyLength
        }
        return totalTextLength >= Self.minimumTextLength
    }
    
    /// Cancella la richiesta pendente per un thread
    func cancelRequest(for threadId: UUID) {
        pendingRequests.remove(threadId)
        requestQueue.removeAll { $0.0 == threadId }
        if case .loading = summaryStates[threadId] {
            summaryStates[threadId] = .notRequested
        }
    }
    
    /// Pulisce la cache per un thread specifico
    func clearCache(for threadId: UUID) {
        cache.removeValue(forKey: threadId)
        summaryStates.removeValue(forKey: threadId)
        saveToDisk()
    }
    
    /// Pulisce tutta la cache
    func clearAllCache() {
        cache.removeAll()
        summaryStates.removeAll()
        saveToDisk()
    }
    
    // MARK: - Private Methods
    
    private func processQueue() {
        guard activeRequests < maxConcurrentRequests,
              let (threadId, emails) = requestQueue.first else {
            return
        }
        
        requestQueue.removeFirst()
        activeRequests += 1
        
        Task {
            await generateSummary(for: threadId, emails: emails)
            
            await MainActor.run {
                self.activeRequests -= 1
                self.pendingRequests.remove(threadId)
                self.processQueue()
            }
        }
    }
    
    private func generateSummary(for threadId: UUID, emails: [Email]) async {
        // Ordina per data
        let sortedEmails = emails.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        // Costruisci il contesto per il riassunto
        var context = ""
        var participants: Set<String> = []
        
        for email in sortedEmails.prefix(15) {
            participants.insert(email.sender.displayName)
            
            if let body = email.body {
                let (mainBody, _) = EmailHelpers.extractQuote(from: body)
                let cleanBody = EmailHelpers.cleanHTMLBody(mainBody)
                let withoutSignature = EmailHelpers.removeSignatureAndDisclaimer(from: cleanBody)
                context += "\n---\nDa: \(email.sender.displayName)\nData: \(email.date.formatted())\n\(String(withoutSignature.prefix(500)))"
            }
        }
        
        // Usa AIManager con Apple Intelligence per generare il riassunto
        let prompt = """
        Genera un riassunto conciso (massimo 3 frasi) di questa conversazione email.
        Focus sui punti chiave e decisioni importanti.
        
        \(context)
        """
        
        // Crea task AI con Apple Intelligence
        let task = AITask(
            type: .emailSummary,
            priority: .secondary,
            preferredProvider: .appleIntelligence,
            parameters: [
                "subject": AnyCodable("Thread Email"),
                "body": AnyCodable(context),
                "prompt": AnyCodable(prompt)
            ]
        )
        
        // Genera riassunto con streaming
        var summary = ""
        
        // Mostra stato loading
        await updateStreaming(for: threadId, text: "")
        
        // Usa AIManager per generare il riassunto
        let taskId = await MainActor.run {
            return aiManager.enqueue(task) { aiResult in
                Task { @MainActor in
                    if aiResult.success {
                        // Estrai il risultato - potrebbe essere String o AnyCodable
                        var resultText: String?
                        if let stringValue = aiResult.result?.value as? String {
                            resultText = stringValue
                        } else if let anyCodable = aiResult.result, let stringValue = anyCodable.value as? String {
                            resultText = stringValue
                        }
                        
                        if let finalSummary = resultText?.trimmingCharacters(in: .whitespacesAndNewlines), !finalSummary.isEmpty {
                            let cached = CachedSummary(
                                threadId: threadId,
                                summary: finalSummary,
                                emailCount: emails.count,
                                lastUpdated: Date()
                            )
                            self.cache[threadId] = cached
                            self.summaryStates[threadId] = .ready(finalSummary)
                            self.saveToDisk()
                        } else {
                            self.summaryStates[threadId] = .error("Riassunto vuoto")
                        }
                    } else {
                        // Gestisci errore
                        let errorMessage = aiResult.error?.localizedDescription ?? "Errore sconosciuto"
                        self.summaryStates[threadId] = .error("Errore: \(errorMessage)")
                    }
                }
            }
        }
        
        // Fallback: se dopo 10 secondi non abbiamo risposta, genera riassunto semplice
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 secondi
        
        await MainActor.run {
            // Se ancora in loading, genera riassunto semplice come fallback
            if case .loading = self.summaryStates[threadId] {
                let simpleSummary = self.generateSimpleSummary(emails: sortedEmails, participants: participants)
                let cached = CachedSummary(
                    threadId: threadId,
                    summary: simpleSummary,
                    emailCount: emails.count,
                    lastUpdated: Date()
                )
                self.cache[threadId] = cached
                self.summaryStates[threadId] = .ready(simpleSummary)
                self.saveToDisk()
            }
        }
    }
    
    /// Genera un riassunto semplice come fallback
    private func generateSimpleSummary(emails: [Email], participants: Set<String>) -> String {
        var summary = ""
        
        if !participants.isEmpty {
            summary += "Partecipanti: \(participants.joined(separator: ", "))"
        }
        
        if let firstDate = emails.first?.date, let lastDate = emails.last?.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            if !summary.isEmpty { summary += "\n\n" }
            summary += "Periodo: \(formatter.string(from: firstDate)) - \(formatter.string(from: lastDate))"
        }
        
        return summary.isEmpty ? "Conversazione email" : summary
    }
    
    private func updateStreaming(for threadId: UUID, text: String) async {
        await MainActor.run {
            self.summaryStates[threadId] = .streaming(text)
        }
    }
    
    // MARK: - Persistence
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let summaries = try JSONDecoder().decode([CachedSummary].self, from: data)
            
            for summary in summaries {
                cache[summary.threadId] = summary
                summaryStates[summary.threadId] = .ready(summary.summary)
            }
            
            print("[ThreadSummaryCache] Caricati \(summaries.count) riassunti dalla cache")
        } catch {
            print("[ThreadSummaryCache] Errore caricamento cache: \(error)")
        }
    }
    
    private func saveToDisk() {
        let summaries = Array(cache.values)
        
        do {
            let data = try JSONEncoder().encode(summaries)
            try data.write(to: cacheURL)
        } catch {
            print("[ThreadSummaryCache] Errore salvataggio cache: \(error)")
        }
    }
}

