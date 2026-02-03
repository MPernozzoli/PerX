import Foundation
import PDFKit
import AppKit

/// Genera i file PDF di chiusura per un sinistro
class ClosureFilesService {
    static let shared = ClosureFilesService()
    
    private let fileService = FileService.shared
    private let fileTagManager = FileTagManager.shared
    private let compagniaService = CompagniaService.shared
    private let claimSyncService = ClaimSyncService.shared
    private let signatureService = SignatureService.shared
    private let placementService = SignaturePlacementService.shared
    private let editorService = MediaEditorService.shared
    
    private init() {}
    
    // MARK: - Strutture dati
    
    struct PhotoItem {
        let url: URL
        let tagId: String
        let caption: String
        let additionalText: String // Testo aggiuntivo originale (es. nome del bene per foto_bene)
        let beneRiferimento: String?
        let sortOrder: Int
        let pdfPageIndex: Int? // Se è una pagina di un PDF, indica l'indice
        
        var isPDFPage: Bool {
            pdfPageIndex != nil
        }
    }
    
    struct ClosureResult {
        let generatedFiles: [URL]
        let errors: [String]
        let skippedFiles: [String]
    }
    
    // Limite massimo per file singolo da caricare (10 MB)
    private let maxUploadFileSize: Int64 = 10 * 1024 * 1024
    
    // MARK: - API Pubblica
    
    /// Restituisce i file con annotazioni tra quelli da processare per la chiusura
    @MainActor
    func getFilesWithAnnotations(for sinistro: Sinistro) async -> [URL] {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return []
        }
        
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        let taggedFiles = await collectTaggedFilesForClosure(inPath: sinistroPath, compagnia: compagnia)
        let annotationService = PDFAnnotationService.shared
        
        return taggedFiles
            .map { $0.url }
            .filter { annotationService.hasAnnotations(for: $0.path) }
    }
    
    /// Converte uno o più file in PDF nella stessa directory
    func convertFilesToPDF(fileURLs: [URL], completion: @escaping (Int, [String]) -> Void) {
        var successCount = 0
        var errors: [String] = []
        
        for fileURL in fileURLs {
            let outputURL = fileURL.deletingPathExtension().appendingPathExtension("pdf")
            
            // Se è già PDF, salta
            if fileURL.pathExtension.lowercased() == "pdf" {
                errors.append("\(fileURL.lastPathComponent) è già un PDF")
                continue
            }
            
            if convertToPDF(fileURL: fileURL, outputURL: outputURL) {
                successCount += 1
            } else {
                errors.append("Errore conversione \(fileURL.lastPathComponent)")
            }
        }
        
        completion(successCount, errors)
    }
    
    /// Crea un unico PDF da più file, un file per pagina senza margini
    func mergeFilesToSinglePDF(fileURLs: [URL], outputURL: URL, completion: @escaping (Bool, String?) -> Void) {
        guard !fileURLs.isEmpty else {
            completion(false, "Nessun file selezionato")
            return
        }
        
        let outputPath = outputURL.deletingLastPathComponent().path
        
        // Crea il PDF finale
        let mergedPDFData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mergedPDFData as CFMutableData) else {
            completion(false, "Errore creazione consumer PDF")
            return
        }
        
        // Usa le dimensioni della prima pagina per inizializzare il context
        var tempPDFs: [URL] = []
        var firstPageBounds: CGRect?
        
        // Converti tutti i file in PDF temporanei
        for fileURL in fileURLs {
            let tempURL = outputURL.deletingLastPathComponent().appendingPathComponent("temp_\(UUID().uuidString).pdf")
            
            // Se è già PDF, copialo direttamente
            if fileURL.pathExtension.lowercased() == "pdf" {
                let success = fileService.performWithSecurityScopedAccess(to: outputPath) {
                    do {
                        if FileManager.default.fileExists(atPath: tempURL.path) {
                            try FileManager.default.removeItem(at: tempURL)
                        }
                        try FileManager.default.copyItem(at: fileURL, to: tempURL)
                        return true
                    } catch {
                        return false
                    }
                } ?? false
                
                if success {
                    tempPDFs.append(tempURL)
                    if firstPageBounds == nil, let pdf = PDFDocument(url: tempURL),
                       let firstPage = pdf.page(at: 0) {
                        firstPageBounds = firstPage.bounds(for: .mediaBox)
                    }
                }
            } else {
                // Converti in PDF
                if convertToPDFWithoutSignature(fileURL: fileURL, outputURL: tempURL) {
                    tempPDFs.append(tempURL)
                    if firstPageBounds == nil, let pdf = PDFDocument(url: tempURL),
                       let firstPage = pdf.page(at: 0) {
                        firstPageBounds = firstPage.bounds(for: .mediaBox)
                    }
                }
            }
        }
        
        guard !tempPDFs.isEmpty else {
            completion(false, "Nessun file convertito con successo")
            return
        }
        
        // Usa le dimensioni della prima pagina o A4 come fallback
        let mediaBox = firstPageBounds ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        var mutableMediaBox = mediaBox
        
        guard let mergedContext = CGContext(consumer: consumer, mediaBox: &mutableMediaBox, nil) else {
            // Pulisci file temporanei
            for tempURL in tempPDFs {
                try? FileManager.default.removeItem(at: tempURL)
            }
            completion(false, "Errore creazione context PDF")
            return
        }
        
        // Aggiungi tutte le pagine di tutti i file
        for tempURL in tempPDFs {
            guard let pdf = PDFDocument(url: tempURL) else {
                continue
            }
            
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                var pageMediaBox = pageBounds
                
                mergedContext.beginPDFPage(nil)
                
                // Disegna la pagina senza margini
                if let pageRef = page.pageRef {
                    mergedContext.saveGState()
                    mergedContext.drawPDFPage(pageRef)
                    mergedContext.restoreGState()
                } else {
                    mergedContext.saveGState()
                    page.draw(with: .mediaBox, to: mergedContext)
                    mergedContext.restoreGState()
                }
                
                mergedContext.endPDFPage()
            }
        }
        
        // Chiudi il PDF
        mergedContext.closePDF()
        
        // Salva il PDF finale
        let success = fileService.performWithSecurityScopedAccess(to: outputPath) {
            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try mergedPDFData.write(to: outputURL, options: .atomic)
                return true
            } catch {
                print("[ClosureFiles] ❌ Errore salvataggio PDF unificato: \(error)")
                return false
            }
        } ?? false
        
        // Pulisci file temporanei
        for tempURL in tempPDFs {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        if success {
            completion(true, nil)
        } else {
            completion(false, "Errore salvataggio PDF finale")
        }
    }
    
    /// Genera tutti i file di chiusura per un sinistro
    /// - Parameter annotationDecisions: Dizionario che mappa filePath -> true se includere annotazioni
    func generateClosureFiles(
        for sinistro: Sinistro,
        attoSottotipo: SottotipoAtto? = nil,
        annotationDecisions: [String: Bool] = [:],
        completion: @escaping (ClosureResult) -> Void
    ) {
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            completion(ClosureResult(generatedFiles: [], errors: ["Cartella sinistro non trovata"], skippedFiles: []))
            return
        }
        
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        
        // Crea cartella "Da Chiudere" se non esiste
        let daChiuderePath = (sinistroPath as NSString).appendingPathComponent("Da Chiudere")
        let folderExists = fileService.performWithSecurityScopedAccess(to: sinistroPath, operation: {
            FileManager.default.fileExists(atPath: daChiuderePath)
        }) ?? false
        
        if !folderExists {
            let created = fileService.performWithSecurityScopedAccess(to: sinistroPath, operation: {
                do {
                    try FileManager.default.createDirectory(atPath: daChiuderePath, withIntermediateDirectories: true)
                    return true
                } catch {
                    print("[ClosureFiles] ❌ Errore creazione cartella Da Chiudere: \(error)")
                    return false
                }
            }) ?? false
            
            guard created else {
                completion(ClosureResult(generatedFiles: [], errors: ["Impossibile creare cartella Da Chiudere"], skippedFiles: []))
                return
            }
        }
        
        // Pulisci la cartella "Da Chiudere": sposta file esistenti nella root del sinistro
        cleanDaChiudereFolder(daChiuderePath: daChiuderePath, sinistroPath: sinistroPath)
        
        Task { @MainActor in
            var generatedFiles: [URL] = []
            var errors: [String] = []
            var skippedFiles: [String] = []
            
            // Raccogli tutti i file taggati "da allegare in chiusura"
            let taggedFiles = await collectTaggedFilesForClosure(inPath: sinistroPath, compagnia: compagnia)
            
            // Gestisci file foto: verifica se ci sono file già taggati con "file_foto"
            let filesWithFileFotoTag = await collectFilesWithFileFotoTag(inPath: sinistroPath)
            
            if !filesWithFileFotoTag.isEmpty {
            // Se ci sono file taggati con "file_foto", clona i file invece di spostarli o generare PDF
            for (index, fileItem) in filesWithFileFotoTag.enumerated() {
                let progressivo = filesWithFileFotoTag.count > 1 ? index + 1 : nil
                let nomeFile = compagniaService.generaNomeFile(
                    compagnia: compagnia,
                    riferimento: riferimento,
                    tipoFile: .foto,
                    progressivo: progressivo
                )
                let outputURL = URL(fileURLWithPath: daChiuderePath).appendingPathComponent("\(nomeFile).\(fileItem.url.pathExtension)")
                
                // Usiamo copyItem per clonare il file, preservando l'originale
                if copyFileWithSecurityScopedAccess(from: fileItem.url, to: outputURL) {
                    await tagGeneratedFile(at: outputURL.path, tagId: "file_foto")
                    generatedFiles.append(outputURL)
                } else {
                    errors.append("Errore copia \(fileItem.url.lastPathComponent)")
                }
            }
        } else {
            // Genera PDF Foto solo se non ci sono file già taggati con "file_foto"
            let photoFiles = taggedFiles.filter { isPhotoTag($0.tagId) }
            if !photoFiles.isEmpty {
                if let photoURL = generatePhotoPDF(
                    photos: photoFiles,
                    riferimento: riferimento,
                    compagnia: compagnia,
                    outputPath: daChiuderePath
                ) {
                    // Taggare il file generato
                    await tagGeneratedFile(at: photoURL.path, tagId: "file_foto")
                    generatedFiles.append(photoURL)
                } else {
                    errors.append("Errore generazione PDF foto")
                }
            }
        }
        
        // Genera PDF per altri file taggati
        let nonPhotoFiles = taggedFiles.filter { !isPhotoTag($0.tagId) }
        
        // Separa atti dagli altri file (escludi allegati_atto che vengono aggiunti all'atto)
        let attoFiles = nonPhotoFiles.filter { $0.tagId == "atto_da_firmare" || $0.tagId == "atto_firmato" }
        let otherFiles = nonPhotoFiles.filter { 
            $0.tagId != "atto_da_firmare" && 
            $0.tagId != "atto_firmato" && 
            $0.tagId != "allegati_atto"
        }
        
        // Determina se è concordata: atto_firmato presente
        var hasAttoFirmato = false
        for attoFile in attoFiles {
            // attoFiles contiene file con tag "atto_da_firmare" o "atto_firmato"
            let tags = await fileTagManager.getTagsForFile(at: attoFile.url.path)
            if tags.contains(where: { $0.id == "atto_firmato" }) {
                hasAttoFirmato = true
                break
            }
        }
        let isConcordata = hasAttoFirmato || sinistro.concordata
        
        // Aggiorna la proprietà concordata del sinistro
        if isConcordata && !sinistro.concordata {
            sinistro.concordata = true
            try? sinistro.managedObjectContext?.save()
        }
        
        // Genera PDF per atto
        if !attoFiles.isEmpty {
            // Priorità agli atti firmati
            var attoFile = attoFiles[0]
            var attiFirmati: [PhotoItem] = []
            var attiDaFirmare: [PhotoItem] = []
            
            for atto in attoFiles {
                let tags = await fileTagManager.getTagsForFile(at: atto.url.path)
                if tags.contains(where: { $0.id == "atto_firmato" }) {
                    attiFirmati.append(atto)
                } else if tags.contains(where: { $0.id == "atto_da_firmare" }) {
                    attiDaFirmare.append(atto)
                }
            }
            
            // Seleziona atto firmato se disponibile, altrimenti atto da firmare
            if !attiFirmati.isEmpty {
                attoFile = attiFirmati[0]
            } else if !attiDaFirmare.isEmpty {
                attoFile = attiDaFirmare[0]
            }
            
            let sottotipo = await determineSottotipoAtto(filePath: attoFile.url.path, sinistro: sinistro, provided: attoSottotipo)
            
            let nomeFile = compagniaService.generaNomeFile(
                compagnia: compagnia,
                riferimento: riferimento,
                tipoFile: .atto,
                concordata: isConcordata,
                sottotipoAtto: sottotipo
            )
            
            let outputURL = URL(fileURLWithPath: daChiuderePath).appendingPathComponent("\(nomeFile).pdf")
            
            // Raccogli allegati atto
            let allegatiAtto = await collectAllegatiAtto(inPath: sinistroPath)
            
            // Genera PDF atto con allegati
            if await generateAttoPDFWithAllegati(
                attoFile: attoFile.url,
                allegati: allegatiAtto,
                outputURL: outputURL
            ) {
                // Taggare il file generato
                await tagGeneratedFile(at: outputURL.path, tagId: "file_atto")
                generatedFiles.append(outputURL)
            } else {
                errors.append("Errore conversione \(attoFile.url.lastPathComponent)")
            }
        }
        
        // Genera PDF per gli altri file
        for file in otherFiles {
            let tipoFile = mapTagToTipoFile(file.tagId)
            let sottotipoAttoFile = await determineSottotipoAtto(filePath: file.url.path, sinistro: sinistro, provided: attoSottotipo)
            let sottotipoGiust = determineSottotipoGiustificativo(tagId: file.tagId)
            
            let nomeFile = compagniaService.generaNomeFile(
                compagnia: compagnia,
                riferimento: riferimento,
                tipoFile: tipoFile,
                concordata: isConcordata,
                sottotipoAtto: sottotipoAttoFile,
                sottotipoGiustificativo: sottotipoGiust
            )
            
            let outputURL = URL(fileURLWithPath: daChiuderePath).appendingPathComponent("\(nomeFile).pdf")
            
            // Controlla se includere annotazioni
            let includeAnnotations = annotationDecisions[file.url.path] ?? false
            
            if convertToPDF(fileURL: file.url, outputURL: outputURL, includeAnnotations: includeAnnotations) {
                // Taggare il file generato in base al tipo
                let closureTagId = mapTagToClosureTag(file.tagId)
                await tagGeneratedFile(at: outputURL.path, tagId: closureTagId)
                generatedFiles.append(outputURL)
            } else {
                errors.append("Errore conversione \(file.url.lastPathComponent)")
            }
            }
            
            completion(ClosureResult(generatedFiles: generatedFiles, errors: errors, skippedFiles: skippedFiles))
            
            // Upload immediato dei file di chiusura (prioritario)
            if !generatedFiles.isEmpty {
                let prepared = self.prepareClosureFilesForUpload(generatedFiles, sinistroPath: sinistroPath)
                Task { @MainActor in
                    await self.claimSyncService.uploadClosureFilesImmediately(riferimento: riferimento, fileURLs: prepared)
                }
            }
        }
    }
    
    /// Verifica dimensione e, se necessario, comprime/splitta i file per rientrare sotto i 10 MB.
    /// Nota: opera dentro la cartella del sinistro con security-scoped access.
    private func prepareClosureFilesForUpload(_ files: [URL], sinistroPath: String) -> [URL] {
        var result: [URL] = []
        
        let prepared: [URL] = fileService.performWithSecurityScopedAccess(to: sinistroPath) {
            var out: [URL] = []
            for url in files {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                    ?? (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
                    ?? 0
                
                if size > 0 && size > maxUploadFileSize {
                    out.append(contentsOf: compressOrSplitToUnderLimit(url: url, maxBytes: maxUploadFileSize))
                } else {
                    out.append(url)
                }
            }
            return out
        } ?? files
        
        result.append(contentsOf: prepared)
        return result
    }
    
    /// Strategia:
    /// - prova a zippare il file
    /// - se lo zip resta > limite, splitta lo zip in parti <= ~9MB
    /// - NON rimuove l'originale (richiesto dall'utente per preservare i file di partenza)
    private func compressOrSplitToUnderLimit(url: URL, maxBytes: Int64) -> [URL] {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        
        // 1) ZIP (massima compressione)
        let zipURL = dir.appendingPathComponent(url.lastPathComponent + ".zip")
        _ = try? fm.removeItem(at: zipURL)
        
        let zipOk = runZip(input: url, output: zipURL)
        if zipOk, let zipSize = (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? NSNumber)?.int64Value {
            if zipSize <= maxBytes {
                // Restituiamo lo zip, ma NON cancelliamo l'originale
                return [zipURL]
            }
            
            // 2) Split in parti (<= ~9MB)
            let parts = splitFile(zipURL, partSizeBytes: 9 * 1024 * 1024)
            if !parts.isEmpty {
                // Rimuoviamo lo zip temporaneo ma NON l'originale
                try? fm.removeItem(at: zipURL)
                return parts
            }
        }
        
        // Fallback: se non riusciamo a ridurre, manteniamo il file (verrà comunque caricato, ma può fallire lato server)
        return [url]
    }
    
    private func runZip(input: URL, output: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -j: no path, -9: max compression
        process.arguments = ["-j", "-9", output.lastPathComponent, input.lastPathComponent]
        process.currentDirectoryURL = input.deletingLastPathComponent()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func splitFile(_ url: URL, partSizeBytes: Int) -> [URL] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        var partIndex = 1
        var parts: [URL] = []
        
        while true {
            let data = try? handle.read(upToCount: partSizeBytes)
            guard let data, !data.isEmpty else { break }
            
            let partName = String(format: "%@.part%02d.%@", base, partIndex, ext.isEmpty ? "bin" : ext)
            let partURL = dir.appendingPathComponent(partName)
            _ = try? fm.removeItem(at: partURL)
            do {
                try data.write(to: partURL, options: .atomic)
                parts.append(partURL)
            } catch {
                // Se fallisce, pulisci e abort
                for p in parts { try? fm.removeItem(at: p) }
                return []
            }
            partIndex += 1
        }
        
        return parts
    }
    
    // MARK: - Raccolta file taggati
    
    private func collectTaggedFilesForClosure(inPath sinistroPath: String, compagnia: Compagnia) async -> [PhotoItem] {
        var items: [PhotoItem] = []
        
        print("[ClosureFiles] 🔍 Raccolta file taggati da: \(sinistroPath)")
        
        // Scansiona tutti i file nella cartella sinistro ricorsivamente
        var allFiles = fileService.listFilesRecursive(inDirectory: sinistroPath)
        
        // Fallback: scansione diretta se listFilesRecursive non funziona
        if allFiles.isEmpty {
            print("[ClosureFiles] ⚠️ listFilesRecursive vuoto, provo scansione diretta")
            allFiles = scanDirectoryRecursive(sinistroPath)
        }
        
        print("[ClosureFiles] 📁 File totali trovati: \(allFiles.count)")
        
        var taggedFileCount = 0
        var includedFileCount = 0
        
        for fileURL in allFiles {
            let path = fileURL.path
            
            // Salta la cartella "Da Chiudere" per evitare loop
            if path.contains("/Da Chiudere/") {
                continue
            }
            
            // 1. Raccogli tag a livello file
            let tags = await fileTagManager.getTagsForFile(at: path)
            
            if !tags.isEmpty {
                taggedFileCount += 1
            }
            
            for tag in tags {
                // Per fulminazione, applica la logica della compagnia
                let shouldInclude: Bool
                if tag.id == "fulminazione" {
                    shouldInclude = await shouldIncludeFulminazione(forFile: path, compagnia: compagnia)
                    if !shouldInclude {
                        print("[ClosureFiles] ⏭️ Fulminazione esclusa per logica compagnia: \(fileURL.lastPathComponent)")
                    }
                } else {
                    // Per altri tag, usa il flag "da allegare in chiusura"
                    shouldInclude = await fileTagManager.getDaAllegareInChiusura(forFile: path, tagId: tag.id)
                    if !shouldInclude {
                        print("[ClosureFiles] ⏭️ Tag '\(tag.id)' senza 'da allegare': \(fileURL.lastPathComponent)")
                    }
                }
                
                guard shouldInclude else { continue }
                
                includedFileCount += 1
                print("[ClosureFiles] ✅ Incluso: \(fileURL.lastPathComponent) [tag: \(tag.id)]")
                
                let additionalText = await fileTagManager.getAdditionalText(forFile: path, tagId: tag.id) ?? ""
                let beneRiferimento = await fileTagManager.getBeneRiferimento(forFile: path, tagId: tag.id)
                let caption = generateCaption(tagId: tag.id, additionalText: additionalText, beneRiferimento: beneRiferimento)
                
                items.append(PhotoItem(
                    url: fileURL,
                    tagId: tag.id,
                    caption: caption,
                    additionalText: additionalText,
                    beneRiferimento: beneRiferimento,
                    sortOrder: sortOrderForTag(tag.id),
                    pdfPageIndex: nil
                ))
            }
            
            // 2. Per i PDF, raccogli anche i tag delle singole pagine
            if fileURL.pathExtension.lowercased() == "pdf" {
                let pdfPageTags = await fileTagManager.getAllPDFPageTags(forFile: path)
                
                for (pageIndex, pageTags) in pdfPageTags {
                    for tag in pageTags {
                        // Verifica se la pagina ha il flag "da allegare in chiusura" per questo tag
                        guard await fileTagManager.getDaAllegareForPDFPage(forFile: path, pageIndex: pageIndex, tagId: tag.id) else {
                            continue
                        }
                        guard isPhotoTag(tag.id) else { continue }
                        
                        print("[ClosureFiles] ✅ Inclusa pagina PDF \(pageIndex): \(fileURL.lastPathComponent) [tag: \(tag.id)]")
                        
                        let additionalText = await fileTagManager.getAdditionalTextForPDFPage(forFile: path, pageIndex: pageIndex, tagId: tag.id) ?? ""
                        let beneRiferimento: String? = nil
                        let caption = generateCaption(tagId: tag.id, additionalText: additionalText, beneRiferimento: beneRiferimento)
                        
                        items.append(PhotoItem(
                            url: fileURL,
                            tagId: tag.id,
                            caption: caption,
                            additionalText: additionalText,
                            beneRiferimento: beneRiferimento,
                            sortOrder: sortOrderForTag(tag.id),
                            pdfPageIndex: pageIndex
                        ))
                    }
                }
            }
        }
        
        print("[ClosureFiles] 📊 Riepilogo: \(taggedFileCount) file taggati, \(includedFileCount) inclusi per chiusura")
        
        // Ordina con logica avanzata: ubicazioni prima, poi raggruppato per bene
        return sortPhotosWithBeneGrouping(items)
    }
    
    /// Ordina le foto secondo la logica:
    /// 1. Foto ubicazione rischio
    /// 2. Foto altre ubicazioni
    /// 3. Per ogni bene (in ordine alfabetico):
    ///    - Foto bene
    ///    - Foto componenti
    ///    - Foto test funzionali/strumentali
    ///    - Foto ripristini
    private func sortPhotosWithBeneGrouping(_ items: [PhotoItem]) -> [PhotoItem] {
        // Separa ubicazioni dalle foto dei beni
        let ubicazioni = items.filter { isUbicazioneTag($0.tagId) }
        let beniFotos = items.filter { !isUbicazioneTag($0.tagId) }
        
        // Ordina ubicazioni: rischio prima, poi tecnico, poi altre
        let sortedUbicazioni = ubicazioni.sorted { sortOrderForTag($0.tagId) < sortOrderForTag($1.tagId) }
        
        // Raggruppa foto per bene
        // Per foto_bene: il nome del bene è nella caption (additionalText)
        // Per componenti/test/ripristino: il nome del bene è in beneRiferimento
        var beniMap: [String: [PhotoItem]] = [:]
        var senzaBene: [PhotoItem] = []
        
        for foto in beniFotos {
            let nomeBene = determinaNomeBene(for: foto)
            if let bene = nomeBene, !bene.isEmpty {
                if beniMap[bene] == nil {
                    beniMap[bene] = []
                }
                beniMap[bene]?.append(foto)
            } else {
                senzaBene.append(foto)
            }
        }
        
        // Ordina i nomi dei beni alfabeticamente
        let beniOrdinati = beniMap.keys.sorted()
        
        // Costruisci l'array finale
        var result: [PhotoItem] = []
        
        // 1. Ubicazioni
        result.append(contentsOf: sortedUbicazioni)
        
        // 2. Per ogni bene, ordina le foto interne
        for bene in beniOrdinati {
            if let fotosBene = beniMap[bene] {
                let ordinate = fotosBene.sorted { sortOrderIntraBene($0.tagId) < sortOrderIntraBene($1.tagId) }
                result.append(contentsOf: ordinate)
            }
        }
        
        // 3. Foto senza bene specificato (ordinate per tipo) - in fondo
        let senzaBeneOrdinato = senzaBene.sorted { sortOrderIntraBene($0.tagId) < sortOrderIntraBene($1.tagId) }
        result.append(contentsOf: senzaBeneOrdinato)
        
        return result
    }
    
    /// Determina il nome del bene a cui appartiene una foto
    private func determinaNomeBene(for foto: PhotoItem) -> String? {
        switch foto.tagId {
        case "foto_bene":
            // Per foto_bene, il nome del bene è nell'additionalText
            return foto.additionalText.isEmpty ? nil : foto.additionalText
            
        case "foto_componente", "foto_test_funzionale", "test_strumentale", "foto_ripristino":
            // Per questi tag, il nome del bene è in beneRiferimento
            return foto.beneRiferimento
            
        default:
            return foto.beneRiferimento
        }
    }
    
    /// Verifica se un tag è di ubicazione
    private func isUbicazioneTag(_ tagId: String) -> Bool {
        return FileTagManager.FileTag.ubicazioneTags.contains(tagId)
    }
    
    /// Ordine delle foto all'interno di un gruppo bene:
    /// foto_bene → foto_componente → foto_test_funzionale/test_strumentale → foto_ripristino
    private func sortOrderIntraBene(_ tagId: String) -> Int {
        switch tagId {
        case "foto_bene": return 0
        case "foto_componente": return 1
        case "foto_test_funzionale": return 2
        case "test_strumentale": return 3
        case "foto_ripristino": return 4
        default: return 10
        }
    }
    
    /// Scansione diretta ricorsiva (fallback)
    private func scanDirectoryRecursive(_ path: String) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        let directoryURL = URL(fileURLWithPath: path)
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                results.append(url)
            }
        }
        
        return results
    }
    
    private func isPhotoTag(_ tagId: String) -> Bool {
        return tagId.hasPrefix("foto_") || tagId == "test_strumentale"
    }
    
    private func sortOrderForTag(_ tagId: String) -> Int {
        switch tagId {
        case "foto_ubicazione_rischio": return 0
        case "foto_ubicazione_tecnico": return 1
        case "foto_ubicazione_amministratore": return 2
        case "foto_ubicazione_altra": return 3
        case "foto_bene": return 10
        case "foto_componente": return 20
        case "foto_test_funzionale": return 30
        case "test_strumentale": return 31
        case "foto_ripristino": return 40
        default: return 100
        }
    }
    
    private func generateCaption(tagId: String, additionalText: String, beneRiferimento: String?) -> String {
        switch tagId {
        case "foto_ubicazione_rischio":
            return "Ubicazione del rischio assicurato"
        case "foto_ubicazione_tecnico":
            return "Ubicazione tecnico riparatore"
        case "foto_ubicazione_amministratore":
            return "Ubicazione amministratore"
        case "foto_ubicazione_altra":
            if additionalText.isEmpty {
                return "Altra ubicazione"
            } else {
                return "Ubicazione: \(additionalText)"
            }
        case "foto_bene":
            if additionalText.isEmpty {
                return "Bene oggetto del sinistro"
            } else {
                return "Bene oggetto del sinistro: \(additionalText)"
            }
        case "foto_componente":
            var caption = additionalText.isEmpty ? "Componente" : additionalText
            if let bene = beneRiferimento, !bene.isEmpty {
                caption += ", facente parte di \(bene)"
            }
            return caption
        case "foto_test_funzionale":
            if let bene = beneRiferimento, !bene.isEmpty {
                return "Test funzionale su \(bene)"
            }
            return "Test funzionale"
        case "test_strumentale":
            if let bene = beneRiferimento, !bene.isEmpty {
                return "Test strumentale su \(bene)"
            }
            return "Test strumentale"
        case "foto_ripristino":
            var caption = additionalText.isEmpty ? "Ripristino" : "Ripristino: \(additionalText)"
            if let bene = beneRiferimento, !bene.isEmpty {
                caption += " su \(bene)"
            }
            return caption
        default:
            return additionalText
        }
    }
    
    // MARK: - Generazione PDF Foto
    
    /// Dimensione massima del PDF in bytes (10 MB)
    private let maxPDFSize: Int = 10 * 1024 * 1024
    
    /// Dimensione target per le immagini nel PDF (larghezza in pixel)
    /// Usato per pre-processing delle immagini
    private let targetImageWidth: CGFloat = 2000
    
    /// Fattore di scala per la rasterizzazione delle immagini nel PDF
    /// Scala 4x = alta qualità (partenza), scala 1x = bassa qualità (fallback)
    private let maxImageScaleFactor: CGFloat = 4.0
    private let minImageScaleFactor: CGFloat = 1.5
    
    /// Qualità JPEG per la compressione delle immagini (0.0 - 1.0)
    private let maxJpegQuality: CGFloat = 0.85
    private let minJpegQuality: CGFloat = 0.5
    
    private func generatePhotoPDF(
        photos: [PhotoItem],
        riferimento: String,
        compagnia: Compagnia,
        outputPath: String
    ) -> URL? {
        // Genera con qualità adattiva per stare nei 10 MB
        return generatePhotoPDFWithAdaptiveQuality(
            photos: photos,
            riferimento: riferimento,
            compagnia: compagnia,
            outputPath: outputPath,
            scaleFactor: maxImageScaleFactor,
            jpegQuality: maxJpegQuality
        )
    }
    
    /// Genera PDF con qualità adattiva, riducendo scala/qualità se supera i 10 MB
    private func generatePhotoPDFWithAdaptiveQuality(
        photos: [PhotoItem],
        riferimento: String,
        compagnia: Compagnia,
        outputPath: String,
        scaleFactor: CGFloat,
        jpegQuality: CGFloat
    ) -> URL? {
        // A4 VERTICALE: 595 x 842 punti
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 30
        let titleHeight: CGFloat = 40
        let captionHeight: CGFloat = 20
        let spacing: CGFloat = 8
        
        // 2 colonne x 4 righe = 8 foto per pagina (layout verticale)
        let columns = 2
        let rows = 4
        
        let availableWidth = pageRect.width - (margin * 2) - (spacing * CGFloat(columns - 1))
        let availableHeight = pageRect.height - (margin * 2) - titleHeight - (spacing * CGFloat(rows - 1)) - (captionHeight * CGFloat(rows))
        
        let photoWidth = availableWidth / CGFloat(columns)
        let photoHeight = availableHeight / CGFloat(rows)
        
        // Aspect ratio 16:9
        let targetAspect: CGFloat = 16.0 / 9.0
        let actualPhotoHeight = min(photoHeight, photoWidth / targetAspect)
        let actualPhotoWidth = actualPhotoHeight * targetAspect
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        
        let photosPerPage = columns * rows
        let totalPages = (photos.count + photosPerPage - 1) / photosPerPage
        
        print("[ClosureFiles] 📸 Generazione PDF foto: \(photos.count) foto su \(totalPages) pagine (scala: \(scaleFactor)x, JPEG: \(Int(jpegQuality * 100))%)")
        
        for pageIndex in 0..<totalPages {
            context.beginPDFPage(nil)
            
            let isFirstPage = pageIndex == 0
            let currentTitleHeight = isFirstPage ? titleHeight : 0
            let currentAvailableHeight = pageRect.height - (margin * 2) - currentTitleHeight - (spacing * CGFloat(rows - 1)) - (captionHeight * CGFloat(rows))
            let currentPhotoHeight = currentAvailableHeight / CGFloat(rows)
            let currentActualPhotoHeight = min(currentPhotoHeight, photoWidth / targetAspect)
            let currentActualPhotoWidth = currentActualPhotoHeight * targetAspect
            
            // Titolo solo nella prima pagina
            if isFirstPage {
                let title = "Documentazione Fotografica del Sinistro \(riferimento)"
                drawText(title, at: CGPoint(x: margin, y: pageRect.height - margin - 15), 
                        font: .boldSystemFont(ofSize: 14), context: context, maxWidth: pageRect.width - margin * 2)
                
                // Linea sotto titolo
                context.setStrokeColor(NSColor.separatorColor.cgColor)
                context.setLineWidth(0.5)
                context.move(to: CGPoint(x: margin, y: pageRect.height - margin - titleHeight + 5))
                context.addLine(to: CGPoint(x: pageRect.width - margin, y: pageRect.height - margin - titleHeight + 5))
                context.strokePath()
            }
            
            // Foto
            let startIndex = pageIndex * photosPerPage
            let endIndex = min(startIndex + photosPerPage, photos.count)
            
            for i in startIndex..<endIndex {
                let localIndex = i - startIndex
                let col = localIndex % columns
                let row = localIndex / columns
                
                let x = margin + CGFloat(col) * (photoWidth + spacing) + (photoWidth - currentActualPhotoWidth) / 2
                let y = pageRect.height - margin - currentTitleHeight - CGFloat(row + 1) * (currentActualPhotoHeight + captionHeight + spacing)
                
                let photoRect = CGRect(x: x, y: y + captionHeight, width: currentActualPhotoWidth, height: currentActualPhotoHeight)
                
                // Disegna foto con scala e compressione JPEG
                let photoItem = photos[i]
                if let image = loadPhotoImageCompressed(for: photoItem, targetWidth: targetImageWidth, targetAspect: targetAspect) {
                    drawImageWithQuality(image, in: photoRect, context: context, scaleFactor: scaleFactor, jpegQuality: jpegQuality)
                } else {
                    // Placeholder se immagine non caricabile
                    context.setFillColor(NSColor.lightGray.cgColor)
                    context.fill(photoRect)
                    print("[ClosureFiles] ⚠️ Immagine non caricabile: \(photoItem.url.lastPathComponent)")
                }
                
                // Didascalia
                drawText(photoItem.caption, at: CGPoint(x: x, y: y), 
                        font: .systemFont(ofSize: 8), context: context, maxWidth: currentActualPhotoWidth)
            }
            
            // Numero pagina
            let pageText = "Pagina \(pageIndex + 1) di \(totalPages)"
            drawText(pageText, at: CGPoint(x: pageRect.width - margin - 80, y: margin / 2),
                    font: .systemFont(ofSize: 8), context: context, maxWidth: 80)
            
            context.endPDFPage()
        }
        
        context.closePDF()
        
        // Salva file
        let nomeFile = compagniaService.generaNomeFile(
            compagnia: compagnia,
            riferimento: riferimento,
            tipoFile: .foto
        )
        let outputURL = URL(fileURLWithPath: outputPath).appendingPathComponent("\(nomeFile).pdf")
        
        // Usa security-scoped access per scrivere il file
        return fileService.performWithSecurityScopedAccess(to: outputPath) {
            do {
                try pdfData.write(to: outputURL, options: .atomic)
                
                // Verifica dimensione
                let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
                let fileSizeMB = Double(fileSize) / 1024.0 / 1024.0
                print("[ClosureFiles] ✅ PDF foto generato: \(String(format: "%.2f", fileSizeMB)) MB")
                
                if fileSize > maxPDFSize {
                    // PDF troppo grande, rigenera con qualità ridotta
                    let newScaleFactor = max(minImageScaleFactor, scaleFactor - 0.5)
                    let newJpegQuality = max(minJpegQuality, jpegQuality - 0.1)
                    
                    if newScaleFactor >= minImageScaleFactor || newJpegQuality >= minJpegQuality {
                        print("[ClosureFiles] ⚠️ PDF troppo grande (\(String(format: "%.2f", fileSizeMB)) MB), rigenerazione con scala \(newScaleFactor)x e JPEG \(Int(newJpegQuality * 100))%...")
                        
                        // Elimina il file troppo grande
                        try? FileManager.default.removeItem(at: outputURL)
                        
                        // Rigenera con qualità ridotta (ricorsivo)
                        return generatePhotoPDFWithAdaptiveQuality(
                            photos: photos,
                            riferimento: riferimento,
                            compagnia: compagnia,
                            outputPath: outputPath,
                            scaleFactor: newScaleFactor,
                            jpegQuality: newJpegQuality
                        )
                    } else {
                        print("[ClosureFiles] ⚠️ PDF ancora troppo grande anche con qualità minima, mantenuto comunque")
                    }
                }
                
                return outputURL
            } catch {
                print("[ClosureFiles] ❌ Errore scrittura PDF foto: \(error)")
                return nil
            }
        } ?? nil
    }
    
    /// Ricomprime un PDF se supera la dimensione massima
    private func recompressPDF(at url: URL) -> URL? {
        guard let pdfDoc = PDFDocument(url: url) else { return url }
        
        // Crea nuovo PDF con immagini più compresse
        let outputURL = url
        
        // Per ora restituisce il file originale - la compressione è già applicata
        // In futuro si può implementare una ricompressione più aggressiva
        return pdfDoc.write(to: outputURL) ? outputURL : nil
    }
    
    /// Carica un'immagine da un PhotoItem compressa per ridurre dimensione PDF
    private func loadPhotoImageCompressed(for item: PhotoItem, targetWidth: CGFloat, targetAspect: CGFloat) -> NSImage? {
        if item.isPDFPage, let pageIndex = item.pdfPageIndex {
            // Estrai immagine da pagina PDF (già ridimensionata)
            return extractImageFromPDFPageCompressed(at: item.url, pageIndex: pageIndex, targetWidth: targetWidth, targetAspect: targetAspect)
        } else {
            // Carica immagine normale compressa
            return loadAndCompressImage(at: item.url, targetWidth: targetWidth, targetAspect: targetAspect)
        }
    }
    
    /// Estrae un'immagine da una specifica pagina di un PDF (ridimensionata)
    private func extractImageFromPDFPageCompressed(at url: URL, pageIndex: Int, targetWidth: CGFloat, targetAspect: CGFloat) -> NSImage? {
        // Prova prima senza security-scoped access
        if let document = PDFDocument(url: url), let page = document.page(at: pageIndex) {
            return extractImageFromPDFPage(page: page, targetWidth: targetWidth, targetAspect: targetAspect)
        }
        
        // Fallback: prova con security-scoped access
        let filePath = url.deletingLastPathComponent().path
        let result: NSImage? = fileService.performWithSecurityScopedAccess(to: filePath) {
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else {
                return nil
            }
            return extractImageFromPDFPage(page: page, targetWidth: targetWidth, targetAspect: targetAspect)
        } ?? nil
        return result
    }
    
    /// Helper per estrarre immagine da pagina PDF
    private func extractImageFromPDFPage(page: PDFPage, targetWidth: CGFloat, targetAspect: CGFloat) -> NSImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Calcola scala per ottenere la larghezza target
        let targetHeight = targetWidth / targetAspect
        let scaleX = targetWidth / pageBounds.width
        let scaleY = targetHeight / pageBounds.height
        let scale = max(scaleX, scaleY) // Prendi la scala maggiore per coprire l'area
        
        let scaledWidth = pageBounds.width * scale
        let scaledHeight = pageBounds.height * scale
        
        // Crea immagine dalla pagina PDF
        let image = NSImage(size: CGSize(width: scaledWidth, height: scaledHeight))
        image.lockFocus()
        
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: CGSize(width: scaledWidth, height: scaledHeight)))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        
        image.unlockFocus()
        
        // Croppa all'aspect ratio e ridimensiona
        return cropAndResizeImage(image, targetWidth: targetWidth, targetAspect: targetAspect)
    }
    
    /// Carica, comprimi e croppa un'immagine
    private func loadAndCompressImage(at url: URL, targetWidth: CGFloat, targetAspect: CGFloat) -> NSImage? {
        // Prova prima senza security-scoped access (per file già accessibili)
        if let image = NSImage(contentsOf: url) {
            return cropAndResizeImage(image, targetWidth: targetWidth, targetAspect: targetAspect)
        }
        
        // Prova a caricare i dati direttamente
        if let data = try? Data(contentsOf: url), let imageFromData = NSImage(data: data) {
            return cropAndResizeImage(imageFromData, targetWidth: targetWidth, targetAspect: targetAspect)
        }
        
        // Fallback: prova con security-scoped access se necessario
        let filePath = url.deletingLastPathComponent().path
        let result: NSImage? = fileService.performWithSecurityScopedAccess(to: filePath) {
            if let image = NSImage(contentsOf: url) {
                return cropAndResizeImage(image, targetWidth: targetWidth, targetAspect: targetAspect)
            }
            if let data = try? Data(contentsOf: url), let imageFromData = NSImage(data: data) {
                return cropAndResizeImage(imageFromData, targetWidth: targetWidth, targetAspect: targetAspect)
            }
            print("[ClosureFiles] ⚠️ Impossibile caricare immagine: \(url.lastPathComponent)")
            return nil
        } ?? nil
        return result
    }
    
    
    /// Croppa e ridimensiona un'immagine per ottimizzare la dimensione
    /// Usa NSImage.draw per preservare l'orientamento EXIF
    private func cropAndResizeImage(_ image: NSImage, targetWidth: CGFloat, targetAspect: CGFloat) -> NSImage {
        let originalSize = image.size
        let originalAspect = originalSize.width / originalSize.height
        
        // Calcola il crop rect centrato
        var cropRect: CGRect
        if originalAspect > targetAspect {
            // L'immagine è più larga del target - croppa sui lati
            let newWidth = originalSize.height * targetAspect
            let xOffset = (originalSize.width - newWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: originalSize.height)
        } else {
            // L'immagine è più alta del target - croppa sopra/sotto
            let newHeight = originalSize.width / targetAspect
            let yOffset = (originalSize.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: originalSize.width, height: newHeight)
        }
        
        // Calcola dimensione finale
        let targetHeight = targetWidth / targetAspect
        let finalSize = CGSize(width: targetWidth, height: targetHeight)
        
        // Crea nuova immagine usando NSImage.draw che rispetta l'orientamento EXIF
        let finalImage = NSImage(size: finalSize)
        finalImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Disegna l'immagine croppata e ridimensionata
        // from: specifica quale parte dell'immagine sorgente disegnare
        // in: specifica dove disegnarla nell'immagine di destinazione
        image.draw(in: NSRect(origin: .zero, size: finalSize),
                  from: cropRect,
                  operation: .copy,
                  fraction: 1.0,
                  respectFlipped: true,
                  hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        
        finalImage.unlockFocus()
        
        return finalImage
    }
    
    private func drawImage(_ image: NSImage, in rect: CGRect, context: CGContext) {
        // Usa la versione con qualità di default
        drawImageWithQuality(image, in: rect, context: context, scaleFactor: maxImageScaleFactor, jpegQuality: maxJpegQuality)
    }
    
    /// Disegna un'immagine nel PDF con scala e compressione JPEG configurabili
    /// - scaleFactor: moltiplicatore per la risoluzione di rendering (es. 4.0 = 4x la dimensione del rect)
    /// - jpegQuality: qualità JPEG 0.0-1.0 per la compressione
    private func drawImageWithQuality(_ image: NSImage, in rect: CGRect, context: CGContext, scaleFactor: CGFloat, jpegQuality: CGFloat) {
        // Rasterizza ad alta risoluzione (scala moltiplicata)
        let scaledWidth = rect.width * scaleFactor
        let scaledHeight = rect.height * scaleFactor
        let scaledSize = CGSize(width: scaledWidth, height: scaledHeight)
        
        // Crea un bitmap context per rasterizzare l'immagine ad alta risoluzione
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapContext = CGContext(
            data: nil,
            width: Int(scaledWidth),
            height: Int(scaledHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("[ClosureFiles] ⚠️ Impossibile creare bitmap context")
            return
        }
        
        // Disegna l'NSImage nel bitmap context usando NSGraphicsContext
        // Questo rispetta l'orientamento EXIF
        let nsContext = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        
        // Alta qualità di interpolazione
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Disegna l'immagine nel bitmap ad alta risoluzione
        image.draw(
            in: NSRect(origin: .zero, size: scaledSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Ottieni il CGImage rasterizzato ad alta risoluzione
        guard let hiResCGImage = bitmapContext.makeImage() else {
            print("[ClosureFiles] ⚠️ Impossibile creare CGImage da bitmap")
            return
        }
        
        // Comprimi in JPEG per ridurre dimensione del PDF
        guard let jpegData = compressToJPEG(cgImage: hiResCGImage, quality: jpegQuality),
              let jpegImage = CGImage(
                jpegDataProviderSource: CGDataProvider(data: jpegData as CFData)!,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            // Fallback: usa l'immagine non compressa
            context.draw(hiResCGImage, in: rect)
            return
        }
        
        // Disegna l'immagine JPEG compressa nel PDF
        context.draw(jpegImage, in: rect)
    }
    
    /// Comprime un CGImage in dati JPEG
    private func compressToJPEG(cgImage: CGImage, quality: CGFloat) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
    
    private func drawCGImage(_ cgImage: CGImage, in rect: CGRect, context: CGContext) {
        // Per CGImage diretti, disegna senza trasformazioni
        // (il CGImage è già nell'orientamento corretto)
        context.draw(cgImage, in: rect)
    }
    
    private func drawText(_ text: String, at point: CGPoint, font: NSFont, context: CGContext, maxWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), 
                                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        let drawRect = CGRect(x: point.x, y: point.y, width: maxWidth, height: bounding.height)
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // MARK: - Conversione altri file in PDF
    
    private func convertToPDF(fileURL: URL, outputURL: URL, includeAnnotations: Bool = false) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        let outputPath = outputURL.deletingLastPathComponent().path
        
        // Se è già PDF, clona e applica firma/annotazioni se presenti
        if ext == "pdf" {
            let success = fileService.performWithSecurityScopedAccess(to: outputPath) {
                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    // Clona il file (copyItem preserva l'originale)
                    try FileManager.default.copyItem(at: fileURL, to: outputURL)
                    return true
                } catch {
                    print("[ClosureFiles] ❌ Errore clonazione PDF: \(error)")
                    return false
                }
            } ?? false
            
            if success {
                // Applica annotazioni se richiesto
                if includeAnnotations {
                    Task { @MainActor in
                        applyAnnotationsToClosureFile(fileURL: fileURL, outputURL: outputURL)
                    }
                }
                
                // Applica firma se presente (asincrono per file finali)
                applySignatureToClosureFile(fileURL: fileURL, outputURL: outputURL)
            }
            
            return success
        }
        
        // Immagini -> PDF
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            let success = convertImageToPDF(imageURL: fileURL, outputURL: outputURL)
            // Applica firma se presente (asincrono per file finali)
            if success {
                applySignatureToClosureFile(fileURL: fileURL, outputURL: outputURL)
            }
            return success
        }
        
        // Altri formati: usa sistema di print/preview
        let success = convertDocumentToPDF(documentURL: fileURL, outputURL: outputURL)
        // Applica firma se presente (asincrono per file finali)
        if success {
            applySignatureToClosureFile(fileURL: fileURL, outputURL: outputURL)
        }
        return success
    }
    
    /// Converte un file in PDF senza applicare la firma (per file temporanei)
    private func convertToPDFWithoutSignature(fileURL: URL, outputURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        let outputPath = outputURL.deletingLastPathComponent().path
        
        // Se è già PDF, clona senza applicare firma
        if ext == "pdf" {
            return fileService.performWithSecurityScopedAccess(to: outputPath) {
                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    // Clona il file (copyItem preserva l'originale)
                    try FileManager.default.copyItem(at: fileURL, to: outputURL)
                    return true
                } catch {
                    print("[ClosureFiles] ❌ Errore clonazione PDF: \(error)")
                    return false
                }
            } ?? false
        }
        
        // Immagini -> PDF
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            return convertImageToPDF(imageURL: fileURL, outputURL: outputURL)
        }
        
        // Altri formati: usa sistema di print/preview
        return convertDocumentToPDF(documentURL: fileURL, outputURL: outputURL)
    }
    
    /// Applica le annotazioni al file di chiusura (stampa permanente)
    @MainActor
    private func applyAnnotationsToClosureFile(fileURL: URL, outputURL: URL) {
        let annotationService = PDFAnnotationService.shared
        
        guard annotationService.hasAnnotations(for: fileURL.path) else {
            return
        }
        
        guard let originalDocument = PDFDocument(url: outputURL) else {
            print("[ClosureFiles] ⚠️ Impossibile caricare PDF per applicare annotazioni: \(outputURL.lastPathComponent)")
            return
        }
        
        guard let annotatedDocument = annotationService.applyAnnotationsToPDF(
            originalDocument,
            filePath: fileURL.path,
            includeAnnotations: true
        ) else {
            print("[ClosureFiles] ⚠️ Errore applicazione annotazioni a: \(outputURL.lastPathComponent)")
            return
        }
        
        // Salva il documento con annotazioni
        let success = annotatedDocument.write(to: outputURL)
        if success {
            print("[ClosureFiles] ✅ Annotazioni applicate al file di chiusura: \(outputURL.lastPathComponent)")
        } else {
            print("[ClosureFiles] ❌ Errore salvataggio PDF con annotazioni: \(outputURL.lastPathComponent)")
        }
    }
    
    /// Applica la firma salvata al file di chiusura (stampa permanente) - versione asincrona
    private func applySignatureToClosureFile(fileURL: URL, outputURL: URL) {
        Task { @MainActor in
            applySignatureToClosureFileSync(fileURL: fileURL, outputURL: outputURL)
        }
    }
    
    /// Applica la firma salvata al file di chiusura (stampa permanente) - versione sincrona
    @MainActor
    private func applySignatureToClosureFileSync(fileURL: URL, outputURL: URL) {
        // Cerca posizione firma per il file originale
        guard let originalPlacement = placementService.getPlacement(for: fileURL.path) else {
            return
        }
        
        // Ottieni l'immagine della firma
        let signatureImage: NSImage?
        if originalPlacement.signatureType == "individual" {
            signatureImage = signatureService.individualSignature
        } else {
            signatureImage = signatureService.studioSignature
        }
        
        guard let signature = signatureImage else {
            print("[ClosureFiles] ⚠️ Firma non trovata per tipo: \(originalPlacement.signatureType)")
            return
        }
        
        // Crea un placement temporaneo per il file di output (necessario per printAnnotationsToPDF)
        // Converti l'immagine in PNG data per la stampa
        let signatureImageData: Data?
        if let tiffData = signature.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            signatureImageData = pngData
            print("[ClosureFiles] ✅ Dati immagine firma creati: \(pngData.count) bytes")
        } else {
            signatureImageData = nil
            print("[ClosureFiles] ⚠️ Impossibile convertire immagine firma in PNG")
        }
        
        // Usa i dati appena creati, oppure quelli salvati nell'originale
        let finalSignatureData = signatureImageData ?? originalPlacement.signatureImageData
        print("[ClosureFiles] 📋 Dati firma finali: \(finalSignatureData != nil ? "\(finalSignatureData!.count) bytes" : "NESSUNO")")
        
        let tempPlacement = SignaturePlacementService.SignaturePlacement(
            filePath: outputURL.path,
            signatureType: originalPlacement.signatureType,
            position: originalPlacement.position,
            size: originalPlacement.size,
            pageIndex: originalPlacement.pageIndex,
            signatureImageData: finalSignatureData
        )
        
        // Salva temporaneamente il placement per il file di output
        placementService.setPlacement(tempPlacement)
        print("[ClosureFiles] 💾 Placement temporaneo salvato per: \(outputURL.path)")
        defer {
            // Rimuovi il placement temporaneo dopo l'uso (ma mantieni quello originale)
            if fileURL.path != outputURL.path {
                placementService.removePlacement(for: outputURL.path)
            }
        }
        
        // Applica la firma al file di chiusura
        let ext = outputURL.pathExtension.lowercased()
        if ext == "pdf" {
            // Per PDF, prima aggiungi come annotazione, poi stampa permanentemente
            let pageIndex = originalPlacement.pageIndex ?? 0
            print("[ClosureFiles] 📝 Applico firma a pagina \(pageIndex + 1) di \(outputURL.lastPathComponent)")
            
            let added = editorService.addSignatureToPDF(
                at: outputURL,
                pageIndex: pageIndex,
                signature: signature,
                position: originalPlacement.position,
                size: originalPlacement.size,
                createVersion: false, // Non creare versione per file di chiusura
                asAnnotation: true
            )
            
            if added {
                print("[ClosureFiles] ✅ Annotazione firma aggiunta, ora stampo permanentemente...")
                // Verifica che le annotazioni siano presenti prima di stampare
                if let doc = PDFDocument(url: outputURL) {
                    let annotations = doc.page(at: pageIndex)?.annotations.filter { $0.userName == "PerX_Signature" } ?? []
                    print("[ClosureFiles] 📋 Trovate \(annotations.count) annotazioni firma prima della stampa")
                }
                
                // Stampa permanentemente le annotazioni (ora trova il placement per outputURL.path)
                let printed = editorService.printAnnotationsToPDF(at: outputURL, pageIndex: pageIndex)
                if printed {
                    print("[ClosureFiles] ✅ Firma stampata permanentemente nel PDF")
                } else {
                    print("[ClosureFiles] ⚠️ Errore stampa permanente della firma")
                }
            } else {
                print("[ClosureFiles] ⚠️ Errore aggiunta annotazione firma")
            }
        } else {
            // Per immagini, applica direttamente (già permanente)
            _ = editorService.addSignatureToImage(
                at: outputURL,
                signature: signature,
                position: originalPlacement.position,
                size: originalPlacement.size,
                createVersion: false // Non creare versione per file di chiusura
            )
        }
        
        print("[ClosureFiles] ✅ Firma applicata al file di chiusura: \(outputURL.lastPathComponent)")
    }
    
    private func convertImageToPDF(imageURL: URL, outputURL: URL) -> Bool {
        // Prova prima senza security-scoped access
        var image: NSImage? = NSImage(contentsOf: imageURL)
        
        // Fallback: prova con security-scoped access
        if image == nil {
            image = fileService.performWithSecurityScopedAccess(to: imageURL.deletingLastPathComponent().path) {
                NSImage(contentsOf: imageURL)
            } ?? nil
        }
        
        // Fallback: prova a caricare tramite Data
        if image == nil {
            if let data = try? Data(contentsOf: imageURL) {
                image = NSImage(data: data)
            }
        }
        
        guard let loadedImage = image else {
            print("[ClosureFiles] ⚠️ Impossibile caricare immagine per conversione: \(imageURL.lastPathComponent)")
            return false
        }
        
        // Usa le dimensioni originali dell'immagine come dimensioni della pagina PDF
        // Converti da punti (72 DPI) mantenendo le dimensioni pixel
        let imageSize = loadedImage.size
        let pageRect = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return false }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }
        
        context.beginPDFPage(nil)
        
        // Disegna l'immagine a dimensione piena senza margini
        let imageRect = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        drawImage(loadedImage, in: imageRect, context: context)
        
        context.endPDFPage()
        context.closePDF()
        
        let outputPath = outputURL.deletingLastPathComponent().path
        return fileService.performWithSecurityScopedAccess(to: outputPath) {
            do {
                try pdfData.write(to: outputURL, options: .atomic)
                return true
            } catch {
                return false
            }
        } ?? false
    }
    
    private func convertDocumentToPDF(documentURL: URL, outputURL: URL) -> Bool {
        // Usa NSWorkspace per stampare in PDF
        // Clona il file originale nella cartella di destinazione
        let outputPath = outputURL.deletingLastPathComponent().path
        
        return fileService.performWithSecurityScopedAccess(to: outputPath) {
            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                // Clona il file originale (preservando l'originale col tag dov'è)
                try FileManager.default.copyItem(at: documentURL, to: outputURL)
                return true
            } catch {
                print("[ClosureFiles] ❌ Errore clonazione documento: \(error)")
                return false
            }
        } ?? false
    }
    
    // MARK: - Mapping Tag -> TipoFile
    
    /// Determina se la fulminazione deve essere inclusa basandosi sulla compagnia
    /// Unipol: sempre inclusa | Altre compagnie: solo se positiva
    private func shouldIncludeFulminazione(forFile path: String, compagnia: Compagnia) async -> Bool {
        // Unipol allega sempre la fulminazione
        if compagnia == .unipolItalia {
            return true
        }
        
        // Altre compagnie: allega solo se positiva
        let sottotipo = await fileTagManager.getFulminazioneSottotipo(forFile: path, tagId: "fulminazione")
        return sottotipo?.lowercased() == "positiva"
    }
    
    
    /// Carica un file come PDFDocument (convertendo se necessario)
    private func loadAsPDF(url: URL) -> PDFDocument? {
        let ext = url.pathExtension.lowercased()
        
        // Se è già un PDF
        if ext == "pdf" {
            // Prova prima direttamente
            if let doc = PDFDocument(url: url) {
                return doc
            }
            // Fallback con security-scoped access
            let result: PDFDocument? = fileService.performWithSecurityScopedAccess(to: url.deletingLastPathComponent().path) {
                PDFDocument(url: url)
            } ?? nil
            return result
        }
        
        // Se è un'immagine, converti in PDF
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            // Prova a caricare l'immagine con vari metodi
            var image: NSImage? = NSImage(contentsOf: url)
            
            if image == nil {
                image = fileService.performWithSecurityScopedAccess(to: url.deletingLastPathComponent().path) {
                    NSImage(contentsOf: url)
                } ?? nil
            }
            
            if image == nil, let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
            
            guard let loadedImage = image else {
                print("[ClosureFiles] ⚠️ Impossibile caricare immagine: \(url.lastPathComponent)")
                return nil
            }
            
            let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
            var mediaBox = pageRect
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
            
            context.beginPDFPage(nil)
            
            let margin: CGFloat = 40
            let maxWidth = pageRect.width - margin * 2
            let maxHeight = pageRect.height - margin * 2
            
            let imageSize = loadedImage.size
            let scaleX = maxWidth / imageSize.width
            let scaleY = maxHeight / imageSize.height
            let scale = min(scaleX, scaleY, 1.0)
            
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            let x = (pageRect.width - scaledWidth) / 2
            let y = (pageRect.height - scaledHeight) / 2
            
            let imageRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
            drawImage(loadedImage, in: imageRect, context: context)
            
            context.endPDFPage()
            context.closePDF()
            
            return PDFDocument(data: pdfData as Data)
        }
        
        // Altri formati non supportati direttamente
        return nil
    }
    
    private func mapTagToTipoFile(_ tagId: String) -> TipoFileCompagnia {
        switch tagId {
        case "perizia": return .perizia
        case "fulminazione": return .fulminazione
        case "verbale": return .verbale
        case "atto", "atto_da_firmare", "atto_firmato": return .atto
        case "fattura", "preventivo": return .giustificativi
        default: return .altro
        }
    }
    
    /// Determina il sottotipo giustificativo dal tag
    private func determineSottotipoGiustificativo(tagId: String) -> SottotipoGiustificativo? {
        switch tagId {
        case "fattura": return .fattura
        case "preventivo": return .preventivo
        default: return nil
        }
    }
    
    /// Mappa un tag originale al tag di chiusura generato
    private func mapTagToClosureTag(_ tagId: String) -> String {
        switch tagId {
        case "perizia": return "file_perizia"
        case "fulminazione": return "file_fulminazione"
        case "verbale": return "file_verbale"
        case "fattura", "preventivo": return "file_giustificativi"
        case "atto_da_firmare", "atto_firmato": return "file_atto"
        case "accettazione": return "file_altro" // Accettazione -> Altro file di chiusura
        case "denuncia": return "file_altro" // Denuncia -> Altro file di chiusura
        case "dichiarazione": return "file_altro" // Dichiarazione -> Altro file di chiusura
        case "report_cat": return "file_altro" // Report CAT -> Altro file di chiusura
        default: return "file_altro" // fallback per tutti gli altri tag
        }
    }
    
    /// Struttura per allegato con sottotipo
    private struct AllegatoAtto {
        let url: URL
        let sottotipo: String?
        
        /// Ordine di ordinamento: IBAN=0 (subito dopo atto), accettazione=1, delega=2, documenti=3, altri=999
        var sortOrder: Int {
            guard let sottotipo = sottotipo?.lowercased() else { return 999 }
            switch sottotipo {
            case "iban": return 0  // IBAN subito dopo l'atto (prima pagina degli allegati)
            case "accettazione": return 1
            case "delega": return 2
            case "documenti": return 3
            default: return 999
            }
        }
    }
    
    /// Raccoglie i file con tag "allegati_atto" da allegare all'atto, ordinati per sottotipo
    private func collectAllegatiAtto(inPath sinistroPath: String) async -> [URL] {
        let allFiles = fileService.listFilesRecursive(inDirectory: sinistroPath)
        var allegati: [AllegatoAtto] = []
        
        for fileURL in allFiles {
            let path = fileURL.path
            
            // Salta la cartella "Da Chiudere"
            if path.contains("/Da Chiudere/") {
                continue
            }
            
            let tags = await fileTagManager.getTagsForFile(at: path)
            
            // Verifica se ha il tag "allegati_atto" con "da allegare in chiusura"
            if tags.contains(where: { $0.id == "allegati_atto" }),
               await fileTagManager.getDaAllegareInChiusura(forFile: path, tagId: "allegati_atto") {
                let sottotipo = await fileTagManager.getAllegatiAttoSottotipo(forFile: path, tagId: "allegati_atto")
                allegati.append(AllegatoAtto(url: fileURL, sottotipo: sottotipo))
            }
        }
        
        // Ordina: accettazione, IBAN, delega, documenti, altri
        let sorted = allegati.sorted { $0.sortOrder < $1.sortOrder }
        return sorted.map { $0.url }
    }
    
    /// Genera il PDF dell'atto unendo l'atto principale con gli allegati (senza margini)
    @MainActor
    private func generateAttoPDFWithAllegati(attoFile: URL, allegati: [URL], outputURL: URL) async -> Bool {
        // Verifica che outputURL abbia il nome corretto (non temporaneo)
        let expectedFileName = outputURL.lastPathComponent
        if expectedFileName.hasPrefix("temp_") {
            print("[ClosureFiles] ⚠️ ERRORE: outputURL ha nome temporaneo: \(expectedFileName)")
            return false
        }
        
        print("[ClosureFiles] 📄 Generazione PDF atto con nome finale: \(expectedFileName)")
        
        // Crea un PDF temporaneo per l'atto principale (in una directory temporanea per evitare conflitti)
        let tempDir = FileManager.default.temporaryDirectory
        let tempAttoURL = tempDir.appendingPathComponent("temp_atto_\(UUID().uuidString).pdf")
        
        // Converti l'atto in PDF senza applicare la firma (la applicheremo dopo)
        guard convertToPDFWithoutSignature(fileURL: attoFile, outputURL: tempAttoURL) else {
            print("[ClosureFiles] ❌ Errore conversione atto principale")
            return false
        }
        
        // Applica la firma al file temporaneo in modo sincrono
        applySignatureToClosureFileSync(fileURL: attoFile, outputURL: tempAttoURL)
        
        // Ricarica il PDF dopo l'applicazione della firma per assicurarsi che sia salvato
        // Attendi un momento per assicurarsi che il file sia stato scritto
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 secondi
        
        guard let attoPDF = PDFDocument(url: tempAttoURL) else {
            print("[ClosureFiles] ❌ Errore caricamento PDF atto principale dopo firma")
            try? FileManager.default.removeItem(at: tempAttoURL)
            return false
        }
        
        // Verifica che la firma sia stata applicata
        var hasSignature = false
        for i in 0..<attoPDF.pageCount {
            if let page = attoPDF.page(at: i) {
                let annotations = page.annotations.filter { $0.userName == "PerX_Signature" }
                if !annotations.isEmpty {
                    hasSignature = true
                    print("[ClosureFiles] ✅ Firma trovata nella pagina \(i + 1) del file temporaneo")
                    break
                }
            }
        }
        
        if !hasSignature {
            print("[ClosureFiles] ⚠️ Nessuna annotazione firma trovata nel file temporaneo")
        }
        
        // Crea il PDF finale unendo atto e allegati usando CGContext per preservare la firma
        let mergedPDFData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mergedPDFData as CFMutableData) else {
            print("[ClosureFiles] ❌ Errore creazione consumer per PDF finale")
            try? FileManager.default.removeItem(at: tempAttoURL)
            return false
        }
        
        // Crea il context una sola volta usando la prima pagina per determinare le dimensioni
        guard let firstPage = attoPDF.page(at: 0) else {
            print("[ClosureFiles] ❌ Errore: PDF atto vuoto")
            try? FileManager.default.removeItem(at: tempAttoURL)
            return false
        }
        
        let firstPageBounds = firstPage.bounds(for: .mediaBox)
        var mediaBox = firstPageBounds
        
        guard let mergedContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            print("[ClosureFiles] ❌ Errore creazione context per PDF finale")
            try? FileManager.default.removeItem(at: tempAttoURL)
            return false
        }
        
        // Aggiungi tutte le pagine dell'atto principale disegnandole direttamente (inclusa la firma stampata)
        for i in 0..<attoPDF.pageCount {
            guard let page = attoPDF.page(at: i) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            var pageMediaBox = pageBounds
            
            mergedContext.beginPDFPage(nil)
            
            // Disegna la pagina originale (inclusa la firma già stampata permanentemente)
            if let pageRef = page.pageRef {
                mergedContext.saveGState()
                mergedContext.drawPDFPage(pageRef)
                mergedContext.restoreGState()
            } else {
                mergedContext.saveGState()
                page.draw(with: .mediaBox, to: mergedContext)
                mergedContext.restoreGState()
            }
            
            mergedContext.endPDFPage()
        }
        
        // Aggiungi gli allegati (senza margini)
        for allegatoURL in allegati {
            // Converti l'allegato in PDF se necessario
            let tempAllegatoURL = outputURL.deletingLastPathComponent().appendingPathComponent("temp_allegato_\(UUID().uuidString).pdf")
            
            guard convertToPDF(fileURL: allegatoURL, outputURL: tempAllegatoURL) else {
                print("[ClosureFiles] ⚠️ Errore conversione allegato: \(allegatoURL.lastPathComponent)")
                continue
            }
            
            guard let allegatoPDF = PDFDocument(url: tempAllegatoURL) else {
                print("[ClosureFiles] ⚠️ Errore caricamento PDF allegato: \(allegatoURL.lastPathComponent)")
                try? FileManager.default.removeItem(at: tempAllegatoURL)
                continue
            }
            
            // Aggiungi tutte le pagine dell'allegato senza margini
            for i in 0..<allegatoPDF.pageCount {
                guard let page = allegatoPDF.page(at: i) else { continue }
                
                mergedContext.beginPDFPage(nil)
                
                // Disegna la pagina dell'allegato
                if let pageRef = page.pageRef {
                    mergedContext.saveGState()
                    mergedContext.drawPDFPage(pageRef)
                    mergedContext.restoreGState()
                } else {
                    mergedContext.saveGState()
                    page.draw(with: .mediaBox, to: mergedContext)
                    mergedContext.restoreGState()
                }
                
                mergedContext.endPDFPage()
            }
            
            // Rimuovi il file temporaneo dell'allegato
            try? FileManager.default.removeItem(at: tempAllegatoURL)
        }
        
        // Chiudi il PDF
        mergedContext.closePDF()
        
        // Salva il PDF finale con il nome corretto
        let outputPath = outputURL.deletingLastPathComponent().path
        
        print("[ClosureFiles] 💾 Salvataggio PDF finale con nome: \(expectedFileName)")
        
        let success = fileService.performWithSecurityScopedAccess(to: outputPath) {
            // Rimuovi eventuale file esistente con lo stesso nome
            if FileManager.default.fileExists(atPath: outputURL.path) {
                do {
                    try FileManager.default.removeItem(at: outputURL)
                    print("[ClosureFiles] 🗑️ Rimosso file esistente: \(expectedFileName)")
                } catch {
                    print("[ClosureFiles] ⚠️ Errore rimozione file esistente: \(error)")
                }
            }
            
            // Salva il PDF finale con il nome corretto
            do {
                try mergedPDFData.write(to: outputURL, options: .atomic)
                
                // Verifica che il file sia stato salvato con il nome corretto
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    let actualFileName = outputURL.lastPathComponent
                    if actualFileName == expectedFileName {
                        print("[ClosureFiles] ✅ PDF atto con \(allegati.count) allegati salvato correttamente: \(actualFileName)")
                        return true
                    } else {
                        print("[ClosureFiles] ⚠️ ERRORE: Nome file non corrisponde! Atteso: \(expectedFileName), Trovato: \(actualFileName)")
                        return false
                    }
                } else {
                    print("[ClosureFiles] ⚠️ File non trovato dopo salvataggio: \(expectedFileName)")
                    return false
                }
            } catch {
                print("[ClosureFiles] ❌ Errore scrittura PDF finale: \(error)")
                return false
            }
        } ?? false
        
        // Rimuovi sempre il file temporaneo dell'atto (anche in caso di errore)
        // Il file temporaneo è nella directory temporanea, quindi non serve security-scoped access
        if FileManager.default.fileExists(atPath: tempAttoURL.path) {
            do {
                try FileManager.default.removeItem(at: tempAttoURL)
                print("[ClosureFiles] 🗑️ File temporaneo rimosso: \(tempAttoURL.lastPathComponent)")
            } catch {
                print("[ClosureFiles] ⚠️ Errore rimozione file temporaneo: \(error)")
            }
        }
        
        // Verifica finale che il file sia stato salvato correttamente
        if success {
            let finalPath = outputURL.path
            let finalFileName = outputURL.lastPathComponent
            if FileManager.default.fileExists(atPath: finalPath) {
                if finalFileName == expectedFileName {
                    print("[ClosureFiles] ✅ Verifica finale: File salvato correttamente con nome: \(finalFileName)")
                } else {
                    print("[ClosureFiles] ⚠️ ERRORE VERIFICA: Nome file non corrisponde! Atteso: \(expectedFileName), Trovato: \(finalFileName)")
                }
            } else {
                print("[ClosureFiles] ⚠️ ERRORE VERIFICA: File finale non trovato: \(finalPath)")
            }
        } else {
            print("[ClosureFiles] ❌ Errore salvataggio PDF atto con allegati")
        }
        
        return success
    }
    
    /// Raccoglie i file già taggati con "file_foto" (da copiare invece di generare PDF)
    private func collectFilesWithFileFotoTag(inPath sinistroPath: String) async -> [PhotoItem] {
        let allFiles = fileService.listFilesRecursive(inDirectory: sinistroPath)
        var items: [PhotoItem] = []
        
        for fileURL in allFiles {
            let path = fileURL.path
            
            // Salta la cartella "Da Chiudere"
            if path.contains("/Da Chiudere/") {
                continue
            }
            
            let tags = await fileTagManager.getTagsForFile(at: path)
            
            // Verifica se ha il tag "file_foto" con "da allegare in chiusura"
            if tags.contains(where: { $0.id == "file_foto" }),
               await fileTagManager.getDaAllegareInChiusura(forFile: path, tagId: "file_foto") {
                items.append(PhotoItem(
                    url: fileURL,
                    tagId: "file_foto",
                    caption: "",
                    additionalText: "",
                    beneRiferimento: nil,
                    sortOrder: 0,
                    pdfPageIndex: nil
                ))
            }
        }
        
        return items
    }
    
    /// Copia un file con security-scoped access (usa il path comune se possibile)
    private func copyFileWithSecurityScopedAccess(from sourceURL: URL, to destinationURL: URL) -> Bool {
        let sourcePath = sourceURL.deletingLastPathComponent().path
        let destinationPath = destinationURL.deletingLastPathComponent().path
        
        // Se sorgente e destinazione sono nella stessa directory, usa quella
        if sourcePath == destinationPath {
            return fileService.performWithSecurityScopedAccess(to: sourcePath) {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    return true
                } catch {
                    print("[ClosureFiles] ❌ Errore copia file: \(error)")
                    return false
                }
            } ?? false
        }
        
        // Altrimenti prova prima con la destinazione (che di solito è nella stessa root)
        return fileService.performWithSecurityScopedAccess(to: destinationPath) {
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                return true
            } catch {
                print("[ClosureFiles] ❌ Errore copia file: \(error)")
                return false
            }
        } ?? false
    }
    
    /// Tagga un file generato nella cartella "Da Chiudere"
    private func tagGeneratedFile(at path: String, tagId: String) async {
        guard let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == tagId }) else {
            print("[ClosureFiles] ⚠️ Tag non trovato in availableTags: \(tagId)")
            print("[ClosureFiles] 📋 Tag disponibili: \(FileTagManager.FileTag.availableTags.map { $0.id })")
            return
        }
        
        // Prima rimuovi tutti i tag esistenti dal file (potrebbero essere stati applicati automaticamente)
        let existingTags = await fileTagManager.getTagsForFile(at: path)
        for existingTag in existingTags {
            await fileTagManager.removeTag(existingTag, fromFile: path)
        }
        
        print("[ClosureFiles] 🏷️ Applico tag '\(tagId)' a: \(URL(fileURLWithPath: path).lastPathComponent)")
        await fileTagManager.addTag(tag, toFile: path, daAllegareInChiusura: false)
        
        // Verifica che il tag sia stato applicato
        let appliedTags = await fileTagManager.getTagsForFile(at: path)
        print("[ClosureFiles] ✅ Tag applicati: \(appliedTags.map { $0.id })")
    }
    
    private func determineSottotipoAtto(filePath: String, sinistro: Sinistro, provided: SottotipoAtto?) async -> SottotipoAtto? {
        // Se fornito esplicitamente, usa quello
        if let provided = provided {
            return provided
        }
        
        // Controlla se nel tag è salvato il sottotipo (cerca nei tag atto)
        let tags = await fileTagManager.getTagsForFile(at: filePath)
        var sottotipoString: String? = nil
        
        // Cerca prima nel tag corrente, poi nell'altro tag atto possibile
        for tag in tags where FileTagManager.FileTag.attoTags.contains(tag.id) {
            if let sottotipo = await fileTagManager.getAttoSottotipo(forFile: filePath, tagId: tag.id) {
                sottotipoString = sottotipo
                break
            }
        }
        
        // Se non trovato nel tag corrente, prova con l'altro tag atto
        if sottotipoString == nil {
            let hasFirmato = tags.contains(where: { $0.id == "atto_firmato" })
            let hasDaFirmare = tags.contains(where: { $0.id == "atto_da_firmare" })
            
            if hasFirmato {
                // Prova con atto_da_firmare
                if let sottotipo = await fileTagManager.getAttoSottotipo(forFile: filePath, tagId: "atto_da_firmare") {
                    sottotipoString = sottotipo
                }
            } else if hasDaFirmare {
                // Prova con atto_firmato
                if let sottotipo = await fileTagManager.getAttoSottotipo(forFile: filePath, tagId: "atto_firmato") {
                    sottotipoString = sottotipo
                }
            }
        }
        
        if let sottotipoString = sottotipoString {
            if sottotipoString == "liquidazione" {
                return .liquidazione
            } else if sottotipoString == "accertamento" {
                return .accertamento
            }
        }
        
        // Fallback: determina dal tipo di chiusura
        return compagniaService.determinaSottotipoAtto(tipoChiusura: sinistro.definizione)
    }
    
    // MARK: - Utility
    
    /// Pulisce la cartella "Da Chiudere" eliminando solo i file con tag di chiusura generati
    private func cleanDaChiudereFolder(daChiuderePath: String, sinistroPath: String) {
        // Prima raccogliamo i file in modo sincrono
        let filePaths: [String] = fileService.performWithSecurityScopedAccess(to: sinistroPath) {
            let fileManager = FileManager.default
            
            guard let contents = try? fileManager.contentsOfDirectory(atPath: daChiuderePath) else {
                return []
            }
            
            return contents
                .filter { !$0.hasPrefix(".") }
                .map { (daChiuderePath as NSString).appendingPathComponent($0) }
        } ?? []
        
        // Poi verifichiamo i tag e eliminiamo in modo async
        Task { @MainActor in
            let fileManager = FileManager.default
            
            for filePath in filePaths {
                let tags = await fileTagManager.getTagsForFile(at: filePath)
                let hasClosureTag = tags.contains { FileTagManager.FileTag.closureGeneratedTags.contains($0.id) }
                
                if hasClosureTag {
                    do {
                        try fileManager.removeItem(atPath: filePath)
                        print("[ClosureFiles] ✅ Eliminato file generato: \(URL(fileURLWithPath: filePath).lastPathComponent)")
                    } catch {
                        print("[ClosureFiles] ⚠️ Errore eliminazione: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// Restituisce la lista dei beni già taggati nelle foto per selezione componenti
    func getTaggedBeni(inSinistroPath path: String) async -> [String] {
        var beni: Set<String> = []
        
        let allFiles = fileService.listFilesRecursive(inDirectory: path)
        for fileURL in allFiles {
            let filePath = fileURL.path
            let tags = await fileTagManager.getTagsForFile(at: filePath)
            
            for tag in tags where tag.id == "foto_bene" {
                if let additionalText = await fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id),
                   !additionalText.isEmpty {
                    beni.insert(additionalText)
                }
            }
        }
        
        return Array(beni).sorted()
    }
    
    // MARK: - Verifica File Mancanti
    
    /// Verifica se mancano file essenziali per la chiusura
    /// Usa la logica centralizzata in CompagniaService per determinare i file richiesti
    func checkMissingEssentialFiles(for sinistro: Sinistro) async -> [String] {
        var missingFiles: [String] = []
        
        guard let riferimento = sinistro.riferimento,
              let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return ["Cartella sinistro non trovata"]
        }
        
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        
        // Ottieni i tipi di file richiesti dalla compagnia per questo sinistro
        let fileRichiesti = compagniaService.getFileRichiestiPerChiusura(compagnia: compagnia, sinistro: sinistro)
        
        // Raccogli i file taggati
        let taggedFiles = await collectTaggedFilesForClosure(inPath: sinistroPath, compagnia: compagnia)
        let filesWithFileFotoTag = await collectFilesWithFileFotoTag(inPath: sinistroPath)
        
        // Verifica ogni tipo di file richiesto
        for tipoFile in fileRichiesti {
            switch tipoFile {
            case .foto:
                let hasPhotos = !taggedFiles.filter { isPhotoTag($0.tagId) }.isEmpty || !filesWithFileFotoTag.isEmpty
                if !hasPhotos {
                    missingFiles.append("Foto")
                }
                
            case .verbale:
                // Verbale richiesto solo per sinistri tradizionali (con sopralluogo)
                let isTradizionale = sinistro.sopralluogo == true
                if isTradizionale {
                    let hasVerbale = taggedFiles.contains { $0.tagId == "verbale" }
                    if !hasVerbale {
                        missingFiles.append("Verbale")
                    }
                }
                
            case .atto:
                let hasAtto = taggedFiles.contains { $0.tagId == "atto_firmato" || $0.tagId == "atto_da_firmare" }
                if !hasAtto {
                    missingFiles.append("Atto")
                }
                
            case .fulminazione:
                let hasFulminazione = taggedFiles.contains { $0.tagId == "fulminazione" }
                if !hasFulminazione {
                    missingFiles.append("Fulminazione")
                }
                
            case .giustificativi:
                let hasGiustificativi = taggedFiles.contains { $0.tagId == "fattura" || $0.tagId == "preventivo" }
                if !hasGiustificativi {
                    missingFiles.append("Giustificativi")
                }
                
            case .perizia:
                // La perizia viene generata dall'elaborato Excel, non la verifichiamo qui
                break
                
            case .altro:
                // File generici, non obbligatori
                break
            }
        }
        
        return missingFiles
    }
}

