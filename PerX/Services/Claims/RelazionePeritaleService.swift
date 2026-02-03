import Foundation
import CoreData

/// Servizio principale per la generazione automatica delle frasi della relazione peritale
class RelazionePeritaleService {
    static let shared = RelazionePeritaleService()
    
    private let templateManager = RelazioneTemplateManager.shared
    private let diarioExtractor = DiarioExtractorService.shared
    private let calcoliService = CalcoliService.shared
    
    // MARK: - Limiti caratteri
    
    static let limiteRelazionePerizia = 1500
    static let limiteRiserve = 500
    static let limiteOsservazioni = 500
    static let limiteNoteConclusive = 1000
    
    private init() {}
    
    // MARK: - Determinazione
    
    /// Opzioni disponibili per la determinazione
    static let opzioniDeterminazione: [String] = [
        "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con BONIFICO BANCARIO",
        "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con ASSEGNO",
        "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE (Non liquidabile dallo Studio peritale)",
        "CONCORDATO VERBALMENTE con BONIFICO BANCARIO",
        "CONCORDATO VERBALMENTE con ASSEGNO",
        "CONCORDATO VERBALMENTE (Non liquidabile dallo Studio peritale)",
        "CONCORDATO CON ATTO DI ACCERTAMENTO DI DANNO",
        "CONCORDATO CON ATTO DI ACCERTAMENTO CON RISERVA",
        "NON CONCORDATO (ved. NOTE)",
        "NON CONCORDATO (NO Fenomeno elettrico)",
        "NON CONCORDATO (NO residui)",
        "NON CONCORDATO (Sotto franchigia)",
        "NON CONCORDATO (Garanzie non operanti)",
        "NON CONCORDATO (Danno indennizzabile ma stima non concordata)",
        "NON CONCORDATO (Ubicazione del sinistro non assicurata)"
    ]
    
    /// Deriva la determinazione dal campo definizione del sinistro
    func derivaDeterminazione(da sinistro: Sinistro) -> String? {
        guard let definizione = sinistro.definizione?.uppercased() else { return nil }
        
        // Cerca corrispondenza esatta (case insensitive)
        if let esatta = Self.opzioniDeterminazione.first(where: { $0.uppercased() == definizione }) {
            return esatta
        }
        
        // Fallback su logica fuzzy
        if definizione.contains("VERBALE") || definizione.contains("VERBALMENTE") {
            if definizione.contains("BONIFICO") { return "CONCORDATO VERBALMENTE con BONIFICO BANCARIO" }
            if definizione.contains("ASSEGNO") { return "CONCORDATO VERBALMENTE con ASSEGNO" }
            return "CONCORDATO VERBALMENTE con BONIFICO BANCARIO"
        }
        
        if definizione.contains("ACCERTAMENTO") {
            if definizione.contains("RISERVA") { return "CONCORDATO CON ATTO DI ACCERTAMENTO CON RISERVA" }
            return "CONCORDATO CON ATTO DI ACCERTAMENTO DI DANNO"
        }
        
        if definizione.contains("NO FENOMENO") || definizione.contains("NON FENOMENO") {
            return "NON CONCORDATO (NO Fenomeno elettrico)"
        }
        
        if definizione.contains("NO RESIDUI") || definizione.contains("SENZA RESIDUI") {
            return "NON CONCORDATO (NO residui)"
        }
        
        if definizione.contains("SOTTO FRANCHIGIA") || definizione.contains("FRANCHIGIA") {
            return "NON CONCORDATO (Sotto franchigia)"
        }
        
        if definizione.contains("GARANZIE NON OPERANTI") || definizione.contains("GARANZIA NON OPERANTE") {
            return "NON CONCORDATO (Garanzie non operanti)"
        }
        
        if definizione.contains("UBICAZIONE") && definizione.contains("NON ASSICURATA") {
            return "NON CONCORDATO (Ubicazione del sinistro non assicurata)"
        }
        
        if definizione.contains("DANNO INDENNIZZABILE") && definizione.contains("NON CONCORDATA") {
            return "NON CONCORDATO (Danno indennizzabile ma stima non concordata)"
        }
        
        if definizione.contains("VED. NOTE") || definizione.contains("VEDI NOTE") {
            return "NON CONCORDATO (ved. NOTE)"
        }
        
        if definizione.contains("CONCORDAT") && !definizione.contains("NON") {
            if definizione.contains("BONIFICO") { return "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con BONIFICO BANCARIO" }
            if definizione.contains("ASSEGNO") { return "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con ASSEGNO" }
            return "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con BONIFICO BANCARIO"
        }
        
        return nil
    }
    
    // MARK: - Evento Causato Da
    
    /// Genera il valore di default per "Evento causato da"
    /// - Parameter sinistro: Il sinistro
    /// - Returns: "Fenomeno Elettrico" se ha liquidazione, vuoto altrimenti
    func generaEventoCausatoDa(sinistro: Sinistro, perizia: Perizia?) -> String {
        if sinistro.haLiquidazione {
            return "Fenomeno Elettrico"
        }
        return ""
    }
    
    // MARK: - Relazione Peritale
    
    /// Genera la relazione peritale completa
    /// - Parameters:
    ///   - sinistro: Il sinistro
    ///   - perizia: La perizia associata
    /// - Returns: Testo della relazione (max 1500 caratteri)
    @MainActor
    func generaRelazionePeritale(sinistro: Sinistro, perizia: Perizia) async -> String {
        // Controlla se esiste analisi Perxia
        if let perxiaRelazione = cercaRelazionePerxia(sinistro: sinistro), !perxiaRelazione.isEmpty {
            // Arricchisci con dati attuali e tronca se necessario
            let arricchita = arricchisciRelazione(perxiaRelazione, sinistro: sinistro, perizia: perizia)
            return troncaConCoerenza(arricchita, limite: Self.limiteRelazionePerizia)
        }
        
        // Altrimenti usa template base
        let nomiBeni = estraiNomiBeni(da: perizia)
        let fePositivo = determinaCompatibilitaFE(sinistro: sinistro, perizia: perizia)
        
        // Verifica se ci sono fulminazioni rilevate da METEOCAST
        let haFulminazioni = sinistro.fulminazione != nil && !sinistro.fulminazione!.isEmpty
        
        let template = templateManager.selezionaTemplate(
            sopralluogo: sinistro.sopralluogo,
            mantenimentoResidui: perizia.mantenimentoResidui,
            fePositivo: fePositivo,
            haFulminazioni: haFulminazioni
        )
        
        let analisiTecnica = templateManager.generaAnalisiTecnica(perizia: perizia, escludiMisure: true)
        
        var relazione = await templateManager.personalizzaTemplate(
            template,
            sinistro: sinistro,
            perizia: perizia,
            beni: nomiBeni,
            analisiTecnica: analisiTecnica
        )
        
        // Arricchisci con comunicazioni dal diario
        relazione = arricchisciRelazione(relazione, sinistro: sinistro, perizia: perizia)
        
        return troncaConCoerenza(relazione, limite: Self.limiteRelazionePerizia)
    }
    
    // MARK: - Note Conclusive
    
    /// Genera le note conclusive (3 blocchi)
    /// - Parameters:
    ///   - sinistro: Il sinistro
    ///   - perizia: La perizia
    /// - Returns: Testo delle note conclusive
    func generaNoteConclusive(sinistro: Sinistro, perizia: Perizia) -> String {
        var blocchi: [String] = []
        
        // BLOCCO 1: IVA e Ripristini (sempre presente)
        let blocco1 = generaBloccoIVARipristini(sinistro: sinistro, perizia: perizia)
        blocchi.append(blocco1)
        
        // BLOCCO 2: In base alla determinazione
        if let blocco2 = generaBloccoDeterminazione(sinistro: sinistro, perizia: perizia) {
            blocchi.append(blocco2)
        }
        
        // BLOCCO 3: METEOCAST (solo Generali e Zurich)
        if let blocco3 = generaBloccoMETEOCAST(sinistro: sinistro) {
            blocchi.append(blocco3)
        }
        
        return blocchi.joined(separator: "\n\n")
    }
    
    // MARK: - Riserve
    
    /// Genera le riserve automaticamente in base ai dati
    /// - Parameters:
    ///   - sinistro: Il sinistro
    ///   - perizia: La perizia
    /// - Returns: Array di frasi di riserva
    func generaRiserve(sinistro: Sinistro, perizia: Perizia) -> [String] {
        var riserve: [String] = []
        let importoAtto = calcolaImportoAtto(perizia: perizia)
        let prefisso = importoAtto > 0 ? "Il perito eleva riserva a favore della propria Mandante in quanto " : ""
        
        // 1. No residui
        if perizia.mantenimentoResidui?.lowercased() == "no" {
            let frase = prefisso + "l'Assicurato non ha mantenuto i residui del sinistro."
            riserve.append(capitalizzaPrima(frase))
        }
        
        // 2. Partita non acquistata
        for partita in perizia.partiteArray {
            if !partita.partitaAcquistata {
                let nomePartita = partita.nomeEditabile
                let frase = prefisso + "il bene oggetto del sinistro rientra nella definizione di \(nomePartita), che non risulta acquistata sulla Polizza in oggetto."
                riserve.append(capitalizzaPrima(frase))
            }
        }
        
        // 3. Denuncia tardiva + no residui
        if perizia.denunciaTardiva && perizia.mantenimentoResidui?.lowercased() == "no" {
            let frase = prefisso + "l'Assicurato non ha adempiuto agli obblighi contrattuali relativi alla tempistica della denuncia e non ha mantenuto i residui del sinistro."
            // Evita duplicati
            if !riserve.contains(where: { $0.contains("tempistica della denuncia") }) {
                riserve.append(capitalizzaPrima(frase))
            }
        }
        
        // Combina e tronca
        let testoCompleto = riserve.joined(separator: "\n")
        if testoCompleto.count > Self.limiteRiserve {
            return [troncaConCoerenza(testoCompleto, limite: Self.limiteRiserve)]
        }
        
        return riserve
    }
    
    /// Genera frasi di riserva predefinite (per pulsanti manuali)
    static let fraseRiservaFENonSottoscritta = "la Garanzia Fenomeno elettrico non risulta sottoscritta nel contratto di Polizza."
    static let fraseRiservaNoFEConCauseEsterne = "non sono emersi elementi per poter ricondurre il lamentato danno ad un fenomeno elettrico con il concorso di cause esterne."
    static let fraseRiservaNoFE = "non sono emersi danni riconducibili alle condizioni della Garanzia Fenomeno elettrico."
    
    /// Formatta una frase di riserva con o senza prefisso in base all'importo
    func formattaFraseRiserva(_ frase: String, importoAtto: Double) -> String {
        let prefisso = importoAtto > 0 ? "Il perito eleva riserva a favore della propria Mandante in quanto " : ""
        return capitalizzaPrima(prefisso + frase)
    }
    
    // MARK: - Osservazioni
    
    /// Genera le osservazioni automaticamente
    /// - Parameters:
    ///   - sinistro: Il sinistro
    ///   - perizia: La perizia
    /// - Returns: Array di osservazioni
    func generaOsservazioni(sinistro: Sinistro, perizia: Perizia) -> [String] {
        var osservazioni: [String] = []
        
        // 1. Sotto franchigia
        let determinazione = perizia.determinazione ?? derivaDeterminazione(da: sinistro) ?? ""
        if determinazione.lowercased().contains("sotto franchigia") {
            let franchigia = calcolaFranchigia(perizia: perizia)
            if franchigia > 0 {
                let importoFormattato = formattaImportoEuro(franchigia)
                osservazioni.append("Il danno risulta interamente assorbito dalla franchigia contrattuale di € \(importoFormattato).")
            }
        }
        
        // 2. Supplemento indennizzo (SI non in liquidazione)
        if let ossSI = generaOsservazioneSI(sinistro: sinistro, perizia: perizia) {
            osservazioni.append(ossSI)
        }
        
        // 3. Atto precedente
        if sinistro.dataInvioAtto != nil {
            osservazioni.append("Il presente atto viene emesso a conclusione della perizia contrattuale ed ANNULLA e SOSTITUISCE qualsiasi altro precedente.")
        }
        
        // Combina e tronca
        let testoCompleto = osservazioni.joined(separator: "\n")
        if testoCompleto.count > Self.limiteOsservazioni {
            return [troncaConCoerenza(testoCompleto, limite: Self.limiteOsservazioni)]
        }
        
        return osservazioni
    }
    
    // MARK: - Helpers Privati
    
    private func cercaRelazionePerxia(sinistro: Sinistro) -> String? {
        if let ultimaAnalisi = sinistro.perxiaAnalisiArray.first,
           let relazione = ultimaAnalisi.relazioneComplessiva,
           !relazione.isEmpty {
            return relazione
        }
        return nil
    }
    
    private func arricchisciRelazione(_ relazione: String, sinistro: Sinistro, perizia: Perizia) -> String {
        // Non aggiungere comunicazioni dal diario - sono relazioni professionali, non devono contenere
        // riferimenti a comunicazioni interne o assegnazioni
        return relazione
    }
    
    private func estraiNomiBeni(da perizia: Perizia) -> [String] {
        var nomi: [String] = []
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                nomi.append(bene.nome)
            }
        }
        return nomi
    }
    
    private func determinaCompatibilitaFE(sinistro: Sinistro, perizia: Perizia) -> Bool? {
        // Cerca nell'analisi Perxia
        if let ultimaAnalisi = sinistro.perxiaAnalisiArray.first {
            for bene in ultimaAnalisi.beniArray {
                if let compatibilita = bene.compatibilitaGaranzia?.lowercased() {
                    if compatibilita.contains("compatibile") || compatibilita.contains("positiv") {
                        return true
                    }
                    if compatibilita.contains("non compatibile") || compatibilita.contains("negativ") {
                        return false
                    }
                }
            }
        }
        
        // Fallback: usa definizione sinistro
        if let def = sinistro.definizione?.lowercased() {
            if def.contains("no fenomeno") || def.contains("non fenomeno") {
                return false
            }
            if sinistro.haLiquidazione {
                return true
            }
        }
        
        return nil // Non determinato
    }
    
    private func generaBloccoIVARipristini(sinistro: Sinistro, perizia: Perizia) -> String {
        var parti: [String] = []
        
        // Analizza IVA dei beni
        let ivaStatus = analizzaIVABeni(perizia: perizia)
        let ivaFrase: String
        switch ivaStatus {
        case .tuttiInclusa:
            ivaFrase = "IVA inclusa"
        case .tuttiEsclusa:
            ivaFrase = "IVA esclusa"
        case .misto:
            ivaFrase = "IVA parzialmente inclusa"
        }
        
        parti.append("Gli importi a stima del danno sono da considerarsi \(ivaFrase).")
        
        // Analizza ripristini (basato solo su ripristiniUltimati dei beni)
        let ripristiniStatus = analizzaRipristiniBeni(perizia: perizia)
        
        let ripristiniFrase: String
        switch ripristiniStatus {
        case .tuttiUltimati:
            ripristiniFrase = "I ripristini risultano già stati effettuati."
        case .parziali:
            ripristiniFrase = "I ripristini risultano parzialmente effettuati."
        case .nessunoUltimato:
            ripristiniFrase = "I ripristini risultano non ancora effettuati."
        }
        
        parti.append(ripristiniFrase)
        
        return parti.joined(separator: " ")
    }
    
    private func generaBloccoDeterminazione(sinistro: Sinistro, perizia: Perizia) -> String? {
        let determinazione = perizia.determinazione ?? derivaDeterminazione(da: sinistro) ?? ""
        let detLower = determinazione.lowercased()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        // Concordata con atto firmato
        if detLower.contains("bonifico") || detLower.contains("assegno") || (detLower.contains("concordat") && !detLower.contains("verbal") && !detLower.contains("riserva")) {
            let dataComunicazione = sinistro.dataComunicazioneEsito ?? sinistro.dataInvioAtto ?? Date()
            let dataRitorno = sinistro.dataRicezioneAttoSottoscritto ?? sinistro.dataRitornoAtto ?? Date()
            
            return """
            In data \(dateFormatter.string(from: dataComunicazione)) abbiamo comunicato l'esito degli accertamenti peritali all'Assicurato al quale è stato inviato a mezzo email l'atto di accertamento di danno da noi predisposto. Tale atto è tornato sottoscritto in data \(dateFormatter.string(from: dataRitorno)).
            """
        }
        
        // Concordata verbalmente
        if detLower.contains("verbal") {
            let dataAccettazione = sinistro.dataAccettazioneVerbale ?? Date()
            return """
            Come da accordo con il liquidatore procediamo alla pronta definizione avendo concordato il danno verbalmente con l'Assicurato in data \(dateFormatter.string(from: dataAccettazione)).
            """
        }
        
        // Non concordato e non paghiamo
        if detLower.contains("non concordat") && !detLower.contains("danno indennizzabile") {
            let dataComunicazione = sinistro.dataComunicazioneEsito ?? sinistro.dataInvioAtto ?? Date()
            return """
            In data \(dateFormatter.string(from: dataComunicazione)) abbiamo comunicato l'esito degli accertamenti peritali all'Assicurato al quale è stato inviato a mezzo email l'atto di liquidazione amichevole di danno da noi predisposto. Non abbiamo ritenuto necessario attenderne la restituzione.
            """
        }
        
        // Danno indennizzabile ma stima non concordata
        if detLower.contains("danno indennizzabile") {
            let dataComunicazione = sinistro.dataComunicazioneEsito ?? sinistro.dataInvioAtto ?? Date()
            var frase = """
            Teniamo ad evidenziare che in data \(dateFormatter.string(from: dataComunicazione)) abbiamo provveduto a comunicare l'esito peritale all'Assicurato che, nonostante le spiegazioni fornite, non ha inteso accettare l'importo di liquidazione amichevole proposto
            """
            
            // Aggiungi ragioni dal diario se disponibili
            if let ragioni = diarioExtractor.estraiRagioniRifiuto(da: sinistro) {
                frase += " (\(ragioni))"
            }
            frase += "."
            
            // Aggiungi comunicazione agenzia se presente
            if let dataAgenzia = diarioExtractor.cercaDataComunicazioneAgenzia(da: sinistro) {
                frase += " Abbiamo del fatto informato l'Agenzia che, in data \(dateFormatter.string(from: dataAgenzia)), ci ha confermato che l'Assicurato non intende accettare l'esito peritale."
            }
            
            return frase
        }
        
        return nil
    }
    
    private func generaBloccoMETEOCAST(sinistro: Sinistro) -> String? {
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        let gruppo = compagnia.gruppo
        
        if gruppo == .generali || gruppo == .zurich {
            return "Precisiamo che abbiamo effettuato la perizia in modalità documentale e utilizzato il portale METEOCAST per verificare la presenza di fulminazioni."
        }
        
        return nil
    }
    
    private func generaOsservazioneSI(sinistro: Sinistro, perizia: Perizia) -> String? {
        // Verifica se c'è divisione SI/VSU con SI non liquidato
        guard sinistro.haDivisioneSIVSU else { return nil }
        
        // Calcola SI totale
        var totaleSI: Double = 0
        var haIVASuSI = false
        
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                let determinazione = bene.determinazioneDannoEffettiva
                if determinazione.contains("SI") {
                    for voce in bene.vociCostoArray where voce.indennizzabile {
                        if let si = voce.si {
                            totaleSI += si.doubleValue
                        }
                    }
                    // Verifica IVA
                    if !bene.ivaInclusa && bene.ripristiniUltimati == false {
                        haIVASuSI = true
                    }
                }
            }
        }
        
        guard totaleSI > 0 else { return nil }
        
        // Verifica se SI è già in liquidazione (ripristini ultimati)
        var ripristiniTuttiUltimati = true
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                if !bene.ripristiniUltimati {
                    ripristiniTuttiUltimati = false
                    break
                }
            }
        }
        
        // Se ripristini ultimati, SI è già incluso nella liquidazione
        if ripristiniTuttiUltimati {
            return nil
        }
        
        let importoNumeri = formattaImportoEuro(totaleSI)
        let importoLettere = numeroInLettere(totaleSI)
        
        var frase = "Il suddetto importo sarà integrato fino ad un ulteriore importo pari a euro \(importoNumeri) (\(importoLettere)/00)"
        
        if haIVASuSI {
            let aliquotaIVA = 22.0 // Default
            let ivaImporto = totaleSI * aliquotaIVA / 100
            let ivaNumeri = formattaImportoEuro(ivaImporto)
            let ivaLettere = numeroInLettere(ivaImporto)
            frase += " più iva (€ \(ivaNumeri) (\(ivaLettere)/00))"
        }
        
        frase += " sul danno stimato totale, a titolo di \"supplemento di indennizzo\", erogabile dietro presentazione di fattura entro il termine previsto dalla polizza."
        
        return frase
    }
    
    // MARK: - Calcoli
    
    private func calcolaImportoAtto(perizia: Perizia) -> Double {
        var totale: Double = 0
        
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                if let forzato = bene.liquidazioneForzata {
                    totale += forzato.doubleValue
                } else {
                    for voce in bene.vociCostoArray where voce.indennizzabile {
                        if let vsu = voce.vsu { totale += vsu.doubleValue }
                        if let si = voce.si { totale += si.doubleValue }
                    }
                }
            }
        }
        
        return totale
    }
    
    private func calcolaFranchigia(perizia: Perizia) -> Double {
        guard let garanzia = perizia.garanzieArray.first else { return 0 }
        return garanzia.franchigiaMinimo?.doubleValue ?? 0
    }
    
    // MARK: - Analisi Beni
    
    enum StatusIVA { case tuttiInclusa, tuttiEsclusa, misto }
    enum StatusRipristini { case tuttiUltimati, parziali, nessunoUltimato }
    
    private func analizzaIVABeni(perizia: Perizia) -> StatusIVA {
        var haBeni = false
        var tuttiInclusa = true
        var tuttiEsclusa = true
        
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                haBeni = true
                if bene.ivaInclusa {
                    tuttiEsclusa = false
                } else {
                    tuttiInclusa = false
                }
            }
        }
        
        // Se non ci sono beni, default è esclusa
        if !haBeni {
            return .tuttiEsclusa
        }
        
        if tuttiInclusa { return .tuttiInclusa }
        if tuttiEsclusa { return .tuttiEsclusa }
        return .misto
    }
    
    private func analizzaRipristiniBeni(perizia: Perizia) -> StatusRipristini {
        var tuttiUltimati = true
        var almenoUnoUltimato = false
        
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                if bene.ripristiniUltimati {
                    almenoUnoUltimato = true
                } else {
                    tuttiUltimati = false
                }
            }
        }
        
        if tuttiUltimati { return .tuttiUltimati }
        if almenoUnoUltimato { return .parziali }
        return .nessunoUltimato
    }
    
    // MARK: - Formattazione
    
    private func formattaImportoEuro(_ importo: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "it_IT")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: importo)) ?? String(format: "%.2f", importo)
    }
    
    private func numeroInLettere(_ numero: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "it_IT")
        let parteIntera = Int(numero)
        return formatter.string(from: NSNumber(value: parteIntera)) ?? "\(parteIntera)"
    }
    
    private func capitalizzaPrima(_ stringa: String) -> String {
        guard let primo = stringa.first else { return stringa }
        return primo.uppercased() + stringa.dropFirst()
    }
    
    private func troncaConCoerenza(_ testo: String, limite: Int) -> String {
        guard testo.count > limite else { return testo }
        
        // Cerca l'ultimo punto prima del limite
        let indiceLimite = testo.index(testo.startIndex, offsetBy: limite - 3) // Spazio per "..."
        let sottotesto = String(testo[..<indiceLimite])
        
        if let ultimoPunto = sottotesto.lastIndex(of: ".") {
            return String(sottotesto[...ultimoPunto])
        }
        
        // Fallback: tronca all'ultimo spazio
        if let ultimoSpazio = sottotesto.lastIndex(of: " ") {
            return String(sottotesto[..<ultimoSpazio]) + "..."
        }
        
        return sottotesto + "..."
    }
}
