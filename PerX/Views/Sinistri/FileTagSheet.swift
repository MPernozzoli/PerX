import SwiftUI

struct FileTagSheet: View {
    let url: URL
    let sinistroPath: String?
    let sinistro: Sinistro?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var fileTagManager = FileTagManager.shared
    @State private var isEditingQuickPhotoTagField = false
    
    init(url: URL, sinistroPath: String? = nil, sinistro: Sinistro? = nil) {
        self.url = url
        self.sinistroPath = sinistroPath
        self.sinistro = sinistro
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Tag per \(url.lastPathComponent)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Documenti principali
                    TagCategorySection(title: "Documenti") {
                        let docTags = FileTagManager.FileTag.unifiedTagsForUI().filter { $0.category == nil }
                        ForEach(docTags) { tag in
                            TagRowView(tag: tag, url: url, sinistroPath: sinistroPath, sinistro: sinistro)
                        }
                    }
                    
                    // Foto
                    TagCategorySection(title: "Foto") {
                        PhotoQuickTagPanelView(
                            filePath: url.path,
                            sinistroPath: sinistroPath,
                            fileTagManager: fileTagManager,
                            isEditingTextField: $isEditingQuickPhotoTagField
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Chiudi") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 500, height: 600)
        .padding(.top)
    }
}

// MARK: - Tag Category Section

private struct TagCategorySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                content
            }
        }
    }
}

// MARK: - Tag Row View

private struct TagRowView: View {
    let tag: FileTagManager.FileTag
    let url: URL
    let sinistroPath: String?
    let sinistro: Sinistro?
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    
    @State private var additionalText: String = ""
    @State private var selectedBene: String = ""
    @State private var componenteName: String = ""
    @State private var attoSottotipo: String = ""
    @State private var attoStato: String = ""
    @State private var giustificativiTipo: String = ""
    @State private var fulminazioneSottotipo: String = ""
    @State private var allegatiAttoSottotipo: String = ""
    @State private var ubicazioneTipo: String = "rischio" // rischio, tecnico, amministratore, altra
    @State private var ubicazioneAltraDescrizione: String = ""
    @FocusState private var isUbicazioneAltraFocused: Bool
    
    // Focus states per gestire l'input correttamente
    @FocusState private var isComponenteFocused: Bool
    @FocusState private var isBeneFocused: Bool
    @FocusState private var isAdditionalTextFocused: Bool
    
    // Suggerimenti dropdown
    @State private var showBeneSuggestions = false
    @State private var showComponenteSuggestions = false
    
    // Debounce tasks
    @State private var beneDebounceTask: Task<Void, Never>?
    @State private var componenteDebounceTask: Task<Void, Never>?
    @State private var additionalTextDebounceTask: Task<Void, Never>?
    
    // State per valori async
    @State private var availableBeni: [String] = []
    @State private var beniUsatiInSinistro: [String] = []
    @State private var componentiUsatiInSinistro: [String] = []
    @State private var isSelected: Bool = false
    @State private var daAllegare: Bool = false
    
    private func loadAsyncData() {
        let currentTags = fileTagManager.getTagsForFile(at: url.path)
        
        // Per tag unificati, controlla se uno dei tag individuali è presente
        if tag.id == "atto" {
            isSelected = currentTags.contains(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })
            if let attoTag = currentTags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" }) {
                daAllegare = fileTagManager.getDaAllegareInChiusura(forFile: url.path, tagId: attoTag.id)
            }
        } else if tag.id == "giustificativi" {
            isSelected = currentTags.contains(where: { $0.id == "fattura" || $0.id == "preventivo" })
            if let giustTag = currentTags.first(where: { $0.id == "fattura" || $0.id == "preventivo" }) {
                daAllegare = fileTagManager.getDaAllegareInChiusura(forFile: url.path, tagId: giustTag.id)
            }
        } else if tag.id == "foto_ubicazione" {
            isSelected = currentTags.contains(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) })
            if let ubicazioneTag = currentTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                daAllegare = fileTagManager.getDaAllegareInChiusura(forFile: url.path, tagId: ubicazioneTag.id)
            }
        } else {
            isSelected = currentTags.contains(tag)
            daAllegare = fileTagManager.getDaAllegareInChiusura(forFile: url.path, tagId: tag.id)
        }
        
        // Carica suggerimenti beni in background
        Task { @MainActor in
            if let path = sinistroPath {
                availableBeni = await ClosureFilesService.shared.getTaggedBeni(inSinistroPath: path)
                beniUsatiInSinistro = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
                componentiUsatiInSinistro = await commonItemsManager.getComponentiUsedInSinistro(sinistroPath: path)
            }
        }
    }
    
    // Suggerimenti beni con priorità ai già usati nel sinistro
    private var beniSuggestions: [String] {
        let altri = commonItemsManager.allBeni.filter { bene in
            !beniUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(bene) == .orderedSame }
        }
        var result = beniUsatiInSinistro.filter { $0.localizedCaseInsensitiveContains(selectedBene) || selectedBene.isEmpty }
        let altriNonInUsati = altri.filter { bene in
            bene.localizedCaseInsensitiveContains(selectedBene) || selectedBene.isEmpty
        }.filter { bene in
            !beniUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(bene) == .orderedSame }
        }
        result.append(contentsOf: altriNonInUsati)
        return Array(result.prefix(10))
    }
    
    // Suggerimenti componenti
    private var componentiSuggestions: [String] {
        let altri = commonItemsManager.allComponenti.filter { comp in
            !componentiUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(comp) == .orderedSame }
        }
        var result = componentiUsatiInSinistro.filter { $0.localizedCaseInsensitiveContains(componenteName) || componenteName.isEmpty }
        let altriNonInUsati = altri.filter { comp in
            comp.localizedCaseInsensitiveContains(componenteName) || componenteName.isEmpty
        }.filter { comp in
            !componentiUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(comp) == .orderedSame }
        }
        result.append(contentsOf: altriNonInUsati)
        return Array(result.prefix(10))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main tag row
            HStack {
                Button {
                    toggleTag()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? tag.tagColor : .secondary)
                        Text(tag.name)
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if isSelected {
                    // Toggle da allegare
                    Toggle("", isOn: Binding(
                        get: { daAllegare },
                        set: { newValue in
                            daAllegare = newValue
                            Task { @MainActor in
                                // Per tag unificati, usa il tag effettivo
                                let effectiveTagId: String
                                if tag.id == "atto" {
                                    let currentTags = await fileTagManager.getTagsForFile(at: url.path)
                                    if let attoTag = currentTags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" }) {
                                        effectiveTagId = attoTag.id
                                    } else {
                                        effectiveTagId = "atto_da_firmare"
                                    }
                                } else if tag.id == "giustificativi" {
                                    let currentTags = await fileTagManager.getTagsForFile(at: url.path)
                                    if let giustTag = currentTags.first(where: { $0.id == "fattura" || $0.id == "preventivo" }) {
                                        effectiveTagId = giustTag.id
                                    } else {
                                        effectiveTagId = "fattura"
                                    }
                                } else if tag.id == "foto_ubicazione" {
                                    let currentTags = await fileTagManager.getTagsForFile(at: url.path)
                                    if let ubicazioneTag = currentTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                                        effectiveTagId = ubicazioneTag.id
                                    } else {
                                        effectiveTagId = "foto_ubicazione_rischio"
                                    }
                                } else {
                                    effectiveTagId = tag.id
                                }
                                await fileTagManager.setDaAllegareInChiusura(newValue, forFile: url.path, tagId: effectiveTagId)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(daAllegare ? .blue : .secondary.opacity(0.5))
                }
            }
            
            // Opzioni aggiuntive quando selezionato
            if isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    // Testo aggiuntivo (per bene, componente, etc.)
                    if tag.requiresAdditionalText {
                        if tag.id == "foto_componente" {
                            // Componente: campo componente + campo bene
                            componenteFieldsWithAutocomplete
                        } else {
                            // Altri tag con testo aggiuntivo
                            additionalTextFieldWithAutocomplete
                        }
                    }
                    
                    // Opzioni per tag atto (supporta sia tag individuali che unificato "atto")
                    if FileTagManager.FileTag.attoTags.contains(tag.id) || tag.id == "atto" {
                        attoStatoView
                        attoSottotipoView
                    }
                    
                    // Tipo giustificativi (supporta sia tag individuali che unificato "giustificativi")
                    if FileTagManager.FileTag.giustificativiTags.contains(tag.id) || tag.id == "giustificativi" {
                        giustificativiTipoView
                    }
                    
                    // Sottotipo fulminazione
                    if FileTagManager.FileTag.fulminazioneTags.contains(tag.id) {
                        fulminazioneSottotipoView
                    }
                    
                    // Sottotipo allegati atto
                    if FileTagManager.FileTag.allegatiAttoTags.contains(tag.id) {
                        allegatiAttoSottotipoView
                    }
                    
                    // Tipo ubicazione (supporta sia tag individuali che unificato "foto_ubicazione")
                    if FileTagManager.FileTag.ubicazioneTags.contains(tag.id) || tag.id == "foto_ubicazione" {
                        ubicazioneTipoView
                    }
                    
                    // Bene di riferimento (per test funzionali, test strumentali, ripristini)
                    if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) && tag.id != "foto_componente" {
                        beneRiferimentoViewWithAutocomplete
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? tag.tagColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onAppear {
            loadAsyncData()
            loadExistingValues()
        }
        .onDisappear {
            // Salva tutto quando la view scompare (cambio foto, chiusura sheet, ecc.)
            saveAllValues()
        }
        .onChange(of: selectedBene) { _ in
            // Salva il bene ad ogni modifica (con debounce implicito nel TextField)
            saveBeneDebounced()
        }
        .onChange(of: componenteName) { _ in
            // Salva il componente ad ogni modifica
            saveComponenteDebounced()
        }
        .onChange(of: additionalText) { _ in
            // Salva il testo aggiuntivo ad ogni modifica
            saveAdditionalTextDebounced()
        }
    }
    
    // MARK: - Componente Fields with Autocomplete
    
    private var componenteFieldsWithAutocomplete: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Nome componente con autocompletamento
            VStack(alignment: .leading, spacing: 4) {
                Text("Componente")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    TextField("Es: scheda elettronica, circolatore", text: $componenteName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .focused($isComponenteFocused)
                        .onChange(of: isComponenteFocused) { focused in
                            if focused {
                                showComponenteSuggestions = true
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    showComponenteSuggestions = false
                                }
                            }
                        }
                    
                    // Pulsante X per cancellare
                    if !componenteName.isEmpty {
                        Button {
                            componenteName = ""
                            Task { await saveComponente() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rimuovi componente")
                    }
                    
                    // Dropdown button
                    if !componentiSuggestions.isEmpty {
                        Button {
                            showComponenteSuggestions.toggle()
                            if showComponenteSuggestions {
                                isComponenteFocused = true
                            }
                        } label: {
                            Image(systemName: showComponenteSuggestions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                    }
                    
                    // Indicatore salvato
                    if !componenteName.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }
                
                // Dropdown suggerimenti componenti
                if showComponenteSuggestions && !componentiSuggestions.isEmpty {
                    suggestionsDropdown(
                        suggestions: componentiSuggestions,
                        query: componenteName,
                        onSelect: { selected in
                            componenteName = selected
                            showComponenteSuggestions = false
                            isComponenteFocused = false
                        }
                    )
                }
            }
            
            // Bene di riferimento con autocompletamento
            beneFieldWithAutocomplete(label: "Bene di riferimento")
        }
    }
    
    // MARK: - Additional Text Field with Autocomplete
    
    private var additionalTextFieldWithAutocomplete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(getFieldLabel())
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                TextField("Descrizione", text: $additionalText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .focused($isAdditionalTextFocused)
                
                // Pulsante X per cancellare
                if !additionalText.isEmpty {
                    Button {
                        additionalText = ""
                        Task { await saveAdditionalText() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi descrizione")
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.7))
                }
            }
        }
    }
    
    // MARK: - Bene Riferimento View with Autocomplete
    
    private var beneRiferimentoViewWithAutocomplete: some View {
        beneFieldWithAutocomplete(label: getBeneFieldLabel())
    }
    
    private func beneFieldWithAutocomplete(label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                TextField("Es: caldaia, inverter fotovoltaico", text: $selectedBene)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .focused($isBeneFocused)
                    .onChange(of: isBeneFocused) { focused in
                        if focused {
                            showBeneSuggestions = true
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showBeneSuggestions = false
                            }
                        }
                    }
                
                // Pulsante X per cancellare
                if !selectedBene.isEmpty {
                    Button {
                        selectedBene = ""
                        Task { await saveBene() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi bene")
                }
                
                // Dropdown button
                if !beniSuggestions.isEmpty {
                    Button {
                        showBeneSuggestions.toggle()
                        if showBeneSuggestions {
                            isBeneFocused = true
                        }
                    } label: {
                        Image(systemName: showBeneSuggestions ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                }
                
                // Indicatore salvato
                if !selectedBene.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.7))
                }
            }
            
            // Dropdown suggerimenti beni
            if showBeneSuggestions && !beniSuggestions.isEmpty {
                suggestionsDropdown(
                    suggestions: beniSuggestions,
                    query: selectedBene,
                    onSelect: { selected in
                        selectedBene = selected
                        showBeneSuggestions = false
                        isBeneFocused = false
                    }
                )
            }
        }
    }
    
    // MARK: - Suggestions Dropdown
    
    private func suggestionsDropdown(suggestions: [String], query: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sezione "Usati in questo sinistro"
            let usati = suggestions.filter { suggestion in
                beniUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
            }
            
            if !usati.isEmpty {
                Text("Usati in questo sinistro")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                
                ForEach(usati, id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(suggestion)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Sezione "Altri suggerimenti"
            let altri = suggestions.filter { suggestion in
                !beniUsatiInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
            }
            
            if !altri.isEmpty {
                if !usati.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                }
                
                Text("Suggerimenti")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                
                ForEach(altri, id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: 250)
    }
    
    // MARK: - Field Labels
    
    private func getFieldLabel() -> String {
        switch tag.id {
        case "foto_bene":
            return "Nome del bene"
        default:
            return "Descrizione"
        }
    }
    
    private func getBeneFieldLabel() -> String {
        switch tag.id {
        case "foto_test_funzionale", "test_strumentale":
            return "Bene testato"
        case "foto_ripristino":
            return "Bene ripristinato"
        default:
            return "Bene di riferimento"
        }
    }
    
    // MARK: - Atto Stato View
    
    private var attoStatoView: some View {
        HStack(spacing: 8) {
            Text("Stato:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $attoStato) {
                Text("Da Firmare").tag("da_firmare")
                Text("Firmato").tag("firmato")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: attoStato) { newValue in
                Task { @MainActor in
                    guard !newValue.isEmpty else { return }
                    
                    // Usa applyTag per cambiare stato atto, preservando sottotipo e daAllegare
                    var tagData = FileTagManager.TagApplicationData(tagId: "atto")
                    tagData.attoStato = newValue
                    tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
                    tagData.daAllegareInChiusura = daAllegare
                    
                    await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
                    
                    // Aggiorna concordata se firmato
                    if newValue == "firmato", let sinistro = sinistro {
                        fileTagManager.updateSinistroConcordataIfNeeded(forFile: url.path, sinistro: sinistro)
                    }
                }
            }
        }
    }
    
    // MARK: - Atto Sottotipo View
    
    private var attoSottotipoView: some View {
        HStack(spacing: 8) {
            Text("Tipo:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $attoSottotipo) {
                Text("Non specificato").tag("")
                Text("Liquidazione").tag("liquidazione")
                Text("Accertamento").tag("accertamento")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: attoSottotipo) { newValue in
                Task { @MainActor in
                    // Per tag unificato, trova il tag effettivo
                    let effectiveTagId: String
                    if tag.id == "atto" {
                        let currentTags = await fileTagManager.getTagsForFile(at: url.path)
                        if let attoTag = currentTags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" }) {
                            effectiveTagId = attoTag.id
                        } else {
                            effectiveTagId = "atto_da_firmare" // Default
                        }
                    } else {
                        effectiveTagId = tag.id
                    }
                    await fileTagManager.setAttoSottotipo(newValue.isEmpty ? nil : newValue, forFile: url.path, tagId: effectiveTagId)
                }
            }
        }
    }
    
    // MARK: - Giustificativi Tipo View
    
    private var giustificativiTipoView: some View {
        HStack(spacing: 8) {
            Text("Tipo:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $giustificativiTipo) {
                Text("Fattura").tag("fattura")
                Text("Preventivo").tag("preventivo")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: giustificativiTipo) { newValue in
                Task { @MainActor in
                    guard !newValue.isEmpty else { return }
                    
                    // Usa applyTag per cambiare tipo giustificativo, preservando daAllegare
                    var tagData = FileTagManager.TagApplicationData(tagId: "giustificativi")
                    tagData.giustificativiTipo = newValue
                    tagData.daAllegareInChiusura = daAllegare
                    
                    await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
                }
            }
        }
    }
    
    // MARK: - Fulminazione Sottotipo View
    
    private var fulminazioneSottotipoView: some View {
        HStack(spacing: 8) {
            Text("Esito:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $fulminazioneSottotipo) {
                Text("Non specificato").tag("")
                Text("Positiva").tag("positiva")
                Text("Negativa").tag("negativa")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: fulminazioneSottotipo) { newValue in
                fileTagManager.setFulminazioneSottotipo(newValue.isEmpty ? nil : newValue, forFile: url.path, tagId: tag.id)
                
                // Aggiorna il campo fulminazione del sinistro
                if let sinistro = sinistro {
                    fileTagManager.updateSinistroFulminazioneIfNeeded(forFile: url.path, sinistro: sinistro)
                }
            }
        }
    }
    
    // MARK: - Allegati Atto Sottotipo View
    
    private var allegatiAttoSottotipoView: some View {
        HStack(spacing: 8) {
            Text("Tipo:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $allegatiAttoSottotipo) {
                Text("Non specificato").tag("")
                Text("Accettazione").tag("accettazione")
                Text("IBAN").tag("iban")
                Text("Delega").tag("delega")
                Text("Documenti").tag("documenti")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 250)
            .onChange(of: allegatiAttoSottotipo) { newValue in
                Task { @MainActor in
                    await fileTagManager.setAllegatiAttoSottotipo(newValue.isEmpty ? nil : newValue, forFile: url.path, tagId: tag.id)
                    
                    // Se è IBAN, imposta IBAN=true nel sinistro
                    if newValue == "iban", let sinistro = sinistro {
                        sinistro.iban = true
                        try? sinistro.managedObjectContext?.save()
                    }
                }
            }
        }
    }
    
    // MARK: - Save Actions
    
    private func saveComponente() async {
        // Usa applyTag per salvare con riconciliazione
        var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
        tagData.additionalText = componenteName.isEmpty ? nil : componenteName
        tagData.beneRiferimento = selectedBene.isEmpty ? nil : selectedBene
        
        await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
    }
    
    private func saveComponenteDebounced() {
        componenteDebounceTask?.cancel()
        componenteDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
            guard !Task.isCancelled else { return }
            await saveComponente()
        }
    }
    
    private func saveBene() async {
        // Usa applyTag per salvare con riconciliazione
        var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
        tagData.beneRiferimento = selectedBene.isEmpty ? nil : selectedBene
        tagData.additionalText = tag.id == "foto_componente" ? componenteName : additionalText
        tagData.attoStato = attoStato.isEmpty ? nil : attoStato
        tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
        tagData.giustificativiTipo = giustificativiTipo.isEmpty ? nil : giustificativiTipo
        tagData.fulminazioneSottotipo = fulminazioneSottotipo.isEmpty ? nil : fulminazioneSottotipo
        tagData.ubicazioneTipo = ubicazioneTipo.isEmpty ? nil : ubicazioneTipo
        tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
        
        await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
    }
    
    private func saveBeneDebounced() {
        beneDebounceTask?.cancel()
        beneDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
            guard !Task.isCancelled else { return }
            await saveBene()
        }
    }
    
    private func saveAdditionalText() async {
        // Usa applyTag per salvare con riconciliazione
        var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
        tagData.additionalText = additionalText.isEmpty ? nil : additionalText
        tagData.beneRiferimento = selectedBene.isEmpty ? nil : selectedBene
        tagData.attoStato = attoStato.isEmpty ? nil : attoStato
        tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
        tagData.giustificativiTipo = giustificativiTipo.isEmpty ? nil : giustificativiTipo
        tagData.fulminazioneSottotipo = fulminazioneSottotipo.isEmpty ? nil : fulminazioneSottotipo
        tagData.ubicazioneTipo = ubicazioneTipo.isEmpty ? nil : ubicazioneTipo
        tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
        
        await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
    }
    
    private func saveAdditionalTextDebounced() {
        additionalTextDebounceTask?.cancel()
        additionalTextDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 secondi
            guard !Task.isCancelled else { return }
            await saveAdditionalText()
        }
    }
    
    private func saveAllValues() {
        // Cancella tutti i task di debounce e salva immediatamente
        beneDebounceTask?.cancel()
        componenteDebounceTask?.cancel()
        additionalTextDebounceTask?.cancel()
        
        // Salva usando applyTag (un'unica chiamata con tutti i valori)
        Task { @MainActor in
            if isSelected {
                await saveAdditionalText() // Salva tutti i valori con applyTag
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleTag() {
        let isUnifiedAttoTag = tag.id == "atto"
        let isUnifiedGiustificativiTag = tag.id == "giustificativi"
        let isUnifiedUbicazioneTag = tag.id == "foto_ubicazione"
        
        if isSelected {
            // RIMOZIONE TAG - usa removeCurrentTag per rimuovere tutti i tag
            fileTagManager.removeCurrentTag(fromFile: url.path)
            
            isSelected = false
            attoStato = ""
            giustificativiTipo = ""
            ubicazioneTipo = "rischio"
            ubicazioneAltraDescrizione = ""
            additionalText = ""
            selectedBene = ""
            componenteName = ""
        } else {
            // AGGIUNTA TAG - usa applyTag con TagApplicationData
            var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
            
            // Imposta valori di default per tag unificati
            if isUnifiedAttoTag {
                tagData.attoStato = "da_firmare"
                attoStato = "da_firmare"
            } else if isUnifiedGiustificativiTag {
                tagData.giustificativiTipo = "fattura"
                giustificativiTipo = "fattura"
            } else if isUnifiedUbicazioneTag {
                tagData.ubicazioneTipo = "rischio"
                ubicazioneTipo = "rischio"
            }
            
            // Applica il tag usando il sistema centralizzato
            // La logica di ereditarietà (bene ↔ componente ↔ test) è gestita in applyTag
            Task {
                await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
                
                // Ricarica i valori dopo che applyTag ha fatto l'ereditarietà
                await MainActor.run {
                    loadExistingValues()
                }
            }
            
            isSelected = true
            
            // Se è atto_firmato, aggiorna concordata del sinistro
            if tag.id == "atto_firmato", let sinistro = sinistro {
                fileTagManager.updateSinistroConcordataIfNeeded(forFile: url.path, sinistro: sinistro)
            }
            
            // Se è fulminazione, aggiorna il campo fulminazione del sinistro
            if tag.id == "fulminazione", let sinistro = sinistro {
                fileTagManager.updateSinistroFulminazioneIfNeeded(forFile: url.path, sinistro: sinistro)
            }
        }
    }
    
    private func loadExistingValues() {
        // Per tag unificati, trova il tag effettivo da cui caricare i valori
        let currentTags = fileTagManager.getTagsForFile(at: url.path)
        var effectiveTagId = tag.id
        
        if tag.id == "atto" {
            // Trova quale tag atto è presente
            if currentTags.contains(where: { $0.id == "atto_firmato" }) {
                effectiveTagId = "atto_firmato"
                attoStato = "firmato"
            } else if currentTags.contains(where: { $0.id == "atto_da_firmare" }) {
                effectiveTagId = "atto_da_firmare"
                attoStato = "da_firmare"
            } else {
                attoStato = ""
            }
            attoSottotipo = fileTagManager.getAttoSottotipo(forFile: url.path, tagId: effectiveTagId) ?? ""
        } else if tag.id == "giustificativi" {
            // Trova quale tag giustificativo è presente
            if currentTags.contains(where: { $0.id == "fattura" }) {
                effectiveTagId = "fattura"
                giustificativiTipo = "fattura"
            } else if currentTags.contains(where: { $0.id == "preventivo" }) {
                effectiveTagId = "preventivo"
                giustificativiTipo = "preventivo"
            } else {
                giustificativiTipo = ""
            }
        } else if tag.id == "foto_ubicazione" {
            // Trova quale tag ubicazione è presente
            if currentTags.contains(where: { $0.id == "foto_ubicazione_rischio" }) {
                effectiveTagId = "foto_ubicazione_rischio"
                ubicazioneTipo = "rischio"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_tecnico" }) {
                effectiveTagId = "foto_ubicazione_tecnico"
                ubicazioneTipo = "tecnico"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_amministratore" }) {
                effectiveTagId = "foto_ubicazione_amministratore"
                ubicazioneTipo = "amministratore"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_altra" }) {
                effectiveTagId = "foto_ubicazione_altra"
                ubicazioneTipo = "altra"
                ubicazioneAltraDescrizione = fileTagManager.getAdditionalText(forFile: url.path, tagId: effectiveTagId) ?? ""
            } else {
                ubicazioneTipo = "rischio"
            }
        } else {
            // Per tag normali, carica i valori standard
            attoSottotipo = fileTagManager.getAttoSottotipo(forFile: url.path, tagId: tag.id) ?? ""
            attoStato = fileTagManager.getAttoStato(forFile: url.path, tagId: tag.id) ?? ""
            giustificativiTipo = fileTagManager.getGiustificativiTipo(forFile: url.path, tagId: tag.id) ?? ""
        }
        
        additionalText = fileTagManager.getAdditionalText(forFile: url.path, tagId: effectiveTagId) ?? ""
        selectedBene = fileTagManager.getBeneRiferimento(forFile: url.path, tagId: effectiveTagId) ?? ""
        componenteName = additionalText // Per componente, il nome è nel testo aggiuntivo
        fulminazioneSottotipo = fileTagManager.getFulminazioneSottotipo(forFile: url.path, tagId: tag.id) ?? ""
        allegatiAttoSottotipo = fileTagManager.getAllegatiAttoSottotipo(forFile: url.path, tagId: tag.id) ?? ""
    }
    
    // MARK: - Ubicazione Tipo View
    
    private var ubicazioneTipoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tipo:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $ubicazioneTipo) {
                    Text("Del rischio").tag("rischio")
                    Text("Tecnico riparatore").tag("tecnico")
                    Text("Amministratore").tag("amministratore")
                    Text("Altro").tag("altra")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                .onChange(of: ubicazioneTipo) { newValue in
                    Task { @MainActor in
                        // Usa applyTag per cambiare tipo ubicazione, preservando daAllegare
                        var tagData = FileTagManager.TagApplicationData(tagId: "foto_ubicazione")
                        tagData.ubicazioneTipo = newValue
                        tagData.daAllegareInChiusura = daAllegare
                        
                        // Mantieni la descrizione per "altra"
                        if newValue == "altra" {
                            tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
                        }
                        
                        await fileTagManager.applyTag(tagData, toFile: url.path, sinistroPath: sinistroPath)
                    }
                }
            }
            
            // Campo testo per "Altro"
            if ubicazioneTipo == "altra" {
                HStack(spacing: 6) {
                    TextField("Descrizione ubicazione", text: $ubicazioneAltraDescrizione)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .focused($isUbicazioneAltraFocused)
                        .onChange(of: ubicazioneAltraDescrizione) { newValue in
                            saveUbicazioneAltraDebounced()
                        }
                    
                    if !ubicazioneAltraDescrizione.isEmpty {
                        Button {
                            ubicazioneAltraDescrizione = ""
                            Task {
                                await fileTagManager.setAdditionalText(nil, forFile: url.path, tagId: "foto_ubicazione_altra")
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }
            }
        }
    }
    
    @State private var ubicazioneAltraDebounceTask: Task<Void, Never>?
    
    private func saveUbicazioneAltraDebounced() {
        ubicazioneAltraDebounceTask?.cancel()
        ubicazioneAltraDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await fileTagManager.setAdditionalText(ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione, forFile: url.path, tagId: "foto_ubicazione_altra")
        }
    }
}
