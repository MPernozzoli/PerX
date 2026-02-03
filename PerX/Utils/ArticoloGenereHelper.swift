import Foundation

/// Helper per determinare l'articolo corretto in base al genere del nome
struct ArticoloGenereHelper {
    
    // MARK: - Genere
    
    enum Genere {
        case maschile
        case femminile
    }
    
    // MARK: - Dizionario beni comuni
    
    /// Dizionario dei beni comuni con il loro genere
    /// Key: nome bene in minuscolo, Value: genere
    private static let beniFemminili: Set<String> = [
        // Elettrodomestici femminili
        "lavatrice", "lavastoviglie", "asciugatrice", "lavasciuga",
        "cappa", "cappa aspirante", "friggitrice", "macchina del caffè",
        "macchinetta", "moka", "stufa", "stufa elettrica", "stufa a pellet",
        "lampada", "abat-jour", "piantana", "plafoniera",
        "tv", "televisione", "antenna", "parabola",
        "caldaia", "pompa", "pompa di calore", "pompa sommersa",
        "motopompa", "centralina", "scheda", "scheda elettronica",
        "unità interna", "unità esterna", "split",
        "serranda", "tapparella", "persiana", "zanzariera",
        "presa", "spina", "ciabatta", "multipresa",
        "tastiera", "stampante", "webcam",
        // Componenti
        "valvola", "resistenza", "bobina", "ventola", "batteria",
        // Impianti
        "linea", "linea elettrica", "dorsale",
        // Altro
        "cassaforte", "bilancia", "bilancia professionale"
    ]
    
    /// Beni che iniziano con vocale (richiedono l'apostrofo)
    private static let beniConVocaleIniziale: Set<String> = [
        "impianto", "inverter", "asciugatrice", "aspirapolvere",
        "antenna", "autoclave", "ascensore", "orologio",
        "amplificatore", "alimentatore", "estrattore", "umidificatore",
        "elettrodomestico", "interruttore", "abbattitore"
    ]
    
    // MARK: - Metodi pubblici
    
    /// Determina il genere di un nome bene
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: Genere determinato
    static func determinaGenere(di nomeBene: String) -> Genere {
        let nomeNormalizzato = nomeBene.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Controlla nel dizionario femminili
        if beniFemminili.contains(nomeNormalizzato) {
            return .femminile
        }
        
        // Controlla se il nome inizia con una parola femminile
        for bene in beniFemminili {
            if nomeNormalizzato.hasPrefix(bene + " ") || nomeNormalizzato.hasPrefix(bene + "-") {
                return .femminile
            }
        }
        
        // Euristica: nomi che finiscono in -a sono spesso femminili
        // Ma attenzione: clima, sistema, problema sono maschili
        let eccezioniMaschili = ["clima", "sistema", "problema", "schema", "tema", "plasma", "programma", "dilemma"]
        if nomeNormalizzato.hasSuffix("a") && !eccezioniMaschili.contains(where: { nomeNormalizzato.hasSuffix($0) }) {
            // Verifica se è un suffisso comune femminile
            let suffissiFemminili = ["trice", "iera", "ina", "ella", "etta", "essa", "rice"]
            if suffissiFemminili.contains(where: { nomeNormalizzato.hasSuffix($0) }) {
                return .femminile
            }
        }
        
        // Default: maschile
        return .maschile
    }
    
    /// Determina se il nome inizia con vocale (per apostrofo)
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: true se inizia con vocale
    static func iniziaConVocale(_ nomeBene: String) -> Bool {
        let nomeNormalizzato = nomeBene.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Controlla nel dizionario
        if beniConVocaleIniziale.contains(nomeNormalizzato) {
            return true
        }
        
        // Controlla prima lettera
        let vocali: Set<Character> = ["a", "e", "i", "o", "u"]
        if let primaLettera = nomeNormalizzato.first {
            return vocali.contains(primaLettera)
        }
        
        return false
    }
    
    /// Restituisce l'articolo determinativo corretto per un bene
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: Articolo determinativo (il, la, l')
    static func articoloDeterminativo(per nomeBene: String) -> String {
        if iniziaConVocale(nomeBene) {
            return "l'"
        }
        
        let genere = determinaGenere(di: nomeBene)
        return genere == .femminile ? "la" : "il"
    }
    
    /// Restituisce l'articolo indeterminativo corretto per un bene
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: Articolo indeterminativo (un, una, un')
    static func articoloIndeterminativo(per nomeBene: String) -> String {
        let genere = determinaGenere(di: nomeBene)
        
        if genere == .femminile {
            if iniziaConVocale(nomeBene) {
                return "un'"
            }
            return "una"
        }
        
        return "un"
    }
    
    /// Formatta il nome del bene con l'articolo corretto
    /// - Parameters:
    ///   - nomeBene: Nome del bene
    ///   - determinativo: Se usare l'articolo determinativo (default) o indeterminativo
    /// - Returns: Stringa con articolo + nome (es. "il frigorifero", "la lavatrice")
    static func conArticolo(_ nomeBene: String, determinativo: Bool = true) -> String {
        let articolo = determinativo ? articoloDeterminativo(per: nomeBene) : articoloIndeterminativo(per: nomeBene)
        
        // Se l'articolo finisce con apostrofo, non mettere spazio
        if articolo.hasSuffix("'") {
            return articolo + nomeBene.lowercased()
        }
        
        return articolo + " " + nomeBene.lowercased()
    }
    
    /// Formatta una lista di beni con articoli corretti
    /// - Parameters:
    ///   - nomiBeni: Array di nomi dei beni
    ///   - congiunzione: Congiunzione da usare (default "e")
    /// - Returns: Stringa formattata (es. "il frigorifero, la lavatrice e l'impianto")
    static func listaConArticoli(_ nomiBeni: [String], congiunzione: String = "e") -> String {
        guard !nomiBeni.isEmpty else { return "" }
        
        if nomiBeni.count == 1 {
            return conArticolo(nomiBeni[0])
        }
        
        let formattati = nomiBeni.map { conArticolo($0) }
        
        if formattati.count == 2 {
            return "\(formattati[0]) \(congiunzione) \(formattati[1])"
        }
        
        let tuttiTranneUltimo = formattati.dropLast().joined(separator: ", ")
        return "\(tuttiTranneUltimo) \(congiunzione) \(formattati.last!)"
    }
    
    /// Restituisce la forma corretta per "lamentato/lamentata" in base al genere
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: "lamentato" o "lamentata"
    static func lamentato(per nomeBene: String) -> String {
        let genere = determinaGenere(di: nomeBene)
        return genere == .femminile ? "lamentata" : "lamentato"
    }
    
    /// Restituisce la forma corretta per "danneggiato/danneggiata" in base al genere
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: "danneggiato" o "danneggiata"
    static func danneggiato(per nomeBene: String) -> String {
        let genere = determinaGenere(di: nomeBene)
        return genere == .femminile ? "danneggiata" : "danneggiato"
    }
    
    /// Formatta il bene con "lamentato danneggiato" concordato
    /// - Parameter nomeBene: Nome del bene
    /// - Returns: Stringa come "il frigorifero lamentato danneggiato"
    static func beneLamentatoDanneggiato(_ nomeBene: String) -> String {
        let articolo = conArticolo(nomeBene)
        let lam = lamentato(per: nomeBene)
        let dan = danneggiato(per: nomeBene)
        return "\(articolo) \(lam) \(dan)"
    }
    
    /// Genera la frase corretta per uno o più beni
    /// - Parameter nomiBeni: Array di nomi dei beni
    /// - Returns: Frase formattata (singolare concordato o "i beni lamentati danneggiati")
    static func fraseBeniLamentatiDanneggiati(_ nomiBeni: [String]) -> String {
        guard !nomiBeni.isEmpty else { return "i beni lamentati danneggiati" }
        
        if nomiBeni.count == 1 {
            return beneLamentatoDanneggiato(nomiBeni[0])
        }
        
        // Per più beni, usare sempre il plurale generico
        return "i beni lamentati danneggiati"
    }
    
    /// Genera la frase corretta per "preso visione di/del/della/dei/delle/degli [beni]"
    /// - Parameter nomiBeni: Array di nomi dei beni
    /// - Returns: Frase formattata (es. "del cancello lamentato danneggiato" o "dei beni lamentati danneggiati")
    static func frasePresoVisione(_ nomiBeni: [String]) -> String {
        guard !nomiBeni.isEmpty else { return "dei beni lamentati danneggiati" }
        
        if nomiBeni.count == 1 {
            let nomeBene = nomiBeni[0]
            let articoloPrep = articoloPreposizionale(per: nomeBene, plurale: false)
            let lam = lamentato(per: nomeBene)
            let dan = danneggiato(per: nomeBene)
            
            if articoloPrep.hasSuffix("'") {
                return "\(articoloPrep)\(nomeBene.lowercased()) \(lam) \(dan)"
            }
            return "\(articoloPrep) \(nomeBene.lowercased()) \(lam) \(dan)"
        }
        
        // Per più beni, usare sempre il plurale generico
        return "dei beni lamentati danneggiati"
    }
    
    // MARK: - Articoli Preposizionali
    
    /// Restituisce l'articolo preposizionale corretto (di/del/della/dei/delle/degli)
    /// - Parameters:
    ///   - nomeBene: Nome del bene
    ///   - plurale: Se usare forma plurale (default: false)
    /// - Returns: Articolo preposizionale (di, del, della, dei, delle, degli)
    static func articoloPreposizionale(per nomeBene: String, plurale: Bool = false) -> String {
        if plurale {
            // Plurale
            let genere = determinaGenere(di: nomeBene)
            
            if iniziaConVocale(nomeBene) {
                return "degli"
            }
            
            return genere == .femminile ? "delle" : "dei"
        } else {
            // Singolare
            let genere = determinaGenere(di: nomeBene)
            
            if iniziaConVocale(nomeBene) {
                return "dell'"
            }
            
            return genere == .femminile ? "della" : "del"
        }
    }
    
    /// Formatta il nome con articolo preposizionale corretto
    /// - Parameters:
    ///   - nomeBene: Nome del bene
    ///   - plurale: Se usare forma plurale (default: false)
    /// - Returns: Stringa con articolo preposizionale + nome (es. "della caldaia", "dei frigoriferi")
    static func conArticoloPreposizionale(_ nomeBene: String, plurale: Bool = false) -> String {
        let articolo = articoloPreposizionale(per: nomeBene, plurale: plurale)
        
        // Se l'articolo finisce con apostrofo, non mettere spazio
        if articolo.hasSuffix("'") {
            return articolo + nomeBene.lowercased()
        }
        
        return articolo + " " + nomeBene.lowercased()
    }
    
    /// Genera la frase corretta per "documentazione fotografica di/del/della/dei/delle/degli [beni]"
    /// - Parameter nomiBeni: Array di nomi dei beni
    /// - Returns: Frase formattata (es. "della caldaia", "dei beni lamentati danneggiati")
    static func fraseDocumentazioneFotografica(_ nomiBeni: [String]) -> String {
        guard !nomiBeni.isEmpty else { return "dei beni lamentati danneggiati" }
        
        if nomiBeni.count == 1 {
            return conArticoloPreposizionale(nomiBeni[0], plurale: false)
        }
        
        // Per più beni, usare sempre il plurale generico
        return "dei beni lamentati danneggiati"
    }
}
