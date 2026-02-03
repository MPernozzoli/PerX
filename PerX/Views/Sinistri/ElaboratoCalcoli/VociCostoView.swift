import SwiftUI
import CoreData

struct VociCostoView: View {
    @ObservedObject var bene: Bene
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    @StateObject private var formulaParser = FormulaParser.shared
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    
    let deprezzamento: Double
    let aliquotaIVA: Double
    let ivaInclusa: Bool
    let determinazioneDanno: String
    @Binding var diversiPerRiga: Bool
    var sinistroPath: String? = nil
    var componentiFromGiustificativi: [String] = []
    
    @State private var modalita: String = "Normale"
    @State private var componentiSuggeriti: [String] = []
    @State private var showManodoperaSuggestion: Bool = true
    @State private var allComponentiDisponibili: [String] = []
    
    private let modalitaOptions = ["Normale", "Inverso", "Forzatura"]
    
    // Unità di misura disponibili
    static let unitaMisuraOptions = ["pz", "ore", "ml", "kg", "L", "a corpo"]
    
    // Abbinamenti predefiniti voce -> (unitaMisura, quantita, valoreUnitario)
    static let abbinamentVoci: [String: (um: String, qty: Double, val: Double)] = [
        "Manodopera": (um: "ore", qty: 5, val: 40.0),
        "Diritto di chiamata": (um: "a corpo", qty: 1, val: 50.0),
        "Trasporto": (um: "a corpo", qty: 1, val: 40.0),
        "Smaltimento": (um: "a corpo", qty: 1, val: 150.0),
        "Scheda di alimentazione": (um: "pz", qty: 1, val: 0.0),
        "Scheda di controllo": (um: "pz", qty: 1, val: 0.0),
        "Scheda madre": (um: "pz", qty: 1, val: 0.0),
        "Scheda elettronica": (um: "pz", qty: 1, val: 0.0),
        "Inverter": (um: "pz", qty: 1, val: 0.0),
        "Compressore": (um: "pz", qty: 1, val: 0.0),
        "Motore": (um: "pz", qty: 1, val: 0.0),
        "Alimentatore": (um: "pz", qty: 1, val: 0.0),
        "Display": (um: "pz", qty: 1, val: 0.0),
        "Pompa": (um: "pz", qty: 1, val: 0.0),
        "Resistenza": (um: "pz", qty: 1, val: 0.0),
        "Ventola": (um: "pz", qty: 1, val: 0.0),
        "Cavo alimentazione": (um: "ml", qty: 1, val: 0.0),
        "Cablaggio": (um: "a corpo", qty: 1, val: 0.0)
    ]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header con controlli
                HStack {
                    Image(systemName: "tablecells")
                        .foregroundColor(.blue)
                    Text("Voci di costo")
                        .font(.headline)
                    
                    Spacer()
                    
                    Toggle("Diversi per riga", isOn: $diversiPerRiga)
                        .toggleStyle(.switch)
                    
                    Text("Modalità")
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $modalita) {
                        ForEach(modalitaOptions, id: \.self) { mod in
                            Text(mod).tag(mod)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    
                    Button {
                        addVoceCosto()
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                
                if bene.vociCostoArray.isEmpty {
                    Text("Nessuna voce di costo")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                } else {
                    VociCostoTableView(
                        voci: bene.vociCostoArray.sorted { $0.ordine < $1.ordine },
                        deprezzamento: deprezzamento,
                        aliquotaIVA: aliquotaIVA,
                        ivaInclusa: ivaInclusa,
                        determinazioneDanno: determinazioneDanno,
                        modalita: modalita,
                        diversiPerRiga: $diversiPerRiga,
                        descrizioneSuggerimenti: allComponentiDisponibili,
                        onUpdate: { voce in
                            aggiornaCalcoli(voce)
                        },
                        onDelete: { voce in
                            deleteVoceCosto(voce)
                        }
                    )
                }
                
                // Suggerimenti componenti
                if !componentiSuggeriti.isEmpty || showManodoperaSuggestion {
                    Divider()
                    
                    Text("Voci suggerite:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(componentiSuggeriti, id: \.self) { componente in
                                let abbinamento = Self.abbinamentVoci[componente] ?? (um: "pz", qty: 1, val: 0.0)
                                SuggestedVoceCostoRow(
                                    descrizione: componente,
                                    quantita: abbinamento.qty,
                                    valoreUnitario: abbinamento.val,
                                    unitaMisura: abbinamento.um,
                                    onConfirm: {
                                        addVoceCostoFromSuggestion(
                                            descrizione: componente,
                                            quantita: abbinamento.qty,
                                            valoreUnitario: abbinamento.val,
                                            unitaMisura: abbinamento.um
                                        )
                                        componentiSuggeriti.removeAll { $0 == componente }
                                    },
                                    onRemove: {
                                        componentiSuggeriti.removeAll { $0 == componente }
                                    }
                                )
                            }
                            
                            if showManodoperaSuggestion {
                                SuggestedVoceCostoRow(
                                    descrizione: "Manodopera",
                                    quantita: 5,
                                    valoreUnitario: 40,
                                    unitaMisura: "ore",
                                    onConfirm: {
                                        addVoceCostoFromSuggestion(descrizione: "Manodopera", quantita: 5, valoreUnitario: 40, unitaMisura: "ore")
                                        showManodoperaSuggestion = false
                                    },
                                    onRemove: {
                                        showManodoperaSuggestion = false
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .task {
            await loadComponentiSuggeriti()
        }
    }
    
    private func loadComponentiSuggeriti() async {
        guard let path = sinistroPath else { 
            allComponentiDisponibili = commonItemsManager.allComponenti
            filterSuggerimenti()
            return 
        }
        var suggeriti = await commonItemsManager.getComponentiUsedInSinistro(sinistroPath: path)
        
        // Aggiungi componenti da giustificativi (senza duplicati)
        for componente in componentiFromGiustificativi {
            if !suggeriti.contains(where: { $0.localizedCaseInsensitiveCompare(componente) == .orderedSame }) {
                suggeriti.append(componente)
            }
        }
        
        componentiSuggeriti = suggeriti
        allComponentiDisponibili = commonItemsManager.allComponenti
        filterSuggerimenti()
    }
    
    /// Filtra i suggerimenti per escludere voci già presenti nelle voci di stima
    private func filterSuggerimenti() {
        let descrizioniEsistenti = Set(bene.vociCostoArray.map { $0.descrizione.lowercased() })
        
        // Filtra componenti suggeriti
        componentiSuggeriti = componentiSuggeriti.filter { componente in
            !descrizioniEsistenti.contains(componente.lowercased())
        }
        
        // Nascondi suggerimento manodopera se già esiste
        if descrizioniEsistenti.contains("manodopera") {
            showManodoperaSuggestion = false
        }
    }
    
    private func addVoceCosto() {
        let newVoce = VoceCosto(context: viewContext)
        newVoce.id = UUID()
        newVoce.descrizione = "Nuova voce"
        newVoce.unitaMisura = "pz"
        newVoce.quantita = NSDecimalNumber.one
        newVoce.valoreUnitario = NSDecimalNumber.zero
        newVoce.percentualeMigliorie = NSDecimalNumber.zero
        newVoce.percentualeIllesi = NSDecimalNumber.zero
        newVoce.indennizzabile = true
        newVoce.bene = bene
        newVoce.ordine = Int16(bene.vociCostoArray.count)
        
        try? viewContext.save()
    }
    
    private func addVoceCostoFromSuggestion(descrizione: String, quantita: Double, valoreUnitario: Double, unitaMisura: String = "p") {
        let newVoce = VoceCosto(context: viewContext)
        newVoce.id = UUID()
        newVoce.descrizione = descrizione
        newVoce.unitaMisura = unitaMisura
        newVoce.quantita = NSDecimalNumber(value: quantita)
        newVoce.valoreUnitario = NSDecimalNumber(value: valoreUnitario)
        newVoce.totaleANuovo = NSDecimalNumber(value: quantita * valoreUnitario)
        newVoce.percentualeMigliorie = NSDecimalNumber.zero
        newVoce.percentualeIllesi = NSDecimalNumber.zero
        newVoce.nettoMigliorie = newVoce.totaleANuovo
        newVoce.nettoIllesi = newVoce.totaleANuovo
        newVoce.indennizzabile = true
        newVoce.bene = bene
        newVoce.ordine = Int16(bene.vociCostoArray.count)
        
        // Calcola VSU e SI
        let nettoIllesi = newVoce.nettoIllesi?.doubleValue ?? 0
        let vsu = nettoIllesi * (1 - deprezzamento / 100)
        newVoce.vsu = NSDecimalNumber(value: vsu)
        
        let si = calcoliService.calcolaSI(
            nettoIllesi: nettoIllesi,
            vsu: vsu,
            determinazioneDanno: determinazioneDanno
        )
        newVoce.si = NSDecimalNumber(value: si)
        
        try? viewContext.save()
    }
    
    private func aggiornaCalcoli(_ voce: VoceCosto) {
        calcoliService.aggiornaCalcoliVoce(
            voce,
            deprezzamento: NSDecimalNumber(value: deprezzamento),
            determinazioneDanno: determinazioneDanno
        )
        try? viewContext.save()
    }
    
    private func deleteVoceCosto(_ voce: VoceCosto) {
        viewContext.delete(voce)
        try? viewContext.save()
    }
}

// Tabella voci di costo custom
struct VociCostoTableView: View {
    let voci: [VoceCosto]
    let deprezzamento: Double
    let aliquotaIVA: Double
    let ivaInclusa: Bool
    let determinazioneDanno: String
    let modalita: String
    @Binding var diversiPerRiga: Bool
    var descrizioneSuggerimenti: [String] = []
    let onUpdate: (VoceCosto) -> Void
    let onDelete: (VoceCosto) -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    @StateObject private var formulaParser = FormulaParser.shared
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    TableHeaderCell(text: "Descrizione", width: 150)
                    TableHeaderCell(text: "U.M.", width: 60)
                    TableHeaderCell(text: "Qty", width: 80)
                    TableHeaderCell(text: "Unitario", width: 100)
                    TableHeaderCell(text: "Totale a nuovo", width: 100)
                    TableHeaderCell(text: "% Migl.", width: 80)
                    TableHeaderCell(text: "Netto Migl.", width: 100)
                    TableHeaderCell(text: "% Illesi", width: 80)
                    TableHeaderCell(text: "Netto Illesi", width: 100)
                    
                    if diversiPerRiga {
                        TableHeaderCell(text: "Depr.", width: 70)
                        TableHeaderCell(text: "Aliq. IVA", width: 80)
                        TableHeaderCell(text: "IVA", width: 100)
                    }
                    
                    TableHeaderCell(text: "VSU", width: 100)
                    TableHeaderCell(text: "SI", width: 100)
                    TableHeaderCell(text: "Indenn.", width: 50)
                    TableHeaderCell(text: "", width: 40) // Spazio per elimina
                }
                .background(Color(NSColor.controlBackgroundColor))
                .padding(.vertical, 4)
                
                Divider()
                
                // Rows
                ForEach(voci, id: \.id) { voce in
                    VociCostoRowView(
                        voce: voce,
                        deprezzamento: deprezzamento,
                        aliquotaIVA: aliquotaIVA,
                        ivaInclusa: ivaInclusa,
                        determinazioneDanno: determinazioneDanno,
                        modalita: modalita,
                        diversiPerRiga: $diversiPerRiga,
                        descrizioneSuggerimenti: descrizioneSuggerimenti,
                        onUpdate: onUpdate,
                        onDelete: onDelete
                    )
                    Divider()
                }
            }
        }
    }
}

struct TableHeaderCell: View {
    let text: String
    let width: CGFloat
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct VociCostoRowView: View {
    @ObservedObject var voce: VoceCosto
    let deprezzamento: Double
    let aliquotaIVA: Double
    let ivaInclusa: Bool
    let determinazioneDanno: String
    let modalita: String
    @Binding var diversiPerRiga: Bool
    var descrizioneSuggerimenti: [String] = []
    let onUpdate: (VoceCosto) -> Void
    let onDelete: (VoceCosto) -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var formulaParser = FormulaParser.shared
    @StateObject private var calcoliService = CalcoliService.shared
    @State private var deprezzamentoRiga: Double = 20.0
    @State private var aliquotaIVARiga: Double = 22.0
    @State private var showDescrizioneSuggestions: Bool = false
    @State private var descrizioneFiltrata: [String] = []
    
    var body: some View {
        HStack(spacing: 0) {
            TextField("Descrizione", text: createDescrizioneBinding())
                .textFieldStyle(.plain)
                .frame(width: 150, alignment: .leading)
                .padding(.horizontal, 4)
            
            Picker("", selection: createUnitaMisuraBinding()) {
                ForEach(VociCostoView.unitaMisuraOptions, id: \.self) { um in
                    Text(um).tag(um)
                }
            }
            .labelsHidden()
            .frame(width: 60)
            
            TextField("Qty", text: createQuantitaBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 80, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("Unit.", text: createValoreUnitarioBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("Tot. nuovo", text: createTotaleANuovoBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("% Migl.", text: createPercentualeMigliorieBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 80, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("Netto Migl.", text: createNettoMigliorieBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("% Illesi", text: createPercentualeIllesiBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 80, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("Netto Illesi", text: createNettoIllesiBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            if diversiPerRiga {
                TextField("Depr.", text: createDeprezzamentoRigaBinding())
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70, alignment: .trailing)
                    .padding(.horizontal, 4)
                
                TextField("IVA%", text: createAliquotaIVARigaBinding())
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80, alignment: .trailing)
                    .padding(.horizontal, 4)
                
                Text(CurrencyFormatter.shared.formatWithSymbol(calcolaIVARiga()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                    .padding(.horizontal, 4)
            }
            
            TextField("VSU", text: createVSUBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            TextField("SI", text: createSIBinding())
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 4)
            
            Toggle("", isOn: createIndennizzabileBinding())
                .labelsHidden()
                .frame(width: 50)
            
            Button {
                onDelete(voce)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
        }
        .padding(.vertical, 2)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            deprezzamentoRiga = deprezzamento
            aliquotaIVARiga = aliquotaIVA
        }
    }
    
    private func calcolaIVARiga() -> Double {
        let nettoIllesi = voce.nettoIllesi?.doubleValue ?? 0
        let deprezzamento = diversiPerRiga ? deprezzamentoRiga : self.deprezzamento
        let vsu = nettoIllesi * (1 - deprezzamento / 100)
        let aliquota = diversiPerRiga ? aliquotaIVARiga : self.aliquotaIVA
        return vsu * (aliquota / 100)
    }
    
    private func createDescrizioneBinding() -> Binding<String> {
        Binding(
            get: { voce.descrizione },
            set: { 
                voce.descrizione = $0
                onUpdate(voce)
            }
        )
    }
    
    private func createUnitaMisuraBinding() -> Binding<String> {
        Binding(
            get: { voce.unitaMisura },
            set: { 
                voce.unitaMisura = $0
                try? viewContext.save()
            }
        )
    }
    
    private func createDeprezzamentoRigaBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(NSDecimalNumber(value: deprezzamentoRiga)) },
            set: { 
                if let val = parseItalian($0) {
                    deprezzamentoRiga = val.doubleValue
                    calcolaVSUeSI()
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createAliquotaIVARigaBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(NSDecimalNumber(value: aliquotaIVARiga)) },
            set: { 
                if let val = parseItalian($0) {
                    aliquotaIVARiga = val.doubleValue
                    calcolaVSUeSI()
                    onUpdate(voce)
                }
            }
        )
    }
    
    // Formatter italiano per numeri con decimali
    private var italianNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    private func formatItalian(_ value: NSDecimalNumber?) -> String {
        guard let value = value else { return "0,00" }
        return italianNumberFormatter.string(from: value) ?? "0,00"
    }
    
    private func parseItalian(_ string: String) -> NSDecimalNumber? {
        // Sostituisce virgola con punto per il parsing
        let normalized = string.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        let val = NSDecimalNumber(string: normalized)
        return val != NSDecimalNumber.notANumber ? val : nil
    }
    
    private func createQuantitaBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.quantita) },
            set: { 
                if let val = parseItalian($0) {
                    voce.quantita = val
                    if modalita == "Normale" {
                        calcolaNormale()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createValoreUnitarioBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.valoreUnitario) },
            set: { 
                if let val = parseItalian($0) {
                    voce.valoreUnitario = val
                    if modalita == "Normale" {
                        calcolaNormale()
                    } else if modalita == "Inverso" {
                        calcolaInverso()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createTotaleANuovoBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.totaleANuovo) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("totaleANuovo", value: true)
                }
                if let val = parseItalian($0) {
                    voce.totaleANuovo = val
                    if modalita == "Inverso" {
                        calcolaInverso()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createPercentualeMigliorieBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.percentualeMigliorie) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("percentualeMigliorie", value: true)
                }
                if let val = parseItalian($0) {
                    voce.percentualeMigliorie = val
                    if modalita == "Normale" {
                        calcolaNormale()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createNettoMigliorieBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.nettoMigliorie) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("nettoMigliorie", value: true)
                }
                if let val = parseItalian($0) {
                    voce.nettoMigliorie = val
                    if modalita == "Inverso" {
                        calcolaInverso()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createPercentualeIllesiBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.percentualeIllesi) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("percentualeIllesi", value: true)
                }
                if let val = parseItalian($0) {
                    voce.percentualeIllesi = val
                    if modalita == "Normale" {
                        calcolaNormale()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createNettoIllesiBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.nettoIllesi) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("nettoIllesi", value: true)
                }
                if let val = parseItalian($0) {
                    voce.nettoIllesi = val
                    if modalita == "Inverso" {
                        calcolaInverso()
                    }
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createVSUBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.vsu) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("vsu", value: true)
                }
                if let val = parseItalian($0) {
                    voce.vsu = val
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createSIBinding() -> Binding<String> {
        Binding(
            get: { formatItalian(voce.si) },
            set: { 
                if modalita == "Forzatura" {
                    voce.setForzato("si", value: true)
                }
                if let val = parseItalian($0) {
                    voce.si = val
                    onUpdate(voce)
                }
            }
        )
    }
    
    private func createIndennizzabileBinding() -> Binding<Bool> {
        Binding(
            get: { voce.indennizzabile },
            set: { 
                voce.indennizzabile = $0
                try? viewContext.save()
            }
        )
    }
    
    private func createContext() -> [String: NSDecimalNumber] {
        return [:]
    }
    
    // Calcolo modalità Normale
    private func calcolaNormale() {
        let quantita = voce.quantita.doubleValue
        let valoreUnitario = voce.valoreUnitario.doubleValue
        let totaleANuovo = quantita * valoreUnitario
        
        voce.totaleANuovo = NSDecimalNumber(value: totaleANuovo)
        
        let percentualeMigliorie = voce.percentualeMigliorie?.doubleValue ?? 0
        let nettoMigliorie = totaleANuovo * (1 - percentualeMigliorie / 100)
        voce.nettoMigliorie = NSDecimalNumber(value: nettoMigliorie)
        
        let percentualeIllesi = voce.percentualeIllesi?.doubleValue ?? 0
        let nettoIllesi = nettoMigliorie * (1 - percentualeIllesi / 100)
        voce.nettoIllesi = NSDecimalNumber(value: nettoIllesi)
        
        calcolaVSUeSI()
    }
    
    // Calcolo modalità Inverso
    private func calcolaInverso() {
        let quantita = voce.quantita.doubleValue
        
        // Se ho totale a nuovo e quantità, calcolo valore unitario
        if let totaleANuovo = voce.totaleANuovo, quantita > 0 {
            let valoreUnitario = totaleANuovo.doubleValue / quantita
            voce.valoreUnitario = NSDecimalNumber(value: valoreUnitario)
        }
        
        // Se ho netto migliorie e totale a nuovo, calcolo percentuale migliorie
        if let nettoMigliorie = voce.nettoMigliorie, let totaleANuovo = voce.totaleANuovo, totaleANuovo.doubleValue > 0 {
            let percentualeMigliorie = (1 - nettoMigliorie.doubleValue / totaleANuovo.doubleValue) * 100
            voce.percentualeMigliorie = NSDecimalNumber(value: percentualeMigliorie)
        }
        
        // Se ho netto illesi e netto migliorie, calcolo percentuale illesi
        if let nettoIllesi = voce.nettoIllesi, let nettoMigliorie = voce.nettoMigliorie, nettoMigliorie.doubleValue > 0 {
            let percentualeIllesi = (1 - nettoIllesi.doubleValue / nettoMigliorie.doubleValue) * 100
            voce.percentualeIllesi = NSDecimalNumber(value: percentualeIllesi)
        }
        
        calcolaVSUeSI()
    }
    
    private func calcolaVSUeSI() {
        let nettoIllesi = voce.nettoIllesi?.doubleValue ?? 0
        let deprezzamento = diversiPerRiga ? deprezzamentoRiga : self.deprezzamento
        let vsu = nettoIllesi * (1 - deprezzamento / 100)
        voce.vsu = NSDecimalNumber(value: vsu)
        
        // Calcolo SI in base alla determinazione danno
        let si = calcoliService.calcolaSI(
            nettoIllesi: nettoIllesi,
            vsu: vsu,
            determinazioneDanno: determinazioneDanno
        )
        voce.si = NSDecimalNumber(value: si)
    }
}

// Campo editabile con supporto formule e indicatore forzato
struct EditableField: View {
    @Binding var value: String
    let isEditable: Bool
    let isForzato: Bool
    let context: [String: NSDecimalNumber]
    
    @StateObject private var formulaParser = FormulaParser.shared
    
    var body: some View {
        HStack(spacing: 2) {
            if isEditable {
                FormulaTextField(value: $value, context: context)
            } else {
                Text(value)
                    .foregroundColor(.secondary)
            }
            
            if isForzato {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }
        }
    }
}

// TextField con supporto formule excel-like
struct FormulaTextField: View {
    @Binding var value: String
    let context: [String: NSDecimalNumber]
    @StateObject private var formulaParser = FormulaParser.shared
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: $value)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onChange(of: value) { newValue in
                if newValue.hasPrefix("=") {
                    // Valuta la formula
                    if let result = formulaParser.evaluateFormula(newValue, context: context) {
                        value = result.stringValue
                    }
                }
            }
    }
}
