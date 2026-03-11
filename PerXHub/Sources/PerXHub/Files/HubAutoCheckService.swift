import Foundation
import PerXCore
import SQLite
#if os(macOS)
import PDFKit
#endif

/// Servizio per autotagging e parsing file sul Hub
/// Replica la logica di FileTagManager e parser del client
public actor HubAutoCheckService {
    public static let shared = HubAutoCheckService()
    
    private init() {}
    
    // MARK: - Main Processing
    
    /// Processa cartella sinistro dopo import
    public func processFolder(sinistroRef: String) async throws -> ProcessingResult {
        print("[AutoCheck] Processing folder for: \(sinistroRef)")
        
        var result = ProcessingResult(sinistroRef: sinistroRef)
        
        // Ottieni lista file dal Vault
        let files = try await VaultManager.shared.listFiles(sinistroRef: sinistroRef)
        
        // Auto-tag per ogni file
        for file in files {
            let taggedFile = await autoTagFile(file, sinistroRef: sinistroRef)
            if !taggedFile.tags.isEmpty {
                result.taggedFiles.append(taggedFile)
            }
        }
        
        // Cerca e parsa Elaborato Peritale Excel (.xlsm)
        if let excelFile = findElaboratoPeritale(in: files, sinistroRef: sinistroRef) {
            do {
                let excelData = try await parseElaboratoExcel(file: excelFile, sinistroRef: sinistroRef)
                result.excelData = excelData
            } catch {
                print("[AutoCheck] ⚠️ Excel parsing failed: \(error)")
            }
        }
        
        // Cerca e parsa PDF incarico (per regolarità amministrativa - solo Generali)
        if let pdfFile = findIncaricoPDF(in: files) {
            do {
                let pdfData = try await parseIncaricoPDF(file: pdfFile)
                result.pdfData = pdfData
            } catch {
                print("[AutoCheck] ⚠️ PDF parsing failed: \(error)")
            }
        }
        
        // Salva dati estratti nel sinistro
        try await updateSinistroWithExtractedData(
            sinistroRef: sinistroRef,
            excelData: result.excelData,
            pdfData: result.pdfData
        )
        
        // Salva i tag nel database
        try await saveTagsToDatabase(result.taggedFiles, sinistroRef: sinistroRef)
        
        print("[AutoCheck] ✅ Processed \(files.count) files, tagged \(result.taggedFiles.count)")
        return result
    }
    
    // MARK: - Auto Tagging (replica logica FileTagManager)
    
    private func autoTagFile(_ file: VaultFile, sinistroRef: String) async -> HubTaggedFile {
        var taggedFile = HubTaggedFile(
            fileId: file.id,
            filename: file.filename,
            relativePath: file.relativePath
        )
        
        let filename = file.filename.lowercased()
        let ext = (filename as NSString).pathExtension
        
        // --- Documenti principali ---
        
        // Elaborato Peritale Excel
        if isElaboratoPeritale(filename: filename, sinistroRef: sinistroRef) {
            var tag = HubTagApplicationData(tagId: "elaborato_excel")
            tag.daAllegareInChiusura = false // non allegato in chiusura
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Incarico PDF
        if filename.contains("incarico") && ext == "pdf" {
            var tag = HubTagApplicationData(tagId: "incarico")
            tag.daAllegareInChiusura = false
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Polizza / Simplo
        if filename.contains("polizza") || filename.contains("simplo") {
            var tag = HubTagApplicationData(tagId: "simplo_di_polizza")
            tag.daAllegareInChiusura = false
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // CGA (Condizioni Generali di Assicurazione)
        if filename.contains("cga") || filename.contains("condizioni generali") {
            var tag = HubTagApplicationData(tagId: "cga")
            tag.daAllegareInChiusura = false
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Report CAT
        if filename.contains("report cat") || filename.contains("reportcat") || filename.contains("cat_") {
            var tag = HubTagApplicationData(tagId: "report_cat")
            tag.daAllegareInChiusura = false
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Denuncia
        if filename.contains("denuncia") {
            var tag = HubTagApplicationData(tagId: "denuncia")
            tag.daAllegareInChiusura = false
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Dichiarazione
        if filename.contains("dichiarazione") {
            var tag = HubTagApplicationData(tagId: "dichiarazione")
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Fattura
        if filename.contains("fattura") && !filename.contains("preventivo") {
            var tag = HubTagApplicationData(tagId: "fattura")
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Preventivo
        if filename.contains("preventivo") {
            var tag = HubTagApplicationData(tagId: "preventivo")
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Perizia
        if filename.contains("perizia") || filename.contains("relazione") && ext == "pdf" {
            var tag = HubTagApplicationData(tagId: "perizia")
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Verbale
        if filename.contains("verbale") {
            var tag = HubTagApplicationData(tagId: "verbale")
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Fulminazione
        if filename.contains("fulminazione") || filename.contains("fulmin") {
            var tag = HubTagApplicationData(tagId: "fulminazione")
            // Determina positiva/negativa dal nome file
            if filename.contains("positiv") {
                tag.fulminazioneSottotipo = "positiva"
            } else if filename.contains("negativ") {
                tag.fulminazioneSottotipo = "negativa"
            }
            tag.daAllegareInChiusura = true // sarà aggiustato in base a compagnia
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Atto (da firmare o firmato)
        if filename.contains("atto") && ext == "pdf" {
            let isFirmato = filename.contains("firmat") || filename.contains("sottoscritt")
            var tag = HubTagApplicationData(tagId: isFirmato ? "atto_firmato" : "atto_da_firmare")
            // Determina accertamento/liquidazione
            if filename.contains("accertamento") {
                tag.attoSottotipo = "accertamento"
            } else if filename.contains("liquidazione") {
                tag.attoSottotipo = "liquidazione"
            }
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // Allegati atto
        if filename.contains("allegat") && (filename.contains("atto") || filename.contains("accettazione") || filename.contains("delega") || filename.contains("iban")) {
            var tag = HubTagApplicationData(tagId: "allegati_atto")
            if filename.contains("accettazione") {
                tag.allegatiAttoSottotipo = "accettazione"
            } else if filename.contains("iban") {
                tag.allegatiAttoSottotipo = "iban"
            } else if filename.contains("delega") {
                tag.allegatiAttoSottotipo = "delega"
            } else if filename.contains("document") {
                tag.allegatiAttoSottotipo = "documenti"
            }
            tag.daAllegareInChiusura = true
            taggedFile.tags.append(tag)
            return taggedFile
        }
        
        // --- Foto ---
        
        if isImage(filename) {
            // Prova a determinare il tipo di foto dal nome/percorso
            let relativePath = file.relativePath.lowercased()
            
            // Ubicazione
            if relativePath.contains("ubicazione") || filename.contains("ubicazione") || filename.contains("esterno") || filename.contains("facciata") {
                var tag = HubTagApplicationData(tagId: "foto_ubicazione_rischio")
                tag.daAllegareInChiusura = true
                taggedFile.tags.append(tag)
                return taggedFile
            }
            
            // Test strumentale
            if filename.contains("test") || filename.contains("misurazione") || filename.contains("multimetro") {
                var tag = HubTagApplicationData(tagId: "test_strumentale")
                tag.daAllegareInChiusura = true
                taggedFile.tags.append(tag)
                return taggedFile
            }
            
            // Ripristino
            if filename.contains("ripristin") || filename.contains("riparazion") {
                var tag = HubTagApplicationData(tagId: "foto_ripristino")
                tag.daAllegareInChiusura = true
                taggedFile.tags.append(tag)
                return taggedFile
            }
            
            // Se nella cartella foto o da_mail/da_whatsapp, taggalo come foto generico
            if relativePath.contains("foto") || relativePath.contains("da_mail") || relativePath.contains("da_whatsapp") {
                // Non applicare tag automatico - l'utente deciderà
            }
        }
        
        return taggedFile
    }
    
    // MARK: - File Detection Helpers
    
    private func isElaboratoPeritale(filename: String, sinistroRef: String) -> Bool {
        let lower = filename.lowercased()
        
        // Pattern: Elaborato_Peritale_RIFERIMENTO.xlsm
        if lower.hasPrefix("elaborato_peritale_") && (lower.hasSuffix(".xlsm") || lower.hasSuffix(".xlsx")) {
            return true
        }
        
        // Pattern alternativo: contiene elaborato e xlsx/xlsm
        if lower.contains("elaborato") && (lower.hasSuffix(".xlsm") || lower.hasSuffix(".xlsx")) {
            return true
        }
        
        return false
    }
    
    private func findElaboratoPeritale(in files: [VaultFile], sinistroRef: String) -> VaultFile? {
        // Cerca file con pattern Elaborato_Peritale_*.xlsm
        let candidates = files.filter { isElaboratoPeritale(filename: $0.filename, sinistroRef: sinistroRef) }
        
        if candidates.isEmpty { return nil }
        
        // Se ce ne sono più di uno, prendi il più recente
        return candidates.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }.first
    }
    
    private func findIncaricoPDF(in files: [VaultFile]) -> VaultFile? {
        // Cerca PDF con "incarico" o "assegnazione" nel nome
        let candidates = files.filter { file in
            let lower = file.filename.lowercased()
            return lower.hasSuffix(".pdf") && (lower.contains("incarico") || lower.contains("assegnazione"))
        }
        
        if candidates.isEmpty { return nil }
        
        // Se ce ne sono più di uno, prendi il più recente
        return candidates.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }.first
    }
    
    private func isImage(_ filename: String) -> Bool {
        let imageExts = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "bmp", "webp"]
        let ext = (filename as NSString).pathExtension.lowercased()
        return imageExts.contains(ext)
    }
    
    // MARK: - Excel Parsing (Elaborato Peritale)
    
    /// Parsa Elaborato Peritale Excel usando Python worker
    private func parseElaboratoExcel(file: VaultFile, sinistroRef: String) async throws -> ExcelExtractedData {
        print("[AutoCheck] Parsing Excel: \(file.filename)")
        
        // Scarica file dal vault a path temporaneo
        let tempURL = try await VaultManager.shared.downloadToTemp(fileId: file.id)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Chiama Python worker per parsing
        // In alternativa, se siamo su macOS, possiamo usare NativeExcelReader direttamente
        #if os(macOS)
        let result = try NativeExcelReader.shared.readClaimExcelFile(at: tempURL)
        return convertToExcelExtractedData(result)
        #else
        // Fallback: chiama Python worker via API interna
        return try await parseExcelViaPythonWorker(tempURL)
        #endif
    }
    
    private func convertToExcelExtractedData(_ result: [String: Any]) -> ExcelExtractedData {
        var data = ExcelExtractedData()
        
        // Compagnia e gruppo
        data.gruppo = result["gruppo"] as? String
        data.compagnia = result["nome_compagnia"] as? String ?? result["nomeCompagnia"] as? String
        data.area = result["area"] as? String
        
        // Agenzia
        data.codiceAgenzia = result["codice_agenzia"] as? String ?? result["codiceAgenzia"] as? String
        data.agenzia = result["nome_agenzia"] as? String ?? result["agenzia"] as? String
        
        // Identificativi
        data.numeroSinistro = result["numero_sinistro_compagnia"] as? String ?? result["numeroSinistroCompagnia"] as? String
        data.numeroPolizza = result["numero_polizza"] as? String ?? result["numeroPolizza"] as? String
        data.tipoPolizza = result["tipo_polizza"] as? String ?? result["tipoPolizza"] as? String
        
        // Contraente/Assicurato
        data.nomeContraente = result["nome_contraente"] as? String ?? result["nomeContraente"] as? String
        data.telefonoAssicurato = result["telefono_assicurato"] as? String ?? result["telefonoAssicurato"] as? String
        data.telefoniAssicurato = result["telefoni_assicurato"] as? [String] ?? result["telefoniAssicuratoArray"] as? [String]
        data.emailAssicurato = result["email_assicurato"] as? String ?? result["emailAssicurato"] as? String
        data.emailAssicuratoArray = result["email_assicurato_array"] as? [String] ?? result["emailAssicuratoArray"] as? [String]
        data.indirizzoAssicurato = result["indirizzo"] as? String ?? result["indirizzoAssicurato"] as? String
        
        // Danneggiato
        data.nomeDanneggiato = result["nome_danneggiato"] as? String ?? result["nomeDanneggiato"] as? String
        
        // Date
        data.dataSinistro = parseDate(result["data_sinistro"] ?? result["dataSinistro"])
        data.dataDenuncia = parseDate(result["data_denuncia"] ?? result["dataDenuncia"])
        data.dataIncarico = parseDate(result["data_incarico"] ?? result["dataIncarico"])
        data.dataSopralluogo = parseDate(result["data_sopralluogo"] ?? result["dataSopralluogo"])
        
        // Importi
        data.richiesta = parseDouble(result["importo_richiesto"] ?? result["richiesta"])
        data.stimaDanno = parseDouble(result["stima_danno"] ?? result["stimaDanno"])
        
        // Esito
        data.definizione = result["definizione"] as? String
        
        return data
    }
    
    private func parseExcelViaPythonWorker(_ url: URL) async throws -> ExcelExtractedData {
        // TODO: Implementare chiamata a Python worker
        throw NSError(domain: "AutoCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python worker non implementato"])
    }
    
    // MARK: - PDF Parsing (Incarico - Regolarità Amministrativa)
    
    /// Parsa PDF incarico per estrarre regolarità amministrativa (solo Generali)
    private func parseIncaricoPDF(file: VaultFile) async throws -> PDFExtractedData {
        print("[AutoCheck] Parsing PDF: \(file.filename)")
        
        // Scarica file dal vault a path temporaneo
        let tempURL = try await VaultManager.shared.downloadToTemp(fileId: file.id)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        #if os(macOS)
        return try parsePDFNative(at: tempURL)
        #else
        throw NSError(domain: "AutoCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "PDF parsing non disponibile su questa piattaforma"])
        #endif
    }
    
    #if os(macOS)
    private func parsePDFNative(at url: URL) throws -> PDFExtractedData {
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "AutoCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "PDF non leggibile"])
        }
        
        // Estrai testo completo
        var fullText = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex), let pageText = page.string {
                fullText += pageText + "\n"
            }
        }
        
        if fullText.isEmpty {
            throw NSError(domain: "AutoCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "PDF senza testo"])
        }
        
        // Normalizza per parsing
        let normalized = normalizeText(fullText)
        
        var result = PDFExtractedData()
        
        // Estrai regolarità amministrativa
        result.regolaritaAmministrativa = extractRegolaritaAmministrativa(from: normalized)
        
        // Estrai data pagamento premio (solo se regolarità = true)
        if result.regolaritaAmministrativa == true {
            result.dataPagamentoPremio = extractDataPagamentoPremio(from: normalized)
        }
        
        // Estrai date aggiuntive
        result.dataSinistro = extractDate(forLabels: ["data sinistro"], from: normalized)
        result.dataDenuncia = extractDate(forLabels: ["data denuncia"], from: normalized)
        result.dataIncarico = extractDate(forLabels: ["data incarico"], from: normalized)
        
        // Estrai agenzia
        let (codice, nome) = extractAgenzia(from: normalized)
        result.codiceAgenzia = codice
        result.agenzia = nome
        result.subagenzia = extractSubagenzia(from: normalized)
        
        return result
    }
    
    private func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()
        // Rimuovi accenti
        normalized = normalized.replacingOccurrences(of: "à", with: "a")
        normalized = normalized.replacingOccurrences(of: "è", with: "e")
        normalized = normalized.replacingOccurrences(of: "é", with: "e")
        normalized = normalized.replacingOccurrences(of: "ì", with: "i")
        normalized = normalized.replacingOccurrences(of: "ò", with: "o")
        normalized = normalized.replacingOccurrences(of: "ù", with: "u")
        // Normalizza spazi
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized
    }
    
    private func extractRegolaritaAmministrativa(from text: String) -> Bool? {
        let patterns = [
            #"regolarita\s*amministrativa\s*[:\s]+\s*(si|no)\b"#,
            #"regolarita\s*amministrativa\s*[:\s]+\s*(sì|sÌ)\b"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let valueRange = Range(match.range(at: 1), in: text) {
                    let value = String(text[valueRange]).lowercased()
                    if value == "si" || value == "sì" {
                        return true
                    } else if value == "no" {
                        return false
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractDataPagamentoPremio(from text: String) -> Date? {
        let patterns = [
            #"data\s*pag\.?\s*premio\s*[:\s]+\s*(\d{4}[-/]\d{2}[-/]\d{2})"#,
            #"data\s*pagamento\s*premio\s*[:\s]+\s*(\d{4}[-/]\d{2}[-/]\d{2})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   let dateRange = Range(match.range(at: 1), in: text) {
                    return parseDateString(String(text[dateRange]))
                }
            }
        }
        
        return nil
    }
    
    private func extractDate(forLabels labels: [String], from text: String) -> Date? {
        let datePattern = #"(\d{4}[-/]\d{2}[-/]\d{2}|\d{2}[-/]\d{2}[-/]\d{2,4})"#
        
        for label in labels {
            let pattern = "\(label)\\s*[:\\s]+\\s*\(datePattern)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let dateRange = Range(match.range(at: 1), in: text) {
                return parseDateString(String(text[dateRange]))
            }
        }
        
        return nil
    }
    
    private func extractAgenzia(from text: String) -> (codice: String?, nome: String?) {
        let pattern = #"agenzia\s*[:\s]+\s*([a-z0-9]{2,10})\s*(?:-\s*)?(.+?)(?=\s+(subagenzia|data\s+sinistro|data\s+denuncia|data\s+incarico|regolarita|data\s+pag)|$)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return (nil, nil)
        }
        
        let codice: String?
        if let r = Range(match.range(at: 1), in: text) {
            codice = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } else {
            codice = nil
        }
        
        let nome: String?
        if let r = Range(match.range(at: 2), in: text) {
            let raw = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            nome = raw.isEmpty ? nil : raw
        } else {
            nome = nil
        }
        
        return (codice, nome)
    }
    
    private func extractSubagenzia(from text: String) -> String? {
        let pattern = #"subagenzia\s*[:\s]+\s*(.+?)(?=\s+(agenzia|data\s+sinistro|data\s+denuncia|data\s+incarico|regolarita|data\s+pag)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    #endif
    
    // MARK: - Update Sinistro
    
    private func updateSinistroWithExtractedData(
        sinistroRef: String,
        excelData: ExcelExtractedData?,
        pdfData: PDFExtractedData?
    ) async throws {
        let conn = try await DatabaseManager.shared.db()
        
        var updates: [Setter] = []
        
        // Da Excel
        if let excel = excelData {
            // Compagnia e gruppo
            if let gruppo = excel.gruppo {
                updates.append(DatabaseSchema.SinistriColumns.gruppo <- gruppo)
            }
            if let compagnia = excel.compagnia {
                updates.append(DatabaseSchema.SinistriColumns.compagnia <- compagnia)
            }
            if let area = excel.area {
                updates.append(DatabaseSchema.SinistriColumns.area <- area)
            }
            
            // Agenzia
            if let codice = excel.codiceAgenzia {
                updates.append(DatabaseSchema.SinistriColumns.codiceAgenzia <- codice)
            }
            if let agenzia = excel.agenzia {
                updates.append(DatabaseSchema.SinistriColumns.agenzia <- agenzia)
            }
            
            // Identificativi
            if let num = excel.numeroSinistro {
                updates.append(DatabaseSchema.SinistriColumns.numeroSinistro <- num)
            }
            if let pol = excel.numeroPolizza {
                updates.append(DatabaseSchema.SinistriColumns.numeroPolizza <- pol)
            }
            if let tipo = excel.tipoPolizza {
                updates.append(DatabaseSchema.SinistriColumns.tipoPolizza <- tipo)
            }
            
            // Contraente/Assicurato
            if let nome = excel.nomeContraente {
                updates.append(DatabaseSchema.SinistriColumns.nomeContraente <- nome)
                updates.append(DatabaseSchema.SinistriColumns.nomeAssicurato <- nome)
            }
            if let tel = excel.telefonoAssicurato {
                updates.append(DatabaseSchema.SinistriColumns.telefonoContraente <- tel)
                updates.append(DatabaseSchema.SinistriColumns.telefonoAssicurato <- tel)
            }
            if let telefoni = excel.telefoniAssicurato, let json = try? JSONEncoder().encode(telefoni) {
                updates.append(DatabaseSchema.SinistriColumns.telefoniAssicurato <- String(data: json, encoding: .utf8))
            }
            if let email = excel.emailAssicurato {
                updates.append(DatabaseSchema.SinistriColumns.emailContraente <- email)
                updates.append(DatabaseSchema.SinistriColumns.emailAssicurato <- email)
            }
            if let emails = excel.emailAssicuratoArray, let json = try? JSONEncoder().encode(emails) {
                updates.append(DatabaseSchema.SinistriColumns.emailAssicuratoArray <- String(data: json, encoding: .utf8))
            }
            if let indirizzo = excel.indirizzoAssicurato {
                updates.append(DatabaseSchema.SinistriColumns.indirizzoContraente <- indirizzo)
                updates.append(DatabaseSchema.SinistriColumns.indirizzoAssicurato <- indirizzo)
            }
            
            // Danneggiato
            if let nome = excel.nomeDanneggiato {
                updates.append(DatabaseSchema.SinistriColumns.nomeDanneggiato <- nome)
            }
            
            // Date
            if let data = excel.dataSinistro {
                updates.append(DatabaseSchema.SinistriColumns.dataSinistro <- data.timeIntervalSince1970)
            }
            if let data = excel.dataDenuncia {
                updates.append(DatabaseSchema.SinistriColumns.dataDenuncia <- data.timeIntervalSince1970)
            }
            if let data = excel.dataIncarico {
                updates.append(DatabaseSchema.SinistriColumns.dataIncarico <- data.timeIntervalSince1970)
            }
            if let data = excel.dataSopralluogo {
                updates.append(DatabaseSchema.SinistriColumns.dataSopralluogo <- data.timeIntervalSince1970)
            }
            
            // Importi
            if let richiesta = excel.richiesta {
                updates.append(DatabaseSchema.SinistriColumns.richiesta <- richiesta)
            }
            if let stima = excel.stimaDanno {
                updates.append(DatabaseSchema.SinistriColumns.stimaDanno <- stima)
            }
            
            // Esito
            if let def = excel.definizione {
                updates.append(DatabaseSchema.SinistriColumns.definizione <- def)
                // Calcola concordata e negativa dalla definizione
                let upper = def.uppercased()
                let concordata = upper.starts(with: "CONCORDATO") && !upper.contains("NON CONCORDATO")
                let negativa = !upper.contains("DANNO INDENNIZZABILE") && upper.contains("NON CONCORDATO")
                updates.append(DatabaseSchema.SinistriColumns.concordata <- concordata)
                updates.append(DatabaseSchema.SinistriColumns.negativa <- negativa)
            }
        }
        
        // Da PDF (solo regolarità amministrativa)
        if let pdf = pdfData {
            if let regolarita = pdf.regolaritaAmministrativa {
                updates.append(DatabaseSchema.SinistriColumns.regolaritaAmministrativa <- regolarita)
            }
            if let data = pdf.dataPagamentoPremio {
                updates.append(DatabaseSchema.SinistriColumns.dataPagamentoPremio <- data.timeIntervalSince1970)
            }
            // Agenzia da PDF se non già valorizzata da Excel
            if let codice = pdf.codiceAgenzia {
                updates.append(DatabaseSchema.SinistriColumns.codiceAgenzia <- codice)
            }
            if let agenzia = pdf.agenzia {
                updates.append(DatabaseSchema.SinistriColumns.agenzia <- agenzia)
            }
            if let sub = pdf.subagenzia {
                updates.append(DatabaseSchema.SinistriColumns.subagenzia <- sub)
            }
        }
        
        if !updates.isEmpty {
            updates.append(DatabaseSchema.SinistriColumns.lastModifiedAt <- Date().timeIntervalSince1970)
            updates.append(DatabaseSchema.SinistriColumns.syncedToCK <- false)
            
            try conn.run(
                DatabaseSchema.sinistri
                    .filter(DatabaseSchema.SinistriColumns.riferimento == sinistroRef)
                    .update(updates)
            )
            
            print("[AutoCheck] ✅ Updated sinistro with extracted data")
        }
    }
    
    // MARK: - Save Tags to Database
    
    private func saveTagsToDatabase(_ taggedFiles: [HubTaggedFile], sinistroRef: String) async throws {
        // TODO: Implementare salvataggio tag nel vault_files o tabella separata
        // Per ora logghiamo solo
        for file in taggedFiles {
            for tag in file.tags {
                print("[AutoCheck] Tag: \(file.filename) -> \(tag.tagId)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func parseDate(_ value: Any?) -> Date? {
        guard let value = value else { return nil }
        
        if let date = value as? Date {
            return date
        }
        
        if let string = value as? String, !string.isEmpty {
            return parseDateString(string)
        }
        
        if let timeInterval = value as? TimeInterval {
            return Date(timeIntervalSince1970: timeInterval)
        }
        
        return nil
    }
    
    private func parseDateString(_ string: String) -> Date? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "/")
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        
        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "dd/MM/yy",
            "dd-MM-yy"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseDouble(_ value: Any?) -> Double? {
        guard let value = value else { return nil }
        
        if let num = value as? Double {
            return num
        }
        
        if let num = value as? NSNumber {
            return num.doubleValue
        }
        
        if let string = value as? String, !string.isEmpty {
            let normalized = string.replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        
        return nil
    }
}

// MARK: - Result Types

public struct ProcessingResult: Codable, Sendable {
    public let sinistroRef: String
    public var taggedFiles: [HubTaggedFile] = []
    public var excelData: ExcelExtractedData?
    public var pdfData: PDFExtractedData?
    
    public init(sinistroRef: String) {
        self.sinistroRef = sinistroRef
    }
}

public struct ExcelExtractedData: Codable, Sendable {
    // Compagnia e gruppo
    public var gruppo: String?
    public var compagnia: String?
    public var area: String?
    
    // Agenzia
    public var codiceAgenzia: String?
    public var agenzia: String?
    
    // Identificativi
    public var numeroSinistro: String?
    public var numeroPolizza: String?
    public var tipoPolizza: String?
    
    // Contraente/Assicurato
    public var nomeContraente: String?
    public var telefonoAssicurato: String?
    public var telefoniAssicurato: [String]?
    public var emailAssicurato: String?
    public var emailAssicuratoArray: [String]?
    public var indirizzoAssicurato: String?
    
    // Danneggiato
    public var nomeDanneggiato: String?
    
    // Date
    public var dataSinistro: Date?
    public var dataDenuncia: Date?
    public var dataIncarico: Date?
    public var dataSopralluogo: Date?
    
    // Importi
    public var richiesta: Double?
    public var stimaDanno: Double?
    
    // Esito
    public var definizione: String?
    
    public init() {}
}

public struct PDFExtractedData: Codable, Sendable {
    // Regolarità amministrativa (Generali)
    public var regolaritaAmministrativa: Bool?
    public var dataPagamentoPremio: Date?
    
    // Date
    public var dataSinistro: Date?
    public var dataDenuncia: Date?
    public var dataIncarico: Date?
    
    // Agenzia
    public var codiceAgenzia: String?
    public var agenzia: String?
    public var subagenzia: String?
    
    public init() {}
}

// MARK: - Native Excel Reader (macOS)

#if os(macOS)
import Foundation
import Compression

/// Lettore nativo per file Excel (.xlsx/.xlsm) senza dipendenze esterne
/// Replica la logica di NativeExcelReader del client
public class NativeExcelReader {
    public static let shared = NativeExcelReader()
    
    private init() {}
    
    public static var isRunningInSandbox: Bool {
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
    
    public func readClaimExcelFile(at url: URL) throws -> [String: Any] {
        // Apri il file Excel come ZIP
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        let fileData = fileHandle.readDataToEndOfFile()
        
        // Estrai i contenuti XML
        guard let archive = try? extractZip(data: fileData) else {
            throw NSError(domain: "NativeExcelReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "File non valido"])
        }
        
        // Leggi sharedStrings
        let sharedStrings: [String]
        if let ssData = archive["xl/sharedStrings.xml"] {
            sharedStrings = parseSharedStrings(ssData)
        } else {
            sharedStrings = []
        }
        
        // Leggi sheet1
        guard let sheetData = archive["xl/worksheets/sheet1.xml"] else {
            throw NSError(domain: "NativeExcelReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sheet non trovato"])
        }
        
        let cells = parseSheet(sheetData, sharedStrings: sharedStrings)
        
        // Estrai valori nelle celle note
        var result: [String: Any] = [:]
        
        result["gruppo"] = cells["H5"] ?? ""
        result["nome_compagnia"] = cells["P5"] ?? ""
        result["area"] = cells["H8"] ?? ""
        
        // Agenzia
        let agenziaFull = cells["P8"] ?? ""
        if agenziaFull.count >= 3 {
            result["codice_agenzia"] = String(agenziaFull.prefix(3)).uppercased()
            result["nome_agenzia"] = String(agenziaFull.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else {
            result["codice_agenzia"] = ""
            result["nome_agenzia"] = agenziaFull
        }
        
        result["numero_sinistro_compagnia"] = cells["E10"] ?? ""
        result["data_sinistro"] = cells["H13"] ?? ""
        result["data_denuncia"] = cells["K13"] ?? ""
        result["data_incarico"] = cells["P13"] ?? ""
        result["data_sopralluogo"] = cells["S13"] ?? ""
        result["indirizzo"] = cells["E14"] ?? ""
        result["numero_polizza"] = cells["E16"] ?? ""
        result["tipo_polizza"] = cells["P16"] ?? ""
        result["nome_contraente"] = normalizeNome(cells["D20"] ?? "")
        
        // Contatti da L20
        let contatti = cells["L20"] ?? ""
        let (telefoni, emails) = extractContacts(from: contatti)
        result["telefono_assicurato"] = telefoni.first ?? ""
        result["telefoni_assicurato"] = telefoni
        result["email_assicurato"] = emails.first ?? ""
        result["email_assicurato_array"] = emails
        
        result["nome_danneggiato"] = cells["A24"] ?? ""
        result["importo_richiesto"] = cells["I24"] ?? "0"
        result["definizione"] = cells["M24"] ?? ""
        result["stima_danno"] = cells["S24"] ?? "0"
        
        return result
    }
    
    private func extractZip(data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        
        // Mini ZIP parser
        var offset = 0
        while offset < data.count - 30 {
            // Local file header signature
            let sig = data.subdata(in: offset..<offset+4)
            guard sig == Data([0x50, 0x4B, 0x03, 0x04]) else { break }
            
            let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compressedSize = data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) }
            let uncompressedSize = data.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) }
            let fileNameLength = data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + Int(fileNameLength)
            guard fileNameEnd <= data.count else { break }
            
            let fileName = String(data: data.subdata(in: fileNameStart..<fileNameEnd), encoding: .utf8) ?? ""
            
            let contentStart = fileNameEnd + Int(extraFieldLength)
            let contentEnd = contentStart + Int(compressedSize)
            guard contentEnd <= data.count else { break }
            
            let compressedData = data.subdata(in: contentStart..<contentEnd)
            
            if compressionMethod == 0 {
                // Stored (no compression)
                result[fileName] = compressedData
            } else if compressionMethod == 8 {
                // Deflate
                if let decompressed = decompress(compressedData, expectedSize: Int(uncompressedSize)) {
                    result[fileName] = decompressed
                }
            }
            
            offset = contentEnd
        }
        
        return result
    }
    
    private func decompress(_ data: Data, expectedSize: Int) -> Data? {
        var result = Data(count: expectedSize)
        let decodedSize = result.withUnsafeMutableBytes { destPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize > 0 else { return nil }
        result.count = decodedSize
        return result
    }
    
    private func parseSharedStrings(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        
        var strings: [String] = []
        
        // Simple regex-based parsing
        let pattern = "<t[^>]*>([^<]*)</t>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(xml.startIndex..., in: xml)
            let matches = regex.matches(in: xml, options: [], range: range)
            for match in matches {
                if let textRange = Range(match.range(at: 1), in: xml) {
                    strings.append(String(xml[textRange]))
                }
            }
        }
        
        return strings
    }
    
    private func parseSheet(_ data: Data, sharedStrings: [String]) -> [String: String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [:] }
        
        var cells: [String: String] = [:]
        
        // Pattern per celle: <c r="A1" t="s"><v>0</v></c>
        let cellPattern = #"<c r=\"([A-Z]+\d+)\"[^>]*(?:t=\"([^\"]+)\")?[^>]*><v>([^<]*)</v></c>"#
        if let regex = try? NSRegularExpression(pattern: cellPattern, options: []) {
            let range = NSRange(xml.startIndex..., in: xml)
            let matches = regex.matches(in: xml, options: [], range: range)
            
            for match in matches {
                guard let refRange = Range(match.range(at: 1), in: xml),
                      let valueRange = Range(match.range(at: 3), in: xml) else { continue }
                
                let ref = String(xml[refRange])
                let rawValue = String(xml[valueRange])
                
                var cellType: String? = nil
                if let typeRange = Range(match.range(at: 2), in: xml) {
                    cellType = String(xml[typeRange])
                }
                
                if cellType == "s" {
                    // Shared string
                    if let index = Int(rawValue), index < sharedStrings.count {
                        cells[ref] = sharedStrings[index]
                    }
                } else {
                    cells[ref] = rawValue
                }
            }
        }
        
        return cells
    }
    
    private func normalizeNome(_ nome: String) -> String {
        return nome.components(separatedBy: " ")
            .map { word in
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
    
    private func extractContacts(from text: String) -> (telefoni: [String], emails: [String]) {
        var telefoni: [String] = []
        var emails: [String] = []
        
        // Estrai telefoni
        let phonePattern = #"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,9}\b"#
        if let regex = try? NSRegularExpression(pattern: phonePattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches {
                if let r = Range(match.range, in: text) {
                    let phone = String(text[r]).replacingOccurrences(of: "[-.\\s()]", with: "", options: .regularExpression)
                    if phone.count >= 6 && phone.count <= 15 {
                        telefoni.append(phone)
                    }
                }
            }
        }
        
        // Estrai email
        let emailPattern = #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches {
                if let r = Range(match.range, in: text) {
                    emails.append(String(text[r]))
                }
            }
        }
        
        return (telefoni, emails)
    }
}
#endif
