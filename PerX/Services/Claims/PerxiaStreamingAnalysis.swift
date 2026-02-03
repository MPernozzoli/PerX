import Foundation
import CoreData

/// Servizio per l'analisi streaming dei sinistri con tracciabilità fonte e confidenza
extension PerxiaService {
    
    // MARK: - Pipeline Streaming Principale
    
    /// Analizza un sinistro in modalità streaming, generando i beni man mano
    func analizzaSinistroStreaming(
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void,
        beneStreamCallback: @escaping @MainActor (BeneAnalysisStreaming) -> Void,
        relazioneStreamCallback: @escaping @MainActor (String) -> Void,
        quadroContrattualeCallback: @escaping @MainActor (AnalisiQuadroContrattuale) -> Void
    ) async -> Result<AnalisiSinistroCompleta, AIError> {
        
        print("[PerxiaStreaming] 🚀 Avvio analisi streaming per \(sinistro.riferimento ?? "N/A")")

        if (sinistro.stato ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("chius") {
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            return .failure(.processingError("Cartella sinistro non trovata"))
        }
        
        // Verifica prerequisiti (sul main thread perché AutoTaggingService è @MainActor)
        let hasPhotos = await MainActor.run {
            AutoCheckService.shared.hasTaggedPhotos(for: sinistro)
        }
        if !hasPhotos {
            await MainActor.run {
                streamCallback("⚠️ Nessuna foto taggata trovata. Avvio autotagging...\n")
            }
            
            let tagged = await AutoCheckService.shared.runPhotoAutoTagging(for: sinistro, forceReanalyze: false)
            if tagged == 0 {
                return .failure(.processingError("Nessuna foto da analizzare"))
            }
        }
        
        // FASE 1: Raccolta e raggruppamento foto
        await MainActor.run {
            streamCallback("📸 Raccolta foto taggate...\n")
            progressCallback(0.05)
        }
        
        let fotoRaggruppate = await raggruppaFotoPerBeneStreaming(rootPath: rootPath)
        let beniTotali = fotoRaggruppate.count
        
        guard beniTotali > 0 else {
            return .failure(.processingError("Nessun bene identificato dalle foto"))
        }
        
        await MainActor.run {
            streamCallback("✅ Trovati \(beniTotali) beni da analizzare\n\n")
            progressCallback(0.10)
        }
        
        // FASE 2: Analisi parallela foto ubicazione (per Quadro Contrattuale) e giustificativi
        let fotoUbicazione = await trovaTutteLeFotoUbicazione(rootPath: rootPath)
        var quadroContrattuale: AnalisiQuadroContrattuale? = nil
        
        // Analizza giustificativi in parallelo
        let (beniTaggati, componentiTaggati) = await raccogliBeniComponentiDaTag(rootPath: rootPath)
        let fileGiustificativi = await trovaFileGiustificativi(rootPath: rootPath)
        var analisiGiustificativi: AnalisiGiustificativi? = nil
        
        if !fileGiustificativi.isEmpty {
            await MainActor.run {
                streamCallback("📄 Analisi giustificativi (\(fileGiustificativi.count) file)...\n")
            }
            
            analisiGiustificativi = await analizzaGiustificativiStreaming(
                paths: fileGiustificativi,
                beniTaggati: beniTaggati,
                componentiTaggati: componentiTaggati,
                sinistro: sinistro
            )
            
            if analisiGiustificativi != nil {
                await MainActor.run {
                    streamCallback("✅ Analisi giustificativi completata\n\n")
                }
            }
        }
        
        if !fotoUbicazione.isEmpty {
            await MainActor.run {
                streamCallback("🏠 Analisi foto ubicazione (\(fotoUbicazione.count) foto)...\n")
            }
            
            quadroContrattuale = await analizzaFotoUbicazionePerQuadro(
                foto: fotoUbicazione,
                sinistro: sinistro
            )
            
            if let qc = quadroContrattuale {
                await MainActor.run {
                    quadroContrattualeCallback(qc)
                    streamCallback("✅ Analisi ubicazione completata\n\n")
                }
            }
        }
        
        // Estrai importo richiesto dalla denuncia se disponibile
        let fileDenuncia = await trovaFileDenuncia(rootPath: rootPath)
        var importoRichiesto: Double? = nil
        if let denunciaPath = fileDenuncia {
            if let analisiDenuncia = await analizzaDenunciaStreaming(path: denunciaPath, sinistro: sinistro) {
                importoRichiesto = analisiDenuncia.importoRichiesto
            }
        }
        
        // FASE 3: Analisi beni in streaming
        await MainActor.run {
            streamCallback("⚡ Analisi beni...\n")
        }
        
        var beniAnalizzati: [BeneAnalysis] = []
        var beniStreaming: [BeneAnalysisStreaming] = [] // Mantieni anche i dati streaming
        // Ordina i beni alfabeticamente, ma metti "Bene non identificato" per ultimo
        let beniList = Array(fotoRaggruppate.keys).sorted { b1, b2 in
            if b1 == "Bene non identificato" { return false }
            if b2 == "Bene non identificato" { return true }
            return b1.localizedCaseInsensitiveCompare(b2) == .orderedAscending
        }
        
        for (index, nomeBene) in beniList.enumerated() {
            guard let fotoDelBene = fotoRaggruppate[nomeBene] else { continue }
            
            // Estrai info giustificativi per questo bene
            let vociGiustificativo = analisiGiustificativi?.vociPerBene.filter { 
                $0.bene.lowercased() == nomeBene.lowercased() 
            } ?? []
            
            await MainActor.run {
                let giustInfo = vociGiustificativo.isEmpty ? "" : " + giustificativi"
                streamCallback("  → \(nomeBene) (\(fotoDelBene.count) foto\(giustInfo))...")
            }
            
            // Analizza il bene
            if let beneStreaming = await analizzaBeneStreaming(
                nomeBene: nomeBene,
                foto: fotoDelBene,
                sinistro: sinistro,
                fulminazione: fulminazione,
                vociGiustificativo: vociGiustificativo,
                importoRichiesto: importoRichiesto
            ) {
                // Callback immediato per UI
                await MainActor.run {
                    beneStreamCallback(beneStreaming)
                    streamCallback(" ✅\n")
                }
                
                // Mantieni i dati streaming
                beniStreaming.append(beneStreaming)
                
                // Converti a BeneAnalysis per compatibilità
                let beneAnalysis = convertToBeneAnalysis(beneStreaming)
                beniAnalizzati.append(beneAnalysis)
            } else {
                await MainActor.run {
                    streamCallback(" ⚠️ (incompleto)\n")
                }
            }
            
            let progress = 0.10 + (Double(index + 1) / Double(beniTotali)) * 0.60
            await MainActor.run {
                progressCallback(progress)
            }
        }
        
        // FASE 4: Generazione relazione in streaming
        await MainActor.run {
            streamCallback("\n📝 Generazione relazione...\n")
            progressCallback(0.75)
        }
        
        let complessita = calcolaComplessitaSinistro(beni: beniAnalizzati, giustificativi: nil as AnalisiGiustificativi?)
        
        let analisiCompleta = AnalisiSinistroCompleta(
            beni: beniAnalizzati,
            complessita: complessita,
            denuncia: nil,
            giustificativi: nil,
            verificaUbicazione: quadroContrattuale?.verificaIndirizzo != nil ? VerificaUbicazione(
                corrispondenza: quadroContrattuale?.verificaIndirizzo?.esito ?? "non_verificabile",
                evidenzeTrovate: [],
                discrepanze: [],
                confidenza: 0.7,
                note: nil
            ) : nil,
            sopralluogo: sopralluogo,
            fulminazione: fulminazione,
            noteGenerali: nil
        )
        
        // Genera relazione in streaming
        await generaRelazioneStreaming(
            sinistro: sinistro,
            analisi: analisiCompleta,
            ubicazione: ubicazione,
            streamCallback: relazioneStreamCallback
        )
        
        await MainActor.run {
            progressCallback(1.0)
            streamCallback("\n✅ Analisi completata!\n")
        }
        
        // Salva in Core Data (sia dati base che streaming)
        salvaAnalisiCompleta(sinistro: sinistro, analisi: analisiCompleta)
        salvaAnalisiStreaming(sinistro: sinistro, beniStreaming: beniStreaming, quadroContrattuale: quadroContrattuale)
        
        return .success(analisiCompleta)
    }
    
    // MARK: - Raggruppamento Foto per Bene
    
    private func raggruppaFotoPerBeneStreaming(rootPath: String) async -> [String: [FotoConTag]] {
        var result: [String: [FotoConTag]] = [:]
        // Mappa per tracciare la prima versione del nome (per mantenere il case originale)
        var nomeOriginale: [String: String] = [:]
        
        let fotoTaggate = await trovaTutteLesFotoTaggate(rootPath: rootPath)
        
        for (path, tags) in fotoTaggate {
            let beneRaw = await estraiBeneDaTag(path: path, tags: tags)
            let componente = await estraiComponenteDaTag(path: path, tags: tags)
            let tipoTag = determinaTipoFotoDaTag(tags: tags)
            
            // Normalizza il nome del bene per il raggruppamento (case-insensitive)
            let beneNormalizzato: String
            if let beneRaw = beneRaw, !beneRaw.isEmpty {
                let chiave = beneRaw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                // Memorizza la prima versione trovata come nome "ufficiale"
                if nomeOriginale[chiave] == nil {
                    // Capitalizza la prima lettera
                    nomeOriginale[chiave] = beneRaw.prefix(1).uppercased() + beneRaw.dropFirst().lowercased()
                }
                beneNormalizzato = nomeOriginale[chiave]!
            } else {
                // Se non ha un bene associato ma ha tag di ubicazione, skippa "Bene non identificato"
                let hasUbicazioneTag = tags.contains { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }
                if hasUbicazioneTag {
                    continue // Le foto di ubicazione non devono essere raggruppate come bene
                }
                beneNormalizzato = "Bene non identificato"
            }
            
            let foto = FotoConTag(
                path: path,
                bene: beneNormalizzato,
                componente: componente,
                tipoTag: tipoTag,
                tags: tags
            )
            
            if result[beneNormalizzato] == nil {
                result[beneNormalizzato] = []
            }
            result[beneNormalizzato]?.append(foto)
        }
        
        // Rimuovi "Bene non identificato" se è vuoto o se tutte le foto hanno altri beni
        if let nonId = result["Bene non identificato"], nonId.isEmpty {
            result.removeValue(forKey: "Bene non identificato")
        }
        
        print("[PerxiaStreaming] 📊 Raggruppate foto: \(result.mapValues { $0.count })")
        return result
    }
    
    struct FotoConTag {
        let path: String
        let bene: String
        let componente: String?
        let tipoTag: TipoFoto
        let tags: Set<FileTagManager.FileTag>
    }
    
    private func determinaTipoFotoDaTag(tags: Set<FileTagManager.FileTag>) -> TipoFoto {
        let tagIds = Set(tags.map { $0.id })
        
        if tagIds.contains("foto_ubicazione_rischio") { return .ubicazione }
        if tagIds.contains("foto_test_funzionale") || tagIds.contains("foto_test_isolamento") { return .misura }
        if tagIds.contains("foto_componente") || tagIds.contains("foto_scheda") { return .scheda }
        if tagIds.contains("foto_bene") || tagIds.contains("foto_dettaglio_bene") { return .beneGenerale }
        if tagIds.contains("preventivo") || tagIds.contains("fattura") { return .giustificativo }
        
        return .altro
    }
    
    // MARK: - Analisi Bene Streaming
    
    private func analizzaBeneStreaming(
        nomeBene: String,
        foto: [FotoConTag],
        sinistro: Sinistro,
        fulminazione: Bool,
        vociGiustificativo: [VoceGiustificativo],
        importoRichiesto: Double?
    ) async -> BeneAnalysisStreaming? {
        
        // Separa foto per tipo
        let fotoGenerali = foto.filter { $0.tipoTag == .beneGenerale || $0.tipoTag == .beneDettaglio }
        let fotoSchede = foto.filter { $0.tipoTag == .scheda }
        let fotoMisure = foto.filter { $0.tipoTag == .misura }
        
        // Prima chiamata IA: Analisi dettagliata foto
        // Se ci sono più foto, usa batch paralleli per cloud
        var analisiDettagliate: [AnalisiDettaglioFoto] = []
        
        if foto.count > 1 {
            // Usa batch paralleli per cloud
            analisiDettagliate = await analizzaFotoInBatchParalleli(
                foto: foto,
                sinistro: sinistro
            )
        } else {
            // Singola foto: analisi normale
            for f in foto {
                if let analisi = await analizzaFotoDettagliata(foto: f, sinistro: sinistro) {
                    analisiDettagliate.append(analisi)
                }
            }
        }
        
        guard !analisiDettagliate.isEmpty else { return nil }
        
        // Seconda chiamata IA: Sintesi per bene
        return await sintetizzaBeneStreaming(
            nomeBene: nomeBene,
            analisi: analisiDettagliate,
            fotoGenerali: fotoGenerali.map { $0.path },
            fotoSchede: fotoSchede.map { $0.path },
            fotoMisure: fotoMisure.map { $0.path },
            fulminazione: fulminazione,
            vociGiustificativo: vociGiustificativo,
            importoRichiesto: importoRichiesto
        )
    }
    
    // MARK: - Analisi Dettagliata Singola Foto
    
    private func analizzaFotoDettagliata(
        foto: FotoConTag,
        sinistro: Sinistro
    ) async -> AnalisiDettaglioFoto? {
        
        let prompt = buildPromptAnalisiDettagliata(foto: foto, sinistro: sinistro)
        
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "images": AnyCodable([foto.path]),
                "stream": AnyCodable(false),
                "systemPrompt": AnyCodable("Sei un perito assicurativo esperto in fenomeni elettrici. Analizza le foto in dettaglio fornendo risposte JSON strutturate.")
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task) { aiResult in
                    guard !resumed else { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi")))
                    }
                }
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parseAnalisiDettagliata(aiResult, foto: foto)
        case .failure:
            return nil
        }
    }
    
    // MARK: - Analisi Batch Paralleli (Cloud)
    
    /// Analizza multiple foto in batch paralleli per ridurre i tempi quando si usa il cloud
    private func analizzaFotoInBatchParalleli(
        foto: [FotoConTag],
        sinistro: Sinistro
    ) async -> [AnalisiDettaglioFoto] {
        
        // Batch size ottimale per cloud (3-4 foto per batch)
        let batchSize = 3
        let batches = stride(from: 0, to: foto.count, by: batchSize).map { idx in
            Array(foto[idx..<min(idx + batchSize, foto.count)])
        }
        
        print("[PerxiaStreaming] ☁️ Analisi batch paralleli: \(batches.count) batch da max \(batchSize) foto")
        
        var results: [AnalisiDettaglioFoto] = []
        
        // Esegui tutti i batch in parallelo
        await withTaskGroup(of: [AnalisiDettaglioFoto].self) { group in
            // Avvia tutti i task in parallelo
            for batch in batches {
                group.addTask {
                    await self.analizzaBatchFoto(batch: batch, sinistro: sinistro)
                }
            }
            
            // Raccogli i risultati man mano che completano
            for await batchResults in group {
                results.append(contentsOf: batchResults)
            }
        }
        
        print("[PerxiaStreaming] ✅ Batch paralleli completati: \(results.count) foto analizzate")
        return results
    }
    
    /// Analizza un batch di foto usando cloud
    private func analizzaBatchFoto(
        batch: [FotoConTag],
        sinistro: Sinistro
    ) async -> [AnalisiDettaglioFoto] {
        
        // Se il batch ha una sola foto, usa la funzione normale
        if batch.count == 1, let foto = batch.first {
            if let analisi = await analizzaFotoDettagliata(foto: foto, sinistro: sinistro) {
                return [analisi]
            }
            return []
        }
        
        // Costruisci prompt per batch
        let prompt = buildPromptBatchAnalisi(batch: batch, sinistro: sinistro)
        let imagePaths = batch.map { $0.path }
        
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .cloudOpenAI,  // Batch solo su cloud
            fallbackProviders: [],
            allowFallback: false,
            parameters: [
                "prompt": AnyCodable(prompt),
                "images": AnyCodable(imagePaths),
                "stream": AnyCodable(false),
                "systemPrompt": AnyCodable("Sei un perito assicurativo esperto in fenomeni elettrici. Analizza le foto in dettaglio fornendo risposte JSON strutturate. Rispondi SEMPRE in formato JSON con un array di analisi, una per ogni foto."),
                "response_format": AnyCodable(["type": "json_object"]),
                "max_tokens": AnyCodable(6000)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task) { aiResult in
                    guard !resumed else { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi batch")))
                    }
                }
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parseBatchAnalisiDettagliata(aiResult, batch: batch)
        case .failure:
            print("[PerxiaStreaming] ❌ Errore batch, fallback a analisi singole")
            // Fallback: analizza le foto una alla volta
            var fallbackResults: [AnalisiDettaglioFoto] = []
            for foto in batch {
                if let analisi = await analizzaFotoDettagliata(foto: foto, sinistro: sinistro) {
                    fallbackResults.append(analisi)
                }
            }
            return fallbackResults
        }
    }
    
    /// Costruisce il prompt per l'analisi di un batch di foto
    private func buildPromptBatchAnalisi(batch: [FotoConTag], sinistro: Sinistro) -> String {
        var prompt = """
        Analizza queste \(batch.count) foto per una perizia assicurativa Fenomeno Elettrico.
        
        """
        
        for (index, foto) in batch.enumerated() {
            let fileName = URL(fileURLWithPath: foto.path).lastPathComponent
            prompt += """
            FOTO \(index + 1) - \(fileName):
            - Bene: \(foto.bene)
            \(foto.componente != nil ? "- Componente: \(foto.componente!)" : "")
            - Tipo foto: \(foto.tipoTag.rawValue)
            
            """
        }
        
        prompt += """
        Per OGNI foto, analizza in base al suo tipo e fornisci la struttura JSON corrispondente come definito per l'analisi dettagliata.
        
        JSON RICHIESTO (array di analisi):
        {
            "analisi": [
                {
                    "fotoIndex": 0,
                    "descrizioneGenerale": "...",
                    "qualitaFoto": "...",
                    "analisiBene": {...} oppure "analisiScheda": {...} oppure "analisiMisura": {...} oppure "analisiUbicazione": {...}
                },
                ...
            ]
        }
        
        IMPORTANTE: Fornisci una analisi completa per OGNI foto nel batch.
        """
        
        return prompt
    }
    
    /// Parse dei risultati di un batch
    private func parseBatchAnalisiDettagliata(
        _ aiResult: AIResult,
        batch: [FotoConTag]
    ) -> [AnalisiDettaglioFoto] {
        
        guard let text = aiResult.result?.value as? String else { return [] }
        
        let cleaned = extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Cerca array di analisi
            if let analisiArray = json?["analisi"] as? [[String: Any]] {
                var results: [AnalisiDettaglioFoto] = []
                
                for (index, analisiJson) in analisiArray.enumerated() {
                    guard index < batch.count else { continue }
                    let foto = batch[index]
                    
                    // Converti il JSON in AnalisiDettaglioFoto usando la logica esistente
                    let descrizione = analisiJson["descrizioneGenerale"] as? String ?? ""
                    let qualitaStr = analisiJson["qualitaFoto"] as? String ?? "media"
                    let qualita = QualitaFoto(rawValue: qualitaStr) ?? .media
                    
                    // Parse specifico per tipo (replica la logica di parseAnalisiDettagliata)
                    var analisiBene: AnalisiFotoBene? = nil
                    var analisiScheda: AnalisiFotoScheda? = nil
                    var analisiMisura: AnalisiFotoMisura? = nil
                    var analisiUbicazione: AnalisiFotoUbicazione? = nil
                    
                    if let ab = analisiJson["analisiBene"] as? [String: Any] {
                        analisiBene = AnalisiFotoBene(
                            ubicazioneInterna: ab["ubicazioneInterna"] as? String,
                            statoManutenzione: ab["statoManutenzione"] as? String ?? "",
                            marcaVisibile: ab["marcaVisibile"] as? String,
                            modelloVisibile: ab["modelloVisibile"] as? String,
                            annoVisibile: ab["annoVisibile"] as? String,
                            targhettaVisibile: ab["targhettaVisibile"] as? Bool ?? false,
                            testoTarghetta: ab["testoTarghetta"] as? String,
                            segniDanno: ab["segniDanno"] as? [String] ?? [],
                            condizioniDettagliate: ab["condizioniDettagliate"] as? String,
                            ambienteDescrizione: ab["ambienteDescrizione"] as? String,
                            ambienteConsono: ab["ambienteConsono"] as? String,
                            problemiAmbientali: ab["problemiAmbientali"] as? [String],
                            confidenzaMarca: ab["confidenzaMarca"] as? Double ?? 0.5,
                            confidenzaModello: ab["confidenzaModello"] as? Double ?? 0.5,
                            confidenzaAnno: ab["confidenzaAnno"] as? Double ?? 0.5
                        )
                    }
                    
                    if let asc = analisiJson["analisiScheda"] as? [String: Any] {
                        var segniElettrici: [SegnoElettrico] = []
                        var segniNonElettrici: [SegnoNonElettrico] = []
                        
                        if let se = asc["segniDannoElettrico"] as? [[String: Any]] {
                            segniElettrici = se.compactMap { s in
                                SegnoElettrico(
                                    tipo: s["tipo"] as? String ?? "",
                                    descrizione: s["descrizione"] as? String ?? "",
                                    posizione: s["posizione"] as? String,
                                    confidenza: s["confidenza"] as? Double ?? 0.7,
                                    fotoPath: foto.path
                                )
                            }
                        }
                        
                        if let sn = asc["segniDannoNonElettrico"] as? [[String: Any]] {
                            segniNonElettrici = sn.compactMap { s in
                                SegnoNonElettrico(
                                    tipo: s["tipo"] as? String ?? "",
                                    descrizione: s["descrizione"] as? String ?? "",
                                    posizione: s["posizione"] as? String,
                                    confidenza: s["confidenza"] as? Double ?? 0.7,
                                    fotoPath: foto.path
                                )
                            }
                        }
                        
                        analisiScheda = AnalisiFotoScheda(
                            tipoScheda: asc["tipoScheda"] as? String ?? "",
                            segniDannoElettrico: segniElettrici,
                            segniDannoNonElettrico: segniNonElettrici,
                            componentiVisibili: asc["componentiVisibili"] as? [String] ?? [],
                            componentiDanneggiati: asc["componentiDanneggiati"] as? [String] ?? [],
                            valutazioneGenerale: asc["valutazioneGenerale"] as? String ?? ""
                        )
                    }
                    
                    if let am = analisiJson["analisiMisura"] as? [String: Any] {
                        analisiMisura = AnalisiFotoMisura(
                            tipoStrumento: am["tipoStrumento"] as? String ?? "",
                            marcaStrumento: am["marcaStrumento"] as? String,
                            modelloStrumento: am["modelloStrumento"] as? String,
                            valoreDisplay: am["valoreDisplay"] as? String,
                            unitaMisura: am["unitaMisura"] as? String,
                            tipoMisura: am["tipoMisura"] as? String ?? "",
                            dettagliTest: am["dettagliTest"] as? String,
                            puntaliImpostatiCorretti: ValiditaTest(rawValue: am["puntaliImpostatiCorretti"] as? String ?? "") ?? .nonValutabile,
                            impostazioniCorrette: ValiditaTest(rawValue: am["impostazioniCorrette"] as? String ?? "") ?? .nonValutabile,
                            valoreCoerente: ValiditaTest(rawValue: am["valoreCoerente"] as? String ?? "") ?? .nonValutabile,
                            interpretazione: am["interpretazione"] as? String ?? "",
                            indicaDanno: am["indicaDanno"] as? Bool,
                            testValido: am["testValido"] as? Bool ?? false,
                            motivoInvalidita: am["motivoInvalidita"] as? String,
                            relazioneTest: am["relazioneTest"] as? String,
                            confidenzaLettura: am["confidenzaLettura"] as? Double ?? 0.5,
                            confidenzaInterpretazione: am["confidenzaInterpretazione"] as? Double ?? 0.5
                        )
                    }
                    
                    if let au = analisiJson["analisiUbicazione"] as? [String: Any] {
                        var matchIndirizzo: MatchVerifica? = nil
                        var matchNome: MatchVerifica? = nil
                        
                        if let mi = au["matchIndirizzo"] as? [String: Any] {
                            matchIndirizzo = MatchVerifica(
                                trovato: mi["trovato"] as? Bool ?? false,
                                valoreNoto: mi["valoreNoto"] as? String ?? "",
                                valoreTrovato: mi["valoreTrovato"] as? String,
                                esito: mi["esito"] as? String ?? "non_trovato",
                                note: mi["note"] as? String
                            )
                        }
                        
                        if let mn = au["matchNome"] as? [String: Any] {
                            matchNome = MatchVerifica(
                                trovato: mn["trovato"] as? Bool ?? false,
                                valoreNoto: mn["valoreNoto"] as? String ?? "",
                                valoreTrovato: mn["valoreTrovato"] as? String,
                                esito: mn["esito"] as? String ?? "non_trovato",
                                note: mn["note"] as? String
                            )
                        }
                        
                        analisiUbicazione = AnalisiFotoUbicazione(
                            indirizzoVisibile: au["indirizzoVisibile"] as? String,
                            civicoVisibile: au["civicoVisibile"] as? String,
                            nomeCitofonoVisibile: au["nomeCitofonoVisibile"] as? String,
                            altriElementiIdentificativi: au["altriElementiIdentificativi"] as? [String] ?? [],
                            tipoFabbricato: au["tipoFabbricato"] as? String,
                            numeroPiani: au["numeroPiani"] as? Int,
                            annoCostruzioneStimato: au["annoCostruzioneStimato"] as? String,
                            tipoCopertura: au["tipoCopertura"] as? String,
                            materialeCostruzione: au["materialeCostruzione"] as? String,
                            statoGenerale: au["statoGenerale"] as? String,
                            altreCaratteristiche: au["altreCaratteristiche"] as? [String] ?? [],
                            matchIndirizzo: matchIndirizzo,
                            matchNome: matchNome,
                            confidenzaDescrizione: au["confidenzaDescrizione"] as? Double ?? 0.7
                        )
                    }
                    
                    let analisi = AnalisiDettaglioFoto(
                        path: foto.path,
                        tipoFoto: foto.tipoTag,
                        descrizioneGenerale: descrizione,
                        qualitaFoto: qualita,
                        analisiBene: analisiBene,
                        analisiScheda: analisiScheda,
                        analisiMisura: analisiMisura,
                        analisiUbicazione: analisiUbicazione
                    )
                    
                    results.append(analisi)
                }
                
                return results
            }
        } catch {
            print("[PerxiaStreaming] ❌ Errore parsing batch: \(error)")
        }
        
        return []
    }
    
    private func buildPromptAnalisiDettagliata(foto: FotoConTag, sinistro: Sinistro) -> String {
        let fileName = URL(fileURLWithPath: foto.path).lastPathComponent
        
        var prompt = """
        Analizza questa foto per una perizia assicurativa Fenomeno Elettrico.
        
        CONTESTO:
        - File: \(fileName)
        - Bene: \(foto.bene)
        \(foto.componente != nil ? "- Componente: \(foto.componente!)" : "")
        - Tipo foto: \(foto.tipoTag.rawValue)
        
        """
        
        switch foto.tipoTag {
        case .beneGenerale, .beneDettaglio:
            prompt += """
            ANALIZZA IN MODO MOLTO DETTAGLIATO L'ASPETTO VISIVO DEL BENE E DEL CONTESTO.
            
            ⚠️ IMPORTANTE: NON includere in questa analisi informazioni su misure strumentali o test elettrici. Concentrati SOLO sull'aspetto fisico, le condizioni visive e l'ambiente.
            
            COSA ANALIZZARE:
            1. UBICAZIONE INTERNA: Dove si trova il bene (locale caldaia, garage, etc.)
            2. STATO MANUTENZIONE: Condizioni generali del bene basate sull'aspetto visivo
            3. MARCA/MODELLO/ANNO: Se visibili targhette o etichette, trascrivi ESATTAMENTE
            4. CONDIZIONI DEL BENE (DETTAGLIATE):
               - Segni di usura: descrivi eventuali segni di usura normale, abrasioni, deterioramento da tempo
               - Bruciature visibili: presenza di bruciature, annerimenti, carbonizzazioni
               - Manomissioni: segni di interventi non originali, cavi tagliati/riattaccati, componenti sostituiti
               - Stato generale: il bene appare integro, danneggiato, riparato, nuovo, vecchio
            5. AMBIENTE IN CUI SI TROVA IL BENE:
               - Descrizione ambiente: tipo di locale, dimensioni, condizioni
               - Consonanza: l'ambiente è consono all'installazione del bene? (es. umidità eccessiva, polvere, temperature estreme)
               - Problemi ambientali: presenza di umidità, condensa, muffa, polvere eccessiva, calore/freddo eccessivo
               - Installazione corretta: ci sono problemi di posizionamento o montaggio?
            6. SEGNI DANNO VISIBILI: Eventuali danni visibili specifici (escludere interpretazioni di misure)
            
            JSON RICHIESTO:
            {
                "descrizioneGenerale": "descrizione completa SOLO dell'aspetto visivo del bene, condizioni fisiche e ambiente - NO misure strumentali",
                "qualitaFoto": "buona/media/scarsa",
                "analisiBene": {
                    "ubicazioneInterna": "dove si trova",
                    "statoManutenzione": "descrizione stato dettagliata basata su osservazione visiva",
                    "marcaVisibile": "marca o null",
                    "modelloVisibile": "modello o null",
                    "annoVisibile": "anno o null",
                    "targhettaVisibile": true/false,
                    "testoTarghetta": "testo targhetta o null",
                    "segniDanno": ["danno1", ...],
                    "condizioniDettagliate": "descrizione dettagliata di usura, bruciature visibili, manomissioni, stato generale",
                    "ambienteDescrizione": "descrizione dettagliata dell'ambiente",
                    "ambienteConsono": "sì/no/parzialmente - se l'ambiente è consono all'installazione",
                    "problemiAmbientali": ["problema1", ...],
                    "confidenzaMarca": 0.0-1.0,
                    "confidenzaModello": 0.0-1.0,
                    "confidenzaAnno": 0.0-1.0
                }
            }
            """
            
        case .scheda:
            prompt += """
            ANALIZZA SCHEDA ELETTRONICA:
            1. TIPO SCHEDA: Alimentazione, controllo, etc.
            2. SEGNI DANNO ELETTRICO: Annerimenti, componenti esplosi, bruciature, archi elettrici
            3. SEGNI DANNO NON ELETTRICO: Usura, umidità, spaccature, decadimento dielettrico, corrosione
            4. COMPONENTI: Identificabili e danneggiati
            
            JSON RICHIESTO:
            {
                "descrizioneGenerale": "descrizione",
                "qualitaFoto": "buona/media/scarsa",
                "analisiScheda": {
                    "tipoScheda": "tipo",
                    "segniDannoElettrico": [
                        {"tipo": "annerimento/componente_esploso/bruciatura/arco_elettrico", "descrizione": "...", "posizione": "...", "confidenza": 0.0-1.0}
                    ],
                    "segniDannoNonElettrico": [
                        {"tipo": "usura/umidita/spaccatura/decadimento_dielettrico/corrosione", "descrizione": "...", "posizione": "...", "confidenza": 0.0-1.0}
                    ],
                    "componentiVisibili": ["comp1", ...],
                    "componentiDanneggiati": ["comp1", ...],
                    "valutazioneGenerale": "sintesi"
                }
            }
            """
            
        case .misura:
            prompt += """
            ANALIZZA MISURA STRUMENTALE IN MODO MOLTO DETTAGLIATO.
            
            ⚠️ IMPORTANTE: TUTTI i campi del JSON sono OBBLIGATORI. Non usare valori vuoti o null quando puoi fornire informazioni.
            
            DATI DA IDENTIFICARE:
            1. STRUMENTO (OBBLIGATORIO):
               - Tipo: multimetro, megger, pinza amperometrica, termocamera, oscilloscopio, altro
               - Marca e modello se visibili sul display o corpo strumento
            
            2. VALORE MISURATO (OBBLIGATORIO):
               - Trascrivi ESATTAMENTE il valore mostrato sul display
               - Includi sempre l'unità di misura (Ω, kΩ, MΩ, V, A, mA, °C, etc.)
            
            3. TIPO DI TEST/MISURA (OBBLIGATORIO):
               - Identifica il tipo di test: resistenza, isolamento, continuità, tensione AC/DC, corrente, dispersione, temperatura
               - Se è un test di isolamento: è resistivo (resistenza ohmica) o dispersivo (corrente di dispersione)?
            
            4. DETTAGLI METODOLOGICI (OBBLIGATORIO):
               - Dove sono posizionati i puntali? Su quali punti del componente/bene?
               - I puntali sono collegati correttamente per il tipo di misura?
               - Quale scala/range è impostato sullo strumento?
               - Il bene è alimentato o scollegato durante la misura?
            
            5. VALIDITÀ DEL TEST (OBBLIGATORIO):
               - I puntali sono nelle posizioni corrette per questo tipo di test?
               - Le impostazioni dello strumento sono corrette?
               - La misura è stata eseguita secondo procedure standard?
               - Il valore è plausibile per il componente misurato?
            
            6. RELAZIONE TEST (OBBLIGATORIA - non lasciare null):
               Se test VALIDO: "Il test di [tipo] rileva [valore], che [indica/esclude] un danno da FE perché [motivazione tecnica]. [Risolutivo/Non risolutivo] per la diagnosi."
               Se test NON VALIDO: "Test non valido perché [motivo: puntali sbagliati/impostazioni errate/metodologia scorretta/tipo test inappropriato]. Questo impedisce di determinare la presenza di FE perché [spiegazione]."
            
            JSON RICHIESTO:
            {
                "descrizioneGenerale": "descrizione della scena di test",
                "qualitaFoto": "buona/media/scarsa",
                "analisiMisura": {
                    "tipoStrumento": "multimetro/megger/pinza_amperometrica/termocamera/oscilloscopio",
                    "marcaStrumento": "marca visibile o null",
                    "modelloStrumento": "modello visibile o null",
                    "valoreDisplay": "valore esatto letto (es: 0.1, 12.5, OL)",
                    "unitaMisura": "Ω/kΩ/MΩ/V/mV/A/mA/°C",
                    "tipoMisura": "resistenza_ohmica/isolamento_resistivo/isolamento_dispersivo/continuita/tensione_ac/tensione_dc/corrente/dispersione/temperatura",
                    "dettagliTest": "DETTAGLIO COMPLETO: puntali posizionati su [punti], strumento impostato su [scala/range], bene [alimentato/scollegato], metodologia [corretta/scorretta perché...]",
                    "puntaliImpostatiCorretti": "corretto/scorretto/non_valutabile",
                    "impostazioniCorrette": "corretto/scorretto/non_valutabile",
                    "valoreCoerente": "corretto/scorretto/non_valutabile",
                    "interpretazione": "cosa indica questa misura rispetto al funzionamento del componente e se suggerisce danno da FE",
                    "indicaDanno": true/false/null,
                    "testValido": true/false,
                    "motivoInvalidita": "se testValido=false: spiegazione dettagliata (puntali sbagliati dove e perché, impostazioni errate quali, tipo test inappropriato perché). Se testValido=true: null",
                    "relazioneTest": "OBBLIGATORIO: relazione 2-3 frasi che spiega SE e COME questo test aiuta a determinare FE, con interpretazione tecnica del valore",
                    "confidenzaLettura": 0.85,
                    "confidenzaInterpretazione": 0.75
                }
            }
            
            NOTA CONFIDENZE: usa 0.9+ se display nitido e valore chiaro, 0.7-0.9 se leggibile ma non perfetto, 0.5-0.7 se difficile da leggere, <0.5 se quasi illeggibile.
            """
            
        case .ubicazione:
            prompt += """
            ANALIZZA FOTO UBICAZIONE/STABILE:
            1. ELEMENTI IDENTIFICATIVI: Indirizzo, civico, nomi citofono
            2. DESCRIZIONE STABILE: Tipo fabbricato, piani, copertura, materiali, stato
            
            DATI DA CONFRONTARE:
            - Nome assicurato: \(sinistro.nomeAssicurato ?? "N/D")
            - Indirizzo: \(sinistro.indirizzoAssicurato ?? "N/D")
            
            JSON RICHIESTO:
            {
                "descrizioneGenerale": "descrizione",
                "qualitaFoto": "buona/media/scarsa",
                "analisiUbicazione": {
                    "indirizzoVisibile": "indirizzo o null",
                    "civicoVisibile": "civico o null",
                    "nomeCitofonoVisibile": "nome o null",
                    "altriElementiIdentificativi": ["elemento1", ...],
                    "tipoFabbricato": "appartamento/villa/condominio/capannone/...",
                    "numeroPiani": numero o null,
                    "annoCostruzioneStimato": "anno o null",
                    "tipoCopertura": "tegole/lamiera/terrazza/...",
                    "materialeCostruzione": "muratura/prefabbricato/...",
                    "statoGenerale": "buono/discreto/da_ristrutturare",
                    "altreCaratteristiche": ["caratteristica1", ...],
                    "matchIndirizzo": {
                        "trovato": true/false,
                        "valoreNoto": "indirizzo noto",
                        "valoreTrovato": "indirizzo in foto o null",
                        "esito": "confermato/parziale/non_corrisponde/non_trovato",
                        "note": "note o null"
                    },
                    "matchNome": {
                        "trovato": true/false,
                        "valoreNoto": "nome noto",
                        "valoreTrovato": "nome in foto o null",
                        "esito": "confermato/parziale/non_corrisponde/non_trovato",
                        "note": "note o null"
                    },
                    "confidenzaDescrizione": 0.0-1.0
                }
            }
            """
            
        default:
            prompt += """
            ANALIZZA GENERICAMENTE:
            - Descrivi cosa vedi nella foto
            - Identifica elementi rilevanti per una perizia
            
            JSON:
            {
                "descrizioneGenerale": "descrizione",
                "qualitaFoto": "buona/media/scarsa"
            }
            """
        }
        
        return prompt
    }
    
    private func parseAnalisiDettagliata(_ aiResult: AIResult, foto: FotoConTag) -> AnalisiDettaglioFoto? {
        guard let text = aiResult.result?.value as? String else { return nil }
        
        // Estrai JSON dalla risposta
        let cleaned = extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            let descrizione = json?["descrizioneGenerale"] as? String ?? ""
            let qualitaStr = json?["qualitaFoto"] as? String ?? "media"
            let qualita = QualitaFoto(rawValue: qualitaStr) ?? .media
            
            var analisiBene: AnalisiFotoBene? = nil
            var analisiScheda: AnalisiFotoScheda? = nil
            var analisiMisura: AnalisiFotoMisura? = nil
            var analisiUbicazione: AnalisiFotoUbicazione? = nil
            
            // Parse specifico per tipo
            if let ab = json?["analisiBene"] as? [String: Any] {
                analisiBene = AnalisiFotoBene(
                    ubicazioneInterna: ab["ubicazioneInterna"] as? String,
                    statoManutenzione: ab["statoManutenzione"] as? String ?? "",
                    marcaVisibile: ab["marcaVisibile"] as? String,
                    modelloVisibile: ab["modelloVisibile"] as? String,
                    annoVisibile: ab["annoVisibile"] as? String,
                    targhettaVisibile: ab["targhettaVisibile"] as? Bool ?? false,
                    testoTarghetta: ab["testoTarghetta"] as? String,
                    segniDanno: ab["segniDanno"] as? [String] ?? [],
                    condizioniDettagliate: ab["condizioniDettagliate"] as? String,
                    ambienteDescrizione: ab["ambienteDescrizione"] as? String,
                    ambienteConsono: ab["ambienteConsono"] as? String,
                    problemiAmbientali: ab["problemiAmbientali"] as? [String],
                    confidenzaMarca: ab["confidenzaMarca"] as? Double ?? 0.5,
                    confidenzaModello: ab["confidenzaModello"] as? Double ?? 0.5,
                    confidenzaAnno: ab["confidenzaAnno"] as? Double ?? 0.5
                )
            }
            
            if let asc = json?["analisiScheda"] as? [String: Any] {
                var segniElettrici: [SegnoElettrico] = []
                var segniNonElettrici: [SegnoNonElettrico] = []
                
                if let se = asc["segniDannoElettrico"] as? [[String: Any]] {
                    segniElettrici = se.compactMap { s in
                        SegnoElettrico(
                            tipo: s["tipo"] as? String ?? "",
                            descrizione: s["descrizione"] as? String ?? "",
                            posizione: s["posizione"] as? String,
                            confidenza: s["confidenza"] as? Double ?? 0.7,
                            fotoPath: foto.path
                        )
                    }
                }
                
                if let sn = asc["segniDannoNonElettrico"] as? [[String: Any]] {
                    segniNonElettrici = sn.compactMap { s in
                        SegnoNonElettrico(
                            tipo: s["tipo"] as? String ?? "",
                            descrizione: s["descrizione"] as? String ?? "",
                            posizione: s["posizione"] as? String,
                            confidenza: s["confidenza"] as? Double ?? 0.7,
                            fotoPath: foto.path
                        )
                    }
                }
                
                analisiScheda = AnalisiFotoScheda(
                    tipoScheda: asc["tipoScheda"] as? String ?? "",
                    segniDannoElettrico: segniElettrici,
                    segniDannoNonElettrico: segniNonElettrici,
                    componentiVisibili: asc["componentiVisibili"] as? [String] ?? [],
                    componentiDanneggiati: asc["componentiDanneggiati"] as? [String] ?? [],
                    valutazioneGenerale: asc["valutazioneGenerale"] as? String ?? ""
                )
            }
            
            if let am = json?["analisiMisura"] as? [String: Any] {
                analisiMisura = AnalisiFotoMisura(
                    tipoStrumento: am["tipoStrumento"] as? String ?? "",
                    marcaStrumento: am["marcaStrumento"] as? String,
                    modelloStrumento: am["modelloStrumento"] as? String,
                    valoreDisplay: am["valoreDisplay"] as? String,
                    unitaMisura: am["unitaMisura"] as? String,
                    tipoMisura: am["tipoMisura"] as? String ?? "",
                    dettagliTest: am["dettagliTest"] as? String,
                    puntaliImpostatiCorretti: ValiditaTest(rawValue: am["puntaliImpostatiCorretti"] as? String ?? "") ?? .nonValutabile,
                    impostazioniCorrette: ValiditaTest(rawValue: am["impostazioniCorrette"] as? String ?? "") ?? .nonValutabile,
                    valoreCoerente: ValiditaTest(rawValue: am["valoreCoerente"] as? String ?? "") ?? .nonValutabile,
                    interpretazione: am["interpretazione"] as? String ?? "",
                    indicaDanno: am["indicaDanno"] as? Bool,
                    testValido: am["testValido"] as? Bool ?? false,
                    motivoInvalidita: am["motivoInvalidita"] as? String,
                    relazioneTest: am["relazioneTest"] as? String,
                    confidenzaLettura: am["confidenzaLettura"] as? Double ?? 0.5,
                    confidenzaInterpretazione: am["confidenzaInterpretazione"] as? Double ?? 0.5
                )
            }
            
            if let au = json?["analisiUbicazione"] as? [String: Any] {
                var matchIndirizzo: MatchVerifica? = nil
                var matchNome: MatchVerifica? = nil
                
                if let mi = au["matchIndirizzo"] as? [String: Any] {
                    matchIndirizzo = MatchVerifica(
                        trovato: mi["trovato"] as? Bool ?? false,
                        valoreNoto: mi["valoreNoto"] as? String ?? "",
                        valoreTrovato: mi["valoreTrovato"] as? String,
                        esito: mi["esito"] as? String ?? "non_trovato",
                        note: mi["note"] as? String
                    )
                }
                
                if let mn = au["matchNome"] as? [String: Any] {
                    matchNome = MatchVerifica(
                        trovato: mn["trovato"] as? Bool ?? false,
                        valoreNoto: mn["valoreNoto"] as? String ?? "",
                        valoreTrovato: mn["valoreTrovato"] as? String,
                        esito: mn["esito"] as? String ?? "non_trovato",
                        note: mn["note"] as? String
                    )
                }
                
                analisiUbicazione = AnalisiFotoUbicazione(
                    indirizzoVisibile: au["indirizzoVisibile"] as? String,
                    civicoVisibile: au["civicoVisibile"] as? String,
                    nomeCitofonoVisibile: au["nomeCitofonoVisibile"] as? String,
                    altriElementiIdentificativi: au["altriElementiIdentificativi"] as? [String] ?? [],
                    tipoFabbricato: au["tipoFabbricato"] as? String,
                    numeroPiani: au["numeroPiani"] as? Int,
                    annoCostruzioneStimato: au["annoCostruzioneStimato"] as? String,
                    tipoCopertura: au["tipoCopertura"] as? String,
                    materialeCostruzione: au["materialeCostruzione"] as? String,
                    statoGenerale: au["statoGenerale"] as? String,
                    altreCaratteristiche: au["altreCaratteristiche"] as? [String] ?? [],
                    matchIndirizzo: matchIndirizzo,
                    matchNome: matchNome,
                    confidenzaDescrizione: au["confidenzaDescrizione"] as? Double ?? 0.7
                )
            }
            
            return AnalisiDettaglioFoto(
                path: foto.path,
                tipoFoto: foto.tipoTag,
                descrizioneGenerale: descrizione,
                qualitaFoto: qualita,
                analisiBene: analisiBene,
                analisiScheda: analisiScheda,
                analisiMisura: analisiMisura,
                analisiUbicazione: analisiUbicazione
            )
            
        } catch {
            print("[PerxiaStreaming] ❌ Errore parsing analisi foto: \(error)")
            return nil
        }
    }
    
    private func extractJSON(from text: String) -> String {
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
        
        // 2. Se non inizia con {, cerca di estrarre il blocco JSON
        if !cleaned.hasPrefix("{") {
            if let start = cleaned.firstIndex(of: "{"),
               let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            }
        }
        
        return cleaned
    }
    
    // MARK: - Sintesi Bene Streaming
    
    private func sintetizzaBeneStreaming(
        nomeBene: String,
        analisi: [AnalisiDettaglioFoto],
        fotoGenerali: [String],
        fotoSchede: [String],
        fotoMisure: [String],
        fulminazione: Bool,
        vociGiustificativo: [VoceGiustificativo],
        importoRichiesto: Double?
    ) async -> BeneAnalysisStreaming? {
        
        // Estrai dati da analisi
        var marca: DatoTracciato<String>? = nil
        var modello: DatoTracciato<String>? = nil
        var anno: DatoTracciato<String>? = nil
        var annoStimato = false
        var statoManutenzione: DatoTracciato<String>? = nil
        var ubicazioneInterna: String? = nil
        var segniElettrici: [SegnoElettrico] = []
        var segniNonElettrici: [SegnoNonElettrico] = []
        var misureRilevate: [MisuraRilevata] = []
        
        var osservazioniTesti: [String] = []
        var fontiOsservazioni: [String] = []
        
        for a in analisi {
            // Bene
            if let ab = a.analisiBene {
                if let m = ab.marcaVisibile, !m.isEmpty, ab.confidenzaMarca >= 0.6 {
                    if marca == nil || ab.confidenzaMarca > (marca?.confidenza ?? 0) {
                        marca = DatoTracciato(valore: m, confidenza: ab.confidenzaMarca, fontiFoto: [a.path])
                    }
                }
                if let m = ab.modelloVisibile, !m.isEmpty, ab.confidenzaModello >= 0.6 {
                    if modello == nil || ab.confidenzaModello > (modello?.confidenza ?? 0) {
                        modello = DatoTracciato(valore: m, confidenza: ab.confidenzaModello, fontiFoto: [a.path])
                    }
                }
                if let y = ab.annoVisibile, !y.isEmpty, ab.confidenzaAnno >= 0.6 {
                    if anno == nil || ab.confidenzaAnno > (anno?.confidenza ?? 0) {
                        anno = DatoTracciato(valore: y, confidenza: ab.confidenzaAnno, fontiFoto: [a.path])
                        annoStimato = false
                    }
                }
                if ubicazioneInterna == nil, let u = ab.ubicazioneInterna, !u.isEmpty {
                    ubicazioneInterna = u
                }
                if !ab.statoManutenzione.isEmpty {
                    statoManutenzione = DatoTracciato(valore: ab.statoManutenzione, confidenza: 0.8, fontiFoto: [a.path])
                }
                
                // Costruisci testo osservazioni completo con dettagli
                var testoOsservazione = a.descrizioneGenerale
                if let condizioni = ab.condizioniDettagliate, !condizioni.isEmpty {
                    testoOsservazione += "\n\nCondizioni del bene: \(condizioni)"
                }
                if let ambiente = ab.ambienteDescrizione, !ambiente.isEmpty {
                    testoOsservazione += "\n\nAmbiente: \(ambiente)"
                    if let consono = ab.ambienteConsono, !consono.isEmpty {
                        testoOsservazione += " (Ambiente \(consono)"
                        if let problemi = ab.problemiAmbientali, !problemi.isEmpty {
                            testoOsservazione += ": \(problemi.joined(separator: ", "))"
                        }
                        testoOsservazione += ")"
                    }
                }
                osservazioniTesti.append(testoOsservazione)
                fontiOsservazioni.append(a.path)
            }
            
            // Scheda
            if let asc = a.analisiScheda {
                // Aggiungi foto path ai segni
                let segniElConFoto = asc.segniDannoElettrico.map { segno in
                    SegnoElettrico(
                        tipo: segno.tipo,
                        descrizione: segno.descrizione,
                        posizione: segno.posizione,
                        confidenza: segno.confidenza,
                        fotoPath: a.path
                    )
                }
                let segniNonElConFoto = asc.segniDannoNonElettrico.map { segno in
                    SegnoNonElettrico(
                        tipo: segno.tipo,
                        descrizione: segno.descrizione,
                        posizione: segno.posizione,
                        confidenza: segno.confidenza,
                        fotoPath: a.path
                    )
                }
                segniElettrici.append(contentsOf: segniElConFoto)
                segniNonElettrici.append(contentsOf: segniNonElConFoto)
                osservazioniTesti.append(asc.valutazioneGenerale)
                fontiOsservazioni.append(a.path)
            }
            
            // Misura
            if let am = a.analisiMisura {
                let misura = MisuraRilevata(
                    fotoPath: a.path,
                    tipoMisura: am.tipoMisura,
                    strumento: am.tipoStrumento,
                    valore: am.valoreDisplay ?? "N/D",
                    unitaMisura: am.unitaMisura,
                    dettagliTest: am.dettagliTest,
                    testValido: am.testValido,
                    motivoInvalidita: am.motivoInvalidita,
                    relazioneTest: am.relazioneTest,
                    interpretazione: am.interpretazione,
                    indicaDanno: am.indicaDanno,
                    confidenzaLettura: am.confidenzaLettura,
                    confidenzaInterpretazione: am.confidenzaInterpretazione
                )
                misureRilevate.append(misura)
            }
        }
        
        // Costruisci report misure
        var reportMisure: ReportMisure? = nil
        if !misureRilevate.isEmpty {
            let testValidi = misureRilevate.contains { $0.testValido }
            let sintesi = misureRilevate.filter { $0.testValido }.map { $0.interpretazione }.joined(separator: "; ")
            let motivoInvalido = misureRilevate.filter { !$0.testValido }.first?.motivoInvalidita
            
            reportMisure = ReportMisure(
                misureRilevate: misureRilevate,
                testValidi: testValidi,
                sintesiRisultati: testValidi ? sintesi : "Test non validi",
                testInvalidiMotivo: testValidi ? nil : motivoInvalido
            )
        }
        
        // Osservazioni visive
        let osservazioniText = osservazioniTesti.filter { !$0.isEmpty }.joined(separator: " ")
        let osservazioni = DatoTracciato(
            valore: osservazioniText,
            confidenza: 0.85,
            fontiFoto: fontiOsservazioni
        )
        
        // Costruisci JSON giustificativi per questo bene
        var giustificativiJSON = "Nessun giustificativo disponibile"
        if !vociGiustificativo.isEmpty {
            let vociDict = vociGiustificativo.map { voce -> [String: Any] in
                var dict: [String: Any] = [
                    "descrizione": voce.descrizione,
                    "importo": voce.importo,
                    "tipo": voce.tipoImporto
                ]
                if let comp = voce.componente {
                    dict["componente"] = comp
                }
                return dict
            }
            if let data = try? JSONSerialization.data(withJSONObject: vociDict),
               let str = String(data: data, encoding: .utf8) {
                giustificativiJSON = str
            }
        }
        
        // Costruisci JSON analisi dettagliate per il prompt
        let analisiJSON = analisi.map { a -> [String: Any] in
            var dict: [String: Any] = [
                "path": a.path,
                "descrizione": a.descrizioneGenerale,
                "qualita": a.qualitaFoto.rawValue
            ]
            if let ab = a.analisiBene {
                dict["tipo"] = "bene"
                dict["marca"] = ab.marcaVisibile ?? ""
                dict["modello"] = ab.modelloVisibile ?? ""
                dict["anno"] = ab.annoVisibile ?? ""
                dict["statoManutenzione"] = ab.statoManutenzione
            }
            if let asc = a.analisiScheda {
                dict["tipo"] = "scheda"
                dict["valutazione"] = asc.valutazioneGenerale
            }
            if let am = a.analisiMisura {
                dict["tipo"] = "misura"
                dict["interpretazione"] = am.interpretazione
                dict["testValido"] = am.testValido
            }
            return dict
        }
        
        guard let analisiData = try? JSONSerialization.data(withJSONObject: analisiJSON),
              let analisiString = String(data: analisiData, encoding: .utf8) else {
            // Fallback senza IA se errore serializzazione
            let compatibilita = determinaCompatibilitaFE(
                segniElettrici: segniElettrici,
                segniNonElettrici: segniNonElettrici,
                misure: misureRilevate,
                fulminazione: fulminazione
            )
            
            return BeneAnalysisStreaming(
                nome: nomeBene,
                marca: marca,
                modello: modello,
                anno: anno,
                annoStimato: annoStimato,
                ubicazioneInterna: ubicazioneInterna,
                statoManutenzione: statoManutenzione,
                osservazioniVisive: osservazioni,
                segniDannoElettrico: segniElettrici,
                segniDannoNonElettrico: segniNonElettrici,
                reportMisure: reportMisure,
                compatibilitaFE: compatibilita,
                stimaEconomica: nil,
                fotoGenerali: fotoGenerali,
                fotoSchede: fotoSchede,
                fotoMisure: fotoMisure
            )
        }
        
        // Chiamata IA per sintesi completa con giustificativi
        let sintesiCompleta = await sintetizzaBeneConGiustificativi(
            nomeBene: nomeBene,
            analisiJSON: analisiString,
            giustificativiJSON: giustificativiJSON,
            importoRichiesto: importoRichiesto,
            fulminazione: fulminazione,
            segniElettrici: segniElettrici,
            segniNonElettrici: segniNonElettrici,
            misure: misureRilevate
        )
        
        // Determina compatibilità FE (usa sintesi se disponibile, altrimenti calcolo automatico)
        let compatibilita = sintesiCompleta?.compatibilita ?? determinaCompatibilitaFE(
            segniElettrici: segniElettrici,
            segniNonElettrici: segniNonElettrici,
            misure: misureRilevate,
            fulminazione: fulminazione
        )
        
        // Calcola stima economica
        let stimaEconomica = sintesiCompleta?.stimaEconomica
        
        return BeneAnalysisStreaming(
            nome: nomeBene,
            marca: marca,
            modello: modello,
            anno: anno,
            annoStimato: annoStimato,
            ubicazioneInterna: ubicazioneInterna,
            statoManutenzione: statoManutenzione,
            osservazioniVisive: osservazioni,
            segniDannoElettrico: segniElettrici,
            segniDannoNonElettrico: segniNonElettrici,
            reportMisure: reportMisure,
            compatibilitaFE: compatibilita,
            stimaEconomica: stimaEconomica,
            fotoGenerali: fotoGenerali,
            fotoSchede: fotoSchede,
            fotoMisure: fotoMisure
        )
    }
    
    // MARK: - Sintesi con Giustificativi
    
    private func sintetizzaBeneConGiustificativi(
        nomeBene: String,
        analisiJSON: String,
        giustificativiJSON: String,
        importoRichiesto: Double?,
        fulminazione: Bool,
        segniElettrici: [SegnoElettrico],
        segniNonElettrici: [SegnoNonElettrico],
        misure: [MisuraRilevata]
    ) async -> (compatibilita: CompatibilitaFETracciata?, stimaEconomica: StimaEconomicaTracciata?)? {
        
        let importoRichiestoStr = importoRichiesto != nil ? String(format: "%.2f", importoRichiesto!) : "non specificato"
        
        let prompt = """
        Analizza il bene "\(nomeBene)" per una perizia Fenomeno Elettrico considerando anche i giustificativi.
        
        CONTESTO:
        - Fulminazione rilevata nella zona: \(fulminazione ? "SÌ" : "NO")
        - Importo richiesto nella denuncia: €\(importoRichiestoStr)
        
        ANALISI FOTO:
        \(analisiJSON)
        
        GIUSTIFICATIVI (fatture/preventivi) PER QUESTO BENE:
        \(giustificativiJSON)
        
        SEGNI DANNO ELETTRICO: \(segniElettrici.count > 0 ? segniElettrici.map { "\($0.tipo): \($0.descrizione)" }.joined(separator: "; ") : "nessuno")
        SEGNI DANNO NON ELETTRICO: \(segniNonElettrici.count > 0 ? segniNonElettrici.map { "\($0.tipo): \($0.descrizione)" }.joined(separator: "; ") : "nessuno")
        TEST STRUMENTALI: \(misure.count > 0 ? misure.map { "\($0.tipoMisura): \($0.interpretazione)" }.joined(separator: "; ") : "nessuno")
        
        OBIETTIVO: Fornire una valutazione completa considerando foto, test e giustificativi.
        
        ANALIZZA:
        1. COMPATIBILITÀ FE: Valutazione se il danno è compatibile con Fenomeno Elettrico considerando tutte le evidenze
        2. STIMA ECONOMICA: 
           - Se disponibili giustificativi, valuta se gli importi sono COMPATIBILI con il danno osservato
           - Confronta l'importo richiesto con i giustificativi e con la tua stima
           - Indica se ritieni l'importo giustificato congruo, sottostimato o sovrastimato
           - Fornisci una stima peritale se diversa dai giustificativi
        
        REGOLE COMPATIBILITÀ FE:
        - "compatibile": danno localizzato su componenti elettronici, protezioni (MOV/TVS) danneggiate, piste fuse, misure indicano corto/isolamento crollato
        - "poco_probabile": segni non chiari, possibili cause alternative
        - "non_compatibile": usura, ruggine diffusa, surriscaldamento prolungato, blocchi meccanici
        - "indeterminato": documentazione insufficiente, misure assenti/non interpretabili
        
        RISPONDI SOLO CON JSON:
        {
            "compatibilitaFE": {
                "esito": "compatibile/poco_probabile/non_compatibile/indeterminato",
                "motivazione": "spiegazione tecnica dell'esito considerando foto, test e giustificativi",
                "evidenzeAFavore": ["evidenza1", "evidenza2"],
                "evidenzeContrarie": ["evidenza1"],
                "confidenza": 0.0-1.0
            },
            "stimaEconomica": {
                "importo": importo in euro o null,
                "descrizione": "tipo di intervento necessario",
                "baseStima": "stima peritale/preventivo/listino",
                "note": "valutazione congruità importo giustificativi e confronto con importo richiesto",
                "confidenza": 0.0-1.0
            }
        }
        """
        
        let task = AITask(
            type: .textGeneration,
            priority: .secondary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: true,
            knowledgeDomains: [.fenomenoElettrico, .stimaDanni],
            maxKnowledgeChunks: 4
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task) { aiResult in
                    guard !resumed else { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore sintesi")))
                    }
                }
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parseSintesiConGiustificativi(aiResult)
        case .failure:
            return nil
        }
    }
    
    private func parseSintesiConGiustificativi(_ aiResult: AIResult) -> (compatibilita: CompatibilitaFETracciata?, stimaEconomica: StimaEconomicaTracciata?)? {
        guard let text = aiResult.result?.value as? String else { return nil }
        
        let cleaned = extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            var compatibilita: CompatibilitaFETracciata? = nil
            var stimaEconomica: StimaEconomicaTracciata? = nil
            
            if let cf = json?["compatibilitaFE"] as? [String: Any] {
                let evidenzeAFavore = (cf["evidenzeAFavore"] as? [String] ?? []).map {
                    EvidenzaTracciata(descrizione: $0, fotoFonte: [], peso: 0.7)
                }
                let evidenzeContrarie = (cf["evidenzeContrarie"] as? [String] ?? []).map {
                    EvidenzaTracciata(descrizione: $0, fotoFonte: [], peso: 0.7)
                }
                
                compatibilita = CompatibilitaFETracciata(
                    esito: cf["esito"] as? String ?? "indeterminato",
                    motivazione: cf["motivazione"] as? String ?? "",
                    evidenzeAFavore: evidenzeAFavore,
                    evidenzeContrarie: evidenzeContrarie,
                    confidenza: cf["confidenza"] as? Double ?? 0.5
                )
            }
            
            if let se = json?["stimaEconomica"] as? [String: Any] {
                let importo = se["importo"] as? Double
                
                // Parse vociDettaglio se presenti
                var vociDettaglio: [VoceStima]? = nil
                if let vociArray = se["vociDettaglio"] as? [[String: Any]] {
                    vociDettaglio = vociArray.compactMap { voce in
                        guard let descrizione = voce["descrizione"] as? String,
                              let importoVoce = voce["importo"] as? Double,
                              let tipo = voce["tipo"] as? String else { return nil }
                        return VoceStima(
                            descrizione: descrizione,
                            importo: importoVoce,
                            tipo: tipo,
                            fonte: voce["fonte"] as? String
                        )
                    }
                }
                
                stimaEconomica = StimaEconomicaTracciata(
                    importo: importo != nil ? DatoTracciato(valore: importo!, confidenza: se["confidenza"] as? Double ?? 0.7, fontiFoto: []) : nil,
                    descrizione: se["descrizione"] as? String ?? "",
                    baseStima: se["baseStima"] as? String ?? "",
                    note: se["note"] as? String,
                    vociDettaglio: vociDettaglio
                )
            }
            
            return (compatibilita, stimaEconomica)
        } catch {
            print("[PerxiaStreaming] ❌ Errore parsing sintesi con giustificativi: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Functions
    
    private func raccogliBeniComponentiDaTag(rootPath: String) async -> (beni: [String], componenti: [String]) {
        // Usa dizionario per normalizzare case-insensitive
        var beniMap: [String: String] = [:] // chiave normalizzata -> nome formattato
        var componentiMap: [String: String] = [:]
        
        let fotoTaggate = await trovaTutteLesFotoTaggate(rootPath: rootPath)
        
        for (path, tags) in fotoTaggate {
            if let bene = await estraiBeneDaTag(path: path, tags: tags), !bene.isEmpty {
                let chiave = bene.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if beniMap[chiave] == nil {
                    // Capitalizza la prima lettera
                    beniMap[chiave] = bene.prefix(1).uppercased() + bene.dropFirst().lowercased()
                }
            }
            if let comp = await estraiComponenteDaTag(path: path, tags: tags), !comp.isEmpty {
                let chiave = comp.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if componentiMap[chiave] == nil {
                    componentiMap[chiave] = comp.prefix(1).uppercased() + comp.dropFirst().lowercased()
                }
            }
        }
        
        return (Array(beniMap.values).sorted(), Array(componentiMap.values).sorted())
    }
    
    private func trovaFileDenuncia(rootPath: String) async -> String? {
        let denunciaTag = FileTagManager.FileTag.availableTags.first { $0.id == "denuncia" }
        if let tag = denunciaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            return files.first { $0.hasPrefix(rootPath) }
        }
        return nil
    }
    
    private func trovaFileGiustificativi(rootPath: String) async -> [String] {
        var result: [String] = []
        
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        
        if let tag = fatturaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            result.append(contentsOf: files.filter { $0.hasPrefix(rootPath) })
        }
        if let tag = preventivoTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            result.append(contentsOf: files.filter { $0.hasPrefix(rootPath) })
        }
        
        return result
    }
    
    // MARK: - Analisi Giustificativi e Denuncia (Streaming)
    
    private func analizzaGiustificativiStreaming(
        paths: [String],
        beniTaggati: [String],
        componentiTaggati: [String],
        sinistro: Sinistro
    ) async -> AnalisiGiustificativi? {
        // Usa la funzione di PerxiaService (accessibile dall'extension)
        return await fase0_analizzaGiustificativi(
            paths: paths,
            beniTaggati: beniTaggati,
            componentiTaggati: componentiTaggati,
            sinistro: sinistro
        )
    }
    
    private func analizzaDenunciaStreaming(
        path: String,
        sinistro: Sinistro
    ) async -> AnalisiDenuncia? {
        // Usa la funzione di PerxiaService (accessibile dall'extension)
        return await fase0_analizzaDenuncia(path: path, sinistro: sinistro)
    }
    
    private func determinaCompatibilitaFE(
        segniElettrici: [SegnoElettrico],
        segniNonElettrici: [SegnoNonElettrico],
        misure: [MisuraRilevata],
        fulminazione: Bool
    ) -> CompatibilitaFETracciata {
        
        var evidenzeAFavore: [EvidenzaTracciata] = []
        var evidenzeContrarie: [EvidenzaTracciata] = []
        
        // Segni elettrici -> a favore
        for s in segniElettrici where s.confidenza >= 0.6 {
            evidenzeAFavore.append(EvidenzaTracciata(
                descrizione: "\(s.tipo): \(s.descrizione)",
                fotoFonte: s.posizione != nil ? [s.posizione!] : [],
                peso: s.confidenza
            ))
        }
        
        // Segni non elettrici -> contrarie
        for s in segniNonElettrici where s.confidenza >= 0.6 {
            evidenzeContrarie.append(EvidenzaTracciata(
                descrizione: "\(s.tipo): \(s.descrizione)",
                fotoFonte: s.posizione != nil ? [s.posizione!] : [],
                peso: s.confidenza
            ))
        }
        
        // Misure che indicano danno -> a favore
        for m in misure where m.testValido && m.indicaDanno == true {
            evidenzeAFavore.append(EvidenzaTracciata(
                descrizione: "\(m.tipoMisura): \(m.interpretazione)",
                fotoFonte: [m.fotoPath],
                peso: m.confidenzaInterpretazione
            ))
        }
        
        // Determina esito
        let pesoFavore = evidenzeAFavore.reduce(0.0) { $0 + $1.peso }
        let pesoContra = evidenzeContrarie.reduce(0.0) { $0 + $1.peso }
        
        let esito: String
        let confidenza: Double
        
        if evidenzeAFavore.isEmpty && evidenzeContrarie.isEmpty {
            esito = "indeterminato"
            confidenza = 0.3
        } else if pesoFavore > pesoContra * 1.5 {
            esito = "compatibile"
            confidenza = min(0.95, 0.6 + pesoFavore / 5)
        } else if pesoContra > pesoFavore * 1.5 {
            esito = "non_compatibile"
            confidenza = min(0.95, 0.6 + pesoContra / 5)
        } else {
            esito = "poco_probabile"
            confidenza = 0.5
        }
        
        let motivazione = esito == "compatibile"
            ? "Presenza di segni riconducibili a fenomeno elettrico"
            : esito == "non_compatibile"
            ? "Prevalenza di segni non riconducibili a fenomeno elettrico"
            : "Evidenze non sufficienti per determinazione certa"
        
        return CompatibilitaFETracciata(
            esito: esito,
            motivazione: motivazione,
            evidenzeAFavore: evidenzeAFavore,
            evidenzeContrarie: evidenzeContrarie,
            confidenza: confidenza
        )
    }
    
    // MARK: - Conversione a BeneAnalysis (compatibilità)
    
    func convertToBeneAnalysis(_ streaming: BeneAnalysisStreaming) -> BeneAnalysis {
        return BeneAnalysis(
            nome: streaming.nome,
            marca: streaming.marca?.valore,
            modello: streaming.modello?.valore,
            anno: streaming.anno?.valore,
            annoStimato: streaming.annoStimato,
            componentiDanneggiati: streaming.segniDannoElettrico.map { $0.descrizione },
            osservazioniVisive: streaming.osservazioniVisive.valore,
            testEseguiti: streaming.reportMisure?.sintesiRisultati ?? "",
            compatibilitaFE: CompatibilitaFE(
                esito: streaming.compatibilitaFE.esito,
                motivazione: streaming.compatibilitaFE.motivazione,
                evidenzeAFavore: streaming.compatibilitaFE.evidenzeAFavore.map { $0.descrizione },
                evidenzeContrarie: streaming.compatibilitaFE.evidenzeContrarie.map { $0.descrizione }
            ),
            stimaEconomica: nil,
            fotoAssociate: streaming.fotoGenerali + streaming.fotoSchede + streaming.fotoMisure,
            confidenzaMarca: streaming.marca?.confidenza ?? 0,
            confidenzaModello: streaming.modello?.confidenza ?? 0,
            confidenzaAnno: streaming.anno?.confidenza ?? 0,
            confidenzaOsservazioni: streaming.osservazioniVisive.confidenza,
            confidenzaTest: streaming.reportMisure?.misureRilevate.first?.confidenzaInterpretazione ?? 0,
            confidenzaCompatibilita: streaming.compatibilitaFE.confidenza,
            confidenzaStima: 0
        )
    }
    
    // MARK: - Analisi Ubicazione per Quadro Contrattuale
    
    private func trovaTutteLeFotoUbicazione(rootPath: String) async -> [String] {
        let fotoTaggate = await trovaTutteLesFotoTaggate(rootPath: rootPath)
        return fotoTaggate
            .filter { $0.tags.contains { $0.id == "foto_ubicazione_rischio" } }
            .map { $0.path }
    }
    
    private func analizzaFotoUbicazionePerQuadro(
        foto: [String],
        sinistro: Sinistro
    ) async -> AnalisiQuadroContrattuale? {
        
        var analisi: [AnalisiFotoUbicazione] = []
        
        for path in foto {
            let fotoConTag = FotoConTag(
                path: path,
                bene: "Ubicazione",
                componente: nil,
                tipoTag: .ubicazione,
                tags: []
            )
            
            if let det = await analizzaFotoDettagliata(foto: fotoConTag, sinistro: sinistro),
               let au = det.analisiUbicazione {
                analisi.append(au)
            }
        }
        
        guard !analisi.isEmpty else { return nil }
        
        // Unisci risultati
        let tipoFabbricato = analisi.compactMap { $0.tipoFabbricato }.first
        let numeroPiani = analisi.compactMap { $0.numeroPiani }.first
        let anno = analisi.compactMap { $0.annoCostruzioneStimato }.first
        let copertura = analisi.compactMap { $0.tipoCopertura }.first
        let materiale = analisi.compactMap { $0.materialeCostruzione }.first
        let stato = analisi.compactMap { $0.statoGenerale }.first
        let verificaIndirizzo = analisi.compactMap { $0.matchIndirizzo }.first
        let verificaNome = analisi.compactMap { $0.matchNome }.first
        
        return AnalisiQuadroContrattuale(
            tipoFabbricato: tipoFabbricato != nil ? DatoTracciato(valore: tipoFabbricato!, confidenza: 0.8, fontiFoto: foto) : nil,
            numeroPiani: numeroPiani != nil ? DatoTracciato(valore: numeroPiani!, confidenza: 0.75, fontiFoto: foto) : nil,
            annoCostruzione: anno != nil ? DatoTracciato(valore: anno!, confidenza: 0.6, fontiFoto: foto) : nil,
            tipoCopertura: copertura != nil ? DatoTracciato(valore: copertura!, confidenza: 0.7, fontiFoto: foto) : nil,
            materialeCostruzione: materiale != nil ? DatoTracciato(valore: materiale!, confidenza: 0.75, fontiFoto: foto) : nil,
            statoGenerale: stato != nil ? DatoTracciato(valore: stato!, confidenza: 0.7, fontiFoto: foto) : nil,
            superficie: nil,
            altreCaratteristiche: analisi.flatMap { $0.altreCaratteristiche },
            verificaIndirizzo: verificaIndirizzo,
            verificaNome: verificaNome
        )
    }
    
    // MARK: - Generazione Relazione Streaming
    
    private func generaRelazioneStreaming(
        sinistro: Sinistro,
        analisi: AnalisiSinistroCompleta,
        ubicazione: String,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async {
        // Usa il task esistente per relazione ma con streaming
        let prompt = buildRelazionePrompt(sinistro: sinistro, analisi: analisi, ubicazione: ubicazione)
        
        let task = AITask(
            type: .textGeneration,
            priority: .secondary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true),
                "systemPrompt": AnyCodable("Sei un perito assicurativo che scrive relazioni tecniche professionali per perizie su fenomeni elettrici.")
            ],
            requiresKnowledge: true
        )
        
        // Streaming della relazione
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                AIManager.shared.enqueue(task) { aiResult in
                    if let text = aiResult.result?.value as? String {
                        streamCallback(text)
                    }
                    cont.resume(returning: aiResult.success)
                }
            }
        }
    }
    
    private func buildRelazionePrompt(sinistro: Sinistro, analisi: AnalisiSinistroCompleta, ubicazione: String) -> String {
        let beniDesc = analisi.beni.map { bene in
            """
            - \(bene.nome): \(bene.compatibilitaFE.esito). \(bene.osservazioniVisive)
            """
        }.joined(separator: "\n")
        
        return """
        Scrivi una relazione peritale professionale per il sinistro \(sinistro.riferimento ?? "N/A").
        
        DATI:
        - Assicurato: \(sinistro.nomeAssicurato ?? "N/D")
        - Ubicazione: \(ubicazione)
        - Tipo: \(analisi.fulminazione ? "Fulminazione" : "Fenomeno elettrico")
        - Sopralluogo: \(analisi.sopralluogo ? "Sì" : "No (documentale)")
        
        BENI ANALIZZATI:
        \(beniDesc)
        
        COMPLESSITÀ: \(analisi.complessita.livello) (\(analisi.complessita.punteggio)/10)
        
        Scrivi una relazione tecnica completa, professionale e dettagliata.
        """
    }
    
    // MARK: - Persistenza Analisi Streaming
    
    /// Salva i dati streaming completi in Core Data come JSON
    func salvaAnalisiStreaming(
        sinistro: Sinistro,
        beniStreaming: [BeneAnalysisStreaming],
        quadroContrattuale: AnalisiQuadroContrattuale?
    ) {
        let context = PersistenceController.shared.container.viewContext
        
        // Cerca o crea PerxiaAnalisi
        let fetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        fetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        fetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        fetch.fetchLimit = 1
        
        guard let perxiaAnalisi = try? context.fetch(fetch).first else {
            print("[PerxiaStreaming] ⚠️ PerxiaAnalisi non trovata, creazione necessaria")
            return
        }
        
        // Crea struttura dati per salvataggio
        struct AnalisiStreamingData: Codable {
            let beniStreaming: [BeneAnalysisStreaming]
            let quadroContrattuale: AnalisiQuadroContrattuale?
            let dataSalvataggio: Date
        }
        
        let data = AnalisiStreamingData(
            beniStreaming: beniStreaming,
            quadroContrattuale: quadroContrattuale,
            dataSalvataggio: Date()
        )
        
        // Codifica in JSON
        if let encoder = try? JSONEncoder().encode(data),
           let jsonString = String(data: encoder, encoding: .utf8) {
            perxiaAnalisi.contextSummary = jsonString
            try? context.save()
            print("[PerxiaStreaming] ✅ Dati streaming salvati: \(beniStreaming.count) beni")
        } else {
            print("[PerxiaStreaming] ❌ Errore codifica JSON dati streaming")
        }
    }
    
    /// Carica i dati streaming salvati da Core Data
    func caricaAnalisiStreaming(sinistro: Sinistro) -> (beni: [BeneAnalysisStreaming], quadroContrattuale: AnalisiQuadroContrattuale?)? {
        let context = PersistenceController.shared.container.viewContext
        
        let fetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        fetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        fetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        fetch.fetchLimit = 1
        
        guard let perxiaAnalisi = try? context.fetch(fetch).first,
              let jsonString = perxiaAnalisi.contextSummary,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        struct AnalisiStreamingData: Codable {
            let beniStreaming: [BeneAnalysisStreaming]
            let quadroContrattuale: AnalisiQuadroContrattuale?
            let dataSalvataggio: Date
        }
        
        do {
            let data = try JSONDecoder().decode(AnalisiStreamingData.self, from: jsonData)
            print("[PerxiaStreaming] ✅ Dati streaming caricati: \(data.beniStreaming.count) beni")
            return (data.beniStreaming, data.quadroContrattuale)
        } catch {
            print("[PerxiaStreaming] ❌ Errore decodifica JSON dati streaming: \(error)")
            return nil
        }
    }
}
