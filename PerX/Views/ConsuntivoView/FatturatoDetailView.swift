import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct FatturatoDetailView: View {
    private typealias GDS = GlassmorphismDesignSystem
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    @StateObject private var fatturatoSettings = FatturatoSettings.shared
    @StateObject private var fatturaMensileService = FatturaMensileService.shared
    @StateObject private var fiscaleSettings = FatturatoFiscaleSettings.shared
    @StateObject private var bonusMensileService = BonusMensileService.shared
    @State private var selectedMonth: Date
    @State private var importoFatturatoInput: String = ""
    @State private var showingBonusEditor = false
    @State private var bonusToEdit: BonusMensile? = nil
    @State private var showingMonthPicker = false
    @State private var importSourceMonth: Date = Date()
    @State private var cachedBreakdown: FatturatoBreakdown?
    @State private var cachedFiscaleBreakdown: FatturatoFiscaleBreakdown?
    
    let onOpenSinistro: (Sinistro) -> Void
    
    init(initialMonth: Date, onOpenSinistro: @escaping (Sinistro) -> Void) {
        self._selectedMonth = State(initialValue: initialMonth)
        self._importSourceMonth = State(initialValue: Calendar.current.date(byAdding: .month, value: -1, to: initialMonth) ?? initialMonth)
        self.onOpenSinistro = onOpenSinistro
    }
    
    private var currentUserEmail: String? {
        AppState.shared.googleAuthService.userEmail?.lowercased()
    }
    
    private var monthlyClosedClaims: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyClosedClaims(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var sinistriChiusiSuccessful: [Sinistro] {
        ConsuntivoStatsService.shared.getMonthlyClosedClaimsSuccessful(for: selectedMonth, in: viewContext, userEmail: currentUserEmail)
    }
    
    private var totaleBonus: Double {
        bonusMensileService.calcolaTotaleBonus(for: selectedMonth, sinistriChiusi: sinistriChiusiSuccessful, in: viewContext)
    }
    
    private var bonusMensiliDetails: [BonusMensileDetail] {
        let bonusList = bonusMensileService.getBonus(for: selectedMonth).filter { $0.attivo }
        return bonusList.map { bonus in
            let importoBonus = bonusMensileService.calcolaImportoBonus(bonus, for: sinistriChiusiSuccessful, in: viewContext, month: selectedMonth)
            return BonusMensileDetail(
                nome: bonus.nome,
                tipo: bonus.tipo,
                importo: importoBonus
            )
        }
    }
    
    private var breakdown: FatturatoBreakdown {
        cachedBreakdown ?? FatturatoBreakdown(
            totaleSinistri: 0,
            importoBase: 0,
            sinistriBase: 0,
            importoFascia: 0,
            sinistriFascia: 0,
            numeroFascia: nil,
            importoDieciBeni: 0,
            sinistriDieciBeni: 0,
            totaleFatturato: 0,
            bonusMensili: 0,
            bonusMensiliList: [],
            compensiDanno: 0,
            sinistriConCompensoDanno: 0,
            dettaglioCompensiDanno: []
        )
    }
    
    private var fiscaleBreakdown: FatturatoFiscaleBreakdown {
        cachedFiscaleBreakdown ?? FatturatoFiscaleBreakdown(
            totaleParziale: 0,
            marcaDaBollo: 0,
            totaleConMarca: 0,
            rivalsaINPS: 0,
            fatturatoLordo: 0,
            coefficienteSpesa: 0,
            imponibileContributivo: 0,
            contributiINPS: 0,
            imponibileFiscale: 0,
            tasse: 0,
            utileNetto: 0
        )
    }
    
    private func calcolaBreakdownsSeNecessario() {
        // Prova a recuperare dalla cache
        let bonusList = bonusMensileService.getBonus(for: selectedMonth)
        if let cached = FatturatoCacheService.shared.getCachedBreakdowns(
            for: selectedMonth,
            sinistriChiusi: sinistriChiusiSuccessful,
            bonusMensili: bonusList,
            fatturatoSettings: fatturatoSettings,
            fiscaleSettings: fiscaleSettings
        ) {
            cachedBreakdown = cached.breakdown
            cachedFiscaleBreakdown = cached.fiscaleBreakdown
            return
        }
        
        // Cache non valida o non presente, ricalcola
        let breakdown = fatturatoSettings.calcolaBreakdownFatturato(
            sinistri: monthlyClosedClaims,
            bonusMensili: totaleBonus,
            bonusMensiliList: bonusMensiliDetails
        )
        
        let fiscaleBreakdown = fatturatoSettings.calcolaFatturatoFiscale(
            breakdown: breakdown,
            fiscaleSettings: fiscaleSettings,
            for: selectedMonth
        )
        
        // Salva in cache
        FatturatoCacheService.shared.saveBreakdowns(
            breakdown: breakdown,
            fiscaleBreakdown: fiscaleBreakdown,
            for: selectedMonth,
            sinistriChiusi: sinistriChiusiSuccessful,
            bonusMensili: bonusList,
            fatturatoSettings: fatturatoSettings,
            fiscaleSettings: fiscaleSettings
        )
        
        cachedBreakdown = breakdown
        cachedFiscaleBreakdown = fiscaleBreakdown
    }
    
    private var fatturaMensile: FatturaMensile? {
        fatturaMensileService.getFattura(for: selectedMonth)
    }
    
    private var fatturatoEffettivo: Double? {
        fatturaMensileService.getFatturatoEffettivo(for: selectedMonth)
    }
    
    private var fatturatoStimato: Double {
        fiscaleBreakdown.fatturatoLordo
    }
    
    private var fatturatoDaMostrare: Double {
        fatturatoEffettivo ?? fatturatoStimato
    }
    
    /// Breakdown fiscale da usare nel riepilogo: usa l'importo effettivo se disponibile
    private var fiscaleBreakdownEffettivo: FatturatoFiscaleBreakdown {
        if let effettivo = fatturatoEffettivo {
            return calcolaFiscaleDaImportoEffettivo(importoLordo: effettivo)
        }
        return fiscaleBreakdown
    }
    
    /// Calcola il breakdown fiscale partendo da un importo lordo effettivo
    private func calcolaFiscaleDaImportoEffettivo(importoLordo: Double) -> FatturatoFiscaleBreakdown {
        let fatturatoLordo = importoLordo
        let coefficienteSpesa = fatturatoLordo * (fiscaleSettings.coefficienteRedditivita / 100.0)
        let imponibileContributivo = fatturatoLordo - coefficienteSpesa
        let percentualeINPS = fiscaleSettings.getContributiINPS(for: selectedMonth)
        let contributiINPS = imponibileContributivo * (percentualeINPS / 100.0)
        let imponibileFiscale = imponibileContributivo - contributiINPS
        let tasse = imponibileFiscale * (fiscaleSettings.percentualeTasse / 100.0)
        let utileNetto = imponibileFiscale - tasse + coefficienteSpesa
        
        return FatturatoFiscaleBreakdown(
            totaleParziale: 0,
            marcaDaBollo: 0,
            totaleConMarca: 0,
            rivalsaINPS: 0,
            fatturatoLordo: fatturatoLordo,
            coefficienteSpesa: coefficienteSpesa,
            imponibileContributivo: imponibileContributivo,
            contributiINPS: contributiINPS,
            imponibileFiscale: imponibileFiscale,
            tasse: tasse,
            utileNetto: utileNetto
        )
    }
    
    private var isMonthCompleted: Bool {
        fatturaMensileService.isMonthCompleted(selectedMonth)
    }
    
    private var hasPdf: Bool {
        fatturaMensile?.pdfURL != nil && FileManager.default.fileExists(atPath: fatturaMensile?.pdfURL?.path ?? "")
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: selectedMonth).capitalized
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            GlassmorphicDivider()
            
            // Contenuto
            ScrollView {
                VStack(spacing: GDS.Spacing.xxl) {
                    // Breakdown dettagliato
                    breakdownSection
                    
                    // Riepilogo contributi e tasse
                    riepilogoSection
                    
                    // Gestione bonus mensili
                    bonusSection
                    
                    // Input fattura (solo se mese completato)
                    if isMonthCompleted {
                        fatturaInputSection
                    }
                }
                .padding(GDS.Spacing.xxl)
            }
        }
        .background(GDS.SystemColors.windowBackground)
        .frame(width: 900, height: 750)
        .onAppear {
            updateInputFields()
            calcolaBreakdownsSeNecessario()
        }
        .onChange(of: selectedMonth) { _ in
            updateInputFields()
            calcolaBreakdownsSeNecessario()
        }
        .sheet(isPresented: $showingBonusEditor) {
            if let bonus = bonusToEdit {
                BonusEditorView(bonus: bonus, month: selectedMonth, isPresented: $showingBonusEditor)
                    .onDisappear {
                        // Quando chiude l'editor, ricalcola i breakdown
                        calcolaBreakdownsSeNecessario()
                    }
            } else {
                BonusEditorView(month: selectedMonth, isPresented: $showingBonusEditor)
                    .onDisappear {
                        // Quando chiude l'editor, ricalcola i breakdown
                        calcolaBreakdownsSeNecessario()
                    }
            }
        }
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerView(
                selectedMonth: $importSourceMonth,
                isPresented: $showingMonthPicker,
                onConfirm: {
                    bonusMensileService.importaBonus(from: importSourceMonth, to: selectedMonth)
                    showingMonthPicker = false
                }
            )
        }
        .onChange(of: selectedMonth) { newMonth in
            importSourceMonth = Calendar.current.date(byAdding: .month, value: -1, to: newMonth) ?? newMonth
        }
    }
    
    // MARK: - Dettaglio Sinistri Window
    
    private func openDettaglioSinistri() {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: selectedMonth)
        let month = calendar.component(.month, from: selectedMonth)
        let totaleFatturato = dettaglioSinistri.reduce(0) { $0 + $1.totale }
        
        let config = FilterConfig.fatturatoDetailForMonth(
            year: year,
            month: month,
            sinistri: sinistriChiusiSuccessful,
            totaleFatturato: totaleFatturato,
            settings: fatturatoSettings
        )
        
        FilteredSinistriWindowHelper.open(config: config)
    }
    
    private var dettaglioSinistri: [SinistroFatturatoDetail] {
        let totaleSinistri = sinistriChiusiSuccessful.count
        var importoFascia = fatturatoSettings.importoBase
        if let fascia = fatturatoSettings.fasce.sorted(by: { $0.numeroSinistri > $1.numeroSinistri })
            .first(where: { totaleSinistri >= $0.numeroSinistri }) {
            importoFascia = fascia.importoFatturazione
        }
        
        return sinistriChiusiSuccessful.map { sinistro in
            var importoBase: Double
            var tipoBase: String
            var bonus: [String: Double] = [:]
            var totale: Double = 0
            
            // Sinistri >10 beni hanno importo fisso (senza moltiplicatore fascia)
            if sinistro.oltreDieciBeni {
                importoBase = fatturatoSettings.importoBaseDieciBeni
                tipoBase = ">10 beni (fisso)"
            } else {
                importoBase = importoFascia
                tipoBase = "Base"
            }
            
            totale = importoBase
            
            // Calcola compenso per danno (basato sulla compagnia)
            if let dannoAccertato = sinistro.dannoAccertato?.doubleValue, dannoAccertato > 0 {
                let compensoDanno = fatturatoSettings.calcolaCompensoDanno(
                    dannoAccertato: dannoAccertato,
                    compagnia: sinistro.nomeCompagnia
                )
                if compensoDanno > 0 {
                    let nomeCompagnia = sinistro.nomeCompagnia ?? "N/D"
                    bonus["Danno €\(Int(dannoAccertato)) (\(nomeCompagnia))"] = compensoDanno
                    totale += compensoDanno
                }
            }
            
            return SinistroFatturatoDetail(
                sinistro: sinistro,
                importoBase: importoBase,
                tipoBase: tipoBase,
                bonus: bonus,
                totale: totale
            )
        }
    }
    
    private var headerView: some View {
        HStack(spacing: GDS.Spacing.xl) {
            // Navigazione mesi
            HStack(spacing: GDS.Spacing.md) {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(GDS.SystemColors.accentBlue)
                }
                .buttonStyle(.plain)
                
                VStack(spacing: GDS.Spacing.xxs) {
                    Text("Dettaglio Fatturato")
                        .font(GDS.Typography.headline)
                    
                    Text(monthYearString)
                        .font(GDS.Typography.subtitle)
                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                }
                .frame(width: 200)
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(GDS.SystemColors.accentBlue)
                }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
            }
            
            Spacer()
            
            Button("Chiudi") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(GDS.Spacing.xl)
        .background(GDS.SystemColors.controlBackground.opacity(0.5))
    }
    
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: GDS.Spacing.xl) {
            HStack {
                HStack(spacing: GDS.Spacing.md) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundColor(GDS.SystemColors.accentBlue)
                    Text("Breakdown Fatturato")
                        .font(GDS.Typography.headline)
                }
                
                Spacer()
                
                GlassmorphicButton(title: "Dettaglio Sinistri", icon: "list.bullet.rectangle") {
                    openDettaglioSinistri()
                }
            }
            
            GlassmorphicPanel {
                VStack(spacing: GDS.Spacing.lg) {
                    // Base per sinistri
                    BreakdownRowStyled(
                        icon: "doc.text",
                        label: "Base per \(breakdown.sinistriBase) sinistri",
                        value: breakdown.sinistriBase > 0 ? Double(breakdown.sinistriBase) * breakdown.importoBase : 0,
                        note: "€\(String(format: "%.2f", breakdown.importoBase)) per sinistro"
                    )
                    
                    // Bonus per fascia se applicabile
                    if let numeroFascia = breakdown.numeroFascia, breakdown.importoFascia != breakdown.importoBase {
                        let incremento = breakdown.importoFascia - breakdown.importoBase
                        BreakdownRowStyled(
                            icon: "arrow.up.right",
                            label: "Bonus per fascia \(numeroFascia)",
                            value: breakdown.sinistriBase > 0 ? Double(breakdown.sinistriBase) * incremento : 0,
                            note: "€\(String(format: "%.2f", incremento)) per sinistro (fascia ≥\(numeroFascia) sinistri)",
                            valueColor: .green
                        )
                    }
                    
                    // Sinistri oltre 10 beni (importo fisso)
                    if breakdown.sinistriDieciBeni > 0 {
                        BreakdownRowStyled(
                            icon: "cube.box",
                            label: "Sinistri >10 beni (\(breakdown.sinistriDieciBeni))",
                            value: Double(breakdown.sinistriDieciBeni) * breakdown.importoDieciBeni,
                            note: "€\(String(format: "%.2f", breakdown.importoDieciBeni)) per sinistro (importo fisso)",
                            valueColor: .orange
                        )
                    }
                    
                    // Compensi per danno
                    if breakdown.compensiDanno > 0 {
                        BreakdownRowStyled(
                            icon: "flame",
                            label: "Compensi per danno (\(breakdown.sinistriConCompensoDanno) sinistri)",
                            value: breakdown.compensiDanno,
                            note: breakdown.dettaglioCompensiDanno.isEmpty ? nil : 
                                breakdown.dettaglioCompensiDanno.map { "\($0.compagnia): \($0.numeroSinistri)" }.joined(separator: ", "),
                            valueColor: .red
                        )
                    }
                    
                    // Altri bonus mensili
                    ForEach(breakdown.bonusMensiliList, id: \.nome) { bonusDetail in
                        BreakdownRowStyled(
                            icon: "gift",
                            label: bonusDetail.nome,
                            value: bonusDetail.importo,
                            note: bonusDetail.tipo == .unaTantum ? "Bonus una tantum" : "Bonus dinamico",
                            valueColor: .purple
                        )
                    }
                    
                    // Marca da bollo
                    if fiscaleBreakdown.marcaDaBollo > 0 {
                        BreakdownRowStyled(
                            icon: "ticket.fill",
                            label: "Marca da bollo",
                            value: fiscaleBreakdown.marcaDaBollo,
                            note: "Applicata se totale > €77,47"
                        )
                    }
                    
                    // Rivalsa INPS
                    if fiscaleBreakdown.rivalsaINPS > 0 {
                        BreakdownRowStyled(
                            icon: "percent",
                            label: "Rivalsa INPS (\(String(format: "%.0f", fiscaleSettings.rivalsaINPSPercentuale))%)",
                            value: fiscaleBreakdown.rivalsaINPS,
                            note: "Sul totale con marca da bollo"
                        )
                    }
                    
                    GlassmorphicDivider()
                    
                    HStack {
                        HStack(spacing: GDS.Spacing.md) {
                            Image(systemName: "sum")
                                .foregroundColor(.purple)
                            Text("Fatturato Stimato Lordo")
                                .font(GDS.Typography.headline)
                        }
                        Spacer()
                        Text(CurrencyFormatter.shared.formatWithSymbol(fatturatoStimato))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                }
                .padding(GDS.Spacing.xl)
            }
        }
    }
    
    private var riepilogoSection: some View {
        VStack(alignment: .leading, spacing: GDS.Spacing.xl) {
            HStack(spacing: GDS.Spacing.md) {
                Image(systemName: "eurosign.circle")
                    .foregroundColor(.green)
                Text("Riepilogo Fiscale")
                    .font(GDS.Typography.headline)
                
                if fatturatoEffettivo != nil {
                    Text("(basato su fattura effettiva)")
                        .font(GDS.Typography.small)
                        .foregroundColor(.green)
                }
            }
            
            GlassmorphicPanel {
                VStack(spacing: GDS.Spacing.xl) {
                    // Fatturato header
                    if fatturatoEffettivo != nil {
                        VStack(spacing: GDS.Spacing.md) {
                            HStack {
                                HStack(spacing: GDS.Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Fatturato Effettivo Lordo")
                                        .font(GDS.Typography.subtitle)
                                }
                                Spacer()
                                Text(CurrencyFormatter.shared.formatWithSymbol(fatturatoDaMostrare))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                            }
                            
                            HStack {
                                Text("Fatturato Stimato Lordo (breakdown)")
                                    .font(GDS.Typography.small)
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                                Spacer()
                                Text(CurrencyFormatter.shared.formatWithSymbol(fatturatoStimato))
                                    .font(GDS.Typography.small)
                                    .foregroundColor(.purple)
                            }
                        }
                    } else {
                        HStack {
                            HStack(spacing: GDS.Spacing.sm) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundColor(.purple)
                                Text("Fatturato Stimato Lordo")
                                    .font(GDS.Typography.subtitle)
                            }
                            Spacer()
                            Text(CurrencyFormatter.shared.formatWithSymbol(fatturatoStimato))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.purple)
                        }
                    }
                    
                    GlassmorphicDivider()
                    
                    VStack(spacing: GDS.Spacing.lg) {
                        // Coefficiente di redditività
                        RiepilogoRowStyled(
                            icon: "percent",
                            label: "Coefficiente di redditività",
                            value: fiscaleBreakdownEffettivo.coefficienteSpesa,
                            percentuale: fiscaleSettings.coefficienteRedditivita,
                            isNegative: true
                        )
                        
                        // Imponibile contributivo
                        HStack {
                            HStack(spacing: GDS.Spacing.sm) {
                                Image(systemName: "equal.circle")
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                                Text("Imponibile contributivo")
                                    .font(GDS.Typography.bodySemibold)
                            }
                            Spacer()
                            Text(CurrencyFormatter.shared.formatWithSymbol(fiscaleBreakdownEffettivo.imponibileContributivo))
                                .font(GDS.Typography.bodySemibold)
                        }
                        
                        GlassmorphicDivider()
                        
                        // Contributi INPS
                        let percentualeINPS = fiscaleSettings.getContributiINPS(for: selectedMonth)
                        RiepilogoRowStyled(
                            icon: "building.columns",
                            label: "Contributi INPS",
                            value: fiscaleBreakdownEffettivo.contributiINPS,
                            percentuale: percentualeINPS,
                            isNegative: true
                        )
                        
                        // Imponibile fiscale
                        HStack {
                            HStack(spacing: GDS.Spacing.sm) {
                                Image(systemName: "equal.circle")
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                                Text("Imponibile fiscale")
                                    .font(GDS.Typography.bodySemibold)
                            }
                            Spacer()
                            Text(CurrencyFormatter.shared.formatWithSymbol(fiscaleBreakdownEffettivo.imponibileFiscale))
                                .font(GDS.Typography.bodySemibold)
                        }
                        
                        GlassmorphicDivider()
                        
                        // Imposta unica sostitutiva
                        RiepilogoRowStyled(
                            icon: "doc.text",
                            label: "Imposta unica sostitutiva",
                            value: fiscaleBreakdownEffettivo.tasse,
                            percentuale: fiscaleSettings.percentualeTasse,
                            isNegative: true
                        )
                        
                        GlassmorphicDivider()
                        
                        // Utile netto - evidenziato
                        HStack {
                            HStack(spacing: GDS.Spacing.md) {
                                Image(systemName: "banknote")
                                    .foregroundColor(.green)
                                Text(fatturatoEffettivo != nil ? "Utile Netto" : "Utile Netto Stimato")
                                    .font(GDS.Typography.headline)
                            }
                            Spacer()
                            Text(CurrencyFormatter.shared.formatWithSymbol(fiscaleBreakdownEffettivo.utileNetto))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .padding(GDS.Spacing.md)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(GDS.Dimensions.cornerRadiusSmall)
                    }
                }
                .padding(GDS.Spacing.xl)
            }
        }
    }
    
    private var bonusSection: some View {
        VStack(alignment: .leading, spacing: GDS.Spacing.xl) {
            HStack {
                HStack(spacing: GDS.Spacing.md) {
                    Image(systemName: "gift")
                        .foregroundColor(.purple)
                    Text("Bonus Mensili")
                        .font(GDS.Typography.headline)
                }
                
                Spacer()
                
                GlassmorphicButton(title: "Aggiungi Bonus", icon: "plus.circle") {
                    bonusToEdit = nil
                    showingBonusEditor = true
                }
                
                Menu {
                    Button("Importa dal mese precedente") {
                        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        bonusMensileService.importaBonus(from: previousMonth, to: selectedMonth)
                    }
                    
                    Button("Importa da altro mese...") {
                        showingMonthPicker = true
                    }
                } label: {
                    Label("Importa", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
            }
            
            GlassmorphicPanel {
                let bonusList = bonusMensileService.getBonus(for: selectedMonth)
                if bonusList.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: GDS.Spacing.md) {
                            Image(systemName: "gift.circle")
                                .font(.system(size: 32))
                                .foregroundColor(GDS.SystemColors.tertiaryLabel)
                            Text("Nessun bonus configurato per questo mese")
                                .font(GDS.Typography.body)
                                .foregroundColor(GDS.SystemColors.secondaryLabel)
                        }
                        .padding(GDS.Spacing.xxl)
                        Spacer()
                    }
                } else {
                    VStack(spacing: GDS.Spacing.lg) {
                        ForEach(bonusList) { bonus in
                            BonusRowStyled(
                                bonus: bonus,
                                onEdit: {
                                    bonusToEdit = bonus
                                    showingBonusEditor = true
                                },
                                onDelete: {
                                    bonusMensileService.deleteBonus(bonus.id, for: selectedMonth)
                                },
                                sinistriChiusi: sinistriChiusiSuccessful,
                                month: selectedMonth,
                                context: viewContext
                            )
                        }
                    }
                    .padding(GDS.Spacing.xl)
                }
            }
        }
    }
    
    private var fatturaInputSection: some View {
        VStack(alignment: .leading, spacing: GDS.Spacing.xl) {
            HStack(spacing: GDS.Spacing.md) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(GDS.SystemColors.accentBlue)
                Text("Fattura Emessa")
                    .font(GDS.Typography.headline)
            }
            
            GlassmorphicPanel {
                VStack(spacing: GDS.Spacing.xl) {
                    // Importo fatturato
                    VStack(alignment: .leading, spacing: GDS.Spacing.md) {
                        Text("Importo Fatturato")
                            .font(GDS.Typography.subtitle)
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        
                        HStack(spacing: GDS.Spacing.md) {
                            HStack(spacing: GDS.Spacing.sm) {
                                Text("€")
                                    .font(GDS.Typography.headline)
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                                TextField("0,00", text: $importoFatturatoInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                    .onAppear {
                                        if let importo = fatturatoEffettivo {
                                            importoFatturatoInput = String(format: "%.2f", importo).replacingOccurrences(of: ".", with: ",")
                                        }
                                    }
                            }
                            
                            GlassmorphicButton(title: "Salva", icon: "checkmark") {
                                if let importo = Double(importoFatturatoInput.replacingOccurrences(of: ",", with: ".")) {
                                    fatturaMensileService.setImportoFatturato(importo, for: selectedMonth)
                                }
                            }
                        }
                    }
                    
                    GlassmorphicDivider()
                    
                    // PDF
                    VStack(alignment: .leading, spacing: GDS.Spacing.md) {
                        Text("PDF Fattura")
                            .font(GDS.Typography.subtitle)
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        
                        HStack {
                            if hasPdf, let pdfURL = fatturaMensile?.pdfURL {
                                HStack(spacing: GDS.Spacing.md) {
                                    Image(systemName: "doc.fill")
                                        .font(.title2)
                                        .foregroundColor(GDS.SystemColors.accentBlue)
                                    Text(pdfURL.lastPathComponent)
                                        .font(GDS.Typography.body)
                                        .lineLimit(1)
                                    
                                    Button {
                                        NSWorkspace.shared.open(pdfURL)
                                    } label: {
                                        Label("Apri", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                HStack(spacing: GDS.Spacing.md) {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                                    Text("Nessun PDF caricato")
                                        .font(GDS.Typography.body)
                                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                                }
                            }
                            
                            Spacer()
                            
                            GlassmorphicButton(title: hasPdf ? "Cambia PDF" : "Carica PDF", icon: "arrow.up.doc") {
                                openFilePicker()
                            }
                        }
                    }
                }
                .padding(GDS.Spacing.xl)
            }
        }
    }
    
    private func previousMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newDate
            updateInputFields()
        }
    }
    
    private func nextMonth() {
        if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newDate
            updateInputFields()
        }
    }
    
    private func updateInputFields() {
        if let importo = fatturatoEffettivo {
            importoFatturatoInput = String(format: "%.2f", importo).replacingOccurrences(of: ".", with: ",")
        } else {
            importoFatturatoInput = ""
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try fatturaMensileService.setPdf(from: url, for: selectedMonth)
            } catch {
                print("Errore salvataggio PDF: \(error)")
            }
        }
    }
}

struct BreakdownRow: View {
    let label: String
    let value: Double
    var note: String? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                if let note = note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(CurrencyFormatter.shared.formatWithSymbol(value))
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Styled Components (Glassmorphism)

struct BreakdownRowStyled: View {
    private typealias GDS = GlassmorphismDesignSystem
    
    let icon: String
    let label: String
    let value: Double
    var note: String? = nil
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            HStack(spacing: GDS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: GDS.Spacing.xxs) {
                    Text(label)
                        .font(GDS.Typography.body)
                    if let note = note {
                        Text(note)
                            .font(GDS.Typography.small)
                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    }
                }
            }
            Spacer()
            Text(CurrencyFormatter.shared.formatWithSymbol(value))
                .font(GDS.Typography.bodySemibold)
                .foregroundColor(valueColor)
        }
    }
}

struct RiepilogoRow: View {
    let label: String
    let value: Double
    let percentuale: Double
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(String(format: "%.1f", percentuale))%")
                .foregroundColor(.secondary)
                .font(.caption)
            Text(CurrencyFormatter.shared.formatWithSymbol(value))
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct RiepilogoRowStyled: View {
    private typealias GDS = GlassmorphismDesignSystem
    
    let icon: String
    let label: String
    let value: Double
    let percentuale: Double
    var isNegative: Bool = false
    
    var body: some View {
        HStack {
            HStack(spacing: GDS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                    .frame(width: 16)
                Text(label)
                    .font(GDS.Typography.body)
            }
            Spacer()
            HStack(spacing: GDS.Spacing.md) {
                Text("\(String(format: "%.1f", percentuale))%")
                    .font(GDS.Typography.small)
                    .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    .frame(width: 50, alignment: .trailing)
                Text((isNegative ? "- " : "") + CurrencyFormatter.shared.formatWithSymbol(value))
                    .font(GDS.Typography.bodySemibold)
                    .foregroundColor(isNegative ? .red : .primary)
                    .frame(width: 100, alignment: .trailing)
            }
        }
    }
}

struct BonusRow: View {
    let bonus: BonusMensile
    let onEdit: () -> Void
    let onDelete: () -> Void
    let sinistriChiusi: [Sinistro]
    let month: Date
    let context: NSManagedObjectContext
    
    private var totaleBonus: Double {
        switch bonus.tipo {
        case .unaTantum:
            return bonus.attivo ? bonus.importo : 0
        case .dinamico:
            guard bonus.attivo else { return 0 }
            let service = BonusMensileService.shared
            let qualificati = sinistriChiusi.filter { sinistro in
                service.verificaCondizioniPubbliche(bonus.condizioni ?? [], per: sinistro, in: sinistriChiusi, for: month, in: context)
            }
            return Double(qualificati.count) * bonus.importo
        }
    }
    
    private var sinistriQualificati: Int {
        guard bonus.tipo == .dinamico else { return 0 }
        let service = BonusMensileService.shared
        return sinistriChiusi.filter { sinistro in
            service.verificaCondizioniPubbliche(bonus.condizioni ?? [], per: sinistro, in: sinistriChiusi, for: month, in: context)
        }.count
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bonus.nome)
                        .font(.headline)
                    if !bonus.attivo {
                        Text("(Disattivato)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(bonus.tipo == .unaTantum ? "Bonus una tantum" : "Bonus dinamico")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if bonus.tipo == .dinamico {
                    Text("€\(String(format: "%.2f", bonus.importo)) per sinistro")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.shared.formatWithSymbol(totaleBonus))
                    .font(.headline)
                    .foregroundColor(.purple)
                
                if bonus.tipo == .dinamico {
                    Text("\(sinistriQualificati) sinistri qualificati")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.bordered)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.vertical, 4)
    }
}

struct BonusRowStyled: View {
    private typealias GDS = GlassmorphismDesignSystem
    
    let bonus: BonusMensile
    let onEdit: () -> Void
    let onDelete: () -> Void
    let sinistriChiusi: [Sinistro]
    let month: Date
    let context: NSManagedObjectContext
    
    private var totaleBonus: Double {
        switch bonus.tipo {
        case .unaTantum:
            return bonus.attivo ? bonus.importo : 0
        case .dinamico:
            guard bonus.attivo else { return 0 }
            let service = BonusMensileService.shared
            let qualificati = sinistriChiusi.filter { sinistro in
                service.verificaCondizioniPubbliche(bonus.condizioni ?? [], per: sinistro, in: sinistriChiusi, for: month, in: context)
            }
            return Double(qualificati.count) * bonus.importo
        }
    }
    
    private var sinistriQualificati: Int {
        guard bonus.tipo == .dinamico else { return 0 }
        let service = BonusMensileService.shared
        return sinistriChiusi.filter { sinistro in
            service.verificaCondizioniPubbliche(bonus.condizioni ?? [], per: sinistro, in: sinistriChiusi, for: month, in: context)
        }.count
    }
    
    var body: some View {
        HStack(spacing: GDS.Spacing.xl) {
            // Icona
            Image(systemName: bonus.tipo == .unaTantum ? "star.fill" : "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundColor(bonus.attivo ? .purple : GDS.SystemColors.tertiaryLabel)
                .frame(width: 32)
            
            // Info bonus
            VStack(alignment: .leading, spacing: GDS.Spacing.xxs) {
                HStack(spacing: GDS.Spacing.sm) {
                    Text(bonus.nome)
                        .font(GDS.Typography.subtitle)
                    if !bonus.attivo {
                        Text("Disattivato")
                            .font(GDS.Typography.extraSmall)
                            .foregroundColor(.orange)
                            .padding(.horizontal, GDS.Spacing.sm)
                            .padding(.vertical, GDS.Spacing.xxs)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: GDS.Spacing.md) {
                    Text(bonus.tipo == .unaTantum ? "Una tantum" : "Dinamico")
                        .font(GDS.Typography.small)
                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                    
                    if bonus.tipo == .dinamico {
                        Text("•")
                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                        Text("€\(String(format: "%.2f", bonus.importo))/sx")
                            .font(GDS.Typography.small)
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                    }
                }
            }
            
            Spacer()
            
            // Valore
            VStack(alignment: .trailing, spacing: GDS.Spacing.xxs) {
                Text(CurrencyFormatter.shared.formatWithSymbol(totaleBonus))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(bonus.attivo ? .purple : GDS.SystemColors.tertiaryLabel)
                
                if bonus.tipo == .dinamico {
                    Text("\(sinistriQualificati) sx qualificati")
                        .font(GDS.Typography.extraSmall)
                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                }
            }
            
            // Azioni
            HStack(spacing: GDS.Spacing.sm) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(GDS.SystemColors.accentBlue)
                }
                .buttonStyle(.borderless)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(GDS.Spacing.md)
        .background(bonus.attivo ? Color.purple.opacity(0.05) : Color.clear)
        .cornerRadius(GDS.Dimensions.cornerRadiusSmall)
    }
}


