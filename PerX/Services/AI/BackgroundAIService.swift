import Foundation
import CoreData

/// Servizio per analisi automatica dei documenti dei sinistri in background
class BackgroundAIService {
    static let shared = BackgroundAIService()
    
    private let aiManager = AIManager.shared
    private let fileManager = FileManager.default
    private var processedFiles: Set<String> = []
    
    private init() {
        loadProcessedFiles()
    }
    
    // MARK: - Public API
    
    /// Analizza automaticamente tutti i documenti di un sinistro
    func analyzeSinistroDocuments(_ sinistro: Sinistro, context: NSManagedObjectContext) {
        guard let cartella = sinistro.cartella,
              let riferimento = sinistro.riferimento else {
            return
        }
        
        let sinistroPath = cartella
        guard fileManager.fileExists(atPath: sinistroPath) else {
            return
        }
        
        Task {
            await scanAndAnalyzeDocuments(in: sinistroPath, sinistroID: riferimento, context: context)
        }
    }
    
    /// Analizza un singolo file
    func analyzeFile(at path: String, sinistroID: String? = nil) {
        let normalizedPath = (path as NSString).standardizingPath
        
        // Evita di processare lo stesso file due volte
        if processedFiles.contains(normalizedPath) {
            return
        }
        
        // Determina il tipo di file
        let fileExtension = (path as NSString).pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "bmp", "heic", "heif"].contains(fileExtension)
        let isDocument = ["pdf", "doc", "docx", "txt"].contains(fileExtension)
        
        guard isImage || isDocument else {
            return
        }
        
        // Crea task di analisi
        let taskType: AITaskType = isImage ? .imageAnalysis : .documentAnalysis
        let task = AITask(
            type: taskType,
            priority: .secondary,
            preferredProvider: .localMultimodal,
            parameters: [
                "filePath": AnyCodable(normalizedPath),
                "sinistroID": AnyCodable(sinistroID ?? "")
            ]
        )
        
        Task { @MainActor in
            aiManager.enqueue(task) { result in
                if result.success {
                    self.markFileAsProcessed(normalizedPath)
                    self.saveAnalysisResult(filePath: normalizedPath, result: result, sinistroID: sinistroID)
                }
            }
        }
    }
    
    /// Scansiona e analizza tutti i documenti in una cartella
    func scanAndAnalyzeDocuments(in folderPath: String, sinistroID: String, context: NSManagedObjectContext) async {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: folderPath),
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }
        
        var filesToAnalyze: [URL] = []
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let path = fileURL.path
            let normalizedPath = (path as NSString).standardizingPath
            
            // Salta se già processato
            if processedFiles.contains(normalizedPath) {
                continue
            }
            
            // Verifica tipo file supportato
            let fileExtension = fileURL.pathExtension.lowercased()
            let isImage = ["jpg", "jpeg", "png", "gif", "bmp", "heic", "heif"].contains(fileExtension)
            let isDocument = ["pdf", "doc", "docx", "txt"].contains(fileExtension)
            
            if isImage || isDocument {
                filesToAnalyze.append(fileURL)
            }
        }
        
        // Analizza i file trovati
        for fileURL in filesToAnalyze {
            let path = fileURL.path
            analyzeFile(at: path, sinistroID: sinistroID)
            
            // Piccola pausa per non sovraccaricare
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 secondi
        }
    }
    
    /// Verifica se un file è già stato analizzato
    func isFileProcessed(_ filePath: String) -> Bool {
        let normalizedPath = (filePath as NSString).standardizingPath
        return processedFiles.contains(normalizedPath)
    }
    
    // MARK: - Private Implementation
    
    private func markFileAsProcessed(_ filePath: String) {
        processedFiles.insert(filePath)
        saveProcessedFiles()
    }
    
    private func saveAnalysisResult(filePath: String, result: AIResult, sinistroID: String?) {
        // Salva il risultato in CoreData o in un file cache
        // Per ora salva in UserDefaults come cache semplice
        let key = "ai_analysis_\(filePath.hashValue)"
        
        if let resultData = result.result?.value as? String {
            UserDefaults.standard.set(resultData, forKey: key)
        }
    }
    
    private func loadProcessedFiles() {
        if let files = UserDefaults.standard.array(forKey: "ai_processed_files") as? [String] {
            processedFiles = Set(files)
        }
    }
    
    private func saveProcessedFiles() {
        UserDefaults.standard.set(Array(processedFiles), forKey: "ai_processed_files")
    }
    
    /// Ottiene il risultato di analisi per un file
    func getAnalysisResult(for filePath: String) -> String? {
        let key = "ai_analysis_\(filePath.hashValue)"
        return UserDefaults.standard.string(forKey: key)
    }
}

