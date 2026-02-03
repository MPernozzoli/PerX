import SwiftUI
import CoreData

struct CoassicurazioniView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showAddCoassicurazione = false
    @State private var editingCoassicurazione: Coassicurazione?
    
    var coassicurazioniArray: [Coassicurazione] {
        let set = sinistro.coassicurazioni as? Set<Coassicurazione> ?? []
        return set.sorted { $0.ordine < $1.ordine }
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Coassicurazioni")
                        .font(.headline)
                    Spacer()
                    Button {
                        showAddCoassicurazione = true
                    } label: {
                        Label("Aggiungi Coassicurazione", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                if coassicurazioniArray.isEmpty {
                    Text("Nessuna coassicurazione")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                } else {
                    ForEach(coassicurazioniArray) { coassicurazione in
                        CoassicurazioneRowView(
                            coassicurazione: coassicurazione,
                            onEdit: {
                                editingCoassicurazione = coassicurazione
                            }
                        )
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .sheet(isPresented: $showAddCoassicurazione) {
            CoassicurazioneEditView(sinistro: sinistro, coassicurazione: nil)
        }
        .sheet(item: $editingCoassicurazione) { coassicurazione in
            CoassicurazioneEditView(sinistro: sinistro, coassicurazione: coassicurazione)
        }
    }
}

struct CoassicurazioneRowView: View {
    @ObservedObject var coassicurazione: Coassicurazione
    @Environment(\.managedObjectContext) private var viewContext
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(coassicurazione.tipo)
                    .font(.headline)
                Text("\(coassicurazione.compagnia) - Polizza: \(coassicurazione.polizza)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Sinistro: \(coassicurazione.numeroSinistro)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            Button {
                deleteCoassicurazione()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func deleteCoassicurazione() {
        viewContext.delete(coassicurazione)
        try? viewContext.save()
    }
}

struct CoassicurazioneEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    let coassicurazione: Coassicurazione?
    
    @State private var tipo: String = "Diretta"
    @State private var compagnia: String = ""
    @State private var polizza: String = ""
    @State private var numeroSinistro: String = ""
    
    private let tipi = ["Diretta", "Indiretta"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Dati Coassicurazione") {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(tipi, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    
                    TextField("Compagnia", text: $compagnia)
                    TextField("Polizza", text: $polizza)
                    TextField("Numero Sinistro", text: $numeroSinistro)
                }
            }
            .navigationTitle(coassicurazione == nil ? "Aggiungi Coassicurazione" : "Modifica Coassicurazione")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveCoassicurazione()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
        .onAppear {
            if let coassicurazione = coassicurazione {
                loadCoassicurazione(coassicurazione)
            }
        }
    }
    
    private func loadCoassicurazione(_ coassicurazione: Coassicurazione) {
        tipo = coassicurazione.tipo
        compagnia = coassicurazione.compagnia
        polizza = coassicurazione.polizza
        numeroSinistro = coassicurazione.numeroSinistro
    }
    
    private func saveCoassicurazione() {
        viewContext.performAndWait {
            let coassicurazioneToSave: Coassicurazione
            if let existing = coassicurazione {
                coassicurazioneToSave = existing
            } else {
                coassicurazioneToSave = Coassicurazione(context: viewContext)
                coassicurazioneToSave.id = UUID()
                coassicurazioneToSave.sinistro = sinistro
                let existing = sinistro.coassicurazioni as? Set<Coassicurazione> ?? []
                coassicurazioneToSave.ordine = Int16(existing.count)
            }
            
            coassicurazioneToSave.tipo = tipo
            coassicurazioneToSave.compagnia = compagnia
            coassicurazioneToSave.polizza = polizza
            coassicurazioneToSave.numeroSinistro = numeroSinistro
            
            try? viewContext.save()
        }
    }
}

