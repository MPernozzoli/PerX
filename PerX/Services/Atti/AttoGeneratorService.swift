import Foundation
import PDFKit
import AppKit
import CoreData

/// Servizio per la generazione di PDF degli atti compilati
@MainActor
class AttoGeneratorService {
    
    static let shared = AttoGeneratorService()
    
    private let templateManager = AttoTemplateManager.shared
    private let textFitter = TextFitter.shared
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Types
    
    struct GenerationResult {
        let success: Bool
        let pdfData: Data?
        let pdfURL: URL?
        let errorMessage: String?
    }
    
    typealias ManualValues = [String: Any]
    
    // MARK: - Preview Generation
    
    /// Genera PDF in memoria per anteprima (non salva su disco)
    func generatePreview(
        sinistro: Sinistro,
        perizia: Perizia?,
        template: AttoTemplate,
        manualValues: ManualValues? = nil
    ) -> Data? {
        guard let pdfURL = templateManager.getPDFURL(for: template),
              let originalDocument = PDFDocument(url: pdfURL) else {
            print("[AttoGeneratorService] Impossibile caricare PDF template")
            return nil
        }
        
        // Crea un nuovo documento PDF per l'output
        let outputData = NSMutableData()
        guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
              let firstPage = originalDocument.page(at: 0) else {
            return nil
        }
        
        let mediaBox = firstPage.bounds(for: .mediaBox)
        var pdfRect = CGRect(origin: .zero, size: mediaBox.size)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &pdfRect, nil) else {
            return nil
        }
        
        // Estrai i valori per i campi
        let fieldValues = extractFieldValues(
            sinistro: sinistro,
            perizia: perizia,
            template: template,
            manualValues: manualValues
        )
        
        // Processa ogni pagina
        for pageIndex in 0..<originalDocument.pageCount {
            guard let page = originalDocument.page(at: pageIndex) else { continue }
            
            let pageBounds = page.bounds(for: .mediaBox)
            var pageRect = CGRect(origin: .zero, size: pageBounds.size)
            
            // Inizia nuova pagina
            pdfContext.beginPDFPage(nil)
            
            // Disegna la pagina originale
            pdfContext.saveGState()
            if let pageRef = page.pageRef {
                pdfContext.drawPDFPage(pageRef)
            }
            pdfContext.restoreGState()
            
            // Disegna i campi per questa pagina
            if let pageTemplate = template.pages.first(where: { $0.pageNumber == pageIndex }) {
                drawFields(
                    pageTemplate.fields,
                    values: fieldValues,
                    context: pdfContext,
                    pageHeight: pageBounds.height
                )
            }
            
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        return outputData as Data
    }
    
    // MARK: - Save Generation
    
    /// Genera PDF e lo salva nella cartella del sinistro
    func generateAndSave(
        sinistro: Sinistro,
        perizia: Perizia?,
        template: AttoTemplate,
        manualValues: ManualValues? = nil
    ) -> GenerationResult {
        // Genera il PDF
        guard let pdfData = generatePreview(
            sinistro: sinistro,
            perizia: perizia,
            template: template,
            manualValues: manualValues
        ) else {
            return GenerationResult(
                success: false,
                pdfData: nil,
                pdfURL: nil,
                errorMessage: "Impossibile generare il PDF"
            )
        }
        
        // Determina il percorso di salvataggio
        guard let cartella = sinistro.cartella,
              let riferimento = sinistro.riferimento else {
            return GenerationResult(
                success: false,
                pdfData: pdfData,
                pdfURL: nil,
                errorMessage: "Cartella sinistro non configurata"
            )
        }
        
        // Determina sottotipo atto
        let sottotipo = CompagniaService.shared.determinaSottotipoAtto(tipoChiusura: sinistro.definizione)
        
        // Nome file fisso: "atto da firmare"
        let nomeFile = "atto da firmare"
        
        let pdfPath = (cartella as NSString).appendingPathComponent("\(nomeFile).pdf")
        let pdfURL = URL(fileURLWithPath: pdfPath)
        
        // Salva il file
        do {
            try pdfData.write(to: pdfURL, options: .atomic)
            
            // Applica tag
            applyTags(to: pdfURL, sottotipo: sottotipo)
            
            return GenerationResult(
                success: true,
                pdfData: pdfData,
                pdfURL: pdfURL,
                errorMessage: nil
            )
        } catch {
            return GenerationResult(
                success: false,
                pdfData: pdfData,
                pdfURL: nil,
                errorMessage: "Errore salvataggio: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Tag Application
    
    func applyTags(to pdfURL: URL, sottotipo: SottotipoAtto) {
        let fileTagManager = FileTagManager.shared
        
        // Trova il tag "atto_da_firmare"
        if let attoTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "atto_da_firmare" }) {
            fileTagManager.addTag(attoTag, toFile: pdfURL.path)
            
            // Imposta sottotipo
            fileTagManager.setAttoSottotipo(sottotipo.rawValue, forFile: pdfURL.path, tagId: attoTag.id)
        }
    }
    
    // MARK: - Field Value Extraction
    
    private func extractFieldValues(
        sinistro: Sinistro,
        perizia: Perizia?,
        template: AttoTemplate,
        manualValues: ManualValues?
    ) -> [String: Any] {
        var values: [String: Any] = [:]
        
        // Se ci sono valori manuali, usali come override
        if let manual = manualValues {
            values.merge(manual) { _, new in new }
        }
        
        // Nome assicurato
        if values["nome_assicurato"] == nil {
            values["nome_assicurato"] = sinistro.nomeAssicurato ?? ""
        }
        
        // Indirizzo assicurato
        if values["indirizzo_assicurato"] == nil {
            values["indirizzo_assicurato"] = sinistro.indirizzoAssicurato ?? ""
        }
        
        // Importi
        let sottotipo = CompagniaService.shared.determinaSottotipoAtto(tipoChiusura: sinistro.definizione)
        let importo = calculateImporto(sinistro: sinistro, perizia: perizia, sottotipo: sottotipo)
        
        if values["importo_numero"] == nil {
            values["importo_numero"] = importo
        }
        
        if values["importo_lettere"] == nil {
            values["importo_lettere"] = TextFitter.numeroInLettere(Decimal(importo))
        }
        
        // Dati sinistro
        if values["data_sinistro"] == nil, let dataSinistro = sinistro.dataSinistro {
            values["data_sinistro"] = TextFitter.formatDate(dataSinistro)
        }

        // Regolarità amministrativa / Data pagamento premio (Gruppo Generali - da PDF incarico)
        // Nomi campo per "estero"/template:
        // - regolarita_amministrativa  -> "SI"/"NO"/"" (se non rilevata)
        // - data_pagamento_premio     -> dd/MM/yyyy (solo se regolarità = SI)
        if values["regolarita_amministrativa"] == nil {
            if let reg = sinistro.isRegolaritaAmministrativa {
                values["regolarita_amministrativa"] = reg ? "SI" : "NO"
            } else {
                values["regolarita_amministrativa"] = ""
            }
        }
        
        if values["data_pagamento_premio"] == nil {
            if sinistro.isRegolaritaAmministrativa == true, let dataPremio = sinistro.dataPagamentoPremio {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "it_IT")
                formatter.timeZone = TimeZone(identifier: "Europe/Rome")
                formatter.dateFormat = "dd/MM/yyyy"
                values["data_pagamento_premio"] = formatter.string(from: dataPremio)
            } else {
                values["data_pagamento_premio"] = ""
            }
        }
        
        if values["numero_polizza"] == nil {
            values["numero_polizza"] = sinistro.numeroPolizza ?? ""
        }
        
        if values["agenzia"] == nil {
            values["agenzia"] = sinistro.agenzia ?? ""
        }
        
        if values["numero_sinistro_compagnia"] == nil {
            values["numero_sinistro_compagnia"] = sinistro.numeroSinistroCompagnia ?? ""
        }
        
        // Nome perito
        if values["nome_perito"] == nil {
            let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
            values["nome_perito"] = userName
        }
        
        // Tick compagnia
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        values["tick_compagnia_zurich"] = compagnia == .zurichItalia
        values["tick_compagnia_cattolica"] = compagnia == .cattolica
        values["tick_compagnia_generali"] = compagnia == .generaliItalia
        values["tick_compagnia_unipol"] = compagnia == .unipolItalia
        
        // Tick sottocompagnie Cattolica (determinato da tipoPolizza)
        if compagnia == .cattolica {
            let sottocompagnia = determinaSottocompagniaCattolica(tipoPolizza: sinistro.tipoPolizza)
            values["tick_sottocompagnia_cattolica"] = sottocompagnia == .cattolica
            values["tick_sottocompagnia_tua"] = sottocompagnia == .tua
            values["tick_sottocompagnia_fata"] = sottocompagnia == .fata
            values["tick_sottocompagnia_bcc"] = sottocompagnia == .bcc
            values["tick_sottocompagnia_abb"] = sottocompagnia == .abb
        } else {
            // Non Cattolica: tutti false
            values["tick_sottocompagnia_cattolica"] = false
            values["tick_sottocompagnia_tua"] = false
            values["tick_sottocompagnia_fata"] = false
            values["tick_sottocompagnia_bcc"] = false
            values["tick_sottocompagnia_abb"] = false
        }
        
        // Codice fiscale e partita IVA (da compilare manualmente nell'atto)
        if values["codice_fiscale"] == nil {
            values["codice_fiscale"] = ""
        }
        if values["partita_iva"] == nil {
            values["partita_iva"] = ""
        }
        if values["beneficiario"] == nil {
            values["beneficiario"] = sinistro.nomeAssicurato ?? ""
        }
        
        // Tick tipo atto (mutuamente esclusivi)
        if values["tick_tipo_atto_liquidazione"] == nil {
            values["tick_tipo_atto_liquidazione"] = sottotipo == .liquidazione
        }
        if values["tick_tipo_atto_accertamento"] == nil {
            values["tick_tipo_atto_accertamento"] = sottotipo == .accertamento
        }
        
        // Riserva/Osservazioni
        let hasRiserva = perizia?.hasRiserva ?? false
        if values["tick_riserva"] == nil {
            values["tick_riserva"] = hasRiserva
        }
        if values["tick_osservazioni"] == nil {
            values["tick_osservazioni"] = !hasRiserva
        }
        if values["note_riserva_osservazioni"] == nil {
            if hasRiserva {
                values["note_riserva_osservazioni"] = perizia?.noteRiserva ?? ""
            } else {
                values["note_riserva_osservazioni"] = perizia?.noteOsservazioni ?? ""
            }
        }
        
        // Relazione perizia
        if values["relazione_perizia"] == nil {
            values["relazione_perizia"] = perizia?.relazionePerizia ?? ""
        }
        
        if values["note_conclusive"] == nil {
            values["note_conclusive"] = perizia?.noteConclusive ?? ""
        }
        
        if values["evento_causato_da"] == nil {
            values["evento_causato_da"] = perizia?.eventoCausatoDa ?? ""
        }
        
        // Riparto (coassicurazioni)
        let coassicurazioni = sinistro.coassicurazioniArray
        let hasRiparto = !coassicurazioni.isEmpty
        
        if values["tick_riparto"] == nil {
            values["tick_riparto"] = hasRiparto
        }
        
        if values["tick_con_le_seguenti"] == nil {
            values["tick_con_le_seguenti"] = hasRiparto
        }
        
        if coassicurazioni.count > 0 {
            if values["nome_riparto_1"] == nil {
                values["nome_riparto_1"] = coassicurazioni[0].compagnia
            }
        }
        
        if coassicurazioni.count > 1 {
            if values["nome_riparto_2"] == nil {
                values["nome_riparto_2"] = coassicurazioni[1].compagnia
            }
        }
        
        // IBAN
        if values["iban"] == nil {
            // IBAN potrebbe essere nel sinistro o da implementare
            values["iban"] = ""
        }
        
        // Data generazione (per firma)
        let oggi = Date()
        let (giorno, mese, anno) = TextFitter.splitDate(oggi)
        
        if values["data_giorno"] == nil {
            values["data_giorno"] = giorno
        }
        if values["data_mese"] == nil {
            values["data_mese"] = mese
        }
        if values["data_anno"] == nil {
            values["data_anno"] = anno
        }
        if values["data_firma"] == nil {
            values["data_firma"] = TextFitter.formatDate(oggi)
        }
        
        return values
    }
    
    /// Calcola l'importo per l'atto (sempre la stima del danno)
    func calculateImporto(sinistro: Sinistro, perizia: Perizia?, sottotipo: SottotipoAtto) -> Double {
        // In atto inseriamo sempre la stima del danno (che sia indennizzabile o meno)
        // Se è indennizzabile: proposta liquidativa nell'atto di liquidazione
        // Se non è indennizzabile: importo a riserva nell'atto di accertamento
        
        // Priorità: usa l'importo già calcolato e salvato in perizia (evita ricalcoli e mismatch)
        if let perizia = perizia,
           let salvato = perizia.stimaDannoIndennizzabile?.doubleValue,
           salvato > 0 {
            return salvato
        }
        
        // Fallback: valori da Excel
        // Per liquidazione: usa liquidato o stimaDanno
        if sottotipo == .liquidazione {
            return sinistro.liquidato?.doubleValue ?? sinistro.stimaDanno?.doubleValue ?? 0
        } else {
            // Per accertamento: usa stimaDanno o dannoAccertato
            return sinistro.stimaDanno?.doubleValue ?? sinistro.dannoAccertato?.doubleValue ?? 0
        }
    }
    
    // MARK: - Drawing
    
    private func drawFields(
        _ fields: [AttoFieldTemplate],
        values: [String: Any],
        context: CGContext,
        pageHeight: CGFloat
    ) {
        for field in fields {
            guard let value = values[field.name] else { continue }
            
            // Converti rect (PDF ha origine in basso a sinistra)
            let rect = field.rect.cgRect
            
            switch field.type {
            case .checkbox:
                drawCheckbox(
                    value: value as? Bool ?? false,
                    rect: rect,
                    context: context
                )
                
            case .text, .number, .currency, .date, .dateDay, .dateMonth, .dateYear, .ibanFull, .ibanChar, .signature:
                let textValue = formatValue(value, type: field.type)
                drawText(
                    text: textValue,
                    rect: rect,
                    field: field,
                    context: context
                )
            }
        }
    }
    
    private func formatValue(_ value: Any, type: AttoFieldType) -> String {
        switch type {
        case .currency:
            if let number = value as? Double {
                return TextFitter.formatCurrency(Decimal(number))
            } else if let decimal = value as? Decimal {
                return TextFitter.formatCurrency(decimal)
            }
            return String(describing: value)
            
        case .number:
            if let number = value as? Double {
                return String(format: "%.2f", number)
            }
            return String(describing: value)
            
        case .date:
            if let date = value as? Date {
                return TextFitter.formatDate(date)
            }
            return String(describing: value)
            
        default:
            if let str = value as? String {
                return str
            }
            return String(describing: value)
        }
    }
    
    private func drawCheckbox(
        value: Bool,
        rect: CGRect,
        context: CGContext
    ) {
        TextFitter.drawCheckbox(checked: value, in: rect, context: context)
    }
    
    private func drawText(
        text: String,
        rect: CGRect,
        field: AttoFieldTemplate,
        context: CGContext
    ) {
        var options = TextFitter.FitOptions.default
        options.alignment = field.alignment.nsTextAlignment
        
        if let maxLines = field.maxLines {
            options.maxLines = maxLines
        }
        
        if let fontSize = field.fontSize {
            options.maxFontSize = fontSize
            options.minFontSize = fontSize * 0.5
        }
        
        // Applica formattazione speciale in base al nome del campo
        let formattedText = applyFieldFormatting(text: text, fieldName: field.name)
        let useBold = shouldUseBold(fieldName: field.name)
        
        options.useBold = useBold
        
        textFitter.drawText(formattedText, in: rect, context: context, options: options)
    }
    
    // MARK: - Formattazione Speciale
    
    /// Applica formattazione speciale (es. CAPSLOCK per nome assicurato)
    private func applyFieldFormatting(text: String, fieldName: String) -> String {
        let nameLower = fieldName.lowercased()
        
        // CAPSLOCK per nome assicurato
        if nameLower.contains("nome_assicurato") || 
           nameLower.contains("assicurato") && nameLower.contains("nome") ||
           nameLower == "assicurato" {
            return text.uppercased()
        }
        
        // CAPSLOCK per beneficiario
        if nameLower.contains("beneficiario") {
            return text.uppercased()
        }
        
        return text
    }
    
    /// Determina se il campo deve usare font bold
    private func shouldUseBold(fieldName: String) -> Bool {
        let nameLower = fieldName.lowercased()
        
        // Grassetto per: nome, importo a numero, iban, codice_fiscale, p_iva
        let boldFields = [
            "nome", "assicurato", "beneficiario",
            "importo_numero", "importo", "liquidato", "accertato", "indennizzo",
            "iban", "iban_full",
            "codice_fiscale", "cf",
            "p_iva", "partita_iva", "piva"
        ]
        
        for boldField in boldFields {
            if nameLower.contains(boldField) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Sottocompagnie Cattolica
    
    enum SottocompagniaCattolica {
        case cattolica
        case tua
        case fata
        case bcc
        case abb
    }
    
    /// Determina la sottocompagnia Cattolica dal tipo polizza
    /// Priorità: se c'è "Cattolica" insieme a un'altra, usa l'altra
    private func determinaSottocompagniaCattolica(tipoPolizza: String?) -> SottocompagniaCattolica {
        guard let tipo = tipoPolizza?.lowercased() else { return .cattolica }
        
        // Controlla prima le altre sottocompagnie (hanno priorità su Cattolica)
        if tipo.contains("tua") {
            return .tua
        }
        if tipo.contains("fata") {
            return .fata
        }
        if tipo.contains("bcc") {
            return .bcc
        }
        if tipo.contains("abb") {
            return .abb
        }
        
        // Default: Cattolica
        return .cattolica
    }
}
