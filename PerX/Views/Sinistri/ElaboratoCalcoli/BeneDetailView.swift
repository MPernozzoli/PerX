import SwiftUI
import CoreData

struct BeneDetailView: View {
    @ObservedObject var bene: Bene
    @ObservedObject var partita: Partita
    @ObservedObject var perizia: Perizia
    let onClose: (() -> Void)?
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    @StateObject private var autoTaggingService = AutoTaggingService.shared
    @StateObject private var beneSyncService = BeneSyncService.shared
    
    // Stato sincronizzazione campi (attivo = sincronizza con foto/Perxia)
    @State private var syncNomeAttivo: Bool = true
    @State private var syncModelloAttivo: Bool = true
    @State private var syncAnnoAttivo: Bool = true
    @State private var vecchioNomeBene: String = ""
    
    // Verifica se ci sono collegamenti
    @State private var hasFotoCollegate: Bool = false
    @State private var hasPerxiaCollegato: Bool = false
    
    @State private var showDeleteConfirmation: Bool = false
    
    // Bindings per parametri calcolo
    private var ivaInclusa: Binding<Bool> {
        Binding(
            get: { bene.ivaInclusa },
            set: { 
                bene.ivaInclusa = $0
                try? viewContext.save()
            }
        )
    }
    
    private var diversiPerRiga: Binding<Bool> {
        Binding(
            get: { bene.diversiPerRiga },
            set: { 
                bene.diversiPerRiga = $0
                try? viewContext.save()
            }
        )
    }
    
    private var riconosciIVA: Binding<Bool> {
        Binding(
            get: { bene.riconosciIVA },
            set: { 
                bene.riconosciIVA = $0
                try? viewContext.save()
            }
        )
    }
    
    // Binding per deprezzamento e aliquota IVA dal bene
    private var deprezzamento: Binding<Double> {
        Binding(
            get: { bene.deprezzamento > 0 ? bene.deprezzamento : 20.0 },
            set: { 
                bene.deprezzamento = $0
                try? viewContext.save()
            }
        )
    }
    
    private var aliquotaIVA: Binding<Double> {
        Binding(
            get: { bene.aliquotaIVA > 0 ? bene.aliquotaIVA : 22.0 },
            set: { 
                bene.aliquotaIVA = $0
                try? viewContext.save()
            }
        )
    }
    
    // Suggerimenti beni
    @State private var beniSuggeriti: [String] = []
    @State private var nomeBeneSuggested: Bool = false
    @State private var marcaSuggested: Bool = false
    @State private var modelloSuggested: Bool = false
    @State private var annoSuggested: Bool = false
    
    // Suggerimenti da Perxia
    @State private var perxiaSuggestedModello: String? = nil
    @State private var perxiaSuggestedAnno: String? = nil
    
    // Suggerimenti da giustificativi
    @State private var componentFromGiustificativi: [String] = []
    
    private var sinistroPath: String? {
        perizia.sinistro?.cartella
    }
    
    private var perxiaBeneCorrispondente: PerxiaBene? {
        perizia.sinistro?.beniPerxia.first { perxiaBene in
            perxiaBene.tipologia.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame
        }
    }
    
    private let confidenceThreshold: Double = 0.76
    
    init(bene: Bene, partita: Partita, perizia: Perizia, onClose: (() -> Void)? = nil) {
        self.bene = bene
        self.partita = partita
        self.perizia = perizia
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con titolo e pulsanti
            HStack {
                Text(bene.nome)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if bene.partita == nil {
                    Text("(Bozza)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                
                if let onClose = onClose {
                    Button {
                        onClose()
                    } label: {
                        Label("Chiudi", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .confirmationDialog(
                "Eliminare il bene '\(bene.nome)'?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    deleteBene()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Questa azione non può essere annullata. Tutte le voci di costo associate verranno eliminate.")
            }
            
            Divider()
            
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Dati bene
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dati Bene")
                            .font(.headline)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                HStack(spacing: 4) {
                                    Text("Nome:")
                                    if hasFotoCollegate || hasPerxiaCollegato {
                                        Button {
                                            syncNomeAttivo.toggle()
                                        } label: {
                                            Image(systemName: syncNomeAttivo ? "link" : "link.badge.plus")
                                                .font(.caption)
                                                .foregroundColor(syncNomeAttivo ? .blue : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(syncNomeAttivo ? "Sincronizzato con foto/Perxia (clicca per disattivare)" : "Non sincronizzato (clicca per attivare)")
                                    }
                                }
                                .foregroundColor(.secondary)
                                
                                SuggestedTextField(
                                    label: "",
                                    text: Binding(
                                        get: { bene.nome },
                                        set: { nuovoNome in
                                            let vecchio = bene.nome
                                            bene.nome = nuovoNome
                                            try? viewContext.save()
                                            // Sincronizza se attivo
                                            if syncNomeAttivo && (hasFotoCollegate || hasPerxiaCollegato) {
                                                beneSyncService.sincronizzaNome(
                                                    bene: bene,
                                                    vecchioNome: vecchio,
                                                    nuovoNome: nuovoNome,
                                                    sinistroPath: sinistroPath,
                                                    viewContext: viewContext
                                                )
                                            }
                                        }
                                    ),
                                    placeholder: "Nome bene",
                                    suggestions: beniSuggeriti,
                                    isSuggested: nomeBeneSuggested,
                                    onConfirm: {
                                        nomeBeneSuggested = false
                                    }
                                )
                            }
                            
                            GridRow {
                                Text("Marca:")
                                    .foregroundColor(.secondary)
                                TextField("Marca", text: Binding(
                                    get: { bene.marca ?? "" },
                                    set: { 
                                        bene.marca = $0.isEmpty ? nil : $0
                                        try? viewContext.save()
                                    }
                                ))
                            }
                            
                            GridRow {
                                HStack(spacing: 4) {
                                    Text("Modello:")
                                    if hasPerxiaCollegato {
                                        Button {
                                            syncModelloAttivo.toggle()
                                        } label: {
                                            Image(systemName: syncModelloAttivo ? "link" : "link.badge.plus")
                                                .font(.caption)
                                                .foregroundColor(syncModelloAttivo ? .blue : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(syncModelloAttivo ? "Sincronizzato con Perxia (clicca per disattivare)" : "Non sincronizzato (clicca per attivare)")
                                    }
                                }
                                .foregroundColor(.secondary)
                                
                                SuggestedTextField(
                                    label: "",
                                    text: Binding(
                                        get: { bene.modello ?? perxiaSuggestedModello ?? "" },
                                        set: { nuovoModello in
                                            bene.modello = nuovoModello.isEmpty ? nil : nuovoModello
                                            modelloSuggested = false
                                            try? viewContext.save()
                                            // Sincronizza se attivo
                                            if syncModelloAttivo && hasPerxiaCollegato {
                                                beneSyncService.sincronizzaModello(
                                                    bene: bene,
                                                    nuovoModello: nuovoModello.isEmpty ? nil : nuovoModello,
                                                    viewContext: viewContext
                                                )
                                            }
                                        }
                                    ),
                                    placeholder: "Modello",
                                    suggestions: perxiaSuggestedModello != nil ? [perxiaSuggestedModello!] : [],
                                    isSuggested: modelloSuggested,
                                    onConfirm: {
                                        modelloSuggested = false
                                    }
                                )
                            }
                            
                            GridRow {
                                Text("Numero di serie:")
                                    .foregroundColor(.secondary)
                                TextField("Numero di serie", text: Binding(
                                    get: { bene.numeroSerie ?? "" },
                                    set: { 
                                        bene.numeroSerie = $0.isEmpty ? nil : $0
                                        try? viewContext.save()
                                    }
                                ))
                            }
                            
                            GridRow {
                                HStack(spacing: 4) {
                                    Text("Anno:")
                                    if hasPerxiaCollegato {
                                        Button {
                                            syncAnnoAttivo.toggle()
                                        } label: {
                                            Image(systemName: syncAnnoAttivo ? "link" : "link.badge.plus")
                                                .font(.caption)
                                                .foregroundColor(syncAnnoAttivo ? .blue : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(syncAnnoAttivo ? "Sincronizzato con Perxia (clicca per disattivare)" : "Non sincronizzato (clicca per attivare)")
                                    }
                                }
                                .foregroundColor(.secondary)
                                
                                HStack {
                                    SuggestedTextField(
                                        label: "",
                                        text: Binding(
                                            get: {
                                                if bene.anno > 0 {
                                                    return String(bene.anno)
                                                } else if let suggested = perxiaSuggestedAnno {
                                                    return suggested
                                                }
                                                return ""
                                            },
                                            set: { newValue in
                                                if let anno = Int16(newValue.filter { $0.isNumber }) {
                                                    bene.anno = anno
                                                } else if newValue.isEmpty {
                                                    bene.anno = 0
                                                }
                                                annoSuggested = false
                                                try? viewContext.save()
                                                // Sincronizza se attivo
                                                if syncAnnoAttivo && hasPerxiaCollegato {
                                                    beneSyncService.sincronizzaAnno(
                                                        bene: bene,
                                                        nuovoAnno: newValue.isEmpty ? nil : newValue,
                                                        viewContext: viewContext
                                                    )
                                                }
                                            }
                                        ),
                                        placeholder: "Anno",
                                        suggestions: perxiaSuggestedAnno != nil ? [perxiaSuggestedAnno!] : [],
                                        isSuggested: annoSuggested,
                                        onConfirm: {
                                            annoSuggested = false
                                        }
                                    )
                                    .frame(width: 100)
                                    
                                    Toggle("Stimata", isOn: Binding(
                                        get: { bene.stimata },
                                        set: { 
                                            bene.stimata = $0
                                            try? viewContext.save()
                                        }
                                    ))
                                }
                            }
                            
                            GridRow {
                                Text("Partita:")
                                    .foregroundColor(.secondary)
                                Text(partita.nomeEditabile)
                                    .foregroundColor(.primary)
                            }
                            
                            GridRow {
                                Text("Garanzia:")
                                    .foregroundColor(.secondary)
                                // Se c'è una sola garanzia, mostrala come testo statico
                                if perizia.garanzieArray.count == 1 {
                                    Text(perizia.garanzieArray.first?.nomeEditabile ?? "")
                                        .foregroundColor(.primary)
                                        .onAppear {
                                            // Preseleziona automaticamente l'unica garanzia
                                            if bene.garanzia == nil, let unicaGaranzia = perizia.garanzieArray.first {
                                                bene.garanzia = unicaGaranzia
                                                try? viewContext.save()
                                            }
                                        }
                                } else {
                                    Picker("", selection: Binding(
                                        get: { bene.garanzia },
                                        set: { 
                                            bene.garanzia = $0
                                            try? viewContext.save()
                                        }
                                    )) {
                                        Text("Nessuna").tag(nil as Garanzia?)
                                        ForEach(perizia.garanzieArray) { garanzia in
                                            Text(garanzia.nomeEditabile).tag(garanzia as Garanzia?)
                                        }
                                    }
                                }
                            }
                            
                            GridRow {
                                Text("Determinazione danno:")
                                    .foregroundColor(.secondary)
                                Picker("", selection: Binding(
                                    get: { bene.determinazioneDanno ?? partita.determinazioneDanno },
                                    set: { 
                                        bene.determinazioneDanno = $0 == partita.determinazioneDanno ? nil : $0
                                        try? viewContext.save()
                                    }
                                )) {
                                    Text(abbreviaDeterminazione(partita.determinazioneDanno)).tag(partita.determinazioneDanno)
                                    ForEach(["Valore a nuovo", "Valore allo stato d'uso più supplemento d'indennizzo", "VSU + SI (max doppio)", "VSU + SI (max triplo)", "VSU + SI (max quadruplo)", "Valore allo stato d'uso"], id: \.self) { det in
                                        if det != partita.determinazioneDanno {
                                            Text(abbreviaDeterminazione(det)).tag(det)
                                        }
                                    }
                                }
                            }
                            
                            GridRow {
                                Text("Richiesta:")
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("Richiesta", value: Binding(
                                        get: { bene.richiesta?.doubleValue },
                                        set: { 
                                            bene.richiesta = $0 != nil ? NSDecimalNumber(value: $0!) : nil
                                            try? viewContext.save()
                                        }
                                    ), format: .number)
                                    .frame(width: 120)
                                    
                                    Toggle("IVA inclusa", isOn: Binding(
                                        get: { bene.ivaInclusa },
                                        set: { 
                                            bene.ivaInclusa = $0
                                            try? viewContext.save()
                                        }
                                    ))
                                }
                            }
                            
                            GridRow {
                                Text("Ripristini ultimati:")
                                    .foregroundColor(.secondary)
                                Toggle("", isOn: Binding(
                                    get: { bene.ripristiniUltimati },
                                    set: { 
                                        bene.ripristiniUltimati = $0
                                        try? viewContext.save()
                                    }
                                ))
                            }
                            
                            GridRow {
                                Text("Residui mantenuti:")
                                    .foregroundColor(.secondary)
                                Picker("", selection: Binding(
                                    get: { bene.residuiMantenuti ?? "si" },
                                    set: { 
                                        bene.residuiMantenuti = $0
                                        try? viewContext.save()
                                        aggiornaResiduiPerizia()
                                        if $0 == "no" {
                                            impostaVociNonIndennizzabili()
                                        }
                                    }
                                )) {
                                    Text("Sì").tag("si")
                                    Text("Parziali").tag("parziali")
                                    Text("No").tag("no")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                            
                            GridRow {
                                Text("Tipo intervento:")
                                    .foregroundColor(.secondary)
                                Picker("", selection: Binding(
                                    get: { bene.sostituzioneIntero },
                                    set: { 
                                        bene.sostituzioneIntero = $0
                                        try? viewContext.save()
                                    }
                                )) {
                                    Text("Riparazione").tag(false)
                                    Text("Sostituzione intero").tag(true)
                                }
                            }
                            
                            GridRow {
                                Text("Relazione tecnica:")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TextField("Relazione tecnica del bene", text: Binding(
                            get: { bene.relazioneTecnica ?? "" },
                            set: { 
                                bene.relazioneTecnica = $0.isEmpty ? nil : $0
                                try? viewContext.save()
                            }
                        ), axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                }
                .backgroundStyle(.regularMaterial)
                
                // Parametri comuni
                ParametriCalcoloView(
                    deprezzamento: deprezzamento,
                    aliquotaIVA: aliquotaIVA,
                    ivaInclusa: ivaInclusa,
                    diversiPerRiga: diversiPerRiga,
                    riconosciIVA: riconosciIVA
                )
                
                // Voci di costo
                VociCostoView(
                    bene: bene,
                    deprezzamento: deprezzamento.wrappedValue,
                    aliquotaIVA: aliquotaIVA.wrappedValue,
                    ivaInclusa: ivaInclusa.wrappedValue,
                    determinazioneDanno: bene.determinazioneDannoEffettiva,
                    diversiPerRiga: diversiPerRiga,
                    sinistroPath: sinistroPath,
                    componentiFromGiustificativi: componentFromGiustificativi
                )
                
                // Totali
                TotaliBeneView(
                    bene: bene,
                    deprezzamento: deprezzamento,
                    aliquotaIVA: aliquotaIVA,
                    ivaInclusa: ivaInclusa.wrappedValue,
                    determinazioneDanno: bene.determinazioneDannoEffettiva,
                    riconosciIVA: riconosciIVA.wrappedValue
                )
            }
            .padding()
            }
        }
        .task {
            await loadBeniSuggeriti()
        }
    }
    
    private func loadBeniSuggeriti() async {
        guard let path = sinistroPath else { return }
        beniSuggeriti = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
        
        // Verifica collegamenti con foto e Perxia
        hasFotoCollegate = beneSyncService.hasFotoAssociate(bene: bene, sinistroPath: path)
        hasPerxiaCollegato = beneSyncService.getPerxiaBeneCorrispondente(bene: bene, sinistro: perizia.sinistro) != nil
        
        // Carica suggerimenti da Perxia
        loadPerxiaSuggestions()
        
        // Carica suggerimenti da giustificativi
        loadGiustificativiSuggestions()
    }
    
    private func loadPerxiaSuggestions() {
        guard let perxiaBene = perxiaBeneCorrispondente else { return }
        
        // Modello con alta confidence
        if perxiaBene.certezzaModello >= confidenceThreshold,
           let modello = perxiaBene.modello, !modello.isEmpty,
           bene.modello == nil || bene.modello?.isEmpty == true {
            perxiaSuggestedModello = modello
            modelloSuggested = true
        }
        
        // Anno con alta confidence
        if perxiaBene.certezzaAnno >= confidenceThreshold,
           let anno = perxiaBene.anno, !anno.isEmpty,
           bene.anno == 0 {
            perxiaSuggestedAnno = anno
            annoSuggested = true
        }
    }
    
    private func loadGiustificativiSuggestions() {
        guard let sinistro = perizia.sinistro,
              let context = autoTaggingService.getDocumentiContext(for: sinistro) else { return }
        
        // Cerca beni attesi corrispondenti al nome del bene
        let beniCorrispondenti = context.beniAttesi.filter { beneAtteso in
            beneAtteso.nome.localizedCaseInsensitiveContains(bene.nome) ||
            bene.nome.localizedCaseInsensitiveContains(beneAtteso.nome)
        }
        
        // Estrai componenti dai beni corrispondenti
        componentFromGiustificativi = beniCorrispondenti.flatMap { $0.componenti }
    }
    
    /// Abbrevia le determinazioni del danno per ridurre lo spazio
    private func abbreviaDeterminazione(_ det: String) -> String {
        switch det {
        case "Valore allo stato d'uso più supplemento d'indennizzo":
            return "VSU + SI"
        case "Valore a nuovo":
            return "Valore a nuovo"
        case "Valore allo stato d'uso":
            return "VSU"
        default:
            return det
        }
    }
    
    /// Aggiorna il campo mantenimentoResidui della perizia in base ai beni
    private func aggiornaResiduiPerizia() {
        // Raccogli tutti i beni da tutte le partite
        var tuttiBeni: [Bene] = []
        for partita in perizia.partiteArray {
            tuttiBeni.append(contentsOf: partita.beniArray)
        }
        
        // Determina il valore complessivo
        let residuiValues = tuttiBeni.compactMap { $0.residuiMantenuti }
        
        if residuiValues.isEmpty {
            perizia.mantenimentoResidui = "si"
        } else if residuiValues.allSatisfy({ $0 == "no" }) {
            perizia.mantenimentoResidui = "no"
        } else if residuiValues.contains("no") || residuiValues.contains("parziali") {
            perizia.mantenimentoResidui = "parziali"
        } else {
            perizia.mantenimentoResidui = "si"
        }
        
        try? viewContext.save()
    }
    
    /// Imposta tutte le voci di costo come non indennizzabili quando residui = no
    private func impostaVociNonIndennizzabili() {
        for voce in bene.vociCostoArray {
            voce.indennizzabile = false
        }
        try? viewContext.save()
    }
    
    /// Elimina il bene e le sue voci di costo
    private func deleteBene() {
        // Chiude la view PRIMA di eliminare per evitare crash
        onClose?()
        
        // Esegui l'eliminazione dopo un breve delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Prima rimuove le voci di costo
            for voce in bene.vociCostoArray {
                viewContext.delete(voce)
            }
            // Poi elimina il bene
            viewContext.delete(bene)
            try? viewContext.save()
        }
    }
}

