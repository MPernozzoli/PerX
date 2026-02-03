import SwiftUI
import Combine

/// Sezione Importi con editing inline
struct ImportiSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var isEditing = false
    @State private var showDefinizioneSheet = false
    @State private var tempDefinizione: String = ""
    
    // Snapshot per annullare modifiche
    @State private var snapshotRichiesta: Double = 0
    @State private var snapshotLiquidato: Double = 0
    @State private var snapshotDannoAccertato: Double = 0
    @State private var snapshotOltreDieciBeni: Bool = false
    @State private var snapshotDefinizione: String = ""
    @State private var snapshotDefinizioneManuale: Bool = false
    
    // Valori temporanei per editing
    @State private var tempRichiesta: String = ""
    @State private var tempLiquidato: String = ""
    @State private var tempDannoAccertato: String = ""
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Importi")
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
                        .help("Modifica importi")
                    }
                }
                
                VStack(spacing: 16) {
                    // Richiesta
                    importoRow(
                        icon: "eurosign.circle",
                        iconColor: .blue,
                        label: "Richiesta:",
                        value: richiestaTotale(),
                        editValue: $tempRichiesta,
                        isEditing: isEditing
                    )
                    
                    Divider()
                    
                    // Danno Accertato
                    let (dannoAccertatoLordo, stimaDanno, importoLiquidato) = calcolaImportiDaPerizia()
                    let isChiuso = sinistro.stato == StatoManager.StatoSinistro.chiusa.descrizione
                    let isInAtto = sinistro.stato == StatoManager.StatoSinistro.attoInviato.descrizione ||
                                   sinistro.stato == StatoManager.StatoSinistro.esitoComunicato.descrizione ||
                                   sinistro.stato == StatoManager.StatoSinistro.attoRicevutoSottoscritto.descrizione
                    let haLiquidazione = sinistro.haLiquidazione
                    
                    if let dannoAccertato = dannoAccertatoLordo, dannoAccertato > 0 {
                        importoRowWithSource(
                            icon: "eurosign.square.fill",
                            iconColor: .orange,
                            label: "Danno Accertato:",
                            value: dannoAccertato,
                            source: "da Perizia (lordo)"
                        )
                        Divider()
                    } else if let dannoAccertato = sinistro.dannoAccertato?.doubleValue, dannoAccertato > 0 {
                        importoRow(
                            icon: "eurosign.square.fill",
                            iconColor: .orange,
                            label: "Danno Accertato:",
                            value: dannoAccertato,
                            editValue: $tempDannoAccertato,
                            isEditing: isEditing
                        )
                        Divider()
                    }
                    
                    // Stima/Liquidato/Riserva in base allo stato
                    if isChiuso {
                        if haLiquidazione {
                            if let liquidato = importoLiquidato, liquidato > 0 {
                                importoRowWithSource(
                                    icon: "eurosign.circle.fill",
                                    iconColor: .green,
                                    label: "Importo Liquidato:",
                                    value: liquidato,
                                    source: "da Perizia"
                                )
                            } else {
                                importoRow(
                                    icon: "eurosign.circle.fill",
                                    iconColor: .green,
                                    label: "Importo Liquidato:",
                                    value: sinistro.liquidato?.doubleValue ?? 0,
                                    editValue: $tempLiquidato,
                                    isEditing: isEditing
                                )
                            }
                        } else {
                            if let dannoAccertato = dannoAccertatoLordo ?? sinistro.dannoAccertato?.doubleValue, dannoAccertato > 0 {
                                importoRow(
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: .red,
                                    label: "Riserva:",
                                    value: dannoAccertato,
                                    editValue: .constant(""),
                                    isEditing: false
                                )
                            }
                        }
                    } else if isInAtto {
                        if let stima = stimaDanno, stima > 0 {
                            importoRowWithSource(
                                icon: "eurosign.square.fill",
                                iconColor: .orange,
                                label: "Stima del danno:",
                                value: stima,
                                source: "da Perizia"
                            )
                        } else {
                            importoRow(
                                icon: "eurosign.square.fill",
                                iconColor: .orange,
                                label: "Stima del danno:",
                                value: sinistro.stimaDanno?.doubleValue ?? 0,
                                editValue: .constant(""),
                                isEditing: false
                            )
                        }
                    } else {
                        if let stima = stimaDanno, stima > 0 {
                            importoRowWithSource(
                                icon: "eurosign.square.fill",
                                iconColor: .orange,
                                label: "Stima del danno:",
                                value: stima,
                                source: "da Perizia"
                            )
                        } else {
                            importoRow(
                                icon: "eurosign.square.fill",
                                iconColor: .orange,
                                label: "Stima del danno:",
                                value: sinistro.stimaDanno?.doubleValue ?? 0,
                                editValue: .constant(""),
                                isEditing: false
                            )
                        }
                    }
                    
                    // Definizione
                    Divider()
                    
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                        Text("Definizione:")
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if isEditing {
                            Picker("", selection: $tempDefinizione) {
                                Text("Seleziona...").tag("")
                                ForEach(RelazionePeritaleService.opzioniDeterminazione, id: \.self) { opzione in
                                    Text(opzione).tag(opzione)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 300)
                        } else {
                            if let definizione = sinistro.definizione, !definizione.isEmpty {
                                HStack(spacing: 4) {
                                    Text(definizione)
                                        .font(.system(.body, design: .rounded))
                                    if sinistro.definizioneManuale {
                                        Image(systemName: "hand.raised.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .help("Definizione impostata manualmente")
                                    }
                                }
                            } else {
                                Text("Non specificata")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                    }
                    
                    // Oltre 10 beni (solo in editing)
                    if isEditing {
                        Divider()
                        Toggle("Più di 10 beni", isOn: $sinistro.oltreDieciBeni)
                    }
                }
            }
            .padding(12)
        }
        .onReceive(sinistro.publisher(for: \.definizione)) { newValue in
            if !isEditing {
                tempDefinizione = newValue ?? ""
            }
        }
        .onReceive(sinistro.perizia.map { $0.publisher(for: \.determinazione).eraseToAnyPublisher() } ?? Empty<String?, Never>().eraseToAnyPublisher()) { newValue in
            if !isEditing {
                // Se cambia la determinazione sulla perizia, aggiorna il sinistro
                if sinistro.definizione != newValue {
                    sinistro.definizione = newValue
                    tempDefinizione = newValue ?? ""
                }
            }
        }
        .backgroundStyle(.regularMaterial)
        .sheet(isPresented: $showDefinizioneSheet) {
            DefinizioneOverrideView(sinistro: sinistro)
        }
    }
    
    // MARK: - Importo Rows
    
    private func importoRow(icon: String, iconColor: Color, label: String, value: Double, editValue: Binding<String>, isEditing: Bool) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(label)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isEditing && editValue.wrappedValue != "" || isEditing {
                TextField("0,00", text: editValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(CurrencyFormatter.shared.formatWithSymbol(value))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(value > 0 ? .primary : .secondary)
            }
        }
    }
    
    private func importoRowWithSource(icon: String, iconColor: Color, label: String, value: Double, source: String) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(label)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.shared.formatWithSymbol(value))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(value > 0 ? .primary : .secondary)
                Text(source)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    // MARK: - Calcoli
    
    private func richiestaTotale() -> Double {
        let salvata = sinistro.richiesta?.doubleValue ?? 0
        if salvata > 0 { return salvata }
        
        guard let perizia = sinistro.perizia else { return 0 }
        let totale = CalcoliService.shared.calcolaRichiestaTotale(perizia: perizia)
        
        if totale > 0, salvata <= 0 {
            sinistro.richiesta = NSDecimalNumber(value: totale)
            try? viewContext.save()
        }
        
        return totale
    }
    
    private func calcolaImportiDaPerizia() -> (dannoAccertatoLordo: Double?, stimaDanno: Double?, importoLiquidato: Double?) {
        guard let perizia = sinistro.perizia else {
            return (nil, nil, nil)
        }
        
        let dannoAccertatoLordo = CalcoliService.shared.calcolaDannoAccertatoLordo(perizia: perizia)
        let stimaLiquidato = perizia.stimaDannoIndennizzabile?.doubleValue ?? 0
        
        return (dannoAccertatoLordo > 0 ? dannoAccertatoLordo : nil,
                stimaLiquidato > 0 ? stimaLiquidato : nil,
                stimaLiquidato > 0 ? stimaLiquidato : nil)
    }
    
    // MARK: - Snapshot Management
    
    private func takeSnapshot() {
        snapshotRichiesta = sinistro.richiesta?.doubleValue ?? 0
        snapshotLiquidato = sinistro.liquidato?.doubleValue ?? 0
        snapshotDannoAccertato = sinistro.dannoAccertato?.doubleValue ?? 0
        snapshotOltreDieciBeni = sinistro.oltreDieciBeni
        snapshotDefinizione = sinistro.definizione ?? ""
        snapshotDefinizioneManuale = sinistro.definizioneManuale
        
        tempRichiesta = snapshotRichiesta > 0 ? String(format: "%.2f", snapshotRichiesta).replacingOccurrences(of: ".", with: ",") : ""
        tempLiquidato = snapshotLiquidato > 0 ? String(format: "%.2f", snapshotLiquidato).replacingOccurrences(of: ".", with: ",") : ""
        tempDannoAccertato = snapshotDannoAccertato > 0 ? String(format: "%.2f", snapshotDannoAccertato).replacingOccurrences(of: ".", with: ",") : ""
        tempDefinizione = snapshotDefinizione
    }
    
    private func restoreSnapshot() {
        sinistro.richiesta = snapshotRichiesta > 0 ? NSDecimalNumber(value: snapshotRichiesta) : nil
        sinistro.liquidato = snapshotLiquidato > 0 ? NSDecimalNumber(value: snapshotLiquidato) : nil
        sinistro.dannoAccertato = snapshotDannoAccertato > 0 ? NSDecimalNumber(value: snapshotDannoAccertato) : nil
        sinistro.oltreDieciBeni = snapshotOltreDieciBeni
        sinistro.definizione = snapshotDefinizione.isEmpty ? nil : snapshotDefinizione
        sinistro.definizioneManuale = snapshotDefinizioneManuale
    }
    
    private func saveChanges() {
        if let value = Double(tempRichiesta.replacingOccurrences(of: ",", with: ".")) {
            sinistro.richiesta = NSDecimalNumber(value: value)
        }
        if let value = Double(tempLiquidato.replacingOccurrences(of: ",", with: ".")) {
            sinistro.liquidato = NSDecimalNumber(value: value)
        }
        if let value = Double(tempDannoAccertato.replacingOccurrences(of: ",", with: ".")) {
            sinistro.dannoAccertato = NSDecimalNumber(value: value)
        }
        
        // Se la definizione è stata cambiata manualmente, aggiorna il sinistro e la perizia
        if tempDefinizione != snapshotDefinizione {
            sinistro.definizione = tempDefinizione.isEmpty ? nil : tempDefinizione
            sinistro.definizioneManuale = true
            
            // Sincronizza con la perizia
            if let perizia = sinistro.perizia {
                perizia.determinazione = tempDefinizione.isEmpty ? nil : tempDefinizione
            }
        }
        
        // Il valore di oltreDieciBeni è già legato al toggle via binding
        
        sinistro.cloudKitLastModified = Date()
        try? viewContext.save()
    }
}

// MARK: - Definizione Override View (mantenuta per compatibilità)

struct DefinizioneOverrideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    @State private var definizione: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Modifica Definizione")
                .font(.headline)
            
            Text("Attenzione: inserendo manualmente la definizione, la funzione di aggiornamento automatico verrà disattivata per questo sinistro.")
                .foregroundColor(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Definizione:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $definizione)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding()
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Salva") {
                    sinistro.definizione = definizione.isEmpty ? nil : definizione
                    sinistro.definizioneManuale = true
                    sinistro.cloudKitLastModified = Date()
                    try? viewContext.save()
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 500)
        .onAppear {
            definizione = sinistro.definizione ?? ""
        }
    }
}
