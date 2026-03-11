// Fix: Removed duplicate @objc(Sinistro) class declaration to resolve redeclaration error.

import CoreData

// MARK: - Ciclo Controllo

/// Rappresenta un ciclo di controllo/autorizzazione di un sinistro
/// Supporta più cicli per lo stesso sinistro (es. controllo pre invio atto, supervisione non concordata)
struct CicloControllo: Codable, Identifiable {
    let id: UUID
    let dataEntrata: Date
    var tipoEntrata: TipoControllo  // var per consentire aggiornamento del tipo durante il ciclo
    var dataUscita: Date?
    var tipoUscita: TipoUscitaControllo?
    
    enum TipoControllo: String, Codable {
        case inControllo = "In controllo"
        case richiestaAutorizzazione = "Richiesta autorizzazione"
        case supervisioneNonConcordata = "Supervisione non concordata"
    }
    
    enum TipoUscitaControllo: String, Codable {
        case controllata = "Controllata"
        case chiusa = "Chiusa"
        case attoInviato = "Atto inviato"
        case esitoComunicato = "Esito comunicato"
        case inGestione = "In gestione"
        case altro = "Altro"
    }
    
    init(dataEntrata: Date = Date(), tipoEntrata: TipoControllo) {
        self.id = UUID()
        self.dataEntrata = dataEntrata
        self.tipoEntrata = tipoEntrata
        self.dataUscita = nil
        self.tipoUscita = nil
    }
    
    /// Indica se il ciclo è ancora aperto (sinistro ancora in controllo)
    var isAperto: Bool {
        dataUscita == nil
    }
    
    /// Durata del ciclo in giorni (nil se ancora aperto)
    var durataTotaleGiorni: Int? {
        guard let uscita = dataUscita else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: dataEntrata, to: uscita).day
    }
    
    /// Durata in giorni lavorativi (nil se ancora aperto)
    var durataGiorniLavorativi: Int? {
        guard let uscita = dataUscita else { return nil }
        return ItalianCalendarService.shared.getWorkingDaysBetween(from: dataEntrata, to: uscita)
    }
}

@objc(Sinistro)
public class Sinistro: NSManagedObject, Identifiable {
    
    // MARK: - Normalizzazione Campi
    
    /// Normalizza i campi testuali prima del salvataggio
    /// - Title Case: agenzia, nomeCompagnia, gruppo, nomeAssicurato, nomeContraente, nomeDanneggiato
    /// - UPPERCASE: codiceAgenzia, partitaIVAAssicurato, codiceFiscaleAssicurato, area
    public override func willSave() {
        super.willSave()
        
        // Evita loop infiniti: normalizza solo se ci sono cambiamenti effettivi
        guard hasChanges else { return }
        
        // Title Case: solo iniziali maiuscole
        normalizzaCampoTitleCase(forKey: "agenzia")
        normalizzaCampoTitleCase(forKey: "nomeCompagnia")
        normalizzaCampoTitleCase(forKey: "gruppo")
        normalizzaCampoTitleCase(forKey: "nomeAssicurato")
        normalizzaCampoTitleCase(forKey: "nomeContraente")
        normalizzaCampoTitleCase(forKey: "nomeDanneggiato")
        
        // UPPERCASE: tutto maiuscolo
        normalizzaCampoUppercase(forKey: "codiceAgenzia")
        normalizzaCampoUppercase(forKey: "partitaIVAAssicurato")
        normalizzaCampoUppercase(forKey: "codiceFiscaleAssicurato")
        normalizzaCampoUppercase(forKey: "area")
    }
    
    /// Converte una stringa in Title Case (ogni parola con iniziale maiuscola)
    /// Usa setPrimitiveValue per evitare loop infiniti in willSave
    private func normalizzaCampoTitleCase(forKey key: String) {
        guard let valore = primitiveValue(forKey: key) as? String, !valore.isEmpty else { return }
        // Converte ogni parola con iniziale maiuscola e resto minuscolo
        let normalizzato = valore
            .lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        if normalizzato != valore {
            setPrimitiveValue(normalizzato, forKey: key)
        }
    }
    
    /// Converte una stringa in UPPERCASE
    /// Usa setPrimitiveValue per evitare loop infiniti in willSave
    private func normalizzaCampoUppercase(forKey key: String) {
        guard let valore = primitiveValue(forKey: key) as? String, !valore.isEmpty else { return }
        let normalizzato = valore.uppercased()
        if normalizzato != valore {
            setPrimitiveValue(normalizzato, forKey: key)
        }
    }
    
    // --- Campi Legacy (da deprecare ma mantenuti per la migrazione) ---
    @NSManaged public var nomeAssicurato_legacy: String?
    @NSManaged public var telefonoAssicurato_legacy: String?
    @NSManaged public var emailAssicurato_legacy: String?
    @NSManaged public var indirizzoAssicurato_legacy: String?
    // --- Fine Campi Legacy ---
    
    // --- Proprietà per gli attori ---
    @NSManaged public var nomeContraente: String?
    @NSManaged public var telefonoContraente: String?
    @NSManaged public var emailContraente: String?
    @NSManaged public var indirizzoContraente: String?
    
    @NSManaged public var nomeAssicurato: String?
    @NSManaged public var telefonoAssicurato: String?
    @NSManaged public var emailAssicurato: String?
    @NSManaged public var indirizzoAssicurato: String?
    @NSManaged private var telefoniAssicurato: NSObject?
    @NSManaged private var emailAssicuratoArrayStorage: NSObject?
    
    @NSManaged public var nomeDanneggiato: String?
    @NSManaged public var telefonoDanneggiato: String?
    @NSManaged public var emailDanneggiato: String?
    @NSManaged public var indirizzoDanneggiato: String?
    // --- Fine Proprietà per gli attori ---
    
    @NSManaged public var riferimento: String?
    
    // MARK: - Assegnazione / owner (multi-utente)
    @NSManaged public var ownerEmail: String?
    @NSManaged public var assignedToUserEmail: String?
    @NSManaged public var assignedToUserName: String?
    
    // MARK: - CloudKit metadata
    @NSManaged public var cloudKitRecordID: String?
    @NSManaged public var cloudKitLastModified: Date?
    
    // MARK: - Sottostato
    @NSManaged public var substate: String?

    @NSManaged public var stato: String?
    @NSManaged public var dataAperturaGestione: Date?
    @NSManaged public var dataAssegnazione: Date?
    @NSManaged public var dataInvioAtto: Date?
    @NSManaged public var dataChiusura: Date?
    @NSManaged public var dataRevoca: Date?
    @NSManaged public var dataRitornoAtto: Date? // Data ritorno atto (legacy)
    @NSManaged public var dataComunicazioneEsito: Date? // Data comunicazione esito all'assicurato
    @NSManaged public var dataRicezioneAttoSottoscritto: Date? // Data ricezione atto sottoscritto (nuovo, preferire questo)
    @NSManaged public var dataAccettazioneVerbale: Date? // Data accettazione verbale
    @NSManaged public var numeroSinistroCompagnia: String?
    @NSManaged public var codiceAgenzia: String?
    @NSManaged public var richiesta: NSDecimalNumber?
    @NSManaged public var liquidato: NSDecimalNumber?
    @NSManaged public var iban: Bool
    @NSManaged public var sinistroCollegato: Bool
    @NSManaged public var idSinistroCollegato: String?
    @NSManaged public var agenzia: String?
    @NSManaged public var emailAgenzia: String?
    @NSManaged public var telefonoAgenzia: String?
    @NSManaged public var subagenzia: String?
    @NSManaged public var dannoAccertato: NSDecimalNumber?
    @NSManaged public var oltreDieciBeni: Bool
    @NSManaged public var nomeCompagnia: String?
    @NSManaged public var collegamenti: NSObject?
    @NSManaged private var diarioEntries: NSObject?
    @NSManaged public var sopralluogo: Bool
    @NSManaged public var giustificativi: Bool
    @NSManaged public var dataSinistro: Date?
    @NSManaged public var dannoAccertatoNetto: NSDecimalNumber?
    @NSManaged public var tags: NSSet?
    @NSManaged public var fulminazione: String?
    @NSManaged public var gruppo: String?
    @NSManaged public var area: String?
    @NSManaged public var dataDenuncia: Date?
    @NSManaged public var dataIncarico: Date?
    @NSManaged public var dataSopralluogo: Date?
    @NSManaged public var numeroPolizza: String?
    @NSManaged public var tipoPolizza: String?
    @NSManaged public var definizione: String?
    @NSManaged public var definizioneManuale: Bool
    @NSManaged public var stimaDanno: NSDecimalNumber?
    @NSManaged public var propensionePerito: String?
    // Nuovi campi per complessità e ubicazione
    @NSManaged public var complessita: String?
    @NSManaged public var ubicazioneValidata: Bool
    @NSManaged public var ubicazioneNote: String?
    
    // Esito perizia (legacy - ora derivati da definizione)
    @NSManaged public var concordata: Bool      // Perizia concordata con l'assicurato
    @NSManaged public var negativa: Bool        // Perizia negativa (senza indennizzo)
    
    // MARK: - Regolarità Amministrativa (da PDF incarico - Gruppo Generali)
    /// Regolarità amministrativa estratta dal PDF incarico (nil = non rilevata, true = regolare, false = irregolare)
    @NSManaged public var regolaritaAmministrativa: NSNumber?
    /// Data pagamento premio estratta dal PDF incarico (valorizzata solo se regolarità = true)
    @NSManaged public var dataPagamentoPremio: Date?
    /// Flag per disattivare alert/blocchi su regolarità (impostato manualmente dall'utente)
    @NSManaged public var regolaritaAmministrativaOverride: Bool
    
    // MARK: - Identificativi fiscali assicurato (per match pregressi)
    /// Codice Fiscale dell'assicurato
    @NSManaged public var codiceFiscaleAssicurato: String?
    /// Partita IVA dell'assicurato
    @NSManaged public var partitaIVAAssicurato: String?
    
    // MARK: - Contatori e date solleciti (consolidati per performance)
    /// Numero di solleciti ricevuti (da compagnia, agenzia, assicurato, ecc.)
    @NSManaged public var sollecitiRicevutiCount: Int16
    /// Numero di solleciti inviati (manualmente o automatici)
    @NSManaged public var sollecitiInviatiCount: Int16
    /// Data dell'ultimo sollecito ricevuto
    @NSManaged public var dataUltimoSollecitoRicevuto: Date?
    /// Data dell'ultimo sollecito inviato
    @NSManaged public var dataUltimoSollecitoInviato: Date?
    /// Tipo mittente massimo sollecito ricevuto (peso più alto = più urgente)
    /// 0=unknown, 1=assicurato, 2=agenzia, 3=studio, 4=liquidatore/compagnia
    @NSManaged public var tipoMittenteSollecitoMax: Int16
    
    /// JSON storage per la lista dettagliata dei solleciti ricevuti
    @NSManaged private var sollecitiRicevutiJSON: String?
    
    // MARK: - Cicli di Controllo/Autorizzazione
    /// JSON storage per i cicli di controllo (array di CicloControllo)
    @NSManaged private var cicliControlloJSON: String?
    
    // MARK: - Computed Properties derivate dalla Definizione
    
    /// Indica se il sinistro prevede una liquidazione (indennizzo)
    public var haLiquidazione: Bool {
        guard let def = definizione?.uppercased() else { return false }
        
        // Atto di accertamento (con riserva, di danno, ecc.) non ha mai liquidazione
        if def.contains("ATTO DI ACCERTAMENTO") {
            return false
        }
        
        // Liquidazione NO
        let noLiquidazione = [
            "NON CONCORDATO (VED. NOTE)",
            "NON CONCORDATO (NO FENOMENO ELETTRICO)",
            "NON CONCORDATO (NO RESIDUI)",
            "NON CONCORDATO (SOTTO FRANCHIGIA)",
            "NON CONCORDATO (GARANZIE NON OPERANTI)",
            "NON CONCORDATO (UBICAZIONE DEL SINISTRO NON ASSICURATA)"
        ]
        
        for pattern in noLiquidazione {
            if def.contains(pattern.uppercased()) {
                return false
            }
        }
        
        // Se contiene "NON CONCORDATO" ma non è nella lista sopra, potrebbe essere il caso speciale
        // "NON CONCORDATO (Danno indennizzabile ma stima non concordata)" che HA liquidazione
        if def.contains("DANNO INDENNIZZABILE") {
            return true
        }
        
        // Se inizia con CONCORDATO, ha liquidazione (tranne ACCERTAMENTO CON RISERVA già filtrato)
        if def.starts(with: "CONCORDATO") {
            return true
        }
        
        return false
    }
    
    /// Indica se la perizia è stata concordata con l'assicurato
    public var isConcordata: Bool {
        guard let def = definizione?.uppercased() else { return false }
        
        // NON CONCORDATO = non concordata
        if def.starts(with: "NON CONCORDATO") {
            return false
        }
        
        // CONCORDATO = concordata
        if def.starts(with: "CONCORDATO") {
            return true
        }
        
        return false
    }
    
    /// Verifica se la perizia ha divisione tra SI e VSU
    /// Cerca pattern come "SI" e "VSU" nella definizione o altri campi
    public var haDivisioneSIVSU: Bool {
        // Cerca nella definizione
        if let def = definizione?.uppercased() {
            // Pattern comuni: "SI:" e "VSU:" o "SI " e "VSU " o riferimenti separati
            let hasSI = def.contains(" SI") || def.contains("SI:") || def.contains("SI/") || def.contains("/SI")
            let hasVSU = def.contains(" VSU") || def.contains("VSU:") || def.contains("VSU/") || def.contains("/VSU")
            
            // Se ha entrambi, c'è divisione
            if hasSI && hasVSU {
                return true
            }
        }
        
        // Potrebbe essere anche in altri campi, per ora restituiamo false se non trovato
        return false
    }
    
    /// Verifica se la perizia è senza atto (per Zurich: concordata e senza divisione SI/VSU)
    /// Per le altre compagnie sono sempre con atto
    public var isPeriziaSenzaAtto: Bool {
        // Verifica se è Zurich
        guard let nomeCompagnia = nomeCompagnia?.lowercased(),
              nomeCompagnia.contains("zurich") else {
            // Altre compagnie: sempre con atto
            return false
        }
        
        // Zurich: senza atto se concordata E senza divisione SI/VSU
        return isConcordata && !haDivisioneSIVSU
    }
    

    /// - Note: La Pronta Liquidazione (PL) significa che lo studio paga direttamente l'assicurato e non la compagnia
    // TODO: Questa logica vale solo per Generali e Zurich. Per Unipol la PL funziona diversamente.
    // Implementare logica completa in RuleManager o CompagniaService per gestire correttamente
    // la PL in base alla compagnia del sinistro (self.nomeCompagnia / self.gruppo)
    public var isInPL: Bool {
        guard let def = definizione?.uppercased() else { return false }
        
        // Se l'importo liquidato è superiore a 5000€ (5001,00 in poi), PL è sempre NO
        if let importo = importoLiquidatoEffettivo?.doubleValue, importo > 5000.0 {
            return false
        }
        
        // Non liquidabile dallo Studio peritale = NO in PL
        if def.contains("NON LIQUIDABILE DALLO STUDIO PERITALE") {
            return false
        }
        
        // Atto di accertamento (con riserva, di danno, ecc.) = NO in PL
        if def.contains("ATTO DI ACCERTAMENTO") {
            return false
        }
        
        // Tutti i NON CONCORDATO sono NO in PL, TRANNE "Danno indennizzabile ma stima non concordata"
        if def.starts(with: "NON CONCORDATO") {
            if def.contains("DANNO INDENNIZZABILE") {
                return true
            }
            return false
        }
        
        // CONCORDATO standard = in PL (solo se importo <= 5000€)
        if def.starts(with: "CONCORDATO") {
            return true
        }
        
        return false
    }
    
    /// Indica se il sinistro è negativo (no liquidazione)
    public var isNegativa: Bool {
        return !haLiquidazione
    }
    
    /// Label da mostrare per l'importo: "Liquidazione" se liquidato, "Stima del danno" se non liquidato
    public var importoLabel: String {
        return haLiquidazione ? "Liquidazione" : "Stima del danno"
    }
    
    /// Importo da visualizzare
    /// - Se haLiquidazione = true: il valore è l'importo liquidato (usa stimaDanno dall'excel, fallback a liquidato)
    /// - Se haLiquidazione = false: il valore è solo una stima del danno
    /// Per le statistiche del liquidato medio usare solo sinistri con haLiquidazione == true
    public var importoDaVisualizzare: NSDecimalNumber? {
        // L'excel salva sempre in stimaDanno, ma quando c'è liquidazione quel valore è l'importo liquidato
        return stimaDanno ?? liquidato ?? dannoAccertato
    }
    
    /// Importo liquidato effettivo (solo per sinistri con liquidazione)
    /// Da usare per le statistiche del liquidato medio
    public var importoLiquidatoEffettivo: NSDecimalNumber? {
        guard haLiquidazione else { return nil }
        // L'excel salva il valore in stimaDanno, che per i liquidati è l'importo effettivo
        return stimaDanno ?? liquidato ?? dannoAccertato
    }
    
    // MARK: - Computed Properties per Regolarità Amministrativa
    
    /// Regolarità amministrativa come Bool? (nil = non rilevata, true = regolare, false = irregolare)
    public var isRegolaritaAmministrativa: Bool? {
        get { regolaritaAmministrativa?.boolValue }
        set { regolaritaAmministrativa = newValue.map { NSNumber(value: $0) } }
    }
    
    /// Indica se la regolarità è stata rilevata (indipendentemente dal valore)
    public var hasRegolaritaAmministrativa: Bool {
        return regolaritaAmministrativa != nil
    }
    
    /// Indica se il sinistro ha irregolarità amministrativa (per blocchi/alert)
    /// Ritorna true solo se è stato rilevato e il valore è false
    public var hasIrregolaritaAmministrativa: Bool {
        return regolaritaAmministrativa?.boolValue == false
    }
    
    /// Indica se l'alert per irregolarità è attivo (non overridato)
    public var shouldShowIrregolaritaAlert: Bool {
        return hasIrregolaritaAmministrativa && !regolaritaAmministrativaOverride
    }
    
    // MARK: - Metodi Helper per Solleciti
    
    /// Lista dettagliata dei solleciti ricevuti (ordinata cronologicamente, più recenti prima)
    public var sollecitiRicevutiArray: [SollecitoRicevuto] {
        get {
            guard let json = sollecitiRicevutiJSON,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([SollecitoRicevuto].self, from: data) else {
                return []
            }
            return array.sorted { $0.dataRicezione > $1.dataRicezione }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                sollecitiRicevutiJSON = json
            }
        }
    }
    
    /// Aggiunge un sollecito alla lista dettagliata e aggiorna i contatori
    public func aggiungiSollecito(_ sollecito: SollecitoRicevuto) {
        var lista = sollecitiRicevutiArray
        lista.append(sollecito)
        sollecitiRicevutiArray = lista
        
        // Aggiorna anche i contatori consolidati
        sollecitiRicevutiCount = Int16(lista.count)
        dataUltimoSollecitoRicevuto = sollecito.dataRicezione
        
        // Aggiorna il tipo mittente solo se più grave del precedente
        if sollecito.tipoMittente.rawValue > tipoMittenteSollecitoMax {
            tipoMittenteSollecitoMax = Int16(sollecito.tipoMittente.rawValue)
        }
    }
    
    /// Rimuove un sollecito dalla lista dettagliata e aggiorna i contatori
    public func rimuoviSollecito(id: UUID) {
        var lista = sollecitiRicevutiArray
        lista.removeAll { $0.id == id }
        sollecitiRicevutiArray = lista
        
        // Aggiorna contatori
        sollecitiRicevutiCount = Int16(lista.count)
        dataUltimoSollecitoRicevuto = lista.first?.dataRicezione
        
        // Ricalcola tipo mittente max
        tipoMittenteSollecitoMax = Int16(lista.map { $0.tipoMittente.rawValue }.max() ?? 0)
    }
    
    /// Registra un sollecito ricevuto (incrementa contatore, aggiorna data e tipo mittente max)
    /// - Parameter tipoMittente: tipo del mittente (usa TipoMittenteSollecito.rawValue)
    public func registraSollecitoRicevuto(tipoMittente: TipoMittenteSollecito = .unknown) {
        sollecitiRicevutiCount += 1
        dataUltimoSollecitoRicevuto = Date()
        // Aggiorna il tipo mittente solo se più grave del precedente
        if tipoMittente.rawValue > tipoMittenteSollecitoMax {
            tipoMittenteSollecitoMax = Int16(tipoMittente.rawValue)
        }
    }
    
    /// Registra un sollecito inviato (incrementa contatore e aggiorna data)
    public func registraSollecitoInviato() {
        sollecitiInviatiCount += 1
        dataUltimoSollecitoInviato = Date()
    }
    
    /// Verifica se il sinistro ha urgenze critiche (solleciti ricevuti)
    public var hasSollecitiRicevuti: Bool {
        return sollecitiRicevutiCount > 0
    }
    
    /// Verifica se è stato superato il limite di solleciti inviati (3+)
    public var hasSuperatoLimiteSollecitiInviati: Bool {
        return sollecitiInviatiCount >= 3
    }
    
    /// Tipo mittente massimo come enum
    public var tipoMittenteSollecitoMaxEnum: TipoMittenteSollecito {
        return TipoMittenteSollecito(rawValue: Int(tipoMittenteSollecitoMax)) ?? .unknown
    }
    
    /// Boost priorità basato sul tipo mittente massimo (0.1 - 0.4)
    public var boostPrioritaSolleciti: Double {
        return tipoMittenteSollecitoMaxEnum.boostPriorita
    }
    
    // MARK: - Relazioni Perizia
    @NSManaged public var perizia: Perizia?
    @NSManaged public var coassicurazioni: NSSet?
    @NSManaged public var perxiaAnalisi: NSSet?
    
    var perxiaAnalisiArray: [PerxiaAnalisi] {
        let set = perxiaAnalisi as? Set<PerxiaAnalisi> ?? []
        return set.sorted { ($0.dataAnalisi ?? Date.distantPast) > ($1.dataAnalisi ?? Date.distantPast) }
    }
    
    // MARK: - Gestione cartelle e date aggiuntive
    @NSManaged public var cartella: String? // Percorso della cartella fisica del sinistro
    @NSManaged public var dataCreazione: Date? // Data di creazione del record
    
    public var id: String {
        riferimento ?? UUID().uuidString
    }
    
    var wrappedDivisioneCompagnia: String {
        nomeCompagnia ?? "Divisione mancante"
    }
    
    var wrappedNomeCompagnia: String {
        nomeCompagnia ?? "Non specificata"
    }
    
    // Alias per retrocompatibilità: divisioneCompagnia punta a nomeCompagnia
    var divisioneCompagnia: String? {
        get {
            return nomeCompagnia
        }
        set {
            nomeCompagnia = newValue
        }
    }
    
    var collegamentiSet: Set<String> {
        get {
            if let set = collegamenti as? Set<String> {
                return set
            }
            return Set<String>()
        }
        set {
            collegamenti = newValue as NSSet
        }
    }
    
    var diarioArray: [DiarioEntry] {
        get {
            if let data = diarioEntries as? Data,
               let entries = try? JSONDecoder().decode([DiarioEntry].self, from: data) {
                return entries
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                diarioEntries = data as NSObject
            }
        }
    }
    
    var telefoniAssicuratoArray: [String] {
        get {
            if let array = telefoniAssicurato as? [String] {
                return array
            }
            return []
        }
        set {
            telefoniAssicurato = newValue as NSArray
        }
    }
    
    var emailAssicuratoArray: [String] {
        get {
            if let array = emailAssicuratoArrayStorage as? [String] {
                return array
            }
            return []
        }
        set {
            emailAssicuratoArrayStorage = newValue as NSArray
        }
    }
    
    func addDiarioEntry(_ entry: DiarioEntry) {
        var entries = diarioArray
        entries.insert(entry, at: 0) // Inserisce all'inizio dell'array
        diarioArray = entries
    }
    
    // MARK: - Cicli Controllo Array
    
    /// Array dei cicli di controllo/autorizzazione del sinistro
    var cicliControlloArray: [CicloControllo] {
        get {
            guard let json = cicliControlloJSON,
                  let data = json.data(using: .utf8),
                  let cicli = try? JSONDecoder().decode([CicloControllo].self, from: data) else {
                return []
            }
            return cicli.sorted { $0.dataEntrata > $1.dataEntrata } // Più recenti prima
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                cicliControlloJSON = json
            }
        }
    }
    
    /// Ciclo di controllo attualmente aperto (se esiste)
    var cicloControlloAperto: CicloControllo? {
        cicliControlloArray.first { $0.isAperto }
    }
    
    /// Indica se il sinistro è attualmente in un ciclo di controllo
    var isInControllo: Bool {
        cicloControlloAperto != nil
    }
    
    /// Registra l'entrata in un ciclo di controllo
    /// - Parameter tipo: Tipo di controllo (inControllo, richiestaAutorizzazione, supervisioneNonConcordata)
    func registraEntrataControllo(tipo: CicloControllo.TipoControllo) {
        // Se c'è già un ciclo aperto, non aprirne un altro
        guard cicloControlloAperto == nil else {
            print("[Sinistro] ⚠️ Ciclo controllo già aperto, ignoro nuova entrata")
            return
        }
        
        let nuovoCiclo = CicloControllo(dataEntrata: Date(), tipoEntrata: tipo)
        var cicli = cicliControlloArray
        cicli.insert(nuovoCiclo, at: 0)
        cicliControlloArray = cicli
        
        print("[Sinistro] 📥 Registrata entrata controllo: \(tipo.rawValue)")
    }
    
    /// Registra l'uscita dal ciclo di controllo attualmente aperto
    /// - Parameter tipo: Tipo di uscita (controllata, chiusa, attoInviato, ecc.)
    func registraUscitaControllo(tipo: CicloControllo.TipoUscitaControllo) {
        var cicli = cicliControlloArray
        
        // Trova il ciclo aperto e chiudilo
        if let index = cicli.firstIndex(where: { $0.isAperto }) {
            var ciclo = cicli[index]
            ciclo.dataUscita = Date()
            ciclo.tipoUscita = tipo
            cicli[index] = ciclo
            cicliControlloArray = cicli
            
            let durata = ciclo.durataGiorniLavorativi ?? 0
            print("[Sinistro] 📤 Registrata uscita controllo: \(tipo.rawValue) (durata: \(durata) gg lav)")
        } else {
            print("[Sinistro] ⚠️ Nessun ciclo controllo aperto da chiudere")
        }
    }
    
    /// Aggiorna il tipo di controllo del ciclo attualmente aperto
    /// Usato quando si cambia tra stati di controllo (es. inControllo → supervisioneNonConcordata)
    /// - Parameter tipo: Nuovo tipo di controllo
    func aggiornaTipoControllo(tipo: CicloControllo.TipoControllo) {
        var cicli = cicliControlloArray
        
        if let index = cicli.firstIndex(where: { $0.isAperto }) {
            var ciclo = cicli[index]
            let vecchioTipo = ciclo.tipoEntrata
            ciclo.tipoEntrata = tipo
            cicli[index] = ciclo
            cicliControlloArray = cicli
            
            print("[Sinistro] 🔄 Aggiornato tipo controllo: \(vecchioTipo.rawValue) → \(tipo.rawValue)")
        } else {
            // Se non c'è un ciclo aperto, ne apriamo uno nuovo (caso edge)
            registraEntrataControllo(tipo: tipo)
        }
    }
    
    /// Statistiche aggregate sui cicli di controllo
    var statisticheControllo: (numeroCicli: Int, giorniTotali: Int, giorniLavorativiTotali: Int) {
        let cicliChiusi = cicliControlloArray.filter { !$0.isAperto }
        let giorniTotali = cicliChiusi.compactMap { $0.durataTotaleGiorni }.reduce(0, +)
        let giorniLav = cicliChiusi.compactMap { $0.durataGiorniLavorativi }.reduce(0, +)
        return (cicliChiusi.count, giorniTotali, giorniLav)
    }
    
    var statoGiustificativi: StatoGiustificativi {
        get {
            if let path = FileService.shared.getSinistroPath(riferimento: riferimento ?? ""),
               !path.isEmpty {
                return giustificativi ? .presenti : .assenti
            }
            return .nonNoti
        }
        set {
            giustificativi = newValue.isPresent
        }
    }
    
    // Dettaglio stato (annotazione predefinita)
    var statoDetail: StatoDetailCategory {
        get {
            if let raw = persistedStatoDetailCategory, let value = StatoDetailCategory(rawValue: raw) {
                return value
            }
            return .none
        }
        set {
            persistedStatoDetailCategory = newValue == .none ? nil : newValue.rawValue
        }
    }
    
    private var detailCategoryStorageKey: String {
        let key = riferimento ?? id
        return "sinistro.statoDetailCategory.\(key)"
    }
    
    /// Persistenza leggera senza migrazione Core Data
    private var persistedStatoDetailCategory: String? {
        get { UserDefaults.standard.string(forKey: detailCategoryStorageKey) }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: detailCategoryStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: detailCategoryStorageKey)
            }
        }
    }
    
    // MARK: - Tag Management (solo mailtag, non filetag!)
    // I filetag sono gestiti da FileTagManager.FileTag e non vanno mai confusi con Tag (Core Data)
    public func addToTags(_ tag: Tag) {
        let tags = self.tags?.mutableCopy() as? NSMutableSet ?? NSMutableSet()
        tags.add(tag)
        self.tags = tags
    }
    
    public func removeFromTags(_ tag: Tag) {
        let tags = self.tags?.mutableCopy() as? NSMutableSet ?? NSMutableSet()
        tags.remove(tag)
        self.tags = tags
    }
  
    // MARK: - Convenience Methods per gestire i tre attori fondamentali
    
    /// Assegna la stessa persona ai tre ruoli (contraente, assicurato, danneggiato)
    public func assegnaStessaPersonaAiTreRuoli(nome: String, telefono: String, email: String, indirizzo: String) {
        self.nomeContraente = nome
        self.telefonoContraente = telefono
        self.emailContraente = email
        self.indirizzoContraente = indirizzo
        
        self.nomeAssicurato = nome
        self.telefonoAssicurato = telefono
        self.emailAssicurato = email
        self.indirizzoAssicurato = indirizzo
        
        self.nomeDanneggiato = nome
        self.telefonoDanneggiato = telefono
        self.emailDanneggiato = email
        self.indirizzoDanneggiato = indirizzo
    }
    
    /// Verifica se la stessa persona ricopre tutti e tre i ruoli
    public var haSamepersonaPerTuttiIRuoli: Bool {
        guard let nomeContraente = nomeContraente,
              let nomeAssicurato = nomeAssicurato,
              let nomeDanneggiato = nomeDanneggiato else {
            return false
        }
        return nomeContraente == nomeAssicurato && nomeAssicurato == nomeDanneggiato
    }
    
    /// Restituisce il nome dell'attore principale (contraente)
    public var attorePrincipale: String? {
        return nomeContraente
    }
    
    // MARK: - Computed properties per backward compatibility
    
    public var nomeAssicuratoCompleto: String? {
        return nomeAssicurato ?? nomeAssicurato_legacy
    }
    
    public     var ragioneSocialeCompagnia: String? {
        return nomeCompagnia
    }
    
    var coassicurazioniArray: [Coassicurazione] {
        let set = coassicurazioni as? Set<Coassicurazione> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    public func addToCoassicurazioni(_ coass: Coassicurazione) {
        let items = self.mutableSetValue(forKey: "coassicurazioni")
        items.add(coass)
    }
    
    public func removeFromCoassicurazioni(_ coass: Coassicurazione) {
        let items = self.mutableSetValue(forKey: "coassicurazioni")
        items.remove(coass)
    }
    
    // MARK: - PerxiaAnalisi
    
    public func addToPerxiaAnalisi(_ analisi: PerxiaAnalisi) {
        let items = self.mutableSetValue(forKey: "perxiaAnalisi")
        items.add(analisi)
    }
    
    public func removeFromPerxiaAnalisi(_ analisi: PerxiaAnalisi) {
        let items = self.mutableSetValue(forKey: "perxiaAnalisi")
        items.remove(analisi)
    }
    
    // MARK: - Validazione Riferimento
    
    /// Valida il riferimento prima dell'inserimento
    /// Rifiuta sinistri con riferimento non valido o non conforme alle regole
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateRiferimento()
    }
    
    /// Valida il riferimento prima dell'aggiornamento
    /// Rifiuta sinistri con riferimento non valido o non conforme alle regole
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        
        // Valida solo se il riferimento è stato modificato
        if isUpdated && changedValues().keys.contains("riferimento") {
            try validateRiferimento()
        }
    }
    
    /// Valida il riferimento secondo le regole di business
    private func validateRiferimento() throws {
        guard let riferimento = riferimento, !riferimento.isEmpty else {
            // Riferimento vuoto è valido (può essere impostato dopo)
            return
        }
        
        // Valida il riferimento
        if let error = RiferimentoValidator.validate(riferimento) {
            print("[Sinistro] ❌ Validazione riferimento fallita: \(error)")
            throw NSError(
                domain: "SinistroValidationError",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey: error,
                    "riferimento": riferimento
                ]
            )
        }
    }
}

// MARK: - Fetch Request
extension Sinistro {
    static var fetchRequest: NSFetchRequest<Sinistro> {
        NSFetchRequest<Sinistro>(entityName: "Sinistro")
    }
}

enum StatoGiustificativi: String, Codable {
    case nonNoti = "Non noti"
    case presenti = "Presenti"
    case parziali = "Parziali"
    case assenti = "Assenti"
    
    var isPresent: Bool {
        self == .presenti || self == .parziali
    }
}

/// Tipo mittente sollecito ricevuto (peso crescente = più urgente)
/// Usato per calcolare il boost priorità in base alla gravità del sollecito
public enum TipoMittenteSollecito: Int, Codable, CaseIterable {
    case unknown = 0           // Mittente non identificato
    case assicurato = 1        // Assicurato/Cliente/Danneggiato (peso basso)
    case agenzia = 2           // Agenzia/Broker (peso medio-basso)
    case studio = 3            // Studio peritale (peso medio-alto)
    case liquidatoreCompagnia = 4  // Liquidatore/Compagnia/ACT (peso massimo)
    
    /// Boost priorità associato a questo tipo di mittente
    public var boostPriorita: Double {
        switch self {
        case .unknown: return 0.05
        case .assicurato: return 0.1
        case .agenzia: return 0.2
        case .studio: return 0.3
        case .liquidatoreCompagnia: return 0.4
        }
    }
    
    /// Descrizione leggibile
    public var descrizione: String {
        switch self {
        case .unknown: return "Mittente sconosciuto"
        case .assicurato: return "Assicurato"
        case .agenzia: return "Agenzia"
        case .studio: return "Studio"
        case .liquidatoreCompagnia: return "Liquidatore/Compagnia"
        }
    }
    
    /// Determina il tipo mittente dal testo (titolo + testo entry diario)
    public static func fromText(_ text: String) -> TipoMittenteSollecito {
        let lower = text.lowercased()
        
        if lower.contains("compagnia") || lower.contains("liquidatore") {
            return .liquidatoreCompagnia
        } else if lower.contains("studio") {
            return .studio
        } else if lower.contains("agenzia") || lower.contains("broker") {
            return .agenzia
        } else if lower.contains("assicurat") || lower.contains("cliente") || lower.contains("danneggiato") {
            return .assicurato
        }
        
        return .unknown
    }
}

// MARK: - Sync Tracking & Sede Agenzia

extension Sinistro {
    
    /// Chiave UserDefaults per la sede agenzia selezionata
    private var sedeAgenziaStorageKey: String {
        "sinistro_sede_agenzia_\(riferimento ?? "")"
    }
    
    /// ID della sede/filiale agenzia selezionata per questo sinistro.
    /// nil = usa sede madre, altrimenti ID della filiale.
    /// Salvato localmente in UserDefaults (sincronizzato via CK tramite CloudKitSinistroSyncService).
    public var sedeAgenziaSelezionataId: String? {
        get {
            UserDefaults.standard.string(forKey: sedeAgenziaStorageKey)
        }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: sedeAgenziaStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: sedeAgenziaStorageKey)
            }
        }
    }
    
    /// Marca il sinistro come modificato localmente (per tracking sync).
    /// Attualmente imposta lastModified e notifica il context.
    public func markAsLocallyModified() {
        // Usa il campo cloudKitLastModified come timestamp della modifica
        // per tracking generico delle modifiche locali
        objectWillChange.send()
    }
}
