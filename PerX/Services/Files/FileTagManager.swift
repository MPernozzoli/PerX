import Foundation
import SwiftUI
import CoreData
import CryptoKit

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[try transform(key)] = value
        }
        return result
    }
}

/// Entry nella storia dei tag per un file
struct TagHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operation: TagOperation
    let tagId: String
    let additionalText: String?
    let daAllegare: Bool?
    let attoSottotipo: String?
    let fulminazioneSottotipo: String?
    let giustificativiTipo: String?
    let elaboratoExcelUltimo: Bool?
    let beneRiferimento: String?
    
    enum TagOperation: String, Codable {
        case add
        case remove
        case modify
    }
    
    init(
        operation: TagOperation,
        tagId: String,
        additionalText: String? = nil,
        daAllegare: Bool? = nil,
        attoSottotipo: String? = nil,
        fulminazioneSottotipo: String? = nil,
        giustificativiTipo: String? = nil,
        elaboratoExcelUltimo: Bool? = nil,
        beneRiferimento: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.operation = operation
        self.tagId = tagId
        self.additionalText = additionalText
        self.daAllegare = daAllegare
        self.attoSottotipo = attoSottotipo
        self.fulminazioneSottotipo = fulminazioneSottotipo
        self.giustificativiTipo = giustificativiTipo
        self.elaboratoExcelUltimo = elaboratoExcelUltimo
        self.beneRiferimento = beneRiferimento
    }
}

@MainActor
class FileTagManager: ObservableObject {
    static let shared = FileTagManager()
    
    @Published var fileTags: [String: Set<FileTag>] = [:] // path: Set<FileTag>
    @Published var fileTagMetadata: [String: [String: String]] = [:] // path: [tagId: additionalText]
    @Published var fileTagDaAllegare: [String: [String: Bool]] = [:] // path: [tagId: daAllegareInChiusura]
    @Published var pdfPageTags: [String: [Int: Set<FileTag>]] = [:] // path: [pageIndex: Set<FileTag>]
    @Published var pdfPageTagMetadata: [String: [Int: [String: String]]] = [:] // path: [pageIndex: [tagId: additionalText]]
    @Published var pdfPageDaAllegare: [String: [Int: [String: Bool]]] = [:] // path: [pageIndex: [tagId: daAllegare]]
    
    // Storage per sottotipi e bene riferimento
    @Published var fileTagAttoSottotipo: [String: [String: String]] = [:] // path: [tagId: "accertamento"/"liquidazione"]
    @Published var fileTagAttoStato: [String: [String: String]] = [:] // path: [tagId: "firmato"/"da_firmare"] - per UI unificata
    @Published var fileTagFulminazioneSottotipo: [String: [String: String]] = [:] // path: [tagId: "positiva"/"negativa"]
    @Published var fileTagGiustificativiTipo: [String: [String: String]] = [:] // path: [tagId: "fattura"/"preventivo"] - per UI unificata
    @Published var fileTagAllegatiAttoSottotipo: [String: [String: String]] = [:] // path: [tagId: "accettazione"/"iban"/"delega"/"documenti"]
    @Published var fileTagElaboratoExcelUltimo: [String: [String: Bool]] = [:] // path: [tagId: true/false]
    @Published var fileTagBeneRiferimento: [String: [String: String]] = [:] // path: [tagId: nomeBene]
    
    // Tag rimossi manualmente dall'utente (non devono essere ri-applicati automaticamente)
    @Published var manuallyRemovedTags: [String: Set<String>] = [:] // path: Set<tagId>
    
    // Storia dei tag per ogni file (cronologia completa)
    private var fileTagHistory: [String: [TagHistoryEntry]] = [:] // path: [TagHistoryEntry]
    
    // MARK: - Batch Mode (per operazioni massive)
    
    /// Quando true, le operazioni di modifica non salvano immediatamente su disco
    private var batchMode: Bool = false
    
    /// Inizia una operazione batch - le modifiche vengono accumulate in memoria
    func beginBatchUpdate() {
        batchMode = true
    }
    
    /// Termina l'operazione batch e salva tutte le modifiche su disco
    func commitBatchUpdate() {
        batchMode = false
        saveTags()
        objectWillChange.send()
    }
    
    /// Annulla l'operazione batch senza salvare (ricarica da disco)
    func cancelBatchUpdate() {
        batchMode = false
        loadTags()
        objectWillChange.send()
    }
    
    /// Salva solo se non siamo in batch mode
    private func saveIfNotBatching() {
        guard !batchMode else { return }
        saveTags()
        objectWillChange.send()
    }
    
    private let tagsKey = "FileTagManager.tags"
    private let metadataKey = "FileTagManager.metadata"
    private let daAllegareKey = "FileTagManager.daAllegare"
    private let pdfPageTagsKey = "FileTagManager.pdfPageTags"
    private let pdfPageTagMetadataKey = "FileTagManager.pdfPageTagMetadata"
    private let pdfPageDaAllegareKey = "FileTagManager.pdfPageDaAllegare"
    private let attoSottotipoKey = "FileTagManager.attoSottotipo"
    private let attoStatoKey = "FileTagManager.attoStato"
    private let fulminazioneSottotipoKey = "FileTagManager.fulminazioneSottotipo"
    private let giustificativiTipoKey = "FileTagManager.giustificativiTipo"
    private let allegatiAttoSottotipoKey = "FileTagManager.allegatiAttoSottotipo"
    private let elaboratoExcelUltimoKey = "FileTagManager.elaboratoExcelUltimo"
    private let beneRiferimentoKey = "FileTagManager.beneRiferimento"
    private let manuallyRemovedTagsKey = "FileTagManager.manuallyRemovedTags"
    private let tagHistoryKey = "FileTagManager.tagHistory"
    
    // Cache interna (non deve mai essere trattata come contenuto utente)
    private static let perxCacheFolderName = "perx-cache"
    private func isInPerxCache(_ path: String) -> Bool {
        let p = path.lowercased()
        return p.contains("/\(Self.perxCacheFolderName)/") || p.hasSuffix("/\(Self.perxCacheFolderName)")
    }
    
    private let fileService = FileService.shared
    private let versioningService = FileVersioningService.shared
    
    private init() {
        loadTags()
        
        // Ritarda l'aggiornamento e la migrazione per evitare problemi di inizializzazione 
        // singletons circolari o eccessivo carico al boot
        Task { @MainActor in
            updateElaboratoExcelUltimo()
            await migrateExistingTagsToVersioning()
        }
    }
    
    /// Migra i tag esistenti da UserDefaults alla cartella versioning
    private func migrateExistingTagsToVersioning() async {
        // Crea una copia delle chiavi per evitare modifiche concorrenti durante l'iterazione
        let pathsToMigrate = await MainActor.run { Array(fileTags.keys) }
        
        for path in pathsToMigrate {
            guard !isInPerxCache(path) else { continue }
            
            // Se il file esiste ancora, salva i tag nella cartella versioning
            if FileManager.default.fileExists(atPath: path) {
                await MainActor.run {
                    saveTagsToVersioning(for: path)
                }
            }
        }
    }
    
    // MARK: - Elaborato Excel Ultimo
    
    /// Aggiorna automaticamente il flag "ultimo" per elaborato_excel
    func updateElaboratoExcelUltimo() {
        // Raggruppa per sinistro (trova la cartella sinistro)
        var sinistriFiles: [String: [(path: String, date: Date)]] = [:]
        
        // Usa la proprietà della classe invece di FileService.shared locale per evitare shadowing e potenziali crash al boot
        for (path, tags) in fileTags {
            guard !isInPerxCache(path) else { continue }
            if tags.contains(where: { $0.id == "elaborato_excel" }) {
                // Estrai riferimento dal nome file (Elaborato_Peritale_RIFERIMENTO.xlsm)
                let fileName = (path as NSString).lastPathComponent
                var riferimento: String? = nil
                
                if fileName.lowercased().hasPrefix("elaborato_peritale_") {
                    let prefix = "elaborato_peritale_"
                    let withoutPrefix = String(fileName.dropFirst(prefix.count))
                    if let dotIndex = withoutPrefix.firstIndex(of: ".") {
                        riferimento = String(withoutPrefix.prefix(upTo: dotIndex))
                    }
                }
                
                // Trova la cartella sinistro usando FileService
                let sinistroPath: String
                if let ref = riferimento, let foundPath = fileService.getSinistroPath(riferimento: ref, create: false) {
                    sinistroPath = foundPath
                } else {
                    // Fallback: usa la cartella padre del file (assumendo che sia nella root del sinistro)
                    sinistroPath = (path as NSString).deletingLastPathComponent
                }
                
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                if sinistriFiles[sinistroPath] == nil {
                    sinistriFiles[sinistroPath] = []
                }
                sinistriFiles[sinistroPath]?.append((path: path, date: modDate))
            }
        }
        
        var needsSave = false
        
        // Per ogni sinistro, trova il file più recente
        for (_, files) in sinistriFiles {
            if files.count > 1 {
                // Ordina per data di modifica (più recente prima)
                let sorted = files.sorted { $0.date > $1.date }
                let mostRecent = sorted[0]
                
                // Imposta ultimo=true per il più recente, false per gli altri
                for file in files {
                    let shouldBeUltimo = file.path == mostRecent.path
                    let current = fileTagElaboratoExcelUltimo[file.path]?["elaborato_excel"] ?? false
                    
                    if current != shouldBeUltimo {
                        if fileTagElaboratoExcelUltimo[file.path] == nil {
                            fileTagElaboratoExcelUltimo[file.path] = [:]
                        }
                        fileTagElaboratoExcelUltimo[file.path]?["elaborato_excel"] = shouldBeUltimo
                        needsSave = true
                    }
                }
            } else if files.count == 1 {
                // Un solo file, non serve flag ultimo
                let path = files[0].path
                if fileTagElaboratoExcelUltimo[path]?["elaborato_excel"] == true {
                    fileTagElaboratoExcelUltimo[path]?["elaborato_excel"] = false
                    needsSave = true
                }
            }
        }
        
        if needsSave {
            saveTags()
        }
    }
    
    func getElaboratoExcelUltimo(forFile path: String, tagId: String) -> Bool? {
        return fileTagElaboratoExcelUltimo[path]?[tagId]
    }
    
    func setElaboratoExcelUltimo(_ isUltimo: Bool, forFile path: String, tagId: String) {
        if fileTagElaboratoExcelUltimo[path] == nil {
            fileTagElaboratoExcelUltimo[path] = [:]
        }
        fileTagElaboratoExcelUltimo[path]?[tagId] = isUltimo
        saveTags()
        objectWillChange.send()
    }
    
    struct FileTag: Identifiable, Hashable {
        let id: String
        let name: String
        let tagColor: Color
        let requiresAdditionalText: Bool
        let category: TagCategory?
        
        enum TagCategory: String, CaseIterable {
            case foto = "Foto"
        }
        
        static let availableTags: [FileTag] = [
            // Documenti principali - ordine logico di utilizzo
            FileTag(id: "atto_da_firmare", name: "Atto da Firmare", tagColor: .pink, requiresAdditionalText: false, category: nil),
            FileTag(id: "atto_firmato", name: "Atto Firmato", tagColor: .mint, requiresAdditionalText: false, category: nil),
            FileTag(id: "allegati_atto", name: "Allegati Atto", tagColor: .mint.opacity(0.7), requiresAdditionalText: false, category: nil),
            FileTag(id: "fattura", name: "Fattura", tagColor: .blue, requiresAdditionalText: false, category: nil),
            FileTag(id: "preventivo", name: "Preventivo", tagColor: .blue, requiresAdditionalText: false, category: nil),
            FileTag(id: "fulminazione", name: "Fulminazione", tagColor: .yellow, requiresAdditionalText: false, category: nil),
            FileTag(id: "perizia", name: "Perizia", tagColor: .green, requiresAdditionalText: false, category: nil),
            FileTag(id: "verbale", name: "Verbale", tagColor: .orange, requiresAdditionalText: false, category: nil),
            
            // Tag per file generati nella cartella "Da Chiudere"
            FileTag(id: "file_foto", name: "File Foto", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_atto", name: "File Atto", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_giustificativi", name: "File Giustificativi", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_perizia", name: "File Perizia", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_verbale", name: "File Verbale", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_fulminazione", name: "File Fulminazione", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "file_altro", name: "Altro file di chiusura", tagColor: .gray, requiresAdditionalText: false, category: nil),
            FileTag(id: "dichiarazione", name: "Dichiarazione", tagColor: .purple, requiresAdditionalText: false, category: nil),
            FileTag(id: "denuncia", name: "Denuncia", tagColor: .red, requiresAdditionalText: false, category: nil),
            
            // Documenti secondari/informativi
            FileTag(id: "elaborato_excel", name: "Elaborato Excel", tagColor: .green, requiresAdditionalText: false, category: nil),
            FileTag(id: "report_cat", name: "Report CAT", tagColor: .indigo, requiresAdditionalText: false, category: nil),
            FileTag(id: "simplo_di_polizza", name: "Simplo di Polizza", tagColor: .blue, requiresAdditionalText: false, category: nil),
            FileTag(id: "cga", name: "CGA", tagColor: .indigo, requiresAdditionalText: false, category: nil),
            FileTag(id: "incarico", name: "Incarico", tagColor: .brown, requiresAdditionalText: false, category: nil),
            
            // Categoria Foto - ordine logico
            // Tag ubicazione individuali (usati internamente, l'UI mostra il tag unificato)
            FileTag(id: "foto_ubicazione_rischio", name: "Ubicazione del rischio", tagColor: .red, requiresAdditionalText: false, category: .foto),
            FileTag(id: "foto_ubicazione_tecnico", name: "Ubicazione tecnico riparatore", tagColor: .red, requiresAdditionalText: false, category: .foto),
            FileTag(id: "foto_ubicazione_amministratore", name: "Ubicazione amministratore", tagColor: .red, requiresAdditionalText: false, category: .foto),
            FileTag(id: "foto_ubicazione_altra", name: "Altra ubicazione", tagColor: .red, requiresAdditionalText: true, category: .foto),
            FileTag(id: "foto_bene", name: "Bene", tagColor: .red, requiresAdditionalText: true, category: .foto),
            FileTag(id: "foto_componente", name: "Componente", tagColor: .red, requiresAdditionalText: true, category: .foto),
            FileTag(id: "foto_ripristino", name: "Ripristino", tagColor: .red, requiresAdditionalText: true, category: .foto),
            FileTag(id: "foto_test_funzionale", name: "Test funzionale", tagColor: .red, requiresAdditionalText: false, category: .foto),
            FileTag(id: "test_strumentale", name: "Test strumentale", tagColor: .red, requiresAdditionalText: false, category: .foto)
        ]
        
        /// Tag che supportano sottotipo atto (accertamento/liquidazione)
        static let attoTags = ["atto_da_firmare", "atto_firmato"]
        
        /// Tag che supportano sottotipo fulminazione (positiva/negativa)
        static let fulminazioneTags = ["fulminazione"]
        
        /// Tag che supportano tipo giustificativi (fattura/preventivo) - per UI unificata
        static let giustificativiTags = ["fattura", "preventivo"]
        
        /// Tag che supportano sottotipo allegati atto
        static let allegatiAttoTags = ["allegati_atto"]
        
        /// Tag ubicazione (del rischio, tecnico riparatore, amministratore, altra)
        static let ubicazioneTags = ["foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_amministratore", "foto_ubicazione_altra"]
        
        /// Tag che supportano selezione bene di riferimento
        static let beneRiferimentoTags = ["foto_componente", "foto_ripristino", "foto_test_funzionale", "test_strumentale"]
        
        /// Tag per file generati nella cartella "Da Chiudere"
        static let closureGeneratedTags = ["file_foto", "file_atto", "file_giustificativi", "file_perizia", "file_verbale", "file_fulminazione", "file_altro"]
        
        /// Tag unificati per UI (mostrati come un solo tag con selettori)
        static let unifiedTags: [String: [String]] = [
            "atto": ["atto_da_firmare", "atto_firmato"],
            "giustificativi": ["fattura", "preventivo"],
            "foto_ubicazione": ["foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_amministratore", "foto_ubicazione_altra"]
        ]
        
        /// Ottiene il nome visualizzato per un tag, considerando sottotipi/stato
        static func getDisplayName(for tagId: String, in fileTagManager: FileTagManager, forFile path: String) async -> String {
            switch tagId {
            case "atto_da_firmare", "atto_firmato":
                let sottotipo = await MainActor.run {
                    fileTagManager.getAttoSottotipo(forFile: path, tagId: tagId) ?? ""
                }
                
                var name = tagId == "atto_firmato" ? "Atto Firmato" : "Atto da Firmare"
                if !sottotipo.isEmpty {
                    name += " - \(sottotipo.capitalized)"
                }
                return name
                
            case "fattura", "preventivo":
                return tagId == "fattura" ? "Fattura" : "Preventivo"
                
            case "elaborato_excel":
                let isUltimo = await MainActor.run {
                    fileTagManager.getElaboratoExcelUltimo(forFile: path, tagId: tagId) ?? false
                }
                return isUltimo ? "Elaborato Excel - ultimo" : "Elaborato Excel"
                
            default:
                return availableTags.first(where: { $0.id == tagId })?.name ?? tagId
            }
        }
        
        static func tagsByCategory() -> [TagCategory?: [FileTag]] {
            var result: [TagCategory?: [FileTag]] = [:]
            for tag in availableTags {
                if result[tag.category] == nil {
                    result[tag.category] = []
                }
                result[tag.category]?.append(tag)
            }
            return result
        }
        
        /// Tag unificati per UI (nasconde tag individuali e mostra quelli unificati)
        /// Esclude anche i tag file_* di sistema tranne file_foto
        static func unifiedTagsForUI() -> [FileTag] {
            var unified: [FileTag] = []
            var seenAtto = false
            var seenGiustificativi = false
            var seenUbicazione = false
            
            for tag in availableTags {
                // Escludi tutti i tag file_* di sistema tranne file_foto
                if FileTag.closureGeneratedTags.contains(tag.id) && tag.id != "file_foto" {
                    continue
                }
                
                if tag.id == "atto_da_firmare" || tag.id == "atto_firmato" {
                    if !seenAtto {
                        unified.append(FileTag(id: "atto", name: "Atto", tagColor: .mint, requiresAdditionalText: false, category: nil))
                        seenAtto = true
                    }
                } else if tag.id == "fattura" || tag.id == "preventivo" {
                    if !seenGiustificativi {
                        unified.append(FileTag(id: "giustificativi", name: "Giustificativi", tagColor: .blue, requiresAdditionalText: false, category: nil))
                        seenGiustificativi = true
                    }
                } else if ubicazioneTags.contains(tag.id) {
                    if !seenUbicazione {
                        unified.append(FileTag(id: "foto_ubicazione", name: "Foto Ubicazione", tagColor: .red, requiresAdditionalText: false, category: .foto))
                        seenUbicazione = true
                    }
                } else {
                    unified.append(tag)
                }
            }
            return unified
        }
        
        static func unifiedTagsByCategory() -> [TagCategory?: [FileTag]] {
            var result: [TagCategory?: [FileTag]] = [:]
            for tag in unifiedTagsForUI() {
                if result[tag.category] == nil {
                    result[tag.category] = []
                }
                result[tag.category]?.append(tag)
            }
            return result
        }
        
        /// Tag foto che sono mutualmente esclusivi (solo uno può essere applicato a un file)
        static let photoTags: Set<String> = Set(availableTags.filter { $0.category == .foto }.map { $0.id })
    }
    
    // MARK: - Tag Application Data
    
    /// Struttura per raccogliere tutti i dati necessari per applicare un tag
    struct TagApplicationData {
        let tagId: String
        var additionalText: String?
        var daAllegareInChiusura: Bool?
        var attoSottotipo: String?
        var attoStato: String? // "firmato" o "da_firmare"
        var giustificativiTipo: String? // "fattura" o "preventivo"
        var fulminazioneSottotipo: String?
        var allegatiAttoSottotipo: String?
        var beneRiferimento: String?
        var ubicazioneTipo: String? // "rischio", "tecnico", "amministratore", "altra"
        var ubicazioneAltraDescrizione: String?
        
        init(tagId: String) {
            self.tagId = tagId
        }
    }
    
    // MARK: - Helper Methods
    
    /// Verifica se un file è un PDF
    func isPDFFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "pdf"
    }
    
    /// Ottiene il path del sinistro da un path file
    private func getSinistroPathFromFilePath(_ filePath: String) -> String? {
        return getSinistroPath(for: filePath)
    }
    
    // MARK: - Apply Tag (Unified Method)
    
    /// Applica un tag a un file con logica centralizzata
    /// - Gestisce la regola "un solo tag per file" (tranne PDF)
    /// - Gestisce l'ereditarietà dei dati tra tag (bene ↔ componente ↔ test)
    /// - Gestisce la riconciliazione dei nomi beni/componenti
    func applyTag(_ data: TagApplicationData, toFile path: String, sinistroPath: String? = nil) async {
        // 1. Ottieni tag esistenti e dati da ereditare
        let existingTags = getTagsForFile(at: path)
        
        // 2. Ereditarietà: salva dati rilevanti prima di rimuovere tag esistenti
        var inheritedBene: String? = nil
        var inheritedComponente: String? = nil
        
        for existingTag in existingTags {
            if existingTag.id == "foto_bene" {
                // Da bene a componente/test: trasferisci il nome del bene
                inheritedBene = getAdditionalText(forFile: path, tagId: "foto_bene")
            } else if existingTag.id == "foto_componente" {
                // Da componente a bene/test: trasferisci il bene di riferimento e il componente
                inheritedBene = getBeneRiferimento(forFile: path, tagId: "foto_componente")
                inheritedComponente = getAdditionalText(forFile: path, tagId: "foto_componente")
            } else if FileTag.beneRiferimentoTags.contains(existingTag.id) {
                // Da test funzionale/strumentale a bene/componente: trasferisci il bene testato
                inheritedBene = getBeneRiferimento(forFile: path, tagId: existingTag.id)
            }
        }
        
        // 3. REGOLA: Un solo tag per file (tranne PDF che possono avere più tag, uno per pagina)
        // I file non-PDF possono avere solo UN tag
        if !isPDFFile(path) && !existingTags.isEmpty {
            // Rimuovi tutti i tag esistenti prima di aggiungere il nuovo
            for existingTag in existingTags {
                removeTag(existingTag, fromFile: path, manualRemoval: false)
            }
        }
        
        // 4. Determina il tag effettivo da applicare (gestisce tag unificati)
        let effectiveTagId: String
        switch data.tagId {
        case "atto":
            effectiveTagId = data.attoStato == "firmato" ? "atto_firmato" : "atto_da_firmare"
        case "giustificativi":
            effectiveTagId = data.giustificativiTipo == "preventivo" ? "preventivo" : "fattura"
        case "foto_ubicazione":
            switch data.ubicazioneTipo {
            case "tecnico": effectiveTagId = "foto_ubicazione_tecnico"
            case "amministratore": effectiveTagId = "foto_ubicazione_amministratore"
            case "altra": effectiveTagId = "foto_ubicazione_altra"
            default: effectiveTagId = "foto_ubicazione_rischio"
            }
        default:
            effectiveTagId = data.tagId
        }
        
        // 5. Riconciliazione beni/componenti
        let effectiveSinistroPath = sinistroPath ?? getSinistroPathFromFilePath(path)
        let commonItemsManager = CommonItemsManager.shared
        
        var reconciledAdditionalText = data.additionalText
        var reconciledBeneRiferimento = data.beneRiferimento
        
        // Applica ereditarietà se non ci sono dati già specificati
        if effectiveTagId == "foto_bene" {
            // Se stiamo applicando foto_bene e non c'è additionalText, usa il bene ereditato
            if (reconciledAdditionalText == nil || reconciledAdditionalText?.isEmpty == true), let inherited = inheritedBene, !inherited.isEmpty {
                reconciledAdditionalText = inherited
            }
            // Riconcilia
            if let text = reconciledAdditionalText, !text.isEmpty {
                reconciledAdditionalText = await commonItemsManager.reconcileBene(text, sinistroPath: effectiveSinistroPath)
            }
        } else if effectiveTagId == "foto_componente" {
            // Se stiamo applicando foto_componente
            // additionalText = nome componente
            // beneRiferimento = bene a cui appartiene
            if (reconciledBeneRiferimento == nil || reconciledBeneRiferimento?.isEmpty == true), let inherited = inheritedBene, !inherited.isEmpty {
                reconciledBeneRiferimento = inherited
            }
            // Riconcilia bene
            if let bene = reconciledBeneRiferimento, !bene.isEmpty {
                reconciledBeneRiferimento = await commonItemsManager.reconcileBene(bene, sinistroPath: effectiveSinistroPath)
            }
            // Riconcilia componente
            if let comp = reconciledAdditionalText, !comp.isEmpty {
                reconciledAdditionalText = await commonItemsManager.reconcileComponente(comp, sinistroPath: effectiveSinistroPath)
            }
        } else if FileTag.beneRiferimentoTags.contains(effectiveTagId) {
            // Test funzionale, test strumentale, ripristino: hanno beneRiferimento
            if (reconciledBeneRiferimento == nil || reconciledBeneRiferimento?.isEmpty == true), let inherited = inheritedBene, !inherited.isEmpty {
                reconciledBeneRiferimento = inherited
            }
            // Riconcilia bene
            if let bene = reconciledBeneRiferimento, !bene.isEmpty {
                reconciledBeneRiferimento = await commonItemsManager.reconcileBene(bene, sinistroPath: effectiveSinistroPath)
            }
        }
        
        // 6. Trova e applica il tag
        guard let tag = FileTag.availableTags.first(where: { $0.id == effectiveTagId }) else {
            print("[FileTagManager] ⚠️ Tag non trovato: \(effectiveTagId)")
            return
        }
        
        // Applica il tag con i dati riconciliati
        addTag(tag, toFile: path, additionalText: reconciledAdditionalText, daAllegareInChiusura: data.daAllegareInChiusura)
        
        // 7. Imposta metadati aggiuntivi
        if let bene = reconciledBeneRiferimento, !bene.isEmpty {
            setBeneRiferimento(bene, forFile: path, tagId: effectiveTagId)
        }
        
        if let attoSottotipo = data.attoSottotipo, !attoSottotipo.isEmpty {
            setAttoSottotipo(attoSottotipo, forFile: path, tagId: effectiveTagId)
        }
        
        if let fulminazioneSottotipo = data.fulminazioneSottotipo, !fulminazioneSottotipo.isEmpty {
            setFulminazioneSottotipo(fulminazioneSottotipo, forFile: path, tagId: effectiveTagId)
        }
        
        if let allegatiAttoSottotipo = data.allegatiAttoSottotipo, !allegatiAttoSottotipo.isEmpty {
            setAllegatiAttoSottotipo(allegatiAttoSottotipo, forFile: path, tagId: effectiveTagId)
        }
        
        // Per ubicazione altra, salva la descrizione
        if effectiveTagId == "foto_ubicazione_altra", let desc = data.ubicazioneAltraDescrizione, !desc.isEmpty {
            setAdditionalText(desc, forFile: path, tagId: effectiveTagId)
        }
        
        // Aggiungi beni/componenti custom se non esistono già
        if let text = reconciledAdditionalText, !text.isEmpty {
            if effectiveTagId == "foto_bene" {
                commonItemsManager.addCustomBene(text)
            } else if effectiveTagId == "foto_componente" {
                commonItemsManager.addCustomComponente(text)
            }
        }
        if let bene = reconciledBeneRiferimento, !bene.isEmpty {
            commonItemsManager.addCustomBene(bene)
        }
    }
    
    /// Rimuove il tag corrente da un file (versione semplificata per toggle)
    func removeCurrentTag(fromFile path: String) {
        let existingTags = getTagsForFile(at: path)
        for tag in existingTags {
            removeTag(tag, fromFile: path, manualRemoval: true)
        }
    }
    
    func getTagsForFile(at path: String) -> Set<FileTag> {
        // Prova a caricare i tag persistenti se il file non ha ancora tag
        if fileTags[path] == nil || fileTags[path]?.isEmpty == true {
            _ = loadTagsFromVersioning(for: path)
        }
        return fileTags[path] ?? []
    }
    
    func getAdditionalText(forFile path: String, tagId: String) -> String? {
        fileTagMetadata[path]?[tagId]
    }
    
    func setAdditionalText(_ text: String?, forFile path: String, tagId: String) {
        // Salva lo stato precedente nella storia
        let previousText = fileTagMetadata[path]?[tagId]
        if previousText != text {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                additionalText: previousText
            )
        }
        
        if fileTagMetadata[path] == nil {
            fileTagMetadata[path] = [:]
        }
        if let text = text, !text.isEmpty {
            fileTagMetadata[path]?[tagId] = text
        } else {
            fileTagMetadata[path]?.removeValue(forKey: tagId)
        }
        
        // Aggiungi entry nella storia per il nuovo stato
        if previousText != text {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                additionalText: text
            )
        }
        
        saveIfNotBatching()
    }
    
    func getDaAllegareInChiusura(forFile path: String, tagId: String) -> Bool {
        return fileTagDaAllegare[path]?[tagId] ?? false
    }
    
    func setDaAllegareInChiusura(_ value: Bool, forFile path: String, tagId: String) {
        // Salva lo stato precedente nella storia
        let previousValue = fileTagDaAllegare[path]?[tagId] ?? false
        if previousValue != value {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                daAllegare: previousValue
            )
        }
        
        if fileTagDaAllegare[path] == nil {
            fileTagDaAllegare[path] = [:]
        }
        if value {
            fileTagDaAllegare[path]?[tagId] = true
        } else {
            fileTagDaAllegare[path]?.removeValue(forKey: tagId)
        }
        
        // Aggiungi entry nella storia per il nuovo stato
        if previousValue != value {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                daAllegare: value
            )
        }
        
        saveIfNotBatching()
    }
    
    /// Disattiva "da allegare in chiusura" per un tag su tutti i file
    private func deactivateDaAllegareForTagOnAllFiles(tagId: String) {
        for path in fileTagDaAllegare.keys {
            fileTagDaAllegare[path]?.removeValue(forKey: tagId)
            if fileTagDaAllegare[path]?.isEmpty == true {
                fileTagDaAllegare.removeValue(forKey: path)
            }
        }
    }
    
    // MARK: - Sottotipo Atto (Accertamento/Liquidazione)
    
    func getAttoSottotipo(forFile path: String, tagId: String) -> String? {
        return fileTagAttoSottotipo[path]?[tagId]
    }
    
    func setAttoSottotipo(_ sottotipo: String?, forFile path: String, tagId: String) {
        // Salva lo stato precedente nella storia
        let previousSottotipo = fileTagAttoSottotipo[path]?[tagId]
        if previousSottotipo != sottotipo {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                attoSottotipo: previousSottotipo
            )
        }
        
        if fileTagAttoSottotipo[path] == nil {
            fileTagAttoSottotipo[path] = [:]
        }
        if let sottotipo = sottotipo, !sottotipo.isEmpty {
            fileTagAttoSottotipo[path]?[tagId] = sottotipo
        } else {
            fileTagAttoSottotipo[path]?.removeValue(forKey: tagId)
        }
        
        // Aggiungi entry nella storia per il nuovo stato
        if previousSottotipo != sottotipo {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                attoSottotipo: sottotipo
            )
        }
        
        saveTags()
        objectWillChange.send()
    }
    
    // MARK: - Stato Atto (Firmato/Da Firmare)
    
    /// Ottiene lo stato atto per un file (per UI unificata - senza tagId)
    func getAttoStato(forFile path: String) -> String? {
        let tags = getTagsForFile(at: path)
        if tags.contains(where: { $0.id == "atto_firmato" }) {
            return "firmato"
        } else if tags.contains(where: { $0.id == "atto_da_firmare" }) {
            return "da_firmare"
        }
        return nil
    }
    
    /// Ottiene lo stato atto per un file con tagId specifico (per tag individuali)
    func getAttoStato(forFile path: String, tagId: String) -> String? {
        // Per atto_firmato e atto_da_firmare, lo stato è implicito nel tagId
        if tagId == "atto_firmato" {
            return "firmato"
        } else if tagId == "atto_da_firmare" {
            return "da_firmare"
        }
        return nil
    }
    
    /// Imposta lo stato atto convertendo in tag appropriato (per UI unificata - senza tagId)
    func setAttoStato(_ stato: String?, forFile path: String) {
        let tags = getTagsForFile(at: path)
        
        // Rimuovi tag atto esistenti
        if let attoFirmato = tags.first(where: { $0.id == "atto_firmato" }) {
            removeTag(attoFirmato, fromFile: path, manualRemoval: false)
        }
        if let attoDaFirmare = tags.first(where: { $0.id == "atto_da_firmare" }) {
            removeTag(attoDaFirmare, fromFile: path, manualRemoval: false)
        }
        
        // Aggiungi il tag appropriato
        if let stato = stato, !stato.isEmpty {
            if stato == "firmato" {
                if let tag = FileTag.availableTags.first(where: { $0.id == "atto_firmato" }) {
                    addTag(tag, toFile: path)
                }
            } else if stato == "da_firmare" {
                if let tag = FileTag.availableTags.first(where: { $0.id == "atto_da_firmare" }) {
                    addTag(tag, toFile: path)
                }
            }
        }
    }
    
    // MARK: - Tipo Giustificativi (Fattura/Preventivo)
    
    /// Ottiene il tipo giustificativi per un file (per UI unificata - senza tagId)
    func getGiustificativiTipo(forFile path: String) -> String? {
        let tags = getTagsForFile(at: path)
        if tags.contains(where: { $0.id == "fattura" }) {
            return "fattura"
        } else if tags.contains(where: { $0.id == "preventivo" }) {
            return "preventivo"
        }
        return nil
    }
    
    /// Ottiene il tipo giustificativi per un file con tagId specifico (per tag individuali)
    func getGiustificativiTipo(forFile path: String, tagId: String) -> String? {
        // Per fattura e preventivo, il tipo è implicito nel tagId
        if tagId == "fattura" {
            return "fattura"
        } else if tagId == "preventivo" {
            return "preventivo"
        }
        return nil
    }
    
    /// Imposta il tipo giustificativi convertendo in tag appropriato (per UI unificata - senza tagId)
    func setGiustificativiTipo(_ tipo: String?, forFile path: String) {
        let tags = getTagsForFile(at: path)
        
        // Rimuovi tag giustificativi esistenti
        if let fattura = tags.first(where: { $0.id == "fattura" }) {
            removeTag(fattura, fromFile: path, manualRemoval: false)
        }
        if let preventivo = tags.first(where: { $0.id == "preventivo" }) {
            removeTag(preventivo, fromFile: path, manualRemoval: false)
        }
        
        // Aggiungi il tag appropriato
        if let tipo = tipo, !tipo.isEmpty {
            if tipo == "fattura" {
                if let tag = FileTag.availableTags.first(where: { $0.id == "fattura" }) {
                    addTag(tag, toFile: path)
                }
            } else if tipo == "preventivo" {
                if let tag = FileTag.availableTags.first(where: { $0.id == "preventivo" }) {
                    addTag(tag, toFile: path)
                }
            }
        }
    }
    
    // MARK: - Sottotipo Allegati Atto (Accettazione/IBAN/Delega/Documenti)
    
    func getAllegatiAttoSottotipo(forFile path: String, tagId: String) -> String? {
        return fileTagAllegatiAttoSottotipo[path]?[tagId]
    }
    
    func setAllegatiAttoSottotipo(_ sottotipo: String?, forFile path: String, tagId: String) {
        if fileTagAllegatiAttoSottotipo[path] == nil {
            fileTagAllegatiAttoSottotipo[path] = [:]
        }
        if let sottotipo = sottotipo, !sottotipo.isEmpty {
            fileTagAllegatiAttoSottotipo[path]?[tagId] = sottotipo
        } else {
            fileTagAllegatiAttoSottotipo[path]?.removeValue(forKey: tagId)
        }
        saveTags()
        objectWillChange.send()
    }
    
    // MARK: - Sottotipo Fulminazione (Positiva/Negativa)
    
    func getFulminazioneSottotipo(forFile path: String, tagId: String) -> String? {
        return fileTagFulminazioneSottotipo[path]?[tagId]
    }
    
    func setFulminazioneSottotipo(_ sottotipo: String?, forFile path: String, tagId: String) {
        // Salva lo stato precedente nella storia
        let previousSottotipo = fileTagFulminazioneSottotipo[path]?[tagId]
        if previousSottotipo != sottotipo {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                fulminazioneSottotipo: previousSottotipo
            )
        }
        
        if fileTagFulminazioneSottotipo[path] == nil {
            fileTagFulminazioneSottotipo[path] = [:]
        }
        if let sottotipo = sottotipo, !sottotipo.isEmpty {
            fileTagFulminazioneSottotipo[path]?[tagId] = sottotipo
        } else {
            fileTagFulminazioneSottotipo[path]?.removeValue(forKey: tagId)
        }
        
        // Aggiungi entry nella storia per il nuovo stato
        if previousSottotipo != sottotipo {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                fulminazioneSottotipo: sottotipo
            )
        }
        
        saveTags()
        objectWillChange.send()
    }
    
    // MARK: - Bene di Riferimento (per componenti, test funzionali, test strumentali)
    
    func getBeneRiferimento(forFile path: String, tagId: String) -> String? {
        return fileTagBeneRiferimento[path]?[tagId]
    }
    
    func setBeneRiferimento(_ bene: String?, forFile path: String, tagId: String) {
        // Salva lo stato precedente nella storia
        let previousBene = fileTagBeneRiferimento[path]?[tagId]
        if previousBene != bene {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                beneRiferimento: previousBene
            )
        }
        
        if fileTagBeneRiferimento[path] == nil {
            fileTagBeneRiferimento[path] = [:]
        }
        if let bene = bene, !bene.isEmpty {
            fileTagBeneRiferimento[path]?[tagId] = bene
        } else {
            fileTagBeneRiferimento[path]?.removeValue(forKey: tagId)
        }
        
        // Aggiungi entry nella storia per il nuovo stato
        if previousBene != bene {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tagId,
                beneRiferimento: bene
            )
        }
        
        saveIfNotBatching()
    }
    
    func addTag(_ tag: FileTag, toFile path: String, additionalText: String? = nil, daAllegareInChiusura: Bool? = nil) {
        // Prova a caricare i tag persistenti se il file non ha ancora tag
        if fileTags[path] == nil || fileTags[path]?.isEmpty == true {
            _ = loadTagsFromVersioning(for: path)
        }
        
        // Se il file ha già un tag file_* (file generato), non permettere l'aggiunta di tag ordinari
        let existingTags = fileTags[path] ?? []
        let hasGeneratedTag = existingTags.contains { FileTag.closureGeneratedTags.contains($0.id) }
        
        // Se il file ha un tag file_* e stiamo cercando di aggiungere un tag ordinario, blocca
        if hasGeneratedTag && !FileTag.closureGeneratedTags.contains(tag.id) {
            print("[FileTagManager] ⚠️ Impossibile aggiungere tag ordinario '\(tag.id)' a file generato (ha già tag file_*)")
            return
        }
        
        // Salva lo stato precedente nella storia se il tag esiste già (modifica)
        let wasExisting = existingTags.contains(tag)
        let previousAdditionalText = fileTagMetadata[path]?[tag.id]
        let previousDaAllegare = fileTagDaAllegare[path]?[tag.id]
        let previousAttoSottotipo = fileTagAttoSottotipo[path]?[tag.id]
        let previousFulminazioneSottotipo = fileTagFulminazioneSottotipo[path]?[tag.id]
        let previousGiustificativiTipo = fileTagGiustificativiTipo[path]?[tag.id]
        let previousElaboratoExcelUltimo = fileTagElaboratoExcelUltimo[path]?[tag.id]
        let previousBeneRiferimento = fileTagBeneRiferimento[path]?[tag.id]
        
        if wasExisting {
            addTagHistoryEntry(
                for: path,
                operation: .modify,
                tagId: tag.id,
                additionalText: previousAdditionalText,
                daAllegare: previousDaAllegare,
                attoSottotipo: previousAttoSottotipo,
                fulminazioneSottotipo: previousFulminazioneSottotipo,
                giustificativiTipo: previousGiustificativiTipo,
                elaboratoExcelUltimo: previousElaboratoExcelUltimo,
                beneRiferimento: previousBeneRiferimento
            )
        }
        
        var currentTags = fileTags[path] ?? []
        currentTags.insert(tag)
        fileTags[path] = currentTags
        
        // Se l'utente ri-aggiunge un tag, rimuovilo dalla lista dei rimossi manualmente
        manuallyRemovedTags[path]?.remove(tag.id)
        if manuallyRemovedTags[path]?.isEmpty == true {
            manuallyRemovedTags.removeValue(forKey: path)
        }
        
        if let additionalText = additionalText, !additionalText.isEmpty {
            if fileTagMetadata[path] == nil {
                fileTagMetadata[path] = [:]
            }
            fileTagMetadata[path]?[tag.id] = additionalText
        }
        
        // Per i documenti (non foto), imposta "da allegare in chiusura" automaticamente a true
        // L'utente può poi disattivarlo manualmente se vuole escludere il file
        // NOTA: I tag file_* non devono avere "da allegare" attivo perché sono già nella cartella "Da Chiudere"
        let shouldAutoAllegare: Bool
        if FileTag.closureGeneratedTags.contains(tag.id) {
            // I tag file_* non devono mai avere "da allegare" attivo
            shouldAutoAllegare = false
        } else {
            shouldAutoAllegare = daAllegareInChiusura ?? shouldAutoIncludeInClosure(tag: tag)
        }
        
        if shouldAutoAllegare {
            if fileTagDaAllegare[path] == nil {
                fileTagDaAllegare[path] = [:]
            }
            fileTagDaAllegare[path]?[tag.id] = true
        }
        
        // Se è elaborato_excel, aggiorna i flag ultimo
        if tag.id == "elaborato_excel" {
            updateElaboratoExcelUltimo()
        }
        
        // Aggiungi entry nella storia per l'operazione add/modify
        addTagHistoryEntry(
            for: path,
            operation: wasExisting ? .modify : .add,
            tagId: tag.id,
            additionalText: additionalText ?? fileTagMetadata[path]?[tag.id],
            daAllegare: shouldAutoAllegare ? true : fileTagDaAllegare[path]?[tag.id],
            attoSottotipo: fileTagAttoSottotipo[path]?[tag.id],
            fulminazioneSottotipo: fileTagFulminazioneSottotipo[path]?[tag.id],
            giustificativiTipo: fileTagGiustificativiTipo[path]?[tag.id],
            elaboratoExcelUltimo: fileTagElaboratoExcelUltimo[path]?[tag.id],
            beneRiferimento: fileTagBeneRiferimento[path]?[tag.id]
        )
        
        saveTags()
        objectWillChange.send()
        
        // Crea versione "parlante" per cambio tag
        createVersionForTagChange(filePath: path, operation: wasExisting ? "Modifica tag" : "Aggiungi tag", tagName: tag.name)
        
        // Notifica se è stato aggiunto il tag "atto_da_firmare" (per aggiornare lo stato sinistro)
        if tag.id == "atto_da_firmare" {
            NotificationCenter.default.post(
                name: .attoDaFirmareTagged,
                object: nil,
                userInfo: ["filePath": path]
            )
        }
    }
    
    /// Aggiunge un'entry nella storia dei tag
    private func addTagHistoryEntry(
        for path: String,
        operation: TagHistoryEntry.TagOperation,
        tagId: String,
        additionalText: String? = nil,
        daAllegare: Bool? = nil,
        attoSottotipo: String? = nil,
        fulminazioneSottotipo: String? = nil,
        giustificativiTipo: String? = nil,
        elaboratoExcelUltimo: Bool? = nil,
        beneRiferimento: String? = nil
    ) {
        if fileTagHistory[path] == nil {
            fileTagHistory[path] = []
        }
        
        let entry = TagHistoryEntry(
            operation: operation,
            tagId: tagId,
            additionalText: additionalText,
            daAllegare: daAllegare,
            attoSottotipo: attoSottotipo,
            fulminazioneSottotipo: fulminazioneSottotipo,
            giustificativiTipo: giustificativiTipo,
            elaboratoExcelUltimo: elaboratoExcelUltimo,
            beneRiferimento: beneRiferimento
        )
        
        fileTagHistory[path]?.append(entry)
        
        // Mantieni solo le ultime 100 entry per file (per evitare crescita eccessiva)
        if let history = fileTagHistory[path], history.count > 100 {
            fileTagHistory[path] = Array(history.suffix(100))
        }
    }
    
    /// Determina se un tag dovrebbe avere "da allegare in chiusura" attivo di default
    private func shouldAutoIncludeInClosure(tag: FileTag) -> Bool {
        // Tag che vengono normalmente allegati in chiusura
        // Fulminazione: la logica compagnia è gestita in ClosureFilesService
        // Foto: tutte incluse di default
        // NON auto-allegare: denuncia, polizza, incarico, elaborato_excel, simplo, cga, report_cat
        let autoIncludeTags: Set<String> = [
            // Documenti principali da allegare
            "atto_da_firmare", "atto_firmato",
            "allegati_atto",
            "fattura", "preventivo",
            "fulminazione",
            "verbale",
            "perizia",
            "dichiarazione",
            // Foto - tutte le tipologie
            "foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_amministratore", "foto_ubicazione_altra",
            "foto_bene", "foto_componente", "foto_ripristino",
            "foto_test_funzionale", "test_strumentale"
        ]
        return autoIncludeTags.contains(tag.id)
    }
    
    /// Imposta "da allegare in chiusura" per fulminazione basandosi sulla compagnia
    /// Unipol: sempre allegata, Altre compagnie: solo se positiva
    func setFulminazioneDaAllegare(forFile path: String, compagnia: Compagnia, sottotipo: String?) {
        let shouldAllegare: Bool
        
        if compagnia == .unipolItalia {
            // Unipol: allega sempre la fulminazione
            shouldAllegare = true
        } else {
            // Altre compagnie: allega solo se positiva
            shouldAllegare = sottotipo?.lowercased() == "positiva"
        }
        
        setDaAllegareInChiusura(shouldAllegare, forFile: path, tagId: "fulminazione")
    }
    
    /// Aggiorna la proprietà concordata del sinistro se viene aggiunto tag atto_firmato
    /// atto_firmato = concordata firmata
    func updateSinistroConcordataIfNeeded(forFile path: String, sinistro: Sinistro) {
        let tags = getTagsForFile(at: path)
        let hasAttoFirmato = tags.contains { $0.id == "atto_firmato" }
        
        // Concordata se: atto firmato
        if hasAttoFirmato && !sinistro.concordata {
            sinistro.concordata = true
            try? sinistro.managedObjectContext?.save()
        }
    }
    
    /// Aggiorna il campo fulminazione del sinistro quando viene taggato un file di fulminazione
    /// Se il sottotipo è "positiva", imposta "Fulminazione Positiva", se "negativa" imposta "Fulminazione Negativa"
    func updateSinistroFulminazioneIfNeeded(forFile path: String, sinistro: Sinistro) {
        let tags = getTagsForFile(at: path)
        let hasFulminazione = tags.contains { $0.id == "fulminazione" }
        
        guard hasFulminazione else { return }
        
        // Ottieni il sottotipo fulminazione
        let sottotipo = getFulminazioneSottotipo(forFile: path, tagId: "fulminazione")
        
        // Determina il valore da impostare
        let nuovoValore: String?
        if let sottotipo = sottotipo?.lowercased() {
            if sottotipo == "positiva" {
                nuovoValore = "Positiva"
            } else if sottotipo == "negativa" {
                nuovoValore = "Negativa"
            } else {
                nuovoValore = nil
            }
        } else {
            nuovoValore = nil
        }
        
        // Aggiorna solo se il valore è diverso
        if sinistro.fulminazione != nuovoValore {
            sinistro.fulminazione = nuovoValore
            try? sinistro.managedObjectContext?.save()
            print("[FileTagManager] ✅ Aggiornato campo fulminazione sinistro: \(nuovoValore ?? "nil")")
        }
        
        // Imposta "da allegare in chiusura" basandosi sulla compagnia e sul sottotipo
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        setFulminazioneDaAllegare(forFile: path, compagnia: compagnia, sottotipo: sottotipo)
    }
    
    /// Overload che cerca il sinistro dal path del file
    func updateSinistroFulminazioneIfNeeded(forFile path: String) {
        guard let riferimento = getRiferimentoFromPath(path) else {
            print("[FileTagManager] ⚠️ Impossibile estrarre riferimento dal path: \(path)")
            return
        }
        
        // Trova il sinistro corrispondente
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(request).first else {
            print("[FileTagManager] ⚠️ Sinistro non trovato per riferimento: \(riferimento)")
            return
        }
        
        updateSinistroFulminazioneIfNeeded(forFile: path, sinistro: sinistro)
    }
    
    /// Ottiene il riferimento del sinistro dal path del file
    private func getRiferimentoFromPath(_ path: String) -> String? {
        let fileService = FileService.shared
        let pathComponents = (path as NSString).pathComponents
        
        // Cerca nella gerarchia delle cartelle per trovare una cartella che corrisponde a un sinistro
        for i in stride(from: pathComponents.count - 1, through: 0, by: -1) {
            let partialPath = pathComponents[0...i].joined(separator: "/")
            if let riferimento = extractRiferimentoFromPath(partialPath) {
                // Verifica che sia una cartella sinistro valida
                if fileService.getSinistroPath(riferimento: riferimento, create: false) != nil {
                    return riferimento
                }
            }
        }
        
        return nil
    }
    
    /// Estrae il riferimento dalla path (assume che il nome della cartella sia il riferimento)
    private func extractRiferimentoFromPath(_ path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard let lastComponent = components.last, !lastComponent.isEmpty else { return nil }
        
        // Il riferimento è tipicamente il nome della cartella sinistro
        // Può essere nel formato "RIFERIMENTO" o "RIFERIMENTO - Descrizione"
        let riferimento = lastComponent.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return riferimento?.isEmpty == false ? riferimento : nil
    }
    
    /// Verifica se un sinistro ha file con tag atto_firmato nella sua cartella
    func checkSinistroConcordata(sinistroPath: String, sinistro: Sinistro) {
        var shouldBeConcordata = false
        
        for (path, tags) in fileTags {
            if path.hasPrefix(sinistroPath) {
                guard !isInPerxCache(path) else { continue }
                // Concordata se: atto firmato
                if tags.contains(where: { $0.id == "atto_firmato" }) {
                    shouldBeConcordata = true
                    break
                }
            }
        }
        
        if shouldBeConcordata && !sinistro.concordata {
            sinistro.concordata = true
            try? sinistro.managedObjectContext?.save()
        }
    }
    
    func removeTag(_ tag: FileTag, fromFile path: String, manualRemoval: Bool = true) {
        // Salva lo stato precedente nella storia prima di rimuovere
        let previousAdditionalText = fileTagMetadata[path]?[tag.id]
        let previousDaAllegare = fileTagDaAllegare[path]?[tag.id]
        let previousAttoSottotipo = fileTagAttoSottotipo[path]?[tag.id]
        let previousFulminazioneSottotipo = fileTagFulminazioneSottotipo[path]?[tag.id]
        let previousGiustificativiTipo = fileTagGiustificativiTipo[path]?[tag.id]
        let previousElaboratoExcelUltimo = fileTagElaboratoExcelUltimo[path]?[tag.id]
        let previousBeneRiferimento = fileTagBeneRiferimento[path]?[tag.id]
        
        addTagHistoryEntry(
            for: path,
            operation: .remove,
            tagId: tag.id,
            additionalText: previousAdditionalText,
            daAllegare: previousDaAllegare,
            attoSottotipo: previousAttoSottotipo,
            fulminazioneSottotipo: previousFulminazioneSottotipo,
            giustificativiTipo: previousGiustificativiTipo,
            elaboratoExcelUltimo: previousElaboratoExcelUltimo,
            beneRiferimento: previousBeneRiferimento
        )
        
        var currentTags = fileTags[path] ?? []
        currentTags.remove(tag)
        fileTags[path] = currentTags
        
        // Se è una rimozione manuale, traccia il tag per evitare che venga ri-applicato automaticamente
        if manualRemoval {
            if manuallyRemovedTags[path] == nil {
                manuallyRemovedTags[path] = []
            }
            manuallyRemovedTags[path]?.insert(tag.id)
        }
        
        fileTagMetadata[path]?.removeValue(forKey: tag.id)
        if fileTagMetadata[path]?.isEmpty == true {
            fileTagMetadata.removeValue(forKey: path)
        }
        
        fileTagDaAllegare[path]?.removeValue(forKey: tag.id)
        if fileTagDaAllegare[path]?.isEmpty == true {
            fileTagDaAllegare.removeValue(forKey: path)
        }
        
        // Rimuovi sottotipo atto se presente
        fileTagAttoSottotipo[path]?.removeValue(forKey: tag.id)
        if fileTagAttoSottotipo[path]?.isEmpty == true {
            fileTagAttoSottotipo.removeValue(forKey: path)
        }
        
        // Rimuovi stato atto se presente
        fileTagAttoStato[path]?.removeValue(forKey: tag.id)
        if fileTagAttoStato[path]?.isEmpty == true {
            fileTagAttoStato.removeValue(forKey: path)
        }
        
        // Rimuovi sottotipo fulminazione se presente
        fileTagFulminazioneSottotipo[path]?.removeValue(forKey: tag.id)
        if fileTagFulminazioneSottotipo[path]?.isEmpty == true {
            fileTagFulminazioneSottotipo.removeValue(forKey: path)
        }
        
        // Rimuovi tipo giustificativi se presente
        fileTagGiustificativiTipo[path]?.removeValue(forKey: tag.id)
        if fileTagGiustificativiTipo[path]?.isEmpty == true {
            fileTagGiustificativiTipo.removeValue(forKey: path)
        }
        
        // Rimuovi elaborato_excel_ultimo se presente
        fileTagElaboratoExcelUltimo[path]?.removeValue(forKey: tag.id)
        if fileTagElaboratoExcelUltimo[path]?.isEmpty == true {
            fileTagElaboratoExcelUltimo.removeValue(forKey: path)
        }
        
        // Rimuovi bene riferimento se presente
        fileTagBeneRiferimento[path]?.removeValue(forKey: tag.id)
        if fileTagBeneRiferimento[path]?.isEmpty == true {
            fileTagBeneRiferimento.removeValue(forKey: path)
        }
        
        // Se è elaborato_excel, aggiorna i flag ultimo
        if tag.id == "elaborato_excel" {
            updateElaboratoExcelUltimo()
        }
        
        saveTags()
        objectWillChange.send()
    }
    
    func getFilesWithTag(_ tag: FileTag) -> [String] {
        fileTags
            .filter { (path, tags) in
                !isInPerxCache(path) && tags.contains(tag)
            }
            .map { $0.key }
    }
    
    /// Verifica se un tag è stato rimosso manualmente dall'utente per un file
    func wasTagManuallyRemoved(tagId: String, fromFile path: String) -> Bool {
        return manuallyRemovedTags[path]?.contains(tagId) ?? false
    }
    
    /// Rimuove un tag dalla lista dei rimossi manualmente (utile se l'utente lo ri-aggiunge)
    func clearManuallyRemovedTag(tagId: String, fromFile path: String) {
        manuallyRemovedTags[path]?.remove(tagId)
        if manuallyRemovedTags[path]?.isEmpty == true {
            manuallyRemovedTags.removeValue(forKey: path)
        }
        saveTags()
    }
    
    func clearTags(forFile path: String) {
        fileTags[path] = []
        fileTagMetadata.removeValue(forKey: path)
        fileTagDaAllegare.removeValue(forKey: path)
        fileTagAttoSottotipo.removeValue(forKey: path)
        fileTagAttoStato.removeValue(forKey: path)
        fileTagFulminazioneSottotipo.removeValue(forKey: path)
        fileTagGiustificativiTipo.removeValue(forKey: path)
        fileTagElaboratoExcelUltimo.removeValue(forKey: path)
        fileTagBeneRiferimento.removeValue(forKey: path)
        pdfPageTags.removeValue(forKey: path)
        pdfPageTagMetadata.removeValue(forKey: path)
        saveTags()
        objectWillChange.send()
    }
    
    // MARK: - Tag per pagina PDF
    
    func getTagsForPDFPage(at path: String, pageIndex: Int) -> Set<FileTag> {
        pdfPageTags[path]?[pageIndex] ?? []
    }
    
    func getAdditionalTextForPDFPage(forFile path: String, pageIndex: Int, tagId: String) -> String? {
        pdfPageTagMetadata[path]?[pageIndex]?[tagId]
    }
    
    func addTag(_ tag: FileTag, toPDFPage path: String, pageIndex: Int, additionalText: String? = nil, daAllegareInChiusura: Bool? = nil) {
        if pdfPageTags[path] == nil {
            pdfPageTags[path] = [:]
        }
        if pdfPageTags[path]?[pageIndex] == nil {
            pdfPageTags[path]?[pageIndex] = []
        }
        pdfPageTags[path]?[pageIndex]?.insert(tag)
        
        if let additionalText = additionalText, !additionalText.isEmpty {
            if pdfPageTagMetadata[path] == nil {
                pdfPageTagMetadata[path] = [:]
            }
            if pdfPageTagMetadata[path]?[pageIndex] == nil {
                pdfPageTagMetadata[path]?[pageIndex] = [:]
            }
            pdfPageTagMetadata[path]?[pageIndex]?[tag.id] = additionalText
        }
        
        // Per i documenti (non foto), imposta "da allegare in chiusura" automaticamente a true
        let shouldAutoAllegare = daAllegareInChiusura ?? shouldAutoIncludeInClosure(tag: tag)
        
        if shouldAutoAllegare {
            if pdfPageDaAllegare[path] == nil {
                pdfPageDaAllegare[path] = [:]
            }
            if pdfPageDaAllegare[path]?[pageIndex] == nil {
                pdfPageDaAllegare[path]?[pageIndex] = [:]
            }
            pdfPageDaAllegare[path]?[pageIndex]?[tag.id] = true
        }
        
        saveTags()
        objectWillChange.send()
        
        // Crea versione "parlante" per rimozione tag
        createVersionForTagChange(filePath: path, operation: "Rimuovi tag", tagName: tag.name)
    }
    
    func removeTag(_ tag: FileTag, fromPDFPage path: String, pageIndex: Int) {
        pdfPageTags[path]?[pageIndex]?.remove(tag)
        pdfPageTagMetadata[path]?[pageIndex]?.removeValue(forKey: tag.id)
        
        if pdfPageTags[path]?[pageIndex]?.isEmpty == true {
            pdfPageTags[path]?.removeValue(forKey: pageIndex)
        }
        if pdfPageTagMetadata[path]?[pageIndex]?.isEmpty == true {
            pdfPageTagMetadata[path]?.removeValue(forKey: pageIndex)
        }
        if pdfPageTags[path]?.isEmpty == true {
            pdfPageTags.removeValue(forKey: path)
        }
        if pdfPageTagMetadata[path]?.isEmpty == true {
            pdfPageTagMetadata.removeValue(forKey: path)
        }
        
        saveTags()
        objectWillChange.send()
    }
    
    func setAdditionalTextForPDFPage(_ text: String?, forFile path: String, pageIndex: Int, tagId: String) {
        if pdfPageTagMetadata[path] == nil {
            pdfPageTagMetadata[path] = [:]
        }
        if pdfPageTagMetadata[path]?[pageIndex] == nil {
            pdfPageTagMetadata[path]?[pageIndex] = [:]
        }
        if let text = text, !text.isEmpty {
            pdfPageTagMetadata[path]?[pageIndex]?[tagId] = text
        } else {
            pdfPageTagMetadata[path]?[pageIndex]?.removeValue(forKey: tagId)
        }
        saveTags()
        objectWillChange.send()
    }
    
    func getAllPDFPageTags(forFile path: String) -> [Int: Set<FileTag>] {
        pdfPageTags[path] ?? [:]
    }
    
    func getDaAllegareForPDFPage(forFile path: String, pageIndex: Int, tagId: String) -> Bool {
        return pdfPageDaAllegare[path]?[pageIndex]?[tagId] ?? false
    }
    
    func setDaAllegareForPDFPage(_ value: Bool, forFile path: String, pageIndex: Int, tagId: String) {
        if pdfPageDaAllegare[path] == nil {
            pdfPageDaAllegare[path] = [:]
        }
        if pdfPageDaAllegare[path]?[pageIndex] == nil {
            pdfPageDaAllegare[path]?[pageIndex] = [:]
        }
        if value {
            pdfPageDaAllegare[path]?[pageIndex]?[tagId] = true
        } else {
            pdfPageDaAllegare[path]?[pageIndex]?.removeValue(forKey: tagId)
        }
        saveTags()
        objectWillChange.send()
    }
    
    /// Verifica se una pagina PDF ha almeno un tag con "da allegare in chiusura" attivo
    func hasAnyDaAllegareForPDFPage(forFile path: String, pageIndex: Int) -> Bool {
        guard let pageTags = pdfPageDaAllegare[path]?[pageIndex] else { return false }
        return pageTags.values.contains(true)
    }
    
    // MARK: - API per IA
    
    func addTagsFromAI(forFile path: String, tags: [(tagId: String, additionalText: String?, daAllegareInChiusura: Bool)]) {
        for (tagId, additionalText, daAllegare) in tags {
            if let tag = FileTag.availableTags.first(where: { $0.id == tagId }) {
                addTag(tag, toFile: path, additionalText: additionalText, daAllegareInChiusura: daAllegare)
            }
        }
    }
    
    func addTagsFromAIForPDFPage(forFile path: String, pageIndex: Int, tags: [(tagId: String, additionalText: String?)]) {
        for (tagId, additionalText) in tags {
            if let tag = FileTag.availableTags.first(where: { $0.id == tagId }) {
                addTag(tag, toPDFPage: path, pageIndex: pageIndex, additionalText: additionalText)
            }
        }
    }
    
    // MARK: - Persistenza basata su SHA256
    
    /// Calcola SHA256 di un file
    private func sha256Hash(filePath: String) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath)) else {
            return nil
        }
        defer { try? fileHandle.close() }
        
        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1MB chunks
        
        fileHandle.seek(toFileOffset: 0)
        while true {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Trova il path del sinistro da un file path
    private func getSinistroPath(for filePath: String) -> String? {
        // Cerca nella gerarchia delle cartelle per trovare una cartella che corrisponde a un sinistro
        let pathComponents = (filePath as NSString).pathComponents
        
        for i in stride(from: pathComponents.count - 1, through: 0, by: -1) {
            let partialPath = pathComponents[0...i].joined(separator: "/")
            if let riferimento = extractRiferimentoFromPath(partialPath) {
                // Verifica che sia una cartella sinistro valida
                if let sinistroPath = fileService.getSinistroPath(riferimento: riferimento, create: false) {
                    return sinistroPath
                }
            }
        }
        
        return nil
    }
    
    /// Crea una versione "parlante" quando cambiano i tag
    private func createVersionForTagChange(filePath: String, operation: String, tagName: String) {
        guard let sinistroPath = getSinistroPath(for: filePath) else {
            return
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        let description = "\(operation): \(tagName)"
        _ = versioningService.createVersion(of: fileURL, in: sinistroPath, description: description)
    }
    
    /// Struttura dati per i tag persistenti
    private struct PersistentTagData: Codable {
        var tags: [String] // Array di tag IDs
        var metadata: [String: String] // tagId: additionalText
        var daAllegare: [String: Bool] // tagId: daAllegareInChiusura
        var attoSottotipo: [String: String] // tagId: sottotipo
        var fulminazioneSottotipo: [String: String] // tagId: sottotipo
        var giustificativiTipo: [String: String] // tagId: tipo
        var allegatiAttoSottotipo: [String: String] // tagId: sottotipo
        var elaboratoExcelUltimo: [String: Bool] // tagId: ultimo
        var beneRiferimento: [String: String] // tagId: bene
        var manuallyRemoved: [String] // Array di tag IDs rimossi manualmente
        var pdfPageTags: [String: [String]]? // pageIndex: [tagId]
        var pdfPageMetadata: [String: [String: String]]? // pageIndex: [tagId: additionalText]
        var pdfPageDaAllegare: [String: [String: Bool]]? // pageIndex: [tagId: daAllegare]
        var history: [TagHistoryEntry]? // Storia completa dei tag
    }
    
    /// Salva i tag di un file nella cartella versioning basandosi su SHA256
    private func saveTagsToVersioning(for filePath: String) {
        guard !isInPerxCache(filePath) else { return }
        guard let sinistroPath = getSinistroPath(for: filePath) else { return }
        guard let sha256 = sha256Hash(filePath: filePath) else { return }
        
        let versionsDir = versioningService.getVersionsDirectory(for: sinistroPath)
        let tagsFileName = "\(sha256).tags.json"
        let tagsFilePath = (versionsDir as NSString).appendingPathComponent(tagsFileName)
        
        // Prepara i dati da salvare
        let tags = fileTags[filePath] ?? []
        let metadata = fileTagMetadata[filePath] ?? [:]
        let daAllegare = fileTagDaAllegare[filePath] ?? [:]
        let attoSottotipo = fileTagAttoSottotipo[filePath] ?? [:]
        let fulminazioneSottotipo = fileTagFulminazioneSottotipo[filePath] ?? [:]
        let giustificativiTipo = fileTagGiustificativiTipo[filePath] ?? [:]
        let allegatiAttoSottotipo = fileTagAllegatiAttoSottotipo[filePath] ?? [:]
        let elaboratoExcelUltimo = fileTagElaboratoExcelUltimo[filePath] ?? [:]
        let beneRiferimento = fileTagBeneRiferimento[filePath] ?? [:]
        let manuallyRemoved = manuallyRemovedTags[filePath] ?? []
        
        // Prepara i tag delle pagine PDF
        var pdfPageTagsData: [String: [String]]? = nil
        var pdfPageMetadataData: [String: [String: String]]? = nil
        var pdfPageDaAllegareData: [String: [String: Bool]]? = nil
        
        if let pageTags = pdfPageTags[filePath], !pageTags.isEmpty {
            pdfPageTagsData = pageTags.mapKeys { String($0) }.mapValues { tags in
                Array(tags.map { $0.id })
            }
            pdfPageMetadataData = pdfPageTagMetadata[filePath]?.mapKeys { String($0) }
            pdfPageDaAllegareData = pdfPageDaAllegare[filePath]?.mapKeys { String($0) }
        }
        
        let tagData = PersistentTagData(
            tags: Array(tags.map { $0.id }),
            metadata: metadata,
            daAllegare: daAllegare,
            attoSottotipo: attoSottotipo,
            fulminazioneSottotipo: fulminazioneSottotipo,
            giustificativiTipo: giustificativiTipo,
            allegatiAttoSottotipo: allegatiAttoSottotipo,
            elaboratoExcelUltimo: elaboratoExcelUltimo,
            beneRiferimento: beneRiferimento,
            manuallyRemoved: Array(manuallyRemoved),
            pdfPageTags: pdfPageTagsData,
            pdfPageMetadata: pdfPageMetadataData,
            pdfPageDaAllegare: pdfPageDaAllegareData,
            history: fileTagHistory[filePath]
        )
        
        // Salva con security-scoped access
        _ = fileService.performWithSecurityScopedAccess(to: sinistroPath) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(tagData)
                try data.write(to: URL(fileURLWithPath: tagsFilePath), options: .atomic)
                return true
            } catch {
                print("[FileTagManager] ⚠️ Errore salvataggio tag persistenti: \(error)")
                return false
            }
        }
    }
    
    /// Carica i tag di un file dalla cartella versioning basandosi su SHA256
    /// Restituisce true se sono stati caricati tag, false altrimenti
    @discardableResult
    func loadTagsFromVersioning(for filePath: String) -> Bool {
        guard !isInPerxCache(filePath) else { return false }
        guard let sinistroPath = getSinistroPath(for: filePath) else { return false }
        guard let sha256 = sha256Hash(filePath: filePath) else { return false }
        
        let versionsDir = versioningService.getVersionsDirectory(for: sinistroPath)
        let tagsFileName = "\(sha256).tags.json"
        let tagsFilePath = (versionsDir as NSString).appendingPathComponent(tagsFileName)
        
        // Carica con security-scoped access
        guard let data = fileService.performWithSecurityScopedAccess(to: sinistroPath, operation: {
            try? Data(contentsOf: URL(fileURLWithPath: tagsFilePath))
        }),
              let unwrappedData = data else {
            return false
        }
        
        guard let tagData = try? JSONDecoder().decode(PersistentTagData.self, from: unwrappedData) else {
            return false
        }
        
        // Applica i tag caricati
        let loadedTags = Set(tagData.tags.compactMap { tagId in
            FileTag.availableTags.first { $0.id == tagId }
        })
        
        // Solo se ci sono tag da applicare e il file non ha già tag (evita sovrascrivere modifiche recenti)
        if !loadedTags.isEmpty && (fileTags[filePath] == nil || fileTags[filePath]?.isEmpty == true) {
            fileTags[filePath] = loadedTags
            fileTagMetadata[filePath] = tagData.metadata
            fileTagDaAllegare[filePath] = tagData.daAllegare
            fileTagAttoSottotipo[filePath] = tagData.attoSottotipo
            fileTagFulminazioneSottotipo[filePath] = tagData.fulminazioneSottotipo
            fileTagGiustificativiTipo[filePath] = tagData.giustificativiTipo
            fileTagAllegatiAttoSottotipo[filePath] = tagData.allegatiAttoSottotipo
            fileTagElaboratoExcelUltimo[filePath] = tagData.elaboratoExcelUltimo
            fileTagBeneRiferimento[filePath] = tagData.beneRiferimento
            manuallyRemovedTags[filePath] = Set(tagData.manuallyRemoved)
            
            // Carica tag pagine PDF
            if let pdfPageTagsData = tagData.pdfPageTags {
                pdfPageTags[filePath] = Dictionary(uniqueKeysWithValues: pdfPageTagsData.compactMap { key, value -> (Int, Set<FileTag>)? in
                    guard let pageIndex = Int(key) else { return nil }
                    let tags = Set(value.compactMap { tagId in
                        FileTag.availableTags.first { $0.id == tagId }
                    })
                    return (pageIndex, tags)
                })
            }
            
            if let pdfPageMetadataData = tagData.pdfPageMetadata {
                pdfPageTagMetadata[filePath] = Dictionary(uniqueKeysWithValues: pdfPageMetadataData.compactMap { key, value -> (Int, [String: String])? in
                    guard let pageIndex = Int(key) else { return nil }
                    return (pageIndex, value)
                })
            }
            
            if let pdfPageDaAllegareData = tagData.pdfPageDaAllegare {
                pdfPageDaAllegare[filePath] = Dictionary(uniqueKeysWithValues: pdfPageDaAllegareData.compactMap { key, value -> (Int, [String: Bool])? in
                    guard let pageIndex = Int(key) else { return nil }
                    return (pageIndex, value)
                })
            }
            
            // Carica la storia se presente
            if let history = tagData.history, !history.isEmpty {
                fileTagHistory[filePath] = history
            }
            
            return true
        }
        
        return false
    }
    
    // MARK: - Persistenza
    
    private func saveTags() {
        // Salva i tag
        let tagData = fileTags.mapValues { tags in
            tags.map { ["id": $0.id, "name": $0.name] }
        }
        if let encoded = try? JSONEncoder().encode(tagData) {
            UserDefaults.standard.set(encoded, forKey: tagsKey)
        }
        
        // Salva i metadati
        if let metadataEncoded = try? JSONEncoder().encode(fileTagMetadata) {
            UserDefaults.standard.set(metadataEncoded, forKey: metadataKey)
        }
        
        // Salva daAllegareInChiusura
        if let daAllegareEncoded = try? JSONEncoder().encode(fileTagDaAllegare) {
            UserDefaults.standard.set(daAllegareEncoded, forKey: daAllegareKey)
        }
        
        // Salva sottotipo atto
        if let attoSottotipoEncoded = try? JSONEncoder().encode(fileTagAttoSottotipo) {
            UserDefaults.standard.set(attoSottotipoEncoded, forKey: attoSottotipoKey)
        }
        
        // Salva stato atto
        if let attoStatoEncoded = try? JSONEncoder().encode(fileTagAttoStato) {
            UserDefaults.standard.set(attoStatoEncoded, forKey: attoStatoKey)
        }
        
        // Salva sottotipo fulminazione
        if let fulminazioneSottotipoEncoded = try? JSONEncoder().encode(fileTagFulminazioneSottotipo) {
            UserDefaults.standard.set(fulminazioneSottotipoEncoded, forKey: fulminazioneSottotipoKey)
        }
        
        // Salva tipo giustificativi
        if let giustificativiTipoEncoded = try? JSONEncoder().encode(fileTagGiustificativiTipo) {
            UserDefaults.standard.set(giustificativiTipoEncoded, forKey: giustificativiTipoKey)
        }
        
        // Salva sottotipo allegati atto
        if let allegatiAttoSottotipoEncoded = try? JSONEncoder().encode(fileTagAllegatiAttoSottotipo) {
            UserDefaults.standard.set(allegatiAttoSottotipoEncoded, forKey: allegatiAttoSottotipoKey)
        }
        
        // Salva elaborato_excel_ultimo
        if let elaboratoExcelUltimoEncoded = try? JSONEncoder().encode(fileTagElaboratoExcelUltimo) {
            UserDefaults.standard.set(elaboratoExcelUltimoEncoded, forKey: elaboratoExcelUltimoKey)
        }
        
        // Salva bene riferimento
        if let beneRiferimentoEncoded = try? JSONEncoder().encode(fileTagBeneRiferimento) {
            UserDefaults.standard.set(beneRiferimentoEncoded, forKey: beneRiferimentoKey)
        }
        
        // Salva tag rimossi manualmente (converti Set in Array per JSON)
        let manuallyRemovedData = manuallyRemovedTags.mapValues { Array($0) }
        if let manuallyRemovedEncoded = try? JSONEncoder().encode(manuallyRemovedData) {
            UserDefaults.standard.set(manuallyRemovedEncoded, forKey: manuallyRemovedTagsKey)
        }
        
        // Salva i tag delle pagine PDF (converti Int in String per JSON)
        let pdfPageTagData: [String: [String: [[String: String]]]] = pdfPageTags.mapValues { pageTags in
            pageTags.mapKeys { String($0) }.mapValues { tags in
                tags.map { ["id": $0.id, "name": $0.name] }
            }
        }
        if let pdfPageTagsEncoded = try? JSONEncoder().encode(pdfPageTagData) {
            UserDefaults.standard.set(pdfPageTagsEncoded, forKey: pdfPageTagsKey)
        }
        
        // Salva i metadati delle pagine PDF (converti Int in String per JSON)
        let pdfPageMetadataData: [String: [String: [String: String]]] = pdfPageTagMetadata.mapValues { pageMetadata in
            pageMetadata.mapKeys { String($0) }
        }
        if let pdfPageMetadataEncoded = try? JSONEncoder().encode(pdfPageMetadataData) {
            UserDefaults.standard.set(pdfPageMetadataEncoded, forKey: pdfPageTagMetadataKey)
        }
        
        // Salva da allegare per pagine PDF (converti Int in String per JSON)
        let pdfPageDaAllegareData: [String: [String: [String: Bool]]] = pdfPageDaAllegare.mapValues { pageData in
            pageData.mapKeys { String($0) }
        }
        if let pdfPageDaAllegareEncoded = try? JSONEncoder().encode(pdfPageDaAllegareData) {
            UserDefaults.standard.set(pdfPageDaAllegareEncoded, forKey: pdfPageDaAllegareKey)
        }
        
        // Salva la storia dei tag (converti Date in TimeInterval per compatibilità JSON)
        let historyData: [String: [[String: Any]]] = fileTagHistory.mapValues { entries in
            entries.map { entry in
                var dict: [String: Any] = [
                    "id": entry.id.uuidString,
                    "timestamp": entry.timestamp.timeIntervalSince1970,
                    "operation": entry.operation.rawValue,
                    "tagId": entry.tagId
                ]
                if let text = entry.additionalText { dict["additionalText"] = text }
                if let daAllegare = entry.daAllegare { dict["daAllegare"] = daAllegare }
                if let attoSottotipo = entry.attoSottotipo { dict["attoSottotipo"] = attoSottotipo }
                if let fulminazioneSottotipo = entry.fulminazioneSottotipo { dict["fulminazioneSottotipo"] = fulminazioneSottotipo }
                if let giustificativiTipo = entry.giustificativiTipo { dict["giustificativiTipo"] = giustificativiTipo }
                if let elaboratoExcelUltimo = entry.elaboratoExcelUltimo { dict["elaboratoExcelUltimo"] = elaboratoExcelUltimo }
                if let beneRiferimento = entry.beneRiferimento { dict["beneRiferimento"] = beneRiferimento }
                return dict
            }
        }
        if let historyEncoded = try? JSONSerialization.data(withJSONObject: historyData) {
            UserDefaults.standard.set(historyEncoded, forKey: tagHistoryKey)
        }
        
        // Salva anche nella cartella versioning per tutti i file con tag
        for filePath in fileTags.keys {
            saveTagsToVersioning(for: filePath)
        }
    }
    
    private func loadTags() {
        // Carica i tag
        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
            fileTags = decoded.mapValues { tagDicts in
                Set(tagDicts.compactMap { dict in
                    FileTag.availableTags.first { $0.id == dict["id"] }
                })
            }
        }
        
        // Carica i metadati
        if let metadataData = UserDefaults.standard.data(forKey: metadataKey),
           let metadataDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: metadataData) {
            fileTagMetadata = metadataDecoded
        }
        
        // Carica daAllegareInChiusura
        if let daAllegareData = UserDefaults.standard.data(forKey: daAllegareKey),
           let daAllegareDecoded = try? JSONDecoder().decode([String: [String: Bool]].self, from: daAllegareData) {
            fileTagDaAllegare = daAllegareDecoded
        }
        
        // Carica sottotipo atto
        if let attoSottotipoData = UserDefaults.standard.data(forKey: attoSottotipoKey),
           let attoSottotipoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: attoSottotipoData) {
            fileTagAttoSottotipo = attoSottotipoDecoded
        }
        
        // Carica stato atto
        if let attoStatoData = UserDefaults.standard.data(forKey: attoStatoKey),
           let attoStatoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: attoStatoData) {
            fileTagAttoStato = attoStatoDecoded
        }
        
        // Carica sottotipo fulminazione
        if let fulminazioneSottotipoData = UserDefaults.standard.data(forKey: fulminazioneSottotipoKey),
           let fulminazioneSottotipoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: fulminazioneSottotipoData) {
            fileTagFulminazioneSottotipo = fulminazioneSottotipoDecoded
        }
        
        // Carica tipo giustificativi
        if let giustificativiTipoData = UserDefaults.standard.data(forKey: giustificativiTipoKey),
           let giustificativiTipoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: giustificativiTipoData) {
            fileTagGiustificativiTipo = giustificativiTipoDecoded
        }
        
        // Carica sottotipo allegati atto
        if let allegatiAttoSottotipoData = UserDefaults.standard.data(forKey: allegatiAttoSottotipoKey),
           let allegatiAttoSottotipoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: allegatiAttoSottotipoData) {
            fileTagAllegatiAttoSottotipo = allegatiAttoSottotipoDecoded
        }
        
        // Carica elaborato_excel_ultimo
        if let elaboratoExcelUltimoData = UserDefaults.standard.data(forKey: elaboratoExcelUltimoKey),
           let elaboratoExcelUltimoDecoded = try? JSONDecoder().decode([String: [String: Bool]].self, from: elaboratoExcelUltimoData) {
            fileTagElaboratoExcelUltimo = elaboratoExcelUltimoDecoded
        }
        
        // Carica bene riferimento
        if let beneRiferimentoData = UserDefaults.standard.data(forKey: beneRiferimentoKey),
           let beneRiferimentoDecoded = try? JSONDecoder().decode([String: [String: String]].self, from: beneRiferimentoData) {
            fileTagBeneRiferimento = beneRiferimentoDecoded
        }
        
        // Carica tag rimossi manualmente (converti Array in Set)
        if let manuallyRemovedData = UserDefaults.standard.data(forKey: manuallyRemovedTagsKey),
           let manuallyRemovedDecoded = try? JSONDecoder().decode([String: [String]].self, from: manuallyRemovedData) {
            manuallyRemovedTags = manuallyRemovedDecoded.mapValues { Set($0) }
        }
        
        // Carica i tag delle pagine PDF (converti String in Int)
        if let pdfPageTagsData = UserDefaults.standard.data(forKey: pdfPageTagsKey),
           let pdfPageTagsDecoded = try? JSONDecoder().decode([String: [String: [[String: String]]]].self, from: pdfPageTagsData) {
            pdfPageTags = pdfPageTagsDecoded.mapValues { pageTags in
                Dictionary(uniqueKeysWithValues: pageTags.compactMap { key, value in
                    guard let pageIndex = Int(key) else { return nil }
                    let tags = Set(value.compactMap { dict in
                        FileTag.availableTags.first { $0.id == dict["id"] }
                    })
                    return (pageIndex, tags)
                })
            }
        }
        
        // Carica i metadati delle pagine PDF (converti String in Int)
        if let pdfPageMetadataData = UserDefaults.standard.data(forKey: pdfPageTagMetadataKey),
           let pdfPageMetadataDecoded = try? JSONDecoder().decode([String: [String: [String: String]]].self, from: pdfPageMetadataData) {
            pdfPageTagMetadata = pdfPageMetadataDecoded.mapValues { pageMetadata in
                Dictionary(uniqueKeysWithValues: pageMetadata.compactMap { key, value in
                    guard let pageIndex = Int(key) else { return nil }
                    return (pageIndex, value)
                })
            }
        }
        
        // Carica da allegare per pagine PDF (converti String in Int)
        if let pdfPageDaAllegareData = UserDefaults.standard.data(forKey: pdfPageDaAllegareKey),
           let pdfPageDaAllegareDecoded = try? JSONDecoder().decode([String: [String: [String: Bool]]].self, from: pdfPageDaAllegareData) {
            pdfPageDaAllegare = pdfPageDaAllegareDecoded.mapValues { pageData in
                Dictionary(uniqueKeysWithValues: pageData.compactMap { key, value in
                    guard let pageIndex = Int(key) else { return nil }
                    return (pageIndex, value)
                })
            }
        }
        
        // Carica la storia dei tag (la storia viene principalmente salvata nella cartella versioning)
        // Per UserDefaults, carichiamo solo se presente (compatibilità con versioni future)
        if let historyData = UserDefaults.standard.data(forKey: tagHistoryKey),
           let historyDict = try? JSONSerialization.jsonObject(with: historyData) as? [String: [[String: Any]]] {
            // La storia viene principalmente gestita dalla cartella versioning
            // UserDefaults serve solo come backup temporaneo
            // Il caricamento completo avviene quando si caricano i tag dalla versioning
        }
    }
    
    // MARK: - Storia dei tag
    
    /// Restituisce la storia completa dei tag per un file (ordinata cronologicamente, più recente prima)
    func getTagHistory(forFile path: String) -> [TagHistoryEntry] {
        return fileTagHistory[path]?.sorted { $0.timestamp > $1.timestamp } ?? []
    }
    
    /// Restituisce l'ultimo tag applicato per un file (basato sulla storia)
    func getLastTagApplied(forFile path: String, tagId: String) -> TagHistoryEntry? {
        return getTagHistory(forFile: path).first { $0.tagId == tagId && $0.operation == .add }
    }
} 