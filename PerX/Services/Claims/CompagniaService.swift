import Foundation

// MARK: - Gruppi Assicurativi

enum GruppoAssicurativo: String, CaseIterable, Codable {
    case zurich = "Zurich Group"
    case generali = "Generali"
    case unipolSai = "UnipolSai"
    case unknown = "Altro"
    
    static func from(nomeGruppo: String?) -> GruppoAssicurativo {
        guard let nome = nomeGruppo?.lowercased() else { return .unknown }
        
        if nome.contains("zurich") {
            return .zurich
        } else if nome.contains("generali") || nome.contains("cattolica") {
            return .generali
        } else if nome.contains("unipol") {
            return .unipolSai
        }
        return .unknown
    }
    
    var compagnie: [Compagnia] {
        switch self {
        case .zurich:
            return [.zurichItalia]
        case .generali:
            return [.cattolica, .generaliItalia]
        case .unipolSai:
            return [.unipolItalia]
        case .unknown:
            return []
        }
    }
    
    // MARK: - UI Metadata (colore e icona per filtri)
    
    /// Colore UI del gruppo (RGB 0-1)
    var uiColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .zurich: return (0.0, 0.47, 0.78)      // Blu Zurich
        case .generali: return (0.77, 0.12, 0.23)  // Rosso Generali
        case .unipolSai: return (0.0, 0.44, 0.25)  // Verde Unipol
        case .unknown: return (0.5, 0.5, 0.5)      // Grigio
        }
    }
    
    /// Icona SF Symbol per il gruppo
    var uiIconSystemName: String {
        switch self {
        case .zurich: return "building.2.fill"
        case .generali: return "building.columns.fill"
        case .unipolSai: return "shield.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    /// Label breve per UI
    var shortLabel: String {
        switch self {
        case .zurich: return "Zurich"
        case .generali: return "Generali"
        case .unipolSai: return "Unipol"
        case .unknown: return "Altro"
        }
    }
}

// MARK: - Compagnie

enum Compagnia: String, CaseIterable, Codable {
    case zurichItalia = "Zurich Italia"
    case cattolica = "Cattolica"
    case generaliItalia = "Generali Italia"
    case unipolItalia = "Unipol Italia"
    case unknown = "Altro"
    
    // MARK: - Detection
    
    static func from(nomeCompagnia: String?) -> Compagnia {
        guard let nome = nomeCompagnia?.lowercased() else { return .unknown }
        
        if nome.contains("zurich") && nome.contains("italia") {
            return .zurichItalia
        } else if nome.contains("cattolica") {
            return .cattolica
        } else if nome.contains("generali") && nome.contains("italia") {
            return .generaliItalia
        } else if nome.contains("unipol") && nome.contains("italia") {
            return .unipolItalia
        }
        return .unknown
    }
    
    /// Determina la compagnia prima dal gruppo, poi dal nome compagnia
    static func detect(gruppo: String?, compagnia: String?) -> Compagnia {
        // Prima verifica gruppo
        let gruppoRiconosciuto = GruppoAssicurativo.from(nomeGruppo: gruppo)
        
        // Se il gruppo ha una sola compagnia, usa quella
        if gruppoRiconosciuto.compagnie.count == 1 {
            return gruppoRiconosciuto.compagnie[0]
        }
        
        // Altrimenti cerca nel nome compagnia
        return from(nomeCompagnia: compagnia)
    }
    
    // MARK: - Properties
    
    var sigla: String {
        switch self {
        case .zurichItalia: return "ZUR"
        case .cattolica: return "CAT"
        case .generaliItalia: return "GEN"
        case .unipolItalia: return "UNI"
        case .unknown: return "XXX"
        }
    }
    
    var gruppo: GruppoAssicurativo {
        switch self {
        case .zurichItalia: return .zurich
        case .cattolica, .generaliItalia: return .generali
        case .unipolItalia: return .unipolSai
        case .unknown: return .unknown
        }
    }
    
    // MARK: - UI Metadata (colore, icona e logo per filtri)
    
    /// Colore UI della compagnia (RGB 0-1)
    var uiColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .zurichItalia: return (0.0, 0.47, 0.78)      // Blu Zurich
        case .cattolica: return (0.85, 0.55, 0.0)        // Arancione Cattolica
        case .generaliItalia: return (0.77, 0.12, 0.23)  // Rosso Generali
        case .unipolItalia: return (0.0, 0.44, 0.25)     // Verde Unipol
        case .unknown: return (0.5, 0.5, 0.5)            // Grigio
        }
    }
    
    /// Icona SF Symbol per la compagnia
    var uiIconSystemName: String {
        switch self {
        case .zurichItalia: return "z.circle.fill"
        case .cattolica: return "c.circle.fill"
        case .generaliItalia: return "g.circle.fill"
        case .unipolItalia: return "u.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    /// Nome asset del logo PNG (nil = usa icona di default)
    /// TODO: Aggiungere PNG logo per ogni compagnia in Assets.xcassets
    var logoAssetName: String? {
        switch self {
        case .zurichItalia: return nil  // TODO: "logo_zurich"
        case .cattolica: return nil     // TODO: "logo_cattolica"
        case .generaliItalia: return nil // TODO: "logo_generali"
        case .unipolItalia: return nil  // TODO: "logo_unipol"
        case .unknown: return nil
        }
    }
    
    /// Label breve per UI
    var shortLabel: String {
        switch self {
        case .zurichItalia: return "Zurich"
        case .cattolica: return "Cattolica"
        case .generaliItalia: return "Generali"
        case .unipolItalia: return "Unipol"
        case .unknown: return "Altro"
        }
    }
    
    /// Zurich non invia quasi mai gli atti: usiamo data comunica esito come data invio atto
    var usaComunicaEsitoPerAtto: Bool {
        switch self {
        case .zurichItalia: return true
        default: return false
        }
    }
    
    /// Unipol allega sempre la fulminazione, le altre solo se positiva
    var sempreAllegaFulminazione: Bool {
        switch self {
        case .unipolItalia: return true
        default: return false
        }
    }
    
    /// Determina se l'atto è sempre richiesto per la chiusura
    /// - Generali/Unipol: sempre (se concordata verbale: atto + accettazione)
    /// - Zurich: solo per sinistri non indennizzabili o con vincolo bancario
    var attoSempreRichiesto: Bool {
        switch self {
        case .cattolica, .generaliItalia, .unipolItalia:
            return true
        case .zurichItalia:
            return false // Zurich richiede atto solo in casi specifici
        case .unknown:
            return false
        }
    }
    
    // MARK: - File Richiesti per Chiusura
    
    /// Tipi di file sempre obbligatori per la chiusura (indipendentemente dal sinistro)
    /// - Unipol: Foto, Verbale, Fulminazione, Atto
    /// - Generali: Foto, Verbale, Atto
    /// - Zurich: Foto, Verbale (Atto solo in casi specifici)
    var fileObbligatoriChiusura: [TipoFileCompagnia] {
        switch self {
        case .unipolItalia:
            return [.foto, .verbale, .fulminazione, .atto]
        case .cattolica, .generaliItalia:
            return [.foto, .verbale, .atto]
        case .zurichItalia:
            return [.foto, .verbale] // Atto gestito separatamente
        case .unknown:
            return [.foto]
        }
    }
    
    /// Verifica se un tipo di file è richiesto per la chiusura
    func isFileRichiesto(_ tipo: TipoFileCompagnia) -> Bool {
        return fileObbligatoriChiusura.contains(tipo)
    }
    
    // MARK: - Range Liquidazione e PL
    
    /// Range per il calcolo della media liquidato (esclusi negativi)
    var rangeLiquidatoMedio: (min: Double, max: Double) {
        switch self {
        case .cattolica, .generaliItalia:
            // Gruppo Generali: da 1 a 5k (esclusi special client)
            return (min: 1, max: 5000)
        case .zurichItalia:
            // Zurich: da 1 a 5k
            return (min: 1, max: 5000)
        case .unipolItalia:
            // Unipol: da 250 a 4k
            return (min: 250, max: 4000)
        case .unknown:
            return (min: 1, max: 10000)
        }
    }
    
    /// Range per il calcolo della media PL (solo sinistri in PL)
    var rangePL: (min: Double, max: Double) {
        switch self {
        case .cattolica, .generaliItalia:
            // Gruppo Generali: da 1 a 5k
            return (min: 1, max: 5000)
        case .zurichItalia:
            // Zurich: da 1 a 10k
            return (min: 1, max: 10000)
        case .unipolItalia:
            // Unipol: da 1 a 4k (con eccezioni, non tutti i sinistri sono in PL)
            return (min: 1, max: 4000)
        case .unknown:
            return (min: 1, max: 10000)
        }
    }
    
    // MARK: - Valori di Riferimento
    
    /// Valore target per la media liquidato (sotto questo valore è ottimale)
    var targetLiquidatoMedio: Double {
        switch self {
        case .cattolica, .generaliItalia:
            // Gruppo Generali: <800
            return 800
        case .zurichItalia:
            // Zurich: <1000
            return 1000
        case .unipolItalia:
            // Unipol: <750
            return 750
        case .unknown:
            return 1000
        }
    }
    
    /// Valore target per la percentuale di negative (sopra questo valore è ottimale)
    var targetNegative: Double {
        switch self {
        case .cattolica, .generaliItalia:
            // Gruppo Generali: 10%
            return 10
        case .zurichItalia:
            // Zurich: 10%
            return 10
        case .unipolItalia:
            // Unipol: 5%
            return 5
        case .unknown:
            return 10
        }
    }
    
    /// Valore target per il tempo medio di gestione in giorni (sotto questo valore è ottimale)
    var targetTempoGestione: Double {
        // 20 giorni per tutte le compagnie
        return 20
    }
    
    /// Valore target per la percentuale di concordate (sopra questo valore è ottimale)
    /// Generali/Unipol: 85%, Zurich: 90%
    var targetConcordate: Double {
        switch self {
        case .cattolica, .generaliItalia:
            return 85
        case .unipolItalia:
            return 85
        case .zurichItalia:
            return 90
        case .unknown:
            return 85
        }
    }
}

extension GruppoAssicurativo {
    /// Range per il calcolo della media liquidato (esclusi negativi) - usa valori effettivi (override o default)
    var rangeLiquidatoMedio: (min: Double, max: Double) {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveRangeLiquidatoMedio(primaCompagnia)
        }
        return (min: 1, max: 10000)
    }
    
    /// Range per il calcolo della media PL (solo sinistri in PL) - usa valori effettivi (override o default)
    var rangePL: (min: Double, max: Double) {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveRangePL(primaCompagnia)
        }
        return (min: 1, max: 10000)
    }
    
    /// Valore target per la media liquidato - usa valori effettivi (override o default)
    var targetLiquidatoMedio: Double {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveTargetLiquidatoMedio(primaCompagnia)
        }
        return 1000
    }
    
    /// Valore target per la percentuale di negative - usa valori effettivi (override o default)
    var targetNegative: Double {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveTargetNegative(primaCompagnia)
        }
        return 10
    }
    
    /// Valore target per il tempo medio di gestione - usa valori effettivi (override o default)
    var targetTempoGestione: Double {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveTargetTempoGestione(primaCompagnia)
        }
        return 20
    }
    
    /// Valore target per la percentuale di concordate - usa valori effettivi (override o default)
    var targetConcordate: Double {
        if let primaCompagnia = compagnie.first {
            return CompagniaSettingsService.shared.effectiveTargetConcordate(primaCompagnia)
        }
        return 85
    }
}

// MARK: - Tipi di File per Nomenclatura

enum TipoFileCompagnia: String, CaseIterable {
    case perizia
    case foto
    case atto
    case giustificativi
    case verbale
    case fulminazione
    case altro
    
    /// Ordine di priorità per la numerazione progressiva
    var priorita: Int {
        switch self {
        case .perizia: return 0          // Sempre 1
        case .fulminazione: return 1     // Prima di tutto dopo perizia
        case .foto: return 2
        case .atto: return 3
        case .giustificativi: return 4
        case .verbale: return 5
        case .altro: return 6            // Sempre ultimo
        }
    }
}

// MARK: - Sottotipi

enum SottotipoAtto: String {
    case liquidazione = "liquidazione"
    case accertamento = "accertamento"
}

enum SottotipoGiustificativo: String {
    case preventivo = "preventivo"
    case fattura = "fattura"
}

enum SottotipoChiusura: String {
    case concordata = "concordata"
    case nonConcordata = "nonconcordata"
}

// MARK: - CompagniaService

class CompagniaService {
    static let shared = CompagniaService()
    
    private init() {}
    
    // MARK: - File Nomenclatura
    
    /// Genera il nome file secondo le regole della compagnia
    func generaNomeFile(
        compagnia: Compagnia,
        riferimento: String,
        tipoFile: TipoFileCompagnia,
        progressivo: Int? = nil,
        concordata: Bool? = nil,
        sottotipoAtto: SottotipoAtto? = nil,
        sottotipoGiustificativo: SottotipoGiustificativo? = nil
    ) -> String {
        switch compagnia {
        case .zurichItalia:
            return generaNomeFileZurich(
                riferimento: riferimento,
                tipoFile: tipoFile,
                progressivo: progressivo ?? 2
            )
            
        case .cattolica, .generaliItalia:
            return generaNomeFileGruppoGenerali(
                riferimento: riferimento,
                tipoFile: tipoFile,
                progressivo: progressivo ?? 1,
                concordata: concordata,
                sottotipoAtto: sottotipoAtto,
                sottotipoGiustificativo: sottotipoGiustificativo
            )
            
        case .unipolItalia:
            return generaNomeFileUnipol(
                riferimento: riferimento,
                tipoFile: tipoFile,
                progressivo: progressivo ?? 1
            )
            
        case .unknown:
            // Fallback generico
            return "\(riferimento)_\(tipoFile.rawValue)"
        }
    }
    
    // MARK: - Zurich Nomenclatura
    
    /// Zurich: [riferimento]_1 per perizia, [riferimento]_x per tutto il resto
    private func generaNomeFileZurich(riferimento: String, tipoFile: TipoFileCompagnia, progressivo: Int) -> String {
        switch tipoFile {
        case .perizia:
            return "\(riferimento)_1"
        default:
            return "\(riferimento)_\(progressivo)"
        }
    }
    
    // MARK: - Gruppo Generali (Cattolica, Generali Italia) Nomenclatura
    
    /// Cattolica/Generali Italia nomenclatura con suffissi specifici
    private func generaNomeFileGruppoGenerali(
        riferimento: String,
        tipoFile: TipoFileCompagnia,
        progressivo: Int,
        concordata: Bool?,
        sottotipoAtto: SottotipoAtto?,
        sottotipoGiustificativo: SottotipoGiustificativo?
    ) -> String {
        switch tipoFile {
        case .perizia:
            let chiusura = concordata ?? false ? "concordata" : "nonconcordata"
            return "\(riferimento)_\(chiusura)"
            
        case .foto:
            return "\(riferimento)_foto"
            
        case .atto:
            let tipo = sottotipoAtto?.rawValue ?? "liquidazione"
            return "\(riferimento)_\(tipo)"
            
        case .giustificativi:
            let tipo = sottotipoGiustificativo?.rawValue ?? "preventivo"
            return "\(riferimento)_\(tipo)"
            
        case .verbale:
            return "\(riferimento)_verbale"
            
        case .fulminazione:
            // Fulminazione è sempre il primo "altro" (prioritario)
            return "\(riferimento)_altro\(progressivo)"
            
        case .altro:
            return "\(riferimento)_altro\(progressivo)"
        }
    }
    
    // MARK: - Unipol Nomenclatura
    
    /// Unipol nomenclatura specifica
    private func generaNomeFileUnipol(riferimento: String, tipoFile: TipoFileCompagnia, progressivo: Int) -> String {
        switch tipoFile {
        case .perizia:
            return "\(riferimento)_perizia"
            
        case .atto:
            // Il sottotipo viene determinato esternamente in base alla chiusura
            return "\(riferimento)_liquidazione" // Default, sostituito dal chiamante
            
        case .giustificativi:
            return "\(riferimento)_richiesta"
            
        case .fulminazione:
            return "\(riferimento)_meteo"
            
        case .verbale:
            return "\(riferimento)_altro1"
            
        case .foto:
            // Foto è sempre l'ultimo nella lista "altro"
            return "\(riferimento)_altro\(progressivo)"
            
        case .altro:
            return "\(riferimento)_altro\(progressivo)"
        }
    }
    
    // MARK: - Generazione Lista File Ordinata
    
    struct FileNomenclatura {
        let tipo: TipoFileCompagnia
        let nomeFile: String
        let progressivo: Int
    }
    
    /// Genera la lista di nomi file ordinata per priorità
    /// I file mancanti vengono esclusi e i progressivi si adattano
    func generaListaFileOrdinata(
        compagnia: Compagnia,
        riferimento: String,
        filePresenti: Set<TipoFileCompagnia>,
        concordata: Bool? = nil,
        sottotipoAtto: SottotipoAtto? = nil,
        sottotipoGiustificativo: SottotipoGiustificativo? = nil
    ) -> [FileNomenclatura] {
        
        var risultato: [FileNomenclatura] = []
        var progressivoAltro = 1
        var progressivoGenerale = 2 // Per Zurich, inizia da 2 (1 è perizia)
        
        // Ordina per priorità
        let tipiOrdinati = filePresenti.sorted { $0.priorita < $1.priorita }
        
        for tipo in tipiOrdinati {
            let nomeFile: String
            let progressivo: Int
            
            switch compagnia {
            case .zurichItalia:
                if tipo == .perizia {
                    progressivo = 1
                } else {
                    progressivo = progressivoGenerale
                    progressivoGenerale += 1
                }
                nomeFile = generaNomeFileZurich(
                    riferimento: riferimento,
                    tipoFile: tipo,
                    progressivo: progressivo
                )
                
            case .cattolica, .generaliItalia:
                switch tipo {
                case .perizia, .foto, .atto, .giustificativi, .verbale:
                    progressivo = 0 // Non usato per questi tipi
                case .fulminazione, .altro:
                    progressivo = progressivoAltro
                    progressivoAltro += 1
                }
                nomeFile = generaNomeFileGruppoGenerali(
                    riferimento: riferimento,
                    tipoFile: tipo,
                    progressivo: progressivo,
                    concordata: concordata,
                    sottotipoAtto: sottotipoAtto,
                    sottotipoGiustificativo: sottotipoGiustificativo
                )
                
            case .unipolItalia:
                switch tipo {
                case .perizia, .atto, .giustificativi, .fulminazione:
                    progressivo = 0 // Non usato per questi tipi
                case .verbale:
                    progressivo = 1 // Verbale è sempre altro1
                case .foto, .altro:
                    progressivo = progressivoAltro
                    if tipo != .verbale {
                        progressivoAltro += 1
                    }
                }
                nomeFile = generaNomeFileUnipol(
                    riferimento: riferimento,
                    tipoFile: tipo,
                    progressivo: progressivo
                )
                
            case .unknown:
                progressivo = progressivoGenerale
                progressivoGenerale += 1
                nomeFile = "\(riferimento)_\(tipo.rawValue)"
            }
            
            risultato.append(FileNomenclatura(
                tipo: tipo,
                nomeFile: nomeFile,
                progressivo: progressivo
            ))
        }
        
        return risultato
    }
    
    // MARK: - Segmentazione Numero Sinistro per Thread
    
    /// Segmenta il numero sinistro compagnia per estrarre la parte usata nei thread email
    /// Restituisce le varianti del numero che possono essere usate per il matching
    func segmentaNumeroSinistro(numeroCompleto: String, compagnia: Compagnia) -> [String] {
        var segmenti: [String] = [numeroCompleto]
        
        switch compagnia {
        case .zurichItalia:
            // Formato Zurich: es. "300/2024/1234567" o "300-2024-1234567"
            // Le email possono contenere solo parte del numero
            let segments = segmentaZurich(numeroCompleto)
            segmenti.append(contentsOf: segments)
            
        case .cattolica:
            // Formato Cattolica: es. "2024/123456/01" o simile
            let segments = segmentaCattolica(numeroCompleto)
            segmenti.append(contentsOf: segments)
            
        case .generaliItalia:
            // Formato Generali Italia: simile a Cattolica
            let segments = segmentaCattolica(numeroCompleto)
            segmenti.append(contentsOf: segments)
            
        case .unipolItalia:
            // Formato Unipol: 1-8101-2026-0040019
            let segments = segmentaUnipol(numeroCompleto)
            segmenti.append(contentsOf: segments)
            
        case .unknown:
            break
        }
        
        // Rimuovi duplicati e stringhe vuote
        return Array(Set(segmenti.filter { !$0.isEmpty }))
    }
    
    /// Segmentazione specifica per Zurich
    private func segmentaZurich(_ numero: String) -> [String] {
        var segmenti: [String] = []
        
        // Normalizza separatori
        let normalizzato = numero
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        
        // Split per /
        let parti = normalizzato.split(separator: "/").map(String.init)
        
        if parti.count >= 3 {
            // Formato tipico: CODICE/ANNO/NUMERO
            // Aggiungi le ultime 7 cifre (numero pratica)
            if let ultimo = parti.last, ultimo.count >= 7 {
                segmenti.append(String(ultimo.suffix(7)))
            }
            
            // Aggiungi ANNO/NUMERO
            segmenti.append("\(parti[1])/\(parti[2])")
            
            // Aggiungi solo il numero finale
            if let ultimo = parti.last {
                segmenti.append(ultimo)
            }
        } else if parti.count == 2 {
            // Formato: ANNO/NUMERO
            segmenti.append(contentsOf: parti)
        }
        
        // Estrai qualsiasi sequenza di 7+ cifre
        let numeriPuri = numero.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for num in numeriPuri where num.count >= 7 {
            segmenti.append(num)
            if num.count > 7 {
                segmenti.append(String(num.suffix(7)))
            }
        }
        
        return segmenti
    }
    
    /// Segmentazione specifica per Cattolica/Generali Italia
    private func segmentaCattolica(_ numero: String) -> [String] {
        var segmenti: [String] = []
        
        // Normalizza separatori
        let normalizzato = numero
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        
        // Split per /
        let parti = normalizzato.split(separator: "/").map(String.init)
        
        if parti.count >= 3 {
            // Formato tipico: ANNO/NUMERO/PROGRESSIVO
            // Aggiungi ANNO/NUMERO (senza progressivo)
            segmenti.append("\(parti[0])/\(parti[1])")
            
            // Aggiungi solo il numero centrale
            segmenti.append(parti[1])
            
            // Aggiungi numero+progressivo
            segmenti.append("\(parti[1])/\(parti[2])")
        } else if parti.count == 2 {
            segmenti.append(contentsOf: parti)
        }
        
        // Estrai qualsiasi sequenza di 6+ cifre
        let numeriPuri = numero.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for num in numeriPuri where num.count >= 6 {
            segmenti.append(num)
        }
        
        return segmenti
    }
    
    /// Segmentazione specifica per Unipol
    /// Formato: 1-8101-2026-0040019 (4 segmenti separati da trattino)
    /// Varianti per ricerca mail: completo, senza trattini, ultime 7 cifre
    private func segmentaUnipol(_ numero: String) -> [String] {
        var segmenti: [String] = []
        
        // Versione senza trattini
        let senzaTrattini = numero.replacingOccurrences(of: "-", with: "")
        if senzaTrattini != numero {
            segmenti.append(senzaTrattini)
        }
        
        // Split per trattino
        let parti = numero.split(separator: "-").map(String.init)
        
        // Formato tipico: 1-8101-2026-0040019 (tipo, codice, anno, numero progressivo)
        if parti.count >= 4 {
            // Ultima parte è il numero progressivo (es. 0040019)
            let numeroProgressivo = parti[3]
            segmenti.append(numeroProgressivo)
            
            // Ultime 7 cifre del progressivo (es. 0040019 → 0040019, o se più lungo le ultime 7)
            if numeroProgressivo.count >= 7 {
                let ultime7 = String(numeroProgressivo.suffix(7))
                if ultime7 != numeroProgressivo {
                    segmenti.append(ultime7)
                }
            }
            
            // Anno-numero (es. 2026-0040019)
            segmenti.append("\(parti[2])-\(parti[3])")
            
            // Codice-anno-numero (es. 8101-2026-0040019)
            segmenti.append("\(parti[1])-\(parti[2])-\(parti[3])")
        } else if parti.count == 3 {
            // Formato ridotto senza primo segmento
            let numeroProgressivo = parti[2]
            segmenti.append(numeroProgressivo)
            if numeroProgressivo.count >= 7 {
                segmenti.append(String(numeroProgressivo.suffix(7)))
            }
        }
        
        // Estrai qualsiasi sequenza di 7+ cifre (per match generico)
        let numeriPuri = numero.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for num in numeriPuri where num.count >= 7 {
            segmenti.append(num)
            // Aggiungi anche le ultime 7 cifre se il numero è più lungo
            if num.count > 7 {
                segmenti.append(String(num.suffix(7)))
            }
        }
        
        return segmenti
    }
    
    // MARK: - Match Numero Sinistro
    
    /// Verifica se un testo (es. corpo email) contiene una variante del numero sinistro
    func matchNumeroSinistro(testo: String, numeroSinistro: String, compagnia: Compagnia) -> Bool {
        let segmenti = segmentaNumeroSinistro(numeroCompleto: numeroSinistro, compagnia: compagnia)
        let testoNormalizzato = testo.lowercased()
        
        for segmento in segmenti {
            // Match esatto o con separatori diversi
            let segmentoNormalizzato = segmento.lowercased()
            if testoNormalizzato.contains(segmentoNormalizzato) {
                return true
            }
            
            // Prova anche con spazi invece di /
            let conSpazi = segmentoNormalizzato.replacingOccurrences(of: "/", with: " ")
            if testoNormalizzato.contains(conSpazi) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Utility
    
    /// Verifica quali file sono richiesti per la chiusura di un sinistro specifico
    /// Tiene conto delle regole della compagnia e delle caratteristiche del sinistro
    /// - Parameters:
    ///   - compagnia: La compagnia assicurativa
    ///   - sinistro: Il sinistro da verificare
    /// - Returns: Array dei tipi di file richiesti
    func getFileRichiestiPerChiusura(compagnia: Compagnia, sinistro: Sinistro) -> [TipoFileCompagnia] {
        var fileRichiesti = CompagniaSettingsService.shared.effectiveFileObbligatoriChiusura(compagnia)
        
        // Per Zurich, aggiungi l'atto solo se il sinistro lo richiede
        if compagnia == .zurichItalia {
            if isAttoRichiesto(compagnia: compagnia, sinistro: sinistro) {
                fileRichiesti.append(.atto)
            }
        }
        
        return fileRichiesti
    }
    
    /// Determina se l'atto è richiesto per un sinistro specifico
    /// - Parameters:
    ///   - compagnia: La compagnia assicurativa
    ///   - sinistro: Il sinistro da verificare
    /// - Returns: true se l'atto è richiesto
    func isAttoRichiesto(compagnia: Compagnia, sinistro: Sinistro) -> Bool {
        // Se la compagnia richiede sempre l'atto, restituisci true
        if CompagniaSettingsService.shared.effectiveFileObbligatoriChiusura(compagnia).contains(.atto) {
            return true
        }
        
        // Zurich: atto solo per sinistri non indennizzabili
        if compagnia == .zurichItalia {
            let definizione = sinistro.definizione?.lowercased() ?? ""
            let isNonIndennizzabile = definizione.contains("negativ") ||
                                      definizione.contains("accertamento") ||
                                      definizione.contains("senza seguito") ||
                                      definizione.contains("non indennizzabile")
            return isNonIndennizzabile
        }
        
        return false
    }
    
    /// Determina il sottotipo dell'atto in base al tipo di chiusura del sinistro
    func determinaSottotipoAtto(tipoChiusura: String?) -> SottotipoAtto {
        guard let chiusura = tipoChiusura?.lowercased() else { return .accertamento }
        
        // Chiusure che indicano liquidazione
        let tipiLiquidazione = [
            "liquidazione",
            "concordata",
            "pagato",
            "transazione",
            "risarcimento"
        ]
        
        for tipo in tipiLiquidazione {
            if chiusura.contains(tipo) {
                return .liquidazione
            }
        }
        
        return .accertamento
    }
    
    /// Determina se la perizia è concordata o meno
    func isConcordata(tipoChiusura: String?) -> Bool {
        guard let chiusura = tipoChiusura?.lowercased() else { return false }
        
        let tipiConcordati = [
            "concordata",
            "transazione",
            "accordo"
        ]
        
        for tipo in tipiConcordati {
            if chiusura.contains(tipo) {
                return true
            }
        }
        
        return false
    }
    
    /// Determina se includere il file fulminazione nella chiusura
    /// - Parameters:
    ///   - compagnia: La compagnia assicurativa
    ///   - sottotipo: "positiva" o "negativa" (nil = negativa)
    /// - Returns: true se la fulminazione deve essere inclusa
    func shouldIncludeFulminazione(compagnia: Compagnia, sottotipo: String?) -> Bool {
        // Unipol allega sempre
        if CompagniaSettingsService.shared.effectiveSempreAllegaFulminazione(compagnia) {
            return true
        }
        
        // Altre compagnie: solo se positiva
        return sottotipo?.lowercased() == "positiva"
    }
}

// MARK: - Estensioni per Compatibilità

extension CompagniaService {
    
    /// Compatibilità con AgencyReaderHelper.CompagniaType
    func toCompagnia(_ legacyType: String) -> Compagnia {
        switch legacyType.lowercased() {
        case "cattolica":
            return .cattolica
        case "generaliitalia":
            return .generaliItalia
        case "zurichitalia":
            return .zurichItalia
        default:
            return .unknown
        }
    }
}

// MARK: - Unipol Specific Parsing

extension CompagniaService {
    
    /// Estrae il codice agenzia Unipol dal formato Excel
    /// Input: "53936- Agenzia 53936" o "53936-Agenzia 53936" o simili
    /// Output: "53936" (solo il codice numerico)
    func estraiCodiceAgenziaUnipol(_ agenziaRaw: String?) -> String? {
        guard let raw = agenziaRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        
        // Pattern: codice numerico all'inizio seguito da trattino
        // Es: "53936- Agenzia 53936" → "53936"
        if let dashRange = raw.range(of: "-") {
            let codice = String(raw[..<dashRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !codice.isEmpty, codice.allSatisfy({ $0.isNumber }) {
                return codice
            }
        }
        
        // Fallback: estrai primo gruppo di numeri
        let numeri = raw.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        return numeri.first
    }
    
    /// Formatta il numero sinistro Unipol per visualizzazione UI
    /// Input: "18101-2026-0040019" o "1810120260040019"
    /// Output: "1-8101-2026-0040019" (formato standard con trattini)
    func formattaNumeroSinistroUnipol(_ numero: String?) -> String? {
        guard let raw = numero?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        
        // Se già formattato con trattini, restituisci così
        if raw.contains("-") {
            return raw
        }
        
        // Prova a formattare numero continuo
        // Formato atteso: 1 cifra + 4 cifre + 4 cifre (anno) + 7 cifre = 16 cifre totali
        let soloNumeri = raw.filter { $0.isNumber }
        
        if soloNumeri.count == 16 {
            let idx1 = soloNumeri.index(soloNumeri.startIndex, offsetBy: 1)
            let idx2 = soloNumeri.index(idx1, offsetBy: 4)
            let idx3 = soloNumeri.index(idx2, offsetBy: 4)
            
            let parte1 = String(soloNumeri[..<idx1])           // 1 cifra
            let parte2 = String(soloNumeri[idx1..<idx2])       // 4 cifre (codice)
            let parte3 = String(soloNumeri[idx2..<idx3])       // 4 cifre (anno)
            let parte4 = String(soloNumeri[idx3...])           // 7 cifre (progressivo)
            
            return "\(parte1)-\(parte2)-\(parte3)-\(parte4)"
        }
        
        // Formato con 15 cifre (senza prima cifra): 4+4+7
        if soloNumeri.count == 15 {
            let idx1 = soloNumeri.index(soloNumeri.startIndex, offsetBy: 4)
            let idx2 = soloNumeri.index(idx1, offsetBy: 4)
            
            let parte1 = String(soloNumeri[..<idx1])           // 4 cifre (codice)
            let parte2 = String(soloNumeri[idx1..<idx2])       // 4 cifre (anno)
            let parte3 = String(soloNumeri[idx2...])           // 7 cifre (progressivo)
            
            return "\(parte1)-\(parte2)-\(parte3)"
        }
        
        // Non riconosciuto, restituisci originale
        return raw
    }
    
    /// Verifica se una stringa rappresenta un nome compagnia Unipol (UnipolSai, Unipol, Unipol Sai, Unipol-Sai)
    /// Case insensitive, gestisce tutte le varianti storiche dopo il rebranding
    func isUnipol(_ nomeCompagnia: String?) -> Bool {
        guard let nome = nomeCompagnia?.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "") else {
            return false
        }
        
        // Tutte le varianti normalizzate diventano "unipolsai" o "unipol"
        return nome.contains("unipol")
    }
    
    /// Normalizza il nome compagnia Unipol per storage consistente
    /// UnipolSai, Unipol, Unipol Sai, Unipol-Sai → "Unipol"
    func normalizzaNomeUnipol(_ nomeCompagnia: String?) -> String? {
        guard isUnipol(nomeCompagnia) else { return nomeCompagnia }
        return "Unipol"
    }
}

