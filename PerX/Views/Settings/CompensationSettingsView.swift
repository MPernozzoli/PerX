import SwiftUI

struct CompensationSettingsView: View {
    private typealias GDS = GlassmorphismDesignSystem
    
    @StateObject private var fatturatoSettings = FatturatoSettings.shared
    @StateObject private var fiscaleSettings = FatturatoFiscaleSettings.shared
    @State private var ranges: [CompensationRange] = []
    @State private var damageThresholds: [DamageThreshold] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: GDS.Spacing.xxl) {
                // Compensi a fasce
                GlassmorphicPanel {
                    VStack(spacing: GDS.Spacing.xl) {
                        // Header
                        HStack {
                            Text("Compensi a fasce")
                                .font(GDS.Typography.headline)
                            Spacer()
                            GlassmorphicButton(title: "Aggiungi Fascia", icon: "plus") {
                                addNewRange()
                            }
                        }
                        .padding(.bottom, GDS.Spacing.md)
                        
                        GlassmorphicDivider()
                        
                        // Table Header
                        HStack {
                            Text("Fascia")
                                .frame(width: 120, alignment: .leading)
                            Text("N° Sinistri")
                                .frame(width: 100)
                            Text("% Incentivo")
                                .frame(width: 100)
                            Text("Compenso")
                                .frame(width: 100)
                            VStack(spacing: 2) {
                                Text(">10 beni")
                                Text("(fisso)")
                                    .font(GDS.Typography.extraSmall)
                            }
                            .frame(width: 100)
                            Text("")
                                .frame(width: 40)
                        }
                        .font(GDS.Typography.caption)
                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                        
                        // Table Content
                        ForEach($ranges) { $range in
                            HStack {
                                if range.isBase {
                                    Text("Base")
                                        .frame(width: 120, alignment: .leading)
                                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                                    Text("0")
                                        .frame(width: 100)
                                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                                    Text("0%")
                                        .frame(width: 100)
                                        .foregroundColor(GDS.SystemColors.secondaryLabel)
                                    HStack {
                                        Text("€")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                        TextField("", value: Binding(
                                            get: { range.compensation },
                                            set: { newValue in
                                                range.compensation = newValue
                                                updateCompensations()
                                            }
                                        ), formatter: numberFormatter)
                                    }
                                    .frame(width: 100)
                                    HStack {
                                        Text("€")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                        TextField("", value: Binding(
                                            get: { range.extraCompensation },
                                            set: { newValue in
                                                range.extraCompensation = newValue
                                                updateCompensations()
                                            }
                                        ), formatter: numberFormatter)
                                    }
                                    .frame(width: 100)
                                    Color.clear.frame(width: 40)
                                } else {
                                    Text("Fascia \(range.level)")
                                        .frame(width: 120, alignment: .leading)
                                    TextField("", value: Binding(
                                        get: { range.threshold },
                                        set: { newValue in
                                            range.threshold = newValue
                                            saveRanges()
                                        }
                                    ), formatter: intFormatter)
                                        .frame(width: 100)
                                    HStack {
                                        TextField("", text: Binding(
                                            get: { String(format: "%.0f", range.incentivePercentage * 100) },
                                            set: { newValue in
                                                if let value = Double(newValue) {
                                                    range.incentivePercentage = value / 100
                                                    let baseComp = getBaseCompensation()
                                                    range.compensation = calculateCompensation(baseCompensation: baseComp, percentage: range.incentivePercentage)
                                                    // Non aggiornare extraCompensation: è fisso e non subisce il moltiplicatore
                                                    saveRanges()
                                                }
                                            }
                                        ))
                                        .frame(width: 50)
                                        Text("%")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                    }
                                    .frame(width: 100)
                                    HStack {
                                        Text("€")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                        Text(range.compensation.formatted(.number.precision(.fractionLength(2))))
                                    }
                                    .frame(width: 100)
                                    // Importo >10 beni è FISSO - mostra il valore base senza moltiplicatore
                                    HStack {
                                        Text("€")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                        Text(getBaseExtraCompensation().formatted(.number.precision(.fractionLength(2))))
                                            .foregroundColor(.orange)
                                    }
                                    .frame(width: 100)
                                    .help("Importo fisso: non subisce il moltiplicatore della fascia")
                                    Button(action: { deleteRange(range) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .frame(width: 40)
                                }
                            }
                            .padding(.vertical, GDS.Spacing.xs)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(GDS.Spacing.xl)
                }
                
                // Compensi per danno - Header
                VStack(alignment: .leading, spacing: GDS.Spacing.md) {
                    HStack {
                        HStack(spacing: GDS.Spacing.md) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Compensi per danno")
                                .font(GDS.Typography.headline)
                        }
                        Spacer()
                        Menu {
                            Button("Soglia generica") {
                                addNewDamageThreshold(compagnia: nil)
                            }
                            Divider()
                            
                            ForEach(GruppoAssicurativo.allCases.filter { $0 != .unknown }, id: \.rawValue) { gruppo in
                                Menu(gruppo.rawValue) {
                                    Button("Tutto \(gruppo.shortLabel)") {
                                        addNewDamageThreshold(compagnia: gruppo.rawValue)
                                    }
                                    
                                    if !gruppo.compagnie.isEmpty {
                                        Divider()
                                        ForEach(gruppo.compagnie, id: \.rawValue) { compagnia in
                                            Button(compagnia.rawValue) {
                                                addNewDamageThreshold(compagnia: compagnia.rawValue)
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Aggiungi Soglia", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Text("Le soglie specifiche per compagnia hanno priorità su quelle generiche")
                        .font(GDS.Typography.small)
                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                        .padding(.horizontal, GDS.Spacing.md)
                }
                
                // Visualizzazione soglie organizzata per gruppo
                damageThresholdsCardsView
                
                // Parametri fiscali
                GlassmorphicPanel {
                    VStack(alignment: .leading, spacing: GDS.Spacing.xl) {
                        Text("Parametri fiscali")
                            .font(GDS.Typography.headline)
                        
                        Text("Percentuali usate nel calcolo del fatturato stimato")
                            .font(GDS.Typography.caption)
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        
                        GlassmorphicDivider()
                        
                        // Contributi INPS (per anno) - default 26,09%
                        HStack {
                            Text("Contributi INPS (anno \(Calendar.current.component(.year, from: Date())))")
                                .frame(width: 280, alignment: .leading)
                            HStack {
                                TextField("", value: Binding(
                                    get: { fiscaleSettings.getContributiINPS(for: Date()) },
                                    set: { fiscaleSettings.setContributiINPS($0, for: Calendar.current.component(.year, from: Date())) }
                                ), formatter: numberFormatter)
                                Text("%")
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                            }
                            .frame(width: 100)
                        }
                        .textFieldStyle(.roundedBorder)
                        .help("Default 26,09%")
                        
                        // Coefficiente di redditività
                        HStack {
                            Text("Coefficiente di redditività")
                                .frame(width: 280, alignment: .leading)
                            HStack {
                                TextField("", value: $fiscaleSettings.coefficienteRedditivita, formatter: numberFormatter)
                                Text("%")
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                            }
                            .frame(width: 100)
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        // Rivalsa INPS
                        HStack {
                            Text("Rivalsa INPS")
                                .frame(width: 280, alignment: .leading)
                            HStack {
                                TextField("", value: $fiscaleSettings.rivalsaINPSPercentuale, formatter: numberFormatter)
                                Text("%")
                                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                            }
                            .frame(width: 100)
                            GlassmorphicToggle(title: "Abilitata", isOn: $fiscaleSettings.rivalsaINPSAbilitata)
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        // Imposta unica sostitutiva: 5%, 15% o Personalizzato
                        VStack(alignment: .leading, spacing: GDS.Spacing.md) {
                            Text("Imposta unica sostitutiva")
                                .font(GDS.Typography.subtitle)
                            
                            HStack(spacing: GDS.Spacing.xl) {
                                Picker("", selection: Binding(
                                    get: {
                                        let p = fiscaleSettings.percentualeTasse
                                        if p == 5 { return 0 }
                                        if p == 15 { return 1 }
                                        return 2
                                    },
                                    set: { tag in
                                        switch tag {
                                        case 0: fiscaleSettings.percentualeTasse = 5
                                        case 1: fiscaleSettings.percentualeTasse = 15
                                        default:
                                            let p = fiscaleSettings.percentualeTasse
                                            if p == 5 || p == 15 { fiscaleSettings.percentualeTasse = 10 }
                                        }
                                    }
                                )) {
                                    Text("5%").tag(0)
                                    Text("15%").tag(1)
                                    Text("Personalizzato").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 280)
                                
                                if fiscaleSettings.percentualeTasse != 5 && fiscaleSettings.percentualeTasse != 15 {
                                    HStack {
                                        TextField("", value: $fiscaleSettings.percentualeTasse, formatter: numberFormatter)
                                        Text("%")
                                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                                    }
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        
                        // Marca da bollo
                        HStack {
                            Text("Marca da bollo")
                                .frame(width: 280, alignment: .leading)
                            GlassmorphicToggle(title: "Applica se totale > €77,47", isOn: $fiscaleSettings.marcaDaBolloAbilitata)
                        }
                    }
                    .padding(GDS.Spacing.xl)
                }
            }
            .padding(GDS.Spacing.xxl)
        }
        .background(GDS.SystemColors.windowBackground)
        .onAppear {
            fatturatoSettings.ricaricaImpostazioni()
            loadDefaultRanges()
            loadDefaultDamageThresholds()
        }
    }
    
    private func getBaseCompensation() -> Double {
        ranges.first(where: { $0.isBase })?.compensation ?? 0
    }
    
    private func getBaseExtraCompensation() -> Double {
        ranges.first(where: { $0.isBase })?.extraCompensation ?? 0
    }
    
    private func calculateCompensation(baseCompensation: Double, percentage: Double) -> Double {
        baseCompensation * (1 + percentage)
    }
    
    private func updateCompensations() {
        for i in ranges.indices where !ranges[i].isBase {
            ranges[i].compensation = calculateCompensation(baseCompensation: getBaseCompensation(), percentage: ranges[i].incentivePercentage)
            // NON aggiornare extraCompensation: l'importo >10 beni è FISSO e non subisce il moltiplicatore
        }
        saveRanges()
    }
    
    private func addNewRange() {
        let newLevel = (ranges.map { $0.level }.max() ?? 0) + 1
        let baseComp = getBaseCompensation()
        let baseExtraComp = getBaseExtraCompensation()
        let newRange = CompensationRange(
            level: newLevel,
            threshold: 0,
            incentivePercentage: 0,
            compensation: baseComp,
            extraCompensation: baseExtraComp,
            isBase: false
        )
        ranges.append(newRange)
        saveRanges()
    }
    
    private func deleteRange(_ range: CompensationRange) {
        ranges.removeAll { $0.id == range.id }
        saveRanges()
    }
    
    private var compagnieDisponibili: [String] {
        // Usa le compagnie e i gruppi definiti in CompagniaService
        var compagnie: [String] = []
        
        // Aggiungi tutti i gruppi assicurativi
        for gruppo in GruppoAssicurativo.allCases where gruppo != .unknown {
            compagnie.append(gruppo.shortLabel)
        }
        
        // Aggiungi tutte le compagnie
        for compagnia in Compagnia.allCases where compagnia != .unknown {
            compagnie.append(compagnia.rawValue)
        }
        
        // Aggiungi le compagnie già usate nelle soglie esistenti (potrebbero essere personalizzate)
        let compagnieEsistenti = damageThresholds.compactMap { $0.compagnia?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return Array(Set(compagnie + compagnieEsistenti)).sorted()
    }
    
    // MARK: - Soglie Danno Cards View
    
    @ViewBuilder
    private var damageThresholdsCardsView: some View {
        VStack(spacing: GDS.Spacing.lg) {
            // Soglie generiche
            let indiciGenerici = damageThresholds.indices.filter { 
                damageThresholds[$0].compagnia == nil || damageThresholds[$0].compagnia?.isEmpty == true 
            }
            
            if !indiciGenerici.isEmpty {
                GlassmorphicPanel {
                    VStack(alignment: .leading, spacing: GDS.Spacing.lg) {
                        HStack(spacing: GDS.Spacing.md) {
                            Image(systemName: "globe")
                                .foregroundColor(.orange)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: GDS.Spacing.xxs) {
                                Text("Regole Generiche")
                                    .font(GDS.Typography.subtitle)
                                    .foregroundColor(.orange)
                                Text("\(indiciGenerici.count) soglie configurate")
                                    .font(GDS.Typography.extraSmall)
                                    .foregroundColor(GDS.SystemColors.tertiaryLabel)
                            }
                        }
                        
                        GlassmorphicDivider()
                        
                        ForEach(indiciGenerici, id: \.self) { index in
                            damageThresholdCard(index: index)
                        }
                    }
                    .padding(GDS.Spacing.xl)
                }
            }
            
            // Soglie specifiche per gruppo
            let indiciSpecifici = damageThresholds.indices.filter { 
                damageThresholds[$0].compagnia != nil && !(damageThresholds[$0].compagnia?.isEmpty ?? true)
            }
            
            if !indiciSpecifici.isEmpty {
                ForEach(GruppoAssicurativo.allCases.filter { $0 != .unknown }, id: \.rawValue) { gruppo in
                    let indiciGruppo = indiciSpecifici.filter { index in
                        guard let compagnia = damageThresholds[index].compagnia else { return false }
                        return compagnia == gruppo.rawValue || gruppo.compagnie.contains { $0.rawValue == compagnia }
                    }
                    
                    if !indiciGruppo.isEmpty {
                        GlassmorphicPanel {
                            VStack(alignment: .leading, spacing: GDS.Spacing.lg) {
                                HStack(spacing: GDS.Spacing.md) {
                                    Image(systemName: gruppo.uiIconSystemName)
                                        .foregroundColor(Color(red: gruppo.uiColor.red, green: gruppo.uiColor.green, blue: gruppo.uiColor.blue))
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: GDS.Spacing.xxs) {
                                        Text(gruppo.rawValue)
                                            .font(GDS.Typography.subtitle)
                                            .foregroundColor(Color(red: gruppo.uiColor.red, green: gruppo.uiColor.green, blue: gruppo.uiColor.blue))
                                        Text("\(indiciGruppo.count) soglie configurate")
                                            .font(GDS.Typography.extraSmall)
                                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                                    }
                                }
                                
                                GlassmorphicDivider()
                                
                                ForEach(indiciGruppo, id: \.self) { index in
                                    damageThresholdCard(index: index)
                                }
                            }
                            .padding(GDS.Spacing.xl)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Soglie Danno List View (legacy)
    
    @ViewBuilder
    private var damageThresholdsListView: some View {
        // Separa soglie generiche e specifiche
        let indiciGenerici = damageThresholds.indices.filter { 
            damageThresholds[$0].compagnia == nil || damageThresholds[$0].compagnia?.isEmpty == true 
        }
        let indiciSpecifici = damageThresholds.indices.filter { 
            damageThresholds[$0].compagnia != nil && !(damageThresholds[$0].compagnia?.isEmpty ?? true)
        }
        
        // Soglie generiche
        if !indiciGenerici.isEmpty {
            HStack(spacing: GDS.Spacing.md) {
                Image(systemName: "globe")
                    .foregroundColor(.orange)
                Text("Regole generiche (tutte le compagnie)")
                    .font(GDS.Typography.small)
                    .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, GDS.Spacing.sm)
            
            ForEach(indiciGenerici, id: \.self) { index in
                damageThresholdRowByIndex(index: index)
            }
        }
        
        // Soglie specifiche raggruppate per gruppo assicurativo
        if !indiciSpecifici.isEmpty {
            GlassmorphicDivider()
            
            ForEach(GruppoAssicurativo.allCases.filter { $0 != .unknown }, id: \.rawValue) { gruppo in
                let indiciGruppo = indiciSpecifici.filter { index in
                    guard let compagnia = damageThresholds[index].compagnia else { return false }
                    return compagnia == gruppo.rawValue || gruppo.compagnie.contains { $0.rawValue == compagnia }
                }
                
                if !indiciGruppo.isEmpty {
                    VStack(alignment: .leading, spacing: GDS.Spacing.sm) {
                        HStack(spacing: GDS.Spacing.md) {
                            Image(systemName: gruppo.uiIconSystemName)
                                .foregroundColor(Color(red: gruppo.uiColor.red, green: gruppo.uiColor.green, blue: gruppo.uiColor.blue))
                            Text(gruppo.rawValue)
                                .font(GDS.Typography.subtitle)
                                .foregroundColor(Color(red: gruppo.uiColor.red, green: gruppo.uiColor.green, blue: gruppo.uiColor.blue))
                        }
                        .padding(.top, GDS.Spacing.md)
                        
                        ForEach(indiciGruppo, id: \.self) { index in
                            let compagnia = damageThresholds[index].compagnia ?? ""
                            let isCompagniaSpecifica = compagnia != gruppo.rawValue
                            
                            HStack(spacing: GDS.Spacing.sm) {
                                if isCompagniaSpecifica {
                                    Text("└")
                                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                                        .font(.system(size: 14, design: .monospaced))
                                }
                                damageThresholdRowByIndex(index: index, showCompagnia: isCompagniaSpecifica)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func damageThresholdCard(index: Int) -> some View {
        if index < damageThresholds.count {
            let threshold = damageThresholds[index]
            
            HStack(spacing: GDS.Spacing.xl) {
                // Icona e info compagnia
                VStack(alignment: .leading, spacing: GDS.Spacing.xs) {
                    if threshold.isGenerica {
                        HStack(spacing: GDS.Spacing.sm) {
                            Image(systemName: threshold.escludiSeSpecifica ? "minus.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(threshold.escludiSeSpecifica ? .orange : .green)
                            Text(threshold.escludiSeSpecifica ? "Tutte tranne" : "Tutte")
                                .font(GDS.Typography.bodySemibold)
                                .foregroundColor(threshold.escludiSeSpecifica ? .orange : .green)
                        }
                        Text(threshold.escludiSeSpecifica ? "Escluse compagnie con regole specifiche" : "Include anche compagnie con regole specifiche")
                            .font(GDS.Typography.extraSmall)
                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    } else {
                        HStack(spacing: GDS.Spacing.sm) {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(GDS.SystemColors.accentBlue)
                            Text(threshold.compagnia ?? "")
                                .font(GDS.Typography.bodySemibold)
                        }
                        Text("Regola specifica")
                            .font(GDS.Typography.extraSmall)
                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    }
                }
                .frame(width: 200, alignment: .leading)
                
                Spacer()
                
                // Soglia danno
                VStack(alignment: .leading, spacing: GDS.Spacing.xs) {
                    Text("Danno accertato")
                        .font(GDS.Typography.extraSmall)
                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    HStack(spacing: GDS.Spacing.xs) {
                        Text("≥")
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        TextField("", value: Binding(
                            get: { damageThresholds[index].value },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].value = newValue
                                    saveDamageThresholds()
                                }
                            }
                        ), formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("€")
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                    }
                }
                
                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundColor(GDS.SystemColors.tertiaryLabel)
                
                // Compenso
                VStack(alignment: .leading, spacing: GDS.Spacing.xs) {
                    Text("Compenso")
                        .font(GDS.Typography.extraSmall)
                        .foregroundColor(GDS.SystemColors.tertiaryLabel)
                    HStack(spacing: GDS.Spacing.xs) {
                        TextField("", value: Binding(
                            get: { damageThresholds[index].compensation },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].compensation = newValue
                                    saveDamageThresholds()
                                }
                            }
                        ), formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("€")
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                    }
                }
                
                // Opzioni per soglie generiche
                if threshold.isGenerica {
                    VStack(alignment: .leading, spacing: GDS.Spacing.xs) {
                        Text("Applicazione")
                            .font(GDS.Typography.extraSmall)
                            .foregroundColor(GDS.SystemColors.tertiaryLabel)
                        Picker("", selection: Binding(
                            get: { damageThresholds[index].escludiSeSpecifica },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].escludiSeSpecifica = newValue
                                    saveDamageThresholds()
                                }
                            }
                        )) {
                            Text("Tutte").tag(false)
                            Text("Tutte tranne").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
                
                // Delete button
                Button(action: { deleteDamageThreshold(threshold) }) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Elimina soglia")
            }
            .padding(GDS.Spacing.md)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(GDS.Dimensions.cornerRadiusSmall)
        }
    }
    
    @ViewBuilder
    private func damageThresholdRowByIndex(index: Int, showCompagnia: Bool = true) -> some View {
        if index < damageThresholds.count {
            let threshold = damageThresholds[index]
            VStack(alignment: .leading, spacing: GDS.Spacing.xs) {
                HStack {
                    if showCompagnia {
                        // Per soglie generiche mostra "Tutte" o "Tutte tranne" in base all'opzione
                        if threshold.isGenerica {
                            Text(threshold.escludiSeSpecifica ? "Tutte tranne" : "Tutte")
                                .frame(width: 150, alignment: .leading)
                                .foregroundColor(.orange)
                                .font(GDS.Typography.small)
                        } else {
                            Text(threshold.compagnia ?? "")
                                .frame(width: 150, alignment: .leading)
                                .foregroundColor(.primary)
                                .font(GDS.Typography.small)
                        }
                    }
                    
                    HStack {
                        Text("€")
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        TextField("Soglia", value: Binding(
                            get: { damageThresholds[index].value },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].value = newValue
                                    saveDamageThresholds()
                                }
                            }
                        ), formatter: numberFormatter)
                    }
                    .frame(width: showCompagnia ? 150 : 120)
                    
                    HStack {
                        Text("€")
                            .foregroundColor(GDS.SystemColors.secondaryLabel)
                        TextField("Compenso", value: Binding(
                            get: { damageThresholds[index].compensation },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].compensation = newValue
                                    saveDamageThresholds()
                                }
                            }
                        ), formatter: numberFormatter)
                    }
                    .frame(width: showCompagnia ? 150 : 120)
                    
                    // Toggle per soglie generiche: escludiSeSpecifica
                    if threshold.isGenerica {
                        Picker("", selection: Binding(
                            get: { damageThresholds[index].escludiSeSpecifica },
                            set: { newValue in
                                if index < damageThresholds.count {
                                    damageThresholds[index].escludiSeSpecifica = newValue
                                    saveDamageThresholds()
                                }
                            }
                        )) {
                            Text("Tutte").tag(false)
                            Text("Tutte tranne").tag(true)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .help("'Tutte': si applica a tutte le compagnie\n'Tutte tranne': si applica solo a compagnie senza regole specifiche")
                    } else {
                        Color.clear.frame(width: 120)
                    }
                    
                    Button(action: { deleteDamageThreshold(threshold) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 40)
                }
            }
            .padding(.vertical, GDS.Spacing.xs)
            .textFieldStyle(.roundedBorder)
        }
    }
    
    @ViewBuilder
    private func damageThresholdRow(threshold: Binding<DamageThreshold>, showCompagnia: Bool = true) -> some View {
        HStack {
            // Compagnia (solo se richiesto)
            if showCompagnia {
                Text(threshold.wrappedValue.compagnia ?? "Tutte")
                    .frame(width: 150, alignment: .leading)
                    .foregroundColor(threshold.wrappedValue.compagnia == nil ? .orange : .primary)
                    .font(GDS.Typography.small)
            }
            
            // Soglia danno
            HStack {
                Text("€")
                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                TextField("Soglia", value: Binding(
                    get: { threshold.wrappedValue.value },
                    set: { newValue in
                        threshold.wrappedValue.value = newValue
                        saveDamageThresholds()
                    }
                ), formatter: numberFormatter)
            }
            .frame(width: showCompagnia ? 150 : 120)
            
            // Compenso
            HStack {
                Text("€")
                    .foregroundColor(GDS.SystemColors.secondaryLabel)
                TextField("Compenso", value: Binding(
                    get: { threshold.wrappedValue.compensation },
                    set: { newValue in
                        threshold.wrappedValue.compensation = newValue
                        saveDamageThresholds()
                    }
                ), formatter: numberFormatter)
            }
            .frame(width: showCompagnia ? 150 : 120)
            
            // Elimina
            Button(action: { deleteDamageThreshold(threshold.wrappedValue) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .frame(width: 40)
        }
        .padding(.vertical, GDS.Spacing.xs)
        .textFieldStyle(.roundedBorder)
    }
    
    private func addNewDamageThreshold(compagnia: String? = nil) {
        let newThreshold = DamageThreshold(value: 0, compensation: 0, compagnia: compagnia)
        damageThresholds.append(newThreshold)
        saveDamageThresholds()
    }
    
    private func deleteDamageThreshold(_ threshold: DamageThreshold) {
        damageThresholds.removeAll { $0.id == threshold.id }
        saveDamageThresholds()
    }
    
    private func saveRanges() {
        // Sincronizza le modifiche con FatturatoSettings
        syncRangesToFatturatoSettings()
    }
    
    private func saveDamageThresholds() {
        // Sincronizza le modifiche con FatturatoSettings
        syncDamageThresholdsToFatturatoSettings()
    }
    
    private func syncRangesToFatturatoSettings() {
        // Aggiorna importoBase e importoBaseDieciBeni dalla fascia base
        if let baseRange = ranges.first(where: { $0.isBase }) {
            fatturatoSettings.importoBase = baseRange.compensation
            fatturatoSettings.importoBaseDieciBeni = baseRange.extraCompensation
        }
        
        // Converti le fasce non-base in FasciaNumero
        var nuoveFasce: [FatturatoSettings.FasciaNumero] = []
        for range in ranges where !range.isBase {
            nuoveFasce.append(FatturatoSettings.FasciaNumero(
                numeroSinistri: Int(range.threshold),
                percentualeIncremento: range.incentivePercentage,
                importoFatturazione: range.compensation
            ))
        }
        // Ordina per numero sinistri
        nuoveFasce.sort { $0.numeroSinistri < $1.numeroSinistri }
        fatturatoSettings.fasce = nuoveFasce
    }
    
    private func syncDamageThresholdsToFatturatoSettings() {
        let nuoveSoglie = damageThresholds.map { threshold in
            FatturatoSettings.SogliaDanno(
                valoreDanno: threshold.value,
                importoFatturazione: threshold.compensation,
                compagnia: threshold.compagnia,
                escludiSeSpecifica: threshold.escludiSeSpecifica
            )
        }
        fatturatoSettings.soglie = nuoveSoglie
    }
    
    private func loadRangesFromFatturatoSettings() {
        var nuoveRanges: [CompensationRange] = []
        
        // Aggiungi la fascia base
        nuoveRanges.append(CompensationRange(
            level: 0,
            threshold: 0,
            incentivePercentage: 0,
            compensation: fatturatoSettings.importoBase,
            extraCompensation: fatturatoSettings.importoBaseDieciBeni,
            isBase: true
        ))
        
        // Aggiungi le altre fasce
        for (index, fascia) in fatturatoSettings.fasce.enumerated() {
            nuoveRanges.append(CompensationRange(
                level: index + 1,
                threshold: Double(fascia.numeroSinistri),
                incentivePercentage: fascia.percentualeIncremento,
                compensation: fascia.importoFatturazione,
                extraCompensation: fatturatoSettings.importoBaseDieciBeni, // Importo fisso, senza moltiplicatore
                isBase: false
            ))
        }
        
        ranges = nuoveRanges
    }
    
    private func loadDamageThresholdsFromFatturatoSettings() {
        damageThresholds = fatturatoSettings.soglie.map { soglia in
            DamageThreshold(
                value: soglia.valoreDanno,
                compensation: soglia.importoFatturazione,
                compagnia: soglia.compagnia,
                escludiSeSpecifica: soglia.escludiSeSpecifica
            )
        }
    }
    
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        return formatter
    }
    
    private var intFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    private var percentFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    private func loadDefaultRanges() {
        loadRangesFromFatturatoSettings()
    }
    
    private func loadDefaultDamageThresholds() {
        loadDamageThresholdsFromFatturatoSettings()
    }
}

struct CompensationRange: Codable, Identifiable, Equatable {
    var id = UUID()
    var level: Int
    var threshold: Double
    var incentivePercentage: Double
    var compensation: Double
    var extraCompensation: Double
    var isBase: Bool
    
    static var defaultRanges: Data {
        // Nota: extraCompensation è FISSO a €40 per tutte le fasce (non subisce il moltiplicatore)
        let ranges = [
            CompensationRange(level: 0, threshold: 0, incentivePercentage: 0, compensation: 25.00, extraCompensation: 40.00, isBase: true),
            CompensationRange(level: 1, threshold: 50, incentivePercentage: 0.10, compensation: 27.50, extraCompensation: 40.00, isBase: false),
            CompensationRange(level: 2, threshold: 75, incentivePercentage: 0.15, compensation: 28.75, extraCompensation: 40.00, isBase: false),
            CompensationRange(level: 3, threshold: 100, incentivePercentage: 0.20, compensation: 30.00, extraCompensation: 40.00, isBase: false),
            CompensationRange(level: 4, threshold: 130, incentivePercentage: 0.25, compensation: 31.25, extraCompensation: 40.00, isBase: false)
        ]
        return (try? JSONEncoder().encode(ranges)) ?? Data()
    }
}

struct DamageThreshold: Codable, Identifiable, Equatable {
    var id = UUID()
    var value: Double
    var compensation: Double
    var compagnia: String? // nil = regola generica per tutte le compagnie
    /// Se true e compagnia è nil, questa soglia si applica solo a compagnie senza regole specifiche ("tutte tranne")
    /// Se false e compagnia è nil, questa soglia si applica a TUTTE le compagnie indiscriminatamente
    var escludiSeSpecifica: Bool = true
    
    var isGenerica: Bool {
        compagnia == nil || compagnia?.isEmpty == true
    }
    
    init(id: UUID = UUID(), value: Double, compensation: Double, compagnia: String? = nil, escludiSeSpecifica: Bool = true) {
        self.id = id
        self.value = value
        self.compensation = compensation
        self.compagnia = compagnia
        self.escludiSeSpecifica = escludiSeSpecifica
    }
    
    // Retrocompatibilità per dati esistenti senza compagnia
    enum CodingKeys: String, CodingKey {
        case id, value, compensation, compagnia, escludiSeSpecifica
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.value = try container.decode(Double.self, forKey: .value)
        self.compensation = try container.decode(Double.self, forKey: .compensation)
        self.compagnia = try? container.decode(String.self, forKey: .compagnia)
        self.escludiSeSpecifica = (try? container.decode(Bool.self, forKey: .escludiSeSpecifica)) ?? true
    }
    
    static var defaultData: Data {
        let thresholds = [
            DamageThreshold(value: 10000, compensation: 100),
            DamageThreshold(value: 20000, compensation: 200),
            DamageThreshold(value: 30000, compensation: 300),
            DamageThreshold(value: 40000, compensation: 400),
            DamageThreshold(value: 50000, compensation: 500)
        ]
        return (try? JSONEncoder().encode(thresholds)) ?? Data()
    }
} 