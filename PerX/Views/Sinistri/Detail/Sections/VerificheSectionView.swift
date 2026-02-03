import SwiftUI

/// Sezione Verifiche con giustificativi basati su file-tag
struct VerificheSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var fileTagManager = FileTagManager.shared
    
    @State private var isEditing = false
    
    // Snapshot per annullare modifiche
    @State private var snapshotFulminazione: String = ""
    @State private var snapshotSopralluogo: Bool = false
    @State private var snapshotIban: Bool = false
    @State private var snapshotRegolaritaOverride: Bool = false
    
    // Stato giustificativi da file-tag
    @State private var hasFattura: Bool = false
    @State private var hasPreventivo: Bool = false
    @State private var sinistroPathExists: Bool = false
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Verifiche")
                        .font(.headline)
                    Spacer()
                    
                    if isEditing {
                        HStack(spacing: 8) {
                            Button("Annulla") {
                                restoreSnapshot()
                                isEditing = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            
                            Button("Salva") {
                                saveChanges()
                                isEditing = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    } else {
                        Button {
                            takeSnapshot()
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Modifica verifiche")
                    }
                }
                
                VStack(spacing: 16) {
                    // Fulminazione
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("Fulminazione:")
                            .foregroundColor(.secondary)
                        Spacer()
                        if isEditing {
                            Picker("", selection: Binding(
                                get: { sinistro.fulminazione ?? "Non effettuata" },
                                set: { sinistro.fulminazione = $0 }
                            )) {
                                Text("Non effettuata").tag("Non effettuata")
                                Text("Positiva").tag("Positiva")
                                Text("Negativa").tag("Negativa")
                                Text("CESI - Negativo").tag("CESI - Negativo")
                                Text("CESI - Positivo entro 1KM").tag("CESI - Positivo entro 1KM")
                                Text("CESI - Positivo entro 3KM").tag("CESI - Positivo entro 3KM")
                                Text("CESI - Positivo entro 5KM").tag("CESI - Positivo entro 5KM")
                                Text("CESI - Positivo entro 10KM").tag("CESI - Positivo entro 10KM")
                            }
                            .frame(maxWidth: 250)
                        } else {
                            Text(sinistro.fulminazione ?? "Non effettuata")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Divider()
                    
                    // Perizia di tipo
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.blue)
                        Text("Perizia di tipo:")
                            .foregroundColor(.secondary)
                        Spacer()
                        if isEditing {
                            Picker("", selection: $sinistro.sopralluogo) {
                                Text("Documentale").tag(false)
                                Text("Tradizionale").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        } else {
                            if sinistroPathExists {
                                Text(sinistro.sopralluogo ? "Tradizionale" : "Documentale")
                                    .foregroundColor(.primary)
                            } else {
                                Text("Non nota")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Giustificativi (basati su file-tag)
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.orange)
                        Text("Giustificativi:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(giustificativiText)
                            .foregroundColor(giustificativiColor)
                    }
                    
                    Divider()
                    
                    // IBAN
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(.green)
                        Text("IBAN:")
                            .foregroundColor(.secondary)
                        Spacer()
                        if isEditing {
                            Toggle("", isOn: $sinistro.iban)
                                .labelsHidden()
                        } else {
                            Text(sinistro.iban ? "Presente" : "Non presente")
                                .foregroundColor(sinistro.iban ? .green : .secondary)
                        }
                    }
                    
                    // Regolarità Amministrativa (solo per Gruppo Generali)
                    if GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo) == .generali {
                        Divider()
                        
                        HStack {
                            Image(systemName: sinistro.hasIrregolaritaAmministrativa ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                .foregroundColor(regolaritaAmministrativaColor)
                            Text("Regolarità amministrativa:")
                                .foregroundColor(.secondary)
                            Spacer()
                            if isEditing {
                                Toggle("Override", isOn: $sinistro.regolaritaAmministrativaOverride)
                                    .help("Disattiva alert irregolarità")
                            } else {
                                Text(regolaritaAmministrativaText)
                                    .foregroundColor(regolaritaAmministrativaColor)
                                    .fontWeight(sinistro.hasIrregolaritaAmministrativa ? .semibold : .regular)
                            }
                        }
                        
                        // Data Pagamento Premio
                        if sinistro.isRegolaritaAmministrativa == true, let dataPagamento = sinistro.dataPagamentoPremio {
                            Divider()
                            
                            HStack {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundColor(.blue)
                                Text("Data pag. premio:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(dataPagamento))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .onAppear {
            checkSinistroPath()
            loadGiustificativiFromTags()
        }
        .onChange(of: fileTagManager.fileTags) { _ in
            loadGiustificativiFromTags()
        }
        .onChange(of: sinistro.riferimento) { _ in
            checkSinistroPath()
            loadGiustificativiFromTags()
        }
    }
    
    // MARK: - Path Check
    
    private func checkSinistroPath() {
        guard let riferimento = sinistro.riferimento else {
            sinistroPathExists = false
            return
        }
        
        // Esegui il controllo del path in modo sicuro
        sinistroPathExists = FileService.shared.getSinistroPath(riferimento: riferimento, create: false) != nil
    }
    
    // MARK: - Giustificativi from File Tags
    
    private var giustificativiText: String {
        if hasFattura && hasPreventivo {
            return "presenti"
        } else if hasFattura {
            return "fatture"
        } else if hasPreventivo {
            return "preventivi"
        } else {
            if sinistroPathExists {
                return sinistro.statoGiustificativi.rawValue
            }
            return "Non noti"
        }
    }
    
    private var giustificativiColor: Color {
        if hasFattura || hasPreventivo {
            return .primary
        }
        return sinistro.statoGiustificativi == .assenti ? .red : .secondary
    }
    
    private func loadGiustificativiFromTags() {
        guard let riferimento = sinistro.riferimento,
              let _ = FileService.shared.getSinistroPath(riferimento: riferimento, create: false) else {
            hasFattura = false
            hasPreventivo = false
            return
        }
        
        Task { @MainActor in
            let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
            let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
            
            var foundFattura = false
            var foundPreventivo = false
            
            if let tag = fatturaTag {
                let filesWithTag = fileTagManager.getFilesWithTag(tag)
                foundFattura = filesWithTag.contains { $0.contains(riferimento) }
            }
            
            if let tag = preventivoTag {
                let filesWithTag = fileTagManager.getFilesWithTag(tag)
                foundPreventivo = filesWithTag.contains { $0.contains(riferimento) }
            }
            
            hasFattura = foundFattura
            hasPreventivo = foundPreventivo
        }
    }
    
    // MARK: - Regolarità Helpers
    
    private var regolaritaAmministrativaText: String {
        guard let regolarita = sinistro.isRegolaritaAmministrativa else {
            return "Non rilevata"
        }
        return regolarita ? "Regolare" : "Irregolare"
    }
    
    private var regolaritaAmministrativaColor: Color {
        guard let regolarita = sinistro.isRegolaritaAmministrativa else {
            return .secondary
        }
        return regolarita ? .green : .red
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatLong(date)
    }
    
    // MARK: - Snapshot Management
    
    private func takeSnapshot() {
        snapshotFulminazione = sinistro.fulminazione ?? "Non effettuata"
        snapshotSopralluogo = sinistro.sopralluogo
        snapshotIban = sinistro.iban
        snapshotRegolaritaOverride = sinistro.regolaritaAmministrativaOverride
    }
    
    private func restoreSnapshot() {
        sinistro.fulminazione = snapshotFulminazione
        sinistro.sopralluogo = snapshotSopralluogo
        sinistro.iban = snapshotIban
        sinistro.regolaritaAmministrativaOverride = snapshotRegolaritaOverride
    }
    
    private func saveChanges() {
        sinistro.cloudKitLastModified = Date()
        try? viewContext.save()
    }
}
