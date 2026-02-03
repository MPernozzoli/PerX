import Foundation

class ExcelFinderService {
    static let shared = ExcelFinderService()
    private let fileService = FileService.shared
    private let fileTagManager = FileTagManager.shared
    
    private init() {}
    
    public enum ExcelFinderError: Error {
        case noExcelFileFound
        case multipleFilesNeedUserSelection
        case invalidFileName
        case permissionDenied
    }
    
    struct ExcelFileInfo {
        let url: URL
        let riferimento: String
        let versione: Int?
        let isControlloQualita: Bool
        
        var priority: Int {
            // CQ ha sempre priorità massima
            if isControlloQualita { return 1000 + (versione ?? 0) }
            // Altrimenti priorità basata sulla versione
            return versione ?? -1
        }
    }
    
    func findElaboratoPeritale(forSinistro sinistro: Sinistro) async throws -> URL {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            print("[ExcelFinder] ⚠️ Sinistro senza riferimento valido")
            throw ExcelFinderError.noExcelFileFound
        }
        
        guard let path = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[ExcelFinder] ⚠️ Cartella sinistro non trovata per riferimento: \(riferimento)")
            throw ExcelFinderError.noExcelFileFound
        }
        
        // Prima cerca un file con tag "elaborato_excel_ultimo"
        if let taggedExcelURL = await findTaggedExcelFile(inPath: path, preferUltimo: true) {
            print("[ExcelFinder] ✅ Trovato file Excel taggato (ultimo): \(taggedExcelURL.lastPathComponent)")
            return taggedExcelURL
        }
        
        // Poi cerca un file con tag "elaborato_excel" normale
        if let taggedExcelURL = await findTaggedExcelFile(inPath: path, preferUltimo: false) {
            print("[ExcelFinder] ✅ Trovato file Excel taggato: \(taggedExcelURL.lastPathComponent)")
            return taggedExcelURL
        }
        
        // Usa FileService per accedere alla directory con i permessi corretti
        let fileItems = fileService.listContents(inDirectory: path)
        
        // Filtra solo i file Excel (non directory) che iniziano con "Elaborato_Peritale_"
        let excelFiles = fileItems.filter { item in
            !item.isDirectory &&
            item.url.pathExtension.lowercased() == "xlsm" &&
            item.url.lastPathComponent.starts(with: "Elaborato_Peritale_")
        }.map { $0.url }
        
        guard !excelFiles.isEmpty else {
            // Log dettagliato per debug
            let allFiles = fileItems.map { $0.url.lastPathComponent }
            print("[ExcelFinder] ⚠️ Nessun file Excel trovato per sinistro \(riferimento)")
            print("[ExcelFinder] 📁 Cartella: \(path)")
            print("[ExcelFinder] 📋 File presenti nella cartella: \(allFiles.prefix(10).joined(separator: ", "))")
            throw ExcelFinderError.noExcelFileFound
        }
        
        // Analizza i nomi dei file
        var fileInfos: [ExcelFileInfo] = []
        var hasUnparseableFiles = false
        
        for fileURL in excelFiles {
            if let fileInfo = parseFileName(fileURL, riferimento: sinistro.riferimento ?? "") {
                fileInfos.append(fileInfo)
            } else {
                hasUnparseableFiles = true
            }
        }
        
        // Se non riusciamo a parsare tutti i file o non troviamo file validi
        if fileInfos.isEmpty || hasUnparseableFiles {
            throw ExcelFinderError.multipleFilesNeedUserSelection
        }
        
        // Ordina per priorità e prendi il primo
        return fileInfos.sorted { $0.priority > $1.priority }.first?.url ?? excelFiles[0]
    }
    
    /// Cerca un file con tag "elaborato_excel" nella cartella del sinistro
    /// Se preferUltimo è true, cerca solo file con flag "ultimo" = true
    private func findTaggedExcelFile(inPath path: String, preferUltimo: Bool) async -> URL? {
        guard let excelTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "elaborato_excel" }) else {
            return nil
        }
        
        let taggedFiles = await fileTagManager.getFilesWithTag(excelTag)
        
        // Cerca un file taggato che sia nella cartella del sinistro
        for taggedPath in taggedFiles {
            if taggedPath.hasPrefix(path) {
                let url = URL(fileURLWithPath: taggedPath)
                let ext = url.pathExtension.lowercased()
                // Verifica che sia un file Excel valido
                guard ext == "xlsm" || ext == "xlsx" || ext == "xls" else {
                    continue
                }
                
                // Se preferUltimo è true, verifica che il file abbia il flag "ultimo"
                if preferUltimo {
                    let isUltimo = await fileTagManager.getElaboratoExcelUltimo(forFile: taggedPath, tagId: "elaborato_excel") ?? false
                    if isUltimo {
                        return url
                    }
                } else {
                    // Se preferUltimo è false, verifica che il file NON abbia il flag "ultimo" (o non sia impostato)
                    let isUltimo = await fileTagManager.getElaboratoExcelUltimo(forFile: taggedPath, tagId: "elaborato_excel") ?? false
                    if !isUltimo {
                        return url
                    }
                }
            }
        }
        
        return nil
    }
    
    private func parseFileName(_ url: URL, riferimento: String) -> ExcelFileInfo? {
        let filename = url.lastPathComponent
        
        // Formato atteso: Elaborato_Peritale_[riferimento]_[versione]_[(opzionale)CQ].xlsm
        let components = filename.dropLast(5) // rimuove .xlsm
            .split(separator: "_")
        
        guard components.count >= 4,
              components[0] == "Elaborato",
              components[1] == "Peritale",
              String(components[2]) == riferimento else {
            return nil
        }
        
        let isControlloQualita = components.last == "CQ"
        let versioneComponent = components[components.count - (isControlloQualita ? 2 : 1)]
        let versione = Int(versioneComponent)
        
        return ExcelFileInfo(
            url: url,
            riferimento: riferimento,
            versione: versione,
            isControlloQualita: isControlloQualita
        )
    }
    
    func needsExcelDataUpdate(_ sinistro: Sinistro) -> Bool {
        // Verifica se mancano dati che dovrebbero essere estratti dall'Excel
        return sinistro.richiesta == nil ||
               sinistro.liquidato == nil ||
               sinistro.dannoAccertato == nil ||
               sinistro.dannoAccertatoNetto == nil
    }
} 