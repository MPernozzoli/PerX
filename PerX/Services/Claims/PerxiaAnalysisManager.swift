import Foundation
import Combine
import CoreData

/// Manager singleton per gestire le analisi Perxia in modo persistente
/// Le analisi continuano anche se l'utente cambia view
class PerxiaAnalysisManager: ObservableObject {
    static let shared = PerxiaAnalysisManager()
    
    // MARK: - Stato Analisi per Sinistro
    
    struct AnalysisState: Identifiable {
        var id: String { sinistroRiferimento }
        let sinistroRiferimento: String
        var status: AnalysisStatus
        var progress: Double
        var currentPhase: String
        var streamOutput: String
        var beniAnalizzati: [PerxiaService.BeneAnalysisStreaming]
        var quadroContrattuale: PerxiaService.AnalisiQuadroContrattuale?
        var relazione: String
        var error: String?
        var startTime: Date
        var analisiCompleta: PerxiaService.AnalisiSinistroCompleta?
    }
    
    enum AnalysisStatus: String {
        case idle = "idle"
        case running = "running"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var activeAnalyses: [String: AnalysisState] = [:]
    
    // MARK: - Private
    
    private var analysisTasks: [String: Task<Void, Never>] = [:]
    private let perxiaService = PerxiaService.shared
    private let queue = DispatchQueue(label: "com.perx.analysis.manager", qos: .userInitiated)
    
    private init() {}
    
    // MARK: - Public API
    
    /// Verifica se un sinistro ha un'analisi in corso
    func isAnalyzing(riferimento: String) -> Bool {
        activeAnalyses[riferimento]?.status == .running
    }
    
    /// Ottiene lo stato corrente dell'analisi per un sinistro
    /// Carica dallo storage persistente se non è in memoria
    func getState(for riferimento: String) -> AnalysisState? {
        // Se è in memoria, restituiscilo
        if let state = activeAnalyses[riferimento] {
            return state
        }
        
        // Altrimenti carica dallo storage persistente
        return loadState(riferimento: riferimento)
    }
    
    /// Avvia un'analisi per un sinistro (o restituisce lo stato se già in corso)
    @MainActor
    func startAnalysis(
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String
    ) {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Se già in corso, non fare nulla
        if isAnalyzing(riferimento: riferimento) {
            print("[AnalysisManager] ⏳ Analisi già in corso per \(riferimento)")
            return
        }
        
        // Crea stato iniziale
        let initialState = AnalysisState(
            sinistroRiferimento: riferimento,
            status: .running,
            progress: 0,
            currentPhase: "Inizializzazione...",
            streamOutput: "",
            beniAnalizzati: [],
            quadroContrattuale: nil,
            relazione: "",
            error: nil,
            startTime: Date(),
            analisiCompleta: nil
        )
        
        activeAnalyses[riferimento] = initialState
        
        print("[AnalysisManager] 🚀 Avvio analisi per \(riferimento)")
        
        // Avvia task in background
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.runAnalysis(
                sinistro: sinistro,
                riferimento: riferimento,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione
            )
        }
        
        analysisTasks[riferimento] = task
    }
    
    /// Cancella un'analisi in corso
    @MainActor
    func cancelAnalysis(riferimento: String) {
        guard var state = activeAnalyses[riferimento] else { return }
        
        analysisTasks[riferimento]?.cancel()
        analysisTasks.removeValue(forKey: riferimento)
        
        state.status = .cancelled
        state.currentPhase = "Cancellato"
        state.error = "Analisi interrotta dall'utente"
        activeAnalyses[riferimento] = state
        
        print("[AnalysisManager] ❌ Analisi cancellata per \(riferimento)")
    }
    
    /// Rimuove lo stato di un'analisi completata (per pulizia)
    @MainActor
    func clearState(riferimento: String) {
        activeAnalyses.removeValue(forKey: riferimento)
        analysisTasks.removeValue(forKey: riferimento)
    }
    
    // MARK: - Private Implementation
    
    private func runAnalysis(
        sinistro: Sinistro,
        riferimento: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String
    ) async {
        
        // Usa la pipeline streaming
        let result = await perxiaService.analizzaSinistroStreaming(
            sinistro: sinistro,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            streamCallback: { [weak self] message in
                self?.updateStreamOutput(riferimento: riferimento, message: message)
            },
            progressCallback: { [weak self] value in
                self?.updateProgress(riferimento: riferimento, progress: value)
            },
            beneStreamCallback: { [weak self] bene in
                self?.addBene(riferimento: riferimento, bene: bene)
            },
            relazioneStreamCallback: { [weak self] text in
                self?.appendRelazione(riferimento: riferimento, text: text)
            },
            quadroContrattualeCallback: { [weak self] qc in
                self?.updateQuadroContrattuale(riferimento: riferimento, quadro: qc)
            }
        )
        
        // Aggiorna stato finale
        await MainActor.run { [weak self] in
            guard var state = self?.activeAnalyses[riferimento] else { return }
            
            switch result {
            case .success(let analisi):
                state.status = .completed
                state.progress = 1.0
                state.currentPhase = "Completato"
                state.analisiCompleta = analisi
                print("[AnalysisManager] ✅ Analisi completata per \(riferimento): \(analisi.beni.count) beni")
                
                // Salva lo stato in modo persistente
                self?.saveState(riferimento: riferimento, state: state)
                
            case .failure(let error):
                state.status = .failed
                state.currentPhase = "Errore"
                state.error = error.localizedDescription
                print("[AnalysisManager] ❌ Analisi fallita per \(riferimento): \(error)")
            }
            
            self?.activeAnalyses[riferimento] = state
            self?.analysisTasks.removeValue(forKey: riferimento)
        }
    }
    
    // MARK: - State Update Helpers
    
    @MainActor
    private func updateStreamOutput(riferimento: String, message: String) {
        guard var state = activeAnalyses[riferimento] else { return }
        state.streamOutput += message
        
        // Estrai fase dal messaggio
        if message.contains("📸") {
            state.currentPhase = "Raccolta foto taggate..."
        } else if message.contains("🏠") {
            state.currentPhase = "Analisi foto ubicazione..."
        } else if message.contains("⚡") {
            state.currentPhase = "Analisi beni..."
        } else if message.contains("📝") {
            state.currentPhase = "Generazione relazione..."
        } else if message.contains("→") {
            // Estrai nome bene dal messaggio
            if let range = message.range(of: "→ ") {
                let rest = String(message[range.upperBound...])
                if let endRange = rest.range(of: " (") {
                    let beneName = String(rest[..<endRange.lowerBound])
                    state.currentPhase = "Analisi: \(beneName)"
                }
            }
        }
        
        activeAnalyses[riferimento] = state
    }
    
    @MainActor
    private func updateProgress(riferimento: String, progress: Double) {
        guard var state = activeAnalyses[riferimento] else { return }
        state.progress = progress
        activeAnalyses[riferimento] = state
    }
    
    @MainActor
    private func addBene(riferimento: String, bene: PerxiaService.BeneAnalysisStreaming) {
        guard var state = activeAnalyses[riferimento] else { return }
        state.beniAnalizzati.append(bene)
        activeAnalyses[riferimento] = state
    }
    
    @MainActor
    private func appendRelazione(riferimento: String, text: String) {
        guard var state = activeAnalyses[riferimento] else { return }
        state.relazione += text
        activeAnalyses[riferimento] = state
        
        // Salva la relazione in Core Data in modo incrementale
        saveRelazione(riferimento: riferimento, relazione: state.relazione)
    }
    
    /// Salva la relazione in Core Data
    private func saveRelazione(riferimento: String, relazione: String) {
        let context = PersistenceController.shared.container.viewContext
        
        let fetch = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetch.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetch.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(fetch).first else { return }
        
        // Cerca o crea PerxiaAnalisi
        let analisiFetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        analisiFetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        analisiFetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        analisiFetch.fetchLimit = 1
        
        let perxiaAnalisi: PerxiaAnalisi
        if let existing = try? context.fetch(analisiFetch).first {
            perxiaAnalisi = existing
        } else {
            perxiaAnalisi = PerxiaAnalisi(context: context)
            perxiaAnalisi.id = UUID()
            perxiaAnalisi.dataAnalisi = Date()
            perxiaAnalisi.sinistro = sinistro
        }
        
        perxiaAnalisi.relazioneComplessiva = relazione
        try? context.save()
    }
    
    @MainActor
    private func updateQuadroContrattuale(riferimento: String, quadro: PerxiaService.AnalisiQuadroContrattuale) {
        guard var state = activeAnalyses[riferimento] else { return }
        state.quadroContrattuale = quadro
        activeAnalyses[riferimento] = state
    }
    
    // MARK: - Persistenza Stato
    
    /// Salva lo stato dell'analisi in modo persistente (Core Data)
    private func saveState(riferimento: String, state: AnalysisState) {
        // Trova il sinistro
        let context = PersistenceController.shared.container.viewContext
        let fetch = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetch.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetch.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(fetch).first else {
            print("[AnalysisManager] ⚠️ Sinistro non trovato per salvataggio stato: \(riferimento)")
            return
        }
        
        // Se l'analisi è completata, salva i dati streaming
        if state.status == .completed, let analisi = state.analisiCompleta {
            // I dati streaming vengono salvati da salvaAnalisiStreaming
            // Qui salviamo solo lo stato base
            print("[AnalysisManager] 💾 Stato analisi completata salvato per \(riferimento)")
        }
    }
    
    /// Carica lo stato dell'analisi dallo storage persistente
    private func loadState(riferimento: String) -> AnalysisState? {
        let context = PersistenceController.shared.container.viewContext
        
        // Trova il sinistro
        let fetch = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetch.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetch.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(fetch).first else {
            return nil
        }
        
        // Carica l'analisi streaming salvata
        if let (beniStreaming, quadroContrattuale) = perxiaService.caricaAnalisiStreaming(sinistro: sinistro) {
            // Cerca l'ultima analisi per la relazione
            let analisiFetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
            analisiFetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
            analisiFetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
            analisiFetch.fetchLimit = 1
            
            let relazione = (try? context.fetch(analisiFetch).first)?.relazioneComplessiva ?? ""
            
            // Ricostruisci AnalisiSinistroCompleta dai dati base
            let beniBase = beniStreaming.map { beneStreaming in
                perxiaService.convertToBeneAnalysis(beneStreaming)
            }
            
            let complessita = perxiaService.calcolaComplessitaSinistro(beni: beniBase, giustificativi: nil)
            
            let analisiCompleta = PerxiaService.AnalisiSinistroCompleta(
                beni: beniBase,
                complessita: complessita,
                denuncia: nil,
                giustificativi: nil,
                verificaUbicazione: quadroContrattuale?.verificaIndirizzo != nil ? PerxiaService.VerificaUbicazione(
                    corrispondenza: quadroContrattuale?.verificaIndirizzo?.esito ?? "non_verificabile",
                    evidenzeTrovate: [],
                    discrepanze: [],
                    confidenza: 0.7,
                    note: nil
                ) : nil,
                sopralluogo: sinistro.sopralluogo,
                fulminazione: sinistro.fulminazione != nil && !sinistro.fulminazione!.isEmpty,
                noteGenerali: nil
            )
            
            let state = AnalysisState(
                sinistroRiferimento: riferimento,
                status: .completed,
                progress: 1.0,
                currentPhase: "Completato",
                streamOutput: "",
                beniAnalizzati: beniStreaming,
                quadroContrattuale: quadroContrattuale,
                relazione: relazione,
                error: nil,
                startTime: Date(),
                analisiCompleta: analisiCompleta
            )
            
            // Metti in memoria per accesso rapido
            activeAnalyses[riferimento] = state
            
            print("[AnalysisManager] ✅ Stato analisi caricato da storage per \(riferimento): \(beniStreaming.count) beni")
            return state
        }
        
        return nil
    }
}

// MARK: - View Model per osservare lo stato
class PerxiaAnalysisViewModel: ObservableObject {
    let sinistroRiferimento: String
    private var cancellables = Set<AnyCancellable>()
    
    @Published var state: PerxiaAnalysisManager.AnalysisState?
    
    var isAnalyzing: Bool {
        state?.status == .running
    }
    
    var progress: Double {
        state?.progress ?? 0
    }
    
    var currentPhase: String {
        state?.currentPhase ?? ""
    }
    
    var beni: [PerxiaService.BeneAnalysisStreaming] {
        state?.beniAnalizzati ?? []
    }
    
    var relazione: String {
        state?.relazione ?? ""
    }
    
    var error: String? {
        state?.error
    }
    
    var quadroContrattuale: PerxiaService.AnalisiQuadroContrattuale? {
        state?.quadroContrattuale
    }
    
    var analisiCompleta: PerxiaService.AnalisiSinistroCompleta? {
        state?.analisiCompleta
    }
    
    init(sinistroRiferimento: String) {
        self.sinistroRiferimento = sinistroRiferimento
        
        // Osserva cambiamenti nel manager
        PerxiaAnalysisManager.shared.$activeAnalyses
            .map { $0[sinistroRiferimento] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
            .store(in: &cancellables)
        
        // Stato iniziale: carica da storage se disponibile
        if let savedState = PerxiaAnalysisManager.shared.getState(for: sinistroRiferimento) {
            self.state = savedState
        }
    }
    
    func startAnalysis(sinistro: Sinistro, fulminazione: Bool, sopralluogo: Bool, ubicazione: String) {
        Task { @MainActor in
            PerxiaAnalysisManager.shared.startAnalysis(
                sinistro: sinistro,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione
            )
        }
    }
    
    func cancelAnalysis() {
        Task { @MainActor in
            PerxiaAnalysisManager.shared.cancelAnalysis(riferimento: sinistroRiferimento)
        }
    }
}
