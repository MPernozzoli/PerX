import Foundation

class FatturatoFiscaleSettings: ObservableObject {
    static let shared = FatturatoFiscaleSettings()
    
    private static let fiscaleKeys = ["contributiINPS", "percentualeTasse", "marcaDaBolloAbilitata", "rivalsaINPSAbilitata", "rivalsaINPSPercentuale", "coefficienteRedditivita"]
    private var cloudKitObserver: NSObjectProtocol?
    
    // Contributi INPS per anno
    @Published private var contributiINPS: [Int: Double] {
        didSet {
            if let encoded = try? JSONEncoder().encode(contributiINPS) {
                UserDefaults.standard.set(encoded, forKey: "contributiINPS")
                // Invalida tutta la cache quando cambiano i contributi INPS
                FatturatoCacheService.shared.invalidaTuttaCache()
            }
        }
    }
    
    // Percentuale tasse (5% o 15%)
    @Published var percentualeTasse: Double {
        didSet {
            UserDefaults.standard.set(percentualeTasse, forKey: "percentualeTasse")
            // Invalida tutta la cache quando cambiano le impostazioni fiscali
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    // Marca da bollo abilitata
    @Published var marcaDaBolloAbilitata: Bool {
        didSet {
            UserDefaults.standard.set(marcaDaBolloAbilitata, forKey: "marcaDaBolloAbilitata")
            // Invalida tutta la cache quando cambiano le impostazioni fiscali
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    // Rivalsa INPS abilitata
    @Published var rivalsaINPSAbilitata: Bool {
        didSet {
            UserDefaults.standard.set(rivalsaINPSAbilitata, forKey: "rivalsaINPSAbilitata")
            // Invalida tutta la cache quando cambiano le impostazioni fiscali
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    // Percentuale rivalsa INPS sul totale (default 4%)
    @Published var rivalsaINPSPercentuale: Double {
        didSet {
            UserDefaults.standard.set(rivalsaINPSPercentuale, forKey: "rivalsaINPSPercentuale")
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    // Coefficiente di redditività / spesa (default 22%)
    @Published var coefficienteRedditivita: Double {
        didSet {
            UserDefaults.standard.set(coefficienteRedditivita, forKey: "coefficienteRedditivita")
            FatturatoCacheService.shared.invalidaTuttaCache()
        }
    }
    
    private let contributiINPSKey = "contributiINPS"
    private let percentualeTasseKey = "percentualeTasse"
    private let marcaDaBolloKey = "marcaDaBolloAbilitata"
    private let rivalsaINPSKey = "rivalsaINPSAbilitata"
    
    private init() {
        // Carica contributi INPS
        if let data = UserDefaults.standard.data(forKey: contributiINPSKey),
           let decoded = try? JSONDecoder().decode([Int: Double].self, from: data) {
            self.contributiINPS = decoded
        } else {
            // Valori default: anno corrente al 26.09%
            let currentYear = Calendar.current.component(.year, from: Date())
            self.contributiINPS = [currentYear: 26.09]
        }
        
        // Carica percentuale tasse (default 5%)
        let savedPercentualeTasse = UserDefaults.standard.double(forKey: percentualeTasseKey)
        if savedPercentualeTasse == 0 {
            self.percentualeTasse = 5.0
        } else {
            self.percentualeTasse = savedPercentualeTasse
        }
        
        // Carica marca da bollo (default true se non presente)
        if UserDefaults.standard.object(forKey: marcaDaBolloKey) != nil {
            self.marcaDaBolloAbilitata = UserDefaults.standard.bool(forKey: marcaDaBolloKey)
        } else {
            self.marcaDaBolloAbilitata = true
        }
        
        // Carica rivalsa INPS (default true se non presente)
        if UserDefaults.standard.object(forKey: rivalsaINPSKey) != nil {
            self.rivalsaINPSAbilitata = UserDefaults.standard.bool(forKey: rivalsaINPSKey)
        } else {
            self.rivalsaINPSAbilitata = true
        }
        
        // Carica percentuale rivalsa INPS (default 4%)
        let savedRivalsaPct = UserDefaults.standard.double(forKey: "rivalsaINPSPercentuale")
        self.rivalsaINPSPercentuale = savedRivalsaPct == 0 ? 4.0 : savedRivalsaPct
        
        // Carica coefficiente di redditività (default 22%)
        let savedCoeff = UserDefaults.standard.double(forKey: "coefficienteRedditivita")
        self.coefficienteRedditivita = savedCoeff == 0 ? 22.0 : savedCoeff
        
        // Sottoscrivi a CloudKit per ricaricare quando i settings vengono aggiornati
        cloudKitObserver = NotificationCenter.default.addObserver(
            forName: NotificationNames.cloudKitSettingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let keys = notification.userInfo?["keys"] as? [String],
               keys.contains(where: { Self.fiscaleKeys.contains($0) }) {
                self.ricaricaImpostazioni()
            }
        }
    }
    
    deinit {
        if let o = cloudKitObserver { NotificationCenter.default.removeObserver(o) }
    }
    
    func ricaricaImpostazioni() {
        let defaults = UserDefaults.standard
        
        if let data = defaults.data(forKey: contributiINPSKey),
           let decoded = try? JSONDecoder().decode([Int: Double].self, from: data) {
            contributiINPS = decoded
        }
        
        let savedTasse = defaults.double(forKey: percentualeTasseKey)
        if savedTasse != 0 { percentualeTasse = savedTasse }
        
        if defaults.object(forKey: marcaDaBolloKey) != nil {
            marcaDaBolloAbilitata = defaults.bool(forKey: marcaDaBolloKey)
        }
        
        if defaults.object(forKey: rivalsaINPSKey) != nil {
            rivalsaINPSAbilitata = defaults.bool(forKey: rivalsaINPSKey)
        }
        
        let savedRivalsaPct = defaults.double(forKey: "rivalsaINPSPercentuale")
        if savedRivalsaPct != 0 { rivalsaINPSPercentuale = savedRivalsaPct }
        
        let savedCoeff = defaults.double(forKey: "coefficienteRedditivita")
        if savedCoeff != 0 { coefficienteRedditivita = savedCoeff }
        
        objectWillChange.send()
    }
    
    func getContributiINPS(for date: Date) -> Double {
        let year = Calendar.current.component(.year, from: date)
        
        // Cerca l'anno corrente o il primo anno precedente disponibile
        if let contributo = contributiINPS[year] {
            return contributo
        }
        
        // Cerca anni precedenti in ordine decrescente
        for y in stride(from: year - 1, through: year - 10, by: -1) {
            if let contributo = contributiINPS[y] {
                return contributo
            }
        }
        
        // Default se non trovato
        return 26.09
    }
    
    func setContributiINPS(_ percentuale: Double, for year: Int) {
        contributiINPS[year] = percentuale
    }
}

