import Foundation
import CoreData

/// Manager per gestire i template delle relazioni peritali
class RelazioneTemplateManager {
    static let shared = RelazioneTemplateManager()
    
    private let context: NSManagedObjectContext
    private let fileTagManager = FileTagManager.shared
    private let fileService = FileService.shared
    private let calcoliService = CalcoliService.shared
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Template Base Hardcoded
    
    /// Template base per relazione peritale - caso standard con sopralluogo
    static let templateSopralluogoStandard = """
    A seguito dell'incarico ricevuto è stato effettuato sopralluogo presso l'ubicazione del rischio sito in [INDIRIZZO] previa disponibilità da parte dell'Assicurato.
    
    Al sopralluogo abbiamo preso visione [BENI_PRESO_VISIONE] a seguito del sinistro in oggetto come di seguito riportato all'interno della tabella di stima del danno.
    
    [ANALISI_TECNICA]
    
    [CONCLUSIONE_COMPATIBILITA]
    
    La stima del danno è stata redatta prendendo altresì in considerazione [GIUSTIFICATIVI] ed i prezzi medi di mercato per ripristini similari per prestazioni e funzionalità.
    """
    
    /// Template base per relazione peritale - caso documentale (no sopralluogo)
    static let templateDocumentaleStandard = """
    A seguito dell'incarico ricevuto abbiamo contattato l'Assicurato al fine di acquisire le informazioni necessarie allo svolgimento dell'attività peritale. Sulla base di quanto emerso in fase di primo contatto con l'Assicurato, ricorrendo le condizioni previste, abbiamo ritenuto opportuno espletare l'incarico mediante Perizia Documentale.
    
    È stata acquisita la documentazione fotografica [BENI_LAMENTATI_PREPOSIZIONALE] [GIUSTIFICATIVI_ACQUISITI]. [DESCRIZIONE_BENI_DALLE_FOTO]
    
    [ANALISI_TECNICA]
    
    [CONCLUSIONE_COMPATIBILITA]
    
    La stima del danno è stata effettuata considerando [GIUSTIFICATIVI_STIMA] per prestazioni, rendimento e funzionalità[PREVENTIVO_ALINEATO].
    
    [COASSICURAZIONE_FRASE]
    """
    
    /// Template per caso con residui non mantenuti
    static let templateNoResidui = """
    Abbiamo contattato l'Assicurato il quale ci ha comunicato di non aver conservato i residui del bene sinistrato. Pertanto, non siamo stati in grado di effettuare le verifiche tecniche necessarie per accertare la compatibilità del danno con la garanzia Fenomeno Elettrico.
    
    [BENI_LAMENTATI] risulta essere stato sostituito/riparato senza attendere le verifiche peritali.
    
    In assenza dei residui, non è possibile riscontrare elementi oggettivi che permettano di ricondurre il danno ad un fenomeno elettrico riconducibile alle condizioni di garanzia.
    """
    
    /// Template per caso FE positivo (con fulminazioni METEOCAST) - sopralluogo
    static let templateFEPositivoConFulminazioniSopralluogo = """
    Dalle verifiche tecniche effettuate [VERIFICHE_TECNICHE] riteniamo il lamentato danno riconducibile ad un fenomeno elettrico (con ogni probabilità a seguito di una variazione di tensione all'interno della rete elettrica dell'impianto dell'Assicurato).
    
    Evidenziamo la presenza di episodi di fulminazione il giorno del sinistro nelle immediate vicinanze dell'ubicazione del rischio.
    """
    
    /// Template per caso FE positivo (senza fulminazioni METEOCAST) - sopralluogo
    static let templateFEPositivoSenzaFulminazioniSopralluogo = """
    Dalle verifiche tecniche effettuate [VERIFICHE_TECNICHE] riteniamo il lamentato danno riconducibile ad un fenomeno elettrico (con ogni probabilità a seguito di una variazione di tensione all'interno della rete elettrica dell'impianto dell'Assicurato).
    """
    
    /// Template per caso FE positivo (con fulminazioni METEOCAST) - documentale
    static let templateFEPositivoConFulminazioniDocumentale = """
    Evidenziamo la presenza di episodi di fulminazione il giorno del sinistro nelle immediate vicinanze dell'ubicazione del rischio.
    
    Sulla base di quanto emerso riteniamo il danno riconducibile ad un fenomeno elettrico e pertanto indennizzabile a termini di Polizza.
    """
    
    /// Template per caso FE positivo (senza fulminazioni METEOCAST) - documentale
    static let templateFEPositivoSenzaFulminazioniDocumentale = """
    Sulla base di quanto emerso riteniamo il danno riconducibile ad un fenomeno elettrico e pertanto indennizzabile a termini di Polizza.
    """
    
    /// Template per caso FE negativo
    static let templateFENegativo = """
    Le verifiche tecniche effettuate non hanno evidenziato segni riconducibili ad un fenomeno elettrico. [MOTIVAZIONE_NEGATIVA]
    
    Sulla base degli accertamenti effettuati, non riteniamo il danno riconducibile alla garanzia Fenomeno Elettrico prevista in polizza.
    """
    
    // MARK: - Placeholder
    
    enum Placeholder: String, CaseIterable {
        case indirizzo = "[INDIRIZZO]"
        case dataSopralluogo = "[DATA_SOPRALLUOGO]"
        case descrizioneEvento = "[DESCRIZIONE_EVENTO]"
        case beniLamentati = "[BENI_LAMENTATI]"
        case beniLamentatiPreposizionale = "[BENI_LAMENTATI_PREPOSIZIONALE]"
        case statoBeni = "[STATO_BENI]"
        case analisiTecnica = "[ANALISI_TECNICA]"
        case conclusioneCompatibilita = "[CONCLUSIONE_COMPATIBILITA]"
        case segniFE = "[SEGNI_FE]"
        case motivazioneNegativa = "[MOTIVAZIONE_NEGATIVA]"
        case nomeAssicurato = "[NOME_ASSICURATO]"
        case dataEvento = "[DATA_EVENTO]"
        case descrizioneBeniDalleFoto = "[DESCRIZIONE_BENI_DALLE_FOTO]"
    }
    
    // MARK: - Selezione Template
    
    /// Seleziona il template appropriato in base alle caratteristiche del sinistro
    /// - Parameters:
    ///   - sopralluogo: Se è stato effettuato sopralluogo
    ///   - mantenimentoResidui: Stato dei residui ("si", "parziali", "no")
    ///   - fePositivo: Se il fenomeno elettrico è stato confermato
    ///   - haFulminazioni: Se ci sono fulminazioni rilevate da METEOCAST
    /// - Returns: Template base appropriato
    func selezionaTemplate(
        sopralluogo: Bool,
        mantenimentoResidui: String?,
        fePositivo: Bool?,
        haFulminazioni: Bool = false
    ) -> String {
        // Se non ci sono residui, usa template specifico
        if mantenimentoResidui?.lowercased() == "no" {
            return Self.templateNoResidui
        }
        
        // Scegli template base per sopralluogo o documentale
        var template = sopralluogo ? Self.templateSopralluogoStandard : Self.templateDocumentaleStandard
        
        // Aggiungi conclusione FE se determinata
        if let fePos = fePositivo {
            let conclusioneFE: String
            if fePos {
                // Usa template specifico per sopralluogo o documentale
                if sopralluogo {
                    conclusioneFE = haFulminazioni ? Self.templateFEPositivoConFulminazioniSopralluogo : Self.templateFEPositivoSenzaFulminazioniSopralluogo
                } else {
                    conclusioneFE = haFulminazioni ? Self.templateFEPositivoConFulminazioniDocumentale : Self.templateFEPositivoSenzaFulminazioniDocumentale
                }
            } else {
                conclusioneFE = Self.templateFENegativo
            }
            template = template.replacingOccurrences(of: Placeholder.conclusioneCompatibilita.rawValue, with: conclusioneFE)
        }
        
        return template
    }
    
    // MARK: - Personalizzazione Template
    
    /// Personalizza un template sostituendo i placeholder con i dati reali
    /// - Parameters:
    ///   - template: Template base
    ///   - sinistro: Sinistro da cui estrarre i dati
    ///   - perizia: Perizia associata
    ///   - beni: Array dei nomi dei beni coinvolti
    ///   - analisiTecnica: Analisi tecnica da inserire
    /// - Returns: Template personalizzato
    @MainActor
    func personalizzaTemplate(
        _ template: String,
        sinistro: Sinistro,
        perizia: Perizia,
        beni: [String],
        analisiTecnica: String? = nil
    ) async -> String {
        var risultato = template
        
        // Indirizzo
        let indirizzo = sinistro.indirizzoAssicurato ?? sinistro.indirizzoDanneggiato ?? "indirizzo non specificato"
        risultato = risultato.replacingOccurrences(of: Placeholder.indirizzo.rawValue, with: indirizzo)
        
        // Data sopralluogo
        if let dataSopralluogo = sinistro.dataSopralluogo {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.locale = Locale(identifier: "it_IT")
            risultato = risultato.replacingOccurrences(of: Placeholder.dataSopralluogo.rawValue, with: formatter.string(from: dataSopralluogo))
        } else {
            risultato = risultato.replacingOccurrences(of: "in data \(Placeholder.dataSopralluogo.rawValue) ", with: "")
        }
        
        // Beni lamentati
        let fraseBeni = ArticoloGenereHelper.fraseBeniLamentatiDanneggiati(beni)
        risultato = risultato.replacingOccurrences(of: Placeholder.beniLamentati.rawValue, with: fraseBeni)
        
        // Beni per "preso visione" (con articolo preposizionale corretto)
        let frasePresoVisione = ArticoloGenereHelper.frasePresoVisione(beni)
        risultato = risultato.replacingOccurrences(of: "[BENI_PRESO_VISIONE]", with: frasePresoVisione)
        
        // Beni lamentati con articolo preposizionale (per "documentazione fotografica di/del/della...")
        let fraseBeniPreposizionale = ArticoloGenereHelper.fraseDocumentazioneFotografica(beni)
        risultato = risultato.replacingOccurrences(of: Placeholder.beniLamentatiPreposizionale.rawValue, with: fraseBeniPreposizionale)
        
        // Descrizione evento (non più usato nei nuovi template, ma manteniamo per retrocompatibilità)
        let descrizioneEvento = perizia.eventoCausatoDa ?? "un evento"
        risultato = risultato.replacingOccurrences(of: Placeholder.descrizioneEvento.rawValue, with: "l'evento è riconducibile a \(descrizioneEvento.lowercased())")
        
        // Stato beni
        let statoBeni = determinaStatoBeni(perizia: perizia)
        if statoBeni.isEmpty {
            // Rimuovi placeholder e spazi multipli se stato beni è vuoto
            risultato = risultato.replacingOccurrences(of: Placeholder.statoBeni.rawValue, with: "")
        } else {
            risultato = risultato.replacingOccurrences(of: Placeholder.statoBeni.rawValue, with: statoBeni)
        }
        
        // Segni FE - rimuovi placeholder e frasi incomplete se non ci sono dati
        // Gestisce pattern come "quali [SEGNI_FE]." o "[SEGNI_FE]."
        if risultato.contains(Placeholder.segniFE.rawValue) {
            // Rimuovi pattern "quali [SEGNI_FE]." o "quali [SEGNI_FE]"
            risultato = risultato.replacingOccurrences(of: "quali \(Placeholder.segniFE.rawValue).", with: "")
            risultato = risultato.replacingOccurrences(of: "quali \(Placeholder.segniFE.rawValue)", with: "")
            // Rimuovi anche eventuali pattern con virgola o spazio
            risultato = risultato.replacingOccurrences(of: ", \(Placeholder.segniFE.rawValue).", with: ".")
            risultato = risultato.replacingOccurrences(of: " \(Placeholder.segniFE.rawValue).", with: ".")
            // Rimuovi placeholder standalone
            risultato = risultato.replacingOccurrences(of: Placeholder.segniFE.rawValue, with: "")
            // Pulisci spazi multipli e frasi incomplete
            risultato = risultato.replacingOccurrences(of: "  ", with: " ")
            risultato = risultato.replacingOccurrences(of: " .", with: ".")
            risultato = risultato.replacingOccurrences(of: " ,", with: ",")
        }
        
        // Descrizione beni dalle foto (per template documentale)
        let descrizioneBeni = generaDescrizioneBeniDalleFoto(perizia: perizia, beni: beni)
        risultato = risultato.replacingOccurrences(of: Placeholder.descrizioneBeniDalleFoto.rawValue, with: descrizioneBeni)
        
        // Analisi tecnica
        if let analisi = analisiTecnica, !analisi.isEmpty {
            risultato = risultato.replacingOccurrences(of: Placeholder.analisiTecnica.rawValue, with: analisi)
        } else {
            risultato = risultato.replacingOccurrences(of: Placeholder.analisiTecnica.rawValue, with: "")
        }
        
        // Nome assicurato
        let nomeAssicurato = sinistro.nomeAssicurato ?? sinistro.nomeDanneggiato ?? "l'Assicurato"
        risultato = risultato.replacingOccurrences(of: Placeholder.nomeAssicurato.rawValue, with: nomeAssicurato)
        
        // Data evento
        if let dataEvento = sinistro.dataSinistro {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.locale = Locale(identifier: "it_IT")
            risultato = risultato.replacingOccurrences(of: Placeholder.dataEvento.rawValue, with: formatter.string(from: dataEvento))
        }
        
        // Verifiche tecniche (visive, strumentali, funzionali)
        let verificheTecniche = await determinaVerificheTecniche(sinistro: sinistro)
        risultato = risultato.replacingOccurrences(of: "[VERIFICHE_TECNICHE]", with: verificheTecniche)
        
        // Giustificativi (fatture/preventivi)
        let testoGiustificativi = await determinaTestoGiustificativi(sinistro: sinistro)
        
        // Per [GIUSTIFICATIVI] nel template sopralluogo: se vuoto, rimuovi anche "prendendo altresì in considerazione" e l'"ed"
        if testoGiustificativi.isEmpty {
            risultato = risultato.replacingOccurrences(of: "prendendo altresì in considerazione [GIUSTIFICATIVI] ed i prezzi", with: "prendendo in considerazione i prezzi")
            risultato = risultato.replacingOccurrences(of: "[GIUSTIFICATIVI]", with: "")
        } else {
            risultato = risultato.replacingOccurrences(of: "[GIUSTIFICATIVI]", with: testoGiustificativi)
        }
        
        // Per [GIUSTIFICATIVI_ACQUISITI] nella relazione documentale
        let testoGiustificativiAcquisiti = await determinaTestoGiustificativiAcquisiti(sinistro: sinistro)
        risultato = risultato.replacingOccurrences(of: "[GIUSTIFICATIVI_ACQUISITI]", with: testoGiustificativiAcquisiti)
        
        // Per [GIUSTIFICATIVI_STIMA] nella relazione documentale
        if testoGiustificativi.isEmpty {
            risultato = risultato.replacingOccurrences(of: "[GIUSTIFICATIVI_STIMA]", with: "il prezzo medio di mercato di componenti equivalenti")
        } else {
            // testoGiustificativi contiene già "presentati da parte dell'Assicurato", quindi non lo ripetiamo
            risultato = risultato.replacingOccurrences(of: "[GIUSTIFICATIVI_STIMA]", with: "\(testoGiustificativi) ed i prezzi medi di mercato per ripristini similari")
        }
        
        // Preventivo allineato (solo se c'è preventivo e la richiesta è allineata)
        let frasePreventivo = determinaFrasePreventivo(sinistro: sinistro, perizia: perizia)
        risultato = risultato.replacingOccurrences(of: "[PREVENTIVO_ALINEATO]", with: frasePreventivo)
        
        // Coassicurazione frase (solo se coassicurazione è "no")
        let fraseCoassicurazione = determinaFraseCoassicurazione(sinistro: sinistro)
        risultato = risultato.replacingOccurrences(of: "[COASSICURAZIONE_FRASE]", with: fraseCoassicurazione)
        
        // Pulisci placeholder rimasti
        for placeholder in Placeholder.allCases {
            risultato = risultato.replacingOccurrences(of: placeholder.rawValue, with: "")
        }
        
        // Pulisci spazi e righe vuote multiple
        risultato = pulisciTesto(risultato)
        
        return risultato
    }
    
    // MARK: - Helper Verifiche Tecniche
    
    /// Determina il testo corretto per le verifiche tecniche effettuate
    /// - Parameter sinistro: Sinistro da verificare
    /// - Returns: Testo appropriato (es. "(visive)", "(visive, strumentali)", "(visive, funzionali)", "(visive, strumentali, funzionali)")
    @MainActor
    private func determinaVerificheTecniche(sinistro: Sinistro) async -> String {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            return "(visive)"
        }
        
        var verifiche: [String] = ["visive"]
        
        // Verifica presenza test strumentali
        let testStrumentaleTag = FileTagManager.FileTag.availableTags.first { $0.id == "test_strumentale" }
        if let tag = testStrumentaleTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            if !files.isEmpty {
                verifiche.append("strumentali")
            }
        }
        
        // Verifica presenza test funzionali
        let testFunzionaleTag = FileTagManager.FileTag.availableTags.first { $0.id == "foto_test_funzionale" }
        if let tag = testFunzionaleTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            if !files.isEmpty {
                verifiche.append("funzionali")
            }
        }
        
        return "(\(verifiche.joined(separator: ", ")))"
    }
    
    // MARK: - Helper Giustificativi
    
    /// Determina il testo corretto per giustificativi (fatture/preventivi) - per uso nella stima
    /// - Parameter sinistro: Sinistro da verificare
    /// - Returns: Testo appropriato con "presentati da parte dell'Assicurato" (es. "la fattura presentata da parte dell'Assicurato", "i giustificativi presentati da parte dell'Assicurato", "")
    @MainActor
    private func determinaTestoGiustificativi(sinistro: Sinistro) async -> String {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            return ""
        }
        
        // Verifica presenza fatture e preventivi
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        
        var numFatture = 0
        var numPreventivi = 0
        
        if let tag = fatturaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            numFatture = files.count
        }
        
        if let tag = preventivoTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            numPreventivi = files.count
        }
        
        // Determina il testo in base ai conteggi
        if numFatture > 0 && numPreventivi > 0 {
            // Entrambi presenti: usa "i giustificativi"
            return "i giustificativi presentati da parte dell'Assicurato"
        } else if numFatture > 0 {
            // Solo fatture
            return numFatture == 1 ? "la fattura presentata da parte dell'Assicurato" : "le fatture presentate da parte dell'Assicurato"
        } else if numPreventivi > 0 {
            // Solo preventivi
            return numPreventivi == 1 ? "il preventivo presentato da parte dell'Assicurato" : "i preventivi presentati da parte dell'Assicurato"
        } else {
            // Nessuno: stringa vuota
            return ""
        }
    }
    
    /// Determina il testo corretto per giustificativi acquisiti (fatture/preventivi) - per uso nella relazione documentale
    /// - Parameter sinistro: Sinistro da verificare
    /// - Returns: Testo appropriato (es. "ed la fattura di ripristino del danno", "ed i preventivi di ripristino del danno", "")
    @MainActor
    private func determinaTestoGiustificativiAcquisiti(sinistro: Sinistro) async -> String {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            return ""
        }
        
        // Verifica presenza fatture e preventivi
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        
        var numFatture = 0
        var numPreventivi = 0
        
        if let tag = fatturaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            numFatture = files.count
        }
        
        if let tag = preventivoTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            numPreventivi = files.count
        }
        
        // Se non ci sono giustificativi, ritorna stringa vuota
        guard numFatture > 0 || numPreventivi > 0 else {
            return ""
        }
        
        // Determina il testo in base ai conteggi
        if numFatture > 0 && numPreventivi > 0 {
            // Entrambi presenti: usa "i giustificativi"
            return "ed i giustificativi di ripristino del danno"
        } else if numFatture > 0 {
            // Solo fatture
            return numFatture == 1 ? "ed la fattura di ripristino del danno" : "ed le fatture di ripristino del danno"
        } else {
            // Solo preventivi
            return numPreventivi == 1 ? "ed il preventivo di ripristino del danno" : "ed i preventivi di ripristino del danno"
        }
    }
    
    /// Verifica se c'è almeno un preventivo
    /// - Parameter sinistro: Sinistro da verificare
    /// - Returns: true se c'è almeno un preventivo
    @MainActor
    private func verificaPresenzaPreventivo(sinistro: Sinistro) async -> Bool {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            return false
        }
        
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        guard let tag = preventivoTag else { return false }
        
        let files = await fileTagManager.getFilesWithTag(tag)
        return !files.isEmpty
    }
    
    /// Determina la frase sulle coassicurazioni
    /// - Parameter sinistro: Sinistro da verificare
    /// - Returns: Frase se coassicurazione è "no", altrimenti stringa vuota
    private func determinaFraseCoassicurazione(sinistro: Sinistro) -> String {
        // Se non ci sono coassicurazioni (array vuoto), significa coassicurazione = "no"
        if sinistro.coassicurazioniArray.isEmpty {
            return "Non ci risultano aperte altre posizioni di sinistro sui medesimi beni."
        }
        return ""
    }
    
    /// Determina la frase sul preventivo (allineato o eccedente)
    /// - Parameters:
    ///   - sinistro: Sinistro da verificare
    ///   - perizia: Perizia associata
    /// - Returns: Frase appropriata o stringa vuota
    private func determinaFrasePreventivo(sinistro: Sinistro, perizia: Perizia) -> String {
        // Verifica se c'è un preventivo
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else {
            return ""
        }
        
        // Verifica se tutti i beni hanno richiesta
        let tuttiBeni = perizia.partiteArray.flatMap { $0.beniArray }
        guard !tuttiBeni.isEmpty else { return "" }
        
        // Conta beni con richiesta
        let beniConRichiesta = tuttiBeni.filter { $0.richiesta != nil && ($0.richiesta?.doubleValue ?? 0) > 0 }
        
        // Se nessun bene ha richiesta o solo alcuni hanno richiesta, non scrivere nulla
        if beniConRichiesta.isEmpty || beniConRichiesta.count < tuttiBeni.count {
            return ""
        }
        
        // Calcola danno accertato lordo (prima di migliorie, illesi, deprezzamenti)
        let dannoAccertatoLordo = calcoliService.calcolaDannoAccertatoLordo(perizia: perizia)
        
        // Calcola richiesta totale
        let richiestaTotale = calcoliService.calcolaRichiestaTotale(perizia: perizia)
        
        // Se richiesta è zero, non scrivere nulla
        guard richiestaTotale > 0 else { return "" }
        
        // Verifica allineamento con margine del 15%
        let differenzaPercentuale = abs(dannoAccertatoLordo - richiestaTotale) / richiestaTotale
        
        if differenzaPercentuale <= 0.15 {
            // Allineato (entro il 15%)
            return ", risultando complessivamente allineata al preventivo fornito"
        } else {
            // Eccedente
            return ". La richiesta è stata ritenuta eccedente a quanto necessario al solo ripristino del danno"
        }
    }
    
    // MARK: - Generazione Analisi Tecnica
    
    /// Genera l'analisi tecnica dai beni della perizia
    /// - Parameters:
    ///   - perizia: Perizia da cui estrarre i beni
    ///   - escludiMisure: Se escludere valori numerici esatti
    /// - Returns: Testo dell'analisi tecnica
    func generaAnalisiTecnica(perizia: Perizia, escludiMisure: Bool = true) -> String {
        var analisi: [String] = []
        
        // Raccogli le relazioni tecniche di tutti i beni
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                if let relazione = bene.relazioneTecnica, !relazione.isEmpty {
                    var testoRelazione = relazione
                    
                    if escludiMisure {
                        testoRelazione = rimuoviMisureNumeriche(testoRelazione)
                    }
                    
                    let nomeBene = ArticoloGenereHelper.conArticolo(bene.nome)
                    analisi.append("Per quanto riguarda \(nomeBene): \(testoRelazione)")
                }
            }
        }
        
        return analisi.joined(separator: "\n\n")
    }
    
    // MARK: - Core Data Templates
    
    /// Carica template personalizzati dal database
    /// - Parameter tipoSinistro: Filtro per tipo sinistro (opzionale)
    /// - Returns: Array di template
    func caricaTemplatePersonalizzati(tipoSinistro: String? = nil) -> [RelazioneTemplate] {
        let fetch = NSFetchRequest<RelazioneTemplate>(entityName: "RelazioneTemplate")
        fetch.predicate = NSPredicate(format: "attivo == YES")
        fetch.sortDescriptors = [NSSortDescriptor(keyPath: \RelazioneTemplate.nome, ascending: true)]
        
        if let tipo = tipoSinistro {
            fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "attivo == YES"),
                NSPredicate(format: "tipoSinistro == %@ OR tipoSinistro == nil", tipo)
            ])
        }
        
        do {
            return try context.fetch(fetch)
        } catch {
            print("[RelazioneTemplateManager] Errore caricamento template: \(error)")
            return []
        }
    }
    
    /// Salva un nuovo template personalizzato
    /// - Parameters:
    ///   - nome: Nome del template
    ///   - contenuto: Contenuto del template
    ///   - tipoSinistro: Tipo sinistro (opzionale)
    /// - Returns: Template creato o nil se errore
    @discardableResult
    func salvaTemplate(nome: String, contenuto: String, tipoSinistro: String? = nil) -> RelazioneTemplate? {
        let template = RelazioneTemplate(context: context)
        template.id = UUID()
        template.nome = nome
        template.contenuto = contenuto
        template.tipoSinistro = tipoSinistro
        template.dataCreazione = Date()
        template.attivo = true
        
        do {
            try context.save()
            return template
        } catch {
            print("[RelazioneTemplateManager] Errore salvataggio template: \(error)")
            context.rollback()
            return nil
        }
    }
    
    // MARK: - Helpers Privati
    
    /// Genera una descrizione professionale dei beni dalle foto (per template documentale)
    /// Usa i dati già presenti nei beni (nome, marca, modello, anno) senza IA
    private func generaDescrizioneBeniDalleFoto(perizia: Perizia, beni: [String]) -> String {
        var componenti: [String] = []
        var danniVisibili: Set<String> = []
        
        // Raccogli informazioni dai beni (dati già presenti, non da IA)
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                var descrizioneComponente = ""
                
                // Costruisci descrizione componente: nome + marca + modello + anno (se disponibile)
                let nomeBene = bene.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Articolo appropriato per il nome
                let articolo = ArticoloGenereHelper.articoloDeterminativo(per: nomeBene)
                let nomeConArticolo = ArticoloGenereHelper.conArticolo(nomeBene)
                
                // Aggiungi marca se disponibile
                var descrizioneDettaglio = ""
                if let marca = bene.marca?.trimmingCharacters(in: .whitespacesAndNewlines), !marca.isEmpty {
                    descrizioneDettaglio = marca
                }
                
                // Aggiungi modello se disponibile
                if let modello = bene.modello?.trimmingCharacters(in: .whitespacesAndNewlines), !modello.isEmpty {
                    if !descrizioneDettaglio.isEmpty {
                        descrizioneDettaglio += " \(modello)"
                    } else {
                        descrizioneDettaglio = modello
                    }
                }
                
                // Costruisci componente completo
                if !descrizioneDettaglio.isEmpty {
                    descrizioneComponente = "\(nomeConArticolo) \(descrizioneDettaglio)"
                } else {
                    descrizioneComponente = nomeConArticolo
                }
                
                // Aggiungi anno se disponibile e significativo
                if bene.anno > 0 && bene.anno < 3000 {
                    descrizioneComponente += " del \(bene.anno)"
                }
                
                if !descrizioneComponente.isEmpty {
                    componenti.append(descrizioneComponente)
                }
                
                // Estrai danni visibili dalla relazione tecnica se presente
                // (dati già inseriti manualmente, non da IA)
                if let relazione = bene.relazioneTecnica, !relazione.isEmpty {
                    let relazioneLower = relazione.lowercased()
                    if relazioneLower.contains("annerimento") || relazioneLower.contains("scottatura") || relazioneLower.contains("bruciato") {
                        danniVisibili.insert("annerimenti")
                    }
                    if relazioneLower.contains("stress elettrico") || relazioneLower.contains("sovratensione") || relazioneLower.contains("sovracorrente") {
                        danniVisibili.insert("segni compatibili con stress elettrico")
                    }
                    if relazioneLower.contains("scoppio") || relazioneLower.contains("esploso") {
                        danniVisibili.insert("danni da sovratensione")
                    }
                }
            }
        }
        
        // Costruisci la descrizione professionale
        if !componenti.isEmpty {
            var descrizione = "Le foto mostrano "
            
            if componenti.count == 1 {
                descrizione += componenti[0]
            } else if componenti.count == 2 {
                descrizione += "\(componenti[0]) e \(componenti[1])"
            } else {
                let tuttiTranneUltimo = componenti.dropLast().joined(separator: ", ")
                descrizione += "\(tuttiTranneUltimo) e \(componenti.last!)"
            }
            
            // Aggiungi danni visibili se presenti
            if !danniVisibili.isEmpty {
                descrizione += ". "
                let danniArray = Array(danniVisibili)
                let danniTesto = danniArray.count == 1 ? danniArray[0] : danniArray.dropLast().joined(separator: ", ") + " e \(danniArray.last!)"
                
                if componenti.count == 1 {
                    descrizione += "Il bene presenta \(danniTesto)."
                } else {
                    descrizione += "Alcuni componenti presentano \(danniTesto)."
                }
            } else {
                descrizione += "."
            }
            
            return descrizione
        }
        
        // Fallback se non ci sono beni con dati
        let fraseBeni = ArticoloGenereHelper.fraseBeniLamentatiDanneggiati(beni)
        return "Le foto mostrano \(fraseBeni)."
    }
    
    private func determinaStatoBeni(perizia: Perizia) -> String {
        // In una relazione conclusiva, le verifiche sono già state fatte
        // Non serve dire che i beni sono "disponibili per le verifiche"
        // Ritorna stringa vuota per stato standard (verifiche completate)
        let mantenimento = perizia.mantenimentoResidui?.lowercased() ?? "si"
        
        switch mantenimento {
        case "no":
            return "risulta essere stato sostituito/riparato senza attendere le verifiche peritali"
        case "parziali":
            return "risulta essere stato parzialmente sostituito/riparato"
        default:
            // Stato standard: verifiche completate, non serve specificarlo
            return ""
        }
    }
    
    /// Rimuove valori numerici esatti (ohm, volt, megaohm, ecc.)
    private func rimuoviMisureNumeriche(_ testo: String) -> String {
        var risultato = testo
        
        // Pattern per misure comuni
        let patterns = [
            #"\d+[\.,]?\d*\s*(ohm|Ohm|Ω)"#,           // Ohm
            #"\d+[\.,]?\d*\s*(megaohm|MΩ|MOhm)"#,    // Megaohm
            #"\d+[\.,]?\d*\s*(volt|V|v)"#,            // Volt
            #"\d+[\.,]?\d*\s*(ampere|A|amp)"#,        // Ampere
            #"\d+[\.,]?\d*\s*(watt|W)"#,              // Watt
            #"\d+[\.,]?\d*\s*(kW|kilowatt)"#,         // Kilowatt
            #"\d+[\.,]?\d*\s*(mA|milliampere)"#       // Milliampere
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                risultato = regex.stringByReplacingMatches(
                    in: risultato,
                    range: NSRange(risultato.startIndex..., in: risultato),
                    withTemplate: "[valore nella norma]"
                )
            }
        }
        
        // Rimuovi ripetizioni di placeholder
        risultato = risultato.replacingOccurrences(of: "[valore nella norma] [valore nella norma]", with: "[valori nella norma]")
        
        return risultato
    }
    
    private func pulisciTesto(_ testo: String) -> String {
        var risultato = testo
        
        // Rimuovi righe vuote multiple
        while risultato.contains("\n\n\n") {
            risultato = risultato.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        // Rimuovi spazi multipli
        while risultato.contains("  ") {
            risultato = risultato.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Trim
        risultato = risultato.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return risultato
    }
}
