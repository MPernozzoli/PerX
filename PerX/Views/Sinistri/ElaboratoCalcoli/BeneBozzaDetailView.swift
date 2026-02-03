import SwiftUI
import CoreData

/// View per editing beni in bozza (senza partita assegnata)
struct BeneBozzaDetailView: View {
    @ObservedObject var bene: Bene
    @ObservedObject var perizia: Perizia
    let onClose: (() -> Void)?
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    
    @State private var showDeleteConfirmation: Bool = false
    @State private var showAssignSheet: Bool = false
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(bene.nome)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("(Bozza)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                
                Spacer()
                
                Button {
                    showAssignSheet = true
                } label: {
                    Label("Assegna a Partita", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
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
                Text("Questa azione non può essere annullata.")
            }
            .sheet(isPresented: $showAssignSheet) {
                AssignToPartitaSheet(bene: bene, perizia: perizia, onAssign: {
                    showAssignSheet = false
                    onClose?()
                })
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
                                    Text("Nome:")
                                        .foregroundColor(.secondary)
                                    TextField("Nome bene", text: Binding(
                                        get: { bene.nome },
                                        set: { 
                                            bene.nome = $0
                                            try? viewContext.save()
                                        }
                                    ))
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
                                    Text("Modello:")
                                        .foregroundColor(.secondary)
                                    TextField("Modello", text: Binding(
                                        get: { bene.modello ?? "" },
                                        set: { 
                                            bene.modello = $0.isEmpty ? nil : $0
                                            try? viewContext.save()
                                        }
                                    ))
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
                                    Text("Anno:")
                                        .foregroundColor(.secondary)
                                    HStack {
                                        TextField("Anno", text: Binding(
                                            get: { bene.anno > 0 ? String(bene.anno) : "" },
                                            set: { newValue in
                                                if let anno = Int16(newValue.filter { $0.isNumber }) {
                                                    bene.anno = anno
                                                } else if newValue.isEmpty {
                                                    bene.anno = 0
                                                }
                                                try? viewContext.save()
                                            }
                                        ))
                                        .frame(width: 80)
                                        
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
                                    Text("Garanzia:")
                                        .foregroundColor(.secondary)
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
                        sinistroPath: perizia.sinistro?.cartella
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
    }
    
    private func deleteBene() {
        // Chiude la view PRIMA di eliminare per evitare crash
        onClose?()
        
        // Esegui l'eliminazione dopo un breve delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for voce in bene.vociCostoArray {
                viewContext.delete(voce)
            }
            viewContext.delete(bene)
            try? viewContext.save()
        }
    }
}

/// Sheet per assegnare un bene bozza a una partita
struct AssignToPartitaSheet: View {
    @ObservedObject var bene: Bene
    @ObservedObject var perizia: Perizia
    let onAssign: () -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPartita: Partita?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Assegna a Partita")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Seleziona la partita a cui assegnare il bene '\(bene.nome)'")
                .foregroundColor(.secondary)
            
            if perizia.partiteArray.isEmpty {
                Text("Nessuna partita disponibile. Crea prima una partita nella sezione Perizia.")
                    .foregroundColor(.orange)
                    .italic()
                    .padding()
            } else {
                Picker("Partita", selection: $selectedPartita) {
                    Text("Seleziona...").tag(nil as Partita?)
                    ForEach(perizia.partiteArray) { partita in
                        Text(partita.nomeEditabile).tag(partita as Partita?)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Assegna") {
                    assignToPartita()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPartita == nil)
            }
        }
        .padding(30)
        .frame(minWidth: 400)
    }
    
    private func assignToPartita() {
        guard let partita = selectedPartita else { return }
        
        // Rimuove dalla bozza e assegna alla partita
        bene.periziaBozza = nil
        bene.partita = partita
        bene.ordine = Int16(partita.beniArray.count)
        
        try? viewContext.save()
        onAssign()
    }
}
