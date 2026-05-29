import Foundation
import SwiftUI

@MainActor
class AttoTemplateManager: ObservableObject {
    static let shared = AttoTemplateManager()
    
    @Published var templates: [AttoTemplate] = []
    @Published var isLoading = false
    
    private let fileManager = FileManager.default
    private let templatesFileName = "templates.json"
    
    private init() {
        loadTemplates()
    }
    
    // MARK: - Paths
    
    private var bundleTemplatesURL: URL? {
        Bundle.main.url(forResource: "templates", withExtension: "json", subdirectory: "Atti")
    }
    
    private var localTemplatesURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let attiDir = appSupport.appendingPathComponent("PerX/Atti", isDirectory: true)
        if !fileManager.fileExists(atPath: attiDir.path) {
            try? fileManager.createDirectory(at: attiDir, withIntermediateDirectories: true)
        }
        return attiDir.appendingPathComponent(templatesFileName)
    }
    
    // MARK: - JSON Coding
    
    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    // MARK: - Load/Save
    
    func loadTemplates() {
        isLoading = true
        defer { isLoading = false }
        
        var loadedTemplates: [AttoTemplate] = []
        
        // Carica da locale
        if let localURL = localTemplatesURL {
            print("[AttoTemplateManager] Path locale: \(localURL.path)")
            
            if fileManager.fileExists(atPath: localURL.path) {
                print("[AttoTemplateManager] File locale esiste")
                
                do {
                    let data = try Data(contentsOf: localURL)
                    print("[AttoTemplateManager] Letti \(data.count) bytes")
                    
                    let storage = try jsonDecoder.decode(AttoTemplatesStorage.self, from: data)
                    loadedTemplates = storage.templates
                    print("[AttoTemplateManager] Caricati \(loadedTemplates.count) template da locale")
                } catch {
                    print("[AttoTemplateManager] Errore lettura locale: \(error)")
                }
            } else {
                print("[AttoTemplateManager] File locale NON esiste")
            }
        } else {
            print("[AttoTemplateManager] localTemplatesURL è nil!")
        }
        
        // Fallback: carica da bundle se locale è vuoto
        if loadedTemplates.isEmpty {
            if let bundleURL = bundleTemplatesURL {
                do {
                    let data = try Data(contentsOf: bundleURL)
                    let storage = try jsonDecoder.decode(AttoTemplatesStorage.self, from: data)
                    loadedTemplates = storage.templates
                    print("[AttoTemplateManager] Caricati \(loadedTemplates.count) template da bundle")
                } catch {
                    print("[AttoTemplateManager] Errore lettura bundle: \(error)")
                }
            }
        }
        
        templates = loadedTemplates
        print("[AttoTemplateManager] Templates finali: \(templates.count)")
    }
    
    func saveTemplates() {
        saveToLocal()
    }
    
    private func saveToLocal() {
        guard let url = localTemplatesURL else {
            print("[AttoTemplateManager] saveToLocal: localTemplatesURL è nil!")
            return
        }
        
        let storage = AttoTemplatesStorage(templates: templates, lastUpdated: Date())
        
        do {
            let data = try jsonEncoder.encode(storage)
            try data.write(to: url, options: .atomic)
            print("[AttoTemplateManager] Salvati \(templates.count) template in locale: \(url.path)")
            
            // Verifica che il file sia stato scritto
            if fileManager.fileExists(atPath: url.path) {
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let size = attrs?[.size] as? Int ?? 0
                print("[AttoTemplateManager] File scritto: \(size) bytes")
            }
        } catch {
            print("[AttoTemplateManager] Errore salvataggio locale: \(error)")
        }
    }
    
    // MARK: - Sync
    
    func syncWithiCloud() async {
        loadTemplates()
    }
    
    private func mergeTemplates(local: [AttoTemplate], cloud: [AttoTemplate]) async {
        var merged: [String: AttoTemplate] = [:]
        
        // Aggiungi template locali
        for template in local {
            merged[template.id] = template
        }
        
        // Aggiungi/aggiorna con template cloud (più recenti vincono)
        for template in cloud {
            if let existing = merged[template.id] {
                if template.updatedAt > existing.updatedAt {
                    merged[template.id] = template
                }
            } else {
                merged[template.id] = template
            }
        }
        
        let mergedTemplates = Array(merged.values).sorted { $0.nome < $1.nome }
        
        await MainActor.run {
            if mergedTemplates != templates {
                templates = mergedTemplates
                print("[AttoTemplateManager] Merged \(templates.count) template")
            }
        }
        
        saveToLocal()
    }
    
    // MARK: - Template CRUD
    
    func addTemplate(_ template: AttoTemplate) {
        templates.append(template)
        saveTemplates()
    }
    
    func updateTemplate(_ template: AttoTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            templates[index] = updated
            saveTemplates()
        }
    }
    
    func deleteTemplate(id: String) {
        templates.removeAll { $0.id == id }
        saveTemplates()
    }
    
    func createNewVersion(of template: AttoTemplate) -> AttoTemplate {
        var newTemplate = template
        newTemplate.version += 1
        newTemplate.updatedAt = Date()
        
        // Disattiva versione precedente
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].isActive = false
        }
        
        // Nuovo ID per nuova versione
        let newId = UUID().uuidString
        newTemplate = AttoTemplate(
            id: newId,
            nome: template.nome,
            compagnia: template.compagnia,
            tipo: template.tipo,
            version: template.version + 1,
            pdfFileName: template.pdfFileName,
            pages: template.pages,
            createdAt: template.createdAt,
            updatedAt: Date(),
            isActive: true
        )
        
        templates.append(newTemplate)
        saveTemplates()
        return newTemplate
    }
    
    // MARK: - Query
    
    func getTemplate(forCompagnia compagnia: String, tipo: AttoTipo) -> AttoTemplate? {
        templates
            .filter { $0.compagnia.lowercased() == compagnia.lowercased() && $0.tipo == tipo && $0.isActive }
            .sorted { $0.version > $1.version }
            .first
    }
    
    func getTemplates(forCompagnia compagnia: String) -> [AttoTemplate] {
        templates.filter { $0.compagnia.lowercased() == compagnia.lowercased() && $0.isActive }
    }
    
    func getAllVersions(of template: AttoTemplate) -> [AttoTemplate] {
        templates
            .filter { $0.compagnia == template.compagnia && $0.tipo == template.tipo && $0.pdfFileName == template.pdfFileName }
            .sorted { $0.version > $1.version }
    }
    
    // MARK: - PDF Files
    
    private var cloudService: AttoTemplateCloudService {
        AttoTemplateCloudService.shared
    }
    
    func getPDFURL(for template: AttoTemplate) -> URL? {
        // Prima cerca nel servizio PDF locale.
        if let cloudURL = cloudService.getPDFURL(forFileName: template.pdfFileName) {
            return cloudURL
        }
        
        // Fallback: cerca in bundle
        if let bundleURL = Bundle.main.url(forResource: template.pdfFileName.replacingOccurrences(of: ".pdf", with: ""),
                                            withExtension: "pdf",
                                            subdirectory: "Atti") {
            return bundleURL
        }
        
        // Cerca in Resources/Atti del progetto
        let projectPath = "/Users/mpernozzoli/Documents/Attività Peritali/App/PerX BKP16 - fulminazioni Recupero/PerX/Resources/Atti"
        let pdfPath = (projectPath as NSString).appendingPathComponent(template.pdfFileName)
        if fileManager.fileExists(atPath: pdfPath) {
            return URL(fileURLWithPath: pdfPath)
        }
        
        return nil
    }
    
    func getAvailablePDFs() -> [String] {
        // Usa il cloud service per ottenere tutti i PDF disponibili
        return cloudService.availablePDFs.map { $0.fileName }.sorted()
    }
    
    func getAvailablePDFInfos() -> [AttoTemplateCloudService.AttoPDFInfo] {
        return cloudService.availablePDFs
    }
}
