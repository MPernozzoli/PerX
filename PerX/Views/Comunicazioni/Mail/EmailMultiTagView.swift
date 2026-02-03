import SwiftUI
import CoreData

struct EmailMultiTagView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let email: Email
    @State private var selectedSinistri: Set<Sinistro> = []
    @State private var searchText = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default
    ) private var allSinistri: FetchedResults<Sinistro>
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header con info email
                EmailInfoHeaderMultiView(email: email)
                
                // Riferimenti automaticamente rilevati
                if !autoDetectedReferences.isEmpty {
                    AutoDetectedReferencesMultiView(
                        references: autoDetectedReferences,
                        selectedSinistri: $selectedSinistri,
                        allSinistri: Array(allSinistri)
                    )
                }
                
                // Ricerca e selezione manuale
                VStack(alignment: .leading, spacing: 12) {
                    Text("Associa manualmente ad altri sinistri")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    // Barra di ricerca
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Cerca sinistro...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                    
                    // Lista sinistri
                    List(filteredSinistri, id: \.objectID) { sinistro in
                        SinistroSelectionRowMultiView(
                            sinistro: sinistro,
                            isSelected: selectedSinistri.contains(sinistro),
                            onToggle: { isSelected in
                                if isSelected {
                                    selectedSinistri.insert(sinistro)
                                } else {
                                    selectedSinistri.remove(sinistro)
                                }
                            }
                        )
                        .id("\(sinistro.objectID)-\(sinistro.riferimento ?? "")")
                    }
                    .id(searchText)
                }
            }
            .navigationTitle("Associa Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Salva") {
                        saveAssociations()
                    }
                    .disabled(selectedSinistri.isEmpty)
                }
            }
        }
        .onAppear {
            loadCurrentAssociations()
        }
    }
    
    private var autoDetectedReferences: [String] {
        // Estrae tutti i riferimenti automaticamente rilevati
        return MailViewModel.shared.extractAllRiferimenti(from: email)
    }
    
    private var filteredSinistri: [Sinistro] {
        let filtered = allSinistri.filter { sinistro in
            if searchText.isEmpty { return true }
            
            return (sinistro.riferimento ?? "").localizedCaseInsensitiveContains(searchText) ||
                   (sinistro.numeroSinistroCompagnia ?? "").localizedCaseInsensitiveContains(searchText) ||
                   (sinistro.nomeContraente ?? "").localizedCaseInsensitiveContains(searchText)
        }
        
        return Array(filtered)
    }
    
    private func loadCurrentAssociations() {
        // TODO: Carica le associazioni esistenti dal TagManager
        // Per ora vuoto, da implementare quando avremo il sistema di tag multi-sinistro
    }
    
    private func saveAssociations() {
        // TODO: Salva le associazioni usando il TagManager
        // Per ora solo dismiss, da implementare quando avremo il sistema di tag multi-sinistro
        dismiss()
    }
}

struct EmailInfoHeaderMultiView: View {
    let email: Email
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email da associare")
                .font(.headline)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(email.subject)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("Da: \(email.sender.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Data: \(email.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}

struct AutoDetectedReferencesMultiView: View {
    let references: [String]
    @Binding var selectedSinistri: Set<Sinistro>
    let allSinistri: [Sinistro]
    
    var body: some View {
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Riferimenti rilevati automaticamente")
                    .font(.headline)
                    .foregroundColor(.green)
                
                ForEach(references, id: \.self) { riferimento in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        if let sinistro = findSinistro(byRiferimento: riferimento) {
                            Text("Riferimento: \(sinistro.riferimentoVisualizzato)")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Trovato sinistro")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                if let nome = sinistro.nomeContraente, !nome.isEmpty {
                                    Text(nome)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("Riferimento: \(riferimento)")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("Sinistro non trovato")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
    
    private func findSinistro(byRiferimento riferimento: String) -> Sinistro? {
        return allSinistri.first { $0.riferimento == riferimento }
    }
}

struct SinistroSelectionRowMultiView: View {
    let sinistro: Sinistro
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                onToggle(!isSelected)
            }) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sinistro.riferimentoVisualizzato)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let numeroCompagnia = sinistro.numeroSinistroCompagnia, !numeroCompagnia.isEmpty {
                            Text("N. Compagnia: \(numeroCompagnia)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let nome = sinistro.nomeContraente, !nome.isEmpty {
                            Text("Contraente: \(nome)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct EmailMultiTagView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview placeholder per evitare problemi con Core Data e binding
        Text("EmailMultiTagView Preview")
            .padding()
    }
}
