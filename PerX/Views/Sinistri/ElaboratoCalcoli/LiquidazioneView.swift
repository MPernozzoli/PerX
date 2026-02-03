import SwiftUI
import CoreData

struct VocePersonalizzata: Identifiable, Codable, Equatable {
    let id: UUID
    var descrizione: String
    var valore: Double
    
    init(id: UUID = UUID(), descrizione: String, valore: Double) {
        self.id = id
        self.descrizione = descrizione
        self.valore = valore
    }
}

struct LiquidazioneView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    
    @State private var massimalePrimaFranchigia: Bool = false
    @State private var showArrotondamentoField: Bool = false
    @State private var arrotondamentoManuale: String = ""
    @State private var vociPersonalizzate: [VocePersonalizzata] = []
    @State private var showAggiungiVoceSheet: Bool = false
    @State private var nuovaVoceDescrizione: String = ""
    @State private var nuovaVoceValore: String = ""
    
    private var riepilogo: RiepilogoLiquidazione {
        calcoliService.calcolaRiepilogoLiquidazione(
            perizia: perizia,
            massimalePrimaFranchigia: massimalePrimaFranchigia
        )
    }
    
    private var arrotondamento: Double {
        perizia.arrotondamentoLiquidazione?.doubleValue ?? 0
    }
    
    private var totaleVociPersonalizzate: Double {
        vociPersonalizzate.reduce(0) { $0 + $1.valore }
    }
    
    private var dannoArrotondato: Double {
        riepilogo.dannoIndennizzabileTotale + arrotondamento + totaleVociPersonalizzate
    }
    
    private var isUnicaGaranzia: Bool {
        riepilogo.risultatiPerGaranzia.count == 1
    }
    
    private var vociPersonalizzatePerCard: [VocePersonalizzata] {
        isUnicaGaranzia ? vociPersonalizzate : []
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()
            garanzieListView
            if riepilogo.risultatiPerGaranzia.count > 1 {
                Divider()
                totaliComplessiviView
            }
        }
        .padding(16)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "eurosign.circle.fill")
                .foregroundColor(.green)
            Text("Riepilogo Liquidazione")
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            Toggle("Massimale prima franchigia", isOn: $massimalePrimaFranchigia)
                .toggleStyle(.switch)
                .font(.caption)
        }
    }
    
    private var garanzieListView: some View {
        ForEach(riepilogo.risultatiPerGaranzia, id: \.garanzia.id) { risultato in
            garanziaCard(for: risultato)
        }
    }
    
    private func garanziaCard(for risultato: LiquidazioneResult) -> some View {
        GaranziaLiquidazioneCard(
            risultato: risultato,
            perizia: perizia,
            mostraArrotondamento: isUnicaGaranzia,
            arrotondamento: arrotondamento,
            dannoArrotondato: dannoArrotondato,
            showArrotondamentoField: $showArrotondamentoField,
            arrotondamentoManuale: $arrotondamentoManuale,
            vociPersonalizzate: vociPersonalizzatePerCard,
            showAggiungiVoceSheet: isUnicaGaranzia ? $showAggiungiVoceSheet : .constant(false),
            onArrotondaUnita: arrotondaUnita,
            onArrotondaDecina: arrotondaDecina,
            onApplicaArrotondamento: applicaArrotondamentoManuale,
            onCancellaArrotondamento: cancellaArrotondamento,
            onRimuoviVoce: rimuoviVocePersonalizzata
        )
    }
    
    private func rimuoviVocePersonalizzata(_ id: UUID) {
        vociPersonalizzate.removeAll { $0.id == id }
        salvaVociPersonalizzate()
    }
    
    private func caricaVociPersonalizzate() {
        guard let json = perizia.vociPersonalizzateJSON,
              let data = json.data(using: .utf8),
              let voci = try? JSONDecoder().decode([VocePersonalizzata].self, from: data) else {
            vociPersonalizzate = []
            return
        }
        vociPersonalizzate = voci
    }
    
    private func salvaVociPersonalizzate() {
        if let data = try? JSONEncoder().encode(vociPersonalizzate),
           let json = String(data: data, encoding: .utf8) {
            perizia.vociPersonalizzateJSON = json
            try? viewContext.save()
        }
    }
    
    var body: some View {
        GroupBox {
            contentView
        }
        .backgroundStyle(.regularMaterial)
        .onChange(of: dannoArrotondato) { _, newValue in
            // Salva il valore calcolato nella perizia
            perizia.stimaDannoIndennizzabile = NSDecimalNumber(value: newValue)
            try? viewContext.save()
        }
        .onChange(of: massimalePrimaFranchigia) { _, _ in
            // Ricalcola e salva quando cambia massimalePrimaFranchigia
            let nuovoValore = dannoArrotondato
            perizia.stimaDannoIndennizzabile = NSDecimalNumber(value: nuovoValore)
            try? viewContext.save()
        }
        .onChange(of: vociPersonalizzate) { _, _ in
            salvaVociPersonalizzate()
        }
        .onAppear {
            caricaVociPersonalizzate()
        }
        .sheet(isPresented: $showAggiungiVoceSheet) {
            AggiungiVocePersonalizzataSheet(
                descrizione: $nuovaVoceDescrizione,
                valore: $nuovaVoceValore,
                onAggiungi: {
                    let valoreNormalizzato = nuovaVoceValore
                        .replacingOccurrences(of: "€", with: "")
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                        .trimmingCharacters(in: .whitespaces)
                    
                    if let valore = Double(valoreNormalizzato) {
                        let nuovaVoce = VocePersonalizzata(
                            descrizione: nuovaVoceDescrizione,
                            valore: valore
                        )
                        vociPersonalizzate.append(nuovaVoce)
                        salvaVociPersonalizzate()
                        nuovaVoceDescrizione = ""
                        nuovaVoceValore = ""
                        showAggiungiVoceSheet = false
                    }
                }
            )
        }
    }
    
    // MARK: - Valori con IVA ripartita per riepilogo complessivo
    
    private var mostraValoriConIVARiepilogo: Bool {
        riepilogo.risultatiPerGaranzia.allSatisfy { $0.mostraValoriConIvaRipartita }
    }
    
    private var proporzioneVSURiepilogo: Double {
        let totale = riepilogo.totaleVSU + riepilogo.totaleSI
        return totale > 0 ? riepilogo.totaleVSU / totale : 0
    }
    
    private var vsuConIVARiepilogo: Double {
        riepilogo.totaleVSU + (riepilogo.totaleIVA * proporzioneVSURiepilogo)
    }
    
    private var siConIVARiepilogo: Double {
        riepilogo.totaleSI + (riepilogo.totaleIVA * (1 - proporzioneVSURiepilogo))
    }
    
    private var totaliComplessiviView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOTALE COMPLESSIVO")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    HStack(spacing: 4) {
                        Text("Totale VSU:")
                        if mostraValoriConIVARiepilogo {
                            Text("(IVA incl.)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.formatWithSymbol(mostraValoriConIVARiepilogo ? vsuConIVARiepilogo : riepilogo.totaleVSU))
                        .fontWeight(.medium)
                }
                GridRow {
                    HStack(spacing: 4) {
                        Text("Totale SI:")
                        if mostraValoriConIVARiepilogo {
                            Text("(IVA incl.)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.formatWithSymbol(mostraValoriConIVARiepilogo ? siConIVARiepilogo : riepilogo.totaleSI))
                        .fontWeight(.medium)
                }
                // IVA separata solo se ripristini NON ultimati (va a saldo)
                if riepilogo.totaleIVA > 0 && !mostraValoriConIVARiepilogo {
                    GridRow {
                        Text("+ IVA (a saldo):")
                            .foregroundColor(.orange)
                        Text(CurrencyFormatter.shared.formatWithSymbol(riepilogo.totaleIVA))
                            .foregroundColor(.orange)
                    }
                }
                Divider().gridCellColumns(2)
                
                // Voci personalizzate
                GridRow {
                    HStack {
                        Text("Voci personalizzate:")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            nuovaVoceDescrizione = ""
                            nuovaVoceValore = ""
                            showAggiungiVoceSheet = true
                        } label: {
                            Label("Aggiungi", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .gridCellColumns(2)
                
                if !vociPersonalizzate.isEmpty {
                    ForEach(vociPersonalizzate) { voce in
                        GridRow {
                            HStack(spacing: 8) {
                                Text(voce.descrizione)
                                    .foregroundColor(.secondary)
                                Button {
                                    vociPersonalizzate.removeAll { $0.id == voce.id }
                                    salvaVociPersonalizzate()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(CurrencyFormatter.shared.formatWithSymbol(voce.valore))
                                .foregroundColor(voce.valore >= 0 ? .green : .red)
                        }
                    }
                    Divider().gridCellColumns(2)
                }
                
                GridRow {
                    Text("Danno indennizzabile:")
                    .font(.headline)
                    Text(CurrencyFormatter.shared.formatWithSymbol(riepilogo.dannoIndennizzabileTotale))
                        .font(.headline)
                        .foregroundColor(arrotondamento != 0 ? .secondary : .green)
                        .strikethrough(arrotondamento != 0)
                }
                
                // Voci personalizzate
                if !vociPersonalizzate.isEmpty {
                    Divider().gridCellColumns(2)
                    ForEach(vociPersonalizzate) { voce in
                        GridRow {
                            HStack(spacing: 8) {
                                Text(voce.descrizione)
                                    .foregroundColor(.secondary)
                                Button {
                                    vociPersonalizzate.removeAll { $0.id == voce.id }
                                    salvaVociPersonalizzate()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(CurrencyFormatter.shared.formatWithSymbol(voce.valore))
                                .foregroundColor(voce.valore >= 0 ? .green : .red)
                        }
                    }
                }
                
                // Arrotondamento
                arrotondamentoView
                
                // === DANNO NON INDENNIZZABILE TOTALE ===
                if riepilogo.haVociNonIndennizzabili && !riepilogo.tuttoNonIndennizzabile {
                    Divider().gridCellColumns(2)
                    
                    GridRow {
                        Text("NON INDENNIZZABILE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    .gridCellColumns(2)
                    
                    GridRow {
                        Text("Totale VSU (non riconosciuto):")
                            .foregroundColor(.red.opacity(0.7))
                        Text(CurrencyFormatter.shared.formatWithSymbol(riepilogo.totaleVSUNonIndennizzabile))
                            .foregroundColor(.red)
                    }
                    
                    if riepilogo.totaleSINonIndennizzabile > 0 {
                        GridRow {
                            Text("Totale SI (non riconosciuto):")
                                .foregroundColor(.red.opacity(0.7))
                            Text(CurrencyFormatter.shared.formatWithSymbol(riepilogo.totaleSINonIndennizzabile))
                                .foregroundColor(.red)
                        }
                    }
                    
                    GridRow {
                        Text("Danno non riconosciuto:")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(CurrencyFormatter.shared.formatWithSymbol(riepilogo.dannoNonIndennizzabileTotale))
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(riepilogo.tuttoNonIndennizzabile ? Color.red.opacity(0.05) : Color.green.opacity(0.05)))
    }
    
    @ViewBuilder
    private var arrotondamentoView: some View {
        GridRow {
            Text("Indennizzabile (arrotondato):")
                .font(.headline)
            
            HStack(spacing: 4) {
                if showArrotondamentoField {
                    // Campo inline per forzatura
                    TextField("€", text: $arrotondamentoManuale)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .font(.headline)
                        .onSubmit { 
                            applicaArrotondamentoManuale()
                            showArrotondamentoField = false
                        }
                    
                    Button {
                        applicaArrotondamentoManuale()
                        showArrotondamentoField = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showArrotondamentoField = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Chevron giù decina
                    Button { arrotondaDecina(giu: true) } label: {
                        Image(systemName: "chevron.down.2")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Arrotonda alla decina inferiore")
                    
                    // Chevron giù unità
                    Button { arrotondaUnita(giu: true) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Arrotonda all'unità inferiore")
                    
                    // Importo al centro
                    Text(CurrencyFormatter.shared.formatWithSymbol(dannoArrotondato))
                        .font(.headline)
                        .foregroundColor(arrotondamento != 0 ? .orange : .green)
                    
                    // Variazione se arrotondato
                    if arrotondamento != 0 {
                        Text("(\(arrotondamento >= 0 ? "+" : "")\(CurrencyFormatter.shared.format(arrotondamento)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.light)
                    }
                    
                    // Chevron su unità
                    Button { arrotondaUnita(giu: false) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Arrotonda all'unità superiore")
                    
                    // Chevron su decina
                    Button { arrotondaDecina(giu: false) } label: {
                        Image(systemName: "chevron.up.2")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Arrotonda alla decina superiore")
                    
                    // Matita per input manuale
                    Button {
                        arrotondamentoManuale = CurrencyFormatter.shared.format(dannoArrotondato)
                        showArrotondamentoField = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Imposta importo manuale")
                    
                    // X per cancellare arrotondamento
                    if arrotondamento != 0 {
                        Button { cancellaArrotondamento() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Rimuovi arrotondamento")
                    }
                }
            }
        }
        
        GridRow {
            Text("Liquidazione:")
                .font(.headline)
            Text(CurrencyFormatter.shared.formatWithSymbol(dannoArrotondato))
                .font(.headline)
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Funzioni arrotondamento
    
    private func arrotondaUnita(giu: Bool) {
        let danno = riepilogo.dannoIndennizzabileTotale
        let arrotondato = giu ? floor(danno) : ceil(danno)
        let nuovoArrotondamento = arrotondato - danno
        perizia.arrotondamentoLiquidazione = NSDecimalNumber(value: nuovoArrotondamento)
        try? viewContext.save()
    }
    
    private func arrotondaDecina(giu: Bool) {
        let danno = riepilogo.dannoIndennizzabileTotale
        let arrotondato = giu ? floor(danno / 10) * 10 : ceil(danno / 10) * 10
        let nuovoArrotondamento = arrotondato - danno
        perizia.arrotondamentoLiquidazione = NSDecimalNumber(value: nuovoArrotondamento)
        try? viewContext.save()
    }
    
    private func applicaArrotondamentoManuale() {
        let normalized = arrotondamentoManuale
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        
        guard let target = Double(normalized) else { return }
        let nuovoArrotondamento = target - riepilogo.dannoIndennizzabileTotale
        perizia.arrotondamentoLiquidazione = NSDecimalNumber(value: nuovoArrotondamento)
        try? viewContext.save()
    }
    
    private func cancellaArrotondamento() {
        perizia.arrotondamentoLiquidazione = nil
        showArrotondamentoField = false
        try? viewContext.save()
    }
}

struct GaranziaLiquidazioneCard: View {
    let risultato: LiquidazioneResult
    let perizia: Perizia
    
    // Per arrotondamento in caso di singola garanzia
    var mostraArrotondamento: Bool = false
    var arrotondamento: Double = 0
    var dannoArrotondato: Double = 0
    @Binding var showArrotondamentoField: Bool
    @Binding var arrotondamentoManuale: String
    var vociPersonalizzate: [VocePersonalizzata] = []
    @Binding var showAggiungiVoceSheet: Bool
    var onArrotondaUnita: ((Bool) -> Void)?
    var onArrotondaDecina: ((Bool) -> Void)?
    var onApplicaArrotondamento: (() -> Void)?
    var onCancellaArrotondamento: (() -> Void)?
    var onRimuoviVoce: ((UUID) -> Void)?
    
    // Init senza arrotondamento (per retrocompatibilità)
    init(risultato: LiquidazioneResult, perizia: Perizia) {
        self.risultato = risultato
        self.perizia = perizia
        self.mostraArrotondamento = false
        self.arrotondamento = 0
        self.dannoArrotondato = 0
        self._showArrotondamentoField = .constant(false)
        self._arrotondamentoManuale = .constant("")
        self.vociPersonalizzate = []
        self._showAggiungiVoceSheet = .constant(false)
    }
    
    // Init con arrotondamento (per singola garanzia)
    init(
        risultato: LiquidazioneResult,
        perizia: Perizia,
        mostraArrotondamento: Bool,
        arrotondamento: Double,
        dannoArrotondato: Double,
        showArrotondamentoField: Binding<Bool>,
        arrotondamentoManuale: Binding<String>,
        vociPersonalizzate: [VocePersonalizzata],
        showAggiungiVoceSheet: Binding<Bool>,
        onArrotondaUnita: @escaping (Bool) -> Void,
        onArrotondaDecina: @escaping (Bool) -> Void,
        onApplicaArrotondamento: @escaping () -> Void,
        onCancellaArrotondamento: @escaping () -> Void,
        onRimuoviVoce: @escaping (UUID) -> Void
    ) {
        self.risultato = risultato
        self.perizia = perizia
        self.mostraArrotondamento = mostraArrotondamento
        self.arrotondamento = arrotondamento
        self.dannoArrotondato = dannoArrotondato
        self._showArrotondamentoField = showArrotondamentoField
        self._arrotondamentoManuale = arrotondamentoManuale
        self.vociPersonalizzate = vociPersonalizzate
        self._showAggiungiVoceSheet = showAggiungiVoceSheet
        self.onArrotondaUnita = onArrotondaUnita
        self.onArrotondaDecina = onArrotondaDecina
        self.onApplicaArrotondamento = onApplicaArrotondamento
        self.onCancellaArrotondamento = onCancellaArrotondamento
        self.onRimuoviVoce = onRimuoviVoce
    }
    
    // Ottiene le partite associate a questa garanzia
    private var partiteGaranzia: [Partita] {
        perizia.partiteArray.filter { partita in
            partita.beniArray.contains { $0.garanzia?.id == risultato.garanzia.id }
        }
    }
    
    // MARK: - IVA ripartita tra VSU e SI (quando riconosciuta in liquidazione)
    
    /// Proporzione VSU sul totale imponibile
    private var proporzioneVSU: Double {
        let totale = risultato.totaleVSU + risultato.totaleSI
        return totale > 0 ? risultato.totaleVSU / totale : 0
    }
    
    /// IVA quota VSU
    private var ivaQuotaVSU: Double {
        risultato.iva * proporzioneVSU
    }
    
    /// IVA quota SI
    private var ivaQuotaSI: Double {
        risultato.iva * (1 - proporzioneVSU)
    }
    
    /// VSU con IVA inclusa (quando iva > 0)
    private var vsuConIVA: Double {
        risultato.totaleVSU + ivaQuotaVSU
    }
    
    /// SI con IVA inclusa (quando iva > 0)
    private var siConIVA: Double {
        risultato.totaleSI + ivaQuotaSI
    }
    
    /// VSU per partita con IVA ripartita
    private func vsuPartitaConIVA(_ partitaId: UUID) -> Double {
        let vsuPartita = risultato.vsuPerPartita[partitaId] ?? 0
        if risultato.iva > 0 && risultato.totaleVSU > 0 {
            let proporzionePartita = vsuPartita / risultato.totaleVSU
            return vsuPartita + (ivaQuotaVSU * proporzionePartita)
        }
        return vsuPartita
    }
    
    /// SI per partita con IVA ripartita
    private func siPartitaConIVA(_ partitaId: UUID) -> Double {
        let siPartita = risultato.siPerPartita[partitaId] ?? 0
        if risultato.iva > 0 && risultato.totaleSI > 0 {
            let proporzionePartita = siPartita / risultato.totaleSI
            return siPartita + (ivaQuotaSI * proporzionePartita)
        }
        return siPartita
    }
    
    /// True se mostriamo valori con IVA inclusa (condizioni: riconosciIVA + ripristiniUltimati + richiestaIvaInclusa)
    private var mostraValoriConIVA: Bool {
        risultato.mostraValoriConIvaRipartita
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.blue)
                Text(risultato.garanzia.nomeEditabile)
                    .font(.headline)
                Spacer()
                if risultato.massimale > 0 {
                    Text("Max: \(CurrencyFormatter.shared.formatWithSymbol(risultato.massimale))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                // VSU per partita (con IVA inclusa se ripristini ultimati e IVA riconosciuta)
                HStack(spacing: 4) {
                    Text("VSU")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    if mostraValoriConIVA {
                        Text("(IVA incl.)")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .gridCellColumns(2)
                
                ForEach(partiteGaranzia) { partita in
                    let vsu = mostraValoriConIVA ? vsuPartitaConIVA(partita.wrappedId) : (risultato.vsuPerPartita[partita.wrappedId] ?? 0)
                    if vsu > 0 {
                        GridRow {
                            Text("  \(partita.nomeEditabile)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(vsu))
                                .font(.caption)
                        }
                    }
                }
                
                GridRow {
                    Text("Totale VSU:")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    Text(CurrencyFormatter.shared.formatWithSymbol(mostraValoriConIVA ? vsuConIVA : risultato.totaleVSU))
                        .fontWeight(.medium)
                }
                
                // SI per partita (con IVA inclusa se ripristini ultimati e IVA riconosciuta)
                let siTotale = mostraValoriConIVA ? siConIVA : risultato.totaleSI
                if siTotale > 0 {
                    HStack(spacing: 4) {
                        Text("SI")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        if mostraValoriConIVA {
                            Text("(IVA incl.)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .gridCellColumns(2)
                    .padding(.top, 4)
                    
                    ForEach(partiteGaranzia) { partita in
                        let si = mostraValoriConIVA ? siPartitaConIVA(partita.wrappedId) : (risultato.siPerPartita[partita.wrappedId] ?? 0)
                        if si > 0 {
                            GridRow {
                                Text("  \(partita.nomeEditabile)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(CurrencyFormatter.shared.formatWithSymbol(si))
                                    .font(.caption)
                            }
                        }
                    }
                    
                    GridRow {
                        Text("Totale SI:")
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        Text(CurrencyFormatter.shared.formatWithSymbol(mostraValoriConIVA ? siConIVA : risultato.totaleSI))
                            .fontWeight(.medium)
                    }
                }
                
                // Franchigia/Scoperto
                if risultato.franchigia > 0 {
                    GridRow {
                        Text("- Franchigia:")
                            .foregroundColor(.red)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.franchigia))
                            .foregroundColor(.red)
                    }
                }
                if risultato.scoperto > 0 {
                    GridRow {
                        Text("- Scoperto:")
                            .foregroundColor(.red)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.scoperto))
                            .foregroundColor(.red)
                    }
                }
                
                Divider().gridCellColumns(2)
                
                // Voci personalizzate (solo per singola garanzia)
                if mostraArrotondamento {
                    GridRow {
                        HStack {
                            Text("Voci personalizzate:")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                showAggiungiVoceSheet = true
                            } label: {
                                Label("Aggiungi", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .gridCellColumns(2)
                    
                    if !vociPersonalizzate.isEmpty {
                        ForEach(vociPersonalizzate) { voce in
                            GridRow {
                                HStack(spacing: 8) {
                                    Text(voce.descrizione)
                                        .foregroundColor(.secondary)
                                    Button {
                                        onRimuoviVoce?(voce.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(CurrencyFormatter.shared.formatWithSymbol(voce.valore))
                                    .foregroundColor(voce.valore >= 0 ? .green : .red)
                            }
                        }
                        Divider().gridCellColumns(2)
                    }
                }
                
                // Risultato finale
                if !risultato.ripristiniUltimati {
                    // SI a saldo: mostra solo VSU come liquidazione immediata
                    GridRow {
                        Text("Liquidazione (solo VSU):")
                            .fontWeight(.semibold)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.liquidazioneVSU))
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    // SI a saldo
                    GridRow {
                        Text("SI a saldo:")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.totaleSI))
                            .font(.caption)
                    }
                    
                    // IVA a saldo (se riconosciuta)
                    if risultato.ivaASaldo > 0 {
                        GridRow {
                            Text("IVA a saldo:")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(CurrencyFormatter.shared.formatWithSymbol(risultato.ivaASaldo))
                                .font(.caption)
                        }
                    }
                    
                    // Totale a saldo
                    GridRow {
                        Text("Totale a saldo:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.liquidazioneSI))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                } else {
                    // Ripristini ultimati: mostra indennizzabile completo
                    // Nota: IVA già inclusa in VSU e SI quando mostraValoriConIVA = true
                    
                    if mostraArrotondamento {
                        // Arrotondamento inline per singola garanzia
                        GridRow {
                            Text("Indennizzabile\(arrotondamento != 0 ? " (arrotondato)" : ""):")
                                .fontWeight(.semibold)
                            
                            // HStack che allinea tutto a destra, con controlli centrati intorno all'importo
                            HStack(alignment: .center, spacing: 4) {
                                if showArrotondamentoField {
                                    Spacer()
                                    TextField("€", text: $arrotondamentoManuale)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                        .font(.headline)
                                        .onSubmit {
                                            onApplicaArrotondamento?()
                                            showArrotondamentoField = false
                                        }
                                    
                                    Button {
                                        onApplicaArrotondamento?()
                                        showArrotondamentoField = false
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.green)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        showArrotondamentoField = false
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Spacer()
                                    
                                    // Controlli a sinistra dell'importo
                                    Button { onArrotondaDecina?(true) } label: {
                                        Image(systemName: "chevron.down.2")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
                                    Button { onArrotondaUnita?(true) } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
                                    // Importo al centro
                                    Text(CurrencyFormatter.shared.formatWithSymbol(dannoArrotondato))
                                        .fontWeight(.semibold)
                                        .foregroundColor(arrotondamento != 0 ? .orange : .green)
                                    
                                    if arrotondamento != 0 {
                                        Text("(\(arrotondamento >= 0 ? "+" : "")\(CurrencyFormatter.shared.format(arrotondamento)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fontWeight(.light)
                                    }
                                    
                                    // Controlli a destra dell'importo
                                    Button { onArrotondaUnita?(false) } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
                                    Button { onArrotondaDecina?(false) } label: {
                                        Image(systemName: "chevron.up.2")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
                                    Button {
                                        arrotondamentoManuale = CurrencyFormatter.shared.format(dannoArrotondato)
                                        showArrotondamentoField = true
                                    } label: {
                                        Image(systemName: "pencil.circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if arrotondamento != 0 {
                                        Button { onCancellaArrotondamento?() } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } else {
                        GridRow {
                            Text(risultato.tuttoNonIndennizzabile ? "Riserva:" : "Indennizzabile:")
                                .fontWeight(.semibold)
                            Text(CurrencyFormatter.shared.formatWithSymbol(risultato.tuttoNonIndennizzabile ? risultato.dannoNonIndennizzabile : risultato.dannoIndennizzabile))
                                .fontWeight(.semibold)
                                .foregroundColor(risultato.tuttoNonIndennizzabile ? .red : .green)
                        }
                    }
                }
                
                // === DANNO NON INDENNIZZABILE (parziale) ===
                if risultato.haVociNonIndennizzabili && !risultato.tuttoNonIndennizzabile {
                    Divider().gridCellColumns(2)
                    
                    Text("NON INDENNIZZABILE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .gridCellColumns(2)
                    
                    // Dettaglio VSU non indennizzabile per partita
                    ForEach(partiteGaranzia) { partita in
                        let vsuNonInd = risultato.vsuNonIndennizzabilePerPartita[partita.wrappedId] ?? 0
                        let siNonInd = risultato.siNonIndennizzabilePerPartita[partita.wrappedId] ?? 0
                        let totalePartita = vsuNonInd + siNonInd
                        if totalePartita > 0 {
                            GridRow {
                                Text("  \(partita.nomeEditabile)")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.7))
                                Text(CurrencyFormatter.shared.formatWithSymbol(totalePartita))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    GridRow {
                        Text("Danno non riconosciuto:")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text(CurrencyFormatter.shared.formatWithSymbol(risultato.dannoNonIndennizzabile))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(risultato.tuttoNonIndennizzabile ? Color.red.opacity(0.3) : Color(NSColor.separatorColor).opacity(0.3), lineWidth: risultato.tuttoNonIndennizzabile ? 1.5 : 0.5))
    }
}

struct AggiungiVocePersonalizzataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var descrizione: String
    @Binding var valore: String
    let onAggiungi: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Aggiungi Voce Personalizzata")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Descrizione:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Es: quota conto terzi, maggiorazione della franchigia, etc.", text: $descrizione)
                    .textFieldStyle(.roundedBorder)
                
                Text("Valore:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("€ 0,00", text: $valore)
                    .textFieldStyle(.roundedBorder)
                    .help("Inserisci un valore positivo o negativo (es: -50,00 o 100,00)")
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Aggiungi") {
                    onAggiungi()
                }
                .buttonStyle(.borderedProminent)
                .disabled(descrizione.isEmpty || valore.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
