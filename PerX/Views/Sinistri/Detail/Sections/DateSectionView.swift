import SwiftUI

/// Sezione Date con chevron per espandere e editing inline
struct DateSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var isEditing = false
    @State private var showAllDates = false
    
    // Preferenza formato date
    private enum DateDisplayFormat: String {
        case letters
        case numeric
    }
    
    @AppStorage("dateDisplayFormat") private var dateDisplayFormatRawValue: String = DateDisplayFormat.letters.rawValue
    
    private var currentDateDisplayFormat: DateDisplayFormat {
        DateDisplayFormat(rawValue: dateDisplayFormatRawValue) ?? .letters
    }
    
    // Snapshot per annullare modifiche
    @State private var snapshotDates: [String: Date?] = [:]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Date")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Chevron per espandere/collassare
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllDates.toggle()
                        }
                    } label: {
                        Image(systemName: showAllDates ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(showAllDates ? "Nascondi date secondarie" : "Mostra tutte le date")
                    
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
                        .help("Modifica date")
                    }
                }
                
                VStack(spacing: 16) {
                    // Assegnatario (mostra SOLO se diverso dall'utente loggato)
                    if let current = GoogleAuthService.shared.userEmail?.lowercased(),
                       let assigned = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased(),
                       !assigned.isEmpty,
                       assigned != current {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.orange)
                                Text("Assegnato a:")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(sinistro.assignedToUserName ?? sinistro.assignedToUserEmail ?? assigned)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        Divider()
                    }
                    
                    // DATE PRINCIPALI (sempre visibili)
                    
                    // Data Sinistro
                    EditableDateRow(
                        icon: "calendar.badge.exclamationmark",
                        iconColor: .red,
                        label: "Data Sinistro:",
                        date: Binding(
                            get: { sinistro.dataSinistro },
                            set: { sinistro.setDataSinistro($0) }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { sinistro.setDataSinistro(nil) }
                    )
                    
                    // Data denuncia
                    EditableDateRow(
                        icon: "exclamationmark.triangle",
                        iconColor: .orange,
                        label: "Data denuncia:",
                        date: Binding(
                            get: { sinistro.dataDenuncia },
                            set: { sinistro.setDataDenuncia($0) }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { sinistro.setDataDenuncia(nil) }
                    )
                    
                    // Data incarico
                    EditableDateRow(
                        icon: "hand.raised",
                        iconColor: .blue,
                        label: "Data incarico:",
                        date: Binding(
                            get: { sinistro.dataIncarico },
                            set: { newValue in
                                sinistro.dataIncarico = newValue
                                // Valida data assegnazione dopo modifica data incarico
                                sinistro.validateAllDates()
                            }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { 
                            sinistro.dataIncarico = nil
                            sinistro.validateAllDates()
                        }
                    )
                    
                    // Data sopralluogo (solo per sinistri tradizionali)
                    if sinistro.sopralluogo || isEditing {
                        EditableDateRow(
                            icon: "mappin.circle",
                            iconColor: .purple,
                            label: "Data sopralluogo:",
                            date: $sinistro.dataSopralluogo,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataSopralluogo = nil }
                        )
                    }
                    
                    // Data assegnazione
                    EditableDateRow(
                        icon: "calendar.badge.plus",
                        iconColor: .cyan,
                        label: "Assegnazione:",
                        date: Binding(
                            get: { sinistro.dataAssegnazione },
                            set: { sinistro.setDataAssegnazione($0) }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { sinistro.setDataAssegnazione(nil) }
                    )
                    
                    // Data invio atto
                    EditableDateRow(
                        icon: "paperplane.circle",
                        iconColor: .indigo,
                        label: "Invio Atto:",
                        date: Binding(
                            get: { sinistro.dataInvioAtto },
                            set: { newValue in
                                sinistro.dataInvioAtto = newValue
                                // Valida data assegnazione dopo modifica data invio atto
                                sinistro.validateAllDates()
                            }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { 
                            sinistro.dataInvioAtto = nil
                            sinistro.validateAllDates()
                        }
                    )
                    
                    // Data chiusura
                    EditableDateRow(
                        icon: "checkmark.circle",
                        iconColor: .green,
                        label: "Chiusura:",
                        date: Binding(
                            get: { sinistro.dataChiusura },
                            set: { newValue in
                                sinistro.dataChiusura = newValue
                                // Valida data assegnazione dopo modifica data chiusura
                                sinistro.validateAllDates()
                            }
                        ),
                        isEditing: isEditing,
                        formatDate: formatDate,
                        onDelete: { 
                            sinistro.dataChiusura = nil
                            sinistro.validateAllDates()
                        }
                    )
                    
                    // DATE SECONDARIE (visibili solo quando espanso)
                    if showAllDates {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Date aggiuntive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Data apertura gestione
                        EditableDateRow(
                            icon: "folder.badge.plus",
                            iconColor: .teal,
                            label: "Apertura gestione:",
                            date: $sinistro.dataAperturaGestione,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataAperturaGestione = nil }
                        )
                        
                        // Data ritorno atto
                        EditableDateRow(
                            icon: "arrow.uturn.backward.circle",
                            iconColor: .brown,
                            label: "Ritorno atto:",
                            date: $sinistro.dataRitornoAtto,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataRitornoAtto = nil }
                        )
                        
                        // Data comunicazione esito
                        EditableDateRow(
                            icon: "megaphone",
                            iconColor: .pink,
                            label: "Comunicazione esito:",
                            date: $sinistro.dataComunicazioneEsito,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataComunicazioneEsito = nil }
                        )
                        
                        // Data ricezione atto sottoscritto
                        EditableDateRow(
                            icon: "signature",
                            iconColor: .mint,
                            label: "Ricezione atto firmato:",
                            date: $sinistro.dataRicezioneAttoSottoscritto,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataRicezioneAttoSottoscritto = nil }
                        )
                        
                        // Data accettazione verbale
                        EditableDateRow(
                            icon: "checkmark.seal",
                            iconColor: .indigo,
                            label: "Accettazione verbale:",
                            date: $sinistro.dataAccettazioneVerbale,
                            isEditing: isEditing,
                            formatDate: formatDate,
                            onDelete: { sinistro.dataAccettazioneVerbale = nil }
                        )
                        
                        // Data revoca
                        if sinistro.dataRevoca != nil || isEditing {
                            EditableDateRow(
                                icon: "xmark.circle",
                                iconColor: .red,
                                label: "Revoca:",
                                date: $sinistro.dataRevoca,
                                isEditing: isEditing,
                                formatDate: formatDate,
                                onDelete: { sinistro.dataRevoca = nil }
                            )
                        }
                        
                        // Data pagamento premio (se Generali e valorizzata)
                        if GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo) == .generali {
                            if sinistro.dataPagamentoPremio != nil || isEditing {
                                EditableDateRow(
                                    icon: "banknote",
                                    iconColor: .green,
                                    label: "Pagamento premio:",
                                    date: $sinistro.dataPagamentoPremio,
                                    isEditing: isEditing,
                                    formatDate: formatDate,
                                    onDelete: { sinistro.dataPagamentoPremio = nil }
                                )
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .contextMenu {
            dateFormatContextMenu
        }
    }
    
    // MARK: - Date Formatting
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        
        switch currentDateDisplayFormat {
        case .letters:
            formatter.dateStyle = .long
        case .numeric:
            formatter.dateFormat = "dd/MM/yyyy"
        }
        return formatter.string(from: date)
    }
    
    private var dateFormatContextMenu: some View {
        Group {
            Button {
                dateDisplayFormatRawValue = DateDisplayFormat.letters.rawValue
            } label: {
                Text(currentDateDisplayFormat == .letters ? "✓ Formato: mese in lettere" : "Formato: mese in lettere")
            }
            
            Button {
                dateDisplayFormatRawValue = DateDisplayFormat.numeric.rawValue
            } label: {
                Text(currentDateDisplayFormat == .numeric ? "✓ Formato: numerico" : "Formato: numerico")
            }
        }
    }
    
    // MARK: - Snapshot Management
    
    private func takeSnapshot() {
        snapshotDates = [
            "dataSinistro": sinistro.dataSinistro,
            "dataDenuncia": sinistro.dataDenuncia,
            "dataIncarico": sinistro.dataIncarico,
            "dataSopralluogo": sinistro.dataSopralluogo,
            "dataAssegnazione": sinistro.dataAssegnazione,
            "dataInvioAtto": sinistro.dataInvioAtto,
            "dataChiusura": sinistro.dataChiusura,
            "dataAperturaGestione": sinistro.dataAperturaGestione,
            "dataRitornoAtto": sinistro.dataRitornoAtto,
            "dataComunicazioneEsito": sinistro.dataComunicazioneEsito,
            "dataRicezioneAttoSottoscritto": sinistro.dataRicezioneAttoSottoscritto,
            "dataAccettazioneVerbale": sinistro.dataAccettazioneVerbale,
            "dataRevoca": sinistro.dataRevoca,
            "dataPagamentoPremio": sinistro.dataPagamentoPremio
        ]
    }
    
    private func restoreSnapshot() {
        sinistro.setDataSinistro(snapshotDates["dataSinistro"] ?? nil)
        sinistro.setDataDenuncia(snapshotDates["dataDenuncia"] ?? nil)
        sinistro.dataIncarico = snapshotDates["dataIncarico"] ?? nil
        sinistro.dataSopralluogo = snapshotDates["dataSopralluogo"] ?? nil
        sinistro.setDataAssegnazione(snapshotDates["dataAssegnazione"] ?? nil)
        sinistro.dataInvioAtto = snapshotDates["dataInvioAtto"] ?? nil
        sinistro.dataChiusura = snapshotDates["dataChiusura"] ?? nil
        sinistro.dataAperturaGestione = snapshotDates["dataAperturaGestione"] ?? nil
        sinistro.dataRitornoAtto = snapshotDates["dataRitornoAtto"] ?? nil
        sinistro.dataComunicazioneEsito = snapshotDates["dataComunicazioneEsito"] ?? nil
        sinistro.dataRicezioneAttoSottoscritto = snapshotDates["dataRicezioneAttoSottoscritto"] ?? nil
        sinistro.dataAccettazioneVerbale = snapshotDates["dataAccettazioneVerbale"] ?? nil
        sinistro.dataRevoca = snapshotDates["dataRevoca"] ?? nil
        sinistro.dataPagamentoPremio = snapshotDates["dataPagamentoPremio"] ?? nil
        sinistro.validateAllDates()
    }
    
    private func saveChanges() {
        sinistro.cloudKitLastModified = Date()
        try? viewContext.save()
    }
}
