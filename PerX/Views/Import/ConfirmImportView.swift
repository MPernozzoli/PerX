import SwiftUI

struct ConfirmImportView: View {
    let importData: ImportService.ImportData?
    let columnMappings: [ImportService.ColumnMapping]
    let stateMappings: [ImportService.StateMapping]
    let onConfirm: (Bool) -> Void
    
    @State private var isProcessing = false
    @State private var revokeMissing = false
    @Binding var progress: Double
    @Binding var processedCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Conferma Import")
                .font(.title3)
            
            Text("Stai per importare \(importData?.rows.count ?? 0) righe dal file \(importData?.fileName ?? ""). Verifica i mapping prima di procedere.")
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 40) {
                // Riepilogo mapping colonne
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mapping Colonne")
                        .font(.headline)
                    
                    ScrollView {
                        ForEach(columnMappings, id: \.sourceColumn) { mapping in
                            HStack {
                                Text(mapping.sourceColumn)
                                    .frame(width: 150, alignment: .leading)
                                Image(systemName: "arrow.right")
                                Text(mapping.targetField.displayName)
                            }
                            .font(.caption)
                        }
                    }
                }
                
                // Riepilogo mapping stati
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mapping Stati")
                        .font(.headline)
                    
                    ScrollView {
                        ForEach(stateMappings, id: \.sourceState) { mapping in
                            HStack {
                                Text(mapping.sourceState)
                                    .frame(width: 150, alignment: .leading)
                                Image(systemName: "arrow.right")
                                Text(mapping.targetState)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            Toggle(isOn: $revokeMissing) {
                Text("Revoca sinistri mancanti nel file")
            }
            .padding(.top)
            
            HStack {
                Spacer()
                
                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Importazione in corso... (\(processedCount) processati)")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Button("Avvia Import") {
                        isProcessing = true
                        onConfirm(revokeMissing)
                    }
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(40)
    }
} 