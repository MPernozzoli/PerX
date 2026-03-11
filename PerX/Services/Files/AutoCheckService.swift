import Foundation
import CoreData

class AutoCheckService {
    static let shared = AutoCheckService()
    private let fileService = FileService.shared
    private let fileTagManager = FileTagManager.shared
    
    private var processingSinistri = Set<String>()
    private let queue = DispatchQueue(label: "com.perx.autocheck")
    
    /// File spazzatura da spostare automaticamente nel cestino
    private let junkFiles: Set<String> = ["messaggi.txt", "thumbs.db", ".ds_store"]
    
    private init() {}
    
    private func isBlank(_ value: String?) -> Bool {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isSinistroChiuso(_ sinistro: Sinistro) -> Bool {
        (sinistro.stato ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("chius")
    }
    
    /// Riallinea `gruppo` e `nomeCompagnia` quando uno è valorizzato e l'altro è vuoto.
    /// - Se la compagnia è riconoscibile (es. Cattolica/Generali Italia/Zurich Italia/Unipol Italia) imposta il gruppo coerente.
    /// - Se il gruppo è riconoscibile e ha una sola compagnia, imposta anche la compagnia se mancante (Zurich/Unipol).
    private func reconcileGruppoCompagniaIfNeeded(sinistro: Sinistro, context: NSManagedObjectContext) async {
        let hasGruppo = !isBlank(sinistro.gruppo)
        let hasCompagnia = !isBlank(sinistro.nomeCompagnia)
        
        guard hasGruppo != hasCompagnia else { return } // solo se uno è valorizzato e l'altro no
        
        await withCheckedContinuation { continuation in
            context.perform {
                // Caso 1: Compagnia presente, Gruppo mancante -> deduci gruppo dalla compagnia
                if !hasGruppo, hasCompagnia {
                    let gruppoFromCompagnia = GruppoAssicurativo.from(nomeGruppo: sinistro.nomeCompagnia)
                    if gruppoFromCompagnia != .unknown {
                        sinistro.gruppo = gruppoFromCompagnia.rawValue
                        print("[AutoCheck] 🔧 Allineamento: gruppo impostato a '\(gruppoFromCompagnia.rawValue)' da compagnia '\(sinistro.nomeCompagnia ?? "")'")
                    }
                }
                
                // Caso 2: Gruppo presente, Compagnia mancante -> deduci compagnia solo se univoca
                if hasGruppo, !hasCompagnia {
                    let gruppo = GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo)
                    if gruppo.compagnie.count == 1 {
                        sinistro.nomeCompagnia = gruppo.compagnie[0].rawValue
                        print("[AutoCheck] 🔧 Allineamento: compagnia impostata a '\(gruppo.compagnie[0].rawValue)' da gruppo '\(sinistro.gruppo ?? "")'")
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func updateSinistroFromExcelData(_ sinistro: Sinistro, with data: [String: Any]) {
        print("DEBUG: Inizio aggiornamento sinistro con dati Excel")
        print("DEBUG: Dati ricevuti:", data)
        
        // Verifica se il sinistro è stato importato
        let isImported = sinistro.riferimento.flatMap { ImportService.isSinistroImported(riferimento: $0) } ?? false
        
        // Sanity check: verifica se agenzia e numeroSinistroCompagnia sono scambiati
        var agenzia = data["agenzia"] as? String
        var codiceAgenzia = data["codiceAgenzia"] as? String
        var numeroSinistro = data["numeroSinistroCompagnia"] as? String
        
        // Se agenzia sembra un numero sinistro (pattern tipico: alfanumerico con / o -)
        // e numeroSinistro sembra un nome (parole con spazi), scambiali
        if let ag = agenzia, let num = numeroSinistro {
            let agSeemsLikeNumber = looksLikeClaimNumber(ag)
            let numSeemsLikeName = looksLikeAgencyName(num)
            
            if agSeemsLikeNumber && numSeemsLikeName {
                print("[AutoCheck] ⚠️ Rilevato swap agenzia/numeroSinistro, correggo")
                agenzia = num
                numeroSinistro = ag
            }
        }
        
        // Se numeroSinistro è vuoto ma agenzia sembra un numero sinistro, sposta
        if let ag = agenzia, (numeroSinistro ?? "").isEmpty, looksLikeClaimNumber(ag) {
            print("[AutoCheck] ⚠️ Agenzia contiene numero sinistro, sposto")
            numeroSinistro = ag
            agenzia = nil
        }
        
        // Dati base - non sovrascrivere se importato
        if !isImported {
            if let gruppo = data["gruppo"] as? String {
                sinistro.gruppo = gruppo
            }
            
            if let nomeCompagnia = data["nomeCompagnia"] as? String {
                sinistro.nomeCompagnia = nomeCompagnia
            }
            
            if let area = data["area"] as? String {
                sinistro.area = area
            }
            
            if let codAg = codiceAgenzia, !codAg.isEmpty {
                sinistro.codiceAgenzia = codAg.uppercased()
            }
            
            if let ag = agenzia, !ag.isEmpty {
                sinistro.agenzia = ag
            }
            
            if let num = numeroSinistro, !num.isEmpty {
                // Numero sinistro sempre in UPPERCASE
                sinistro.numeroSinistroCompagnia = num.uppercased()
            }
        } else {
            print("[AutoCheck] ⏭️ Sinistro importato, skip aggiornamento dati statici da Excel")
        }
        
        // Date
        if let dataSinistro = data["dataSinistro"] as? Date {
            sinistro.dataSinistro = dataSinistro
        }
        
        if let dataDenuncia = data["dataDenuncia"] as? Date {
            sinistro.dataDenuncia = dataDenuncia
        }
        
        if let dataIncarico = data["dataIncarico"] as? Date {
            sinistro.dataIncarico = dataIncarico
        }
        
        if let dataSopralluogo = data["dataSopralluogo"] as? Date {
            sinistro.dataSopralluogo = dataSopralluogo
            sinistro.sopralluogo = true
        }
        
        // Dati polizza
        if let numeroPolizza = data["numeroPolizza"] as? String {
            sinistro.numeroPolizza = numeroPolizza
        }
        
        if let tipoPolizza = data["tipoPolizza"] as? String {
            sinistro.tipoPolizza = tipoPolizza
        }
        
        // Dati attori - non sovrascrivere nomeAssicurato se importato
        if let nomeContraente = data["nomeContraente"] as? String {
            sinistro.nomeContraente = nomeContraente
        }
        
        if !isImported {
            if let nomeAssicurato = data["nomeAssicurato"] as? String {
                sinistro.nomeAssicurato = nomeAssicurato
            }
        }
        
        if let nomeDanneggiato = data["nomeDanneggiato"] as? String {
            sinistro.nomeDanneggiato = nomeDanneggiato
        }
        
        if let indirizzoAssicurato = data["indirizzoAssicurato"] as? String {
            sinistro.indirizzoAssicurato = indirizzoAssicurato
        }
        
        if let indirizzoContraente = data["indirizzoContraente"] as? String {
            sinistro.indirizzoContraente = indirizzoContraente
        }
        
        if let telefonoAssicurato = data["telefonoAssicurato"] as? String {
            sinistro.telefonoAssicurato = telefonoAssicurato
        }
        
        if let telefonoContraente = data["telefonoContraente"] as? String {
            sinistro.telefonoContraente = telefonoContraente
        }
        
        if let emailAssicurato = data["emailAssicurato"] as? String {
            sinistro.emailAssicurato = emailAssicurato
        }
        
        if let emailContraente = data["emailContraente"] as? String {
            sinistro.emailContraente = emailContraente
        }
        
        if let telefoniAssicuratoArray = data["telefoniAssicuratoArray"] as? [String] {
            sinistro.telefoniAssicuratoArray = telefoniAssicuratoArray
        }
        
        if let emailAssicuratoArray = data["emailAssicuratoArray"] as? [String] {
            sinistro.emailAssicuratoArray = emailAssicuratoArray
        }
        
        // Importi
        if let importoRichiesto = data["richiesta"] as? NSDecimalNumber {
            sinistro.richiesta = importoRichiesto
        }
        
        if let stimaDanno = data["stimaDanno"] as? NSDecimalNumber {
            sinistro.stimaDanno = stimaDanno
        }
        
        // Altri campi
        if let definizione = data["definizione"] as? String {
            // Non sovrascrivere se è stata impostata manualmente
            if !sinistro.definizioneManuale {
                sinistro.definizione = definizione
            } else {
                print("[AutoCheck] ⏭️ Definizione manuale presente, skip aggiornamento da Excel")
            }
        }
        
        // Determinazione: exact match su opzioni, aggiorna perizia.determinazione (solo se non definizione manuale)
        if !sinistro.definizioneManuale {
            let defRaw = (data["determinazione"] as? String) ?? (data["definizione"] as? String)
            let defTrim = defRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !defTrim.isEmpty,
               let matched = RelazionePeritaleService.opzioniDeterminazione
                .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == defTrim.uppercased() }) {
                let ctx = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
                var perizia = sinistro.perizia
                if perizia == nil {
                    perizia = Perizia(context: ctx)
                    perizia?.id = UUID()
                    sinistro.perizia = perizia
                }
                perizia?.determinazione = matched
            }
        }
        
        // Liquidazione: se flag 1 e stimaDanno > 0, imposta liquidato
        let liquidazioneFlag: Bool = {
            if let n = data["liquidazione"] as? NSNumber { return n.intValue != 0 }
            if let b = data["liquidazione"] as? Bool { return b }
            if let i = data["liquidazione"] as? Int { return i != 0 }
            return false
        }()
        let stimaVal = (data["stimaDanno"] as? NSDecimalNumber)?.doubleValue ?? sinistro.stimaDanno?.doubleValue ?? 0
        if liquidazioneFlag && stimaVal > 0 {
            sinistro.liquidato = sinistro.stimaDanno ?? NSDecimalNumber(value: stimaVal)
        }
        
        // Forza il salvataggio del contesto
        do {
            if let context = sinistro.managedObjectContext {
                try context.save()
                print("DEBUG: Salvataggio completato con successo")
            }
        } catch {
            print("DEBUG: Errore durante il salvataggio:", error)
        }
    }
    
    private func checkExcelData(in path: String, sinistro: Sinistro) async {
        // Verifica se il sinistro ha già tutti i dati essenziali
        let hasEssentialData = sinistro.nomeAssicurato?.isEmpty == false &&
                              sinistro.richiesta != nil &&
                              sinistro.numeroSinistroCompagnia?.isEmpty == false
        
        if hasEssentialData {
            print("[AutoCheck] ✅ Sinistro \(sinistro.riferimento ?? "N/A") ha già tutti i dati essenziali, skip lettura Excel")
            return
        }
        
        do {
            print("[AutoCheck] 🔍 Cercando file Excel per sinistro: \(sinistro.riferimento ?? "N/A")")
            let excelURL = try await ExcelFinderService.shared.findElaboratoPeritale(forSinistro: sinistro)
            print("[AutoCheck] ✅ Trovato file Excel: \(excelURL.lastPathComponent)")
            print("[AutoCheck] 📁 Percorso completo: \(excelURL.path)")
            
            await readAndUpdateExcel(excelURL: excelURL, sinistro: sinistro)
        } catch {
            print("[AutoCheck] ⚠️ Errore nella lettura del file Excel: \(error.localizedDescription)")
        }
    }
    
    /// Legge e aggiorna il sinistro con i dati da un file Excel specifico
    func readAndUpdateExcel(excelURL: URL, sinistro: Sinistro) async {
        // Verifica se il sinistro ha già tutti i dati essenziali (ma permette aggiornamento manuale)
        let hasEssentialData = sinistro.nomeAssicurato?.isEmpty == false &&
                              sinistro.richiesta != nil &&
                              sinistro.numeroSinistroCompagnia?.isEmpty == false
        
        if hasEssentialData {
            print("[AutoCheck] ⚠️ Sinistro ha già dati essenziali, ma procedo con aggiornamento manuale")
        }
        
        do {
            print("[AutoCheck] 📊 Lettura file Excel: \(excelURL.lastPathComponent)")
            let data = try await ExcelReaderService.shared.readExcelFile(at: excelURL)
            print("[AutoCheck] 📊 Dati letti dal file Excel: \(data.keys.joined(separator: ", "))")
            
            // Verifica se abbiamo trovato dati essenziali
            let foundEssentialData = (data["nomeContraente"] as? String)?.isEmpty == false ||
                                    (data["richiesta"] as? NSDecimalNumber) != nil ||
                                    (data["numeroSinistroCompagnia"] as? String)?.isEmpty == false
            
            if !foundEssentialData {
                print("[AutoCheck] ⚠️ Nessun dato essenziale trovato nell'Excel, potrebbe essere vuoto o corrotto")
            }
            
            await MainActor.run {
                let context = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
                context.perform {
                    self.updateSinistroFromExcelData(sinistro, with: data)
                    do {
                        try context.save()
                        print("[AutoCheck] ✅ Dati Excel salvati nel sinistro \(sinistro.riferimento ?? "N/A")")
                    } catch {
                        print("[AutoCheck] ❌ Errore salvataggio dati Excel: \(error)")
                    }
                }
            }
        } catch {
            print("[AutoCheck] ⚠️ Errore nella lettura del file Excel: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Coordinamento con Hub (cartella mancante)
    
    /// Se la cartella non è disponibile localmente, richiede download via Hub e attende.
    private func ensureSinistroFolderAvailable(sinistro: Sinistro, riferimento: String, timeout: TimeInterval = 120) async -> String? {
        if let existing = fileService.getSinistroPath(riferimento: riferimento) {
            return existing
        }
        let initialStatus = await ClaimSyncService.shared.status(for: sinistro)
        if initialStatus.isActive {
            print("[AutoCheck] ⏳ Cartella mancante ma sync in corso per \(riferimento), attendo...")
        } else {
            print("[AutoCheck] 📥 Cartella mancante per \(riferimento), richiedo download via Hub...")
            await ClaimSyncService.shared.manualDownload(for: sinistro)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let path = fileService.getSinistroPath(riferimento: riferimento) {
                return path
            }
            let status = await ClaimSyncService.shared.status(for: sinistro)
            if case .error(let message) = status {
                print("[AutoCheck] ❌ Hub sync errore per \(riferimento): \(message)")
                return nil
            }
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
        }
        print("[AutoCheck] ⚠️ Timeout attesa cartella per \(riferimento)")
        return fileService.getSinistroPath(riferimento: riferimento)
    }
    
    func performAutoChecks(for sinistro: Sinistro, context: NSManagedObjectContext) async {
        // Non eseguire se il sinistro è chiuso
        if isSinistroChiuso(sinistro) {
            print("[AutoCheck] ⏸️ Sinistro chiuso, skip")
            return
        }
        
        // Leggi le impostazioni - se non esistono, usa i default (true)
        let autoCheckEnabled = UserDefaults.standard.object(forKey: "enableAutoCheck") as? Bool ?? true
        let excelEnabled = UserDefaults.standard.object(forKey: "enableAutoCheckExcel") as? Bool ?? true
        let tagsEnabled = UserDefaults.standard.object(forKey: "enableAutoCheckTags") as? Bool ?? true
        
        let rifLog = sinistro.riferimento ?? "N/A"
        print("[AutoCheck] 🔍 Verifica impostazioni per \(rifLog):")
        print("[AutoCheck]   - enableAutoCheck: \(autoCheckEnabled)")
        print("[AutoCheck]   - enableAutoCheckExcel: \(excelEnabled)")
        print("[AutoCheck]   - enableAutoCheckTags: \(tagsEnabled)")
        
        // Permetti l'esecuzione se AutoCheck è abilitato O se almeno Excel è abilitato
        guard autoCheckEnabled || excelEnabled else {
            print("[AutoCheck] ⏸️ AutoCheck e Excel disabilitati")
            return
        }
        
        guard let riferimento = sinistro.riferimento else { return }
        
        let isProcessing = queue.sync { processingSinistri.contains(riferimento) }
        if isProcessing {
            print("DEBUG: Sinistro \(riferimento) già in elaborazione, skip")
            return
        }
        
        queue.sync { processingSinistri.insert(riferimento) }
        
        defer {
            queue.sync { processingSinistri.remove(riferimento) }
        }
        
        var path = fileService.getSinistroPath(riferimento: riferimento)
        if path == nil {
            path = await ensureSinistroFolderAvailable(sinistro: sinistro, riferimento: riferimento)
        }
        guard let path else {
            print("[AutoCheck] ❌ Cartella sinistro non trovata (anche dopo sync): \(riferimento)")
            return
        }
        
        // Sposta le operazioni di I/O su background thread (solo se AutoCheck è abilitato)
        let allFiles: [FileService.FileItem]
        if autoCheckEnabled {
            allFiles = await withCheckedContinuation { continuation in
                queue.async {
                    // Pulizia file spazzatura (messaggi.txt, Thumbs.db)
                    self.moveJunkFilesToCestino(inPath: path)
                    
                    let files = self.scanDirectory(path)
                    continuation.resume(returning: files)
                }
            }
        } else {
            allFiles = []
        }
        
        // 1. Check per i dati Excel (prima di tutto)
        print("[AutoCheck] 🔍 enableAutoCheckExcel: \(excelEnabled)")
        if excelEnabled {
            print("[AutoCheck] 📊 Avvio lettura Excel per \(riferimento)")
            await checkExcelData(in: path, sinistro: sinistro)
            print("[AutoCheck] ✅ Lettura Excel completata per \(riferimento)")
        } else {
            print("[AutoCheck] ⏸️ Lettura Excel disabilitata per \(riferimento)")
        }
        
        // 1b. Allineamento Gruppo ↔ Compagnia (solo se uno dei due è vuoto)
        await reconcileGruppoCompagniaIfNeeded(sinistro: sinistro, context: context)
        
        // 2. Esegui i check file-based con tagging pattern (solo se AutoCheck e Tags sono abilitati)
        var taggedCount = 0
        var skippedCount = 0
        if autoCheckEnabled && tagsEnabled {
            print("[AutoCheck] 🏷️ Avvio applicazione tag automatici per \(allFiles.count) file...")
            (taggedCount, skippedCount) = await checkAndApplyTags(for: allFiles)
            print("[AutoCheck] ✅ Applicazione tag completata")
        } else {
            print("[AutoCheck] ⏭️ Skip tag automatici (autoCheck: \(autoCheckEnabled), tags: \(tagsEnabled))")
        }
        
        // 3. Parsing PDF incarico per Gruppo Generali (se regolarità non già rilevata)
        if autoCheckEnabled {
            await checkIncaricoGenerali(sinistro: sinistro)
        }
        
        // 4. Autotagging IA per le foto non taggate (ultimo step di tagging)
        var aiTaggedCount = 0
        if autoCheckEnabled && tagsEnabled {
            print("[AutoCheck] 🤖 Avvio autotagging IA per foto non taggate...")
            aiTaggedCount = await runPhotoAutoTagging(for: sinistro, forceReanalyze: false)
            if aiTaggedCount > 0 {
                print("[AutoCheck] ✅ Autotagging IA completato: \(aiTaggedCount) foto taggate")
            } else {
                print("[AutoCheck] ℹ️ Nessuna foto da taggare con IA")
            }
            
            // Riepilogo finale dopo tutti i processi
            let totalTagged = taggedCount + aiTaggedCount
            print("[AutoCheck] 📊 Riepilogo finale: \(totalTagged) file taggati (\(taggedCount) pattern, \(aiTaggedCount) IA), \(skippedCount) saltati (già con tag)")
        }
        
        // 5. Check cartella Sopralluogo - esegui SEMPRE se Excel o AutoCheck abilitato
        // Questo garantisce che il flag sopralluogo sia impostato anche se AutoCheck generale è off
        if autoCheckEnabled || excelEnabled {
            await MainActor.run {
                // Check per la cartella sopralluogo (veloce)
                checkSopralluogoFolder(in: path, sinistro: sinistro)
            }
        }
        
        // 6. Aggiornamenti giustificativi (solo se AutoCheck è abilitato)
        if autoCheckEnabled {
            await MainActor.run {
                // Check per i giustificativi (usa i risultati già calcolati)
                checkGiustificativi(sinistro: sinistro)
            }
        }
        
        // Salva le modifiche in modo asincrono per evitare blocchi
        await MainActor.run {
            context.perform {
                do {
                    try context.save()
                    print("DEBUG: Auto-checks completati e salvati")
                } catch {
                    print("DEBUG: Errore nel salvataggio dopo auto-checks:", error)
                }
            }
        }
    }

    // MARK: - AutoTagging IA (solo via AutoCheck)
    
    @MainActor
    func runPhotoAutoTagging(for sinistro: Sinistro, forceReanalyze: Bool = false) async -> Int {
        guard !isSinistroChiuso(sinistro) else { return 0 }
        return await AutoTaggingService.shared.runAutoTagging(for: sinistro, forceReanalyze: forceReanalyze, startPeriziaOnComplete: true)
    }
    
    @MainActor
    func autoTagPhotoFiles(_ fileURLs: [URL], for sinistro: Sinistro) async -> Int {
        guard !isSinistroChiuso(sinistro) else { return 0 }
        return await AutoTaggingService.shared.autoTagFiles(fileURLs, for: sinistro)
    }
    
    @MainActor
    func hasTaggedPhotos(for sinistro: Sinistro) -> Bool {
        AutoTaggingService.shared.hasTaggedPhotos(for: sinistro)
    }
    
    @MainActor
    func hasPhotosInFolder(for sinistro: Sinistro) -> Bool {
        AutoTaggingService.shared.hasPhotosInFolder(for: sinistro)
    }
    
    private func scanDirectory(_ path: String) -> [FileService.FileItem] {
        print("[AutoCheck] 🔍 Scansione ricorsiva directory: \(path)")
        
        // Prima prova con FileService (che gestisce i bookmark)
        var allFiles = fileService.listFilesRecursive(inDirectory: path)
        
        // Fallback: se non trova nulla, prova scansione diretta
        if allFiles.isEmpty {
            print("[AutoCheck] ⚠️ listFilesRecursive vuoto, provo scansione diretta...")
            allFiles = scanDirectoryDirectly(path)
        }
        
        // Escludi file nella cartella "Da Chiudere" e nella cache interna PerX
        allFiles = allFiles.filter { url in
            let p = url.path.lowercased()
            return !p.contains("/da chiudere/") && !p.contains("/perx-cache/")
        }
        
        // Limita il numero per evitare problemi di memoria
        let maxFiles = 2000
        let files = Array(allFiles.prefix(maxFiles))
        
        print("[AutoCheck] 📁 Trovati \(files.count) file totali (esclusa cartella Da Chiudere)")
        return files.map { url in
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modificationDate = (attrs[.modificationDate] as? Date) ?? .distantPast
            return FileService.FileItem(
                id: url.path,
                url: url,
                isDirectory: false,
                icon: nil,
                size: size,
                modificationDate: modificationDate
            )
        }
    }
    
    /// Scansione diretta senza passare per FileService (fallback)
    private func scanDirectoryDirectly(_ path: String) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        let directoryURL = URL(fileURLWithPath: path)
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[AutoCheck] ❌ Impossibile creare enumerator per: \(path)")
            return []
        }
        
        for case let url as URL in enumerator {
            // Escludi file nella cartella "Da Chiudere"
            let p = url.path.lowercased()
            if p.contains("/da chiudere/") || p.contains("/perx-cache/") {
                continue
            }
            
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                results.append(url)
            }
        }
        
        print("[AutoCheck] 📂 Scansione diretta: trovati \(results.count) file (esclusa cartella Da Chiudere)")
        return results
    }
    
    // MARK: - Pulizia File Spazzatura
    
    /// Sposta i file spazzatura (messaggi.txt, Thumbs.db, .DS_Store) nel cestino PerX (perx-cache/cestino).
    /// Nota: non sposta nulla che sia già dentro `perx-cache` (che è parte del sinistro e va sincronizzata 1:1).
    func moveJunkFilesToCestino(inPath path: String) {
        let fm = FileManager.default
        let directoryURL = URL(fileURLWithPath: path)
        let preferredCestinoPath = (path as NSString).appendingPathComponent("perx-cache/cestino")
        let preferredCestinoURL = URL(fileURLWithPath: preferredCestinoPath)
        
        // Per path interni (Application Support), l'accesso è diretto.
        // Per path esterni legacy, usiamo i bookmark di FileService.
        let movedCount: Int? = fileService.performWithSecurityScopedAccess(to: path) {
            // Crea la cartella cestino se non esiste (sempre dentro il sinistro).
            if !fm.fileExists(atPath: preferredCestinoPath) {
                try fm.createDirectory(at: preferredCestinoURL, withIntermediateDirectories: true)
                print("[AutoCheck] 🗑️ Creata cartella cestino: \(preferredCestinoPath)")
            }
            
            // Enumera tutti i file nella cartella e sottocartelle (escludendo perx-cache)
            guard let enumerator = fm.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            
            var moved = 0
            
            for case let url as URL in enumerator {
                // Salta tutta la sottostruttura perx-cache (e quindi anche perx-cache/cestino)
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                   url.lastPathComponent.lowercased() == "perx-cache" {
                    enumerator.skipDescendants()
                    continue
                }
                
                // Skip rapido se siamo già dentro perx-cache
                if url.path.lowercased().contains("/perx-cache/") { continue }
                
                let filename = url.lastPathComponent.lowercased()
                guard junkFiles.contains(filename) else { continue }
                
                // Genera nome univoco per evitare conflitti
                let timestamp = Int(Date().timeIntervalSince1970)
                let destFilename = "\(timestamp)_\(url.lastPathComponent)"
                let destURL = preferredCestinoURL.appendingPathComponent(destFilename)
                
                do {
                    try fm.moveItem(at: url, to: destURL)
                    moved += 1
                    print("[AutoCheck] 🗑️ Spostato nel cestino: \(url.lastPathComponent)")
                } catch {
                    print("[AutoCheck] ⚠️ Errore spostamento \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            return moved
        }
        
        if let movedCount, movedCount > 0 {
            print("[AutoCheck] 🗑️ Totale file spazzatura rimossi: \(movedCount)")
        } else if movedCount == nil {
            // Nessun accesso security-scoped: non usiamo fallback in Caches (il cestino deve stare nel sinistro).
            print("[AutoCheck] ⚠️ Nessun accesso security-scoped per spostare file spazzatura in: \(preferredCestinoPath)")
        }
    }
    
    private func checkAndApplyTags(for files: [FileService.FileItem]) async -> (tagged: Int, skipped: Int) {
        print("[AutoCheck] 🏷️ Inizio analisi \(files.count) file per auto-tagging")
        var taggedCount = 0
        var skippedCount = 0
        
        for file in files {
            // Skip file nella cartella "Da Chiudere"
            let p = file.url.path.lowercased()
            if p.contains("/da chiudere/") || p.contains("/perx-cache/") {
                skippedCount += 1
                continue
            }
            
            let filename = file.url.lastPathComponent.lowercased()
            
            // Skip se il file ha già tag (inclusi tag file_*) - verifica sul main thread
            let existingTags = await MainActor.run {
                fileTagManager.getTagsForFile(at: file.url.path)
            }
            if !existingTags.isEmpty {
                skippedCount += 1
                continue
            }
            
            // Check per "atto da firmare"
            if filename.contains("atto da firmare") || filename.contains("atto_da_firmare") {
                if await applyTag("atto_da_firmare", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per atto firmato
            if filename.contains("atto firmato") || filename.contains("atto_firmato") {
                if await applyTag("atto_firmato", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per liquidazione/quietanza -> atto firmato con sottotipo liquidazione
            if filename.contains("liquidazione") || filename.contains("quietanza") {
                if await applyTag("atto_firmato", to: file.url, attoSottotipo: "liquidazione") { taggedCount += 1 }
                continue
            }
            
            // Check per accertamento -> atto firmato con sottotipo accertamento
            if filename.contains("accertamento") {
                if await applyTag("atto_firmato", to: file.url, attoSottotipo: "accertamento") { taggedCount += 1 }
                continue
            }
            
            // Check per fatture
            let fatturaKeywords = ["fattura", "fatt", "fatture", "scontrino", "scontrini"]
            if fatturaKeywords.contains(where: { filename.contains($0) }) {
                if await applyTag("fattura", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per preventivi
            let preventivoKeywords = ["preventivo", "prev", "preventivi"]
            if preventivoKeywords.contains(where: { filename.contains($0) }) {
                if await applyTag("preventivo", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per fulminazione
            if filename.contains("fulminazione") || filename.contains("fulminazioni") {
                if await applyTag("fulminazione", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per polizza/simplo
            if filename.contains("polizza") || filename.contains("simplo") {
                if await applyTag("simplo_di_polizza", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per verbale
            if filename.contains("verbale") {
                if await applyTag("verbale", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per fulminazione (report CESI, Fulmini)
            let fulminazioneKeywords = ["cesi", "fulmini", "fulminazione", "fulmine", "meteofulmini", "meteocast"]
            if fulminazioneKeywords.contains(where: { filename.contains($0) }) {
                if await applyTag("fulminazione", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per incarico (escludi IncaricoAuto.pdf e Scheda_incarico_*.pdf)
            if filename.contains("incarico") {
                let isIncaricoAuto = filename.lowercased() == "incaricoauto.pdf"
                let isSchedaIncarico = filename.lowercased().hasPrefix("scheda_incarico_")
                
                if !isIncaricoAuto && !isSchedaIncarico {
                    if await applyTag("incarico", to: file.url) { taggedCount += 1 }
                }
                continue
            }
            
            // Check per test strumentali
            let testKeywords = ["test dispersiva", "misura dispersiva", "ohmica", "resistiva", "isolamento", "test strumentale"]
            if testKeywords.contains(where: { filename.contains($0) }) {
                if await applyTag("test_strumentale", to: file.url) { taggedCount += 1 }
                continue
            }
            
            // Check per Excel elaborato peritale
            if filename.hasPrefix("elaborato_peritale") && (filename.hasSuffix(".xlsm") || filename.hasSuffix(".xlsx")) {
                if await applyTag("elaborato_excel", to: file.url) {
                    taggedCount += 1
                    // Aggiorna flag "ultimo" dopo aver aggiunto il tag (sul main thread)
                    await MainActor.run {
                        fileTagManager.updateElaboratoExcelUltimo()
                    }
                }
                continue
            }
        }
        
        return (tagged: taggedCount, skipped: skippedCount)
    }
    
    /// Verifica la presenza della cartella "Sopralluogo" e aggiorna il tipo di perizia del sinistro.
    /// - Cartella "Sopralluogo" presente → Sinistro TRADIZIONALE (sopralluogo = true)
    /// - Cartella "Sopralluogo" assente → Sinistro DOCUMENTALE (sopralluogo = false)
    ///   - Se mancano le foto → stato "In attesa (documentale)"
    ///   - Se ci sono le foto → stato "Perizia da eseguire (documentale)"
    private func checkSopralluogoFolder(in path: String, sinistro: Sinistro) {
        let contents = fileService.listContents(inDirectory: path)
        let hasSopralluogoFolder = contents.contains { item in
            item.isDirectory && item.url.lastPathComponent.lowercased() == "sopralluogo"
        }
        
        let previousIsTradizionale = sinistro.sopralluogo
        
        if hasSopralluogoFolder {
            // Sinistro TRADIZIONALE
            sinistro.sopralluogo = true
            
            // Se il tipo è cambiato, notifica e aggiorna stato
            if !previousIsTradizionale {
                print("[AutoCheck] 📁 Rilevata cartella 'Sopralluogo' → Sinistro cambiato a TRADIZIONALE")
                updateStateForTipoPeriziaChange(sinistro: sinistro, isTradizionale: true, path: path)
            }
        } else {
            // Sinistro DOCUMENTALE
            sinistro.sopralluogo = false
            
            // Se il tipo è cambiato (era tradizionale, ora documentale), aggiorna stato
            if previousIsTradizionale {
                print("[AutoCheck] 📁 Cartella 'Sopralluogo' assente → Sinistro cambiato a DOCUMENTALE")
                let hasFoto = checkHasFotoInPath(path)
                updateStateForTipoPeriziaChange(sinistro: sinistro, isTradizionale: false, path: path, hasFoto: hasFoto)
            }
        }
    }
    
    /// Verifica se esistono foto nella cartella del sinistro
    private func checkHasFotoInPath(_ path: String) -> Bool {
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif"]
        
        // Cartelle da controllare per le foto
        let foldersToCheck = [
            path,
            (path as NSString).appendingPathComponent("Foto"),
            (path as NSString).appendingPathComponent("Documentazione"),
            (path as NSString).appendingPathComponent("Documentazione Fotografica")
        ]
        
        for folder in foldersToCheck {
            guard FileManager.default.fileExists(atPath: folder) else { continue }
            
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: folder) {
                for file in contents {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if photoExtensions.contains(ext) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Aggiorna lo stato del sinistro quando cambia il tipo di perizia
    private func updateStateForTipoPeriziaChange(sinistro: Sinistro, isTradizionale: Bool, path: String, hasFoto: Bool = true) {
        guard let context = sinistro.managedObjectContext else { return }
        
        Task {
            do {
                let hasFotoCheck = isTradizionale ? true : hasFoto
                try await StatoManager.shared.updateStateBasedOnFolderStructure(
                    for: sinistro,
                    hasSopralluogoFolder: isTradizionale,
                    hasFoto: hasFotoCheck,
                    context: context
                )
            } catch {
                print("[AutoCheck] ⚠️ Errore aggiornamento stato per cambio tipo perizia: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkGiustificativi(sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Cerca tag giustificativi (FileTagManager è @MainActor)
        if let giustificativiTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "giustificativi" }) {
            Task { @MainActor in
                let filesWithTag = fileTagManager.getFilesWithTag(giustificativiTag)
                if filesWithTag.contains(where: { $0.contains(riferimento) }) {
                    sinistro.giustificativi = true
                }
            }
        }
    }
    
    @discardableResult
    private func applyTag(_ tagId: String, to url: URL, attoSottotipo: String? = nil) async -> Bool {
        // Verifica preliminari (possono essere fatti su background thread)
        let path = url.path
        
        // Applica il tag sul main thread (FileTagManager è @MainActor)
        return await MainActor.run {
            // Non rimuovere tag esistenti - aggiungi solo se non presente
            let existingTags = fileTagManager.getTagsForFile(at: path)
            if existingTags.contains(where: { $0.id == tagId }) {
                return false // Tag già presente
            }
            
            // NON applicare tag ordinari ai file generati (hanno già tag file_*)
            let hasGeneratedTag = existingTags.contains { FileTagManager.FileTag.closureGeneratedTags.contains($0.id) }
            if hasGeneratedTag {
                print("[AutoCheck] ⏭️ File generato, salto tag ordinario '\(tagId)' → \(url.lastPathComponent)")
                return false // File generato, non applicare tag ordinari
            }
            
            // Non applicare se l'utente ha rimosso manualmente questo tag
            if fileTagManager.wasTagManuallyRemoved(tagId: tagId, fromFile: path) {
                return false // Tag rimosso manualmente dall'utente
            }
            
            // Applica il nuovo tag
            if let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == tagId }) {
                fileTagManager.addTag(tag, toFile: path)
                print("[AutoCheck] ✅ Tag '\(tagId)' → \(url.lastPathComponent)")
                
                // Se è un atto con sottotipo, salva anche il sottotipo
                if let sottotipo = attoSottotipo, FileTagManager.FileTag.attoTags.contains(tagId) {
                    fileTagManager.setAttoSottotipo(sottotipo, forFile: path, tagId: tagId)
                }
                
                return true
            } else {
                print("[AutoCheck] ⚠️ Tag '\(tagId)' non trovato")
                return false
            }
        }
    }
    
    func checkSinistro(_ sinistro: Sinistro) async -> [String] {
        var warnings: [String] = []
        
        // Verifica la presenza dei giustificativi (FileTagManager è @MainActor)
        if let path = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
            let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
            let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
            var hasGiustificativi = false
            if let tag = fatturaTag {
                let filesWithTag = await fileTagManager.getFilesWithTag(tag)
                hasGiustificativi = !filesWithTag.isEmpty
            }
            if !hasGiustificativi, let tag = preventivoTag {
                let filesWithTag = await fileTagManager.getFilesWithTag(tag)
                hasGiustificativi = !filesWithTag.isEmpty
            }
            if !hasGiustificativi {
                warnings.append("⚠️ Non sono presenti giustificativi")
            }
        }
        
        // Verifica la presenza delle foto
        if let path = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
            let fotoTag = FileTagManager.FileTag.availableTags.first { $0.id == "foto" }
            if let tag = fotoTag {
                let filesWithTag = await fileTagManager.getFilesWithTag(tag)
                if filesWithTag.isEmpty {
                    warnings.append("⚠️ Non sono presenti foto")
                }
            }
        }
        
        // Verifica la presenza della perizia
        if let path = fileService.getSinistroPath(riferimento: sinistro.riferimento ?? "") {
            let periziaTag = FileTagManager.FileTag.availableTags.first { $0.id == "perizia" }
            if let tag = periziaTag {
                let filesWithTag = await fileTagManager.getFilesWithTag(tag)
                if filesWithTag.isEmpty {
                    warnings.append("⚠️ Non è presente la perizia")
                }
            }
        }
        
        return warnings
    }
    
    /// Esegue una scansione Excel massiva di tutti i sinistri nella cartella interna
    func performMassiveExcelScan() async -> (processed: Int, updated: Int, errors: Int) {
        print("[AutoCheck] 🔍 Inizio scansione Excel massiva")
        
        // Usa la cartella interna Application Support
        let internalClaimsPath = fileService.getInternalClaimsPath()
        let foldersToScan = [internalClaimsPath]
        
        var processed = 0
        var updated = 0
        var errors = 0
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        for directoryPath in foldersToScan {
            print("[AutoCheck] 📁 Scansione directory: \(directoryPath)")
            
            do {
                let directoryURL = URL(fileURLWithPath: directoryPath)
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                // Filtra solo le directory
                let directories = contents.filter { url in
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                        return resourceValues.isDirectory == true
                    } catch {
                        return false
                    }
                }
                
                print("[AutoCheck] 📂 Trovate \(directories.count) cartelle in \(directoryPath)")
                
                for folderURL in directories {
                    let folderName = folderURL.lastPathComponent
                    
                    // Cerca pattern per riferimento interno a 7 cifre
                    let pattern = #"\b([0-9]{7})\b"#
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(location: 0, length: folderName.utf16.count)
                        
                        if let match = regex.firstMatch(in: folderName, range: range) {
                            let riferimentoRange = Range(match.range(at: 1), in: folderName)!
                            let riferimentoInterno = String(folderName[riferimentoRange])
                            
                            print("[AutoCheck] 📋 Processamento cartella: \(folderName) -> \(riferimentoInterno)")
                            processed += 1
                            
                            // Cerca o crea il sinistro nel database
                            await context.perform {
                                let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
                                fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimentoInterno)
                                
                                do {
                                    let existingSinistri = try context.fetch(fetchRequest)
                                    let sinistro: Sinistro
                                    
                                    if let existing = existingSinistri.first {
                                        sinistro = existing
                                        print("[AutoCheck] ✅ Sinistro \(riferimentoInterno) trovato nel DB")
                                    } else {
                                        // Modifica: Skippa la creazione di nuovi sinistri durante la scansione massiva
                                        print("[AutoCheck] ⏭️ Sinistro \(riferimentoInterno) non presente nel DB, salto scansione Excel")
                                        return
                                    }
                                    
                                    // Esegui la scansione Excel per questo sinistro
                                    Task {
                                        do {
                                            print("[AutoCheck] 📊 Ricerca file Excel per \(riferimentoInterno)")
                                            let excelURL = try await ExcelFinderService.shared.findElaboratoPeritale(forSinistro: sinistro)
                                            print("[AutoCheck] 📊 File Excel trovato: \(excelURL.lastPathComponent)")
                                            
                                            let data = try await ExcelReaderService.shared.readExcelFile(at: excelURL)
                                            print("[AutoCheck] 📊 Dati Excel letti per \(riferimentoInterno)")
                                            
                                            await MainActor.run {
                                                context.perform {
                                                    self.updateSinistroFromExcelData(sinistro, with: data)
                                                    do {
                                                        try context.save()
                                                        updated += 1
                                                        print("[AutoCheck] ✅ Sinistro \(riferimentoInterno) aggiornato con dati Excel")
                                                    } catch {
                                                        print("[AutoCheck] ❌ Errore salvataggio \(riferimentoInterno): \(error)")
                                                        errors += 1
                                                    }
                                                }
                                            }
                                        } catch {
                                            print("[AutoCheck] ⚠️ Errore Excel per \(riferimentoInterno): \(error)")
                                            errors += 1
                                        }
                                    }
                                } catch {
                                    print("[AutoCheck] ❌ Errore fetch/create sinistro \(riferimentoInterno): \(error)")
                                    errors += 1
                                }
                            }
                        }
                    }
                }
            } catch {
                print("[AutoCheck] ❌ Errore lettura directory \(directoryPath): \(error)")
                errors += 1
            }
        }
        
        // Aspetta un po' per permettere alle operazioni asincrone di completarsi
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 secondi
        
        print("[AutoCheck] ✅ Scansione Excel completata: \(processed) processati, \(updated) aggiornati, \(errors) errori")
        return (processed, updated, errors)
    }
    
    /// Verifica se una cartella è nuova (prima volta che la troviamo) e esegue scansione Excel
    func checkAndProcessNewFolder(path: String, riferimento: String) async {
        print("[AutoCheck] 🆕 Verifica nuova cartella: \(riferimento)")
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            let fetchRequest: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
            fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            
            do {
                let existingSinistri = try context.fetch(fetchRequest)
                
                // Se il sinistro esiste ma non ha ancora dati Excel (nessun nome assicurato o importi)
                if let sinistro = existingSinistri.first {
                    let needsExcelScan = sinistro.nomeAssicurato?.isEmpty != false ||
                                       sinistro.richiesta?.doubleValue == 0 ||
                                       sinistro.numeroSinistroCompagnia?.isEmpty != false
                    
                    print("[AutoCheck] 🔍 Sinistro \(riferimento) - needsExcelScan: \(needsExcelScan)")
                    
                    if needsExcelScan {
                        print("[AutoCheck] 📊 Sinistro \(riferimento) necessita scansione Excel")
                        
                        Task {
                            await self.performAutoChecks(for: sinistro, context: context)
                        }
                    } else {
                        print("[AutoCheck] ✅ Sinistro \(riferimento) già aggiornato")
                    }
                } else {
                    print("[AutoCheck] ⚠️ Sinistro \(riferimento) non trovato nel database")
                }
            } catch {
                print("[AutoCheck] ❌ Errore verifica sinistro \(riferimento): \(error)")
            }
        }
    }
    
    // MARK: - Scansione Nuovi File
    
    /// Scansiona SOLO i file che non hanno ancora tag (per nuovi file arrivati in cartella)
    /// Chiamare questo metodo quando si aprono cartelle o si rilevano nuovi file
    func scanNewFilesForTags(inPath path: String) {
        let tagsEnabled = UserDefaults.standard.object(forKey: "enableAutoCheckTags") as? Bool ?? true
        guard tagsEnabled else {
            print("[AutoCheck] ⏭️ Auto-tag disabilitato nelle impostazioni")
            return
        }
        
        // Escludi la cartella "Da Chiudere" dalla scansione
        let pathLower = path.lowercased()
        if pathLower.contains("/da chiudere") || pathLower.contains("/perx-cache") {
            print("[AutoCheck] ⏭️ Skip scansione cartella Da Chiudere")
            return
        }
        
        print("[AutoCheck] 🔍 Scansione nuovi file per tag in: \(path)")
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let files = self.scanDirectory(path)
            // Filtra i file senza tag (chiamata main actor per getTagsForFile)
            Task { @MainActor in
                let untaggedFiles = files.filter { file in
                    // Escludi anche file che sono nella cartella "Da Chiudere"
                    let p = file.url.path.lowercased()
                    guard !p.contains("/da chiudere/") && !p.contains("/perx-cache/") else { return false }
                    let existingTags = self.fileTagManager.getTagsForFile(at: file.url.path)
                    return existingTags.isEmpty
                }
                
                if untaggedFiles.isEmpty {
                    print("[AutoCheck] ✅ Nessun nuovo file senza tag trovato")
                    return
                }
                
                print("[AutoCheck] 📁 Trovati \(untaggedFiles.count) file senza tag da analizzare")
                await self.checkAndApplyTags(for: untaggedFiles)
            }
        }
    }
    
    /// Scansiona file nuovi in una sottocartella specifica
    func scanNewFilesForTags(inSubfolder subfolder: String, rootPath: String) {
        let tagsEnabled = UserDefaults.standard.object(forKey: "enableAutoCheckTags") as? Bool ?? true
        guard tagsEnabled else { return }
        
        // Escludi la cartella "Da Chiudere"
        if subfolder.lowercased() == "da chiudere" || subfolder.lowercased() == "perx-cache" {
            print("[AutoCheck] ⏭️ Skip scansione cartella Da Chiudere")
            return
        }
        
        let subfolderPath = (rootPath as NSString).appendingPathComponent(subfolder)
        print("[AutoCheck] 🔍 Scansione sottocartella per nuovi file: \(subfolder)")
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let files = self.scanDirectory(subfolderPath)
            // Filtra i file senza tag (chiamata main actor per getTagsForFile)
            Task { @MainActor in
                let untaggedFiles = files.filter { file in
                    // Escludi anche file che sono nella cartella "Da Chiudere"
                    let p = file.url.path.lowercased()
                    guard !p.contains("/da chiudere/") && !p.contains("/perx-cache/") else { return false }
                    let existingTags = self.fileTagManager.getTagsForFile(at: file.url.path)
                    return existingTags.isEmpty
                }
                
                if !untaggedFiles.isEmpty {
                    print("[AutoCheck] 📁 \(untaggedFiles.count) nuovi file in \(subfolder)")
                    await self.checkAndApplyTags(for: untaggedFiles)
                }
            }
        }
    }
    
    /// Scansiona un singolo file nuovo per applicare tag
    func scanSingleFileForTags(at url: URL) {
        let tagsEnabled = UserDefaults.standard.object(forKey: "enableAutoCheckTags") as? Bool ?? true
        guard tagsEnabled else { return }
        
        // Escludi file nella cartella "Da Chiudere"
        let p = url.path.lowercased()
        if p.contains("/da chiudere/") || p.contains("/perx-cache/") {
            print("[AutoCheck] ⏭️ Skip file nella cartella Da Chiudere: \(url.lastPathComponent)")
            return
        }
        
        print("[AutoCheck] 🔍 Analisi singolo file per tag: \(url.lastPathComponent)")
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modificationDate = (attrs[.modificationDate] as? Date) ?? .distantPast
            
            let fileItem = FileService.FileItem(
                id: url.path,
                url: url,
                isDirectory: false,
                icon: nil,
                size: size,
                modificationDate: modificationDate
            )
            
            // Verifica se il file ha già tag (chiamata main actor per getTagsForFile)
            Task { @MainActor in
                let existingTags = self.fileTagManager.getTagsForFile(at: url.path)
                guard existingTags.isEmpty else {
                    print("[AutoCheck] ⏭️ File già taggato: \(url.lastPathComponent)")
                    return
                }
                
                await self.checkAndApplyTags(for: [fileItem])
            }
        }
    }
    
    // MARK: - Incarico PDF Parsing (Gruppo Generali)
    
    /// Verifica manuale: parse del PDF incarico selezionato e aggiornamento campi sul sinistro.
    /// Usato dal menu contestuale in Cartella (su file con tag "incarico").
    func verifyRegolaritaAmministrativaManually(fromIncaricoPDF pdfURL: URL, sinistro: Sinistro) async {
        // Applicabile solo a Gruppo Generali
        let gruppo = GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo)
        guard gruppo == .generali else {
            print("[AutoCheck] ⏭️ Verifica manuale incarico: non è Gruppo Generali, skip")
            return
        }
        
        guard let riferimento = sinistro.riferimento else { return }
        print("[AutoCheck] 🔎 Verifica manuale regolarità amm. da PDF incarico: \(pdfURL.lastPathComponent) (\(riferimento))")
        
        let parseResult = IncaricoPDFParser.shared.parse(pdfPath: pdfURL.path)
        guard parseResult.success else {
            print("[AutoCheck] ⚠️ Verifica manuale: parsing fallito: \(parseResult.message ?? "errore sconosciuto")")
            return
        }
        
        await MainActor.run {
            let context = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
            context.perform {
                if let regolarita = parseResult.regolaritaAmministrativa {
                    sinistro.regolaritaAmministrativa = NSNumber(value: regolarita)
                    if regolarita {
                        sinistro.dataPagamentoPremio = parseResult.dataPagamentoPremio
                    } else {
                        sinistro.dataPagamentoPremio = nil
                        self.createIrregolaritaTask(for: sinistro)
                    }
                }
                
                // Altri dati (solo se non già presenti)
                if sinistro.dataSinistro == nil, let d = parseResult.dataSinistro {
                    sinistro.dataSinistro = d
                }
                if sinistro.dataDenuncia == nil, let d = parseResult.dataDenuncia {
                    sinistro.dataDenuncia = d
                }
                if sinistro.dataIncarico == nil, let d = parseResult.dataIncarico {
                    sinistro.dataIncarico = d
                }
                
                let codiceAgenziaIsBlank = (sinistro.codiceAgenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if codiceAgenziaIsBlank, let codice = parseResult.codiceAgenzia, !codice.isEmpty {
                    sinistro.codiceAgenzia = codice
                }
                
                let nomeAgenziaIsBlank = (sinistro.agenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if nomeAgenziaIsBlank, let nome = parseResult.nomeAgenzia, !nome.isEmpty {
                    sinistro.agenzia = nome
                }
                
                let subAgenziaIsBlank = (sinistro.subagenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if subAgenziaIsBlank, let sub = parseResult.subagenzia, !sub.isEmpty {
                    sinistro.subagenzia = sub
                }
                
                do {
                    try context.save()
                    print("[AutoCheck] ✅ Verifica manuale: dati incarico salvati per \(riferimento)")
                } catch {
                    print("[AutoCheck] ❌ Verifica manuale: errore salvataggio dati incarico: \(error)")
                }
            }
        }
    }
    
    /// Estrae regolarità amministrativa e data pagamento premio dal PDF incarico
    /// Applicabile solo a sinistri del Gruppo Generali
    private func checkIncaricoGenerali(sinistro: Sinistro) async {
        // Verifica se è già stata rilevata la regolarità
        if sinistro.regolaritaAmministrativa != nil {
            print("[AutoCheck] ⏭️ Regolarità amministrativa già rilevata, skip parsing incarico")
            return
        }
        
        // Verifica se il sinistro è del Gruppo Generali
        let gruppo = GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo)
        guard gruppo == .generali else {
            print("[AutoCheck] ⏭️ Non è Gruppo Generali (\(sinistro.gruppo ?? "N/A")), skip parsing incarico")
            return
        }
        
        guard let riferimento = sinistro.riferimento else { return }
        print("[AutoCheck] 📄 Ricerca PDF incarico per \(riferimento) (Gruppo Generali)")
        
        // Ottieni i file con tag "incarico"
        guard let incaricoTag = FileTagManager.FileTag.availableTags.first(where: { $0.id == "incarico" }) else {
            print("[AutoCheck] ⚠️ Tag 'incarico' non trovato tra i tag disponibili")
            return
        }
        
        let incaricoFiles = await MainActor.run {
            fileTagManager.getFilesWithTag(incaricoTag)
        }
        
        guard let sinistroPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[AutoCheck] ⚠️ Path sinistro non trovato")
            return
        }
        
        // Filtra solo i file del sinistro corrente
        let sinistroIncaricoFiles = incaricoFiles.filter { $0.hasPrefix(sinistroPath) }
        
        guard !sinistroIncaricoFiles.isEmpty else {
            print("[AutoCheck] ℹ️ Nessun file con tag 'incarico' trovato per \(riferimento)")
            return
        }
        
        print("[AutoCheck] 📑 Trovati \(sinistroIncaricoFiles.count) file con tag 'incarico'")
        
        // Usa il parser per trovare il PDF corretto e parsificare
        guard let bestPdfPath = IncaricoPDFParser.shared.findBestIncaricoFile(fromPaths: sinistroIncaricoFiles) else {
            print("[AutoCheck] ⚠️ Nessun PDF valido tra i file incarico")
            return
        }
        
        print("[AutoCheck] 📄 Parsing PDF: \(URL(fileURLWithPath: bestPdfPath).lastPathComponent)")
        
        let parseResult = IncaricoPDFParser.shared.parse(pdfPath: bestPdfPath)
        
        guard parseResult.success else {
            print("[AutoCheck] ⚠️ Parsing fallito: \(parseResult.message ?? "errore sconosciuto")")
            return
        }
        
        // Aggiorna il sinistro con i dati estratti
        await MainActor.run {
            let context = sinistro.managedObjectContext ?? PersistenceController.shared.container.viewContext
            context.perform {
                if let regolarita = parseResult.regolaritaAmministrativa {
                    sinistro.regolaritaAmministrativa = NSNumber(value: regolarita)
                    print("[AutoCheck] ✅ Regolarità amministrativa: \(regolarita ? "Sì" : "No")")
                    
                    if regolarita {
                        sinistro.dataPagamentoPremio = parseResult.dataPagamentoPremio
                        if let data = parseResult.dataPagamentoPremio {
                            let formatter = DateFormatter()
                            formatter.dateStyle = .short
                            print("[AutoCheck] ✅ Data pagamento premio: \(formatter.string(from: data))")
                        }
                    } else {
                        sinistro.dataPagamentoPremio = nil
                        // Genera task urgente per irregolarità amministrativa
                        self.createIrregolaritaTask(for: sinistro)
                    }
                }
                
                // Altri dati (solo se non già presenti)
                if sinistro.dataSinistro == nil, let d = parseResult.dataSinistro {
                    sinistro.dataSinistro = d
                }
                if sinistro.dataDenuncia == nil, let d = parseResult.dataDenuncia {
                    sinistro.dataDenuncia = d
                }
                if sinistro.dataIncarico == nil, let d = parseResult.dataIncarico {
                    sinistro.dataIncarico = d
                }
                
                let codiceAgenziaIsBlank = (sinistro.codiceAgenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if codiceAgenziaIsBlank, let codice = parseResult.codiceAgenzia, !codice.isEmpty {
                    sinistro.codiceAgenzia = codice
                }
                
                let nomeAgenziaIsBlank = (sinistro.agenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if nomeAgenziaIsBlank, let nome = parseResult.nomeAgenzia, !nome.isEmpty {
                    sinistro.agenzia = nome
                }
                
                let subAgenziaIsBlank = (sinistro.subagenzia ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if subAgenziaIsBlank, let sub = parseResult.subagenzia, !sub.isEmpty {
                    sinistro.subagenzia = sub
                }
                
                do {
                    try context.save()
                    print("[AutoCheck] ✅ Dati incarico salvati per \(riferimento)")
                } catch {
                    print("[AutoCheck] ❌ Errore salvataggio dati incarico: \(error)")
                }
            }
        }
    }
    
    /// Crea un task urgente per verificare la regolarità amministrativa con l'agenzia
    private func createIrregolaritaTask(for sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento else { return }
        
        print("[AutoCheck] ⚠️ Irregolarità amministrativa rilevata, creazione task urgente")
        
        // Crea il task usando TaskManager
        let task = DailyTask(
            title: "🚨 Verificare regolarità amministrativa",
            description: "Il sinistro \(riferimento) presenta irregolarità amministrativa. Contattare l'agenzia per verificare.",
            type: .manual,
            sinistroID: riferimento,
            priority: 3.0,
            deadline: Date(),
            scheduledDate: Date(),
            estimatedDuration: 900,
            isTimeSensitive: true
        )
        
        Task { @MainActor in
            TaskManager.shared.addTask(task)
            print("[AutoCheck] ✅ Task urgente creato per \(riferimento)")
        }
    }
    
    // MARK: - Sanity Check Helpers
    
    /// Verifica se una stringa sembra un numero sinistro (pattern alfanumerico con / o -)
    private func looksLikeClaimNumber(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        // Pattern tipici per numeri sinistro:
        // - Contiene / o - (es. "2024/12345", "SIN-2024-001")
        // - È principalmente alfanumerico con pochi spazi
        // - Ha almeno 5 caratteri
        
        // Se contiene / o - è probabilmente un numero sinistro
        if trimmed.contains("/") || trimmed.contains("-") {
            return true
        }
        
        // Se è tutto maiuscolo con numeri, probabilmente è un codice
        let uppercaseAndNumbers = CharacterSet.uppercaseLetters.union(.decimalDigits)
        let filtered = trimmed.unicodeScalars.filter { uppercaseAndNumbers.contains($0) }
        if filtered.count > trimmed.count / 2 && trimmed.count >= 5 {
            // Più della metà sono lettere maiuscole o numeri
            // E non contiene spazi tipici dei nomi
            if !trimmed.contains(" ") || trimmed.filter({ $0 == " " }).count <= 1 {
                return true
            }
        }
        
        return false
    }
    
    /// Verifica se una stringa sembra un nome agenzia (parole con spazi)
    private func looksLikeAgencyName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        // Un nome agenzia tipicamente:
        // - Ha più parole (spazi)
        // - Non contiene / o -
        // - Ha lettere miste (non tutto maiuscolo)
        
        let words = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        
        // Se ha 2+ parole e non contiene / è probabilmente un nome
        if words.count >= 2 && !trimmed.contains("/") {
            return true
        }
        
        // Se è una singola parola ma sembra un nome (iniziale maiuscola, resto minuscolo)
        if words.count == 1 && trimmed.count >= 3 {
            let first = trimmed.first!
            let rest = trimmed.dropFirst()
            if first.isUppercase && rest.allSatisfy({ $0.isLowercase || !$0.isLetter }) {
                return true
            }
        }
        
        return false
    }
} 
