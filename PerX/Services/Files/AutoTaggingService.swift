import Foundation
import SwiftUI
import CoreData
import UserNotifications

/// Servizio per l'auto-tagging intelligente delle foto tramite IA multimodale
@MainActor
class AutoTaggingService: ObservableObject {
    static let shared = AutoTaggingService()
    
    private let fileService = FileService.shared
    private let fileTagManager = FileTagManager.shared
    
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentFile: String = ""
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var statusMessage: String = ""
    
    // Coda persistente
    private var pendingPhotosQueue: [URL] = []
    private var currentSinistro: Sinistro?
    private let queuePersistenceKey = "autotagging_pending_queue"
    private let currentSinistroKey = "autotagging_current_sinistro"
    
    private var processingSinistri = Set<String>()
    private var processingStartTimes: [String: Date] = [:]  // Per timeout
    private let processingTimeout: TimeInterval = 120  // 2 minuti timeout
    private let queue = DispatchQueue(label: "com.perx.autotagging", qos: .userInitiated)
    
    // Cancellazione
    @Published var isCancelled = false
    
    // Cache per evitare analisi ripetute nella stessa sessione
    private var analyzedPaths = Set<String>()
    private var similarityCache: [String: String] = [:] // path -> groupId per foto simili
    
    // Rate limiting per batch cloud: max 5 batch al minuto (12 secondi tra batch)
    private var lastBatchTime: Date?
    private let batchRateLimit: TimeInterval = 12.0 // 60 secondi / 5 batch = 12 secondi
    
    // Callback per notificare completamento autotagging
    var onAutoTaggingCompleted: ((Sinistro, Int) -> Void)?
    
    private init() {
        loadQueue()
        
        // Se c'è una coda residua, riprendi l'elaborazione dopo un breve delay
        if !pendingPhotosQueue.isEmpty {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 secondi
                await resumeProcessing()
            }
        }
    }
    
    // MARK: - Persistenza Coda
    
    private func saveQueue() {
        let paths = pendingPhotosQueue.map { $0.path }
        UserDefaults.standard.set(paths, forKey: queuePersistenceKey)
        
        if let riferimento = currentSinistro?.riferimento {
            UserDefaults.standard.set(riferimento, forKey: currentSinistroKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentSinistroKey)
        }
    }
    
    private func loadQueue() {
        if let paths = UserDefaults.standard.stringArray(forKey: queuePersistenceKey) {
            pendingPhotosQueue = paths.map { URL(fileURLWithPath: $0) }
        }
        
        if let riferimento = UserDefaults.standard.string(forKey: currentSinistroKey) {
            // Recupera il sinistro da CoreData usando il riferimento
            let context = PersistenceController.shared.container.viewContext
            let request = Sinistro.fetchRequest
            request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            request.fetchLimit = 1
            
            do {
                currentSinistro = try context.fetch(request).first
            } catch {
                print("[AutoTagging] ❌ Errore recupero sinistro persistente: \(error)")
            }
        }
    }
    
    @MainActor
    private func resumeProcessing() async {
        guard let sinistro = currentSinistro, !pendingPhotosQueue.isEmpty else { return }
        print("[AutoTagging] 🔄 Ripresa elaborazione coda persistente: \(pendingPhotosQueue.count) foto")
        
        let context = loadDocumentiContext(for: sinistro.riferimento ?? "")
        let results = await analyzePhotosWithAI(photos: pendingPhotosQueue, sinistro: sinistro, context: context)
        
        if !results.isEmpty {
            let taggedCount = await applyTagsWithDeduplication(results: results)
            if taggedCount > 0 {
                markAutoTaggingCompleted(for: sinistro)
                onAutoTaggingCompleted?(sinistro, taggedCount)
                
                // Notifica push al completamento
                sendCompletionNotification(count: taggedCount, for: sinistro)
            }
        }
        
        pendingPhotosQueue.removeAll()
        currentSinistro = nil
        saveQueue()
    }
    
    private func sendCompletionNotification(count: Int, for sinistro: Sinistro) {
        let content = UNMutableNotificationContent()
        let riferimento = sinistro.riferimento ?? "N/A"
        content.title = "Tag applicati - \(riferimento)"
        content.body = "L'analisi IA ha completato il tagging di \(count) foto per il sinistro \(riferimento)."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Strutture dati
    
    struct PhotoAnalysisResult: Codable {
        let path: String
        let tipo: PhotoType
        let tagSuggerito: String?
        let beneRiferimento: String?  // Nome del BENE (es. "caldaia", non "motore caldaia")
        let componente: String?        // Nome del COMPONENTE (es. "scheda elettronica", "motore")
        let descrizione: String
        let qualita: PhotoQuality
        var daAllegare: Bool
        let similarTo: String?         // Path di foto simile se duplicata
        let confidenza: Double
    }
    
    enum PhotoType: String, Codable {
        case ubicazioneRischio = "foto_ubicazione_rischio"
        case ubicazioneTecnico = "foto_ubicazione_tecnico"
        case ubicazioneAmministratore = "foto_ubicazione_amministratore"
        case ubicazioneAltra = "foto_ubicazione_altra"
        case bene = "foto_bene"
        case componente = "foto_componente"
        case ripristino = "foto_ripristino"
        case testFunzionale = "foto_test_funzionale"
        case testStrumentale = "test_strumentale"
        case fattura = "fattura"
        case preventivo = "preventivo"
        case atto = "atto"
        case altro = "altro"
        case irrilevante = "irrilevante"
        
        var tagId: String? {
            switch self {
            case .ubicazioneRischio: return "foto_ubicazione_rischio"
            case .ubicazioneTecnico: return "foto_ubicazione_tecnico"
            case .ubicazioneAmministratore: return "foto_ubicazione_amministratore"
            case .ubicazioneAltra: return "foto_ubicazione_altra"
            case .bene: return "foto_bene"
            case .componente: return "foto_componente"
            case .ripristino: return "foto_ripristino"
            case .testFunzionale: return "foto_test_funzionale"
            case .testStrumentale: return "test_strumentale"
            case .fattura: return "fattura"
            case .preventivo: return "preventivo"
            case .atto: return "atto_da_firmare"
            case .altro, .irrilevante: return nil
            }
        }
    }
    
    enum PhotoQuality: String, Codable {
        case buona = "buona"
        case media = "media"
        case scarsa = "scarsa"
        case irrilevante = "irrilevante"
    }
    
    // MARK: - Contesto Analisi Documenti
    
    /// Contesto estratto dall'analisi di denuncia e giustificativi
    struct DocumentiContext: Codable {
        var beniAttesi: [BeneAtteso]
        var vociGiustificativi: [VoceGiustificativo]  // Voci singole dai preventivi/fatture
        var verificaIndirizzo: VerificaIndirizzo?     // Confronto indirizzo denuncia vs nostri dati
        var dataSinistroDenuncia: Date?               // Data sinistro da denuncia (per confronto)
        var alertDocumenti: AlertDocumenti            // Alert e anomalie rilevate
        var noteGenerali: String?
        var dataAnalisi: Date
        var fileAnalizzati: [String]
        
        init() {
            self.beniAttesi = []
            self.vociGiustificativi = []
            self.alertDocumenti = AlertDocumenti()
            self.dataAnalisi = Date()
            self.fileAnalizzati = []
        }
        
        /// Importo totale calcolato da tutte le voci
        var importoTotale: Double {
            vociGiustificativi.reduce(0) { $0 + $1.importo }
        }
    }
    
    /// Bene atteso estratto dai documenti
    struct BeneAtteso: Codable, Hashable {
        let nome: String              // Nome del bene (es. "caldaia", "cancello carraio")
        let componenti: [String]      // Componenti menzionati (es. "scheda elettronica", "motore")
        let fonte: String             // "denuncia", "preventivo", "fattura"
        let descrizioneBreve: String?
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(nome.lowercased())
        }
        
        static func == (lhs: BeneAtteso, rhs: BeneAtteso) -> Bool {
            lhs.nome.lowercased() == rhs.nome.lowercased()
        }
    }
    
    /// Singola voce di un giustificativo (preventivo/fattura)
    struct VoceGiustificativo: Codable {
        let descrizione: String       // Descrizione della voce
        let importo: Double           // Importo della voce
        let beniAssociati: [String]   // Beni a cui si riferisce (può essere 1 o più)
        let tipo: TipoVoce            // materiale, manodopera, a_corpo
        let fonte: String             // Nome file del documento
        let isACorpo: Bool            // True se è un importo a corpo (non scomposto)
        let dataDocumento: Date?      // Data del documento (per verifica vs data sinistro)
        let numeroDocumento: String?  // Numero fattura/preventivo
        
        enum TipoVoce: String, Codable {
            case materiale = "materiale"
            case manodopera = "manodopera"
            case aCorpo = "a_corpo"        // Importo non scomposto
            case altro = "altro"
        }
    }
    
    /// Verifica dell'indirizzo tra denuncia e dati sinistro
    struct VerificaIndirizzo: Codable {
        let indirizzoDenuncia: String?    // Indirizzo letto dalla denuncia
        let indirizzoSinistro: String?    // Indirizzo dai nostri dati
        let matchCompleto: Bool           // Match esatto
        let matchParziale: Bool           // Match parziale (es. "via Verdi 3/A" vs "via Verdi 3")
        let differenze: String?           // Descrizione differenze se non match
        let daVerificare: Bool            // True se serve verifica manuale
    }
    
    /// Alert/Anomalie rilevate nell'analisi documenti
    struct AlertDocumenti: Codable {
        var giustificativiAntecedenti: [GiustificativoAntecedente]  // Documenti datati prima del sinistro
        var altreAnomalie: [String]                                   // Altre anomalie rilevate
        
        init() {
            self.giustificativiAntecedenti = []
            self.altreAnomalie = []
        }
        
        var hasAlerts: Bool {
            !giustificativiAntecedenti.isEmpty || !altreAnomalie.isEmpty
        }
    }
    
    /// Giustificativo con data antecedente al sinistro
    struct GiustificativoAntecedente: Codable {
        let nomeFile: String
        let dataDocumento: Date
        let dataSinistro: Date
        let differenzaGiorni: Int  // Numero di giorni di differenza (negativo = antecedente)
        let descrizione: String
    }
    
    /// Cache del contesto per sinistro
    private var documentiContextCache: [String: DocumentiContext] = [:]
    
    /// Flag per tracciare cosa è stato analizzato
    struct AnalysisState: Codable {
        var documentiAnalizzati: Bool = false
        var fotoAnalizzate: Bool = false
        var ultimaAnalisiDocumenti: Date?
        var ultimaAnalisiFoto: Date?
        var fileDocumentiAnalizzati: Set<String> = []
        var fileFotoAnalizzati: Set<String> = []
    }
    
    private var analysisStates: [String: AnalysisState] = [:]
    
    // MARK: - Persistenza Contesto
    
    private func saveDocumentiContext(_ context: DocumentiContext, for riferimento: String) {
        documentiContextCache[riferimento] = context
        
        // Salva su disco
        let key = "autotagging_context_\(riferimento)"
        if let data = try? JSONEncoder().encode(context) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadDocumentiContext(for riferimento: String) -> DocumentiContext? {
        // Prima controlla cache
        if let cached = documentiContextCache[riferimento] {
            return cached
        }
        
        // Poi disco
        let key = "autotagging_context_\(riferimento)"
        if let data = UserDefaults.standard.data(forKey: key),
           let context = try? JSONDecoder().decode(DocumentiContext.self, from: data) {
            documentiContextCache[riferimento] = context
            return context
        }
        
        return nil
    }
    
    /// Ottiene il contesto dei documenti analizzati per un sinistro
    func getDocumentiContext(for sinistro: Sinistro) -> DocumentiContext? {
        guard let riferimento = sinistro.riferimento else { return nil }
        return loadDocumentiContext(for: riferimento)
    }
    
    /// Verifica se ci sono nuovi documenti da analizzare
    func hasNewDocumentsToAnalyze(for sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return false
        }
        
        let context = loadDocumentiContext(for: riferimento)
        let currentDocs = findDocumentsToAnalyze(in: rootPath)
        
        // Se non c'è contesto, ci sono nuovi documenti
        guard let ctx = context else { return !currentDocs.isEmpty }
        
        // Controlla se ci sono file non ancora analizzati
        let analyzedSet = Set(ctx.fileAnalizzati)
        return currentDocs.contains { !analyzedSet.contains($0.path) }
    }
    
    /// Verifica se ci sono nuove foto da analizzare
    func hasNewPhotosToAnalyze(for sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let state = analysisStates[riferimento] else {
            return true
        }
        
        // TODO: Implementare check per nuove foto non in fileFotoAnalizzati
        return !state.fotoAnalizzate
    }
    
    // MARK: - API Pubblica
    
    /// Pulisce i sinistri bloccati in elaborazione
    private func cleanupStaleProcessing() {
        let now = Date()
        var staleKeys: [String] = []
        
        for (riferimento, startTime) in processingStartTimes {
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed > processingTimeout {
                staleKeys.append(riferimento)
                print("[AutoTagging] ⏰ Sinistro \(riferimento) in elaborazione da \(Int(elapsed))s - timeout superato")
            }
        }
        
        for key in staleKeys {
            print("[AutoTagging] 🧹 Pulizia sinistro bloccato \(key)")
            processingSinistri.remove(key)
            processingStartTimes.removeValue(forKey: key)
        }
    }
    
    /// Forza il reset di tutti i sinistri in elaborazione (per debug)
    func forceResetAllProcessing() {
        print("[AutoTagging] 🔄 Reset forzato di tutti i sinistri in elaborazione")
        processingSinistri.removeAll()
        processingStartTimes.removeAll()
        isProcessing = false
    }
    
    /// Interrompe l'autotagging in corso
    @MainActor
    func cancel() {
        guard isProcessing else { return }
        print("[AutoTagging] ⏹️ Cancellazione richiesta")
        isCancelled = true
        processingSinistri.removeAll()
        processingStartTimes.removeAll()
        isProcessing = false
        statusMessage = "Interrotto"
    }
    
    /// Avvia l'autotagging per un sinistro (manuale o automatico)
    /// Flusso: 1) Analizza documenti (denuncia/giustificativi) → 2) Analizza foto con contesto
    @MainActor
    func runAutoTagging(for sinistro: Sinistro, forceReanalyze: Bool = false, startPeriziaOnComplete: Bool = false) async -> Int {
        if (sinistro.stato ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("chius") {
            print("[AutoTagging] ⏭️ Sinistro chiuso, skip autotagging IA")
            statusMessage = "Sinistro chiuso: autotagging disabilitato"
            return 0
        }
        
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[AutoTagging] ❌ Cartella sinistro non trovata")
            statusMessage = "Cartella sinistro non trovata"
            return 0
        }
        
        // Pulisci eventuali elaborazioni bloccate
        cleanupStaleProcessing()
        
        // Evita elaborazioni multiple simultanee
        guard !processingSinistri.contains(riferimento) else {
            print("[AutoTagging] ⏭️ Sinistro \(riferimento) già in elaborazione")
            return 0
        }
        
        processingSinistri.insert(riferimento)
        processingStartTimes[riferimento] = Date()
        isCancelled = false
        
        defer {
            processingSinistri.remove(riferimento)
            processingStartTimes.removeValue(forKey: riferimento)
            isProcessing = false
            isCancelled = false
        }
        
        print("[AutoTagging] 🚀 Inizio elaborazione sinistro \(riferimento)")
        
        // ═══════════════════════════════════════════════════════════════
        // FASE 0: Analisi Documenti (denuncia, fatture, preventivi)
        // ═══════════════════════════════════════════════════════════════
        statusMessage = "Analisi documenti..."
        
        var context = loadDocumentiContext(for: riferimento) ?? DocumentiContext()
        let documentsToAnalyze = findDocumentsToAnalyze(in: rootPath)
        let newDocuments = documentsToAnalyze.filter { !context.fileAnalizzati.contains($0.path) }
        
        if !newDocuments.isEmpty || forceReanalyze {
            print("[AutoTagging] 📄 Fase 0: Analisi \(forceReanalyze ? documentsToAnalyze.count : newDocuments.count) documenti")
            let docsToProcess = forceReanalyze ? documentsToAnalyze : newDocuments
            
            if !docsToProcess.isEmpty {
                let extractedContext = await analyzeDocumentsForContext(docsToProcess, sinistro: sinistro)
                
                // Merge con contesto esistente
                context = mergeContexts(existing: context, new: extractedContext)
                saveDocumentiContext(context, for: riferimento)
                
                print("[AutoTagging] ✅ Contesto documenti aggiornato: \(context.beniAttesi.count) beni attesi")
                for bene in context.beniAttesi {
                    print("[AutoTagging]   • \(bene.nome): \(bene.componenti.joined(separator: ", "))")
                }
            }
        } else {
            print("[AutoTagging] ⏭️ Fase 0: Nessun nuovo documento da analizzare")
            if !context.beniAttesi.isEmpty {
                print("[AutoTagging] 📋 Usando contesto esistente: \(context.beniAttesi.count) beni")
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // FASE 1: Analisi Foto con Contesto
        // ═══════════════════════════════════════════════════════════════
        
        isProcessing = true
        progress = 0
        processedCount = 0
        statusMessage = "Scansione foto..."
        
        // Trova tutti i file foto non taggati
        let untaggedPhotos = await findUntaggedPhotos(in: rootPath, forceReanalyze: forceReanalyze)
        totalCount = untaggedPhotos.count
        
        if isCancelled {
            print("[AutoTagging] ⏹️ Elaborazione interrotta")
            return 0
        }
        
        if untaggedPhotos.isEmpty {
            print("[AutoTagging] ✅ Nessuna foto da analizzare")
            statusMessage = "Nessuna foto da analizzare"
            
            // Avvia comunque PerxiaService se richiesto, anche se non ci sono nuove foto da taggare
            if startPeriziaOnComplete {
                await avviaPerxiaAnalisi(for: sinistro)
            }
            
            isProcessing = false
            return 0
        }
        
        print("[AutoTagging] 📸 Fase 1: Trovate \(untaggedPhotos.count) foto da analizzare")
        if !context.beniAttesi.isEmpty {
            print("[AutoTagging] 📋 Contesto: \(context.beniAttesi.map { $0.nome }.joined(separator: ", "))")
        }
        statusMessage = "Analisi \(untaggedPhotos.count) foto..."
        
        // Analizza le foto in batch con contesto dei beni attesi
        print("[AutoTagging] 🚀 Inizio analisi AI con contesto...")
        
        // Salva stato per persistenza
        self.currentSinistro = sinistro
        self.pendingPhotosQueue = untaggedPhotos
        saveQueue()
        
        let results = await analyzePhotosWithAI(photos: untaggedPhotos, sinistro: sinistro, context: context)
        
        if isCancelled {
            print("[AutoTagging] ⏹️ Elaborazione interrotta durante analisi")
            return 0
        }
        
        print("[AutoTagging] ✅ Analisi AI completata: \(results.count) risultati ottenuti")
        
        // Gestisce duplicati e applica tag
        print("[AutoTagging] 🏷️ Inizio applicazione tag...")
        let taggedCount = await applyTagsWithDeduplication(results: results)
        print("[AutoTagging] ✅ Tag applicati: \(taggedCount) foto taggate")
        
        // Pulisci coda persistente
        self.pendingPhotosQueue.removeAll()
        self.currentSinistro = nil
        saveQueue()
        
        isProcessing = false
        progress = 1.0
        statusMessage = "Completato: \(taggedCount) foto"
        
        print("[AutoTagging] ✅ Completato: \(taggedCount) foto taggate su \(untaggedPhotos.count) analizzate")
        
        // Notifica completamento
        if taggedCount > 0 {
            markAutoTaggingCompleted(for: sinistro)
            onAutoTaggingCompleted?(sinistro, taggedCount)
            sendCompletionNotification(count: taggedCount, for: sinistro)
        }
        
        // Avvia PerxiaService al termine se richiesto
        if startPeriziaOnComplete {
            await avviaPerxiaAnalisi(for: sinistro)
        }
        
        return taggedCount
    }
    
    /// Avvia l'analisi PerxiaService per il sinistro
    private func avviaPerxiaAnalisi(for sinistro: Sinistro) async {
        print("[AutoTagging] 🤖 Avvio PerxiaService per \(sinistro.riferimento ?? "N/A")")
        
        // Determina i parametri di default per l'analisi
        let fulminazione = true // Default per il sistema
        let sopralluogo = false // Default se non specificato
        let ubicazione = sinistro.indirizzoAssicurato ?? sinistro.indirizzoDanneggiato ?? ""
        
        _ = await PerxiaService.shared.analizzaSinistroCompleto(
            sinistro: sinistro,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            streamCallback: { _ in },
            progressCallback: { _ in },
            beneCallback: { _ in }
        )
    }
    
    /// Autotagging per file specifici (es. da menu contestuale)
    @MainActor
    func autoTagFiles(_ fileURLs: [URL], for sinistro: Sinistro) async -> Int {
        guard !fileURLs.isEmpty else { return 0 }
        
        if (sinistro.stato ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("chius") {
            print("[AutoTagging] ⏭️ Sinistro chiuso, skip autotagging IA (file specifici)")
            statusMessage = "Sinistro chiuso: autotagging disabilitato"
            return 0
        }
        
        isProcessing = true
        progress = 0
        processedCount = 0
        totalCount = fileURLs.count
        statusMessage = "Analisi \(fileURLs.count) file..."
        isCancelled = false
        
        defer {
            isProcessing = false
            isCancelled = false
        }
        
        // Filtra solo i file immagine
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
        let photoFiles = fileURLs.filter { photoExtensions.contains($0.pathExtension.lowercased()) }
        
        if photoFiles.isEmpty {
            statusMessage = "Nessuna immagine da analizzare"
            return 0
        }
        
        totalCount = photoFiles.count
        
        // Carica il contesto se disponibile
        let context = sinistro.riferimento.flatMap { loadDocumentiContext(for: $0) }
        
        // Analizza le foto con il contesto
        let results = await analyzePhotosWithAI(photos: photoFiles, sinistro: sinistro, context: context)
        
        if isCancelled {
            print("[AutoTagging] ⏹️ Elaborazione interrotta")
            return 0
        }
        
        let taggedCount = await applyTagsWithDeduplication(results: results)
        
        progress = 1.0
        statusMessage = "Completato: \(taggedCount) foto"
        
        return taggedCount
    }
    
    /// Verifica se ci sono foto taggate per un sinistro
    func hasTaggedPhotos(for sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[AutoTagging] ⚠️ hasTaggedPhotos: percorso non trovato per \(sinistro.riferimento ?? "N/A")")
            return false
        }
        
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
        
        // Usa FileService per avere security scoped access
        let result = FileService.shared.performWithSecurityScopedAccess(to: rootPath) { () -> Bool in
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: rootPath),
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            while let url = enumerator?.nextObject() as? URL {
                // Salta directory "Da Chiudere" e simili
                if url.lastPathComponent.lowercased().hasPrefix("da chiudere") {
                    enumerator?.skipDescendants()
                    continue
                }
                
                let ext = url.pathExtension.lowercased()
                guard photoExtensions.contains(ext) else { continue }
                
                let tags = fileTagManager.getTagsForFile(at: url.path)
                if !tags.isEmpty {
                    print("[AutoTagging] ✅ Foto taggata trovata: \(url.lastPathComponent) con tag: \(tags.map { $0.id }.joined(separator: ", "))")
                    return true
                }
            }
            
            return false
        }
        
        let hasTagged = result ?? false
        print("[AutoTagging] 🏷️ hasTaggedPhotos per \(sinistro.riferimento ?? "N/A"): \(hasTagged)")
        return hasTagged
    }
    
    /// Verifica se esistono foto nella cartella del sinistro
    func hasPhotosInFolder(for sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[AutoTagging] ⚠️ hasPhotosInFolder: percorso non trovato per \(sinistro.riferimento ?? "N/A")")
            return false
        }
        
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
        
        // Usa FileService per avere security scoped access
        let result = FileService.shared.performWithSecurityScopedAccess(to: rootPath) { () -> Bool in
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: rootPath),
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            while let url = enumerator?.nextObject() as? URL {
                // Salta directory "Da Chiudere" e simili
                if url.lastPathComponent.lowercased().hasPrefix("da chiudere") {
                    enumerator?.skipDescendants()
                    continue
                }
                
                let ext = url.pathExtension.lowercased()
                if photoExtensions.contains(ext) {
                    print("[AutoTagging] ✅ Foto trovata: \(url.lastPathComponent)")
                    return true
                }
            }
            
            return false
        }
        
        let hasPhotos = result ?? false
        print("[AutoTagging] 📸 hasPhotosInFolder per \(sinistro.riferimento ?? "N/A"): \(hasPhotos)")
        return hasPhotos
    }
    
    /// Verifica se un sinistro ha già eseguito l'autotagging
    func hasRunAutoTagging(for sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento else { return false }
        return UserDefaults.standard.bool(forKey: "autoTagging_completed_\(riferimento)")
    }
    
    /// Segna un sinistro come processato per autotagging
    private func markAutoTaggingCompleted(for sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento else { return }
        UserDefaults.standard.set(true, forKey: "autoTagging_completed_\(riferimento)")
    }
    
    /// Avvia autotagging automatico se è la prima volta che si apre la cartella
    @MainActor
    func runAutoTaggingIfNeeded(for sinistro: Sinistro) async {
        // Disabilitato: non deve partire "da solo" mai.
        print("[AutoTagging] ⏭️ runAutoTaggingIfNeeded disabilitato (usa AutoCheckService)")
        return
    }
    
    // MARK: - Scansione File
    
    private func findUntaggedPhotos(in path: String, forceReanalyze: Bool) async -> [URL] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
                
                // Usa FileService per avere security scoped access
                let result = FileService.shared.performWithSecurityScopedAccess(to: path) { () -> (photos: [URL], stats: (total: Int, analyzed: Int, tagged: Int)) in
                    var foundPhotos: [URL] = []
                    var totalPhotos = 0
                    var skippedAnalyzed = 0
                    var skippedTagged = 0
                    
                    // Scansiona ricorsivamente
                    let enumerator = FileManager.default.enumerator(
                        at: URL(fileURLWithPath: path),
                        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )
                    
                    while let url = enumerator?.nextObject() as? URL {
                        // Salta directory "Da Chiudere" e simili
                        if url.lastPathComponent.lowercased().hasPrefix("da chiudere") {
                            enumerator?.skipDescendants()
                            continue
                        }
                        
                        let ext = url.pathExtension.lowercased()
                        guard photoExtensions.contains(ext) else { continue }
                        
                        totalPhotos += 1
                        
                        // Salta se già analizzata (a meno che non sia forceReanalyze)
                        if !forceReanalyze && self.analyzedPaths.contains(url.path) {
                            skippedAnalyzed += 1
                            continue
                        }
                        
                        // Salta se ha già tag (a meno che non sia forceReanalyze)
                        if !forceReanalyze {
                            let existingTags = self.fileTagManager.getTagsForFile(at: url.path)
                            if !existingTags.isEmpty {
                                skippedTagged += 1
                                continue
                            }
                        }
                        
                        foundPhotos.append(url)
                    }
                    
                    return (foundPhotos, (total: totalPhotos, analyzed: skippedAnalyzed, tagged: skippedTagged))
                }
                
                let photos = result?.photos ?? []
                let stats = result?.stats ?? (total: 0, analyzed: 0, tagged: 0)
                
                print("[AutoTagging] 🔍 Scansione completata:")
                print("[AutoTagging]   - Foto totali trovate: \(stats.total)")
                print("[AutoTagging]   - Saltate (già analizzate): \(stats.analyzed)")
                print("[AutoTagging]   - Saltate (già taggate): \(stats.tagged)")
                print("[AutoTagging]   - Foto da analizzare: \(photos.count)")
                
                if photos.isEmpty && stats.total == 0 {
                    print("[AutoTagging] ⚠️ Nessuna foto trovata - possibile problema di accesso alla directory")
                }
                
                continuation.resume(returning: photos)
            }
        }
    }
    
    // MARK: - Analisi Documenti (Fase 0)
    
    /// Trova i documenti da analizzare (denuncia, fatture, preventivi)
    private func findDocumentsToAnalyze(in path: String) -> [URL] {
        var documents: [URL] = []
        let documentExtensions = ["pdf", "jpg", "jpeg", "png", "heic"]
        let documentTags = ["denuncia", "fattura", "preventivo", "perizia_tecnica"]
        
        // Cerca file con tag documento
        let result = FileService.shared.performWithSecurityScopedAccess(to: path) { () -> [URL] in
            var found: [URL] = []
            
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            while let url = enumerator?.nextObject() as? URL {
                // Salta cartella Da Chiudere
                if url.lastPathComponent.lowercased().hasPrefix("da chiudere") {
                    enumerator?.skipDescendants()
                    continue
                }
                
                let ext = url.pathExtension.lowercased()
                guard documentExtensions.contains(ext) else { continue }
                
                // Controlla se ha un tag documento (SOLO tramite tag, non nomi file)
                let tags = self.fileTagManager.getTagsForFile(at: url.path)
                let hasDocumentTag = tags.contains { tag in
                    documentTags.contains(tag.id)
                }
                
                if hasDocumentTag {
                    found.append(url)
                }
            }
            
            return found
        }
        
        return result ?? []
    }
    
    /// Analizza i documenti per estrarre il contesto (beni attesi, ubicazione, etc.)
    private func analyzeDocumentsForContext(_ documents: [URL], sinistro: Sinistro) async -> DocumentiContext {
        var context = DocumentiContext()
        context.dataAnalisi = Date()
        
        guard !documents.isEmpty else { return context }
        
        print("[AutoTagging] 📄 Analisi \(documents.count) documenti per estrazione contesto...")
        
        // Prepara il prompt per l'estrazione
        let prompt = buildDocumentContextPrompt(for: sinistro)
        
        // Prepara i path dei documenti
        let documentPaths = documents.map { $0.path }
        context.fileAnalizzati = documentPaths
        
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [],
            allowFallback: false,
            parameters: [
                "prompt": AnyCodable(prompt),
                "images": AnyCodable(documentPaths),
                "stream": AnyCodable(false),
                "response_format": AnyCodable(["type": "json_object"]),
                "max_tokens": AnyCodable(4000)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task) { aiResult in
                    if resumed { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi documenti")))
                    }
                }
            }
        }
        
        switch result {
        case .success(let aiResult):
            if let parsedContext = parseDocumentContextResult(aiResult, sinistro: sinistro) {
                context.beniAttesi = parsedContext.beniAttesi
                context.vociGiustificativi = parsedContext.vociGiustificativi
                context.verificaIndirizzo = parsedContext.verificaIndirizzo
                context.dataSinistroDenuncia = parsedContext.dataSinistroDenuncia
                context.noteGenerali = parsedContext.noteGenerali
            }
        case .failure(let error):
            print("[AutoTagging] ⚠️ Errore analisi documenti: \(error)")
        }
        
        return context
    }
    
    private func buildDocumentContextPrompt(for sinistro: Sinistro) -> String {
        // Prepara i dati del sinistro per controlli incrociati
        let indirizzoNostro = sinistro.indirizzoAssicurato ?? sinistro.indirizzoDanneggiato ?? ""
        let nomeAssicuratoNostro = sinistro.nomeAssicurato ?? ""
        let tipoPolizza = sinistro.tipoPolizza ?? ""
        
        return """
        Rispondi in formato JSON. Analizza questi documenti di una pratica assicurativa per Fenomeno Elettrico.
        
        DATI DEL SINISTRO (per controlli incrociati):
        - Indirizzo in nostro possesso: "\(indirizzoNostro)"
        - Nome assicurato: "\(nomeAssicuratoNostro)"
        - Tipo polizza: "\(tipoPolizza)"
        
        OBIETTIVO: Estrarre informazioni per:
        1. Identificare i beni danneggiati e relativi componenti
        2. Estrarre TUTTE le voci economiche dai giustificativi (preventivi/fatture)
        3. Verificare corrispondenza indirizzo denuncia vs nostri dati
        
        ESTRAZIONE BENI:
        - Elenca SOLO beni effettivamente menzionati
        - Usa nomi generici senza marca/modello (es. "caldaia" non "Viessmann V200")
        - Per ogni bene, elenca i componenti citati
        
        ESTRAZIONE VOCI ECONOMICHE (CRITICO):
        - Se il documento SCOMPONE in voci singole: estrai OGNI voce con suo importo
        - Se il documento ha un IMPORTO A CORPO: crea UNA voce con isACorpo=true
        - Ogni voce può riferirsi a UNO o PIÙ beni (es. "riparazione impianto elettrico e allarme")
        - Indica il tipo: materiale, manodopera, a_corpo, altro
        - ESTRAI SEMPRE la DATA e il NUMERO del documento (fattura/preventivo) se presente.
        
        VERIFICA INDIRIZZO:
        - Confronta l'indirizzo nella denuncia con quello in nostro possesso
        - Indica se c'è match completo, parziale (es. "via Verdi 3/A" vs "via Verdi 3") o nessun match
        
        OUTPUT JSON:
        {
            "beniAttesi": [
                {
                    "nome": "nome bene generico",
                    "componenti": ["componente1", "componente2"],
                    "fonte": "denuncia|preventivo|fattura",
                    "descrizioneBreve": "breve descrizione danno"
                }
            ],
            "vociGiustificativi": [
                {
                    "descrizione": "descrizione voce",
                    "importo": 123.45,
                    "beniAssociati": ["bene1", "bene2"],
                    "tipo": "materiale|manodopera|a_corpo|altro",
                    "isACorpo": false,
                    "dataDocumento": "YYYY-MM-DD",
                    "numeroDocumento": "numero fattura/preventivo"
                }
            ],
            "verificaIndirizzo": {
                "indirizzoDenuncia": "indirizzo letto dalla denuncia",
                "matchCompleto": true/false,
                "matchParziale": true/false,
                "differenze": "descrizione differenze se non match",
                "daVerificare": true/false
            },
            "dataSinistroDenuncia": "YYYY-MM-DD" o null,
            "noteGenerali": "note importanti, anomalie rilevate"
        }
        
        SINISTRO: \(sinistro.riferimento ?? "N/A")
        """
    }
    
    private func parseDocumentContextResult(_ aiResult: AIResult, sinistro: Sinistro) -> DocumentiContext? {
        guard let resultText = aiResult.result?.value as? String else { return nil }
        
        var cleanedText = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        } else if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if let endRange = cleanedText.range(of: "```", options: .backwards) {
            cleanedText = String(cleanedText[..<endRange.lowerBound])
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedText.data(using: .utf8) else { return nil }
        
        struct RawContext: Codable {
            let beniAttesi: [RawBene]?
            let vociGiustificativi: [RawVoce]?
            let verificaIndirizzo: RawVerificaIndirizzo?
            let dataSinistroDenuncia: String?
            let noteGenerali: String?
            
            struct RawBene: Codable {
                let nome: String
                let componenti: [String]?
                let fonte: String?
                let descrizioneBreve: String?
            }
            
            struct RawVoce: Codable {
                let descrizione: String
                let importo: Double
                let beniAssociati: [String]?
                let tipo: String?
                let isACorpo: Bool?
                let dataDocumento: String?
                let numeroDocumento: String?
            }
            
            struct RawVerificaIndirizzo: Codable {
                let indirizzoDenuncia: String?
                let matchCompleto: Bool?
                let matchParziale: Bool?
                let differenze: String?
                let daVerificare: Bool?
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        do {
            let raw = try JSONDecoder().decode(RawContext.self, from: data)
            
            var context = DocumentiContext()
            
            // Converti beni
            context.beniAttesi = (raw.beniAttesi ?? []).map { rawBene in
                BeneAtteso(
                    nome: rawBene.nome,
                    componenti: rawBene.componenti ?? [],
                    fonte: rawBene.fonte ?? "documento",
                    descrizioneBreve: rawBene.descrizioneBreve
                )
            }
            
            // Converti voci giustificativi
            context.vociGiustificativi = (raw.vociGiustificativi ?? []).map { rawVoce in
                let tipoVoce: VoceGiustificativo.TipoVoce
                switch rawVoce.tipo?.lowercased() {
                case "materiale": tipoVoce = .materiale
                case "manodopera": tipoVoce = .manodopera
                case "a_corpo": tipoVoce = .aCorpo
                default: tipoVoce = .altro
                }
                
                // Parsing della data documento
                var dataDoc: Date? = nil
                if let dateStr = rawVoce.dataDocumento {
                    dataDoc = dateFormatter.date(from: dateStr)
                }
                
                return VoceGiustificativo(
                    descrizione: rawVoce.descrizione,
                    importo: rawVoce.importo,
                    beniAssociati: rawVoce.beniAssociati ?? [],
                    tipo: tipoVoce,
                    fonte: "documento",
                    isACorpo: rawVoce.isACorpo ?? false,
                    dataDocumento: dataDoc,
                    numeroDocumento: rawVoce.numeroDocumento
                )
            }
            
            // Converti verifica indirizzo
            if let rawVerifica = raw.verificaIndirizzo {
                let indirizzoSinistro = sinistro.indirizzoAssicurato ?? sinistro.indirizzoDanneggiato
                
                context.verificaIndirizzo = VerificaIndirizzo(
                    indirizzoDenuncia: rawVerifica.indirizzoDenuncia,
                    indirizzoSinistro: indirizzoSinistro,
                    matchCompleto: rawVerifica.matchCompleto ?? false,
                    matchParziale: rawVerifica.matchParziale ?? false,
                    differenze: rawVerifica.differenze,
                    daVerificare: rawVerifica.daVerificare ?? false
                )
            }
            
            // Data sinistro dalla denuncia
            if let dateStr = raw.dataSinistroDenuncia {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                context.dataSinistroDenuncia = formatter.date(from: dateStr)
            }
            
            context.noteGenerali = raw.noteGenerali
            
            // Verifica date giustificativi vs data sinistro
            context.alertDocumenti = verificaDateGiustificativi(voci: context.vociGiustificativi, sinistro: sinistro)
            
            print("[AutoTagging] ✅ Contesto estratto: \(context.beniAttesi.count) beni, \(context.vociGiustificativi.count) voci economiche")
            if let verifica = context.verificaIndirizzo {
                if verifica.matchCompleto {
                    print("[AutoTagging] ✅ Indirizzo: match completo")
                } else if verifica.matchParziale {
                    print("[AutoTagging] ⚠️ Indirizzo: match parziale - da verificare")
                } else if verifica.daVerificare {
                    print("[AutoTagging] ⚠️ Indirizzo: da verificare - \(verifica.differenze ?? "differenze non specificate")")
                }
            }
            if context.alertDocumenti.hasAlerts {
                print("[AutoTagging] ⚠️ ALERT: \(context.alertDocumenti.giustificativiAntecedenti.count) giustificativi antecedenti alla data sinistro")
            }
            return context
            
        } catch {
            print("[AutoTagging] ⚠️ Errore parsing contesto: \(error)")
            return nil
        }
    }
    
    /// Verifica che le date dei giustificativi non siano antecedenti alla data del sinistro
    private func verificaDateGiustificativi(voci: [VoceGiustificativo], sinistro: Sinistro) -> AlertDocumenti {
        var alert = AlertDocumenti()
        
        // Usa la data sinistro dai dati del sinistro
        guard let dataSinistro = sinistro.dataSinistro else {
            print("[AutoTagging] ⚠️ Data sinistro non disponibile, skip verifica date giustificativi")
            return alert
        }
        
        let calendar = Calendar.current
        
        // Raggruppa le voci per documento (usando fonte + numeroDocumento + dataDocumento)
        var documentiVerificati: Set<String> = []
        
        for voce in voci {
            guard let dataDoc = voce.dataDocumento else { continue }
            
            // Crea chiave univoca per il documento
            let chiaveDoc = "\(voce.fonte)_\(voce.numeroDocumento ?? "")_\(dataDoc.timeIntervalSince1970)"
            
            // Evita di segnalare lo stesso documento più volte
            guard !documentiVerificati.contains(chiaveDoc) else { continue }
            documentiVerificati.insert(chiaveDoc)
            
            // Confronta le date (solo giorno, ignora ora)
            let dataDocGiorno = calendar.startOfDay(for: dataDoc)
            let dataSinistroGiorno = calendar.startOfDay(for: dataSinistro)
            
            if dataDocGiorno < dataSinistroGiorno {
                // Documento antecedente al sinistro!
                let differenza = calendar.dateComponents([.day], from: dataDocGiorno, to: dataSinistroGiorno).day ?? 0
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd/MM/yyyy"
                
                let antecedente = GiustificativoAntecedente(
                    nomeFile: voce.fonte,
                    dataDocumento: dataDoc,
                    dataSinistro: dataSinistro,
                    differenzaGiorni: -differenza,
                    descrizione: "Documento datato \(dateFormatter.string(from: dataDoc)), sinistro del \(dateFormatter.string(from: dataSinistro)) (\(differenza) giorni prima)"
                )
                
                alert.giustificativiAntecedenti.append(antecedente)
                print("[AutoTagging] ⚠️ ALERT: Giustificativo '\(voce.numeroDocumento ?? "N/A")' datato \(differenza) giorni PRIMA del sinistro!")
            }
        }
        
        return alert
    }
    
    /// Unisce due contesti, mantenendo i beni e voci unici
    private func mergeContexts(existing: DocumentiContext, new: DocumentiContext) -> DocumentiContext {
        var merged = existing
        
        // Merge beni (evita duplicati per nome)
        var beniSet = Set(existing.beniAttesi)
        for bene in new.beniAttesi {
            if !beniSet.contains(bene) {
                merged.beniAttesi.append(bene)
                beniSet.insert(bene)
            }
        }
        
        // Merge voci giustificativi (aggiungi tutte, potrebbero essere da documenti diversi)
        merged.vociGiustificativi.append(contentsOf: new.vociGiustificativi)
        
        // Merge alert documenti
        merged.alertDocumenti.giustificativiAntecedenti.append(contentsOf: new.alertDocumenti.giustificativiAntecedenti)
        merged.alertDocumenti.altreAnomalie.append(contentsOf: new.alertDocumenti.altreAnomalie)
        
        // Usa verifica indirizzo più recente se presente
        if new.verificaIndirizzo != nil { merged.verificaIndirizzo = new.verificaIndirizzo }
        if new.dataSinistroDenuncia != nil { merged.dataSinistroDenuncia = new.dataSinistroDenuncia }
        if new.noteGenerali != nil { merged.noteGenerali = new.noteGenerali }
        
        // Merge file analizzati
        merged.fileAnalizzati = Array(Set(existing.fileAnalizzati + new.fileAnalizzati))
        merged.dataAnalisi = Date()
        
        return merged
    }
    
    // MARK: - Analisi Foto (Fase 1)
    
    private func analyzePhotosWithAI(photos: [URL], sinistro: Sinistro, context: DocumentiContext? = nil) async -> [PhotoAnalysisResult] {
        var results: [PhotoAnalysisResult] = []
        
        // Verifica se il modello locale è disponibile
        let isLocalAvailable = await AIManager.shared.checkProviderAvailable(.localMultimodal)
        
        if isLocalAvailable {
            // Modello locale: analizza una foto alla volta
            print("[AutoTagging] 🖥️ Usando modello locale - analisi singola")
            for (index, photo) in photos.enumerated() {
                if isCancelled {
                    print("[AutoTagging] ⏹️ Elaborazione interrotta")
                    break
                }
                
                await MainActor.run {
                    currentFile = photo.lastPathComponent
                    progress = Double(index) / Double(photos.count)
                    processedCount = index
                    statusMessage = "Analisi \(index + 1)/\(photos.count)..."
                }
                
                if let result = await analyzeSinglePhoto(photo, sinistro: sinistro, existingResults: results, context: context) {
                    results.append(result)
                    analyzedPaths.insert(photo.path)
                }
            }
        } else {
            // Modello cloud: analizza in batch per efficienza
            // Batch da 5 foto, max 3 chiamate simultanee gestite da AIManager
            let batchSize = 5
            let batches = stride(from: 0, to: photos.count, by: batchSize).map {
                Array(photos[$0..<min($0 + batchSize, photos.count)])
            }
            
            print("[AutoTagging] ☁️ Usando modello cloud - analisi batch (\(batches.count) batch da max \(batchSize) foto)")
            
            // Salva i risultati iniziali (prima dei batch) per la deduplicazione
            let initialResults = results
            
            // Esegui i batch in sequenza (AIManager gestirà la concorrenza di 3 task cloud)
            var allBatchResults: [PhotoAnalysisResult] = []
            
            for (batchIndex, batch) in batches.enumerated() {
                if isCancelled {
                    print("[AutoTagging] ⏹️ Elaborazione interrotta")
                    break
                }
                
                // Aggiorna progresso
                await MainActor.run {
                    currentFile = "Batch \(batchIndex + 1)/\(batches.count)"
                    progress = Double(batchIndex) / Double(batches.count)
                    statusMessage = "Analisi batch \(batchIndex + 1)/\(batches.count)..."
                }
                
                // Analizza il batch - AIManager.enqueue gestirà il limite di 3 simultanei e cooldown
                let batchResults = await analyzeBatchPhotos(batch, sinistro: sinistro, existingResults: initialResults + allBatchResults, context: context)
                allBatchResults.append(contentsOf: batchResults)
                
                // Aggiorna coda persistente rimuovendo i file processati
                for url in batch {
                    pendingPhotosQueue.removeAll { $0.path == url.path }
                }
                saveQueue()
                
                print("[AutoTagging] ✅ Batch \(batchIndex + 1)/\(batches.count) completato")
                
                // Aggiorna progresso
                await MainActor.run {
                    progress = Double(batchIndex + 1) / Double(batches.count)
                    statusMessage = "Batch \(batchIndex + 1)/\(batches.count) completati..."
                }
            }
            
            // Deduplicazione finale tra batch
            // Se più batch hanno identificato foto dello stesso bene con daAllegare=true, mantieni solo la migliore
            var beneToBestPhoto: [String: PhotoAnalysisResult] = [:]
            var resultsToAdd: [PhotoAnalysisResult] = []
            
            for result in allBatchResults {
                // Se non è da allegare o non ha bene, aggiungilo direttamente
                guard let bene = result.beneRiferimento, result.daAllegare else {
                    resultsToAdd.append(result)
                    continue
                }
                
                // Se è da allegare e ha un bene, confronta con le altre
                if let existing = beneToBestPhoto[bene] {
                    // Mantieni quella con qualità migliore o confidenza maggiore
                    if result.qualita.rawValue > existing.qualita.rawValue ||
                       (result.qualita == existing.qualita && (result.confidenza ?? 0) > (existing.confidenza ?? 0)) {
                        // La nuova è migliore, marca la vecchia come non da allegare
                        var updatedExisting = existing
                        updatedExisting.daAllegare = false
                        resultsToAdd.append(updatedExisting)
                        beneToBestPhoto[bene] = result
                    } else {
                        // La vecchia è migliore, marca questa come non da allegare
                        var updatedResult = result
                        updatedResult.daAllegare = false
                        resultsToAdd.append(updatedResult)
                    }
                } else {
                    beneToBestPhoto[bene] = result
                }
            }
            
            // Aggiungi tutti i risultati (inclusi quelli deduplicati)
            for result in resultsToAdd {
                results.append(result)
                analyzedPaths.insert(result.path)
            }
            
            // Aggiungi le migliori foto per ogni bene (quelle da allegare)
            for (_, bestPhoto) in beneToBestPhoto {
                results.append(bestPhoto)
                analyzedPaths.insert(bestPhoto.path)
            }
            
            await MainActor.run {
                processedCount = photos.count
            }
        }
        
        return results
    }
    
    // MARK: - Analisi Batch (server-rendered prompt + routing)
    //
    // Il body del prompt è ora gestito dal backend: chiamiamo
    // AIPromptRegistry.renderPrompt con le 4 variabili e riceviamo il testo
    // gia pronto + version_id da loggare nel run.
    // L'esecuzione passa da AIRouter, che applica la policy (phase, trigger)
    // e gestisce il fallback automatico locale→cloud su errore o output
    // malformato (validate JSON con array `results`).
    //
    // Se il backend non risponde (offline + cache vuota) cadiamo sul prompt
    // inline `buildBatchAnalysisPrompt` (versione locale) per non perdere la
    // funzionalita in scenari offline.
    //
    // TODO slice background: il `trigger` qui e hardcoded a `.userInitiated`.
    // Quando wireremo la scansione automatica foto da mail/WA propagheremo
    // `.background` lungo la catena `AutoCheckService.scanNewFilesForTags`
    // -> `runAutoTagging` -> `analyzePhotosWithAI` -> qui.
    private func analyzeBatchPhotos(_ urls: [URL], sinistro: Sinistro, existingResults: [PhotoAnalysisResult], context: DocumentiContext? = nil) async -> [PhotoAnalysisResult] {
        let fileNames = urls.map { $0.lastPathComponent }.joined(separator: ", ")
        print("[AutoTagging] 📦 Analisi batch di \(urls.count) foto: \(fileNames)")

        let imagePaths = urls.map { $0 }
        let systemPrompt = "Sei un sistema di classificazione automatica per foto di perizie assicurative. Il tuo UNICO compito è CLASSIFICARE le foto assegnando tag, tipo, bene e componente. NON estrarre dettagli tecnici, NON fare analisi approfondite, NON descrivere in dettaglio. Rispondi SEMPRE in formato JSON con la struttura richiesta."
        let variables = buildBatchTaggingVariables(for: urls, context: context)

        // 1) Server-render del prompt (preferito). Se fallisce, fallback inline.
        var renderedPrompt: String
        var versionID: String
        do {
            let rendered = try await AIPromptRegistry.shared.renderPrompt(
                phase: AISinistroPhase.tagging,
                variables: variables
            )
            renderedPrompt = rendered.body_rendered
            versionID = rendered.version_id ?? "unknown"
            print("[AutoTagging] 🎯 Prompt server-rendered version=\(versionID)")
        } catch {
            print("[AutoTagging] ⚠️ renderPrompt fallito (\(error)), fallback locale inline")
            renderedPrompt = buildBatchAnalysisPrompt(for: urls, sinistro: sinistro, context: context)
            versionID = "local-inline-fallback"
        }

        // 2) Routing via policy (phase, trigger) + auto-fallback su errore/malformato.
        let outcome = await AIRouter.shared.run(
            phase: AISinistroPhase.tagging,
            trigger: .userInitiated,
            sinistroRef: sinistro.riferimento,
            renderedPrompt: renderedPrompt,
            promptVersionID: versionID,
            images: imagePaths,
            systemPrompt: systemPrompt,
            additionalParameters: [
                "stream": AnyCodable(false),
                "response_format": AnyCodable(["type": "json_object"]),
                "max_tokens": AnyCodable(4000)
            ],
            taskType: .documentAnalysis,
            priority: .secondary,
            validate: isValidBatchTaggingResponse
        )

        if let output = outcome.output, outcome.status != .error {
            print("[AutoTagging] ✅ Batch ok (provider=\(outcome.providerUsed?.rawValue ?? "?"), \(outcome.latencyMs)ms)")
            let pseudoResult = AIResult(
                taskID: UUID(),
                success: true,
                provider: outcome.providerUsed ?? .cloudOpenAI,
                result: AnyCodable(output),
                processingTime: TimeInterval(outcome.latencyMs) / 1000.0
            )
            let parsed = parseBatchAnalysisResult(pseudoResult, for: urls, existingResults: existingResults)
            print("[AutoTagging] ✅ Batch parsing completato: \(parsed.count) foto")
            return parsed
        }

        print("[AutoTagging] ❌ Batch fallito (\(outcome.errorMessage ?? "?")), fallback single-photo")
        var fallbackResults: [PhotoAnalysisResult] = []
        for url in urls {
            if let result = await analyzeSinglePhoto(url, sinistro: sinistro, existingResults: existingResults + fallbackResults, context: context) {
                fallbackResults.append(result)
            }
        }
        return fallbackResults
    }

    /// Costruisce le 4 variabili che il template `sinistri.tagging` si aspetta.
    /// Estratto da `buildBatchAnalysisPrompt` (che rimane come fallback offline).
    private func buildBatchTaggingVariables(for urls: [URL], context: DocumentiContext?) -> [String: String] {
        let tagList = FileTagManager.FileTag.availableTags
            .filter { $0.category == .foto || ["fattura", "preventivo"].contains($0.id) }
            .map { "\($0.id): \($0.name)" }
            .joined(separator: ", ")

        let fileList = urls.enumerated()
            .map { "- Foto \($0.offset + 1): \($0.element.lastPathComponent)" }
            .joined(separator: "\n")

        var contextSection = ""
        if let ctx = context, !ctx.beniAttesi.isEmpty {
            let beniList = ctx.beniAttesi.map { bene -> String in
                var line = "• \(bene.nome)"
                if !bene.componenti.isEmpty {
                    line += " (componenti: \(bene.componenti.joined(separator: ", ")))"
                }
                return line
            }.joined(separator: "\n")
            contextSection = """

            CONTESTO DAI DOCUMENTI (beni POSSIBILI, non vincolanti):
            I seguenti beni sono stati menzionati nei documenti del sinistro. Usali come SUGGERIMENTO per identificare le foto, ma NON limitarti solo a questi se vedi altri beni:
            \(beniList)

            """
        }

        return [
            "n_foto": "\(urls.count)",
            "file_list": fileList,
            "context_section": contextSection,
            "tag_list": tagList,
        ]
    }

    /// Validate per AIRouter: l'output deve essere JSON con array `results`.
    /// Un locale che sbaglia formato cade automaticamente sul cloud successivo.
    private func isValidBatchTaggingResponse(_ text: String) -> Bool {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if let end = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<end.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["results"] as? [Any], !arr.isEmpty else {
            return false
        }
        return true
    }
    
    private func buildBatchAnalysisPrompt(for urls: [URL], sinistro: Sinistro, context: DocumentiContext? = nil) -> String {
        // Solo tag foto e giustificativi (fattura, preventivo), NO atti
        let tagList = FileTagManager.FileTag.availableTags
            .filter { $0.category == .foto || ["fattura", "preventivo"].contains($0.id) }
            .map { "\($0.id): \($0.name)" }
            .joined(separator: ", ")
        
        let fileList = urls.enumerated().map { "- Foto \($0.offset + 1): \($0.element.lastPathComponent)" }.joined(separator: "\n")
        
        // Costruisci sezione contesto beni (opzionale, non vincolante)
        var contextSection = ""
        if let ctx = context, !ctx.beniAttesi.isEmpty {
            let beniList = ctx.beniAttesi.map { bene in
                var line = "• \(bene.nome)"
                if !bene.componenti.isEmpty {
                    line += " (componenti: \(bene.componenti.joined(separator: ", ")))"
                }
                return line
            }.joined(separator: "\n")
            
            contextSection = """
            
            CONTESTO DAI DOCUMENTI (beni POSSIBILI, non vincolanti):
            I seguenti beni sono stati menzionati nei documenti del sinistro. Usali come SUGGERIMENTO per identificare le foto, ma NON limitarti solo a questi se vedi altri beni:
            \(beniList)
            
            """
        }
        
        return """
        COMPITO: Classifica queste \(urls.count) foto per un sistema di tagging automatico. NON fare analisi approfondite, solo classificazione.
        
        FOTO DA CLASSIFICARE:
        \(fileList)
        \(contextSection)
        
        ⛔ COSA NON FARE:
        - NON estrarre dettagli tecnici (marca, modello, specifiche)
        - NON fare analisi approfondite del contenuto
        - NON descrivere in dettaglio cosa vedi
        - NON usare chiavi come "analisi_documento", "dettagli_tecnici", "immagini"
        
        ✅ COSA FARE:
        - Identifica il TIPO di foto (bene, componente, ubicazione, documento, test)
        - Identifica il BENE (solo nome generico, es. "caldaia" non "Ignis AFE 941")
        - Identifica il COMPONENTE se presente (solo nome, es. "scheda elettronica")
        - Valuta la QUALITÀ visiva
        - Decidi se ALLEGARE (true se rappresentativa, false se duplicata/dettaglio)
        
        REGOLE IMPORTANTI:
        1. BENE = impianto completo (caldaia, cancello, fotovoltaico) - SOLO NOME, NO MARCA/MODELLO
        2. COMPONENTE = parte del bene (scheda, motore, varistore) - SOLO NOME, NO MARCA/MODELLO
        3. BENE RIFERIMENTO OBBLIGATORIO per:
           - foto_componente: DEVI sempre indicare il bene a cui appartiene il componente
           - foto_test_funzionale: DEVI sempre indicare il bene su cui è stato fatto il test
           - test_strumentale: DEVI sempre indicare il bene su cui è stato fatto il test
           - foto_ripristino: DEVI sempre indicare il bene che è stato riparato
        4. UBICAZIONE: identifica il tipo corretto:
           - "foto_ubicazione_rischio": ubicazione del rischio assicurato (esterno, stabile, indirizzo)
           - "foto_ubicazione_tecnico": ubicazione tecnica del bene/impianto (locale tecnico, box, garage)
           - "foto_ubicazione_amministratore": ubicazione amministratore (sede amministrativa, uffici)
           - "foto_ubicazione_altra": altra ubicazione non classificabile nelle precedenti
        5. DOCUMENTI: identifica se fattura, preventivo, atto
        6. QUALITÀ: "buona" (nitida), "media" (accettabile), "scarsa" (sfocata), "irrilevante"
        
        TAG DISPONIBILI: \(tagList)
        
        FORMATO RISPOSTA (JSON OBBLIGATORIO):
        {
            "results": [
                {
                    "filename": "1000136694.jpg",
                    "tipo": "foto_bene",
                    "tagSuggerito": "foto_bene",
                    "beneRiferimento": "caldaia",
                    "componente": null,
                    "descrizione": "Foto caldaia",
                    "qualita": "buona",
                    "daAllegare": true,
                    "confidenza": 0.9
                },
                {
                    "filename": "test_funzionale.jpg",
                    "tipo": "foto_test_funzionale",
                    "tagSuggerito": "foto_test_funzionale",
                    "beneRiferimento": "caldaia",
                    "componente": null,
                    "descrizione": "Test funzionale caldaia",
                    "qualita": "buona",
                    "daAllegare": true,
                    "confidenza": 0.9
                },
                {
                    "filename": "test_strumentale.jpg",
                    "tipo": "test_strumentale",
                    "tagSuggerito": "test_strumentale",
                    "beneRiferimento": "caldaia",
                    "componente": null,
                    "descrizione": "Test strumentale caldaia",
                    "qualita": "buona",
                    "daAllegare": true,
                    "confidenza": 0.9
                },
                {
                    "filename": "componente.jpg",
                    "tipo": "foto_componente",
                    "tagSuggerito": "foto_componente",
                    "beneRiferimento": "caldaia",
                    "componente": "scheda elettronica",
                    "descrizione": "Scheda elettronica caldaia",
                    "qualita": "buona",
                    "daAllegare": true,
                    "confidenza": 0.9
                }
            ]
        }
        
        ⚠️ RISPOSTA: Solo JSON con chiave "results" contenente array. Ogni oggetto DEVE avere "filename".
        ⚠️ IMPORTANTE: Per foto_componente, foto_test_funzionale, test_strumentale e foto_ripristino, il campo "beneRiferimento" è OBBLIGATORIO (non può essere null).
        """
    }
    
    private func parseBatchAnalysisResult(_ aiResult: AIResult, for urls: [URL], existingResults: [PhotoAnalysisResult]) -> [PhotoAnalysisResult] {
        guard let resultText = aiResult.result?.value as? String else { return [] }
        
        // Pulisci la risposta da eventuali markdown
        var cleanedText = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        } else if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if let endRange = cleanedText.range(of: "```", options: .backwards) {
            cleanedText = String(cleanedText[..<endRange.lowerBound])
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedText.data(using: .utf8) else {
            print("[AutoTagging] ⚠️ Impossibile convertire risposta in Data")
            return []
        }
        
        struct RawBatchResult: Codable {
            let filename: String
            let tipo: String
            let tagSuggerito: String?
            let beneRiferimento: String?
            let componente: String?
            let descrizione: String
            let qualita: String
            let daAllegare: Bool
            let confidenza: Double?
        }
        
        struct BatchResponse: Codable {
            let results: [RawBatchResult]
        }
        
        do {
            // Debug: stampa primi caratteri della risposta
            let preview = String(cleanedText.prefix(500))
            print("[AutoTagging] 🔍 Preview risposta JSON (primi 500 char): \(preview)")
            
            // Prima prova a decodificare come oggetto con "results"
            let decoder = JSONDecoder()
            let rawResults: [RawBatchResult]
            
            if let batchResponse = try? decoder.decode(BatchResponse.self, from: data) {
                rawResults = batchResponse.results
                print("[AutoTagging] ✅ JSON batch decodificato: \(rawResults.count) risultati")
            } else {
                // Prova a vedere se è un dizionario con altre chiavi
                if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[AutoTagging] 🔍 JSON è un dizionario con chiavi: \(jsonDict.keys.joined(separator: ", "))")
                    
                    // Cerca chiavi comuni che potrebbero contenere l'array
                    if let resultsArray = jsonDict["results"] as? [[String: Any]] {
                        print("[AutoTagging] ✅ Trovato array in chiave 'results'")
                        rawResults = try decoder.decode([RawBatchResult].self, from: JSONSerialization.data(withJSONObject: resultsArray))
                    } else if let resultsArray = jsonDict["data"] as? [[String: Any]] {
                        print("[AutoTagging] ✅ Trovato array in chiave 'data'")
                        rawResults = try decoder.decode([RawBatchResult].self, from: JSONSerialization.data(withJSONObject: resultsArray))
                    } else if let analisiDoc = jsonDict["analisi_documento"] as? [String: Any],
                              let immagini = analisiDoc["immagini"] as? [[String: Any]] {
                        // Fallback per formato alternativo "analisi_documento" -> "immagini"
                        print("[AutoTagging] ⚠️ Formato alternativo rilevato (analisi_documento/immagini), tentativo conversione...")
                        // Prova a convertire il formato alternativo
                        var convertedResults: [[String: Any]] = []
                        for (index, immagine) in immagini.enumerated() {
                            guard index < urls.count else { break }
                            let filename = urls[index].lastPathComponent
                            var converted: [String: Any] = [
                                "filename": filename,
                                "tipo": "foto_bene",
                                "tagSuggerito": "foto_bene",
                                "beneRiferimento": nil as String?,
                                "componente": nil as String?,
                                "descrizione": immagine["descrizione"] as? String ?? "Foto non classificata",
                                "qualita": "media",
                                "daAllegare": true,
                                "confidenza": 0.5
                            ]
                            convertedResults.append(converted)
                        }
                        if !convertedResults.isEmpty {
                            rawResults = try decoder.decode([RawBatchResult].self, from: JSONSerialization.data(withJSONObject: convertedResults))
                            print("[AutoTagging] ⚠️ Convertiti \(rawResults.count) risultati dal formato alternativo (dati limitati)")
                        } else {
                            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Formato alternativo non convertibile"))
                        }
                    } else if let firstArrayValue = jsonDict.values.first(where: { $0 is [[String: Any]] }) as? [[String: Any]] {
                        print("[AutoTagging] ✅ Trovato array come primo valore del dizionario")
                        rawResults = try decoder.decode([RawBatchResult].self, from: JSONSerialization.data(withJSONObject: firstArrayValue))
                    } else {
                        // Fallback: prova a decodificare direttamente come array
                        rawResults = try decoder.decode([RawBatchResult].self, from: data)
                        print("[AutoTagging] ✅ JSON array decodificato direttamente: \(rawResults.count) risultati")
                    }
                } else {
                    // Fallback: prova a decodificare direttamente come array
                    rawResults = try decoder.decode([RawBatchResult].self, from: data)
                    print("[AutoTagging] ✅ JSON array decodificato direttamente: \(rawResults.count) risultati")
                }
            }
            
            var results: [PhotoAnalysisResult] = []
            
            for raw in rawResults {
                // Trova l'URL corrispondente al filename
                guard let url = urls.first(where: { $0.lastPathComponent == raw.filename }) else {
                    print("[AutoTagging] ⚠️ File non trovato: \(raw.filename)")
                    continue
                }
                
                let photoType = PhotoType(rawValue: raw.tipo) ?? .altro
                let quality = PhotoQuality(rawValue: raw.qualita) ?? .media
                
                // Verifica similarità
                var similarTo: String? = nil
                if let bene = raw.beneRiferimento {
                    for existing in (existingResults + results) {
                        if existing.beneRiferimento == bene && existing.tipo == photoType && existing.daAllegare {
                            similarTo = existing.path
                            break
                        }
                    }
                }
                
                let shouldAttach = similarTo == nil && raw.daAllegare && quality != .irrilevante && quality != .scarsa
                
                results.append(PhotoAnalysisResult(
                    path: url.path,
                    tipo: photoType,
                    tagSuggerito: raw.tagSuggerito ?? photoType.tagId,
                    beneRiferimento: raw.beneRiferimento,
                    componente: raw.componente,
                    descrizione: raw.descrizione,
                    qualita: quality,
                    daAllegare: shouldAttach,
                    similarTo: similarTo,
                    confidenza: raw.confidenza ?? 0.5
                ))
            }
            
            print("[AutoTagging] ✅ Batch parsing: \(results.count)/\(urls.count) foto elaborate")
            return results
        } catch {
            print("[AutoTagging] ⚠️ Errore parsing batch JSON: \(error)")
            print("[AutoTagging] 📄 JSON completo ricevuto: \(cleanedText)")
            
            // Prova a estrarre manualmente l'array se possibile
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                print("[AutoTagging] 🔍 Tipo oggetto JSON: \(type(of: jsonObject))")
                if let dict = jsonObject as? [String: Any] {
                    print("[AutoTagging] 🔍 Chiavi nel dizionario: \(dict.keys.joined(separator: ", "))")
                    for (key, value) in dict {
                        print("[AutoTagging] 🔍 Chiave '\(key)': tipo \(type(of: value))")
                    }
                }
            }
            
            return []
        }
    }
    
    /// Estrae un JSON array dalla risposta
    private func extractJSONArrayFromResponse(_ text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Rimuovi markdown code blocks
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if let endRange = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<endRange.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Se inizia con [, è già un array JSON
        if cleaned.hasPrefix("[") {
            return cleaned
        }
        
        // Cerca l'array nel testo
        guard let arrayStart = cleaned.firstIndex(of: "[") else { return nil }
        
        // Trova la parentesi quadra di chiusura
        var depth = 0
        var inString = false
        var escaped = false
        var arrayEnd: String.Index?
        
        for i in cleaned.indices[arrayStart...] {
            let char = cleaned[i]
            
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            
            if char == "[" {
                depth += 1
            } else if char == "]" {
                depth -= 1
                if depth == 0 {
                    arrayEnd = cleaned.index(after: i)
                    break
                }
            }
        }
        
        guard let end = arrayEnd else {
            if let lastBracket = cleaned.lastIndex(of: "]") {
                return String(cleaned[arrayStart...lastBracket])
            }
            return nil
        }
        
        return String(cleaned[arrayStart..<end])
    }
    
    // MARK: - Analisi Singola (Locale o Fallback)
    
    private func analyzeSinglePhoto(_ url: URL, sinistro: Sinistro, existingResults: [PhotoAnalysisResult], context: DocumentiContext? = nil) async -> PhotoAnalysisResult? {
        let prompt = buildAnalysisPrompt(for: url, sinistro: sinistro, context: context)
        
        // System prompt specifico per il tagging (non analisi approfondita)
        let systemPrompt = "Sei un sistema di classificazione automatica per foto di perizie assicurative. Il tuo UNICO compito è CLASSIFICARE le foto assegnando tag, tipo, bene e componente. NON estrarre dettagli tecnici, NON fare analisi approfondite, NON descrivere in dettaglio. Rispondi SEMPRE in formato JSON con la struttura richiesta."
        
        // Crea task con modello multimodale locale come preferito, cloud come fallback
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "systemPrompt": AnyCodable(systemPrompt),
                "images": AnyCodable([url.path]),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        // Esegui con AIManager
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            if aiResult.usedFallback {
                                print("[AutoTagging] ⚠️ Usato fallback \(aiResult.provider.displayName) per \(url.lastPathComponent)")
                            }
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi foto")))
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parseAnalysisResult(aiResult, for: url, existingResults: existingResults)
        case .failure(let error):
            print("[AutoTagging] ❌ Errore analisi \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    private func buildAnalysisPrompt(for url: URL, sinistro: Sinistro, context: DocumentiContext? = nil) -> String {
        // Solo tag foto e giustificativi (fattura, preventivo), NO atti
        let tagList = FileTagManager.FileTag.availableTags
            .filter { $0.category == .foto || ["fattura", "preventivo"].contains($0.id) }
            .map { "\($0.id): \($0.name)" }
            .joined(separator: ", ")
        
        // Costruisci sezione contesto beni (opzionale, non vincolante)
        var contextSection = ""
        if let ctx = context, !ctx.beniAttesi.isEmpty {
            let beniList = ctx.beniAttesi.map { bene in
                var line = "• \(bene.nome)"
                if !bene.componenti.isEmpty {
                    line += " (componenti: \(bene.componenti.joined(separator: ", ")))"
                }
                return line
            }.joined(separator: "\n")
            
            contextSection = """
            
            CONTESTO DAI DOCUMENTI (beni POSSIBILI, non vincolanti):
            I seguenti beni sono stati menzionati nei documenti. Usali come SUGGERIMENTO, ma identifica correttamente anche beni NON in lista:
            \(beniList)
            
            """
        }
        
        return """
        COMPITO: Classifica questa foto per un sistema di tagging automatico. NON fare analisi approfondite, solo classificazione.
        
        FOTO: \(url.lastPathComponent)
        \(contextSection)
        
        ⛔ COSA NON FARE:
        - NON estrarre dettagli tecnici (marca, modello, specifiche)
        - NON fare analisi approfondite del contenuto
        - NON descrivere in dettaglio cosa vedi
        
        ✅ COSA FARE:
        - Identifica il TIPO di foto (bene, componente, ubicazione, documento, test)
        - Identifica il BENE (solo nome generico, es. "caldaia" non "Ignis AFE 941")
        - Identifica il COMPONENTE se presente (solo nome, es. "scheda elettronica")
        - Valuta la QUALITÀ visiva
        - Decidi se ALLEGARE (true se rappresentativa, false se duplicata/dettaglio)
        
        REGOLE IMPORTANTI:
        1. BENE = impianto completo (caldaia, cancello, fotovoltaico) - SOLO NOME, NO MARCA/MODELLO
        2. COMPONENTE = parte del bene (scheda, motore, varistore) - SOLO NOME, NO MARCA/MODELLO
        3. BENE RIFERIMENTO OBBLIGATORIO per:
           - foto_componente: DEVI sempre indicare il bene a cui appartiene il componente
           - foto_test_funzionale: DEVI sempre indicare il bene su cui è stato fatto il test
           - test_strumentale: DEVI sempre indicare il bene su cui è stato fatto il test
           - foto_ripristino: DEVI sempre indicare il bene che è stato riparato
        4. UBICAZIONE: identifica il tipo corretto:
           - "foto_ubicazione_rischio": ubicazione del rischio assicurato (esterno, stabile, indirizzo)
           - "foto_ubicazione_tecnico": ubicazione tecnica del bene/impianto (locale tecnico, box, garage)
           - "foto_ubicazione_amministratore": ubicazione amministratore (sede amministrativa, uffici)
           - "foto_ubicazione_altra": altra ubicazione non classificabile nelle precedenti
        5. DOCUMENTI: identifica se fattura, preventivo, atto
        6. QUALITÀ: "buona" (nitida), "media" (accettabile), "scarsa" (sfocata), "irrilevante"
        
        TAG DISPONIBILI: \(tagList)
        
        FORMATO RISPOSTA (JSON OBBLIGATORIO):
        {
            "tipo": "foto_bene|foto_componente|foto_ubicazione_rischio|foto_ubicazione_tecnico|foto_ubicazione_amministratore|foto_ubicazione_altra|foto_test_funzionale|test_strumentale|foto_ripristino|...",
            "tagSuggerito": "id_tag o null",
            "beneRiferimento": "nome bene o null (OBBLIGATORIO per foto_componente, foto_test_funzionale, test_strumentale, foto_ripristino)",
            "componente": "nome componente o null",
            "descrizione": "descrizione breve",
            "qualita": "buona|media|scarsa|irrilevante",
            "daAllegare": true/false,
            "confidenza": 0.0-1.0
        }
        
        ⚠️ RISPOSTA: Solo JSON, senza testo aggiuntivo.
        ⚠️ IMPORTANTE: Per foto_componente, foto_test_funzionale, test_strumentale e foto_ripristino, il campo "beneRiferimento" è OBBLIGATORIO (non può essere null).
        """
    }
    
    /// Estrae il JSON dalla risposta dell'IA, che potrebbe essere avvolta in testo libero
    private func extractJSONFromResponse(_ text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Rimuovi markdown code blocks se presenti
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if let endRange = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<endRange.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Se inizia con {, è già JSON
        if cleaned.hasPrefix("{") {
            return cleaned
        }
        
        // 3. Cerca il JSON all'interno del testo (trova la prima { e l'ultima } corrispondente)
        guard let jsonStart = cleaned.firstIndex(of: "{") else {
            return nil
        }
        
        // Trova la parentesi graffa di chiusura corrispondente
        var depth = 0
        var jsonEnd: String.Index?
        var inString = false
        var escaped = false
        
        for i in cleaned.indices[jsonStart...] {
            let char = cleaned[i]
            
            if escaped {
                escaped = false
                continue
            }
            
            if char == "\\" {
                escaped = true
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                continue
            }
            
            if inString {
                continue
            }
            
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    jsonEnd = cleaned.index(after: i)
                    break
                }
            }
        }
        
        guard let end = jsonEnd else {
            // Fallback: prendi fino all'ultima }
            if let lastBrace = cleaned.lastIndex(of: "}") {
                return String(cleaned[jsonStart...lastBrace])
            }
            return nil
        }
        
        return String(cleaned[jsonStart..<end])
    }
    
    private func parseAnalysisResult(_ aiResult: AIResult, for url: URL, existingResults: [PhotoAnalysisResult]) -> PhotoAnalysisResult? {
        guard let resultText = aiResult.result?.value as? String else { return nil }
        
        // Estrai JSON dalla risposta (potrebbe essere avvolto in testo libero)
        guard let jsonString = extractJSONFromResponse(resultText) else {
            print("[AutoTagging] ⚠️ JSON non trovato nella risposta per \(url.lastPathComponent)")
            print("[AutoTagging] 📝 Risposta ricevuta (primi 200 char): \(String(resultText.prefix(200)))")
            return nil
        }
        
        // Prova a decodificare JSON
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        struct RawResult: Codable {
            let tipo: String
            let tagSuggerito: String?
            let beneRiferimento: String?
            let componente: String?
            let descrizione: String
            let qualita: String
            let daAllegare: Bool
            let confidenza: Double?
        }
        
        do {
            let raw = try JSONDecoder().decode(RawResult.self, from: data)
            
            let photoType = PhotoType(rawValue: raw.tipo) ?? .altro
            let quality = PhotoQuality(rawValue: raw.qualita) ?? .media
            
            // Verifica similarità con foto esistenti (stesso bene + stesso tipo)
            var similarTo: String? = nil
            if let bene = raw.beneRiferimento {
                for existing in existingResults {
                    if existing.beneRiferimento == bene && existing.tipo == photoType && existing.daAllegare {
                        similarTo = existing.path
                        break
                    }
                }
            }
            
            // Se è simile a un'altra foto già allegata, non allegare questa
            let shouldAttach = similarTo == nil && raw.daAllegare && quality != .irrilevante && quality != .scarsa
            
            return PhotoAnalysisResult(
                path: url.path,
                tipo: photoType,
                tagSuggerito: raw.tagSuggerito ?? photoType.tagId,
                beneRiferimento: raw.beneRiferimento,
                componente: raw.componente,
                descrizione: raw.descrizione,
                qualita: quality,
                daAllegare: shouldAttach,
                similarTo: similarTo,
                confidenza: raw.confidenza ?? 0.5
            )
        } catch {
            print("[AutoTagging] ⚠️ Errore parsing JSON per \(url.lastPathComponent): \(error)")
            return nil
        }
    }
    
    // MARK: - Limiti per tipo di foto
    
    /// Limiti massimi di foto da allegare per categoria
    private struct AttachmentLimits {
        static let ubicazioneRischio = 2      // Max 2 foto ubicazione rischio
        static let ubicazioneAltro = 2        // Max 2 per altre ubicazioni
        static let benePerBene = 3            // Max 3 foto per ogni bene (idealmente 2)
        static let componentePerBene = 3      // Max 3 foto componente per bene
        static let ripristino = 3             // Max 3 foto ripristino per bene
        static let testFunzionale = 2         // Max 2 foto test funzionale per bene
        static let testStrumentale = 2        // Max 2 foto test strumentale
        static let altro = 2                  // Max 2 foto generiche
    }
    
    // MARK: - Applicazione Tag
    
    @MainActor
    private func applyTagsWithDeduplication(results: [PhotoAnalysisResult]) async -> Int {
        print("[AutoTagging] 🏷️ Inizio applicazione tag per \(results.count) risultati analisi")
        var taggedCount = 0
        
        // Ordina tutti i risultati per qualità e confidenza (migliori prima)
        let sortedResults = results.sorted { photo1, photo2 in
            // Prima per qualità (buona > media > scarsa > irrilevante)
            let qualityOrder: [PhotoQuality: Int] = [.buona: 3, .media: 2, .scarsa: 1, .irrilevante: 0]
            let q1 = qualityOrder[photo1.qualita] ?? 0
            let q2 = qualityOrder[photo2.qualita] ?? 0
            
            if q1 != q2 {
                return q1 > q2
            }
            // Poi per confidenza
            return photo1.confidenza > photo2.confidenza
        }
        
        // Contatori per ogni categoria
        var ubicazioneRischioCount = 0
        var ubicazioneTecnicoCount = 0
        var ubicazioneAltraCount = 0
        
        // Contatori per bene -> tipo -> count
        var beneTypeCount: [String: [PhotoType: Int]] = [:]
        
        // Contatori per componente specifico (bene + componente)
        var componenteCount: [String: Int] = [:]  // "bene|componente" -> count
        
        // Prima passa: raggruppa e conta
        print("[AutoTagging] 📊 Analisi distribuzione foto...")
        
        var photosByCategory: [String: [PhotoAnalysisResult]] = [:]
        
        for photo in sortedResults {
            let categoryKey: String
            
            switch photo.tipo {
            case .ubicazioneRischio:
                categoryKey = "ubicazione_rischio"
            case .ubicazioneTecnico:
                categoryKey = "ubicazione_tecnico"
            case .ubicazioneAmministratore:
                categoryKey = "ubicazione_amministratore"
            case .ubicazioneAltra:
                categoryKey = "ubicazione_altra"
            case .bene:
                let bene = photo.beneRiferimento ?? "sconosciuto"
                categoryKey = "bene|\(bene)"
            case .componente:
                let bene = photo.beneRiferimento ?? "sconosciuto"
                let comp = photo.componente ?? "sconosciuto"
                categoryKey = "componente|\(bene)|\(comp)"
            case .ripristino:
                let bene = photo.beneRiferimento ?? "sconosciuto"
                categoryKey = "ripristino|\(bene)"
            case .testFunzionale:
                let bene = photo.beneRiferimento ?? "sconosciuto"
                categoryKey = "test_funzionale|\(bene)"
            case .testStrumentale:
                let bene = photo.beneRiferimento ?? "generale"
                categoryKey = "test_strumentale|\(bene)"
            default:
                categoryKey = "altro"
            }
            
            if photosByCategory[categoryKey] == nil {
                photosByCategory[categoryKey] = []
            }
            photosByCategory[categoryKey]?.append(photo)
        }
        
        // Log distribuzione
        for (category, photos) in photosByCategory.sorted(by: { $0.key < $1.key }) {
            print("[AutoTagging]   • \(category): \(photos.count) foto")
        }
        
        // Seconda passa: applica tag con limiti
        print("[AutoTagging] 🏷️ Applicazione tag con limiti...")
        
        for (category, photos) in photosByCategory {
            if isCancelled {
                print("[AutoTagging] ⏹️ Elaborazione interrotta durante applicazione tag")
                break
            }
            // Determina il limite per questa categoria
            let limit: Int
            
            if category == "ubicazione_rischio" {
                limit = AttachmentLimits.ubicazioneRischio
            } else if category == "ubicazione_tecnico" {
                limit = AttachmentLimits.ubicazioneAltro
            } else if category == "ubicazione_amministratore" {
                limit = AttachmentLimits.ubicazioneAltro
            } else if category == "ubicazione_altra" {
                limit = AttachmentLimits.ubicazioneAltro
            } else if category.hasPrefix("bene|") {
                limit = AttachmentLimits.benePerBene
            } else if category.hasPrefix("componente|") {
                limit = AttachmentLimits.componentePerBene
            } else if category.hasPrefix("ripristino|") {
                limit = AttachmentLimits.ripristino
            } else if category.hasPrefix("test_funzionale|") {
                limit = AttachmentLimits.testFunzionale
            } else if category.hasPrefix("test_strumentale|") {
                limit = AttachmentLimits.testStrumentale
            } else {
                limit = AttachmentLimits.altro
            }
            
            // Le foto sono già ordinate per qualità/confidenza
            var attachedCount = 0
            
            for photo in photos {
                // Allega solo se non abbiamo raggiunto il limite e la foto merita di essere allegata
                let shouldAttach: Bool
                if photo.qualita == .irrilevante || photo.qualita == .scarsa {
                    // Non allegare foto di scarsa qualità
                    shouldAttach = false
                } else if attachedCount < limit && photo.daAllegare {
                    shouldAttach = true
                    attachedCount += 1
                } else {
                    // Tagga ma non allegare
                    shouldAttach = false
                }
                
                if applyTag(for: photo, daAllegare: shouldAttach) {
                    taggedCount += 1
                }
            }
            
            print("[AutoTagging]   ✓ \(category): \(attachedCount)/\(photos.count) allegate (limite: \(limit))")
        }
        
        print("[AutoTagging] ✅ Applicazione tag completata: \(taggedCount)/\(results.count) foto taggate")
        return taggedCount
    }
    
    private func applyTag(for result: PhotoAnalysisResult, daAllegare: Bool) -> Bool {
        let filename = URL(fileURLWithPath: result.path).lastPathComponent
        
        guard let tagId = result.tagSuggerito else {
            print("[AutoTagging] ⚠️ Nessun tag suggerito per \(filename)")
            return false
        }
        
        guard FileTagManager.FileTag.availableTags.first(where: { $0.id == tagId }) != nil else {
            print("[AutoTagging] ⚠️ Tag '\(tagId)' non trovato nei tag disponibili per \(filename)")
            return false
        }
        
        // Verifica se l'utente ha rimosso manualmente questo tag
        if fileTagManager.wasTagManuallyRemoved(tagId: tagId, fromFile: result.path) {
            print("[AutoTagging] ⏭️ Tag '\(tagId)' rimosso manualmente, skip \(filename)")
            return false
        }
        
        // Estrai il sinistroPath dal path del file
        let sinistroPath = extractSinistroPath(from: result.path)
        
        // Usa il nuovo sistema applyTag con TagApplicationData
        var tagData = FileTagManager.TagApplicationData(tagId: tagId)
        tagData.daAllegareInChiusura = daAllegare
        
        // Gestisci bene e componente in base al tipo di tag
        if tagId == "foto_bene" {
            // Per foto_bene: il bene va in additionalText
            tagData.additionalText = result.beneRiferimento
        } else if tagId == "foto_componente" {
            // Per foto_componente: il componente va in additionalText, il bene in beneRiferimento
            tagData.additionalText = result.componente
            tagData.beneRiferimento = result.beneRiferimento
        } else if FileTagManager.FileTag.beneRiferimentoTags.contains(tagId) {
            // Per tag che supportano beneRiferimento (test funzionale, strumentale, ripristino)
            tagData.additionalText = result.componente
            tagData.beneRiferimento = result.beneRiferimento
        } else {
            // Per altri tag
            tagData.additionalText = result.componente
        }
        
        // Applica il tag usando il nuovo sistema centralizzato (async)
        Task { @MainActor in
            await fileTagManager.applyTag(tagData, toFile: result.path, sinistroPath: sinistroPath)
            
            // Salva la descrizione generata dall'AI (se presente)
            if !result.descrizione.isEmpty {
                // Usa una chiave speciale "descrizione_ai" per salvare la descrizione indipendentemente dal tag
                fileTagManager.setAdditionalText(result.descrizione, forFile: result.path, tagId: "descrizione_ai")
                print("[AutoTagging] 📝 Descrizione salvata: '\(result.descrizione.prefix(50))...' per \(filename)")
            }
        }
        
        print("[AutoTagging] ✅ Tag '\(tagId)' → \(filename) (allegare: \(daAllegare))")
        return true
    }
    
    /// Estrae il path del sinistro da un path file
    private func extractSinistroPath(from filePath: String) -> String? {
        // Cerca nella gerarchia delle cartelle per trovare una cartella che corrisponde a un sinistro
        let pathComponents = (filePath as NSString).pathComponents
        
        for i in stride(from: pathComponents.count - 1, through: 0, by: -1) {
            let partialPath = pathComponents[0...i].joined(separator: "/")
            // Verifica se è una cartella sinistro valida
            if fileService.getSinistroPath(riferimento: (partialPath as NSString).lastPathComponent, create: false) == partialPath {
                return partialPath
            }
        }
        
        return nil
    }
    
    // MARK: - Reset
    
    /// Resetta lo stato dell'autotagging per un sinistro (permette di rieseguirlo)
    func resetAutoTagging(for sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento else { return }
        UserDefaults.standard.removeObject(forKey: "autoTagging_completed_\(riferimento)")
        
        // Rimuovi dalla cache i path di questo sinistro
        if let path = fileService.getSinistroPath(riferimento: riferimento) {
            analyzedPaths = analyzedPaths.filter { !$0.hasPrefix(path) }
        }
    }
}
