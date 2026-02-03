import SwiftUI

struct ImportResultView: View {
    let result: ImportService.ImportResult
    
    var body: some View {
        VStack(spacing: 24) {
            if result.hasErrors {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Import completato con errori")
                    .font(.title3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Import completato con successo")
                    .font(.title3)
            }
            
            Text(result.summary)
                .foregroundColor(.secondary)
            
            if !result.sinistroChanges.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(result.sinistroChanges.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(change.riferimento)
                                        .font(.headline)
                                    if change.isNew {
                                        Text("NUOVO")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                }
                                
                                if !change.changes.isEmpty {
                                    ForEach(Array(change.changes.enumerated()), id: \.offset) { _, fieldChange in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(fieldChange.isAdded ? Color.green : Color.yellow)
                                                .frame(width: 8, height: 8)
                                                .padding(.top, 6)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(fieldChange.field.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                
                                                if fieldChange.isAdded {
                                                    Text("Aggiunto: \(fieldChange.newValue)")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                } else {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Da: \(fieldChange.oldValue ?? "vuoto")")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        Text("A: \(fieldChange.newValue)")
                                                            .font(.caption)
                                                            .foregroundColor(.yellow)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            if result.hasErrors {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dettaglio errori:")
                        .font(.headline)
                    
                    ScrollView {
                        ForEach(result.errors, id: \.self) { error in
                            HStack(alignment: .top) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                Spacer()
                            }
                            .padding(4)
                        }
                    }
                    .frame(height: 200)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(40)
    }
} 