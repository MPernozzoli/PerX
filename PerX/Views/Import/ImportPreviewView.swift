import SwiftUI

struct ImportPreviewView: View {
    let importData: ImportService.ImportData
    let columnMappings: [ImportService.ColumnMapping]
    let stateMappings: [ImportService.StateMapping]
    let onNext: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var previewData: [PreviewRow] = []
    @State private var isCalculating = true
    
    struct PreviewRow: Identifiable {
        let id: String
        let riferimento: String
        let values: [String: String]
        let isNew: Bool
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Anteprima Dati")
                .font(.title3)
            
            Text("Anteprima dei dati che verranno importati. I campi vengono capitalizzati automaticamente (solo prima lettera maiuscola).")
                .foregroundColor(.secondary)
            
            if isCalculating {
                VStack(spacing: 12) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Calcolo anteprima in corso... (\(processedCount) processati)")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if previewData.isEmpty {
                    Text("Nessun dato da mostrare")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let columns = getColumns()
                    
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            // Header
                            HStack(spacing: 0) {
                                Text("Riferimento")
                                    .font(.headline)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                
                                ForEach(columns, id: \.self) { columnName in
                                    Text(columnName)
                                        .font(.headline)
                                        .frame(width: 200, alignment: .leading)
                                        .padding(8)
                                        .background(Color.secondary.opacity(0.1))
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            
                            Divider()
                            
                            // Rows
                            ForEach(previewData) { row in
                                HStack(spacing: 0) {
                                    Text(row.riferimento)
                                        .frame(width: 150, alignment: .leading)
                                        .padding(8)
                                        .foregroundColor(row.isNew ? .blue : .primary)
                                    
                                    ForEach(columns, id: \.self) { columnName in
                                        Text(row.values[columnName] ?? "-")
                                            .frame(width: 200, alignment: .leading)
                                            .padding(8)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                
                                Divider()
                            }
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Avanti") {
                    onNext()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(40)
        .onAppear {
            calculatePreview()
        }
    }
    
    @State private var progress: Double = 0.0
    @State private var processedCount: Int = 0
    
    private func getColumns() -> [String] {
        let fields = columnMappings
            .filter { $0.targetField != .riferimento }
            .map { $0.targetField.displayName }
            .sorted()
        return Array(Set(fields)).sorted()
    }
    
    private func calculatePreview() {
        isCalculating = true
        progress = 0.0
        processedCount = 0
        
        Task {
            do {
                let context = viewContext
                var rows: [PreviewRow] = []
                let totalRows = importData.rows.count
                let batchSize = 50
                
                // Limita l'anteprima ai primi 1000 sinistri per evitare problemi di performance
                let maxPreviewRows = min(totalRows, 1000)
                
                for batchStart in stride(from: 0, to: maxPreviewRows, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, maxPreviewRows)
                    let batch = Array(importData.rows[batchStart..<batchEnd])
                    
                    for row in batch {
                        do {
                            let change = try await ImportService.shared.processRowPreview(
                                row: row,
                                headers: importData.headers,
                                columnMappings: columnMappings,
                                stateMappings: stateMappings,
                                context: context
                            )
                            
                            // Estrai i valori che verranno importati
                            var values: [String: String] = [:]
                            
                            for mapping in columnMappings {
                                guard mapping.targetField != .riferimento,
                                      let columnIndex = importData.headers.firstIndex(of: mapping.sourceColumn),
                                      columnIndex < row.count else {
                                    continue
                                }
                                
                                let rawValue = row[columnIndex].trimmingCharacters(in: .whitespaces)
                                if !rawValue.isEmpty {
                                    // Applica la stessa logica di capitalizzazione usata nell'import
                                    let processedValue = processValueForPreview(rawValue, field: mapping.targetField)
                                    values[mapping.targetField.displayName] = processedValue
                                }
                            }
                            
                            rows.append(PreviewRow(
                                id: change.riferimento,
                                riferimento: change.riferimento,
                                values: values,
                                isNew: change.isNew
                            ))
                            
                            processedCount += 1
                        } catch {
                            // Ignora errori durante l'anteprima
                            print("[ImportPreview] Errore durante l'anteprima: \(error)")
                        }
                    }
                    
                    // Aggiorna il progresso
                    await MainActor.run {
                        progress = Double(processedCount) / Double(maxPreviewRows)
                        previewData = rows
                    }
                    
                    // Yield per permettere aggiornamenti UI
                    await Task.yield()
                }
                
                await MainActor.run {
                    isCalculating = false
                    if totalRows > maxPreviewRows {
                        print("[ImportPreview] Anteprima limitata ai primi \(maxPreviewRows) sinistri su \(totalRows) totali")
                    }
                }
            }
        }
    }
    
    private func processValueForPreview(_ value: String, field: ImportService.DatabaseField) -> String {
        // Applica la stessa logica di capitalizzazione usata nell'import
        if field.isDate {
            return value // Le date non vengono capitalizzate
        } else if field.isAmount {
            return value // Gli importi non vengono capitalizzati
        } else if field == .emailAssicurato || field == .emailContraente || field == .emailDanneggiato || field == .emailAgenzia {
            return value.lowercased()
        } else if field == .numeroSinistroCompagnia {
            return value.uppercased() // Numero sinistro sempre uppercase
        } else if field == .codiceAgenzia {
            return value.uppercased() // Codice agenzia sempre uppercase
        } else if field == .numeroPolizza || field == .telefonoAssicurato || field == .telefonoContraente || field == .telefonoDanneggiato || field == .telefonoAgenzia {
            return value // Numeri polizza e telefoni non vengono modificati
        } else {
            // Capitalizza tutte le iniziali
            guard !value.isEmpty else { return value }
            return value.components(separatedBy: " ")
                .map { word in
                    guard !word.isEmpty else { return word }
                    let first = word.prefix(1).uppercased()
                    let rest = word.dropFirst().lowercased()
                    return first + rest
                }
                .joined(separator: " ")
        }
    }
}

