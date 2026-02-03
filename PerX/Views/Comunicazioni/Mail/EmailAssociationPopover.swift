import SwiftUI
import CoreData

struct EmailAssociationPopover: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let email: Email
    let suggestedSinistri: [Sinistro]
    @State private var searchText = ""
    @State private var selectedSinistri: Set<Sinistro> = []
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default
    ) private var allSinistri: FetchedResults<Sinistro>
    
    let onAssociate: ([Sinistro]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Associa Email a Sinistro")
                    .font(.headline)
                
                Text(email.subject)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Sinistri suggeriti (se presenti)
            if !suggestedSinistri.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        Text("Suggerimenti")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ForEach(suggestedSinistri, id: \.objectID) { sinistro in
                        SinistroCheckboxRow(
                            sinistro: sinistro,
                            isSelected: selectedSinistri.contains(sinistro),
                            onToggle: {
                                if selectedSinistri.contains(sinistro) {
                                    selectedSinistri.remove(sinistro)
                                } else {
                                    selectedSinistri.insert(sinistro)
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
            }
            
            // Barra di ricerca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca per nome, numero sinistro o agenzia...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Lista sinistri filtrati
            List(filteredSinistri, id: \.objectID) { sinistro in
                SinistroCheckboxRow(
                    sinistro: sinistro,
                    isSelected: selectedSinistri.contains(sinistro),
                    onToggle: {
                        if selectedSinistri.contains(sinistro) {
                            selectedSinistri.remove(sinistro)
                        } else {
                            selectedSinistri.insert(sinistro)
                        }
                    }
                )
            }
            .frame(maxHeight: 300)
            
            // Pulsanti
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Associa") {
                    onAssociate(Array(selectedSinistri))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSinistri.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private var filteredSinistri: [Sinistro] {
        let filtered = allSinistri.filter { sinistro in
            if searchText.isEmpty { return true }
            
            let searchLower = searchText.lowercased()
            return (sinistro.riferimento ?? "").lowercased().contains(searchLower) ||
                   (sinistro.numeroSinistroCompagnia ?? "").lowercased().contains(searchLower) ||
                   (sinistro.nomeContraente ?? "").lowercased().contains(searchLower) ||
                   (sinistro.nomeAssicurato ?? "").lowercased().contains(searchLower) ||
                   (sinistro.nomeDanneggiato ?? "").lowercased().contains(searchLower)
        }
        
        // Ordina: prima i suggeriti, poi gli altri
        return filtered.sorted { sinistro1, sinistro2 in
            let isSuggested1 = suggestedSinistri.contains(sinistro1)
            let isSuggested2 = suggestedSinistri.contains(sinistro2)
            if isSuggested1 != isSuggested2 {
                return isSuggested1
            }
            return (sinistro1.riferimento ?? "") < (sinistro2.riferimento ?? "")
        }
    }
}

struct SinistroCheckboxRow: View {
    let sinistro: Sinistro
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sinistro.riferimentoVisualizzato)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let numeroCompagnia = sinistro.numeroSinistroCompagnia, !numeroCompagnia.isEmpty {
                        Text("N. Agenzia: \(numeroCompagnia)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let nome = sinistro.nomeContraente ?? sinistro.nomeAssicurato, !nome.isEmpty {
                        Text("Assicurato: \(nome)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

