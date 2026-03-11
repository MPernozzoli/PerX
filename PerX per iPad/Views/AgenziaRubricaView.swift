//
//  AgenziaRubricaView.swift
//  PerX per iPad
//
//  Rubrica agenzie gerarchica con editing (iOS/iPadOS)
//  Struttura: Gruppo → Compagnia → Agenzia → Agente
//  NOTA: Gruppi e Compagnie sono enum fissi da CompagniaService, non editabili
//

import SwiftUI
import UIKit

struct AgenziaRubricaView: View {
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var searchText = ""
    @State private var selectedGruppo: GruppoAssicurativo?
    @State private var selectedCompagnia: Compagnia?
    @State private var selectedAgenzia: RubricaAgenzia?
    @State private var showingAddAgenzia = false
    @State private var showingAddFiliale = false
    @State private var parentAgenziaForFiliale: RubricaAgenzia?
    @State private var copiedToast = false
    @State private var copiedMessage = ""
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if searchText.count >= 2 {
                    searchResultsList
                } else {
                    hierarchyList
                }
            }
            .navigationTitle("Rubrica Agenzie")
            .searchable(text: $searchText, prompt: "Cerca agenzia...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await service.syncAll() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if service.isSyncing {
                        ProgressView()
                    }
                }
            }
            .navigationDestination(for: GruppoAssicurativo.self) { gruppo in
                GruppoDetailView(gruppo: gruppo)
            }
            .navigationDestination(for: Compagnia.self) { compagnia in
                CompagniaDetailView(compagnia: compagnia)
            }
            .sheet(item: $selectedAgenzia) { agenzia in
                AgenziaDetailSheet(agenzia: agenzia)
            }
            .overlay(alignment: .bottom) {
                if copiedToast {
                    toastView
                }
            }
        }
        .task {
            await service.loadInitial()
        }
    }
    
    // MARK: - Hierarchy List
    
    private var hierarchyList: some View {
        List {
            ForEach(service.gruppi, id: \.self) { gruppo in
                NavigationLink(value: gruppo) {
                    HStack {
                        Image(systemName: gruppo.uiIconSystemName)
                            .foregroundColor(gruppo.color)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading) {
                            Text(gruppo.rawValue)
                                .fontWeight(.semibold)
                            Text("\(service.compagniePer(gruppo: gruppo).count) compagnie")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(countAgenziePer(gruppo: gruppo))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
            }
            
            if service.gruppi.isEmpty && !service.isLoading {
                ContentUnavailableView {
                    Label("Nessun gruppo", systemImage: "folder")
                } description: {
                    Text("I gruppi assicurativi sono predefiniti dal sistema")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await service.syncAll()
        }
    }
    
    // MARK: - Search Results
    
    private var searchResultsList: some View {
        List(service.searchAgenzie(searchText)) { agenzia in
            Button {
                selectedAgenzia = agenzia
            } label: {
                AgenziaRowView(agenzia: agenzia)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func countAgenziePer(gruppo: GruppoAssicurativo) -> Int {
        let compagnieIds = service.compagniePer(gruppo: gruppo).map { $0.rubricaId }
        return service.agenzie.filter { compagnieIds.contains($0.compagniaId) }.count
    }
    
    private var toastView: some View {
        Text(copiedMessage)
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
        copiedMessage = message
        withAnimation {
            copiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToast = false
            }
        }
    }
}

// MARK: - Gruppo Detail View

struct GruppoDetailView: View {
    let gruppo: GruppoAssicurativo
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var selectedAgenzia: RubricaAgenzia?
    
    var body: some View {
        List {
            ForEach(service.compagniePer(gruppo: gruppo), id: \.self) { compagnia in
                NavigationLink(value: compagnia) {
                    HStack {
                        Image(systemName: "building")
                            .foregroundColor(compagnia.color)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading) {
                            Text(compagnia.rawValue)
                                .fontWeight(.medium)
                            Text(compagnia.sigla)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(service.tutteAgenziePer(compagniaId: compagnia.rubricaId).count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(gruppo.rawValue)
        .sheet(item: $selectedAgenzia) { agenzia in
            AgenziaDetailSheet(agenzia: agenzia)
        }
    }
}

// MARK: - Compagnia Detail View

struct CompagniaDetailView: View {
    let compagnia: Compagnia
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var showingAddAgenzia = false
    @State private var showingAddFiliale = false
    @State private var parentAgenziaForFiliale: RubricaAgenzia?
    @State private var selectedAgenzia: RubricaAgenzia?
    
    var body: some View {
        List {
            // Agenzie principali (non filiali)
            ForEach(service.agenziePer(compagniaId: compagnia.rubricaId)) { agenzia in
                let filiali = service.filialiPer(agenziaId: agenzia.id)
                
                Section {
                    // Agenzia madre
                    Button {
                        selectedAgenzia = agenzia
                    } label: {
                        AgenziaRowView(agenzia: agenzia, hasFiliali: !filiali.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { try? await service.deleteAgenzia(agenzia.id) }
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                        
                        Button {
                            parentAgenziaForFiliale = agenzia
                            showingAddFiliale = true
                        } label: {
                            Label("Filiale", systemImage: "plus.circle")
                        }
                        .tint(.purple)
                    }
                    
                    // Filiali
                    ForEach(filiali) { filiale in
                        Button {
                            selectedAgenzia = filiale
                        } label: {
                            AgenziaRowView(agenzia: filiale, isFiliale: true)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { try? await service.deleteAgenzia(filiale.id) }
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(compagnia.rawValue)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddAgenzia = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAgenzia) {
            AgenziaEditorSheet(agenzia: nil, compagniaId: compagnia.rubricaId) { agenzia in
                Task { try? await service.saveAgenzia(agenzia) }
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
        .sheet(item: $selectedAgenzia) { agenzia in
            AgenziaDetailSheet(agenzia: agenzia)
        }
    }
}

// MARK: - Agenzia Row

struct AgenziaRowView: View {
    let agenzia: RubricaAgenzia
    var isFiliale: Bool = false
    var hasFiliali: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icona tipo sede
            if isFiliale {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
            } else if hasFiliali {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                    .foregroundColor(.purple)
            } else {
                Image(systemName: "building.columns.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(agenzia.nomeCompleto)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    if let suffisso = agenzia.suffissoNome, !suffisso.isEmpty {
                        Text(suffisso)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    if isFiliale {
                        Text("Filiale")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    if let citta = agenzia.citta, !citta.isEmpty {
                        Label {
                            Text(citta)
                            if let prov = agenzia.provincia, !prov.isEmpty {
                                Text("(\(prov))")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                        }
                        .font(.caption)
                    }
                    
                    if let tel = agenzia.telefonoPrincipale {
                        Label(tel, systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                if let area = agenzia.descrAreaLegacy, !area.isEmpty {
                    Text(area)
                        .font(.caption2)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Agenzia Detail Sheet

struct AgenziaDetailSheet: View {
    let agenzia: RubricaAgenzia
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CloudKitRubricaSyncService.shared
    @State private var isEditing = false
    @State private var copiedMessage: String?
    @State private var showingAddFiliale = false
    
    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if agenzia.isFiliale {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.orange)
                            } else if service.hasFiliali(agenzia.id) {
                                Image(systemName: "building.2.fill")
                                    .foregroundColor(.purple)
                            }
                            
                            Text(agenzia.nomeCompleto)
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        
                        if let suffisso = agenzia.suffissoNome, !suffisso.isEmpty {
                            Text(suffisso)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if agenzia.isFiliale {
                            Text("Filiale")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if let area = agenzia.descrAreaLegacy, !area.isEmpty {
                            Text(area)
                                .font(.caption)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Contatti
                Section("Contatti") {
                    ForEach(Array(agenzia.telefoni.enumerated()), id: \.offset) { idx, tel in
                        contactRow(icon: "phone.fill", label: "Telefono \(idx + 1)", value: tel)
                    }
                    
                    ForEach(Array(agenzia.email.enumerated()), id: \.offset) { idx, email in
                        contactRow(icon: "envelope.fill", label: "Email \(idx + 1)", value: email)
                    }
                    
                    if let fax = agenzia.fax, !fax.isEmpty {
                        contactRow(icon: "faxmachine", label: "Fax", value: fax)
                    }
                }
                
                // Indirizzo
                if !agenzia.indirizzoCompleto.isEmpty {
                    Section("Indirizzo") {
                        Button {
                            copyToClipboard(agenzia.indirizzoCompleto, label: "Indirizzo")
                        } label: {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.red)
                                    .frame(width: 24)
                                
                                Text(agenzia.indirizzoCompleto)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Note
                if let note = agenzia.note, !note.isEmpty {
                    Section("Note") {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Filiali (solo per agenzie principali)
                if !agenzia.isFiliale {
                    let filiali = service.filialiPer(agenziaId: agenzia.id)
                    
                    Section {
                        if filiali.isEmpty {
                            Text("Nessuna filiale")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(filiali) { filiale in
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle")
                                        .foregroundColor(.orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(filiale.nomeCompleto)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        if let citta = filiale.citta {
                                            Text(citta)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let tel = filiale.telefonoPrincipale {
                                        Text(tel)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        Button {
                            showingAddFiliale = true
                        } label: {
                            Label("Aggiungi filiale", systemImage: "plus.circle")
                        }
                    } header: {
                        Label("Filiali (\(filiali.count))", systemImage: "building.2")
                    }
                }
                
                // Link agenzia madre
                if agenzia.isFiliale, let parentId = agenzia.agenziaParentId,
                   let parent = service.agenzie.first(where: { $0.id == parentId }) {
                    Section("Agenzia Madre") {
                        HStack {
                            Image(systemName: "building.columns")
                                .foregroundColor(.purple)
                            Text(parent.nomeCompleto)
                                .font(.subheadline)
                        }
                    }
                }
                
                // Azioni
                Section {
                    Button {
                        copyToClipboard(agenzia.testoPerCopia, label: "Dati agenzia")
                    } label: {
                        Label("Copia tutti i dati", systemImage: "doc.on.doc.fill")
                    }
                    
                    if let tel = agenzia.telefonoPrincipale {
                        Link(destination: URL(string: "tel:\(tel.replacingOccurrences(of: " ", with: ""))")!) {
                            Label("Chiama", systemImage: "phone.arrow.up.right")
                        }
                    }
                    
                    if let email = agenzia.emailPrincipale {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label("Invia email", systemImage: "envelope.arrow.triangle.branch")
                        }
                    }
                }
            }
            .navigationTitle("Dettaglio Agenzia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifica") { isEditing = true }
                }
            }
            .overlay(alignment: .bottom) {
                if let message = copiedMessage {
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
            }
            .sheet(isPresented: $isEditing) {
                AgenziaEditorSheet(agenzia: agenzia, compagniaId: agenzia.compagniaId) { updated in
                    Task { try? await service.saveAgenzia(updated) }
                }
            }
            .sheet(isPresented: $showingAddFiliale) {
                AgenziaEditorSheet(
                    agenzia: nil,
                    compagniaId: agenzia.compagniaId,
                    agenziaParentId: agenzia.id,
                    parentName: agenzia.nomeCompleto
                ) { filiale in
                    Task { try? await service.saveAgenzia(filiale) }
                }
            }
        }
    }
    
    private func contactRow(icon: String, label: String, value: String) -> some View {
        Button {
            copyToClipboard(value, label: label)
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(value)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func copyToClipboard(_ text: String, label: String) {
        UIPasteboard.general.string = text
        
        withAnimation {
            copiedMessage = "\(label) copiato"
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedMessage = nil
            }
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Editor Sheets
// NOTA: GruppoEditorSheet e CompagniaEditorSheet rimossi
// Gruppi e Compagnie sono enum fissi, non editabili dalla rubrica

struct AgenziaEditorSheet: View {
    let agenzia: RubricaAgenzia?
    let compagniaId: String
    var agenziaParentId: String? = nil
    var parentName: String? = nil
    let onSave: (RubricaAgenzia) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var codice = ""
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
    
    var body: some View {
        NavigationStack {
            Form {
                // Banner filiale
                if isFiliale {
                    Section {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.orange)
                            if let parent = parentName {
                                Text("Filiale di: \(parent)")
                            } else {
                                Text("Questa è una filiale")
                            }
                        }
                    }
                }
                
                Section("Dati Principali") {
                    TextField("Codice (es. 5239)", text: $codice)
                    TextField("Nome", text: $nome)
                    TextField("Suffisso (es. Sede Centrale)", text: $suffissoNome)
                }
                
                Section("Indirizzo") {
                    TextField("Indirizzo", text: $indirizzo)
                    TextField("Città", text: $citta)
                    HStack {
                        TextField("Provincia", text: $provincia)
                        TextField("CAP", text: $cap)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section("Telefoni") {
                    ForEach(telefoni.indices, id: \.self) { idx in
                        HStack {
                            TextField("Telefono \(idx + 1)", text: $telefoni[idx])
                                .keyboardType(.phonePad)
                            if telefoni.count > 1 {
                                Button { telefoni.remove(at: idx) } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    Button { telefoni.append("") } label: {
                        Label("Aggiungi telefono", systemImage: "plus")
                    }
                }
                
                Section("Email") {
                    ForEach(emails.indices, id: \.self) { idx in
                        HStack {
                            TextField("Email \(idx + 1)", text: $emails[idx])
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            if emails.count > 1 {
                                Button { emails.remove(at: idx) } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    Button { emails.append("") } label: {
                        Label("Aggiungi email", systemImage: "plus")
                    }
                }
                
                Section("Altro") {
                    TextField("Fax", text: $fax)
                        .keyboardType(.phonePad)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        var a = agenzia ?? RubricaAgenzia(
                            compagniaId: compagniaId,
                            agenziaParentId: agenziaParentId,
                            codice: codice,
                            nome: nome
                        )
                        a.codice = codice
                        a.nome = nome
                        a.suffissoNome = suffissoNome.isEmpty ? nil : suffissoNome
                        a.agenziaParentId = agenziaParentId ?? agenzia?.agenziaParentId
                        a.indirizzo = indirizzo.isEmpty ? nil : indirizzo
                        a.citta = citta.isEmpty ? nil : citta
                        a.provincia = provincia.isEmpty ? nil : provincia
                        a.cap = cap.isEmpty ? nil : cap
                        a.telefoni = telefoni.filter { !$0.isEmpty }
                        a.email = emails.filter { !$0.isEmpty }
                        a.fax = fax.isEmpty ? nil : fax
                        a.note = note.isEmpty ? nil : note
                        onSave(a)
                        dismiss()
                    }
                    .disabled(nome.isEmpty)
                }
            }
            .onAppear {
                if let a = agenzia {
                    codice = a.codice
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
                }
            }
        }
    }
}

// MARK: - RubricaAgenzia Extension per copia

extension RubricaAgenzia {
    var testoPerCopia: String {
        var result = nomeCompleto
        if !telefoni.isEmpty {
            result += "\nTel: " + telefoni.joined(separator: ", ")
        }
        if !email.isEmpty {
            result += "\nEmail: " + email.joined(separator: ", ")
        }
        if !indirizzoCompleto.isEmpty {
            result += "\nIndirizzo: " + indirizzoCompleto
        }
        return result
    }
}

// MARK: - Preview

#Preview {
    AgenziaRubricaView()
}
