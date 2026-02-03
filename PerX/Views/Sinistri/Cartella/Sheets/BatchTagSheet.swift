import SwiftUI

// MARK: - Batch Tag Mode

enum BatchTagApplicationMode {
    case fullTag           // Sostituisce completamente il tag
    case partialUpdate     // Aggiorna solo alcuni campi mantenendo il tag esistente
}

// MARK: - Batch Tag Sheet

struct BatchTagSheet: View {
    let files: [URL]
    let mode: BatchTagMode
    let sinistro: Sinistro
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    
    // Stato per modalità applicazione
    @State private var applicationMode: BatchTagApplicationMode = .fullTag
    
    // Stato per tag completo
    @State private var selectedTag: FileTagManager.FileTag?
    @State private var additionalText: String = ""
    @State private var beneRiferimento: String = ""
    
    // Stato per update parziale - modalità (tutti vs per gruppo)
    @State private var beneUpdateMode: GroupUpdateMode = .all
    @State private var componenteUpdateMode: GroupUpdateMode = .all
    
    // Valori per "Tutti"
    @State private var partialBeneAll: String = ""
    @State private var partialComponenteAll: String = ""
    
    // Valori per gruppo (chiave = valore esistente, valore = nuovo valore)
    @State private var partialBenePerGroup: [String: String] = [:]
    @State private var partialComponentePerGroup: [String: String] = [:]
    
    // Gruppi trovati nei file selezionati
    @State private var existingBeniGroups: [String] = []  // Beni unici trovati
    @State private var existingComponentiGroups: [String] = []  // Componenti unici trovati
    @State private var filesWithoutBene: Int = 0
    @State private var filesWithoutComponente: Int = 0
    
    // Da allegare
    @State private var updateDaAllegare: Bool = false
    @State private var partialDaAllegare: Bool = true
    
    enum GroupUpdateMode: String, CaseIterable {
        case all = "Tutti"
        case perGroup = "Per gruppo"
    }
    
    // Stato UI
    @State private var isApplying = false
    @State private var appliedCount = 0
    @State private var usedBeni: [String] = []
    @State private var suggestions: [String] = []
    @State private var beniSuggestions: [String] = []
    @State private var componentiSuggestions: [String] = []
    @State private var showSuggestions = false
    @State private var showBeneRiferimentoSuggestions = false
    @State private var showPartialBeneSuggestions = false
    @State private var showPartialComponenteSuggestions = false
    @State private var isEditingTextField = false
    @State private var selectedCategory: TagCategoryFilter = .all
    @FocusState private var isAdditionalTextFocused: Bool
    @FocusState private var isBeneRiferimentoFocused: Bool
    @FocusState private var focusedBeneField: String?  // nil = tutti, altrimenti nome gruppo
    @FocusState private var focusedComponenteField: String?
    
    // Sottotipi per tag specifici
    @State private var attoStato: String = "da_firmare"
    @State private var attoSottotipo: String = "accertamento"
    @State private var giustificativiTipo: String = "fattura"
    @State private var fulminazioneSottotipo: String = "positiva"
    @State private var ubicazioneTipo: String = "rischio"
    @State private var ubicazioneAltra: String = ""
    
    private var sinistroPath: String? {
        FileService.shared.getSinistroPath(riferimento: sinistro.riferimento ?? "")
    }
    
    // MARK: - Filtri categoria tag
    
    enum TagCategoryFilter: String, CaseIterable {
        case all = "Tutti"
        case documenti = "Documenti"
        case foto = "Foto"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .documenti: return "doc.text"
            case .foto: return "camera"
            }
        }
    }
    
    // MARK: - Tag disponibili
    
    private var availableTags: [FileTagManager.FileTag] {
        let unified = FileTagManager.FileTag.unifiedTagsForUI()
        
        switch selectedCategory {
        case .all:
            return unified
        case .documenti:
            return unified.filter { $0.category == nil }
        case .foto:
            return unified.filter { $0.category == .foto }
        }
    }
    
    // MARK: - File filtrati
    
    /// Estensioni per immagini e PDF (per tag foto)
    private let photoExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "pdf"]
    private let pureImageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
    
    /// File immagine + PDF (per tag foto - a volte le foto vengono inviate come PDF)
    private var photoFiles: [URL] {
        return files.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            return isFile && photoExtensions.contains(url.pathExtension.lowercased())
        }
    }
    
    /// Solo immagini pure (per statistiche header)
    private var imageFiles: [URL] {
        return files.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            return isFile && pureImageExtensions.contains(url.pathExtension.lowercased())
        }
    }
    
    /// Solo PDF (per statistiche header)
    private var pdfFiles: [URL] {
        return files.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            return isFile && url.pathExtension.lowercased() == "pdf"
        }
    }
    
    private var nonPhotoFiles: [URL] {
        return files.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            return isFile && !photoExtensions.contains(url.pathExtension.lowercased())
        }
    }
    
    private var targetFiles: [URL] {
        guard let tag = selectedTag else { return files }
        
        // Se è un tag foto, applica a immagini + PDF
        if tag.category == .foto || FileTagManager.FileTag.photoTags.contains(tag.id) || tag.id == "foto_ubicazione" {
            return photoFiles
        }
        
        // Per altri tag, applica a tutti i file (non cartelle)
        return files.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
        }
    }
    
    // MARK: - Proprietà tag selezionato
    
    private var isBeneTag: Bool {
        selectedTag?.id == "foto_bene"
    }
    
    private var isComponenteTag: Bool {
        selectedTag?.id == "foto_componente"
    }
    
    private var isAttoTag: Bool {
        selectedTag?.id == "atto"
    }
    
    private var isGiustificativiTag: Bool {
        selectedTag?.id == "giustificativi"
    }
    
    private var isFulminazioneTag: Bool {
        selectedTag?.id == "fulminazione"
    }
    
    private var isUbicazioneTag: Bool {
        selectedTag?.id == "foto_ubicazione"
    }
    
    private var hasSuggestions: Bool {
        isBeneTag || isComponenteTag
    }
    
    private var needsAdditionalText: Bool {
        selectedTag?.requiresAdditionalText ?? false
    }
    
    private var needsBeneRiferimento: Bool {
        guard let tag = selectedTag else { return false }
        return FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            // Tab per modalità (solo se ci sono foto/PDF)
            if !photoFiles.isEmpty {
                applicationModeSelector
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if applicationMode == .fullTag {
                        fullTagModeContent
                    } else {
                        partialUpdateModeContent
                    }
                }
                .padding()
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 500, height: 600)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .folderContents ? "Applica Tag al contenuto" : "Applica Tag")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    if !imageFiles.isEmpty {
                        Label("\(imageFiles.count) immagini", systemImage: "photo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !pdfFiles.isEmpty {
                        Label("\(pdfFiles.count) PDF", systemImage: "doc.richtext")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !nonPhotoFiles.isEmpty {
                        Label("\(nonPhotoFiles.count) altri", systemImage: "doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Selettore modalità applicazione
    
    private var applicationModeSelector: some View {
        HStack(spacing: 0) {
            ForEach([BatchTagApplicationMode.fullTag, .partialUpdate], id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        applicationMode = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode == .fullTag ? "tag.fill" : "pencil.and.outline")
                            .font(.system(size: 16))
                        Text(mode == .fullTag ? "Tag Completo" : "Aggiorna Campi")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(applicationMode == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundColor(applicationMode == mode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Contenuto modalità Tag Completo
    
    private var fullTagModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filtro categoria
            categoryFilterView
            
            // Selezione tag
            Text("Seleziona Tag")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                ForEach(availableTags, id: \.id) { tag in
                    tagButton(tag)
                }
            }
            
            // Campi aggiuntivi per tag selezionato
            if let tag = selectedTag {
                Divider()
                    .padding(.vertical, 8)
                
                additionalFieldsForTag(tag)
            }
        }
        .onChange(of: selectedTag?.id) { _ in
            // Reset campi quando cambia tag
            additionalText = ""
            beneRiferimento = ""
            suggestions = []
        }
        .onChange(of: isAdditionalTextFocused) { focused in
            if focused && hasSuggestions {
                Task { await loadSuggestions() }
            }
        }
        .onChange(of: isBeneRiferimentoFocused) { focused in
            if focused && needsBeneRiferimento {
                Task { await loadBeniSuggestions() }
            }
        }
    }
    
    // MARK: - Filtro categoria
    
    private var categoryFilterView: some View {
        HStack(spacing: 8) {
            ForEach(TagCategoryFilter.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                    selectedTag = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(.system(size: 11))
                        Text(category.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedCategory == category ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(selectedCategory == category ? .white : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
    
    // MARK: - Bottone tag
    
    private func tagButton(_ tag: FileTagManager.FileTag) -> some View {
        Button {
            selectedTag = tag
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tag.tagColor)
                    .frame(width: 10, height: 10)
                Text(tag.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedTag?.id == tag.id ? tag.tagColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedTag?.id == tag.id ? tag.tagColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Campi aggiuntivi per tag
    
    @ViewBuilder
    private func additionalFieldsForTag(_ tag: FileTagManager.FileTag) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag Atto - stato e sottotipo
            if isAttoTag {
                attoFieldsView
            }
            
            // Tag Giustificativi - tipo
            if isGiustificativiTag {
                giustificativiFieldsView
            }
            
            // Tag Fulminazione - sottotipo
            if isFulminazioneTag {
                fulminazioneFieldsView
            }
            
            // Tag Ubicazione - tipo
            if isUbicazioneTag {
                ubicazioneFieldsView
            }
            
            // Campo additionalText
            if needsAdditionalText {
                ModernAutocompleteField(
                    icon: getFieldIcon(for: tag),
                    label: getFieldLabel(for: tag),
                    placeholder: getPlaceholder(for: tag),
                    text: $additionalText,
                    suggestions: hasSuggestions ? suggestions : [],
                    usedInSinistro: hasSuggestions ? usedBeni : [],
                    showSuggestions: $showSuggestions,
                    isEditing: $isEditingTextField,
                    isFocused: _isAdditionalTextFocused,
                    accentColor: tag.tagColor,
                    onSave: {},
                    onClear: { additionalText = "" }
                )
            }
            
            // Campo bene di riferimento
            if needsBeneRiferimento {
                ModernAutocompleteField(
                    icon: "cube",
                    label: "Bene di riferimento",
                    placeholder: "es. Lavatrice",
                    text: $beneRiferimento,
                    suggestions: beniSuggestions,
                    usedInSinistro: usedBeni,
                    showSuggestions: $showBeneRiferimentoSuggestions,
                    isEditing: $isEditingTextField,
                    isFocused: _isBeneRiferimentoFocused,
                    accentColor: tag.tagColor,
                    onSave: {},
                    onClear: { beneRiferimento = "" }
                )
            }
        }
    }
    
    // MARK: - Campi Atto
    
    private var attoFieldsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stato:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $attoStato) {
                    Text("Da Firmare").tag("da_firmare")
                    Text("Firmato").tag("firmato")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            HStack {
                Text("Tipo:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $attoSottotipo) {
                    Text("Accertamento").tag("accertamento")
                    Text("Liquidazione").tag("liquidazione")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
    
    // MARK: - Campi Giustificativi
    
    private var giustificativiFieldsView: some View {
        HStack {
            Text("Tipo:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Picker("", selection: $giustificativiTipo) {
                Text("Fattura").tag("fattura")
                Text("Preventivo").tag("preventivo")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }
    
    // MARK: - Campi Fulminazione
    
    private var fulminazioneFieldsView: some View {
        HStack {
            Text("Esito:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Picker("", selection: $fulminazioneSottotipo) {
                Text("Positiva").tag("positiva")
                Text("Negativa").tag("negativa")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }
    
    // MARK: - Campi Ubicazione
    
    private var ubicazioneFieldsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tipo:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $ubicazioneTipo) {
                    Text("Del rischio").tag("rischio")
                    Text("Tecnico").tag("tecnico")
                    Text("Amministratore").tag("amministratore")
                    Text("Altro").tag("altra")
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            
            if ubicazioneTipo == "altra" {
                TextField("Descrizione ubicazione", text: $ubicazioneAltra)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
        }
    }
    
    // MARK: - Contenuto modalità Aggiornamento Parziale
    
    private var partialUpdateModeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Info
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Aggiorna i campi mantenendo i tag esistenti. Puoi modificare tutti insieme o per gruppo.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Sezione Bene
            beneUpdateSection
            
            Divider()
            
            // Sezione Componente
            componenteUpdateSection
            
            Divider()
            
            // Campo Da Allegare
            daAllegareSection
        }
        .onAppear {
            analyzeExistingGroups()
        }
    }
    
    // MARK: - Sezione Bene
    
    private var beneUpdateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header con switch modalità
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cube")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Bene")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Spacer()
                
                if !existingBeniGroups.isEmpty {
                    Picker("", selection: $beneUpdateMode) {
                        Text("Tutti").tag(GroupUpdateMode.all)
                        Text("Per gruppo (\(existingBeniGroups.count))").tag(GroupUpdateMode.perGroup)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            
            if beneUpdateMode == .all {
                // Campo singolo per tutti
                GroupTextField(
                    placeholder: "es. Lavatrice - applica a tutti",
                    text: $partialBeneAll,
                    accentColor: .orange,
                    onFocus: { Task { await loadBeniSuggestionsForPartial() } }
                )
                
                // Suggerimenti
                if !beniSuggestions.isEmpty {
                    suggestionChips(suggestions: beniSuggestions, color: .orange) { selected in
                        partialBeneAll = selected
                    }
                }
                
                if filesWithoutBene > 0 {
                    Text("\(filesWithoutBene) file senza bene → verrà impostato")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                // Campi per gruppo
                VStack(spacing: 6) {
                    ForEach(existingBeniGroups, id: \.self) { group in
                        GroupFieldRow(
                            groupName: group,
                            placeholder: "Nuovo valore per '\(group)'",
                            text: binding(for: group, in: $partialBenePerGroup),
                            accentColor: .orange,
                            fileCount: countFilesWithBene(group),
                            suggestions: beniSuggestions,
                            onFocus: { Task { await loadBeniSuggestionsForPartial() } }
                        )
                    }
                    
                    if filesWithoutBene > 0 {
                        GroupFieldRow(
                            groupName: "⚠️ Senza bene",
                            placeholder: "Imposta bene per questi file",
                            text: binding(for: "__no_bene__", in: $partialBenePerGroup),
                            accentColor: .gray,
                            fileCount: filesWithoutBene,
                            suggestions: beniSuggestions,
                            onFocus: { Task { await loadBeniSuggestionsForPartial() } }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Sezione Componente
    
    private var componenteUpdateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header con switch modalità
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("Componente")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Spacer()
                
                if !existingComponentiGroups.isEmpty {
                    Picker("", selection: $componenteUpdateMode) {
                        Text("Tutti").tag(GroupUpdateMode.all)
                        Text("Per gruppo (\(existingComponentiGroups.count))").tag(GroupUpdateMode.perGroup)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            
            if componenteUpdateMode == .all {
                // Campo singolo per tutti
                GroupTextField(
                    placeholder: "es. Scheda controllo - applica a tutti",
                    text: $partialComponenteAll,
                    accentColor: .purple,
                    onFocus: { Task { await loadComponentiSuggestionsForPartial() } }
                )
                
                // Suggerimenti
                if !componentiSuggestions.isEmpty {
                    suggestionChips(suggestions: componentiSuggestions, color: .purple) { selected in
                        partialComponenteAll = selected
                    }
                }
                
                Text("Si applica solo a foto con tag 'Componente'")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                // Campi per gruppo
                VStack(spacing: 6) {
                    ForEach(existingComponentiGroups, id: \.self) { group in
                        GroupFieldRow(
                            groupName: group,
                            placeholder: "Nuovo valore per '\(group)'",
                            text: binding(for: group, in: $partialComponentePerGroup),
                            accentColor: .purple,
                            fileCount: countFilesWithComponente(group),
                            suggestions: componentiSuggestions,
                            onFocus: { Task { await loadComponentiSuggestionsForPartial() } }
                        )
                    }
                    
                    if filesWithoutComponente > 0 && existingComponentiGroups.isEmpty {
                        Text("\(filesWithoutComponente) file senza componente")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Sezione Da Allegare
    
    private var daAllegareSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle(isOn: $updateDaAllegare) {
                    HStack(spacing: 6) {
                        Image(systemName: "pin")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("Aggiorna 'Da Allegare'")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .toggleStyle(.checkbox)
                
                if updateDaAllegare {
                    Picker("", selection: $partialDaAllegare) {
                        Text("Sì").tag(true)
                        Text("No").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
                
                Spacer()
            }
            
            Text("Imposta lo stato 'da allegare in chiusura' su tutte le foto selezionate")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Componenti Helper
    
    private func suggestionChips(suggestions: [String], color: Color, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.15))
                            .foregroundColor(color)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func binding(for key: String, in dict: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { dict.wrappedValue[key] ?? "" },
            set: { dict.wrappedValue[key] = $0 }
        )
    }
    
    // MARK: - Analisi gruppi esistenti
    
    private func analyzeExistingGroups() {
        var beniSet = Set<String>()
        var componentiSet = Set<String>()
        var withoutBene = 0
        var withoutComponente = 0
        
        for file in photoFiles {
            let tags = fileTagManager.getTagsForFile(at: file.path)
            let photoTag = tags.first { FileTagManager.FileTag.photoTags.contains($0.id) }
            
            if let tag = photoTag {
                // Trova il bene
                if tag.id == "foto_bene" {
                    if let bene = fileTagManager.getAdditionalText(forFile: file.path, tagId: tag.id), !bene.isEmpty {
                        beniSet.insert(bene)
                    } else {
                        withoutBene += 1
                    }
                } else if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                    if let bene = fileTagManager.getBeneRiferimento(forFile: file.path, tagId: tag.id), !bene.isEmpty {
                        beniSet.insert(bene)
                    } else {
                        withoutBene += 1
                    }
                } else {
                    withoutBene += 1
                }
                
                // Trova il componente (solo per foto_componente)
                if tag.id == "foto_componente" {
                    if let comp = fileTagManager.getAdditionalText(forFile: file.path, tagId: tag.id), !comp.isEmpty {
                        componentiSet.insert(comp)
                    } else {
                        withoutComponente += 1
                    }
                }
            } else {
                withoutBene += 1
            }
        }
        
        existingBeniGroups = beniSet.sorted()
        existingComponentiGroups = componentiSet.sorted()
        filesWithoutBene = withoutBene
        filesWithoutComponente = withoutComponente
        
        // Inizializza i dizionari per i gruppi
        for bene in existingBeniGroups {
            if partialBenePerGroup[bene] == nil {
                partialBenePerGroup[bene] = ""
            }
        }
        for comp in existingComponentiGroups {
            if partialComponentePerGroup[comp] == nil {
                partialComponentePerGroup[comp] = ""
            }
        }
    }
    
    private func countFilesWithBene(_ bene: String) -> Int {
        var count = 0
        for file in photoFiles {
            let tags = fileTagManager.getTagsForFile(at: file.path)
            let photoTag = tags.first { FileTagManager.FileTag.photoTags.contains($0.id) }
            
            if let tag = photoTag {
                if tag.id == "foto_bene" {
                    if fileTagManager.getAdditionalText(forFile: file.path, tagId: tag.id) == bene {
                        count += 1
                    }
                } else if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                    if fileTagManager.getBeneRiferimento(forFile: file.path, tagId: tag.id) == bene {
                        count += 1
                    }
                }
            }
        }
        return count
    }
    
    private func countFilesWithComponente(_ componente: String) -> Int {
        var count = 0
        for file in photoFiles {
            let tags = fileTagManager.getTagsForFile(at: file.path)
            if let tag = tags.first(where: { $0.id == "foto_componente" }) {
                if fileTagManager.getAdditionalText(forFile: file.path, tagId: tag.id) == componente {
                    count += 1
                }
            }
        }
        return count
    }
    
    // MARK: - Caricamento suggerimenti lazy
    
    private func loadBeniSuggestionsForPartial() async {
        guard let path = sinistroPath else { return }
        beniSuggestions = await commonItemsManager.getBeniSuggestions(for: partialBeneAll, sinistroPath: path)
        usedBeni = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
    }
    
    private func loadComponentiSuggestionsForPartial() async {
        guard let path = sinistroPath else { return }
        componentiSuggestions = await commonItemsManager.getComponentiSuggestions(for: partialComponenteAll, sinistroPath: path)
    }
}

// MARK: - Componenti UI Helper

private struct GroupTextField: View {
    let placeholder: String
    @Binding var text: String
    let accentColor: Color
    var onFocus: (() -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onChange(of: isFocused) { focused in
                    if focused {
                        onFocus?()
                    }
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green.opacity(0.7))
                    .font(.system(size: 12))
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? accentColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

private struct GroupFieldRow: View {
    let groupName: String
    let placeholder: String
    @Binding var text: String
    let accentColor: Color
    let fileCount: Int
    var suggestions: [String] = []
    var onFocus: (() -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    @State private var showSuggestions: Bool = false
    
    private var filteredSuggestions: [String] {
        if text.isEmpty {
            return Array(suggestions.prefix(6))
        }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(6).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Badge gruppo
                HStack(spacing: 4) {
                    Text(groupName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Text("(\(fileCount))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.15))
                .foregroundColor(accentColor)
                .cornerRadius(4)
                .frame(minWidth: 80, alignment: .leading)
                
                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                // Campo
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isFocused ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onChange(of: isFocused) { focused in
                        showSuggestions = focused
                        if focused {
                            onFocus?()
                        }
                    }
                
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.system(size: 12))
                }
            }
            
            // Suggerimenti sotto il campo
            if showSuggestions && !filteredSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                isFocused = false
                                showSuggestions = false
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(accentColor.opacity(0.12))
                                    .foregroundColor(accentColor)
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 100) // Allinea con il campo
            }
        }
    }
}

extension BatchTagSheet {
    // MARK: - Footer
    
    private var footerView: some View {
        VStack(spacing: 12) {
            if isApplying {
                HStack(spacing: 8) {
                    ProgressView()
                        .frame(width: 16, height: 16)
                        .controlSize(.small)
                    Text("Applicazione in corso... \(appliedCount)/\(applicationMode == .fullTag ? targetFiles.count : photoFiles.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    if applicationMode == .fullTag {
                        applyFullTag()
                    } else {
                        applyPartialUpdate()
                    }
                } label: {
                    if applicationMode == .fullTag {
                        Text("Applica a \(targetFiles.count) file")
                    } else {
                        Text("Aggiorna \(photoFiles.count) foto/PDF")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplyButtonDisabled)
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }
    
    private var isApplyButtonDisabled: Bool {
        if isApplying { return true }
        
        if applicationMode == .fullTag {
            return selectedTag == nil || targetFiles.isEmpty
        } else {
            // Almeno un campo deve essere compilato
            let hasBeneAll = beneUpdateMode == .all && !partialBeneAll.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBenePerGroup = beneUpdateMode == .perGroup && partialBenePerGroup.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let hasComponenteAll = componenteUpdateMode == .all && !partialComponenteAll.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasComponentePerGroup = componenteUpdateMode == .perGroup && partialComponentePerGroup.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            let hasAnyField = hasBeneAll || hasBenePerGroup || hasComponenteAll || hasComponentePerGroup || updateDaAllegare
            return !hasAnyField || photoFiles.isEmpty
        }
    }
    
    // MARK: - Caricamento suggerimenti (lazy, solo quando necessario)
    
    private func loadSuggestions() async {
        guard let path = sinistroPath else { return }
        
        if isBeneTag {
            suggestions = await commonItemsManager.getBeniSuggestions(for: additionalText, sinistroPath: path)
            usedBeni = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
        } else if isComponenteTag {
            suggestions = await commonItemsManager.getComponentiSuggestions(for: additionalText, sinistroPath: path)
        } else {
            suggestions = []
        }
    }
    
    private func loadBeniSuggestions() async {
        guard let path = sinistroPath else { return }
        beniSuggestions = await commonItemsManager.getBeniSuggestions(for: beneRiferimento, sinistroPath: path)
        usedBeni = await commonItemsManager.getBeniUsedInSinistro(sinistroPath: path)
    }
    
    // MARK: - Applicazione tag completo
    
    private func applyFullTag() {
        guard let tag = selectedTag else { return }
        
        isApplying = true
        appliedCount = 0
        
        let trimmedText = additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBene = beneRiferimento.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task { @MainActor in
            for file in targetFiles {
                var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
                tagData.additionalText = trimmedText.isEmpty ? nil : trimmedText
                tagData.beneRiferimento = trimmedBene.isEmpty ? nil : trimmedBene
                
                // Imposta sottotipi specifici
                if isAttoTag {
                    tagData.attoStato = attoStato
                    tagData.attoSottotipo = attoSottotipo
                }
                if isGiustificativiTag {
                    tagData.giustificativiTipo = giustificativiTipo
                }
                if isFulminazioneTag {
                    tagData.fulminazioneSottotipo = fulminazioneSottotipo
                }
                if isUbicazioneTag {
                    tagData.ubicazioneTipo = ubicazioneTipo
                    if ubicazioneTipo == "altra" {
                        tagData.ubicazioneAltraDescrizione = ubicazioneAltra.isEmpty ? nil : ubicazioneAltra
                    }
                }
                
                await fileTagManager.applyTag(tagData, toFile: file.path, sinistroPath: sinistroPath)
                
                appliedCount += 1
            }
            
            isApplying = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
    
    // MARK: - Applicazione update parziale
    
    private func applyPartialUpdate() {
        isApplying = true
        appliedCount = 0
        
        // Inizia batch mode per evitare salvataggi multipli su disco
        fileTagManager.beginBatchUpdate()
        
        // Prepara i valori da applicare
        let beneAllTrimmed = partialBeneAll.trimmingCharacters(in: .whitespacesAndNewlines)
        let componenteAllTrimmed = partialComponenteAll.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Prepara mappature per gruppo
        var beneGroupMappings: [String: String] = [:]
        for (key, value) in partialBenePerGroup {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                beneGroupMappings[key] = trimmed
            }
        }
        
        var componenteGroupMappings: [String: String] = [:]
        for (key, value) in partialComponentePerGroup {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                componenteGroupMappings[key] = trimmed
            }
        }
        
        Task { @MainActor in
            for file in photoFiles {
                let existingTags = fileTagManager.getTagsForFile(at: file.path)
                let photoTag = existingTags.first { FileTagManager.FileTag.photoTags.contains($0.id) }
                
                if let existingPhotoTag = photoTag {
                    // Determina il bene corrente del file
                    var currentBene: String? = nil
                    if existingPhotoTag.id == "foto_bene" {
                        currentBene = fileTagManager.getAdditionalText(forFile: file.path, tagId: existingPhotoTag.id)
                    } else if FileTagManager.FileTag.beneRiferimentoTags.contains(existingPhotoTag.id) {
                        currentBene = fileTagManager.getBeneRiferimento(forFile: file.path, tagId: existingPhotoTag.id)
                    }
                    
                    // Determina il componente corrente (solo per foto_componente)
                    var currentComponente: String? = nil
                    if existingPhotoTag.id == "foto_componente" {
                        currentComponente = fileTagManager.getAdditionalText(forFile: file.path, tagId: existingPhotoTag.id)
                    }
                    
                    // === AGGIORNA BENE ===
                    if beneUpdateMode == .all && !beneAllTrimmed.isEmpty {
                        // Applica a tutti
                        if existingPhotoTag.id == "foto_bene" {
                            fileTagManager.setAdditionalText(beneAllTrimmed, forFile: file.path, tagId: existingPhotoTag.id)
                        } else if FileTagManager.FileTag.beneRiferimentoTags.contains(existingPhotoTag.id) {
                            fileTagManager.setBeneRiferimento(beneAllTrimmed, forFile: file.path, tagId: existingPhotoTag.id)
                        }
                    } else if beneUpdateMode == .perGroup {
                        // Applica per gruppo
                        let groupKey = currentBene ?? "__no_bene__"
                        if let newBene = beneGroupMappings[groupKey] ?? beneGroupMappings[currentBene ?? ""] {
                            if existingPhotoTag.id == "foto_bene" {
                                fileTagManager.setAdditionalText(newBene, forFile: file.path, tagId: existingPhotoTag.id)
                            } else if FileTagManager.FileTag.beneRiferimentoTags.contains(existingPhotoTag.id) {
                                fileTagManager.setBeneRiferimento(newBene, forFile: file.path, tagId: existingPhotoTag.id)
                            }
                        }
                    }
                    
                    // === AGGIORNA COMPONENTE ===
                    if existingPhotoTag.id == "foto_componente" {
                        if componenteUpdateMode == .all && !componenteAllTrimmed.isEmpty {
                            fileTagManager.setAdditionalText(componenteAllTrimmed, forFile: file.path, tagId: existingPhotoTag.id)
                        } else if componenteUpdateMode == .perGroup {
                            if let newComp = componenteGroupMappings[currentComponente ?? ""] {
                                fileTagManager.setAdditionalText(newComp, forFile: file.path, tagId: existingPhotoTag.id)
                            }
                        }
                    }
                    
                    // === AGGIORNA DA ALLEGARE ===
                    if updateDaAllegare {
                        fileTagManager.setDaAllegareInChiusura(partialDaAllegare, forFile: file.path, tagId: existingPhotoTag.id)
                    }
                    
                } else {
                    // File senza tag - applica foto_bene se abbiamo un bene
                    var newBene: String? = nil
                    
                    if beneUpdateMode == .all && !beneAllTrimmed.isEmpty {
                        newBene = beneAllTrimmed
                    } else if beneUpdateMode == .perGroup {
                        newBene = beneGroupMappings["__no_bene__"]
                    }
                    
                    if let bene = newBene {
                        var tagData = FileTagManager.TagApplicationData(tagId: "foto_bene")
                        tagData.additionalText = bene
                        tagData.daAllegareInChiusura = updateDaAllegare ? partialDaAllegare : true
                        await fileTagManager.applyTag(tagData, toFile: file.path, sinistroPath: sinistroPath)
                    }
                }
                
                appliedCount += 1
            }
            
            // Aggiungi ai custom items per autocompletamento futuro
            if !beneAllTrimmed.isEmpty {
                commonItemsManager.addCustomBene(beneAllTrimmed)
            }
            for bene in beneGroupMappings.values {
                commonItemsManager.addCustomBene(bene)
            }
            if !componenteAllTrimmed.isEmpty {
                commonItemsManager.addCustomComponente(componenteAllTrimmed)
            }
            for comp in componenteGroupMappings.values {
                commonItemsManager.addCustomComponente(comp)
            }
            
            // Commit tutte le modifiche su disco in un'unica operazione
            fileTagManager.commitBatchUpdate()
            
            isApplying = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
    
    // MARK: - Helper per campi tag
    
    private func getFieldLabel(for tag: FileTagManager.FileTag) -> String {
        switch tag.id {
        case "foto_bene": return "Nome del bene"
        case "foto_componente": return "Nome del componente"
        case "foto_ripristino": return "Descrizione ripristino"
        case "foto_ubicazione_altra": return "Descrizione ubicazione"
        default: return "Descrizione"
        }
    }
    
    private func getPlaceholder(for tag: FileTagManager.FileTag) -> String {
        switch tag.id {
        case "foto_bene": return "es. Lavatrice, Frigorifero..."
        case "foto_componente": return "es. Scheda di controllo, Inverter..."
        case "foto_ripristino": return "es. Sostituzione componente..."
        case "foto_ubicazione_altra": return "es. Negozio, Ufficio..."
        default: return "Inserisci descrizione..."
        }
    }
    
    private func getFieldIcon(for tag: FileTagManager.FileTag) -> String {
        switch tag.id {
        case "foto_bene": return "cube"
        case "foto_componente": return "gearshape"
        case "foto_ripristino": return "wrench.and.screwdriver"
        default: return "text.alignleft"
        }
    }
}
