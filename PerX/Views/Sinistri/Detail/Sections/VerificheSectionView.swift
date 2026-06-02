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

    // Cambio tipo perizia (videoperizia / sopralluogo)
    @State private var pendingTipoAction: TipoPeriziaAction?
    @State private var keepAssignmentOnTipoChange: Bool = false
    
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
                                tipoPeriziaControl
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
            backfillTipoPeriziaIfNeeded()
        }
        .onChange(of: fileTagManager.fileTags) { _ in
            loadGiustificativiFromTags()
        }
        .onChange(of: sinistro.riferimento) { _ in
            checkSinistroPath()
            loadGiustificativiFromTags()
        }
        .sheet(item: $pendingTipoAction) { action in
            CambioTipoPeriziaDialog(
                action: action,
                tipoCorrente: tipoPeriziaCorrente,
                keepAssignment: $keepAssignmentOnTipoChange,
                onConfirm: {
                    let captured = action
                    let keep = keepAssignmentOnTipoChange
                    pendingTipoAction = nil
                    Task { await applyTipoPeriziaAction(captured, keepAssignment: keep) }
                },
                onCancel: { pendingTipoAction = nil }
            )
        }
    }

    // MARK: - Tipo Perizia (Documentale / Tradizionale / Videoperizia)

    fileprivate enum TipoPerizia: String {
        case documentale = "Documentale"
        case tradizionale = "Tradizionale"
        case videoperizia = "Videoperizia"

        var storageValue: String {
            switch self {
            case .documentale: return "documentale"
            case .tradizionale: return "tradizionale"
            case .videoperizia: return "videoperizia"
            }
        }

        static func fromStorage(_ raw: String?) -> TipoPerizia? {
            switch raw?.lowercased() {
            case "documentale": return .documentale
            case "tradizionale": return .tradizionale
            case "videoperizia": return .videoperizia
            default: return nil
            }
        }
    }

    fileprivate enum TipoPeriziaAction: String, Identifiable {
        case richiediVideoperizia
        case richiediSopralluogo

        var id: String { rawValue }

        var titolo: String {
            switch self {
            case .richiediVideoperizia: return "Richiedi videoperizia"
            case .richiediSopralluogo: return "Richiedi sopralluogo"
            }
        }

        var icon: String {
            switch self {
            case .richiediVideoperizia: return "video.badge.plus"
            case .richiediSopralluogo: return "calendar.badge.clock"
            }
        }

        var nuovoStato: StatoManager.StatoSinistro {
            switch self {
            case .richiediVideoperizia: return .videoperiziaDaFissare
            case .richiediSopralluogo: return .sopralluogoDaFissare
            }
        }

        var nuovoSopralluogoFlag: Bool {
            switch self {
            case .richiediVideoperizia: return false
            case .richiediSopralluogo: return true
            }
        }

        var diarioTitolo: String {
            switch self {
            case .richiediVideoperizia: return "Videoperizia richiesta"
            case .richiediSopralluogo: return "Sopralluogo richiesto"
            }
        }
    }

    private var tipoPeriziaCorrente: TipoPerizia {
        if let persisted = TipoPerizia.fromStorage(sinistro.tipoPeriziaEffettuata) {
            return persisted
        }
        return tipoPeriziaDerivato
    }

    /// Derivazione dallo stato corrente, usata solo come fallback quando
    /// `tipoPeriziaEffettuata` non è ancora stato valorizzato (sinistri
    /// pre-esistenti). Una volta scritto, il campo persistito sopravvive
    /// anche dopo la chiusura del sinistro.
    private var tipoPeriziaDerivato: TipoPerizia {
        if let descrizione = sinistro.stato,
           let statoId = StatoManager.shared.getStatoId(fromDescrizione: descrizione),
           let stato = StatoManager.StatoSinistro(rawValue: statoId),
           stato.stateGroup == .videoperizia || stato.variant == .videoperizia {
            return .videoperizia
        }
        return sinistro.sopralluogo ? .tradizionale : .documentale
    }

    private var azioniTipoDisponibili: [TipoPeriziaAction] {
        switch tipoPeriziaCorrente {
        case .documentale: return [.richiediVideoperizia, .richiediSopralluogo]
        case .videoperizia: return [.richiediSopralluogo]
        case .tradizionale: return []
        }
    }

    @ViewBuilder
    private var tipoPeriziaControl: some View {
        if azioniTipoDisponibili.isEmpty {
            Text(tipoPeriziaCorrente.rawValue)
                .foregroundColor(.primary)
        } else {
            Menu {
                ForEach(azioniTipoDisponibili) { action in
                    Button {
                        keepAssignmentOnTipoChange = false
                        pendingTipoAction = action
                    } label: {
                        Label(action.titolo, systemImage: action.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tipoPeriziaCorrente.rawValue)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Cambia tipo di perizia")
        }
    }

    private func applyTipoPeriziaAction(_ action: TipoPeriziaAction, keepAssignment: Bool) async {
        let nuovoStato = action.nuovoStato
        let descrizioneNuova = nuovoStato.descrizione
        let oggi = Date()

        let tipoPrecedente = tipoPeriziaCorrente.rawValue
        let previousOwnerName = sinistro.assignedToUserName
            ?? sinistro.assignedToUserEmail
            ?? sinistro.ownerEmail
            ?? "—"
        let userName = UserProfileService.shared.currentProfile?.displayName
            ?? CurrentUserService.shared.currentUsername
            ?? "Utente"

        let nuovoTipo: TipoPerizia = (action == .richiediVideoperizia) ? .videoperizia : .tradizionale

        await viewContext.perform {
            sinistro.stato = descrizioneNuova
            sinistro.sopralluogo = action.nuovoSopralluogoFlag
            sinistro.tipoPeriziaEffettuata = nuovoTipo.storageValue

            if !keepAssignment {
                sinistro.assignedToUserEmail = nil
                sinistro.assignedToUserName = nil
                sinistro.dataAssegnazione = nil
            }

            let assegnazioneNota = keepAssignment
                ? "Assegnazione mantenuta a \(previousOwnerName)."
                : "Assegnazione rimossa: il sinistro è stato rimandato nel pool."

            let entry = DiarioEntry(
                timestamp: oggi,
                tipo: .sistema,
                titolo: action.diarioTitolo,
                riassunto: "\(userName) ha richiesto: \(action.titolo.lowercased())",
                contenutoCompleto: """
                Azione: \(action.titolo)
                Tipo precedente: \(tipoPrecedente)
                Nuovo stato: \(descrizioneNuova)
                \(assegnazioneNota)
                Data: \(DateUtils.formatDetail(oggi))
                """
            )
            sinistro.addDiarioEntry(entry)
            sinistro.markAsLocallyModified()
            try? viewContext.save()
        }

        // Propaga la transizione di stato al backend: il server si occupa di
        // notificare l'assicurato, generare le pagine portale e aggiornare i
        // substati (videoperizia_da_fissare / sopralluogo_da_fissare).
        do {
            try await ClaimAdapter.shared.changeState(
                riferimento: sinistro.riferimento ?? "",
                newState: nuovoStato,
                reason: action.titolo,
                changedBy: CurrentUserService.shared.currentUsername ?? "ipad"
            )
        } catch {
            print("[VerificheSectionView] ⚠️ changeState fallita: \(error.localizedDescription)")
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
        // Se l'utente ha cambiato Documentale/Tradizionale dal picker editing,
        // persisti il tipo: la videoperizia si imposta solo dal flusso dialog.
        if TipoPerizia.fromStorage(sinistro.tipoPeriziaEffettuata) != .videoperizia {
            let tipo: TipoPerizia = sinistro.sopralluogo ? .tradizionale : .documentale
            sinistro.tipoPeriziaEffettuata = tipo.storageValue
        }
        sinistro.markAsLocallyModified()
        try? viewContext.save()
    }

    /// Backfill: per sinistri preesistenti senza il campo persistito, salviamo
    /// la derivazione corrente così sopravvive a stati terminali successivi.
    private func backfillTipoPeriziaIfNeeded() {
        guard sinistroPathExists,
              (sinistro.tipoPeriziaEffettuata ?? "").isEmpty else { return }
        sinistro.tipoPeriziaEffettuata = tipoPeriziaDerivato.storageValue
        try? viewContext.save()
    }
}

// MARK: - Dialog conferma cambio tipo perizia

private struct CambioTipoPeriziaDialog: View {
    let action: VerificheSectionView.TipoPeriziaAction
    let tipoCorrente: String
    @Binding var keepAssignment: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        action: VerificheSectionView.TipoPeriziaAction,
        tipoCorrente: VerificheSectionView.TipoPerizia,
        keepAssignment: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.action = action
        self.tipoCorrente = tipoCorrente.rawValue
        self._keepAssignment = keepAssignment
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(action.titolo)
                    .font(.headline)
            }

            Text(messaggio)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $keepAssignment) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mantieni assegnazione")
                        .font(.subheadline.weight(.medium))
                    Text("Se disattivato, il sinistro torna nel pool senza perito.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button("Annulla", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action.titolo, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var messaggio: String {
        switch action {
        case .richiediVideoperizia:
            return "Il sinistro passerà da \(tipoCorrente) a Videoperizia da fissare. " +
                   "L'assicurato riceverà la richiesta di scelta dello slot e verranno create le pagine portale dedicate."
        case .richiediSopralluogo:
            return "Il sinistro passerà da \(tipoCorrente) a Sopralluogo da fissare. " +
                   "Verrà avviato il flusso di pianificazione del sopralluogo e aggiornata la pratica come Tradizionale."
        }
    }
}
