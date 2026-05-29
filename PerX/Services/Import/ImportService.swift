import Foundation
import CoreData
import UniformTypeIdentifiers

class ImportService: ObservableObject {
    static var shared: ImportService!
    
    // MARK: - Strutture dati per l'import
    
    struct ImportData {
        let headers: [String]
        let rows: [[String]]
        let fileName: String
    }
    
    struct ColumnMapping {
        let sourceColumn: String
        let targetField: DatabaseField
        let isRequired: Bool
    }
    
    struct StateMapping {
        let sourceState: String
        let targetState: String
    }
    
    struct FieldChange {
        let field: DatabaseField
        let oldValue: String?
        let newValue: String
        let isAdded: Bool // true se il campo era nil/vuoto, false se è stato modificato
    }
    
    struct SinistroChange {
        let riferimento: String
        let isNew: Bool
        let changes: [FieldChange]
    }
    
    struct ImportResult {
        let processed: Int
        let updated: Int
        let created: Int
        let revoked: Int
        let errors: [String]
        let sinistroChanges: [SinistroChange]
        
        var summary: String {
            var parts: [String] = []
            if processed > 0 {
                parts.append("\(processed) sinistri processati")
            }
            if created > 0 {
                parts.append("\(created) creati")
            }
            if updated > 0 {
                parts.append("\(updated) aggiornati")
            }
            if revoked > 0 {
                parts.append("\(revoked) revocati")
            }
            if !errors.isEmpty {
                parts.append("\(errors.count) errori")
            }
            return parts.joined(separator: ", ")
        }
        
        var hasErrors: Bool {
            !errors.isEmpty
        }
    }
    
    enum DatabaseField: String, CaseIterable {
        case riferimento = "riferimento"
        case agenzia = "agenzia"
        case stato = "stato"
        case dataAperturaGestione = "dataAperturaGestione"
        case dataInvioAtto = "dataInvioAtto"
        case dataChiusura = "dataChiusura"
        case dataRevoca = "dataRevoca"
        case dataSinistro = "dataSinistro"
        case numeroSinistroCompagnia = "numeroSinistroCompagnia"
        case nomeCompagnia = "nomeCompagnia"
        case nomeAssicurato = "nomeAssicurato"
        case telefonoAssicurato = "telefonoAssicurato"
        case emailAssicurato = "emailAssicurato"
        case indirizzoAssicurato = "indirizzoAssicurato"
        case richiesta = "richiesta"
        case liquidato = "liquidato"
        case dannoAccertato = "dannoAccertato"
        case dannoAccertatoNetto = "dannoAccertatoNetto"
        // Nuovi campi da Excel
        case gruppo = "gruppo"
        case area = "area"
        case dataDenuncia = "dataDenuncia"
        case dataIncarico = "dataIncarico"
        case dataSopralluogo = "dataSopralluogo"
        case numeroPolizza = "numeroPolizza"
        case tipoPolizza = "tipoPolizza"
        case definizione = "definizione"
        case stimaDanno = "stimaDanno"
        case codiceAgenzia = "codiceAgenzia"
        case nomeContraente = "nomeContraente"
        case telefonoContraente = "telefonoContraente"
        case emailContraente = "emailContraente"
        case indirizzoContraente = "indirizzoContraente"
        case nomeDanneggiato = "nomeDanneggiato"
        case telefonoDanneggiato = "telefonoDanneggiato"
        case emailDanneggiato = "emailDanneggiato"
        case indirizzoDanneggiato = "indirizzoDanneggiato"
        case emailAgenzia = "emailAgenzia"
        case telefonoAgenzia = "telefonoAgenzia"
        
        var displayName: String {
            switch self {
            case .riferimento: return "Riferimento Sinistro"
            case .agenzia: return "Agenzia"
            case .stato: return "Stato"
            case .dataAperturaGestione: return "Data Apertura/Gestione"
            case .dataInvioAtto: return "Data Invio Atto"
            case .dataChiusura: return "Data Chiusura"
            case .dataRevoca: return "Data Revoca"
            case .dataSinistro: return "Data Sinistro"
            case .numeroSinistroCompagnia: return "Numero Sinistro Compagnia"
            case .nomeCompagnia: return "Nome Compagnia"
            case .nomeAssicurato: return "Nome Assicurato"
            case .telefonoAssicurato: return "Telefono Assicurato"
            case .emailAssicurato: return "Email Assicurato"
            case .indirizzoAssicurato: return "Indirizzo Assicurato"
            case .richiesta: return "Importo Richiesto"
            case .liquidato: return "Importo Liquidato"
            case .dannoAccertato: return "Danno Accertato"
            case .dannoAccertatoNetto: return "Danno Accertato Netto"
            case .gruppo: return "Gruppo"
            case .area: return "Area"
            case .dataDenuncia: return "Data Denuncia"
            case .dataIncarico: return "Data Incarico"
            case .dataSopralluogo: return "Data Sopralluogo"
            case .numeroPolizza: return "Numero Polizza"
            case .tipoPolizza: return "Tipo Polizza"
            case .definizione: return "Definizione"
            case .stimaDanno: return "Stima del Danno"
            case .codiceAgenzia: return "Codice Agenzia"
            case .nomeContraente: return "Nome Contraente"
            case .telefonoContraente: return "Telefono Contraente"
            case .emailContraente: return "Email Contraente"
            case .indirizzoContraente: return "Indirizzo Contraente"
            case .nomeDanneggiato: return "Nome Danneggiato"
            case .telefonoDanneggiato: return "Telefono Danneggiato"
            case .emailDanneggiato: return "Email Danneggiato"
            case .indirizzoDanneggiato: return "Indirizzo Danneggiato"
            case .emailAgenzia: return "Email Agenzia"
            case .telefonoAgenzia: return "Telefono Agenzia"
            }
        }
        
        var isRequired: Bool {
            return self == .riferimento // Solo il riferimento è obbligatorio
        }
        
        var isDate: Bool {
            switch self {
            case .dataAperturaGestione, .dataInvioAtto, .dataChiusura, .dataRevoca, .dataSinistro,
                 .dataDenuncia, .dataIncarico, .dataSopralluogo:
                return true
            default:
                return false
            }
        }
        
        var isAmount: Bool {
            switch self {
            case .richiesta, .liquidato, .dannoAccertato, .dannoAccertatoNetto, .stimaDanno:
                return true
            default:
                return false
            }
        }
    }
    
    private let context: NSManagedObjectContext
    private let dateFormatter: DateFormatter
    private let importedSinistriKey = "ImportService.importedSinistri"
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        loadSavedMappings()
    }
    
    // MARK: - Gestione flag import
    
    private func markSinistroAsImported(riferimento: String) {
        var imported = getImportedSinistri()
        imported.insert(riferimento)
        UserDefaults.standard.set(Array(imported), forKey: importedSinistriKey)
    }
    
    static func isSinistroImported(riferimento: String) -> Bool {
        guard let imported = UserDefaults.standard.array(forKey: "ImportService.importedSinistri") as? [String] else {
            return false
        }
        return Set(imported).contains(riferimento)
    }
    
    private func getImportedSinistri() -> Set<String> {
        guard let imported = UserDefaults.standard.array(forKey: importedSinistriKey) as? [String] else {
            return []
        }
        return Set(imported)
    }
    
    static func configure(with context: NSManagedObjectContext) {
        shared = ImportService(context: context)
    }
    
    // MARK: - Persistenza mappings
    
    @Published var savedColumnMappings: [String: String] = [:] // sourceColumn -> targetField
    @Published var savedStateMappings: [String: String] = [:] // sourceState -> targetState
    
    private func loadSavedMappings() {
        if let mappings = UserDefaults.standard.dictionary(forKey: "ImportColumnMappings") as? [String: String] {
            savedColumnMappings = mappings
        }
        
        if let mappings = UserDefaults.standard.dictionary(forKey: "ImportStateMappings") as? [String: String] {
            savedStateMappings = mappings
        }
    }
    
    private func saveMappings() {
        UserDefaults.standard.set(savedColumnMappings, forKey: "ImportColumnMappings")
        UserDefaults.standard.set(savedStateMappings, forKey: "ImportStateMappings")
    }
    
    /// Normalizza un nome per il matching (case-insensitive, rimozione spazi extra)
    private func normalizeName(_ name: String) -> String {
        return name.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    
    /// Trova un mapping salvato per una colonna (con matching fuzzy)
    func findSavedColumnMapping(for columnName: String) -> ImportService.DatabaseField? {
        // Prima prova match esatto
        if let targetFieldRaw = savedColumnMappings[columnName],
           let targetField = DatabaseField(rawValue: targetFieldRaw) {
            return targetField
        }
        
        // Poi prova match normalizzato
        let normalized = normalizeName(columnName)
        for (savedColumn, targetFieldRaw) in savedColumnMappings {
            if normalizeName(savedColumn) == normalized,
               let targetField = DatabaseField(rawValue: targetFieldRaw) {
                return targetField
            }
        }
        
        // Infine prova match parziale (contiene)
        for (savedColumn, targetFieldRaw) in savedColumnMappings {
            let savedNormalized = normalizeName(savedColumn)
            if normalized.contains(savedNormalized) || savedNormalized.contains(normalized),
               normalized.count > 3, // Evita match troppo corti
               let targetField = DatabaseField(rawValue: targetFieldRaw) {
                return targetField
            }
        }
        
        return nil
    }
    
    /// Trova un mapping salvato per uno stato (con matching fuzzy)
    func findSavedStateMapping(for stateName: String) -> String? {
        // Prima prova match esatto
        if let targetState = savedStateMappings[stateName] {
            return targetState
        }
        
        // Poi prova match normalizzato
        let normalized = normalizeName(stateName)
        for (savedState, targetState) in savedStateMappings {
            if normalizeName(savedState) == normalized {
                return targetState
            }
        }
        
        // Infine prova match parziale (contiene)
        for (savedState, targetState) in savedStateMappings {
            let savedNormalized = normalizeName(savedState)
            if normalized.contains(savedNormalized) || savedNormalized.contains(normalized),
               normalized.count > 3 { // Evita match troppo corti
                return targetState
            }
        }
        
        return nil
    }
    
    /// Salva un mapping colonna-campo
    func saveColumnMapping(columnName: String, targetField: DatabaseField) {
        savedColumnMappings[columnName] = targetField.rawValue
        saveMappings()
    }
    
    /// Salva un mapping stato-stato
    func saveStateMapping(sourceState: String, targetState: String) {
        savedStateMappings[sourceState] = targetState
        saveMappings()
    }
    
    // MARK: - Lettura file
    
    func readFile(at url: URL) async throws -> ImportData {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "csv":
            return try await readCSVFile(at: url)
        case "xlsx", "xls":
            return try await readExcelFile(at: url)
        default:
            throw ImportError.unsupportedFileType(fileExtension)
        }
    }
    
    private func readCSVFile(at url: URL) async throws -> ImportData {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        guard !lines.isEmpty else {
            throw ImportError.emptyFile
        }
        
        let headers = parseCSVLine(lines[0])
        let rows = lines.dropFirst().map { parseCSVLine($0) }
        
        return ImportData(
            headers: headers,
            rows: rows,
            fileName: url.lastPathComponent
        )
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
            
            i = line.index(after: i)
        }
        
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
    
    private func readExcelFile(at url: URL) async throws -> ImportData {
        return try await GenericExcelReader.shared.readExcelFile(at: url)
    }
    
    // MARK: - Processing dati
    
    func processImport(
        data: ImportData,
        columnMappings: [ColumnMapping],
        stateMappings: [StateMapping],
        revokeMissing: Bool,
        context: NSManagedObjectContext
    ) async throws -> ImportResult {
        
        // Salva i mapping per usi futuri
        for mapping in columnMappings {
            savedColumnMappings[mapping.sourceColumn] = mapping.targetField.rawValue
        }
        
        for mapping in stateMappings {
            savedStateMappings[mapping.sourceState] = mapping.targetState
        }
        
        saveMappings()
        
        var processed = 0
        var updated = 0
        var created = 0
        var revoked = 0
        var errors: [String] = []
        var sinistroChanges: [SinistroChange] = []
        
        let allRiferimentiInFile = Set(data.rows.compactMap { row -> String? in
            guard let riferimentoMapping = columnMappings.first(where: { $0.targetField == .riferimento }),
                  let riferimentoIndex = data.headers.firstIndex(of: riferimentoMapping.sourceColumn),
                  riferimentoIndex < row.count else {
                return nil
            }
            let riferimento = row[riferimentoIndex].trimmingCharacters(in: .whitespaces)
            return riferimento.isEmpty ? nil : riferimento
        })
        
        // Processa in batch per evitare blocchi con file grandi
        let batchSize = 50
        let totalRows = data.rows.count
        
        for batchStart in stride(from: 0, to: totalRows, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalRows)
            let batch = Array(data.rows[batchStart..<batchEnd])
            
            // Processa il batch
            for (localIndex, row) in batch.enumerated() {
                let globalIndex = batchStart + localIndex
                do {
                    let change = try await processRowInternal(
                        row: row,
                        headers: data.headers,
                        columnMappings: columnMappings,
                        stateMappings: stateMappings,
                        context: context
                    )
                    
                    processed += 1
                    if change.isNew {
                        created += 1
                    } else {
                        updated += 1
                    }
                    
                    // Limita il numero di cambiamenti salvati per evitare problemi di memoria
                    if sinistroChanges.count < 500 {
                        sinistroChanges.append(change)
                    }
                    
                } catch {
                    errors.append("Riga \(globalIndex + 2): \(error.localizedDescription)")
                }
            }
            
            // Salva periodicamente il contesto
            if context.hasChanges {
                try context.save()
            }
            
            // Yield al main thread per permettere aggiornamenti UI
            await Task.yield()
            
            // Piccola pausa per non sovraccaricare il sistema
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Gestione revoca sinistri mancanti
        if revokeMissing {
            let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
            // Escludi quelli già revocati per non toccarli
            fetchRequest.predicate = NSPredicate(format: "NOT (riferimento IN %@) AND stato != %@", allRiferimentiInFile, "Revocata")
            
            do {
                let sinistriDaRevocare = try context.fetch(fetchRequest)
                for sinistro in sinistriDaRevocare {
                    sinistro.stato = "Revocata"
                    sinistro.dataRevoca = Date()
                    revoked += 1
                }
                print("[Import] Revocati \(revoked) sinistri non presenti nel file.")
            } catch {
                errors.append("Errore durante la revoca dei sinistri mancanti: \(error.localizedDescription)")
            }
        }
        
        // Salva le modifiche
        if context.hasChanges {
            try context.save()
        }
        
        return ImportResult(
            processed: processed,
            updated: updated,
            created: created,
            revoked: revoked,
            errors: errors,
            sinistroChanges: sinistroChanges
        )
    }
    
    func processRowPreview(
        row: [String],
        headers: [String],
        columnMappings: [ColumnMapping],
        stateMappings: [StateMapping],
        context: NSManagedObjectContext
    ) async throws -> SinistroChange {
        // Estrai il riferimento (obbligatorio)
        guard let riferimentoMapping = columnMappings.first(where: { $0.targetField == .riferimento }),
              let riferimentoIndex = headers.firstIndex(of: riferimentoMapping.sourceColumn),
              riferimentoIndex < row.count else {
            throw ImportError.missingRequiredField("riferimento")
        }
        
        let riferimento = row[riferimentoIndex].trimmingCharacters(in: .whitespaces)
        guard !riferimento.isEmpty else {
            throw ImportError.emptyRequiredField("riferimento")
        }
        
        // Valida formato riferimento: deve essere esattamente 7 cifre numeriche
        guard isValidRiferimentoFormat(riferimento) else {
            throw ImportError.invalidRiferimentoFormat(riferimento)
        }
        
        // Cerca il sinistro esistente (senza crearlo)
        let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        let existingSinistri = try context.fetch(fetchRequest)
        let sinistro: Sinistro?
        let isNew: Bool
        
        if let existing = existingSinistri.first {
            sinistro = existing
            isNew = false
        } else {
            sinistro = nil
            isNew = true
        }
        
        // Traccia i cambiamenti senza applicarli
        var changes: [FieldChange] = []
        
        for mapping in columnMappings {
            guard let columnIndex = headers.firstIndex(of: mapping.sourceColumn),
                  columnIndex < row.count else {
                continue
            }
            
            let value = row[columnIndex].trimmingCharacters(in: .whitespaces)
            
            if !value.isEmpty {
                // Ottieni il valore corrente
                let oldValue = sinistro != nil ? getCurrentFieldValue(sinistro: sinistro!, field: mapping.targetField) : nil
                
                // Traccia il cambiamento solo se il valore è diverso
                let normalizedOldValue = oldValue?.trimmingCharacters(in: .whitespaces) ?? ""
                let normalizedNewValue = value.trimmingCharacters(in: .whitespaces)
                
                if normalizedOldValue != normalizedNewValue {
                    let isAdded = normalizedOldValue.isEmpty
                    changes.append(FieldChange(
                        field: mapping.targetField,
                        oldValue: oldValue,
                        newValue: normalizedNewValue,
                        isAdded: isAdded
                    ))
                }
            }
        }
        
        return SinistroChange(
            riferimento: riferimento,
            isNew: isNew,
            changes: changes
        )
    }
    
    func processRowInternal(
        row: [String],
        headers: [String],
        columnMappings: [ColumnMapping],
        stateMappings: [StateMapping],
        context: NSManagedObjectContext
    ) async throws -> SinistroChange {
        
        // Estrai il riferimento (obbligatorio)
        guard let riferimentoMapping = columnMappings.first(where: { $0.targetField == .riferimento }),
              let riferimentoIndex = headers.firstIndex(of: riferimentoMapping.sourceColumn),
              riferimentoIndex < row.count else {
            throw ImportError.missingRequiredField("riferimento")
        }
        
        let riferimento = row[riferimentoIndex].trimmingCharacters(in: .whitespaces)
        guard !riferimento.isEmpty else {
            throw ImportError.emptyRequiredField("riferimento")
        }
        
        // Valida formato riferimento: deve essere esattamente 7 cifre numeriche
        guard isValidRiferimentoFormat(riferimento) else {
            throw ImportError.invalidRiferimentoFormat(riferimento)
        }
        
        // Verifica limite importazione sinistri recenti
        if !RiferimentoValidator.canImport(riferimento) {
            if let year = RiferimentoValidator.extractYear(from: riferimento) {
                throw ImportError.invalidRiferimentoFormat("Sinistro \(riferimento) rifiutato: anno \(year) non è recente (solo anno corrente e precedente)")
            } else {
                throw ImportError.invalidRiferimentoFormat("Sinistro \(riferimento) rifiutato: non è recente")
            }
        }
        
        // Cerca o crea il sinistro
        let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        let existingSinistri = try context.fetch(fetchRequest)
        let sinistro: Sinistro
        let isNew: Bool
        
        if let existing = existingSinistri.first {
            sinistro = existing
            isNew = false
        } else {
            sinistro = Sinistro(context: context)
            sinistro.riferimento = riferimento
            isNew = true
        }

        // Assegna owner/assegnatario all'utente che sta importando (anche in caso di update)
        await applyImportOwnership(to: sinistro, isNew: isNew)
        
        // Marca il sinistro come importato
        markSinistroAsImported(riferimento: riferimento)
        
        // Traccia i cambiamenti
        var changes: [FieldChange] = []
        
        // IMPORTANTE: Ordina i mapping per garantire che alcuni campi siano processati prima di altri
        // In particolare: nomeCompagnia DEVE essere processato PRIMA di agenzia (per il parsing corretto)
        let sortedMappings = columnMappings.sorted { m1, m2 in
            let priorityOrder: [DatabaseField] = [
                .riferimento,      // Prima il riferimento
                .nomeCompagnia,    // Poi la compagnia (necessaria per parsing agenzia)
                .gruppo,           // Poi il gruppo
                .codiceAgenzia,    // Poi il codice agenzia
                .agenzia           // Poi l'agenzia (dopo compagnia!)
            ]
            let p1 = priorityOrder.firstIndex(of: m1.targetField) ?? 999
            let p2 = priorityOrder.firstIndex(of: m2.targetField) ?? 999
            return p1 < p2
        }
        
        // Log dei mapping (solo per primo sinistro per evitare spam)
        if riferimento.hasSuffix("1") || riferimento.hasSuffix("0") {
            print("[Import] 📝 Mapping colonne per \(riferimento):")
            for mapping in sortedMappings {
                if let idx = headers.firstIndex(of: mapping.sourceColumn), idx < row.count {
                    print("[Import]   '\(mapping.sourceColumn)' -> \(mapping.targetField.rawValue) = '\(row[idx])'")
                }
            }
        }
        
        // Applica tutti i mapping e traccia i cambiamenti
        for mapping in sortedMappings {
            guard let columnIndex = headers.firstIndex(of: mapping.sourceColumn),
                  columnIndex < row.count else {
                continue
            }
            
            let value = row[columnIndex].trimmingCharacters(in: .whitespaces)
            
            if !value.isEmpty {
                // Ottieni il valore corrente
                let oldValue = getCurrentFieldValue(sinistro: sinistro, field: mapping.targetField)
                
                // Applica il nuovo valore
                try applyFieldValue(
                    sinistro: sinistro,
                    field: mapping.targetField,
                    value: value,
                    stateMappings: stateMappings,
                    context: context
                )
                
                // Traccia il cambiamento solo se il valore è diverso
                let normalizedOldValue = oldValue?.trimmingCharacters(in: .whitespaces) ?? ""
                let normalizedNewValue = value.trimmingCharacters(in: .whitespaces)
                
                if normalizedOldValue != normalizedNewValue {
                    let isAdded = normalizedOldValue.isEmpty
                    changes.append(FieldChange(
                        field: mapping.targetField,
                        oldValue: oldValue,
                        newValue: normalizedNewValue,
                        isAdded: isAdded
                    ))
                }
            }
        }
        
        // Valida tutte le date dopo l'import
        sinistro.validateAllDates()
        
        return SinistroChange(
            riferimento: riferimento,
            isNew: isNew,
            changes: changes
        )
    }

    // MARK: - Ownership (Import sinistri da file / Excel / CSV)
    
    private func applyImportOwnership(to sinistro: Sinistro, isNew: Bool) async {
        let currentEmail: String? = await MainActor.run {
            GoogleAuthService.shared.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let email = currentEmail, !email.isEmpty else { return }
        
        let displayName: String = {
            let fromDefaults = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fromDefaults, !fromDefaults.isEmpty { return fromDefaults }
            return email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
        }()
        
        // Override esplicito: chi importa diventa owner/assegnatario
        sinistro.ownerEmail = email
        sinistro.assignedToUserEmail = email
        sinistro.assignedToUserName = displayName
        
        // Data assegnazione coerente
        if isNew || sinistro.dataAssegnazione == nil {
            sinistro.setDataAssegnazione(Date())
        }
    }
    
    private func getCurrentFieldValue(sinistro: Sinistro, field: DatabaseField) -> String? {
        switch field {
        case .riferimento: return sinistro.riferimento
        case .agenzia: return sinistro.agenzia
        case .stato: return sinistro.stato
        case .dataAperturaGestione: return sinistro.dataAperturaGestione.map { formatDate($0) }
        case .dataInvioAtto: return sinistro.dataInvioAtto.map { formatDate($0) }
        case .dataChiusura: return sinistro.dataChiusura.map { formatDate($0) }
        case .dataRevoca: return sinistro.dataRevoca.map { formatDate($0) }
        case .dataSinistro: return sinistro.dataSinistro.map { formatDate($0) }
        case .numeroSinistroCompagnia: return sinistro.numeroSinistroCompagnia
        case .nomeCompagnia: return sinistro.nomeCompagnia
        case .nomeAssicurato: return sinistro.nomeAssicurato
        case .telefonoAssicurato: return sinistro.telefonoAssicurato
        case .emailAssicurato: return sinistro.emailAssicurato
        case .indirizzoAssicurato: return sinistro.indirizzoAssicurato
        case .richiesta: return sinistro.richiesta?.stringValue
        case .liquidato: return sinistro.liquidato?.stringValue
        case .dannoAccertato: return sinistro.dannoAccertato?.stringValue
        case .dannoAccertatoNetto: return sinistro.dannoAccertatoNetto?.stringValue
        case .gruppo: return sinistro.gruppo
        case .area: return sinistro.area
        case .dataDenuncia: return sinistro.dataDenuncia.map { formatDate($0) }
        case .dataIncarico: return sinistro.dataIncarico.map { formatDate($0) }
        case .dataSopralluogo: return sinistro.dataSopralluogo.map { formatDate($0) }
        case .numeroPolizza: return sinistro.numeroPolizza
        case .tipoPolizza: return sinistro.tipoPolizza
        case .definizione: return sinistro.definizione
        case .stimaDanno: return sinistro.stimaDanno?.stringValue
        case .codiceAgenzia: return sinistro.codiceAgenzia
        case .nomeContraente: return sinistro.nomeContraente
        case .telefonoContraente: return sinistro.telefonoContraente
        case .emailContraente: return sinistro.emailContraente
        case .indirizzoContraente: return sinistro.indirizzoContraente
        case .nomeDanneggiato: return sinistro.nomeDanneggiato
        case .telefonoDanneggiato: return sinistro.telefonoDanneggiato
        case .emailDanneggiato: return sinistro.emailDanneggiato
        case .indirizzoDanneggiato: return sinistro.indirizzoDanneggiato
        case .emailAgenzia: return sinistro.emailAgenzia
        case .telefonoAgenzia: return sinistro.telefonoAgenzia
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
    
    private func applyFieldValue(
        sinistro: Sinistro,
        field: DatabaseField,
        value: String,
        stateMappings: [StateMapping],
        context: NSManagedObjectContext
    ) throws {
        
        switch field {
        case .riferimento:
            sinistro.riferimento = value
            
        case .agenzia:
            // Se abbiamo anche il nome compagnia, parsiamo l'agenzia
            let capitalizedValue = capitalizeFirstLetter(value)
            print("[Import] 🏢 Agenzia input: '\(value)' (compagnia: \(sinistro.nomeCompagnia ?? "nil"))")
            if let nomeCompagnia = sinistro.nomeCompagnia {
                let parsed = AgencyReaderHelper.shared.parseAgenzia(capitalizedValue, compagnia: nomeCompagnia)
                if !parsed.codice.isEmpty {
                    sinistro.codiceAgenzia = parsed.codice.uppercased()
                }
                sinistro.agenzia = parsed.nome
                print("[Import] 🏢 Agenzia parsed: codice='\(parsed.codice)' nome='\(parsed.nome)'")
            } else {
                sinistro.agenzia = capitalizedValue
                print("[Import] 🏢 Agenzia (no compagnia): '\(capitalizedValue)'")
            }
            
        case .stato:
            // Applica mapping stato se disponibile (case-insensitive + trimming)
            let normalizedValue = value.trimmingCharacters(in: .whitespaces).lowercased()
            let mappedState = stateMappings.first(where: { 
                $0.sourceState.trimmingCharacters(in: .whitespaces).lowercased() == normalizedValue 
            })?.targetState ?? capitalizeFirstLetter(value)
            sinistro.stato = mappedState
            print("[Import] 📊 Stato: '\(value)' -> '\(mappedState)'")
            
        case .dataAperturaGestione:
            sinistro.dataAperturaGestione = parseDate(value)
            
        case .dataInvioAtto:
            sinistro.dataInvioAtto = parseDate(value)
            
        case .dataChiusura:
            sinistro.dataChiusura = parseDate(value)
            
        case .dataRevoca:
            sinistro.dataRevoca = parseDate(value)
            
        case .dataSinistro:
            sinistro.setDataSinistro(parseDate(value))
            
        case .numeroSinistroCompagnia:
            // Numero sinistro sempre in UPPERCASE
            sinistro.numeroSinistroCompagnia = value.uppercased()
            print("[Import] 📋 Numero Sinistro: '\(value)' -> '\(value.uppercased())'")
            
        case .nomeCompagnia:
            sinistro.nomeCompagnia = capitalizeFirstLetter(value)
            
        case .nomeAssicurato:
            // Assegna lo stesso valore ai tre ruoli principali
            let capitalizedValue = capitalizeFirstLetter(value)
            sinistro.nomeContraente = capitalizedValue
            sinistro.nomeAssicurato = capitalizedValue
            sinistro.nomeDanneggiato = capitalizedValue
            // Manteniamo anche il campo legacy per retrocompatibilità
            sinistro.nomeAssicurato_legacy = capitalizedValue
            
        case .telefonoAssicurato:
            sinistro.telefonoAssicurato_legacy = value
            
        case .emailAssicurato:
            sinistro.emailAssicurato_legacy = value.lowercased()
            
        case .indirizzoAssicurato:
            sinistro.indirizzoAssicurato_legacy = capitalizeFirstLetter(value)
            
        case .richiesta:
            sinistro.richiesta = parseDecimal(value)
            
        case .liquidato:
            sinistro.liquidato = parseDecimal(value)
            
        case .dannoAccertato:
            sinistro.dannoAccertato = parseDecimal(value)
            
        case .dannoAccertatoNetto:
            sinistro.dannoAccertatoNetto = parseDecimal(value)
            
        case .gruppo:
            sinistro.gruppo = capitalizeFirstLetter(value)
            
        case .area:
            sinistro.area = capitalizeFirstLetter(value)
            
        case .dataDenuncia:
            sinistro.setDataDenuncia(parseDate(value))
            
        case .dataIncarico:
            sinistro.dataIncarico = parseDate(value)
            
        case .dataSopralluogo:
            sinistro.dataSopralluogo = parseDate(value)
            
        case .numeroPolizza:
            sinistro.numeroPolizza = value
            
        case .tipoPolizza:
            sinistro.tipoPolizza = capitalizeFirstLetter(value)
            
        case .definizione:
            // Non sovrascrivere se è stata impostata manualmente
            if !sinistro.definizioneManuale {
                sinistro.definizione = capitalizeFirstLetter(value)
            }
            
        case .stimaDanno:
            sinistro.stimaDanno = parseDecimal(value)
            
        case .codiceAgenzia:
            sinistro.codiceAgenzia = value.uppercased()
            
        case .nomeContraente:
            sinistro.nomeContraente = capitalizeFirstLetter(value)
            
        case .telefonoContraente:
            sinistro.telefonoContraente = value
            
        case .emailContraente:
            sinistro.emailContraente = value.lowercased()
            
        case .indirizzoContraente:
            sinistro.indirizzoContraente = capitalizeFirstLetter(value)
            
        case .nomeDanneggiato:
            sinistro.nomeDanneggiato = capitalizeFirstLetter(value)
            
        case .telefonoDanneggiato:
            sinistro.telefonoDanneggiato = value
            
        case .emailDanneggiato:
            sinistro.emailDanneggiato = value.lowercased()
            
        case .indirizzoDanneggiato:
            sinistro.indirizzoDanneggiato = capitalizeFirstLetter(value)
            
        case .emailAgenzia:
            sinistro.emailAgenzia = value.lowercased()
            
        case .telefonoAgenzia:
            sinistro.telefonoAgenzia = value
        }
    }
    
    // MARK: - Validazione Riferimento
    
    /// Valida il formato del riferimento: deve essere esattamente 7 cifre numeriche
    private func isValidRiferimentoFormat(_ riferimento: String) -> Bool {
        // Deve essere esattamente 7 caratteri e tutti numerici
        guard riferimento.count == 7 else { return false }
        return riferimento.allSatisfy { $0.isNumber }
    }
    
    // MARK: - Utility per parsing
    
    /// Capitalizza una stringa con tutte le iniziali maiuscole
    private func capitalizeFirstLetter(_ string: String) -> String {
        guard !string.isEmpty else { return string }
        return string.components(separatedBy: " ")
            .map { word in
                guard !word.isEmpty else { return word }
                let first = word.prefix(1).uppercased()
                let rest = word.dropFirst().lowercased()
                return first + rest
            }
            .joined(separator: " ")
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 1) Formati "classici"
        let formats = [
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "yyyy-MM-dd",
            "dd-MM-yyyy",
            "dd/MM/yy",
            "MM/dd/yy",
            // Con ora
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS"
        ]
        
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "it_IT")
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        
        // 2) ISO 8601 (con timezone)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let d = iso.date(from: trimmed) { return d }
        
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [
            .withInternetDateTime
        ]
        if let d = isoNoFrac.date(from: trimmed) { return d }
        
        // 3) Serial date Excel (1900 date system). Spesso le date arrivano come numeri (es. "45234" / "45234.5").
        // Accetta solo range realistico per evitare false interpretazioni (es. "20260121").
        let numericCandidate = trimmed.replacingOccurrences(of: ",", with: ".")
        if let serial = Double(numericCandidate), serial >= 20_000, serial <= 80_000 {
            return excelSerialDateToDate(serial)
        }
        
        return nil
    }
    
    /// Converte un serial date Excel (sistema 1900) in `Date`.
    /// - Note: Excel considera erroneamente il 1900 bisestile; i serial >= 60 vanno compensati di 1 giorno.
    private func excelSerialDateToDate(_ serial: Double) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        
        let wholeDays = Int(floor(serial))
        let fraction = serial - Double(wholeDays)
        
        // Base: 1899-12-31 così che serial 1 -> 1900-01-01
        guard let base = DateComponents(calendar: calendar, year: 1899, month: 12, day: 31).date else {
            return nil
        }
        
        var days = wholeDays
        if days >= 60 { days -= 1 } // compensazione bug 1900-02-29
        
        guard var date = calendar.date(byAdding: .day, value: days, to: base) else {
            return nil
        }
        
        if fraction > 0 {
            let seconds = Int(round(fraction * 86_400.0))
            if let withTime = calendar.date(byAdding: .second, value: seconds, to: date) {
                date = withTime
            }
        }
        
        return date
    }
    
    private func parseDecimal(_ decimalString: String) -> NSDecimalNumber? {
        let cleanString = decimalString
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        if let double = Double(cleanString) {
            return NSDecimalNumber(value: double)
        }
        
        return nil
    }
    
    func importSinistro(from data: [String: Any]) throws -> Sinistro {
        let sinistro = Sinistro(context: context)
        
        // Mappatura dei campi base
        sinistro.riferimento = data["riferimento"] as? String
        sinistro.numeroSinistroCompagnia = data["numeroSinistroCompagnia"] as? String
        sinistro.nomeCompagnia = data["nomeCompagnia"] as? String ?? data["divisioneCompagnia"] as? String
        // Parsa agenzia se presente
        if let agenziaFull = data["agenzia"] as? String, !agenziaFull.isEmpty,
           let nomeCompagnia = data["nomeCompagnia"] as? String {
            let parsed = AgencyReaderHelper.shared.parseAgenzia(agenziaFull, compagnia: nomeCompagnia)
            sinistro.codiceAgenzia = parsed.codice.isEmpty ? (data["codiceAgenzia"] as? String) : parsed.codice
            sinistro.agenzia = parsed.nome
        } else {
            sinistro.codiceAgenzia = data["codiceAgenzia"] as? String
            sinistro.agenzia = data["agenzia"] as? String
        }
        
        // Mappatura delle date
        if let dataSinistro = data["dataSinistro"] as? String {
            sinistro.setDataSinistro(dateFormatter.date(from: dataSinistro))
        }
        if let dataAperturaGestione = data["dataAperturaGestione"] as? String {
            sinistro.dataAperturaGestione = dateFormatter.date(from: dataAperturaGestione)
        }
        if let dataChiusura = data["dataChiusura"] as? String {
            sinistro.dataChiusura = dateFormatter.date(from: dataChiusura)
        }
        
        // Mappatura degli attori come stringhe
        sinistro.nomeContraente = data["nomeContraente"] as? String
        sinistro.nomeAssicurato = data["nomeAssicurato"] as? String
        sinistro.nomeDanneggiato = data["nomeDanneggiato"] as? String
        
        // Mappatura dei contatti
        sinistro.emailContraente = data["emailContraente"] as? String
        sinistro.telefonoContraente = data["telefonoContraente"] as? String
        sinistro.indirizzoContraente = data["indirizzoContraente"] as? String
        
        sinistro.emailAssicurato = data["emailAssicurato"] as? String
        sinistro.telefonoAssicurato = data["telefonoAssicurato"] as? String
        sinistro.indirizzoAssicurato = data["indirizzoAssicurato"] as? String
        
        sinistro.emailDanneggiato = data["emailDanneggiato"] as? String
        sinistro.telefonoDanneggiato = data["telefonoDanneggiato"] as? String
        sinistro.indirizzoDanneggiato = data["indirizzoDanneggiato"] as? String
        
        sinistro.emailAgenzia = data["emailAgenzia"] as? String
        sinistro.telefonoAgenzia = data["telefonoAgenzia"] as? String
        
        // Mappatura dei valori numerici
        if let richiesta = data["richiesta"] as? String {
            sinistro.richiesta = NSDecimalNumber(string: richiesta)
        }
        if let dannoAccertato = data["dannoAccertato"] as? String {
            sinistro.dannoAccertato = NSDecimalNumber(string: dannoAccertato)
        }
        if let dannoAccertatoNetto = data["dannoAccertatoNetto"] as? String {
            sinistro.dannoAccertatoNetto = NSDecimalNumber(string: dannoAccertatoNetto)
        }
        if let liquidato = data["liquidato"] as? String {
            sinistro.liquidato = NSDecimalNumber(string: liquidato)
        }
        
        // Mappatura dei booleani
        sinistro.sinistroCollegato = data["sinistroCollegato"] as? Bool ?? false
        sinistro.oltreDieciBeni = data["oltreDieciBeni"] as? Bool ?? false
        sinistro.sopralluogo = data["sopralluogo"] as? Bool ?? false
        sinistro.giustificativi = data["giustificativi"] as? Bool ?? false
        sinistro.iban = data["iban"] as? Bool ?? false
        
        // Mappatura dei collegamenti
        if let collegamenti = data["collegamenti"] as? [String] {
            sinistro.collegamenti = NSSet(array: collegamenti)
        }

        // Anche per import JSON/CSV legacy: assegna ownership all'utente loggato.
        // Qui NON possiamo leggere GoogleAuthService.shared.userEmail (MainActor) perché siamo in contesto non isolato.
        let email = UserDefaults.standard.string(forKey: "userEmail")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let email, !email.isEmpty {
            let displayName: String = {
                let fromDefaults = UserDefaults.standard.string(forKey: "userName")?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let fromDefaults, !fromDefaults.isEmpty { return fromDefaults }
                return email.components(separatedBy: "@").first?.replacingOccurrences(of: ".", with: " ").capitalized ?? email
            }()
            sinistro.ownerEmail = email
            sinistro.assignedToUserEmail = email
            sinistro.assignedToUserName = displayName
            if sinistro.dataAssegnazione == nil {
                sinistro.setDataAssegnazione(Date())
            }
        }
        
        // Valida tutte le date dopo l'import
        sinistro.validateAllDates()
        
        return sinistro
    }
    
    func importSinistri(from dataArray: [[String: Any]]) throws -> [Sinistro] {
        var sinistri: [Sinistro] = []
        
        for data in dataArray {
            let sinistro = try importSinistro(from: data)
            sinistri.append(sinistro)
        }
        
        try context.save()
        return sinistri
    }
    
    func importSinistriFromJSON(_ jsonData: Data) throws -> [Sinistro] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw ImportError.invalidJSON
        }
        
        return try importSinistri(from: jsonArray)
    }
    
    func importSinistriFromCSV(_ csvData: Data) throws -> [Sinistro] {
        guard let csvString = String(data: csvData, encoding: .utf8) else {
            throw ImportError.invalidCSV
        }
        
        let rows = csvString.components(separatedBy: .newlines)
        guard rows.count > 1 else {
            throw ImportError.emptyCSV
        }
        
        let headers = rows[0].components(separatedBy: ",")
        var dataArray: [[String: Any]] = []
        
        for row in rows.dropFirst() {
            let values = row.components(separatedBy: ",")
            guard values.count == headers.count else { continue }
            
            var data: [String: Any] = [:]
            for (index, header) in headers.enumerated() {
                data[header.trimmingCharacters(in: .whitespaces)] = values[index].trimmingCharacters(in: .whitespaces)
            }
            dataArray.append(data)
        }
        
        return try importSinistri(from: dataArray)
    }
}

// MARK: - Errori e risultati

enum ImportError: LocalizedError {
    case unsupportedFileType(String)
    case emptyFile
    case missingRequiredField(String)
    case emptyRequiredField(String)
    case invalidRiferimentoFormat(String)
    case invalidData(String)
    case invalidJSON
    case invalidCSV
    case emptyCSV
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let type):
            return "Tipo di file non supportato: .\(type)"
        case .emptyFile:
            return "Il file è vuoto"
        case .missingRequiredField(let field):
            return "Campo obbligatorio mancante: \(field)"
        case .emptyRequiredField(let field):
            return "Campo obbligatorio vuoto: \(field)"
        case .invalidRiferimentoFormat(let value):
            return "Riferimento '\(value)' non valido: deve essere esattamente 7 cifre numeriche"
        case .invalidData(let message):
            return "Dati non validi: \(message)"
        case .invalidJSON:
            return "JSON non valido"
        case .invalidCSV:
            return "CSV non valido"
        case .emptyCSV:
            return "CSV vuoto"
        }
    }
}
