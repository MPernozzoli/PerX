//
//  AgenziaRubricaView.swift
//  PerX
//
//  Rubrica agenzie gerarchica con editing (macOS)
//  Struttura: Gruppo → Compagnia → Agenzia → Agente
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AgenziaRubricaView: View {
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var searchText = ""
    @State private var selectedGruppo: GruppoAssicurativo?
    @State private var selectedCompagnia: Compagnia?
    @State private var selectedAgenziaId: String?
    // NOTA: Gruppi e Compagnie sono fissi (da CompagniaService), non editabili
    @State private var showingAddAgenzia = false
    @State private var showingAddFiliale = false
    @State private var parentAgenziaForFiliale: RubricaAgenzia?
    @State private var showingImport = false
    @State private var copiedMessage: String?
    
    var body: some View {
        HSplitView {
            // Sidebar gerarchica
            sidebarView
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            
            // Dettaglio
            detailView
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await service.syncAll() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(service.isSyncing)
                .help("Sincronizza rubrica")
                
                Menu {
                    Button("Importa da JSON legacy...") {
                        showingImport = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Importa dati")
            }
        }
        .overlay(alignment: .bottom) {
            if let message = copiedMessage {
                toastView(message)
            }
        }
        .task {
            await service.loadInitial()
        }
        .overlay {
            if service.isLoading || (service.agenzie.isEmpty && service.isSyncing) {
                RubricaLoadingView(isSyncing: service.isSyncing)
            }
        }
        // NOTA: Gruppi e Compagnie sono fissi (enum da CompagniaService), non si creano nuovi
        .sheet(isPresented: $showingAddAgenzia) {
            if let compagnia = selectedCompagnia {
                AgenziaEditorSheet(agenzia: nil, compagniaId: compagnia.rubricaId) { agenzia in
                    Task { try? await service.saveAgenzia(agenzia) }
                }
            }
        }
        .sheet(isPresented: $showingAddFiliale) {
            if let parent = parentAgenziaForFiliale {
                AgenziaEditorSheet(
                    agenzia: nil,
                    compagniaId: parent.compagniaId,
                    agenziaParentId: parent.id,
                    parentName: parent.nomeCompleto
                ) { filiale in
                    Task { try? await service.saveAgenzia(filiale) }
                }
            }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task {
                    do {
                        let count = try await service.importFromLegacyJSON(url: url)
                        showCopied("Importate \(count) agenzie")
                    } catch {
                        showCopied("Errore: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Ricerca
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Cerca...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor).opacity(0.5))
            
            Divider()
            
            if searchText.count >= 2 {
                // Risultati ricerca
                searchResultsList
            } else {
                // Navigazione gerarchica
                hierarchyList
            }
            
            Divider()
            
            // Footer con stats
            HStack {
                if service.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text("\(service.agenzie.count) agenzie")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if let date = service.lastSyncDate {
                    Text("Sync: \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
    }
    
    private var hierarchyList: some View {
        List {
            ForEach(service.gruppi, id: \.self) { gruppo in
                GruppoDisclosureView(
                    gruppo: gruppo,
                    service: service,
                    selectedAgenziaId: $selectedAgenziaId,
                    selectedCompagnia: $selectedCompagnia,
                    selectedGruppo: $selectedGruppo,
                    showingAddAgenzia: $showingAddAgenzia,
                    showingAddFiliale: $showingAddFiliale,
                    parentAgenziaForFiliale: $parentAgenziaForFiliale
                )
            }
        }
    }
    
    // MARK: - Sezione rimossa - bottone aggiungi gruppo (ora fissi da enum)
    // Il vecchio codice con "Aggiungi compagnia" è stato rimosso perché i gruppi/compagnie
    // sono enum fissi definiti in CompagniaService.swift
    
    private var searchResultsList: some View {
        List(service.searchAgenzie(searchText), selection: $selectedAgenziaId) { agenzia in
            AgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id)
                .tag(agenzia.id)
        }
        .listStyle(.plain)
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        if let agenziaId = selectedAgenziaId,
           let agenzia = service.agenzie.first(where: { $0.id == agenziaId }) {
            AgenziaDetailMacView(agenzia: agenzia, onCopy: showCopied) { parent in
                parentAgenziaForFiliale = parent
                showingAddFiliale = true
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "building.2")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("Seleziona un'agenzia")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Oppure cerca per nome, codice o città")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Helpers
    // NOTA: iconForGruppo e colorForGruppo rimossi - ora uso proprietà degli enum
    
    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green)
            .cornerRadius(20)
            .shadow(radius: 4)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func showCopied(_ message: String) {
        withAnimation {
            copiedMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedMessage = nil
            }
        }
    }
}

// MARK: - Agenzia Row

struct AgenziaRowView: View {
    let agenzia: RubricaAgenzia
    var isSelected: Bool = false
    var isFiliale: Bool = false
    var hasFiliali: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Icona per tipo sede
            if isFiliale {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            } else if hasFiliali {
                Image(systemName: "building.2")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(agenzia.nomeCompleto)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    if let suffisso = agenzia.suffissoNome, !suffisso.isEmpty {
                        Text(suffisso)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 8) {
                    if let citta = agenzia.citta, !citta.isEmpty {
                        Text(citta)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if let tel = agenzia.telefonoPrincipale {
                        Text(tel)
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, isFiliale ? 8 : 0)
        .contentShape(Rectangle())
    }
}

// MARK: - Agenzia Detail (Mac)

struct AgenziaDetailMacView: View {
    let agenzia: RubricaAgenzia
    let onCopy: (String) -> Void
    let onAddFiliale: (RubricaAgenzia) -> Void
    
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var isEditing = false
    @State private var editedAgenzia: RubricaAgenzia?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agenzia.nomeCompleto)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let area = agenzia.descrAreaLegacy, !area.isEmpty {
                            Text(area)
                                .font(.caption)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        editedAgenzia = agenzia
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Modifica")
                }
                
                Divider()
                
                // Contatti
                GroupBox("Contatti") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(agenzia.telefoni.enumerated()), id: \.offset) { idx, tel in
                            contactRow(icon: "phone.fill", color: .green, label: "Telefono \(idx + 1)", value: tel)
                        }
                        
                        ForEach(Array(agenzia.email.enumerated()), id: \.offset) { idx, email in
                            contactRow(icon: "envelope.fill", color: .blue, label: "Email \(idx + 1)", value: email)
                        }
                        
                        if let fax = agenzia.fax, !fax.isEmpty {
                            contactRow(icon: "faxmachine", color: .gray, label: "Fax", value: fax)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Indirizzo
                if !agenzia.indirizzoCompleto.isEmpty {
                    GroupBox("Indirizzo") {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.red)
                            Text(agenzia.indirizzoCompleto)
                            Spacer()
                            Button {
                                copyToClipboard(agenzia.indirizzoCompleto)
                                onCopy("Indirizzo copiato")
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Orari
                if let orari = agenzia.orariApertura {
                    GroupBox("Orari di Apertura") {
                        Text(orari.descrizioneCompatta)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                
                // Note
                if let note = agenzia.note, !note.isEmpty {
                    GroupBox("Note") {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                
                // Filiali (solo per agenzie principali)
                if !agenzia.isFiliale {
                    let filiali = service.filialiPer(agenziaId: agenzia.id)
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if filiali.isEmpty {
                                Text("Nessuna filiale")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filiali) { filiale in
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.circle")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 12))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(filiale.nomeCompleto)
                                                .font(.system(size: 12, weight: .medium))
                                            
                                            if let citta = filiale.citta {
                                                Text(citta)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if let tel = filiale.telefonoPrincipale {
                                            Text(tel)
                                                .font(.system(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    
                                    if filiale.id != filiali.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button {
                                onAddFiliale(agenzia)
                            } label: {
                                Label("Aggiungi filiale", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Filiali (\(filiali.count))", systemImage: "building.2")
                    }
                }
                
                // Se è una filiale, mostra link all'agenzia madre
                if agenzia.isFiliale, let parentId = agenzia.agenziaParentId,
                   let parent = service.agenzie.first(where: { $0.id == parentId }) {
                    GroupBox {
                        HStack {
                            Image(systemName: "building.columns")
                                .foregroundColor(.purple)
                            Text("Agenzia madre: \(parent.nomeCompleto)")
                                .font(.caption)
                        }
                    }
                }
                
                Divider()
                
                // Azioni
                HStack(spacing: 12) {
                    Button {
                        copyToClipboard(agenzia.testoPerCopia)
                        onCopy("Dati copiati")
                    } label: {
                        Label("Copia tutto", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let email = agenzia.emailPrincipale {
                        Button {
                            if let url = URL(string: "mailto:\(email)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Email", systemImage: "envelope")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // TODO: Sezione sinistri aperti/chiusi
                // Sarà implementata dopo l'integrazione con SinistroDetailView
                
                Spacer()
            }
            .padding(20)
        }
        .frame(minWidth: 400)
        .sheet(isPresented: $isEditing) {
            if let edited = editedAgenzia {
                AgenziaEditorSheet(agenzia: edited, compagniaId: edited.compagniaId) { updated in
                    Task { try? await service.saveAgenzia(updated) }
                }
            }
        }
    }
    
    private func contactRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13))
            }
            
            Spacer()
            
            Button {
                copyToClipboard(value)
                onCopy("\(label) copiato")
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Editor Sheets
// NOTA: GruppoEditorSheet e CompagniaEditorSheet rimossi
// Gruppi e Compagnie sono enum fissi definiti in CompagniaService.swift

struct AgenziaEditorSheet: View {
    let agenzia: RubricaAgenzia?
    let compagniaId: String
    var agenziaParentId: String? = nil
    var parentName: String? = nil
    let onSave: (RubricaAgenzia) -> Void
    
    init(agenzia: RubricaAgenzia?, compagniaId: String, agenziaParentId: String? = nil, parentName: String? = nil, onSave: @escaping (RubricaAgenzia) -> Void) {
        self.agenzia = agenzia
        self.compagniaId = compagniaId
        self.agenziaParentId = agenziaParentId
        self.parentName = parentName
        self.onSave = onSave
    }
    
    @Environment(\.dismiss) private var dismiss
    
    // Dati principali
    @State private var codice = ""
    @State private var codiciAlternativi: [String] = [""]
    @State private var nome = ""
    @State private var suffissoNome = ""
    @State private var indirizzo = ""
    @State private var citta = ""
    @State private var provincia = ""
    @State private var cap = ""
    @State private var telefoni: [String] = [""]
    @State private var emails: [String] = [""]
    @State private var fax = ""
    @State private var note = ""
    
    // Flag
    @State private var problematica = false
    @State private var puntigliosa = false
    @State private var critica = false
    @State private var comunicareSempreEsitiInAgenzia = false
    @State private var attiSempreInAgenzia = false
    @State private var chiamarePrimaDiInviareAtti = false
    @State private var prioritaria = false
    
    // Orari
    @State private var orariAbilitati = false
    // Lunedì
    @State private var lunAp1 = "09:00"
    @State private var lunCh1 = "13:00"
    @State private var lunAp2 = "14:00"
    @State private var lunCh2 = "18:00"
    @State private var lunAperto = true
    // Martedì
    @State private var marAp1 = "09:00"
    @State private var marCh1 = "13:00"
    @State private var marAp2 = "14:00"
    @State private var marCh2 = "18:00"
    @State private var marAperto = true
    // Mercoledì
    @State private var merAp1 = "09:00"
    @State private var merCh1 = "13:00"
    @State private var merAp2 = "14:00"
    @State private var merCh2 = "18:00"
    @State private var merAperto = true
    // Giovedì
    @State private var gioAp1 = "09:00"
    @State private var gioCh1 = "13:00"
    @State private var gioAp2 = "14:00"
    @State private var gioCh2 = "18:00"
    @State private var gioAperto = true
    // Venerdì
    @State private var venAp1 = "09:00"
    @State private var venCh1 = "13:00"
    @State private var venAp2 = "14:00"
    @State private var venCh2 = "18:00"
    @State private var venAperto = true
    // Sabato
    @State private var sabAp1 = "09:00"
    @State private var sabCh1 = "12:00"
    @State private var sabAp2 = ""
    @State private var sabCh2 = ""
    @State private var sabAperto = false
    // Domenica
    @State private var domAp1 = ""
    @State private var domCh1 = ""
    @State private var domAp2 = ""
    @State private var domCh2 = ""
    @State private var domAperto = false
    
    private var isFiliale: Bool {
        agenziaParentId != nil || agenzia?.isFiliale == true
    }
    
    private var titleText: String {
        if agenzia != nil {
            return isFiliale ? "Modifica Filiale" : "Modifica Agenzia"
        } else {
            return isFiliale ? "Nuova Filiale" : "Nuova Agenzia"
        }
    }
    
    private var compagniaDisplay: String {
        Compagnia(rawValue: compagniaId)?.rawValue ?? compagniaId
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(titleText)
                        .font(.title3.bold())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Banner filiale / compagnia
                if isFiliale {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filiale di")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(parentName ?? "Agenzia madre")
                                .font(.subheadline.bold())
                        }
                        Spacer()
                        Text(compagniaDisplay)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "building.columns.fill")
                            .foregroundColor(.accentColor)
                        Text("Compagnia:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(compagniaDisplay)
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(10)
                }
                
                Form {
                    // DATI PRINCIPALI
                    Section("Dati Principali") {
                        TextField("Codice (es. 5239)", text: $codice)
                        TextField("Nome", text: $nome)
                        TextField("Suffisso (es. Sede Centrale)", text: $suffissoNome)
                            .foregroundColor(.secondary)
                    }
                    
                    // CODICI ALTERNATIVI
                    Section {
                        ForEach(codiciAlternativi.indices, id: \.self) { idx in
                            HStack {
                                TextField("Codice alternativo", text: $codiciAlternativi[idx])
                                if codiciAlternativi.count > 1 {
                                    Button { codiciAlternativi.remove(at: idx) } label: {
                                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button { codiciAlternativi.append("") } label: {
                            Label("Aggiungi codice", systemImage: "plus")
                        }
                    } header: {
                        Text("Codici alternativi")
                    } footer: {
                        Text("Per retrocompatibilità con archivio.")
                    }
                    
                    // INDIRIZZO
                    Section("Indirizzo") {
                        TextField("Indirizzo", text: $indirizzo)
                        HStack {
                            TextField("Città", text: $citta)
                            TextField("Prov", text: $provincia).frame(width: 60)
                            TextField("CAP", text: $cap).frame(width: 80)
                        }
                    }
                    
                    // TELEFONI
                    Section("Telefoni") {
                        ForEach(telefoni.indices, id: \.self) { idx in
                            HStack {
                                TextField("Telefono \(idx + 1)", text: $telefoni[idx])
                                if telefoni.count > 1 {
                                    Button { telefoni.remove(at: idx) } label: {
                                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button { telefoni.append("") } label: {
                            Label("Aggiungi telefono", systemImage: "plus")
                        }
                    }
                    
                    // EMAIL
                    Section("Email") {
                        ForEach(emails.indices, id: \.self) { idx in
                            HStack {
                                TextField("Email \(idx + 1)", text: $emails[idx])
                                if emails.count > 1 {
                                    Button { emails.remove(at: idx) } label: {
                                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button { emails.append("") } label: {
                            Label("Aggiungi email", systemImage: "plus")
                        }
                    }
                    
                    // FLAG
                    Section("Segnalazioni") {
                        Toggle(isOn: $prioritaria) {
                            Label("Prioritaria", systemImage: "star.fill")
                                .foregroundColor(.yellow)
                        }
                        Toggle(isOn: $problematica) {
                            Label("Problematica", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        Toggle(isOn: $puntigliosa) {
                            Label("Puntigliosa", systemImage: "eye.fill")
                                .foregroundColor(.purple)
                        }
                        Toggle(isOn: $critica) {
                            Label("Critica", systemImage: "exclamationmark.octagon.fill")
                                .foregroundColor(.red)
                        }
                        Toggle(isOn: $comunicareSempreEsitiInAgenzia) {
                            Label("Comunicare sempre esiti in agenzia", systemImage: "megaphone.fill")
                                .foregroundColor(.blue)
                        }
                        Toggle(isOn: $attiSempreInAgenzia) {
                            Label("Atti sempre in agenzia", systemImage: "doc.text.fill")
                                .foregroundColor(.teal)
                        }
                        Toggle(isOn: $chiamarePrimaDiInviareAtti) {
                            Label("Chiamare prima di inviare atti", systemImage: "phone.badge.checkmark")
                                .foregroundColor(.green)
                        }
                    }
                    
                    // ORARI DI APERTURA
                    Section {
                        Toggle("Imposta orari di apertura", isOn: $orariAbilitati)
                        
                        if orariAbilitati {
                            orarioGiornoEditor(giorno: "Lunedì", aperto: $lunAperto, ap1: $lunAp1, ch1: $lunCh1, ap2: $lunAp2, ch2: $lunCh2)
                            orarioGiornoEditor(giorno: "Martedì", aperto: $marAperto, ap1: $marAp1, ch1: $marCh1, ap2: $marAp2, ch2: $marCh2)
                            orarioGiornoEditor(giorno: "Mercoledì", aperto: $merAperto, ap1: $merAp1, ch1: $merCh1, ap2: $merAp2, ch2: $merCh2)
                            orarioGiornoEditor(giorno: "Giovedì", aperto: $gioAperto, ap1: $gioAp1, ch1: $gioCh1, ap2: $gioAp2, ch2: $gioCh2)
                            orarioGiornoEditor(giorno: "Venerdì", aperto: $venAperto, ap1: $venAp1, ch1: $venCh1, ap2: $venAp2, ch2: $venCh2)
                            orarioGiornoEditor(giorno: "Sabato", aperto: $sabAperto, ap1: $sabAp1, ch1: $sabCh1, ap2: $sabAp2, ch2: $sabCh2)
                            orarioGiornoEditor(giorno: "Domenica", aperto: $domAperto, ap1: $domAp1, ch1: $domCh1, ap2: $domAp2, ch2: $domCh2)
                        }
                    } header: {
                        Text("Orari di Apertura")
                    }
                    
                    // ALTRO
                    Section("Altro") {
                        TextField("Fax", text: $fax)
                        TextField("Note", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .formStyle(.grouped)
                
                // Pulsanti
                HStack {
                    Button("Annulla") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Salva") {
                        saveAgenzia()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(nome.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 550, height: 700)
        .onAppear { loadFromAgenzia() }
    }
    
    // MARK: - Orario Giorno Editor
    
    private func orarioGiornoEditor(
        giorno: String,
        aperto: Binding<Bool>,
        ap1: Binding<String>,
        ch1: Binding<String>,
        ap2: Binding<String>,
        ch2: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: aperto) {
                Text(giorno)
                    .font(.subheadline.bold())
            }
            
            if aperto.wrappedValue {
                HStack(spacing: 8) {
                    Text("Mattina:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .trailing)
                    TextField("09:00", text: ap1)
                        .frame(width: 55)
                        .textFieldStyle(.roundedBorder)
                    Text("-")
                    TextField("13:00", text: ch1)
                        .frame(width: 55)
                        .textFieldStyle(.roundedBorder)
                    
                    Spacer().frame(width: 16)
                    
                    Text("Pomeriggio:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                    TextField("14:00", text: ap2)
                        .frame(width: 55)
                        .textFieldStyle(.roundedBorder)
                    Text("-")
                    TextField("18:00", text: ch2)
                        .frame(width: 55)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Build OrariApertura
    
    private func buildOrarioGiorno(aperto: Bool, ap1: String, ch1: String, ap2: String, ch2: String) -> OrarioGiorno {
        guard aperto else { return OrarioGiorno(aperto: false, fasce: []) }
        var fasce: [FasciaOraria] = []
        if let f1 = FasciaOraria(apertura: ap1, chiusura: ch1) {
            fasce.append(f1)
        }
        if !ap2.isEmpty, !ch2.isEmpty, let f2 = FasciaOraria(apertura: ap2, chiusura: ch2) {
            fasce.append(f2)
        }
        return OrarioGiorno(aperto: !fasce.isEmpty, fasce: fasce)
    }
    
    private func buildOrari() -> OrariApertura? {
        guard orariAbilitati else { return nil }
        return OrariApertura(
            lunedi: buildOrarioGiorno(aperto: lunAperto, ap1: lunAp1, ch1: lunCh1, ap2: lunAp2, ch2: lunCh2),
            martedi: buildOrarioGiorno(aperto: marAperto, ap1: marAp1, ch1: marCh1, ap2: marAp2, ch2: marCh2),
            mercoledi: buildOrarioGiorno(aperto: merAperto, ap1: merAp1, ch1: merCh1, ap2: merAp2, ch2: merCh2),
            giovedi: buildOrarioGiorno(aperto: gioAperto, ap1: gioAp1, ch1: gioCh1, ap2: gioAp2, ch2: gioCh2),
            venerdi: buildOrarioGiorno(aperto: venAperto, ap1: venAp1, ch1: venCh1, ap2: venAp2, ch2: venCh2),
            sabato: buildOrarioGiorno(aperto: sabAperto, ap1: sabAp1, ch1: sabCh1, ap2: sabAp2, ch2: sabCh2),
            domenica: buildOrarioGiorno(aperto: domAperto, ap1: domAp1, ch1: domCh1, ap2: domAp2, ch2: domCh2)
        )
    }
    
    // MARK: - Load / Save
    
    private func loadFromAgenzia() {
        guard let a = agenzia else { return }
        codice = a.codice
        codiciAlternativi = a.codiciAlternativi.isEmpty ? [""] : a.codiciAlternativi
        nome = a.nome
        suffissoNome = a.suffissoNome ?? ""
        indirizzo = a.indirizzo ?? ""
        citta = a.citta ?? ""
        provincia = a.provincia ?? ""
        cap = a.cap ?? ""
        telefoni = a.telefoni.isEmpty ? [""] : a.telefoni
        emails = a.email.isEmpty ? [""] : a.email
        fax = a.fax ?? ""
        note = a.note ?? ""
        
        // Flag
        problematica = a.problematica
        puntigliosa = a.puntigliosa
        critica = a.critica
        comunicareSempreEsitiInAgenzia = a.comunicareSempreEsitiInAgenzia
        attiSempreInAgenzia = a.attiSempreInAgenzia
        chiamarePrimaDiInviareAtti = a.chiamarePrimaDiInviareAtti
        prioritaria = a.prioritaria
        
        // Orari
        if let orari = a.orariApertura {
            orariAbilitati = true
            let lun = Self.parseOrarioGiorno(orari.lunedi)
            lunAperto = lun.aperto; lunAp1 = lun.ap1; lunCh1 = lun.ch1; lunAp2 = lun.ap2; lunCh2 = lun.ch2
            let mar = Self.parseOrarioGiorno(orari.martedi)
            marAperto = mar.aperto; marAp1 = mar.ap1; marCh1 = mar.ch1; marAp2 = mar.ap2; marCh2 = mar.ch2
            let mer = Self.parseOrarioGiorno(orari.mercoledi)
            merAperto = mer.aperto; merAp1 = mer.ap1; merCh1 = mer.ch1; merAp2 = mer.ap2; merCh2 = mer.ch2
            let gio = Self.parseOrarioGiorno(orari.giovedi)
            gioAperto = gio.aperto; gioAp1 = gio.ap1; gioCh1 = gio.ch1; gioAp2 = gio.ap2; gioCh2 = gio.ch2
            let ven = Self.parseOrarioGiorno(orari.venerdi)
            venAperto = ven.aperto; venAp1 = ven.ap1; venCh1 = ven.ch1; venAp2 = ven.ap2; venCh2 = ven.ch2
            let sab = Self.parseOrarioGiorno(orari.sabato)
            sabAperto = sab.aperto; sabAp1 = sab.ap1; sabCh1 = sab.ch1; sabAp2 = sab.ap2; sabCh2 = sab.ch2
            let dom = Self.parseOrarioGiorno(orari.domenica)
            domAperto = dom.aperto; domAp1 = dom.ap1; domCh1 = dom.ch1; domAp2 = dom.ap2; domCh2 = dom.ch2
        }
    }
    
    private static func parseOrarioGiorno(_ og: OrarioGiorno) -> (aperto: Bool, ap1: String, ch1: String, ap2: String, ch2: String) {
        var ap1 = "", ch1 = "", ap2 = "", ch2 = ""
        if og.fasce.count >= 1 {
            ap1 = og.fasce[0].aperturaString
            ch1 = og.fasce[0].chiusuraString
        }
        if og.fasce.count >= 2 {
            ap2 = og.fasce[1].aperturaString
            ch2 = og.fasce[1].chiusuraString
        }
        return (og.aperto, ap1, ch1, ap2, ch2)
    }
    
    private func saveAgenzia() {
        var a = agenzia ?? RubricaAgenzia(
            compagniaId: compagniaId,
            agenziaParentId: agenziaParentId,
            codice: codice,
            codiciAlternativi: codiciAlternativi.filter { !$0.isEmpty },
            nome: nome
        )
        a.codice = codice
        a.codiciAlternativi = codiciAlternativi.filter { !$0.isEmpty }
        a.nome = nome
        a.suffissoNome = suffissoNome.isEmpty ? nil : suffissoNome
        a.agenziaParentId = agenziaParentId ?? agenzia?.agenziaParentId
        a.compagniaId = compagniaId
        a.indirizzo = indirizzo.isEmpty ? nil : indirizzo
        a.citta = citta.isEmpty ? nil : citta
        a.provincia = provincia.isEmpty ? nil : provincia
        a.cap = cap.isEmpty ? nil : cap
        a.telefoni = telefoni.filter { !$0.isEmpty }
        a.email = emails.filter { !$0.isEmpty }
        a.fax = fax.isEmpty ? nil : fax
        a.note = note.isEmpty ? nil : note
        
        // Flag
        a.problematica = problematica
        a.puntigliosa = puntigliosa
        a.critica = critica
        a.comunicareSempreEsitiInAgenzia = comunicareSempreEsitiInAgenzia
        a.attiSempreInAgenzia = attiSempreInAgenzia
        a.chiamarePrimaDiInviareAtti = chiamarePrimaDiInviareAtti
        a.prioritaria = prioritaria
        
        // Orari
        a.orariApertura = buildOrari()
        
        onSave(a)
        dismiss()
    }
}

// MARK: - Subviews per Type Checker

/// Disclosure group per singolo gruppo assicurativo
private struct GruppoDisclosureView: View {
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddAgenzia: Bool
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    
    var body: some View {
        DisclosureGroup {
            ForEach(service.compagniePer(gruppo: gruppo), id: \.self) { compagnia in
                CompagniaDisclosureView(
                    compagnia: compagnia,
                    gruppo: gruppo,
                    service: service,
                    selectedAgenziaId: $selectedAgenziaId,
                    selectedCompagnia: $selectedCompagnia,
                    selectedGruppo: $selectedGruppo,
                    showingAddAgenzia: $showingAddAgenzia,
                    showingAddFiliale: $showingAddFiliale,
                    parentAgenziaForFiliale: $parentAgenziaForFiliale
                )
            }
        } label: {
            gruppoLabel
        }
    }
    
    private var gruppoLabel: some View {
        Label(gruppo.rawValue, systemImage: gruppo.uiIconSystemName)
            .foregroundColor(gruppo.color)
            .badge(agenzieCount)
    }
    
    private var agenzieCount: Int {
        service.compagniePer(gruppo: gruppo)
            .flatMap { service.tutteAgenziePer(compagniaId: $0.rubricaId) }
            .count
    }
}

/// Disclosure group per singola compagnia
private struct CompagniaDisclosureView: View {
    let compagnia: Compagnia
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddAgenzia: Bool
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    
    var body: some View {
        DisclosureGroup {
            agenzieContent
            addAgenziaButton
        } label: {
            compagniaLabel
        }
    }
    
    private var agenzieContent: some View {
        ForEach(service.agenziePer(compagniaId: compagnia.rubricaId)) { agenzia in
            AgenziaItemView(
                agenzia: agenzia,
                compagnia: compagnia,
                gruppo: gruppo,
                service: service,
                selectedAgenziaId: $selectedAgenziaId,
                selectedCompagnia: $selectedCompagnia,
                selectedGruppo: $selectedGruppo,
                showingAddFiliale: $showingAddFiliale,
                parentAgenziaForFiliale: $parentAgenziaForFiliale
            )
        }
    }
    
    private var addAgenziaButton: some View {
        Button {
            selectedCompagnia = compagnia
            showingAddAgenzia = true
        } label: {
            Label("Aggiungi agenzia", systemImage: "plus.circle")
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }
    
    private var compagniaLabel: some View {
        HStack {
            Circle()
                .fill(compagnia.color)
                .frame(width: 8, height: 8)
            Label(compagnia.rawValue, systemImage: "building")
        }
        .badge(service.tutteAgenziePer(compagniaId: compagnia.rubricaId).count)
    }
}

/// View per singola agenzia (con o senza filiali)
private struct AgenziaItemView: View {
    let agenzia: RubricaAgenzia
    let compagnia: Compagnia
    let gruppo: GruppoAssicurativo
    @ObservedObject var service: CloudKitRubricaSyncService
    @Binding var selectedAgenziaId: String?
    @Binding var selectedCompagnia: Compagnia?
    @Binding var selectedGruppo: GruppoAssicurativo?
    @Binding var showingAddFiliale: Bool
    @Binding var parentAgenziaForFiliale: RubricaAgenzia?
    
    private var filiali: [RubricaAgenzia] {
        service.filialiPer(agenziaId: agenzia.id)
    }
    
    var body: some View {
        if filiali.isEmpty {
            agenziaSenzaFiliali
        } else {
            agenziaConFiliali
        }
    }
    
    private var agenziaSenzaFiliali: some View {
        AgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id)
            .tag(agenzia.id)
            .onTapGesture { selectAgenzia() }
    }
    
    private var agenziaConFiliali: some View {
        DisclosureGroup {
            filialiContent
            addFilialeButton
        } label: {
            AgenziaRowView(agenzia: agenzia, isSelected: selectedAgenziaId == agenzia.id, hasFiliali: true)
                .badge(filiali.count)
        }
        .tag(agenzia.id)
        .onTapGesture { selectAgenzia() }
    }
    
    private var filialiContent: some View {
        ForEach(filiali) { filiale in
            AgenziaRowView(agenzia: filiale, isSelected: selectedAgenziaId == filiale.id, isFiliale: true)
                .tag(filiale.id)
                .onTapGesture { selectFiliale(filiale) }
        }
    }
    
    private var addFilialeButton: some View {
        Button {
            parentAgenziaForFiliale = agenzia
            showingAddFiliale = true
        } label: {
            Label("Aggiungi filiale", systemImage: "plus.circle")
                .font(.caption2)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
    }
    
    private func selectAgenzia() {
        selectedAgenziaId = agenzia.id
        selectedCompagnia = compagnia
        selectedGruppo = gruppo
    }
    
    private func selectFiliale(_ filiale: RubricaAgenzia) {
        selectedAgenziaId = filiale.id
        selectedCompagnia = compagnia
        selectedGruppo = gruppo
    }
}

// MARK: - Preview

#Preview {
    AgenziaRubricaView()
        .frame(width: 1000, height: 700)
}
