import SwiftUI

// MARK: - Photo Tag Selector View (Redesigned)

private func photoTagIcon(for tag: FileTagManager.FileTag) -> String {
    switch tag.id {
    case "foto_ubicazione", "foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_amministratore", "foto_ubicazione_altra":
        return "location.circle.fill"
    case "foto_bene": return "cube.fill"
    case "foto_componente": return "gearshape.fill"
    case "foto_ripristino": return "wrench.and.screwdriver.fill"
    case "foto_test_funzionale": return "checkmark.seal.fill"
    case "test_strumentale": return "waveform.path.ecg"
    default: return "tag.fill"
    }
}

struct PhotoTagSelectorView: View {
    let filePath: String
    let sinistro: Sinistro
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var isEditingTextField: Bool
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    
    @State private var beniSuggestions: [String] = []
    @State private var beniUsatiInSinistro: [String] = []
    @State private var componentiSuggestions: [String] = []
    @State private var componentiUsatiInSinistro: [String] = []
    
    private var photoTags: [FileTagManager.FileTag] {
        FileTagManager.FileTag.unifiedTagsForUI().filter { $0.category == .foto }
    }
    
    private var appliedTags: Set<FileTagManager.FileTag> {
        fileTagManager.getTagsForFile(at: filePath)
    }
    
    private func loadSuggestions() {
        Task { @MainActor in
            if let path = sinistroPath {
                beniUsatiInSinistro = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
                componentiUsatiInSinistro = await commonItemsManager.getComponentiUsedInSinistro(sinistroPath: path)
            }
        }
    }
    
    private func isTagApplied(_ tag: FileTagManager.FileTag) -> Bool {
        // Per tag unificati, controlla se uno dei tag individuali è presente
        if tag.id == "foto_ubicazione" {
            return appliedTags.contains(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) })
        }
        return appliedTags.contains(tag)
    }
    
    private func hasAdditionalFields(_ tag: FileTagManager.FileTag) -> Bool {
        tag.requiresAdditionalText || FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id)
    }
    
    private var sinistroPath: String? {
        FileService.shared.getSinistroPath(riferimento: sinistro.riferimento ?? "")
    }
    
    private func handleTagSelection(_ tag: FileTagManager.FileTag) {
        let isUbicazioneTag = tag.id == "foto_ubicazione"
        
        Task { @MainActor in
            if isTagApplied(tag) {
                // RIMOZIONE - usa removeCurrentTag per rimuovere tutti i tag
                fileTagManager.removeCurrentTag(fromFile: filePath)
            } else {
                // AGGIUNTA - usa applyTag con TagApplicationData
                // La logica di ereditarietà (bene ↔ componente ↔ test) è gestita in applyTag
                var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
                
                // Per tag ubicazione unificato, imposta il default
                if isUbicazioneTag {
                    tagData.ubicazioneTipo = "rischio"
                }
                
                await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Classifica foto")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Quick count
                let appliedCount = photoTags.filter { isTagApplied($0) }.count
                if appliedCount > 0 {
                    Text("\(appliedCount) tag")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 16)
            
            // Tag con campi sempre visibili sotto
            VStack(spacing: 10) {
                ForEach(photoTags, id: \.id) { tag in
                    VStack(spacing: 0) {
                        // Tag button
                        PhotoTagButton(
                            tag: tag,
                            icon: photoTagIcon(for: tag),
                            isApplied: isTagApplied(tag),
                            hasFields: hasAdditionalFields(tag),
                            additionalText: fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id),
                            beneRiferimento: fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id),
                            action: { handleTagSelection(tag) }
                        )
                        
                        // Campi aggiuntivi sempre visibili sotto il tag se applicato
                        if isTagApplied(tag) && hasAdditionalFields(tag) {
                            PhotoTagAdditionalFieldsView(
                                tag: tag,
                                filePath: filePath,
                                sinistroPath: sinistroPath,
                                fileTagManager: fileTagManager,
                                commonItemsManager: commonItemsManager,
                                isEditingTextField: $isEditingTextField
                            )
                            .id("\(filePath)_\(tag.id)")  // Forza ricreazione quando cambia file
                            .padding(.top, 8)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Photo Quick Tag Panel (MediaViewer + Sheet)

struct PhotoQuickTagPanelView: View {
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var isEditingTextField: Bool
    
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    @State private var includeInClosure: Bool = true
    
    private var photoTags: [FileTagManager.FileTag] {
        FileTagManager.FileTag.unifiedTagsForUI().filter { $0.category == .foto }
    }
    
    private var appliedTags: Set<FileTagManager.FileTag> {
        fileTagManager.getTagsForFile(at: filePath)
    }
    
    private var appliedPhotoTags: [FileTagManager.FileTag] {
        photoTags.filter { isTagApplied($0) }
    }
    
    private func isTagApplied(_ tag: FileTagManager.FileTag) -> Bool {
        if tag.id == "foto_ubicazione" {
            return appliedTags.contains(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) })
        }
        return appliedTags.contains(tag)
    }
    
    private var hasAdditionalFields: (FileTagManager.FileTag) -> Bool {
        { tag in tag.requiresAdditionalText || FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) || tag.id == "foto_ubicazione" }
    }
    
    private var isAnyPhotoTagPinned: Bool {
        // Controlla i tag effettivi, non quelli unificati
        appliedTags.filter { $0.category == .foto }.contains { fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: $0.id) }
    }
    
    private func syncIncludeInClosureFromTags() {
        // Se non ci sono tag foto applicati, lasciamo lo stato corrente (di default true)
        guard !appliedPhotoTags.isEmpty else { return }
        includeInClosure = isAnyPhotoTagPinned
    }
    
    private func setPinnedForAllPhotoTags(_ pinned: Bool) {
        // Imposta sui tag effettivi applicati
        for tag in appliedTags.filter({ $0.category == .foto }) {
            fileTagManager.setDaAllegareInChiusura(pinned, forFile: filePath, tagId: tag.id)
        }
    }
    
    private func setPinnedForTag(_ tag: FileTagManager.FileTag, pinned: Bool) {
        if tag.id == "foto_ubicazione" {
            // Per tag ubicazione, trova il tag effettivo
            if let ubicazioneTag = appliedTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                fileTagManager.setDaAllegareInChiusura(pinned, forFile: filePath, tagId: ubicazioneTag.id)
            }
        } else {
            fileTagManager.setDaAllegareInChiusura(pinned, forFile: filePath, tagId: tag.id)
        }
    }
    
    /// Ottiene il testo aggiuntivo per un tag (gestisce tag unificati)
    private func getEffectiveAdditionalText(for tag: FileTagManager.FileTag) -> String? {
        if tag.id == "foto_ubicazione" {
            // Trova il tag ubicazione effettivo e restituisci il suo testo
            if let ubicazioneTag = appliedTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                if ubicazioneTag.id == "foto_ubicazione_altra" {
                    return fileTagManager.getAdditionalText(forFile: filePath, tagId: ubicazioneTag.id)
                }
                // Restituisci il nome del sottotipo
                switch ubicazioneTag.id {
                case "foto_ubicazione_rischio": return "Del rischio"
                case "foto_ubicazione_tecnico": return "Tecnico riparatore"
                case "foto_ubicazione_amministratore": return "Amministratore"
                default: return nil
                }
            }
        }
        return fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id)
    }
    
    /// Ottiene il bene di riferimento per un tag (gestisce tag unificati)
    private func getEffectiveBeneRiferimento(for tag: FileTagManager.FileTag) -> String? {
        if tag.id == "foto_ubicazione" {
            if let ubicazioneTag = appliedTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                return fileTagManager.getBeneRiferimento(forFile: filePath, tagId: ubicazioneTag.id)
            }
        }
        return fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id)
    }
    
    private func handleTagSelection(_ tag: FileTagManager.FileTag) {
        let isUbicazioneTag = tag.id == "foto_ubicazione"
        
        if isTagApplied(tag) {
            // RIMOZIONE - usa removeCurrentTag per coerenza con il nuovo sistema
            fileTagManager.removeCurrentTag(fromFile: filePath)
            syncIncludeInClosureFromTags()
            return
        }
        
        // AGGIUNTA - usa applyTag con TagApplicationData
        // La logica di mutua esclusione e ereditarietà dati è gestita in applyTag
        var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
        tagData.daAllegareInChiusura = includeInClosure
        
        // Per tag ubicazione unificato, imposta il default
        if isUbicazioneTag {
            tagData.ubicazioneTipo = "rischio"
        }
        
        Task { @MainActor in
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
            syncIncludeInClosureFromTags()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Classifica foto")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle(isOn: $includeInClosure) {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                        Text("Allega")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onChange(of: includeInClosure) { newValue in
                    Task { @MainActor in
                        setPinnedForAllPhotoTags(newValue)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            VStack(spacing: 10) {
                ForEach(photoTags, id: \.id) { tag in
                    VStack(spacing: 0) {
                        PhotoTagButton(
                            tag: tag,
                            icon: photoTagIcon(for: tag),
                            isApplied: isTagApplied(tag),
                            hasFields: hasAdditionalFields(tag),
                            additionalText: getEffectiveAdditionalText(for: tag),
                            beneRiferimento: getEffectiveBeneRiferimento(for: tag),
                            action: { handleTagSelection(tag) }
                        )
                        
                        if isTagApplied(tag) && hasAdditionalFields(tag) {
                            if tag.id == "foto_ubicazione" {
                                // Per tag ubicazione, mostra il picker sottotipo
                                UbicazioneSubtypePickerView(
                                    filePath: filePath,
                                    fileTagManager: fileTagManager,
                                    includeInClosure: includeInClosure
                                )
                                .padding(.top, 8)
                            } else {
                                PhotoTagAdditionalFieldsView(
                                    tag: tag,
                                    filePath: filePath,
                                    sinistroPath: sinistroPath,
                                    fileTagManager: fileTagManager,
                                    commonItemsManager: commonItemsManager,
                                    isEditingTextField: $isEditingTextField
                                )
                                .id("\(filePath)_quick_\(tag.id)")
                                .padding(.top, 8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            syncIncludeInClosureFromTags()
        }
        .onChange(of: filePath) { _ in
            syncIncludeInClosureFromTags()
        }
        .onChange(of: isAnyPhotoTagPinned) { _ in
            syncIncludeInClosureFromTags()
        }
        // RIMOSSO: onReceive(objectWillChange) causava loop infinito
        // Il binding @ObservedObject già gestisce gli aggiornamenti necessari
    }
}

// MARK: - Photo Tag Button

struct PhotoTagButton: View {
    let tag: FileTagManager.FileTag
    let icon: String
    let isApplied: Bool
    let hasFields: Bool
    let additionalText: String?
    let beneRiferimento: String?
    let action: () -> Void
    
    @State private var isHovered = false
    
    /// Mostra sia bene che componente se presenti
    private var displaySubtexts: [String] {
        var texts: [String] = []
        if let bene = beneRiferimento, !bene.isEmpty {
            texts.append("🏷 \(bene)")
        }
        if let text = additionalText, !text.isEmpty {
            // Per foto_bene, additionalText è il bene stesso
            if tag.id == "foto_bene" {
                texts.append("🏷 \(text)")
            } else {
                // Per foto_componente o altri, è il componente/descrizione
                texts.append("⚙️ \(text)")
            }
        }
        return texts
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isApplied ? Color.white.opacity(0.2) : tag.tagColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isApplied ? .white : tag.tagColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // Nome tag
                    Text(tag.name)
                        .font(.system(size: 12, weight: isApplied ? .semibold : .medium))
                        .foregroundColor(isApplied ? .white : .primary)
                        .lineLimit(1)
                    
                    // Sottotesti con bene e componente
                    if isApplied && !displaySubtexts.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(displaySubtexts, id: \.self) { subtext in
                                Text(subtext)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                // Checkmark quando applicato
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isApplied ? tag.tagColor : (isHovered ? tag.tagColor.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tag.tagColor.opacity(isApplied ? 0 : (isHovered ? 0.4 : 0.2)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Photo Tag Additional Fields View

struct PhotoTagAdditionalFieldsView: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @ObservedObject var commonItemsManager: CommonItemsManager
    @Binding var isEditingTextField: Bool
    
    @State private var additionalText: String = ""
    @State private var beneRiferimento: String = ""
    @State private var showSuggestions = false
    @State private var showBeneRiferimentoSuggestions = false
    @State private var isLoadingValues = false
    @FocusState private var isAdditionalTextFocused: Bool
    @FocusState private var isBeneRiferimentoFocused: Bool
    
    private var isBeneTag: Bool { tag.id == "foto_bene" }
    private var isComponenteTag: Bool { tag.id == "foto_componente" }
    private var isRipristinoTag: Bool { tag.id == "foto_ripristino" }
    private var isTestFunzionaleTag: Bool { tag.id == "foto_test_funzionale" }
    private var isTestStrumentaleTag: Bool { tag.id == "test_strumentale" }
    private var needsBeneRiferimento: Bool { FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) }
    private var hasSuggestions: Bool { isBeneTag || isComponenteTag }
    private var onlyNeedsBene: Bool { (isTestFunzionaleTag || isTestStrumentaleTag) && !tag.requiresAdditionalText }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Campo principale
            if tag.requiresAdditionalText {
                ModernAutocompleteField(
                    icon: getFieldIcon(),
                    label: getFieldLabel(),
                    placeholder: getPlaceholder(),
                    text: $additionalText,
                    suggestions: hasSuggestions ? suggestions : [],
                    usedInSinistro: hasSuggestions ? usedItems : [],
                    showSuggestions: $showSuggestions,
                    isEditing: $isEditingTextField,
                    isFocused: _isAdditionalTextFocused,
                    accentColor: tag.tagColor,
                    onSave: saveAdditionalText,
                    onClear: { clearAdditionalText() }
                )
            }
            
            // Campo bene di riferimento
            if needsBeneRiferimento {
                ModernAutocompleteField(
                    icon: "cube",
                    label: onlyNeedsBene ? "Bene testato" : "Bene di riferimento",
                    placeholder: "es. Lavatrice",
                    text: $beneRiferimento,
                    suggestions: beniSuggestions,
                    usedInSinistro: beniUsatiInSinistro,
                    showSuggestions: $showBeneRiferimentoSuggestions,
                    isEditing: $isEditingTextField,
                    isFocused: _isBeneRiferimentoFocused,
                    accentColor: tag.tagColor,
                    onSave: saveBeneRiferimento,
                    onClear: { clearBeneRiferimento() }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tag.tagColor.opacity(0.3), lineWidth: 1)
        )
        .task {
            await loadTags()
            loadSuggestions()
            loadExistingValues()
        }
        .onChange(of: additionalText) { _ in
            // Carica suggerimenti solo se non è un reload automatico
            if hasSuggestions && !isLoadingValues {
                loadSuggestions()
            }
        }
        .onChange(of: filePath) { newPath in
            // Non ricaricare se utente sta editando - aspetta che finisca
            guard !isEditingTextField else { return }
            DispatchQueue.main.async {
                loadExistingValues()
            }
        }
        .onChange(of: tag.id) { _ in
            // Non ricaricare se utente sta editando
            guard !isEditingTextField else { return }
            DispatchQueue.main.async {
                loadExistingValues()
            }
        }
        .onDisappear {
            saveAllValues()
        }
    }
    
    private func getFieldIcon() -> String {
        switch tag.id {
        case "foto_bene": return "cube"
        case "foto_componente": return "gearshape"
        case "foto_ripristino": return "wrench.and.screwdriver"
        default: return "text.alignleft"
        }
    }
    
    private func getFieldLabel() -> String {
        switch tag.id {
        case "foto_bene": return "Nome del bene"
        case "foto_componente": return "Nome del componente"
        case "foto_ripristino": return "Descrizione ripristino"
        default: return "Descrizione"
        }
    }
    
    private func getPlaceholder() -> String {
        switch tag.id {
        case "foto_bene": return "es. Lavatrice, Frigorifero..."
        case "foto_componente": return "es. Scheda di controllo, Inverter..."
        case "foto_ripristino": return "es. Sostituzione componente..."
        default: return "Inserisci descrizione..."
        }
    }
    
    @State private var suggestions: [String] = []
    @State private var usedItems: [String] = []
    @State private var beniSuggestions: [String] = []
    @State private var beniUsatiInSinistro: [String] = []
    @State private var appliedTags: Set<FileTagManager.FileTag> = []
    @State private var saveDebounceTask: Task<Void, Never>?
    @State private var lastSavedAdditional: String = ""
    @State private var lastSavedBene: String = ""
    
    private func loadTags() async {
        appliedTags = await fileTagManager.getTagsForFile(at: filePath)
    }
    
    private func loadSuggestions() {
        Task { @MainActor in
            // Carica sempre i suggerimenti beni per il campo bene di riferimento
            if let path = sinistroPath {
                beniSuggestions = await commonItemsManager.getBeniSuggestions(for: beneRiferimento, sinistroPath: path)
                beniUsatiInSinistro = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
            }
            
            if isBeneTag {
                suggestions = await commonItemsManager.getBeniSuggestions(for: additionalText, sinistroPath: sinistroPath)
                if let path = sinistroPath {
                    usedItems = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
                }
            } else if isComponenteTag {
                suggestions = await commonItemsManager.getComponentiSuggestions(for: additionalText, sinistroPath: sinistroPath)
                if let path = sinistroPath {
                    usedItems = await commonItemsManager.getComponentiUsedInSinistro(sinistroPath: path)
                }
            }
        }
    }
    
    private func loadExistingValues() {
        Task { @MainActor in
            isLoadingValues = true
            let loadedAdditional = await fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id) ?? ""
            let loadedBene = await fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id) ?? ""
            
            additionalText = loadedAdditional
            beneRiferimento = loadedBene
            
            // Sincronizza i valori "last saved" per evitare salvataggi inutili
            lastSavedAdditional = loadedAdditional.trimmingCharacters(in: .whitespacesAndNewlines)
            lastSavedBene = loadedBene.trimmingCharacters(in: .whitespacesAndNewlines)
            
            isLoadingValues = false
        }
    }
    
    private func saveAdditionalText() {
        let trimmed = additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAllValuesWithApplyTag()
        
        // Aggiungi ai custom items per autocompletamento futuro
        if !trimmed.isEmpty {
            if isBeneTag {
                commonItemsManager.addCustomBene(trimmed)
            } else if isComponenteTag {
                commonItemsManager.addCustomComponente(trimmed)
            }
        }
    }
    
    private func saveBeneRiferimento() {
        let trimmed = beneRiferimento.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAllValuesWithApplyTag()
        
        if !trimmed.isEmpty {
            commonItemsManager.addCustomBene(trimmed)
        }
    }
    
    private func clearAdditionalText() {
        additionalText = ""
        saveAllValuesWithApplyTag()
    }
    
    private func clearBeneRiferimento() {
        beneRiferimento = ""
        saveAllValuesWithApplyTag()
    }
    
    private func saveAllValues() {
        saveAllValuesWithApplyTag()
    }
    
    /// Salva tutti i valori usando applyTag per riconciliazione centralizzata
    /// Usa debounce per evitare salvataggi troppo frequenti
    private func saveAllValuesWithApplyTag() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms debounce
            guard !Task.isCancelled else { return }
            
            let trimmedAdditional = additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBene = beneRiferimento.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Evita salvataggi ridondanti se i valori non sono cambiati
            guard trimmedAdditional != lastSavedAdditional || trimmedBene != lastSavedBene else {
                return
            }
            
            var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
            tagData.additionalText = trimmedAdditional.isEmpty ? nil : trimmedAdditional
            tagData.beneRiferimento = trimmedBene.isEmpty ? nil : trimmedBene
            
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
            
            // Aggiorna i valori salvati per evitare loop
            lastSavedAdditional = trimmedAdditional
            lastSavedBene = trimmedBene
        }
    }
}

// MARK: - Modern Autocomplete Field

struct ModernAutocompleteField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    let usedInSinistro: [String]
    @Binding var showSuggestions: Bool
    @Binding var isEditing: Bool
    @FocusState var isFocused: Bool
    let accentColor: Color
    let onSave: () -> Void
    var onClear: (() -> Void)? = nil
    
    @State private var debounceTask: Task<Void, Never>?
    
    private var hasSuggestions: Bool { !suggestions.isEmpty }
    
    private var filteredSuggestions: [String] {
        if text.isEmpty {
            return Array(suggestions.prefix(6))
        }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(6).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label con icona
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Campo input
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onChange(of: isFocused) { focused in
                        isEditing = focused
                        if focused && hasSuggestions {
                            showSuggestions = true
                        } else if !focused {
                            // Quando perde focus, salva e nascondi suggerimenti
                            debounceTask?.cancel()
                            onSave()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                            }
                        }
                    }
                    // NON salvare su ogni keypress - salva solo al blur o dopo debounce lungo
                    .onSubmit {
                        debounceTask?.cancel()
                        onSave()
                    }
                
                // Clear button
                if !text.isEmpty {
                    Button {
                        text = ""
                        debounceTask?.cancel()
                        onSave()
                        onClear?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                
                // Saved indicator
                if !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? accentColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            
            // Suggestions dropdown
            if showSuggestions && !filteredSuggestions.isEmpty {
                ModernSuggestionsList(
                    suggestions: filteredSuggestions,
                    usedInSinistro: usedInSinistro,
                    accentColor: accentColor,
                    onSelect: { selected in
                        text = selected
                        showSuggestions = false
                        isFocused = false
                        debounceTask?.cancel()
                        onSave()
                    }
                )
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            onSave()
        }
    }
    
    private func saveDebounced() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onSave()
            }
        }
    }
}

// MARK: - Modern Suggestions List

struct ModernSuggestionsList: View {
    let suggestions: [String]
    let usedInSinistro: [String]
    let accentColor: Color
    let onSelect: (String) -> Void
    
    private var usedFiltered: [String] {
        suggestions.filter { suggestion in
            usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }
    
    private var othersFiltered: [String] {
        suggestions.filter { suggestion in
            !usedInSinistro.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Usati nel sinistro
            if !usedFiltered.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text("Recenti")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                ForEach(usedFiltered, id: \.self) { suggestion in
                    SuggestionItem(
                        text: suggestion,
                        isUsed: true,
                        accentColor: accentColor
                    ) {
                        onSelect(suggestion)
                    }
                }
                
                if !othersFiltered.isEmpty {
                    Divider()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                }
            }
            
            // Altri suggerimenti
            if !othersFiltered.isEmpty {
                ForEach(othersFiltered, id: \.self) { suggestion in
                    SuggestionItem(
                        text: suggestion,
                        isUsed: false,
                        accentColor: accentColor
                    ) {
                        onSelect(suggestion)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

struct SuggestionItem: View {
    let text: String
    let isUsed: Bool
    let accentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isUsed {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Ubicazione Subtype Picker View

struct UbicazioneSubtypePickerView: View {
    let filePath: String
    @ObservedObject var fileTagManager: FileTagManager
    let includeInClosure: Bool
    
    @State private var ubicazioneTipo: String = "rischio"
    @State private var ubicazioneAltraDescrizione: String = ""
    @FocusState private var isAltraFocused: Bool
    @State private var debounceTask: Task<Void, Never>?
    
    private var appliedTags: Set<FileTagManager.FileTag> {
        fileTagManager.getTagsForFile(at: filePath)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Picker tipo ubicazione
            HStack(spacing: 8) {
                Text("Tipo:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $ubicazioneTipo) {
                    Text("Del rischio").tag("rischio")
                    Text("Tecnico riparatore").tag("tecnico")
                    Text("Amministratore").tag("amministratore")
                    Text("Altro").tag("altra")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .onChange(of: ubicazioneTipo) { newValue in
                    handleUbicazioneChange(newValue)
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
                        .focused($isAltraFocused)
                        .onChange(of: ubicazioneAltraDescrizione) { _ in
                            saveAltraDebounced()
                        }
                    
                    if !ubicazioneAltraDescrizione.isEmpty {
                        Button {
                            ubicazioneAltraDescrizione = ""
                            Task {
                                await fileTagManager.setAdditionalText(nil, forFile: filePath, tagId: "foto_ubicazione_altra")
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            loadCurrentUbicazione()
        }
        .onChange(of: filePath) { _ in
            loadCurrentUbicazione()
        }
    }
    
    private func loadCurrentUbicazione() {
        Task { @MainActor in
            let tags = await fileTagManager.getTagsForFile(at: filePath)
            
            if tags.contains(where: { $0.id == "foto_ubicazione_rischio" }) {
                ubicazioneTipo = "rischio"
            } else if tags.contains(where: { $0.id == "foto_ubicazione_tecnico" }) {
                ubicazioneTipo = "tecnico"
            } else if tags.contains(where: { $0.id == "foto_ubicazione_amministratore" }) {
                ubicazioneTipo = "amministratore"
            } else if tags.contains(where: { $0.id == "foto_ubicazione_altra" }) {
                ubicazioneTipo = "altra"
                ubicazioneAltraDescrizione = await fileTagManager.getAdditionalText(forFile: filePath, tagId: "foto_ubicazione_altra") ?? ""
            } else {
                ubicazioneTipo = "rischio"
            }
        }
    }
    
    private func handleUbicazioneChange(_ newValue: String) {
        Task { @MainActor in
            // Ottieni daAllegare dal tag corrente per preservarlo
            let currentTags = await fileTagManager.getTagsForFile(at: filePath)
            var daAllegareDaTrasferire: Bool = includeInClosure
            
            if let currentTag = currentTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                daAllegareDaTrasferire = await fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: currentTag.id)
            }
            
            // Usa applyTag con il nuovo tipo di ubicazione
            var tagData = FileTagManager.TagApplicationData(tagId: "foto_ubicazione")
            tagData.ubicazioneTipo = newValue
            tagData.daAllegareInChiusura = daAllegareDaTrasferire
            
            // Per "altra", trasferisci la descrizione se già presente
            if newValue == "altra" {
                tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
            }
            
            // sinistroPath non disponibile in questa view - usa nil
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: nil)
        }
    }
    
    private func saveAltraDebounced() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            // Usa applyTag per salvare con il nuovo sistema
            var tagData = FileTagManager.TagApplicationData(tagId: "foto_ubicazione")
            tagData.ubicazioneTipo = "altra"
            tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
            tagData.daAllegareInChiusura = includeInClosure
            
            // sinistroPath non disponibile in questa view - usa nil
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: nil)
        }
    }
}
