import SwiftUI
import CoreData

// MARK: - Modelli per il Formula Builder

/// Categoria principale di una condizione
enum CategoriaCondizione: String, CaseIterable {
    case determinazione = "Determinazione"
    case compagnia = "Compagnia"
    case competenza = "Competenza"
    case data = "Data"
    case definizione = "Definizione"
    case percentuale = "% Globale"
    
    var icona: String {
        switch self {
        case .determinazione: return "checkmark.circle"
        case .compagnia: return "building.2"
        case .competenza: return "clock.arrow.circlepath"
        case .data: return "calendar"
        case .definizione: return "tag"
        case .percentuale: return "percent"
        }
    }
    
    var colore: Color {
        switch self {
        case .determinazione: return .teal
        case .compagnia: return .indigo
        case .competenza: return .green
        case .data: return .blue
        case .definizione: return .purple
        case .percentuale: return .orange
        }
    }
}

/// Tipo di data disponibile
enum TipoData: String, CaseIterable {
    case aperturaGestione = "Apertura gestione"
    case assegnazione = "Assegnazione"
    case incarico = "Incarico"
    case invioAtto = "Invio atto"
    case chiusura = "Chiusura"
    case revoca = "Revoca"
    case sinistro = "Sinistro"
    case denuncia = "Denuncia"
    case sopralluogo = "Sopralluogo"
}

/// Tipo di comparazione per le date
enum ComparatoreData: String, CaseIterable {
    case prima = "Prima di"
    case dopo = "Dopo il"
    case tra = "Compresa tra"
}

/// Tipo di percentuale disponibile
enum TipoPercentuale: String, CaseIterable {
    case negative = "Negative"
    case concordate = "Concordate"
    case nonConcordate = "Non concordate"
    case inPL = "In PL"
}

/// Tipo di comparazione per le percentuali
enum ComparatorePercentuale: String, CaseIterable {
    case superiore = "Superiore a"
    case tra = "Compresa tra"
}

/// Tipo di filtro per anno di competenza
enum TipoCompetenza: String, CaseIterable {
    case annoCorrente = "Anno corrente"
    case annoPrecedente = "Anno precedente"
    case annoSpecifico = "Anno specifico"
    case annoTra = "Compreso tra"
}

/// Tipo di determinazione sinistro (condizione diretta)
enum TipoDeterminazione: String, CaseIterable {
    case negativo = "È negativo"
    case concordato = "È concordato"
    case nonConcordato = "Non è concordato"
    case inPL = "È in PL"
}

/// Operatore logico user-friendly
enum OperatoreUserFriendly: String, CaseIterable {
    case unica = "Solo questa"
    case e = "E anche"
    case oppure = "Oppure"
    
    var operatoreLogico: OperatoreLogico? {
        switch self {
        case .unica: return nil
        case .e: return .AND
        case .oppure: return .OR
        }
    }
}

// MARK: - Formula Builder State

/// Stato di una singola regola nel builder
class RegolaState: ObservableObject, Identifiable {
    let id = UUID()
    
    @Published var categoria: CategoriaCondizione = .data
    @Published var operatore: OperatoreUserFriendly = .unica
    
    // Data
    @Published var tipoData: TipoData = .assegnazione
    @Published var comparatoreData: ComparatoreData = .dopo
    @Published var dataValore: Date = Date()
    @Published var dataInizio: Date = Date()
    @Published var dataFine: Date = Date()
    
    // Percentuale
    @Published var tipoPercentuale: TipoPercentuale = .negative
    @Published var comparatorePercentuale: ComparatorePercentuale = .superiore
    @Published var percentualeValore: String = ""
    @Published var percentualeMin: String = ""
    @Published var percentualeMax: String = ""
    @Published var periodoCalcolo: PeriodoCalcoloPercentuale = .mese
    @Published var applicazionePercentuale: ApplicazioneBonusPercentuale = .soloQualificanti
    
    // Definizione
    @Published var definizioniSelezionate: Set<String> = []
    
    // Compagnia
    @Published var compagnieSelezionate: Set<String> = []
    
    // Determinazione
    @Published var tipoDeterminazione: TipoDeterminazione = .negativo
    
    // Competenza
    @Published var tipoCompetenza: TipoCompetenza = .annoCorrente
    @Published var annoSpecifico: String = ""
    @Published var annoDa: String = ""
    @Published var annoA: String = ""
    
    init() {
        // Imposta anno corrente come default
        let currentYear = Calendar.current.component(.year, from: Date())
        annoSpecifico = String(currentYear)
        annoDa = String(currentYear - 1)
        annoA = String(currentYear)
    }
    
    init(from condizione: CondizioneBonus) {
        // Parse operatore
        if let op = condizione.operatore {
            self.operatore = op == .AND ? .e : .oppure
        } else {
            self.operatore = .unica
        }
        
        // Parse tipo condizione
        switch condizione.tipo {
        // Date - Dopo
        case .dataAperturaGestioneDopo:
            categoria = .data; tipoData = .aperturaGestione; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataAssegnazioneDopo:
            categoria = .data; tipoData = .assegnazione; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataIncaricoDopo:
            categoria = .data; tipoData = .incarico; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataInvioAttoDopo:
            categoria = .data; tipoData = .invioAtto; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataChiusuraDopo:
            categoria = .data; tipoData = .chiusura; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataRevocaDopo:
            categoria = .data; tipoData = .revoca; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataSinistroDopo:
            categoria = .data; tipoData = .sinistro; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataDenunciaDopo:
            categoria = .data; tipoData = .denuncia; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
        case .dataSopralluogoDopo:
            categoria = .data; tipoData = .sopralluogo; comparatoreData = .dopo
            if let data = condizione.dataValore { dataValore = data }
            
        // Date - Prima
        case .dataAperturaGestionePrima:
            categoria = .data; tipoData = .aperturaGestione; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataAssegnazionePrima:
            categoria = .data; tipoData = .assegnazione; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataIncaricoPrima:
            categoria = .data; tipoData = .incarico; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataInvioAttoPrima:
            categoria = .data; tipoData = .invioAtto; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataChiusuraPrima:
            categoria = .data; tipoData = .chiusura; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataRevocaPrima:
            categoria = .data; tipoData = .revoca; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataSinistroPrima:
            categoria = .data; tipoData = .sinistro; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataDenunciaPrima:
            categoria = .data; tipoData = .denuncia; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
        case .dataSopralluogoPrima:
            categoria = .data; tipoData = .sopralluogo; comparatoreData = .prima
            if let data = condizione.dataValore { dataValore = data }
            
        // Date - Tra
        case .dataAperturaGestioneTra:
            categoria = .data; tipoData = .aperturaGestione; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataAssegnazioneTra:
            categoria = .data; tipoData = .assegnazione; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataIncaricoTra:
            categoria = .data; tipoData = .incarico; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataInvioAttoTra:
            categoria = .data; tipoData = .invioAtto; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataChiusuraTra:
            categoria = .data; tipoData = .chiusura; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataRevocaTra:
            categoria = .data; tipoData = .revoca; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataSinistroTra:
            categoria = .data; tipoData = .sinistro; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataDenunciaTra:
            categoria = .data; tipoData = .denuncia; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
        case .dataSopralluogoTra:
            categoria = .data; tipoData = .sopralluogo; comparatoreData = .tra
            if let range = condizione.dataRange { dataInizio = range.from; dataFine = range.to }
            
        // Definizione
        case .definizioneIn:
            categoria = .definizione
            if let defs = condizione.definizioniArray { definizioniSelezionate = Set(defs) }
            
        // Compagnia
        case .compagniaIn:
            categoria = .compagnia
            if let comps = condizione.compagnieArray { compagnieSelezionate = Set(comps) }
            
        // Determinazione (condizioni dirette)
        case .sinistroIsNegativo:
            categoria = .determinazione; tipoDeterminazione = .negativo
        case .sinistroIsConcordato:
            categoria = .determinazione; tipoDeterminazione = .concordato
        case .sinistroIsNonConcordato:
            categoria = .determinazione; tipoDeterminazione = .nonConcordato
        case .sinistroIsInPL:
            categoria = .determinazione; tipoDeterminazione = .inPL
            
        // Percentuali
        case .percentualeNegativeSuperiore:
            categoria = .percentuale; tipoPercentuale = .negative; comparatorePercentuale = .superiore
            if let val = condizione.percentualeValore { percentualeValore = String(format: "%.1f", val) }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualeNegativeTra:
            categoria = .percentuale; tipoPercentuale = .negative; comparatorePercentuale = .tra
            if let range = condizione.percentualeRange {
                percentualeMin = String(format: "%.1f", range.min)
                percentualeMax = String(format: "%.1f", range.max)
            }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualeConcordateSuperiore:
            categoria = .percentuale; tipoPercentuale = .concordate; comparatorePercentuale = .superiore
            if let val = condizione.percentualeValore { percentualeValore = String(format: "%.1f", val) }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualeConcordateTra:
            categoria = .percentuale; tipoPercentuale = .concordate; comparatorePercentuale = .tra
            if let range = condizione.percentualeRange {
                percentualeMin = String(format: "%.1f", range.min)
                percentualeMax = String(format: "%.1f", range.max)
            }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualeNonConcordateSuperiore:
            categoria = .percentuale; tipoPercentuale = .nonConcordate; comparatorePercentuale = .superiore
            if let val = condizione.percentualeValore { percentualeValore = String(format: "%.1f", val) }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualeNonConcordateTra:
            categoria = .percentuale; tipoPercentuale = .nonConcordate; comparatorePercentuale = .tra
            if let range = condizione.percentualeRange {
                percentualeMin = String(format: "%.1f", range.min)
                percentualeMax = String(format: "%.1f", range.max)
            }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualePLSuperiore:
            categoria = .percentuale; tipoPercentuale = .inPL; comparatorePercentuale = .superiore
            if let val = condizione.percentualeValore { percentualeValore = String(format: "%.1f", val) }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
        case .percentualePLTra:
            categoria = .percentuale; tipoPercentuale = .inPL; comparatorePercentuale = .tra
            if let range = condizione.percentualeRange {
                percentualeMin = String(format: "%.1f", range.min)
                percentualeMax = String(format: "%.1f", range.max)
            }
            periodoCalcolo = condizione.periodoCalcolo
            applicazionePercentuale = condizione.applicazione
            
        // Competenza (anno di riferimento)
        case .competenzaAnnoCorrente:
            categoria = .competenza; tipoCompetenza = .annoCorrente
        case .competenzaAnnoPrecedente:
            categoria = .competenza; tipoCompetenza = .annoPrecedente
        case .competenzaAnnoSpecifico:
            categoria = .competenza; tipoCompetenza = .annoSpecifico
            if let anno = condizione.annoValore { annoSpecifico = String(anno) }
        case .competenzaAnnoTra:
            categoria = .competenza; tipoCompetenza = .annoTra
            if let range = condizione.annoRange {
                annoDa = String(range.from)
                annoA = String(range.to)
            }
        }
    }
    
    func toCondizione(isFirst: Bool) -> CondizioneBonus {
        let tipo = getTipoCondizione()
        var condizione = CondizioneBonus(
            id: UUID().uuidString,
            tipo: tipo,
            valore: "",
            operatore: isFirst ? nil : operatore.operatoreLogico,
            periodoPercentuale: categoria == .percentuale ? periodoCalcolo : nil,
            applicazionePercentuale: categoria == .percentuale ? applicazionePercentuale : nil
        )
        
        switch categoria {
        case .data:
            if comparatoreData == .tra {
                condizione.dataRange = (from: dataInizio, to: dataFine)
            } else {
                condizione.dataValore = dataValore
            }
        case .percentuale:
            if comparatorePercentuale == .tra {
                if let min = Double(percentualeMin.replacingOccurrences(of: ",", with: ".")),
                   let max = Double(percentualeMax.replacingOccurrences(of: ",", with: ".")) {
                    condizione.percentualeRange = (min: min, max: max)
                }
            } else {
                if let val = Double(percentualeValore.replacingOccurrences(of: ",", with: ".")) {
                    condizione.percentualeValore = val
                }
            }
        case .definizione:
            condizione.definizioniArray = Array(definizioniSelezionate)
        case .compagnia:
            condizione.compagnieArray = Array(compagnieSelezionate)
        case .determinazione:
            break // Non ha valori extra, il tipo è sufficiente
        case .competenza:
            switch tipoCompetenza {
            case .annoSpecifico:
                if let anno = Int(annoSpecifico) {
                    condizione.annoValore = anno
                }
            case .annoTra:
                if let da = Int(annoDa), let a = Int(annoA) {
                    condizione.annoRange = (from: da, to: a)
                }
            default:
                break // annoCorrente e annoPrecedente non hanno valori extra
            }
        }
        
        return condizione
    }
    
    private func getTipoCondizione() -> TipoCondizione {
        switch categoria {
        case .data:
            switch (tipoData, comparatoreData) {
            case (.aperturaGestione, .dopo): return .dataAperturaGestioneDopo
            case (.aperturaGestione, .prima): return .dataAperturaGestionePrima
            case (.aperturaGestione, .tra): return .dataAperturaGestioneTra
            case (.assegnazione, .dopo): return .dataAssegnazioneDopo
            case (.assegnazione, .prima): return .dataAssegnazionePrima
            case (.assegnazione, .tra): return .dataAssegnazioneTra
            case (.incarico, .dopo): return .dataIncaricoDopo
            case (.incarico, .prima): return .dataIncaricoPrima
            case (.incarico, .tra): return .dataIncaricoTra
            case (.invioAtto, .dopo): return .dataInvioAttoDopo
            case (.invioAtto, .prima): return .dataInvioAttoPrima
            case (.invioAtto, .tra): return .dataInvioAttoTra
            case (.chiusura, .dopo): return .dataChiusuraDopo
            case (.chiusura, .prima): return .dataChiusuraPrima
            case (.chiusura, .tra): return .dataChiusuraTra
            case (.revoca, .dopo): return .dataRevocaDopo
            case (.revoca, .prima): return .dataRevocaPrima
            case (.revoca, .tra): return .dataRevocaTra
            case (.sinistro, .dopo): return .dataSinistroDopo
            case (.sinistro, .prima): return .dataSinistroPrima
            case (.sinistro, .tra): return .dataSinistroTra
            case (.denuncia, .dopo): return .dataDenunciaDopo
            case (.denuncia, .prima): return .dataDenunciaPrima
            case (.denuncia, .tra): return .dataDenunciaTra
            case (.sopralluogo, .dopo): return .dataSopralluogoDopo
            case (.sopralluogo, .prima): return .dataSopralluogoPrima
            case (.sopralluogo, .tra): return .dataSopralluogoTra
            }
        case .percentuale:
            switch (tipoPercentuale, comparatorePercentuale) {
            case (.negative, .superiore): return .percentualeNegativeSuperiore
            case (.negative, .tra): return .percentualeNegativeTra
            case (.concordate, .superiore): return .percentualeConcordateSuperiore
            case (.concordate, .tra): return .percentualeConcordateTra
            case (.nonConcordate, .superiore): return .percentualeNonConcordateSuperiore
            case (.nonConcordate, .tra): return .percentualeNonConcordateTra
            case (.inPL, .superiore): return .percentualePLSuperiore
            case (.inPL, .tra): return .percentualePLTra
            }
        case .definizione:
            return .definizioneIn
        case .compagnia:
            return .compagniaIn
        case .determinazione:
            switch tipoDeterminazione {
            case .negativo: return .sinistroIsNegativo
            case .concordato: return .sinistroIsConcordato
            case .nonConcordato: return .sinistroIsNonConcordato
            case .inPL: return .sinistroIsInPL
            }
        case .competenza:
            switch tipoCompetenza {
            case .annoCorrente: return .competenzaAnnoCorrente
            case .annoPrecedente: return .competenzaAnnoPrecedente
            case .annoSpecifico: return .competenzaAnnoSpecifico
            case .annoTra: return .competenzaAnnoTra
            }
        }
    }
}

// MARK: - BonusEditorView

struct BonusEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    
    let month: Date
    let bonusToEdit: BonusMensile?
    
    @State private var nome: String = ""
    @State private var tipoBonus: TipoBonus = .unaTantum
    @State private var importo: String = ""
    @State private var attivo: Bool = true
    @State private var regole: [RegolaState] = []
    @State private var tutteDefinizioni: [String] = []
    @State private var tutteCompagnie: [String] = []
    @State private var isExpanded: Bool = true
    
    init(bonus: BonusMensile, month: Date, isPresented: Binding<Bool>) {
        self.bonusToEdit = bonus
        self.month = month
        self._isPresented = isPresented
        self._nome = State(initialValue: bonus.nome)
        self._tipoBonus = State(initialValue: bonus.tipo)
        self._importo = State(initialValue: String(format: "%.2f", bonus.importo))
        self._attivo = State(initialValue: bonus.attivo)
        
        // Converti condizioni esistenti in regole
        if let condizioni = bonus.condizioni {
            let regolaStates = condizioni.map { RegolaState(from: $0) }
            self._regole = State(initialValue: regolaStates)
        }
    }
    
    init(month: Date, isPresented: Binding<Bool>) {
        self.bonusToEdit = nil
        self.month = month
        self._isPresented = isPresented
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Contenuto
            ScrollView {
                VStack(spacing: 24) {
                    // Info base
                    infoBaseSection
                    
                    // Formula Builder (solo per bonus dinamici)
                    if tipoBonus == .dinamico {
                        formulaBuilderSection
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 800, height: 700)
        .onAppear {
            loadDefinizioni()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bonusToEdit != nil ? "Modifica Bonus" : "Nuovo Bonus")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                
                Text("Configura le regole per il calcolo automatico")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("Attivo", isOn: $attivo)
                .toggleStyle(.switch)
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Info Base
    
    private var infoBaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Informazioni Base", systemImage: "info.circle")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    // Nome
                    HStack {
                        Text("Nome")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("Nome del bonus", text: $nome)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Tipo
                    HStack {
                        Text("Tipo")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $tipoBonus) {
                            Label("Una tantum", systemImage: "1.circle").tag(TipoBonus.unaTantum)
                            Label("Dinamico", systemImage: "function").tag(TipoBonus.dinamico)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        
                        Spacer()
                    }
                    
                    // Importo
                    HStack {
                        Text("Importo")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("€")
                                .foregroundColor(.secondary)
                            TextField("0,00", text: $importo)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            
                            if tipoBonus == .dinamico {
                                Text("per sinistro")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Formula Builder
    
    private var formulaBuilderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Regole del Bonus", systemImage: "function")
                    .font(.headline)
                
                Spacer()
                
                Text("Il bonus viene applicato ai sinistri che soddisfano queste condizioni")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GroupBox {
                VStack(spacing: 0) {
                    if regole.isEmpty {
                        emptyRulesView
                    } else {
                        ForEach(Array(regole.enumerated()), id: \.element.id) { index, regola in
                            VStack(spacing: 0) {
                                // Connettore operatore (tranne per la prima regola)
                                if index > 0 {
                                    operatoreConnector(for: regola, index: index)
                                }
                                
                                // Blocco regola
                                RegolaBlockView(
                                    regola: regola,
                                    tutteDefinizioni: tutteDefinizioni,
                                    tutteCompagnie: tutteCompagnie,
                                    isFirst: index == 0,
                                    onDelete: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            regole.removeAll { $0.id == regola.id }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    // Pulsante aggiungi
                    addRuleButton
                }
                .padding()
            }
            
            // Preview della formula
            if !regole.isEmpty {
                formulaPreview
            }
        }
    }
    
    private var emptyRulesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Nessuna regola configurata")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Aggiungi una regola per definire quali sinistri qualificano per questo bonus")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    private func operatoreConnector(for regola: RegolaState, index: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 20)
            
            Picker("", selection: Binding(
                get: { regola.operatore },
                set: { regola.operatore = $0 }
            )) {
                Text("E anche").tag(OperatoreUserFriendly.e)
                Text("Oppure").tag(OperatoreUserFriendly.oppure)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2, height: 20)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var addRuleButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                regole.append(RegolaState())
            }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Aggiungi regola")
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.top, regole.isEmpty ? 0 : 16)
    }
    
    private var formulaPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Anteprima Formula", systemImage: "eye")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            GroupBox {
                HStack(spacing: 4) {
                    ForEach(Array(regole.enumerated()), id: \.element.id) { index, regola in
                        if index > 0 {
                            Text(regola.operatore == .e ? "E" : "O")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                        }
                        
                        FormulaPreviewBlock(regola: regola)
                    }
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Annulla") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button("Salva") {
                saveBonus()
            }
            .buttonStyle(.borderedProminent)
            .disabled(nome.isEmpty || importo.isEmpty || Double(importo.replacingOccurrences(of: ",", with: ".")) == nil)
            .keyboardShortcut(.return)
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func saveBonus() {
        guard let importoValue = Double(importo.replacingOccurrences(of: ",", with: ".")) else { return }
        
        // Converti le regole in condizioni
        let condizioni: [CondizioneBonus]? = tipoBonus == .dinamico && !regole.isEmpty
            ? regole.enumerated().map { index, regola in regola.toCondizione(isFirst: index == 0) }
            : nil
        
        let bonus = BonusMensile(
            id: bonusToEdit?.id ?? UUID().uuidString,
            nome: nome,
            tipo: tipoBonus,
            importo: importoValue,
            condizioni: condizioni,
            attivo: attivo
        )
        
        if bonusToEdit != nil {
            BonusMensileService.shared.updateBonus(bonus, for: month)
        } else {
            BonusMensileService.shared.addBonus(bonus, for: month)
        }
        
        dismiss()
    }
    
    private func loadDefinizioni() {
        guard tutteDefinizioni.isEmpty else { return }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        
        do {
            let sinistri = try viewContext.fetch(request)
            
            // Carica definizioni
            let definizioni = sinistri.compactMap { $0.definizione }.filter { !$0.isEmpty }
            tutteDefinizioni = Array(Set(definizioni)).sorted()
            
            // Carica compagnie
            let compagnie = sinistri.compactMap { $0.nomeCompagnia }.filter { !$0.isEmpty }
            tutteCompagnie = Array(Set(compagnie)).sorted()
        } catch {
            tutteDefinizioni = []
            tutteCompagnie = []
        }
    }
}

// MARK: - Regola Block View

struct RegolaBlockView: View {
    @ObservedObject var regola: RegolaState
    let tutteDefinizioni: [String]
    let tutteCompagnie: [String]
    let isFirst: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Indicatore categoria
            VStack {
                Image(systemName: regola.categoria.icona)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(regola.categoria.colore)
                    .cornerRadius(8)
            }
            
            // Contenuto regola
            VStack(alignment: .leading, spacing: 12) {
                // Selettore categoria
                HStack(spacing: 8) {
                    ForEach(CategoriaCondizione.allCases, id: \.self) { cat in
                        Button(action: { regola.categoria = cat }) {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icona)
                                    .font(.caption)
                                Text(cat.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(regola.categoria == cat ? cat.colore : Color.secondary.opacity(0.1))
                            .foregroundColor(regola.categoria == cat ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                
                // Campi specifici in base alla categoria
                switch regola.categoria {
                case .determinazione:
                    determinazioneFieldsView
                case .compagnia:
                    compagniaFieldsView
                case .competenza:
                    competenzaFieldsView
                case .data:
                    dataFieldsView
                case .definizione:
                    definizioneFieldsView
                case .percentuale:
                    percentualeFieldsView
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(regola.categoria.colore.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Data Fields
    
    private var dataFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Quale data
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quale data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.tipoData) {
                        ForEach(TipoData.allCases, id: \.self) { tipo in
                            Text(tipo.rawValue).tag(tipo)
                        }
                    }
                    .frame(width: 160)
                }
                
                // Tipo confronto
                VStack(alignment: .leading, spacing: 4) {
                    Text("Condizione")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.comparatoreData) {
                        ForEach(ComparatoreData.allCases, id: \.self) { comp in
                            Text(comp.rawValue).tag(comp)
                        }
                    }
                    .frame(width: 140)
                }
                
                Spacer()
            }
            
            // Campi data dinamici
            HStack(spacing: 12) {
                if regola.comparatoreData == .tra {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $regola.dataInizio, displayedComponents: .date)
                            .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Al")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $regola.dataFine, displayedComponents: .date)
                            .labelsHidden()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $regola.dataValore, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Percentuale Fields
    
    private var percentualeFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Tipo percentuale
                VStack(alignment: .leading, spacing: 4) {
                    Text("Percentuale di")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.tipoPercentuale) {
                        ForEach(TipoPercentuale.allCases, id: \.self) { tipo in
                            Text(tipo.rawValue).tag(tipo)
                        }
                    }
                    .frame(width: 160)
                }
                
                // Condizione
                VStack(alignment: .leading, spacing: 4) {
                    Text("Condizione")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.comparatorePercentuale) {
                        ForEach(ComparatorePercentuale.allCases, id: \.self) { comp in
                            Text(comp.rawValue).tag(comp)
                        }
                    }
                    .frame(width: 140)
                }
                
                // Periodo
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calcolata su")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.periodoCalcolo) {
                        Text("Mese").tag(PeriodoCalcoloPercentuale.mese)
                        Text("Anno").tag(PeriodoCalcoloPercentuale.anno)
                    }
                    .frame(width: 100)
                }
                
                Spacer()
            }
            
            // Valori
            HStack(spacing: 12) {
                if regola.comparatorePercentuale == .tra {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Da")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            TextField("0", text: $regola.percentualeMin)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("%")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            TextField("100", text: $regola.percentualeMax)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("%")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valore")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            TextField("0", text: $regola.percentualeValore)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("%")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Applicazione: a quali sinistri applicare il bonus
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("A chi applicare il bonus?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Button(action: { regola.applicazionePercentuale = .soloQualificanti }) {
                        HStack(spacing: 6) {
                            Image(systemName: regola.applicazionePercentuale == .soloQualificanti ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(regola.applicazionePercentuale == .soloQualificanti ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Solo ai sinistri che contribuiscono")
                                    .font(.caption.weight(.medium))
                                Text(applicazioneDescrizioneQualificanti)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(regola.applicazionePercentuale == .soloQualificanti ? Color.orange.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { regola.applicazionePercentuale = .tutti }) {
                        HStack(spacing: 6) {
                            Image(systemName: regola.applicazionePercentuale == .tutti ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(regola.applicazionePercentuale == .tutti ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A tutti i sinistri")
                                    .font(.caption.weight(.medium))
                                Text("Se la % è soddisfatta, bonus su tutti")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(regola.applicazionePercentuale == .tutti ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
            }
        }
    }
    
    /// Descrizione dinamica per l'opzione "solo qualificanti"
    private var applicazioneDescrizioneQualificanti: String {
        switch regola.tipoPercentuale {
        case .negative:
            return "Solo ai sinistri negativi"
        case .concordate:
            return "Solo ai sinistri concordati"
        case .nonConcordate:
            return "Solo ai sinistri non concordati"
        case .inPL:
            return "Solo ai sinistri in PL"
        }
    }
    
    // MARK: - Determinazione Fields
    
    private var determinazioneFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Il sinistro deve essere:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(TipoDeterminazione.allCases, id: \.self) { tipo in
                    Button(action: { regola.tipoDeterminazione = tipo }) {
                        Text(tipo.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(regola.tipoDeterminazione == tipo ? Color.teal : Color.secondary.opacity(0.1))
                            .foregroundColor(regola.tipoDeterminazione == tipo ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Compagnia Fields
    
    private var compagniaFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seleziona le compagnie ammesse")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if tutteCompagnie.isEmpty {
                Text("Nessuna compagnia trovata nel database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tutteCompagnie, id: \.self) { comp in
                            Button(action: {
                                if regola.compagnieSelezionate.contains(comp) {
                                    regola.compagnieSelezionate.remove(comp)
                                } else {
                                    regola.compagnieSelezionate.insert(comp)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if regola.compagnieSelezionate.contains(comp) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                    }
                                    Text(comp)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(regola.compagnieSelezionate.contains(comp) ? Color.indigo : Color.secondary.opacity(0.1))
                                .foregroundColor(regola.compagnieSelezionate.contains(comp) ? .white : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if !regola.compagnieSelezionate.isEmpty {
                    Text("\(regola.compagnieSelezionate.count) compagnie selezionate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Definizione Fields
    
    private var definizioneFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seleziona le definizioni ammesse")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if tutteDefinizioni.isEmpty {
                Text("Nessuna definizione trovata nel database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tutteDefinizioni, id: \.self) { def in
                            Button(action: {
                                if regola.definizioniSelezionate.contains(def) {
                                    regola.definizioniSelezionate.remove(def)
                                } else {
                                    regola.definizioniSelezionate.insert(def)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if regola.definizioniSelezionate.contains(def) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                    }
                                    Text(def)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(regola.definizioniSelezionate.contains(def) ? Color.purple : Color.secondary.opacity(0.1))
                                .foregroundColor(regola.definizioniSelezionate.contains(def) ? .white : .primary)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if !regola.definizioniSelezionate.isEmpty {
                    Text("\(regola.definizioniSelezionate.count) definizioni selezionate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Competenza Fields
    
    private var competenzaFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anno di competenza")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $regola.tipoCompetenza) {
                        ForEach(TipoCompetenza.allCases, id: \.self) { tipo in
                            Text(tipo.rawValue).tag(tipo)
                        }
                    }
                    .frame(width: 180)
                }
                
                Spacer()
            }
            
            // Campi dinamici in base al tipo
            HStack(spacing: 12) {
                switch regola.tipoCompetenza {
                case .annoCorrente:
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.green)
                        Text("Sinistri dell'anno corrente (dinamico)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    
                case .annoPrecedente:
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.minus")
                            .foregroundColor(.green)
                        Text("Sinistri dell'anno precedente (dinamico)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    
                case .annoSpecifico:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anno")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("2024", text: $regola.annoSpecifico)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                case .annoTra:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Da")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("2023", text: $regola.annoDa)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("2025", text: $regola.annoA)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                
                Spacer()
            }
            
            // Nota esplicativa
            Text("L'anno di competenza viene estratto dal riferimento sinistro (es: 25xxxxx → 2025)")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Formula Preview Block

struct FormulaPreviewBlock: View {
    @ObservedObject var regola: RegolaState
    
    private var descrizione: String {
        switch regola.categoria {
        case .determinazione:
            return regola.tipoDeterminazione.rawValue
            
        case .compagnia:
            let count = regola.compagnieSelezionate.count
            return count == 0 ? "Compagnia" : "Compagnia (\(count))"
            
        case .competenza:
            switch regola.tipoCompetenza {
            case .annoCorrente:
                return "Anno corrente"
            case .annoPrecedente:
                return "Anno precedente"
            case .annoSpecifico:
                return "Anno \(regola.annoSpecifico)"
            case .annoTra:
                return "Anno \(regola.annoDa)-\(regola.annoA)"
            }
            
        case .data:
            let dataStr: String
            if regola.comparatoreData == .tra {
                let df = DateFormatter()
                df.dateStyle = .short
                dataStr = "\(df.string(from: regola.dataInizio)) - \(df.string(from: regola.dataFine))"
            } else {
                let df = DateFormatter()
                df.dateStyle = .short
                dataStr = df.string(from: regola.dataValore)
            }
            return "\(regola.tipoData.rawValue) \(regola.comparatoreData.rawValue.lowercased()) \(dataStr)"
            
        case .definizione:
            let count = regola.definizioniSelezionate.count
            return count == 0 ? "Definizione" : "Definizione in (\(count))"
            
        case .percentuale:
            let valStr: String
            if regola.comparatorePercentuale == .tra {
                valStr = "\(regola.percentualeMin)% - \(regola.percentualeMax)%"
            } else {
                valStr = "\(regola.percentualeValore)%"
            }
            return "% \(regola.tipoPercentuale.rawValue) \(regola.comparatorePercentuale.rawValue.lowercased()) \(valStr)"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: regola.categoria.icona)
                .font(.system(size: 10))
            Text(descrizione)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(regola.categoria.colore.opacity(0.15))
        .foregroundColor(regola.categoria.colore)
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    BonusEditorView(month: Date(), isPresented: .constant(true))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
