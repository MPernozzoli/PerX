import SwiftUI
import AppKit

// MARK: - Modello per preview import

struct AgenziaImportItem: Identifiable {
    let id = UUID()
    let codice: String
    let nome: String
    let indirizzo: String
    let citta: String
    let telefoni: [String]
    let email: [String]
    let isNew: Bool
    let isModified: Bool
    var isSelected: Bool = true
    
    var isValid: Bool {
        !codice.isEmpty &&
        !codice.hasPrefix("IMPORT-") &&
        !nome.isEmpty &&
        !telefoni.isEmpty &&
        !email.isEmpty
    }
    
    var validationErrors: [String] {
        var errors: [String] = []
        if codice.isEmpty || codice.hasPrefix("IMPORT-") {
            errors.append("Codice mancante")
        }
        if nome.isEmpty {
            errors.append("Nome mancante")
        }
        if telefoni.isEmpty {
            errors.append("Telefono mancante")
        }
        if email.isEmpty {
            errors.append("Email mancante")
        }
        return errors
    }
}

// MARK: - Preview View

struct AgenziaImportPreviewView: View {
    let fileData: Data
    let onImport: ([AgenziaImportItem]) -> Void
    let onCancel: () -> Void
    
    @State private var items: [AgenziaImportItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showInvalid = false
    @State private var selectedTab = 0
    
    private var validItems: [AgenziaImportItem] {
        items.filter { $0.isValid }
    }
    
    private var invalidItems: [AgenziaImportItem] {
        items.filter { !$0.isValid }
    }
    
    private var newItems: [AgenziaImportItem] {
        validItems.filter { $0.isNew }
    }
    
    private var modifiedItems: [AgenziaImportItem] {
        validItems.filter { $0.isModified && !$0.isNew }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Nuove (\(newItems.count))").tag(0)
                    Text("Modificate (\(modifiedItems.count))").tag(1)
                    Text("Non valide (\(invalidItems.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                contentView
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 900, height: 600)
        .task {
            await parseData()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anteprima Import Agenzie")
                    .font(.title2.bold())
                Text("Verifica i dati prima dell'importazione")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !isLoading && errorMessage == nil {
                HStack(spacing: 16) {
                    Label("\(validItems.count) valide", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Label("\(invalidItems.count) non valide", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                .font(.callout)
            }
        }
        .padding()
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Analisi file in corso...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Errore durante l'analisi")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            agenzieTable(items: newItems, emptyMessage: "Nessuna nuova agenzia")
        case 1:
            agenzieTable(items: modifiedItems, emptyMessage: "Nessuna agenzia modificata")
        case 2:
            invalidAgenzieTable
        default:
            EmptyView()
        }
    }
    
    // MARK: - Agenzie Table
    
    private func agenzieTable(items: [AgenziaImportItem], emptyMessage: String) -> some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(emptyMessage)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("Codice")
                                .frame(width: 100, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                            Text("Nome")
                                .frame(width: 200, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                            Text("Indirizzo")
                                .frame(width: 200, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                            Text("Città")
                                .frame(width: 120, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                            Text("Telefono")
                                .frame(width: 150, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                            Text("Email")
                                .frame(width: 200, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                        }
                        .font(.headline)
                        
                        Divider()
                        
                        // Data rows
                        ForEach(items) { item in
                            agenziaRow(item)
                            Divider()
                        }
                    }
                }
            }
        }
    }
    
    private func agenziaRow(_ item: AgenziaImportItem) -> some View {
        HStack(spacing: 0) {
            Text(item.codice)
                .frame(width: 100, alignment: .leading)
                .padding(8)
                .foregroundColor(item.isNew ? .blue : .primary)
            Text(item.nome)
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .lineLimit(2)
            Text(item.indirizzo)
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(item.citta)
                .frame(width: 120, alignment: .leading)
                .padding(8)
                .foregroundColor(.secondary)
            Text(item.telefoni.first ?? "-")
                .frame(width: 150, alignment: .leading)
                .padding(8)
                .foregroundColor(.secondary)
            Text(item.email.first ?? "-")
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
    
    // MARK: - Invalid Agenzie Table
    
    private var invalidAgenzieTable: some View {
        Group {
            if invalidItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green.opacity(0.5))
                    Text("Tutte le agenzie sono valide!")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Info banner
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text("Queste agenzie non verranno importate perché mancano dati obbligatori. Puoi forzare l'import con il pulsante sotto.")
                            .font(.caption)
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                Text("Codice")
                                    .frame(width: 100, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                Text("Nome")
                                    .frame(width: 200, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                Text("Telefono")
                                    .frame(width: 150, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                Text("Email")
                                    .frame(width: 200, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                Text("Problemi")
                                    .frame(width: 200, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                            }
                            .font(.headline)
                            
                            Divider()
                            
                            // Data rows
                            ForEach(invalidItems) { item in
                                invalidAgenziaRow(item)
                                Divider()
                            }
                        }
                    }
                    
                    // Forza import button
                    if !invalidItems.isEmpty {
                        HStack {
                            Spacer()
                            Button("Importa comunque le non valide") {
                                // Importa anche le non valide
                                onImport(items.filter { $0.isSelected })
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    private func invalidAgenziaRow(_ item: AgenziaImportItem) -> some View {
        HStack(spacing: 0) {
            Text(item.codice.isEmpty ? "-" : item.codice)
                .frame(width: 100, alignment: .leading)
                .padding(8)
                .foregroundColor(item.codice.isEmpty ? .red : .primary)
            Text(item.nome.isEmpty ? "-" : item.nome)
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .foregroundColor(item.nome.isEmpty ? .red : .primary)
            Text(item.telefoni.first ?? "-")
                .frame(width: 150, alignment: .leading)
                .padding(8)
                .foregroundColor(item.telefoni.isEmpty ? .red : .secondary)
            Text(item.email.first ?? "-")
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .foregroundColor(item.email.isEmpty ? .red : .secondary)
            Text(item.validationErrors.joined(separator: ", "))
                .frame(width: 200, alignment: .leading)
                .padding(8)
                .foregroundColor(.orange)
                .font(.caption)
        }
        .background(Color.orange.opacity(0.05))
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Annulla") {
                onCancel()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            if !isLoading && errorMessage == nil {
                Text("\(validItems.count) agenzie pronte per l'import")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Importa \(validItems.count) agenzie") {
                    onImport(validItems)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(validItems.isEmpty)
            }
        }
        .padding()
    }
    
    // MARK: - Parse Data
    
    private func parseData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let parsed = try await CloudKitRubricaSyncService.shared.parseAgenzieFromData(fileData)
            
            await MainActor.run {
                self.items = parsed
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
