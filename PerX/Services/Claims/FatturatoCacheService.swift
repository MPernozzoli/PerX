import Foundation
import CoreData

/// Cache per i calcoli del fatturato mensile
class FatturatoCacheService {
    static let shared = FatturatoCacheService()
    
    private let userDefaultsKey = "fatturatoCache"
    private let backgroundQueue = DispatchQueue(label: "com.perx.fatturatoCache", qos: .utility)
    
    /// Struttura per la cache di un mese
    struct CachedBreakdown: Codable {
        var monthKey: String // "YYYY-MM"
        var breakdown: CachedFatturatoBreakdown
        var fiscaleBreakdown: CachedFatturatoFiscaleBreakdown
        var checksum: String // Hash per validare la cache
        var timestamp: Date
    }
    
    struct CachedFatturatoBreakdown: Codable {
        var totaleSinistri: Int
        var importoBase: Double
        var sinistriBase: Int
        var importoFascia: Double
        var sinistriFascia: Int
        var numeroFascia: Int?
        var importoDieciBeni: Double
        var sinistriDieciBeni: Int
        var totaleFatturato: Double
        var bonusMensili: Double
        var bonusMensiliList: [BonusMensileDetail]
        // Nuovi campi per compensi per danno
        var compensiDanno: Double?
        var sinistriConCompensoDanno: Int?
        var dettaglioCompensiDanno: [CompensoDannoDetail]?
    }
    
    struct CachedFatturatoFiscaleBreakdown: Codable {
        var totaleParziale: Double
        var marcaDaBollo: Double
        var totaleConMarca: Double
        var rivalsaINPS: Double
        var fatturatoLordo: Double
        var coefficienteSpesa: Double
        var imponibileContributivo: Double
        var contributiINPS: Double
        var imponibileFiscale: Double
        var tasse: Double
        var utileNetto: Double
    }
    
    private var cache: [String: CachedBreakdown] = [:]
    private var pendingRecalculations: Set<String> = [] // Tiene traccia dei mesi per cui è in corso un ricalcolo
    
    private init() {
        loadCache()
    }
    
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: CachedBreakdown].self, from: data) {
            cache = decoded
        }
    }
    
    private func saveCache() {
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    /// Calcola un checksum per validare la cache
    private func calcolaChecksum(
        for month: Date,
        sinistriChiusi: [Sinistro],
        bonusMensili: [BonusMensile],
        fatturatoSettings: FatturatoSettings,
        fiscaleSettings: FatturatoFiscaleSettings
    ) -> String {
        var components: [String] = []
        
        // Numero e hash dei sinistri (usiamo le date di chiusura per identificare cambiamenti)
        // Il numero di sinistri è già incluso nel conteggio, quindi se cambia il numero, cambia anche il checksum
        let sinistriHash = sinistriChiusi
            .map { "\($0.riferimento ?? "")-\($0.dataChiusura?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|")
        // Includiamo il conteggio per garantire che cambiamenti nel numero invalidino la cache
        components.append("sinistri:\(sinistriChiusi.count):\(sinistriHash.hash)")
        
        // Hash dei bonus mensili
        if let bonusData = try? JSONEncoder().encode(bonusMensili) {
            components.append("bonus:\(bonusData.hashValue)")
        }
        
        // Impostazioni fatturazione
        components.append("base:\(fatturatoSettings.importoBase)")
        components.append("base10:\(fatturatoSettings.importoBaseDieciBeni)")
        if let fasceData = try? JSONEncoder().encode(fatturatoSettings.fasce) {
            components.append("fasce:\(fasceData.hashValue)")
        }
        
        // Soglie danno per compagnia
        if let soglieData = try? JSONEncoder().encode(fatturatoSettings.soglie) {
            components.append("soglie:\(soglieData.hashValue)")
        }
        
        // Impostazioni fiscali
        components.append("tasse:\(fiscaleSettings.percentualeTasse)")
        components.append("marca:\(fiscaleSettings.marcaDaBolloAbilitata)")
        components.append("rivalsa:\(fiscaleSettings.rivalsaINPSAbilitata)")
        components.append("rivalsaPct:\(fiscaleSettings.rivalsaINPSPercentuale)")
        components.append("coeffRedd:\(fiscaleSettings.coefficienteRedditivita)")
        let year = Calendar.current.component(.year, from: month)
        components.append("inps:\(fiscaleSettings.getContributiINPS(for: month)):\(year)")
        
        let combined = components.joined(separator: "|")
        return String(combined.hashValue)
    }
    
    /// Converte un FatturatoBreakdown in CachedFatturatoBreakdown
    private func cache(_ breakdown: FatturatoBreakdown) -> CachedFatturatoBreakdown {
        return CachedFatturatoBreakdown(
            totaleSinistri: breakdown.totaleSinistri,
            importoBase: breakdown.importoBase,
            sinistriBase: breakdown.sinistriBase,
            importoFascia: breakdown.importoFascia,
            sinistriFascia: breakdown.sinistriFascia,
            numeroFascia: breakdown.numeroFascia,
            importoDieciBeni: breakdown.importoDieciBeni,
            sinistriDieciBeni: breakdown.sinistriDieciBeni,
            totaleFatturato: breakdown.totaleFatturato,
            bonusMensili: breakdown.bonusMensili,
            bonusMensiliList: breakdown.bonusMensiliList,
            compensiDanno: breakdown.compensiDanno,
            sinistriConCompensoDanno: breakdown.sinistriConCompensoDanno,
            dettaglioCompensiDanno: breakdown.dettaglioCompensiDanno
        )
    }
    
    /// Converte un CachedFatturatoBreakdown in FatturatoBreakdown
    private func breakdown(from cached: CachedFatturatoBreakdown) -> FatturatoBreakdown {
        return FatturatoBreakdown(
            totaleSinistri: cached.totaleSinistri,
            importoBase: cached.importoBase,
            sinistriBase: cached.sinistriBase,
            importoFascia: cached.importoFascia,
            sinistriFascia: cached.sinistriFascia,
            numeroFascia: cached.numeroFascia,
            importoDieciBeni: cached.importoDieciBeni,
            sinistriDieciBeni: cached.sinistriDieciBeni,
            totaleFatturato: cached.totaleFatturato,
            bonusMensili: cached.bonusMensili,
            bonusMensiliList: cached.bonusMensiliList,
            compensiDanno: cached.compensiDanno ?? 0,
            sinistriConCompensoDanno: cached.sinistriConCompensoDanno ?? 0,
            dettaglioCompensiDanno: cached.dettaglioCompensiDanno ?? []
        )
    }
    
    /// Converte un FatturatoFiscaleBreakdown in CachedFatturatoFiscaleBreakdown
    private func cache(_ breakdown: FatturatoFiscaleBreakdown) -> CachedFatturatoFiscaleBreakdown {
        return CachedFatturatoFiscaleBreakdown(
            totaleParziale: breakdown.totaleParziale,
            marcaDaBollo: breakdown.marcaDaBollo,
            totaleConMarca: breakdown.totaleConMarca,
            rivalsaINPS: breakdown.rivalsaINPS,
            fatturatoLordo: breakdown.fatturatoLordo,
            coefficienteSpesa: breakdown.coefficienteSpesa,
            imponibileContributivo: breakdown.imponibileContributivo,
            contributiINPS: breakdown.contributiINPS,
            imponibileFiscale: breakdown.imponibileFiscale,
            tasse: breakdown.tasse,
            utileNetto: breakdown.utileNetto
        )
    }
    
    /// Converte un CachedFatturatoFiscaleBreakdown in FatturatoFiscaleBreakdown
    private func breakdown(from cached: CachedFatturatoFiscaleBreakdown) -> FatturatoFiscaleBreakdown {
        return FatturatoFiscaleBreakdown(
            totaleParziale: cached.totaleParziale,
            marcaDaBollo: cached.marcaDaBollo,
            totaleConMarca: cached.totaleConMarca,
            rivalsaINPS: cached.rivalsaINPS,
            fatturatoLordo: cached.fatturatoLordo,
            coefficienteSpesa: cached.coefficienteSpesa,
            imponibileContributivo: cached.imponibileContributivo,
            contributiINPS: cached.contributiINPS,
            imponibileFiscale: cached.imponibileFiscale,
            tasse: cached.tasse,
            utileNetto: cached.utileNetto
        )
    }
    
    /// Recupera i breakdown dalla cache se validi, altrimenti nil
    func getCachedBreakdowns(
        for month: Date,
        sinistriChiusi: [Sinistro],
        bonusMensili: [BonusMensile],
        fatturatoSettings: FatturatoSettings,
        fiscaleSettings: FatturatoFiscaleSettings
    ) -> (breakdown: FatturatoBreakdown, fiscaleBreakdown: FatturatoFiscaleBreakdown)? {
        let monthKey = FatturaMensile.monthKey(from: month)
        
        guard let cached = cache[monthKey] else {
            return nil
        }
        
        let currentChecksum = calcolaChecksum(
            for: month,
            sinistriChiusi: sinistriChiusi,
            bonusMensili: bonusMensili,
            fatturatoSettings: fatturatoSettings,
            fiscaleSettings: fiscaleSettings
        )
        
        // Se il checksum corrisponde, la cache è valida
        if cached.checksum == currentChecksum {
            return (
                breakdown: breakdown(from: cached.breakdown),
                fiscaleBreakdown: breakdown(from: cached.fiscaleBreakdown)
            )
        }
        
        // Checksum non corrisponde, cache invalidata
        return nil
    }
    
    /// Salva i breakdown in cache
    func saveBreakdowns(
        breakdown: FatturatoBreakdown,
        fiscaleBreakdown: FatturatoFiscaleBreakdown,
        for month: Date,
        sinistriChiusi: [Sinistro],
        bonusMensili: [BonusMensile],
        fatturatoSettings: FatturatoSettings,
        fiscaleSettings: FatturatoFiscaleSettings
    ) {
        let monthKey = FatturaMensile.monthKey(from: month)
        
        let checksum = calcolaChecksum(
            for: month,
            sinistriChiusi: sinistriChiusi,
            bonusMensili: bonusMensili,
            fatturatoSettings: fatturatoSettings,
            fiscaleSettings: fiscaleSettings
        )
        
        let cached = CachedBreakdown(
            monthKey: monthKey,
            breakdown: cache(breakdown),
            fiscaleBreakdown: cache(fiscaleBreakdown),
            checksum: checksum,
            timestamp: Date()
        )
        
        cache[monthKey] = cached
        saveCache()
    }
    
    /// Invalida la cache per un mese specifico e avvia il ricalcolo in background
    func invalidaCacheERicalcolaInBackground(for month: Date, context: NSManagedObjectContext, userEmail: String? = nil) {
        let monthKey = FatturaMensile.monthKey(from: month)
        
        // Rimuovi dalla cache
        cache.removeValue(forKey: monthKey)
        saveCache()
        
        // Se è già in corso un ricalcolo per questo mese, non ne avviare un altro
        guard !pendingRecalculations.contains(monthKey) else {
            return
        }
        
        pendingRecalculations.insert(monthKey)
        
        // Avvia il ricalcolo in background
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Crea un nuovo contesto per il background
            let backgroundContext = context.persistentStoreCoordinator.map { coordinator in
                let bgContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                bgContext.persistentStoreCoordinator = coordinator
                return bgContext
            }
            
            guard let bgContext = backgroundContext else {
                DispatchQueue.main.async {
                    self.pendingRecalculations.remove(monthKey)
                }
                return
            }
            
            bgContext.perform {
                do {
                    // Recupera i sinistri chiusi per il mese
                    let sinistriChiusi = ConsuntivoStatsService.shared.getMonthlyClosedClaimsSuccessful(for: month, in: bgContext, userEmail: userEmail)
                    let monthlyClosedClaims = ConsuntivoStatsService.shared.getMonthlyClosedClaims(for: month, in: bgContext, userEmail: userEmail)
                    
                    // Recupera i bonus
                    let bonusList = BonusMensileService.shared.getBonus(for: month).filter { $0.attivo }
                    
                    // Calcola i breakdown
                    let bonusMensili = BonusMensileService.shared.calcolaTotaleBonus(for: month, sinistriChiusi: sinistriChiusi, in: bgContext)
                    let bonusDetails = bonusList.map { bonus in
                        let importoBonus = BonusMensileService.shared.calcolaImportoBonus(bonus, for: sinistriChiusi, in: bgContext, month: month)
                        return BonusMensileDetail(
                            nome: bonus.nome,
                            tipo: bonus.tipo,
                            importo: importoBonus
                        )
                    }
                    
                    let breakdown = FatturatoSettings.shared.calcolaBreakdownFatturato(
                        sinistri: monthlyClosedClaims,
                        bonusMensili: bonusMensili,
                        bonusMensiliList: bonusDetails
                    )
                    
                    let fiscaleBreakdown = FatturatoSettings.shared.calcolaFatturatoFiscale(
                        breakdown: breakdown,
                        fiscaleSettings: FatturatoFiscaleSettings.shared,
                        for: month
                    )
                    
                    // Estrai i dati necessari per il checksum PRIMA di passare al main thread
                    // Gli oggetti CoreData non possono essere acceduti da un thread diverso
                    let sinistriData: [(riferimento: String?, dataChiusura: Date?)] = sinistriChiusi.map {
                        (riferimento: $0.riferimento, dataChiusura: $0.dataChiusura)
                    }
                    let sinistriCount = sinistriChiusi.count
                    let bonusForMonth = BonusMensileService.shared.getBonus(for: month)
                    
                    // Salva in cache (sul main thread per UserDefaults)
                    DispatchQueue.main.async {
                        self.saveBreakdownsWithExtractedData(
                            breakdown: breakdown,
                            fiscaleBreakdown: fiscaleBreakdown,
                            for: month,
                            sinistriData: sinistriData,
                            sinistriCount: sinistriCount,
                            bonusMensili: bonusForMonth,
                            fatturatoSettings: FatturatoSettings.shared,
                            fiscaleSettings: FatturatoFiscaleSettings.shared
                        )
                        self.pendingRecalculations.remove(monthKey)
                    }
                } catch {
                    print("Errore durante il ricalcolo in background del fatturato: \(error)")
                    DispatchQueue.main.async {
                        self.pendingRecalculations.remove(monthKey)
                    }
                }
            }
        }
    }
    
    /// Salva i breakdown in cache usando dati già estratti (thread-safe)
    private func saveBreakdownsWithExtractedData(
        breakdown: FatturatoBreakdown,
        fiscaleBreakdown: FatturatoFiscaleBreakdown,
        for month: Date,
        sinistriData: [(riferimento: String?, dataChiusura: Date?)],
        sinistriCount: Int,
        bonusMensili: [BonusMensile],
        fatturatoSettings: FatturatoSettings,
        fiscaleSettings: FatturatoFiscaleSettings
    ) {
        let monthKey = FatturaMensile.monthKey(from: month)
        
        let checksum = calcolaChecksumWithExtractedData(
            for: month,
            sinistriData: sinistriData,
            sinistriCount: sinistriCount,
            bonusMensili: bonusMensili,
            fatturatoSettings: fatturatoSettings,
            fiscaleSettings: fiscaleSettings
        )
        
        let cached = CachedBreakdown(
            monthKey: monthKey,
            breakdown: cache(breakdown),
            fiscaleBreakdown: cache(fiscaleBreakdown),
            checksum: checksum,
            timestamp: Date()
        )
        
        cache[monthKey] = cached
        saveCache()
    }
    
    /// Calcola checksum usando dati già estratti (thread-safe)
    private func calcolaChecksumWithExtractedData(
        for month: Date,
        sinistriData: [(riferimento: String?, dataChiusura: Date?)],
        sinistriCount: Int,
        bonusMensili: [BonusMensile],
        fatturatoSettings: FatturatoSettings,
        fiscaleSettings: FatturatoFiscaleSettings
    ) -> String {
        var components: [String] = []
        
        // Numero e hash dei sinistri
        let sinistriHash = sinistriData
            .map { "\($0.riferimento ?? "")-\($0.dataChiusura?.timeIntervalSince1970 ?? 0)" }
            .sorted()
            .joined(separator: "|")
        components.append("sinistri:\(sinistriCount):\(sinistriHash.hash)")
        
        // Hash dei bonus mensili
        if let bonusData = try? JSONEncoder().encode(bonusMensili) {
            components.append("bonus:\(bonusData.hashValue)")
        }
        
        // Impostazioni fatturazione
        components.append("base:\(fatturatoSettings.importoBase)")
        components.append("base10:\(fatturatoSettings.importoBaseDieciBeni)")
        if let fasceData = try? JSONEncoder().encode(fatturatoSettings.fasce) {
            components.append("fasce:\(fasceData.hashValue)")
        }
        
        // Soglie danno per compagnia
        if let soglieData = try? JSONEncoder().encode(fatturatoSettings.soglie) {
            components.append("soglie:\(soglieData.hashValue)")
        }
        
        // Impostazioni fiscali
        components.append("tasse:\(fiscaleSettings.percentualeTasse)")
        components.append("marca:\(fiscaleSettings.marcaDaBolloAbilitata)")
        components.append("rivalsa:\(fiscaleSettings.rivalsaINPSAbilitata)")
        components.append("rivalsaPct:\(fiscaleSettings.rivalsaINPSPercentuale)")
        components.append("coeffRedd:\(fiscaleSettings.coefficienteRedditivita)")
        let year = Calendar.current.component(.year, from: month)
        components.append("inps:\(fiscaleSettings.getContributiINPS(for: month)):\(year)")
        
        let combined = components.joined(separator: "|")
        return String(combined.hashValue)
    }
    
    /// Invalida la cache per un mese specifico
    func invalidaCache(for month: Date) {
        let monthKey = FatturaMensile.monthKey(from: month)
        cache.removeValue(forKey: monthKey)
        saveCache()
    }
    
    /// Invalida tutta la cache
    func invalidaTuttaCache() {
        cache.removeAll()
        saveCache()
    }
}
