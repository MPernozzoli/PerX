import SwiftUI
import AppKit

/// Sezione Compagnia e Agenzia con DisclosureGroup espandibile
struct CompanySectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var isExpanded: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var rubricaService = CloudKitRubricaSyncService.shared
    
    @State private var showingRubricaPopover = false
    @State private var matchedAgenzia: RubricaAgenzia?
    @State private var selectedSedeId: String? // ID sede selezionata (nil = madre)
    @State private var showingPopulateAlert = false
    @State private var currentTime = Date()
    
    // Timer per aggiornare lo stato apertura ogni minuto
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    /// Filiali dell'agenzia matchata
    private var filiali: [RubricaAgenzia] {
        guard let agenzia = matchedAgenzia else { return [] }
        return rubricaService.filialiPer(agenziaId: agenzia.id)
    }
    
    /// Agenzia effettiva (madre o filiale selezionata)
    private var agenziaEffettiva: RubricaAgenzia? {
        guard let madre = matchedAgenzia else { return nil }
        
        // Se c'è una selezione specifica, usa quella
        if let sedeId = selectedSedeId {
            if sedeId == madre.id {
                return madre
            }
            return filiali.first { $0.id == sedeId }
        }
        
        // Default: madre
        return madre
    }
    
    /// Stato apertura dell'agenzia (se ha orari in rubrica)
    private var statoApertura: StatoApertura? {
        guard let agenzia = agenziaEffettiva,
              let orari = agenzia.orariApertura else {
            return nil
        }
        return orari.statoAperturaAttuale()
    }
    
    /// Colore per l'indicatore di stato
    private var coloreStatoApertura: Color {
        guard let stato = statoApertura else { return .gray }
        switch stato {
        case .aperta: return .green
        case .chiudePresto: return .yellow
        case .chiusa: return .red
        }
    }
    
    /// Testo descrittivo stato apertura
    private var testoStatoApertura: String {
        guard let stato = statoApertura else { return "" }
        switch stato {
        case .aperta: return "Aperta"
        case .chiudePresto: return "Chiude presto"
        case .chiusa: return "Chiusa"
        }
    }
    
    /// Cerca l'agenzia nella rubrica usando il codice
    private func cercaAgenziaInRubrica() {
        guard let codice = sinistro.codiceAgenzia, !codice.isEmpty else { return }
        
        // Cerca per codice (principale o alternativo)
        if let found = rubricaService.agenzie.first(where: { $0.matches(codice: codice) }) {
            matchedAgenzia = found
        } else {
            // Prova con ricerca parziale
            let results = rubricaService.searchAgenzie(codice, limit: 1)
            matchedAgenzia = results.first
        }
    }
    
    /// Popola i campi dell'agenzia nel sinistro dalla rubrica
    private func popolaDaRubrica(_ agenzia: RubricaAgenzia) {
        // Popola solo i campi vuoti
        if (sinistro.agenzia ?? "").isEmpty {
            sinistro.agenzia = agenzia.nome
        }
        if (sinistro.codiceAgenzia ?? "").isEmpty {
            sinistro.codiceAgenzia = agenzia.codice
        }
        if (sinistro.telefonoAgenzia ?? "").isEmpty, let primo = agenzia.telefoni.first {
            sinistro.telefonoAgenzia = primo
        }
        if (sinistro.emailAgenzia ?? "").isEmpty, let prima = agenzia.email.first {
            sinistro.emailAgenzia = prima
        }
        
        // Salva
        do {
            try viewContext.save()
        } catch {
            print("Errore salvataggio: \(error)")
        }
    }
    
    var body: some View {
        GroupBox {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 16) {
                        // Griglia principale
                        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 16) {
                            // Prima riga - Gruppo e Compagnia
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Gruppo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.gruppo, fieldName: "Gruppo")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Compagnia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.nomeCompagnia, fieldName: "Compagnia")
                                }
                            }
                            
                            // Seconda riga - Area e Divisione
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Area")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.area, fieldName: "Area")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Divisione")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.nomeCompagnia, fieldName: "Divisione")
                                }
                            }
                            
                            // Terza riga - Numero sinistro e Agenzia
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Numero sinistro")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.numeroSinistroCompagnia, fieldName: "Numero sinistro")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Agenzia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        Button {
                                            cercaAgenziaInRubrica()
                                            showingRubricaPopover = true
                                        } label: {
                                            Image(systemName: matchedAgenzia != nil ? "person.crop.circle.fill" : "person.crop.circle")
                                                .foregroundColor(matchedAgenzia != nil ? .green : .blue)
                                        }
                                        .buttonStyle(.plain)
                                        .help(matchedAgenzia != nil ? "Agenzia trovata in rubrica" : "Cerca in rubrica")
                                        .popover(isPresented: $showingRubricaPopover) {
                                            AgenziaRubricaPopover(
                                                sinistro: sinistro,
                                                matchedAgenzia: matchedAgenzia,
                                                onPopola: { agenzia in
                                                    popolaDaRubrica(agenzia)
                                                    showingRubricaPopover = false
                                                },
                                                onClose: { showingRubricaPopover = false }
                                            )
                                        }
                                        
                                        DefaultableText(value: sinistro.agenzia, fieldName: "Nome agenzia")
                                    }
                                }
                            }
                            
                            // Quarta riga - Codice agenzia e Contatti
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Codice agenzia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.codiceAgenzia, fieldName: "Codice agenzia")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Contatti agenzia")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        // Picker sede se ci sono filiali
                                        if !filiali.isEmpty, let madre = matchedAgenzia {
                                            Picker("", selection: Binding(
                                                get: { selectedSedeId ?? madre.id },
                                                set: { newValue in
                                                    selectedSedeId = newValue
                                                    // Salva sul sinistro per sync CK
                                                    let sedeValue: String? = (newValue == madre.id) ? nil : newValue
                                                    sinistro.sedeAgenziaSelezionataId = sedeValue
                                                    try? viewContext.save()
                                                }
                                            )) {
                                                // Opzione madre
                                                Text(madre.suffissoNome ?? "Sede principale")
                                                    .tag(madre.id)
                                                
                                                // Filiali
                                                ForEach(filiali) { filiale in
                                                    Text(filiale.suffissoNome ?? filiale.citta ?? "Filiale")
                                                        .tag(filiale.id)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .font(.caption)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Usa i contatti dell'agenzia selezionata (effettiva)
                                        let telefonoEffettivo = agenziaEffettiva?.telefonoPrincipale ?? sinistro.telefonoAgenzia
                                        let emailEffettiva = agenziaEffettiva?.emailPrincipale ?? sinistro.emailAgenzia
                                        
                                        if let telefono = telefonoEffettivo, !telefono.isEmpty {
                                            HStack(spacing: 6) {
                                                // Indicatore stato apertura
                                                if let _ = statoApertura {
                                                    Circle()
                                                        .fill(coloreStatoApertura)
                                                        .frame(width: 8, height: 8)
                                                        .shadow(color: coloreStatoApertura.opacity(0.6), radius: 3)
                                                        .help(testoStatoApertura)
                                                }
                                                
                                                Button {
                                                    let cleaned = telefono.replacingOccurrences(of: " ", with: "")
                                                    if let url = URL(string: "tel:\(cleaned)") {
                                                        NSWorkspace.shared.open(url)
                                                    }
                                                } label: {
                                                    Text("📞 \(telefono)")
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                        .underline()
                                                }
                                                .buttonStyle(.plain)
                                                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                                                .contextMenu {
                                                    Button {
                                                        let cleaned = telefono.replacingOccurrences(of: " ", with: "")
                                                        if let url = URL(string: "tel:\(cleaned)") {
                                                            NSWorkspace.shared.open(url)
                                                        }
                                                    } label: {
                                                        Label("Chiama", systemImage: "phone.fill")
                                                    }
                                                    Button {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.setString(telefono, forType: .string)
                                                    } label: {
                                                        Label("Copia numero", systemImage: "doc.on.doc")
                                                    }
                                                }
                                                
                                                // Mostra orari se disponibili
                                                if let agenzia = agenziaEffettiva,
                                                   let orari = agenzia.orariApertura {
                                                    Text("(\(orari.descrizioneOggi))")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            // Numeri aggiuntivi dall'agenzia rubrica
                                            if let agenzia = agenziaEffettiva, agenzia.telefoni.count > 1 {
                                                ForEach(Array(agenzia.telefoni.dropFirst().enumerated()), id: \.offset) { _, tel in
                                                    if !tel.isEmpty {
                                                        HStack(spacing: 6) {
                                                            if let _ = statoApertura {
                                                                Color.clear.frame(width: 8, height: 8) // placeholder per allineamento
                                                            }
                                                            Button {
                                                                let cleaned = tel.replacingOccurrences(of: " ", with: "")
                                                                if let url = URL(string: "tel:\(cleaned)") {
                                                                    NSWorkspace.shared.open(url)
                                                                }
                                                            } label: {
                                                                Text("📞 \(tel)")
                                                                    .font(.caption)
                                                                    .foregroundColor(.blue)
                                                                    .underline()
                                                            }
                                                            .buttonStyle(.plain)
                                                            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        if let email = emailEffettiva, !email.isEmpty {
                                            Button {
                                                let numeroSinistro = sinistro.numeroSinistroCompagnia ?? "N/A"
                                                let nome = sinistro.nomeContraente ?? sinistro.nomeAssicurato ?? "Assicurato"
                                                let riferimento = sinistro.riferimento ?? ""
                                                let oggetto = "Sinistro n.\(numeroSinistro) - Assicurato: \(nome) - ns. rif. \(riferimento)"
                                                ComposeEmailWindowManager.shared.openComposeEmail(
                                                    mode: .new(to: email, subject: oggetto)
                                                )
                                            } label: {
                                                Text("✉️ \(email)")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                    .underline()
                                            }
                                            .buttonStyle(.plain)
                                            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                                            .contextMenu {
                                                Button {
                                                    let numeroSinistro = sinistro.numeroSinistroCompagnia ?? "N/A"
                                                    let nome = sinistro.nomeContraente ?? sinistro.nomeAssicurato ?? "Assicurato"
                                                    let riferimento = sinistro.riferimento ?? ""
                                                    let oggetto = "Sinistro n.\(numeroSinistro) - Assicurato: \(nome) - ns. rif. \(riferimento)"
                                                    ComposeEmailWindowManager.shared.openComposeEmail(
                                                        mode: .new(to: email, subject: oggetto)
                                                    )
                                                } label: {
                                                    Label("Scrivi email", systemImage: "envelope")
                                                }
                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(email, forType: .string)
                                                } label: {
                                                    Label("Copia email", systemImage: "doc.on.doc")
                                                }
                                            }
                                        }
                                        if (telefonoEffettivo ?? "").isEmpty && (emailEffettiva ?? "").isEmpty {
                                            Text("Contatti mancanti")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                        
                                        // Mostra indirizzo sede selezionata se diverso
                                        if let agenzia = agenziaEffettiva,
                                           !agenzia.indirizzoCompleto.isEmpty,
                                           agenzia.id != matchedAgenzia?.id {
                                            Text("📍 \(agenzia.indirizzoCompleto)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            // Riga: Flag agenzia (solo se matchata) + pulsante Dettagli agenzia
                            if let agenzia = agenziaEffettiva {
                                GridRow {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Note agenzia")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        let activeFlags = RubricaAgenziaFlag.allCases.filter { $0.isOn(in: agenzia) }
                                        if activeFlags.isEmpty {
                                            Text("Nessuna")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        } else {
                                            FlowLayout(spacing: 6) {
                                                ForEach(activeFlags) { flag in
                                                    Text(flag.rawValue)
                                                        .font(.caption2)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.orange.opacity(0.2))
                                                        .cornerRadius(6)
                                                }
                                            }
                                        }
                                    }
                                    .gridCellColumns(1)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Button {
                                            AgenziaDetailWindowManager.shared.openAgenziaDetail(agenzia: agenzia)
                                        } label: {
                                            Label("Dettagli agenzia", systemImage: "building.2")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .gridCellColumns(1)
                                }
                            }
                        }
                    }
                    .padding(12)
                },
                label: {
                    HStack {
                        Text("Compagnia: \(sinistro.nomeCompagnia ?? sinistro.agenzia?.components(separatedBy: " ").first ?? "Non specificata")")
                            .font(.headline)
                        Spacer()
                        if !isExpanded {
                            let agenziaText = sinistro.agenzia?.isEmpty == false ? sinistro.agenzia! : "Nome agenzia"
                            let codiceText = sinistro.codiceAgenzia?.isEmpty == false ? sinistro.codiceAgenzia! : "Codice"
                            Text("\(agenziaText) - \(codiceText)")
                                .foregroundColor(.secondary)
                                .italic(sinistro.agenzia?.isEmpty != false || sinistro.codiceAgenzia?.isEmpty != false)
                        }
                    }
                }
            )
        }
        .backgroundStyle(.regularMaterial)
        .task {
            cercaAgenziaInRubrica()
            // Ripristina selezione sede da sinistro
            selectedSedeId = sinistro.sedeAgenziaSelezionataId
        }
        .onReceive(timer) { _ in
            // Forza refresh per aggiornare stato apertura
            currentTime = Date()
        }
    }
}

// MARK: - Popover Rubrica Agenzia

struct AgenziaRubricaPopover: View {
    @ObservedObject var sinistro: Sinistro
    let matchedAgenzia: RubricaAgenzia?
    let onPopola: (RubricaAgenzia) -> Void
    let onClose: () -> Void
    
    @StateObject private var rubricaService = CloudKitRubricaSyncService.shared
    @State private var searchText = ""
    
    private var searchResults: [RubricaAgenzia] {
        guard !searchText.isEmpty else { return [] }
        return rubricaService.searchAgenzie(searchText, limit: 10)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Rubrica Agenzie")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Se trovata agenzia corrispondente
            if let agenzia = matchedAgenzia {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Agenzia trovata")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    
                    AgenziaInfoCard(agenzia: agenzia)
                    
                    // Pulsante per popolare i dati mancanti
                    let hasEmptyFields = (sinistro.telefonoAgenzia ?? "").isEmpty || 
                                        (sinistro.emailAgenzia ?? "").isEmpty ||
                                        (sinistro.agenzia ?? "").isEmpty
                    
                    if hasEmptyFields {
                        Button {
                            onPopola(agenzia)
                        } label: {
                            Label("Compila dati mancanti", systemImage: "arrow.down.doc.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } else {
                // Nessuna corrispondenza - mostra ricerca
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Cerca agenzia...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(searchResults) { agenzia in
                                    Button {
                                        onPopola(agenzia)
                                    } label: {
                                        AgenziaInfoCard(agenzia: agenzia)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    } else if searchText.isEmpty {
                        Text("Inserisci il codice o nome agenzia")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Nessun risultato")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct AgenziaInfoCard: View {
    let agenzia: RubricaAgenzia
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(agenzia.nome)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(agenzia.codice)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            if let indirizzo = agenzia.indirizzo, !indirizzo.isEmpty {
                Text(indirizzo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                if let telefono = agenzia.telefoni.first {
                    Label(telefono, systemImage: "phone")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                if let email = agenzia.email.first {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
