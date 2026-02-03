import Foundation

class FatturatoSettings: ObservableObject {
    static let shared = FatturatoSettings()
    
    @Published var importoBase: Double {
        didSet {
            UserDefaults.standard.set(importoBase, forKey: "importoBase")
            // Invalida tutta la cache quando cambiano le impostazioni globali
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    @Published var importoBaseDieciBeni: Double {
        didSet {
            UserDefaults.standard.set(importoBaseDieciBeni, forKey: "importoBaseDieciBeni")
            // Invalida tutta la cache quando cambiano le impostazioni globali
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    @Published var fasce: [FasciaNumero] {
        didSet {
            if let encoded = try? JSONEncoder().encode(fasce) {
                UserDefaults.standard.set(encoded, forKey: "fasceFatturato")
                // Invalida tutta la cache quando cambiano le impostazioni globali
                FatturatoCacheService.shared.invalidaTuttaCache()
            }
        }
    }
    
    @Published var soglie: [SogliaDanno] {
        didSet {
            if let encoded = try? JSONEncoder().encode(soglie) {
                UserDefaults.standard.set(encoded, forKey: "soglieDanno")
                // Invalida tutta la cache quando cambiano le soglie danno
                FatturatoCacheService.shared.invalidaTuttaCache()
            }
        }
    }
    
    struct FasciaNumero: Codable {
        var numeroSinistri: Int
        var percentualeIncremento: Double
        var importoFatturazione: Double
    }
    
    struct SogliaDanno: Codable, Identifiable {
        var id: UUID = UUID()
        var valoreDanno: Double
        var importoFatturazione: Double
        var compagnia: String? // nil = regola generica per tutte le compagnie
        /// Se true e compagnia è nil, questa soglia si applica solo a compagnie senza regole specifiche
        /// Se false e compagnia è nil, questa soglia si applica a TUTTE le compagnie indiscriminatamente
        var escludiSeSpecifica: Bool = true
        
        // Per retrocompatibilità con dati esistenti senza id
        enum CodingKeys: String, CodingKey {
            case id, valoreDanno, importoFatturazione, compagnia, escludiSeSpecifica
        }
        
        init(id: UUID = UUID(), valoreDanno: Double, importoFatturazione: Double, compagnia: String? = nil, escludiSeSpecifica: Bool = true) {
            self.id = id
            self.valoreDanno = valoreDanno
            self.importoFatturazione = importoFatturazione
            self.compagnia = compagnia
            self.escludiSeSpecifica = escludiSeSpecifica
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
            self.valoreDanno = try container.decode(Double.self, forKey: .valoreDanno)
            self.importoFatturazione = try container.decode(Double.self, forKey: .importoFatturazione)
            self.compagnia = try? container.decode(String.self, forKey: .compagnia)
            // Default true per retrocompatibilità: generiche escludono quelle con regole specifiche
            self.escludiSeSpecifica = (try? container.decode(Bool.self, forKey: .escludiSeSpecifica)) ?? true
        }
    }
    
    private init() {
        // Carica le impostazioni salvate o usa i default
        self.importoBase = UserDefaults.standard.double(forKey: "importoBase")
        self.importoBaseDieciBeni = UserDefaults.standard.double(forKey: "importoBaseDieciBeni")
        
        // Carica fasce
        let defaultFasce = [
            FasciaNumero(numeroSinistri: 50, percentualeIncremento: 0.10, importoFatturazione: 27.50),
            FasciaNumero(numeroSinistri: 75, percentualeIncremento: 0.15, importoFatturazione: 28.75),
            FasciaNumero(numeroSinistri: 100, percentualeIncremento: 0.20, importoFatturazione: 30.00),
            FasciaNumero(numeroSinistri: 130, percentualeIncremento: 0.25, importoFatturazione: 31.25)
        ]
        
        if let savedFasce = UserDefaults.standard.data(forKey: "fasceFatturato"),
           let decoded = try? JSONDecoder().decode([FasciaNumero].self, from: savedFasce) {
            self.fasce = decoded
        } else {
            self.fasce = defaultFasce
        }
        
        // Carica soglie
        let defaultSoglie = [
            SogliaDanno(valoreDanno: 10000, importoFatturazione: 100),
            SogliaDanno(valoreDanno: 20000, importoFatturazione: 200),
            SogliaDanno(valoreDanno: 50000, importoFatturazione: 300)
        ]
        
        if let savedSoglie = UserDefaults.standard.data(forKey: "soglieDanno"),
           let decoded = try? JSONDecoder().decode([SogliaDanno].self, from: savedSoglie) {
            self.soglie = decoded
        } else {
            self.soglie = defaultSoglie
        }
        
        if self.importoBase == 0 {
            self.importoBase = 25
        }
        if self.importoBaseDieciBeni == 0 {
            self.importoBaseDieciBeni = 40
        }
        
        // Sottoscrivi a CloudKit per ricaricare quando i settings vengono aggiornati
        NotificationCenter.default.addObserver(
            forName: NotificationNames.cloudKitSettingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let keys = notification.userInfo?["keys"] as? [String],
               keys.contains(where: { ["importoBase", "importoBaseDieciBeni", "fasceFatturato", "soglieDanno"].contains($0) }) {
                self.ricaricaImpostazioni()
            }
        }
    }
    
    func salvaFasce() {
        if let encoded = try? JSONEncoder().encode(fasce) {
            UserDefaults.standard.set(encoded, forKey: "fasceFatturato")
        }
    }
    
    func aggiornaFascia(at index: Int, nuovaFascia: FasciaNumero) {
        guard index >= 0 && index < fasce.count else { return }
        var nuoveFasce = fasce
        nuoveFasce[index] = nuovaFascia
        fasce = nuoveFasce // Sostituisce l'intero array per triggerare didSet
    }
    
    func salvaSoglie() {
        if let encoded = try? JSONEncoder().encode(soglie) {
            UserDefaults.standard.set(encoded, forKey: "soglieDanno")
        }
    }
    
    func ricaricaImpostazioni() {
        // Ricarica importi base
        let savedImportoBase = UserDefaults.standard.double(forKey: "importoBase")
        let savedImportoBaseDieciBeni = UserDefaults.standard.double(forKey: "importoBaseDieciBeni")
        
        if savedImportoBase != importoBase {
            importoBase = savedImportoBase
        }
        if savedImportoBaseDieciBeni != importoBaseDieciBeni {
            importoBaseDieciBeni = savedImportoBaseDieciBeni
        }
        
        // Ricarica fasce
        if let savedFasce = UserDefaults.standard.data(forKey: "fasceFatturato"),
           let decoded = try? JSONDecoder().decode([FasciaNumero].self, from: savedFasce) {
            fasce = decoded
        }
        
        // Ricarica soglie
        if let savedSoglie = UserDefaults.standard.data(forKey: "soglieDanno"),
           let decoded = try? JSONDecoder().decode([SogliaDanno].self, from: savedSoglie) {
            soglie = decoded
        }
    }
    
    /// Calcola il compenso per danno di un sinistro basandosi sul danno accertato e sulla compagnia
    /// Prima cerca una regola specifica per la compagnia, poi usa quella generica
    func calcolaCompensoDanno(dannoAccertato: Double, compagnia: String?) -> Double {
        // Ordina le soglie per valoreDanno decrescente per trovare la fascia corretta
        let soglieOrdinate = soglie.sorted { $0.valoreDanno > $1.valoreDanno }
        
        let nomeCompagniaNormalizzato = compagnia?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        let haCompagnia = !nomeCompagniaNormalizzato.isEmpty
        
        // Verifica se questa compagnia ha regole specifiche definite
        let compagniaHaRegoleSpecifiche = haCompagnia && soglieOrdinate.contains { soglia in
            guard let sogliaCompagnia = soglia.compagnia?.lowercased().trimmingCharacters(in: .whitespaces),
                  !sogliaCompagnia.isEmpty else { return false }
            return sogliaCompagnia == nomeCompagniaNormalizzato
        }
        
        // Prima cerca regole specifiche per la compagnia
        if haCompagnia {
            let soglieCompagnia = soglieOrdinate.filter { 
                $0.compagnia?.lowercased().trimmingCharacters(in: .whitespaces) == nomeCompagniaNormalizzato 
            }
            if let sogliaApplicabile = soglieCompagnia.first(where: { dannoAccertato >= $0.valoreDanno }) {
                return sogliaApplicabile.importoFatturazione
            }
        }
        
        // Cerca nelle soglie generiche
        let soglieGeneriche = soglieOrdinate.filter { $0.compagnia == nil || $0.compagnia?.isEmpty == true }
        
        for soglia in soglieGeneriche where dannoAccertato >= soglia.valoreDanno {
            // Se la compagnia ha regole specifiche e questa soglia le esclude, salta
            if compagniaHaRegoleSpecifiche && soglia.escludiSeSpecifica {
                continue
            }
            // Altrimenti applica questa soglia
            return soglia.importoFatturazione
        }
        
        return 0
    }
    
    /// Restituisce le compagnie per cui esistono regole specifiche
    func compagnieConRegoleSpecifiche() -> [String] {
        let compagnie = soglie.compactMap { $0.compagnia?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set(compagnie)).sorted()
    }
    
    func calcolaFatturatoGruppo(sinistri: [Sinistro]) -> Double {
        let totaleSinistri = sinistri.count
        
        // Determina la fascia di prezzo basata sul numero totale di sinistri
        var importoFascia = importoBase
        if let fascia = fasce.sorted(by: { $0.numeroSinistri > $1.numeroSinistri })
            .first(where: { totaleSinistri >= $0.numeroSinistri }) {
            importoFascia = fascia.importoFatturazione
        }
        
        var fatturato = 0.0
        
        for sinistro in sinistri {
            // Usa l'importo base o quello per >10 beni
            fatturato += sinistro.oltreDieciBeni ? importoBaseDieciBeni : importoFascia
        }
        
        print("📊 Calcolo Fatturato:")
        print("   • Totale sinistri: \(totaleSinistri)")
        print("   • Importo fascia corrente: €\(String(format: "%.2f", importoFascia))")
        print("   • Sinistri normali: \(sinistri.filter { !$0.oltreDieciBeni }.count)")
        print("   • Sinistri >10 beni: \(sinistri.filter { $0.oltreDieciBeni }.count)")
        print("   • Fatturato totale: €\(String(format: "%.2f", fatturato))")
        
        return fatturato
    }
} 