import SwiftUI

// MARK: - Unified Tag View

/// Componente tag unificato condiviso tra MediaViewer e CartellaView
/// Supporta sia file che singole pagine PDF
struct UnifiedTagView: View {
    
    enum Context: Equatable {
        case file(URL)
        case pdfPage(URL, pageIndex: Int)
        
        var url: URL {
            switch self {
            case .file(let url): return url
            case .pdfPage(let url, _): return url
            }
        }
        
        var pageIndex: Int? {
            switch self {
            case .file: return nil
            case .pdfPage(_, let index): return index
            }
        }
        
        var filePath: String {
            url.path
        }
    }
    
    let context: Context
    let sinistroPath: String?
    
    @StateObject private var fileTagManager = FileTagManager.shared
    @State private var expandedCategories: Set<FileTagManager.FileTag.TagCategory?> = [.foto]
    @State private var editingTagId: String?
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    init(context: Context, sinistroPath: String? = nil) {
        self.context = context
        self.sinistroPath = sinistroPath
    }
    
    var body: some View {
        GlassmorphicPopover {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                headerView
                
                GlassmorphicDivider()
                
                // Lista tag organizzati per categoria
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Tag senza categoria
                        if let noCategoryTags = FileTagManager.FileTag.unifiedTagsByCategory()[nil], !noCategoryTags.isEmpty {
                            UnifiedTagSection(
                                tags: noCategoryTags,
                                context: context,
                                sinistroPath: sinistroPath,
                                fileTagManager: fileTagManager,
                                editingTagId: $editingTagId,
                                editingText: $editingText,
                                isTextFieldFocused: _isTextFieldFocused
                            )
                        }
                        
                        // Categoria Foto
                        if let fotoTags = FileTagManager.FileTag.unifiedTagsByCategory()[.foto], !fotoTags.isEmpty {
                            UnifiedCategorySection(
                                category: .foto,
                                tags: fotoTags,
                                context: context,
                                sinistroPath: sinistroPath,
                                fileTagManager: fileTagManager,
                                expandedCategories: $expandedCategories,
                                editingTagId: $editingTagId,
                                editingText: $editingText,
                                isTextFieldFocused: _isTextFieldFocused
                            )
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            .frame(width: 340)
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
            }
            
            Spacer()
            
            Text(context.url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.bottom, 4)
    }
    
    private var headerTitle: String {
        switch context {
        case .file:
            return "Tag"
        case .pdfPage(_, let pageIndex):
            return "Tag - Pagina \(pageIndex + 1)"
        }
    }
}

// MARK: - Unified Category Section

struct UnifiedCategorySection: View {
    let category: FileTagManager.FileTag.TagCategory
    let tags: [FileTagManager.FileTag]
    let context: UnifiedTagView.Context
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var expandedCategories: Set<FileTagManager.FileTag.TagCategory?>
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var isExpanded: Bool {
        expandedCategories.contains(category)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Text(category.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Badge conteggio tag applicati
                    let appliedCount = countAppliedTags(in: tags)
                    if appliedCount > 0 {
                        GlassmorphicBadge(text: "\(appliedCount)", color: .accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                UnifiedTagSection(
                    tags: tags,
                    context: context,
                    sinistroPath: sinistroPath,
                    fileTagManager: fileTagManager,
                    editingTagId: $editingTagId,
                    editingText: $editingText,
                    isTextFieldFocused: _isTextFieldFocused
                )
                .padding(.leading, 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }
    
    private func countAppliedTags(in tags: [FileTagManager.FileTag]) -> Int {
        switch context {
        case .file:
            let appliedTags = fileTagManager.getTagsForFile(at: context.filePath)
            return tags.filter { tag in
                if tag.id == "atto" {
                    return appliedTags.contains(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })
                } else if tag.id == "giustificativi" {
                    return appliedTags.contains(where: { $0.id == "fattura" || $0.id == "preventivo" })
                } else {
                    return appliedTags.contains(tag)
                }
            }.count
        case .pdfPage(_, let pageIndex):
            let appliedTags = fileTagManager.getTagsForPDFPage(at: context.filePath, pageIndex: pageIndex)
            return tags.filter { appliedTags.contains($0) }.count
        }
    }
}

// MARK: - Unified Tag Section

struct UnifiedTagSection: View {
    let tags: [FileTagManager.FileTag]
    let context: UnifiedTagView.Context
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags) { tag in
                UnifiedTagRow(
                    tag: tag,
                    context: context,
                    sinistroPath: sinistroPath,
                    fileTagManager: fileTagManager,
                    editingTagId: $editingTagId,
                    editingText: $editingText,
                    isTextFieldFocused: _isTextFieldFocused
                )
            }
        }
    }
}

// MARK: - Unified Tag Row

struct UnifiedTagRow: View {
    let tag: FileTagManager.FileTag
    let context: UnifiedTagView.Context
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    @State private var isHovered = false
    
    // State per sottotag
    @State private var attoStato: String = ""
    @State private var attoSottotipo: String = ""
    @State private var giustificativiTipo: String = ""
    @State private var ubicazioneTipo: String = "rischio"
    @State private var ubicazioneAltraDescrizione: String = ""
    @State private var fulminazioneSottotipo: String = ""
    
    var isSelected: Bool {
        switch context {
        case .file:
            if tag.id == "atto" {
                let tags = fileTagManager.getTagsForFile(at: context.filePath)
                return tags.contains(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })
            } else if tag.id == "giustificativi" {
                let tags = fileTagManager.getTagsForFile(at: context.filePath)
                return tags.contains(where: { $0.id == "fattura" || $0.id == "preventivo" })
            } else {
                return fileTagManager.getTagsForFile(at: context.filePath).contains(tag)
            }
        case .pdfPage(_, let pageIndex):
            return fileTagManager.getTagsForPDFPage(at: context.filePath, pageIndex: pageIndex).contains(tag)
        }
    }
    
    var currentAdditionalText: String {
        switch context {
        case .file:
            return fileTagManager.getAdditionalText(forFile: context.filePath, tagId: tag.id) ?? ""
        case .pdfPage(_, let pageIndex):
            return fileTagManager.getAdditionalTextForPDFPage(forFile: context.filePath, pageIndex: pageIndex, tagId: tag.id) ?? ""
        }
    }
    
    var isDaAllegare: Bool {
        switch context {
        case .file:
            return fileTagManager.getDaAllegareInChiusura(forFile: context.filePath, tagId: tag.id)
        case .pdfPage(_, let pageIndex):
            return fileTagManager.getDaAllegareForPDFPage(forFile: context.filePath, pageIndex: pageIndex, tagId: tag.id)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tag button
            Button {
                toggleTag()
            } label: {
                HStack(spacing: 10) {
                    // Checkbox icon con glow
                    ZStack {
                        Circle()
                            .fill(isSelected ? tag.tagColor.opacity(0.2) : Color.clear)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? tag.tagColor : .secondary)
                    }
                    .shadow(color: isSelected ? tag.tagColor.opacity(0.3) : .clear, radius: 4)
                    
                    // Nome tag
                    Text(tag.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? tag.tagColor : .primary)
                    
                    Spacer()
                    
                    // Toggle "Da allegare"
                    if isSelected {
                        Toggle(isOn: Binding(
                            get: { isDaAllegare },
                            set: { setDaAllegare($0) }
                        )) {
                            HStack(spacing: 3) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9))
                                Text("Chiusura")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(isDaAllegare ? tag.tagColor : .secondary)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected ? tag.tagColor.opacity(0.08) :
                            isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass :
                            Color.clear
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? tag.tagColor.opacity(0.3) :
                            isHovered ? GlassmorphismDesignSystem.Colors.borderLight :
                            Color.clear,
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                    isHovered = hovering
                }
            }
            
            // Campo testo aggiuntivo
            if isSelected && tag.requiresAdditionalText {
                additionalTextField
            }
            
            // Sottotag per tag "atto"
            if isSelected && (tag.id == "atto" || FileTagManager.FileTag.attoTags.contains(tag.id)) {
                attoSubtagsView
            }
            
            // Sottotag per tag "giustificativi"
            if isSelected && (tag.id == "giustificativi" || FileTagManager.FileTag.giustificativiTags.contains(tag.id)) {
                giustificativiSubtagView
            }
            
            // Sottotag per tag "foto_ubicazione"
            if isSelected && (tag.id == "foto_ubicazione" || FileTagManager.FileTag.ubicazioneTags.contains(tag.id)) {
                ubicazioneSubtagView
            }
            
            // Sottotag per tag "fulminazione"
            if isSelected && tag.id == "fulminazione" {
                fulminazioneSubtagView
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            loadSubtagValues()
        }
    }
    
    // MARK: - Subtag Views
    
    private var attoSubtagsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stato: Da Firmare / Firmato
            HStack(spacing: 8) {
                Text("Stato:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $attoStato) {
                    Text("Da Firmare").tag("da_firmare")
                    Text("Firmato").tag("firmato")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .onChange(of: attoStato) { newValue in
                    guard !newValue.isEmpty else { return }
                    changeAttoStato(to: newValue)
                }
            }
            
            // Tipo: Non specificato / Liquidazione / Accertamento
            HStack(spacing: 8) {
                Text("Tipo:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $attoSottotipo) {
                    Text("Non specificato").tag("")
                    Text("Liquidazione").tag("liquidazione")
                    Text("Accertamento").tag("accertamento")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)
                .onChange(of: attoSottotipo) { newValue in
                    saveAttoSottotipo(newValue)
                }
            }
        }
        .padding(.leading, 34)
        .padding(.top, 4)
    }
    
    private var giustificativiSubtagView: some View {
        HStack(spacing: 8) {
            Text("Tipo:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Picker("", selection: $giustificativiTipo) {
                Text("Fattura").tag("fattura")
                Text("Preventivo").tag("preventivo")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .onChange(of: giustificativiTipo) { newValue in
                guard !newValue.isEmpty else { return }
                changeGiustificativiTipo(to: newValue)
            }
        }
        .padding(.leading, 34)
        .padding(.top, 4)
    }
    
    private var ubicazioneSubtagView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tipo:")
                    .font(.system(size: 11))
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
                    changeUbicazioneTipo(to: newValue)
                }
            }
            
            if ubicazioneTipo == "altra" {
                HStack(spacing: 8) {
                    Text("Descrizione:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("Specifica ubicazione...", text: $ubicazioneAltraDescrizione)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit {
                            saveUbicazioneAltraDescrizione()
                        }
                }
            }
        }
        .padding(.leading, 34)
        .padding(.top, 4)
    }
    
    private var fulminazioneSubtagView: some View {
        HStack(spacing: 8) {
            Text("Esito:")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Picker("", selection: $fulminazioneSottotipo) {
                Text("Non specificato").tag("")
                Text("Positiva").tag("positiva")
                Text("Negativa").tag("negativa")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            .onChange(of: fulminazioneSottotipo) { newValue in
                saveFulminazioneSottotipo(newValue)
            }
        }
        .padding(.leading, 34)
        .padding(.top, 4)
    }
    
    // MARK: - Subtag Loading
    
    private func loadSubtagValues() {
        guard case .file = context else { return }
        
        let currentTags = fileTagManager.getTagsForFile(at: context.filePath)
        
        // Carica stato atto
        if tag.id == "atto" || FileTagManager.FileTag.attoTags.contains(tag.id) {
            if currentTags.contains(where: { $0.id == "atto_firmato" }) {
                attoStato = "firmato"
                attoSottotipo = fileTagManager.getAttoSottotipo(forFile: context.filePath, tagId: "atto_firmato") ?? ""
            } else if currentTags.contains(where: { $0.id == "atto_da_firmare" }) {
                attoStato = "da_firmare"
                attoSottotipo = fileTagManager.getAttoSottotipo(forFile: context.filePath, tagId: "atto_da_firmare") ?? ""
            }
        }
        
        // Carica tipo giustificativi
        if tag.id == "giustificativi" || FileTagManager.FileTag.giustificativiTags.contains(tag.id) {
            if currentTags.contains(where: { $0.id == "fattura" }) {
                giustificativiTipo = "fattura"
            } else if currentTags.contains(where: { $0.id == "preventivo" }) {
                giustificativiTipo = "preventivo"
            }
        }
        
        // Carica tipo ubicazione
        if tag.id == "foto_ubicazione" || FileTagManager.FileTag.ubicazioneTags.contains(tag.id) {
            if currentTags.contains(where: { $0.id == "foto_ubicazione_rischio" }) {
                ubicazioneTipo = "rischio"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_tecnico" }) {
                ubicazioneTipo = "tecnico"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_amministratore" }) {
                ubicazioneTipo = "amministratore"
            } else if currentTags.contains(where: { $0.id == "foto_ubicazione_altra" }) {
                ubicazioneTipo = "altra"
                ubicazioneAltraDescrizione = fileTagManager.getAdditionalText(forFile: context.filePath, tagId: "foto_ubicazione_altra") ?? ""
            }
        }
        
        // Carica sottotipo fulminazione
        if tag.id == "fulminazione" {
            fulminazioneSottotipo = fileTagManager.getFulminazioneSottotipo(forFile: context.filePath, tagId: "fulminazione") ?? ""
        }
    }
    
    // MARK: - Subtag Actions
    
    /// Ottiene il valore corrente di daAllegare per il tag
    private func getCurrentDaAllegare() -> Bool {
        // Per tag unificati, cerca il tag effettivo
        let currentTags = fileTagManager.getTagsForFile(at: context.filePath)
        
        if tag.id == "atto" {
            if let attoTag = currentTags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" }) {
                return fileTagManager.getDaAllegareInChiusura(forFile: context.filePath, tagId: attoTag.id)
            }
        } else if tag.id == "giustificativi" {
            if let giustTag = currentTags.first(where: { $0.id == "fattura" || $0.id == "preventivo" }) {
                return fileTagManager.getDaAllegareInChiusura(forFile: context.filePath, tagId: giustTag.id)
            }
        } else if tag.id == "foto_ubicazione" {
            if let ubicazioneTag = currentTags.first(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) }) {
                return fileTagManager.getDaAllegareInChiusura(forFile: context.filePath, tagId: ubicazioneTag.id)
            }
        } else {
            return fileTagManager.getDaAllegareInChiusura(forFile: context.filePath, tagId: tag.id)
        }
        return true // Default: allegare
    }
    
    private func changeAttoStato(to newStato: String) {
        guard case .file = context else { return }
        
        // Usa applyTag per cambiare stato atto, preservando sottotipo e daAllegare
        var tagData = FileTagManager.TagApplicationData(tagId: "atto")
        tagData.attoStato = newStato
        tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
        tagData.daAllegareInChiusura = getCurrentDaAllegare()
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func saveAttoSottotipo(_ sottotipo: String) {
        guard case .file = context else { return }
        
        // Usa applyTag per aggiornare il sottotipo
        var tagData = FileTagManager.TagApplicationData(tagId: "atto")
        tagData.attoStato = attoStato.isEmpty ? nil : attoStato
        tagData.attoSottotipo = sottotipo.isEmpty ? nil : sottotipo
        tagData.daAllegareInChiusura = getCurrentDaAllegare()
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func changeGiustificativiTipo(to newTipo: String) {
        guard case .file = context else { return }
        
        // Usa applyTag per cambiare tipo giustificativo, preservando daAllegare
        var tagData = FileTagManager.TagApplicationData(tagId: "giustificativi")
        tagData.giustificativiTipo = newTipo
        tagData.daAllegareInChiusura = getCurrentDaAllegare()
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func changeUbicazioneTipo(to newTipo: String) {
        guard case .file = context else { return }
        
        // Usa applyTag per cambiare tipo ubicazione, preservando daAllegare
        var tagData = FileTagManager.TagApplicationData(tagId: "foto_ubicazione")
        tagData.ubicazioneTipo = newTipo
        tagData.daAllegareInChiusura = getCurrentDaAllegare()
        
        // Per "altra", mantieni la descrizione esistente
        if newTipo == "altra" {
            tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
        }
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func saveUbicazioneAltraDescrizione() {
        guard case .file = context else { return }
        
        // Usa applyTag per salvare la descrizione con riconciliazione
        var tagData = FileTagManager.TagApplicationData(tagId: "foto_ubicazione")
        tagData.ubicazioneTipo = "altra"
        tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
        tagData.daAllegareInChiusura = getCurrentDaAllegare()
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func saveFulminazioneSottotipo(_ sottotipo: String) {
        guard case .file = context else { return }
        fileTagManager.setFulminazioneSottotipo(sottotipo.isEmpty ? nil : sottotipo, forFile: context.filePath, tagId: "fulminazione")
    }
    
    private var additionalTextField: some View {
        HStack(spacing: 8) {
            if editingTagId == tag.id {
                GlassmorphicTextField(
                    placeholderForTag(tag),
                    text: $editingText,
                    icon: "text.cursor"
                )
                .focused($isTextFieldFocused)
                .onSubmit {
                    saveAdditionalText()
                }
                
                GlassmorphicIconButton(icon: "checkmark", size: 22) {
                    saveAdditionalText()
                }
                
                GlassmorphicIconButton(icon: "xmark", size: 22) {
                    cancelEditing()
                }
            } else {
                if !currentAdditionalText.isEmpty {
                    Text(currentAdditionalText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tag.tagColor.opacity(0.1))
                        )
                }
                
                GlassmorphicIconButton(
                    icon: currentAdditionalText.isEmpty ? "plus.circle" : "pencil.circle",
                    size: 22
                ) {
                    startEditing()
                }
            }
        }
        .padding(.leading, 34)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Actions
    
    private func toggleTag() {
        switch context {
        case .file:
            if isSelected {
                // RIMOZIONE - usa removeCurrentTag per rimuovere tutti i tag esistenti
                fileTagManager.removeCurrentTag(fromFile: context.filePath)
                
                // Reset stato locale
                if tag.id == "atto" {
                    attoStato = ""
                    attoSottotipo = ""
                } else if tag.id == "giustificativi" {
                    giustificativiTipo = ""
                } else if tag.id == "foto_ubicazione" {
                    ubicazioneTipo = "rischio"
                    ubicazioneAltraDescrizione = ""
                }
            } else {
                // AGGIUNTA - usa applyTag con TagApplicationData
                var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
                
                // Imposta valori di default per tag unificati
                if tag.id == "atto" {
                    tagData.attoStato = "da_firmare"
                    attoStato = "da_firmare"
                } else if tag.id == "giustificativi" {
                    tagData.giustificativiTipo = "fattura"
                    giustificativiTipo = "fattura"
                } else if tag.id == "foto_ubicazione" {
                    tagData.ubicazioneTipo = "rischio"
                    ubicazioneTipo = "rischio"
                }
                
                // Applica il tag usando il sistema centralizzato
                Task {
                    await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
                }
                
                if tag.requiresAdditionalText {
                    startEditing()
                }
            }
            
        case .pdfPage(_, let pageIndex):
            // Per le pagine PDF manteniamo il comportamento precedente (possono avere un tag per pagina)
            if isSelected {
                fileTagManager.removeTag(tag, fromPDFPage: context.filePath, pageIndex: pageIndex)
            } else {
                fileTagManager.addTag(tag, toPDFPage: context.filePath, pageIndex: pageIndex)
                if tag.requiresAdditionalText {
                    startEditing()
                }
            }
        }
    }
    
    private func setDaAllegare(_ value: Bool) {
        switch context {
        case .file:
            if tag.id == "atto" {
                let tags = fileTagManager.getTagsForFile(at: context.filePath)
                let attoTagId = tags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })?.id ?? "atto_da_firmare"
                fileTagManager.setDaAllegareInChiusura(value, forFile: context.filePath, tagId: attoTagId)
            } else if tag.id == "giustificativi" {
                let tags = fileTagManager.getTagsForFile(at: context.filePath)
                let giustTagId = tags.first(where: { $0.id == "fattura" || $0.id == "preventivo" })?.id ?? "fattura"
                fileTagManager.setDaAllegareInChiusura(value, forFile: context.filePath, tagId: giustTagId)
            } else {
                fileTagManager.setDaAllegareInChiusura(value, forFile: context.filePath, tagId: tag.id)
            }
        case .pdfPage(_, let pageIndex):
            fileTagManager.setDaAllegareForPDFPage(value, forFile: context.filePath, pageIndex: pageIndex, tagId: tag.id)
        }
    }
    
    private func startEditing() {
        editingTagId = tag.id
        editingText = currentAdditionalText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func saveAdditionalText() {
        switch context {
        case .file:
            // Usa applyTag per salvare il testo con riconciliazione
            var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
            tagData.additionalText = editingText
            
            // Mantieni gli altri metadati esistenti
            tagData.attoStato = attoStato.isEmpty ? nil : attoStato
            tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
            tagData.giustificativiTipo = giustificativiTipo.isEmpty ? nil : giustificativiTipo
            tagData.ubicazioneTipo = ubicazioneTipo.isEmpty ? nil : ubicazioneTipo
            tagData.ubicazioneAltraDescrizione = ubicazioneAltraDescrizione.isEmpty ? nil : ubicazioneAltraDescrizione
            
            // Per foto_componente, il beneRiferimento va preservato
            if tag.id == "foto_componente" || FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                tagData.beneRiferimento = fileTagManager.getBeneRiferimento(forFile: context.filePath, tagId: tag.id)
            }
            
            Task {
                await fileTagManager.applyTag(tagData, toFile: context.filePath, sinistroPath: sinistroPath)
            }
        case .pdfPage(_, let pageIndex):
            fileTagManager.setAdditionalTextForPDFPage(editingText, forFile: context.filePath, pageIndex: pageIndex, tagId: tag.id)
        }
        editingTagId = nil
    }
    
    private func cancelEditing() {
        editingTagId = nil
        editingText = ""
    }
    
    private func placeholderForTag(_ tag: FileTagManager.FileTag) -> String {
        switch tag.id {
        case "foto_bene":
            return "Es: caldaia, televisore..."
        case "foto_componente":
            return "Es: scheda, circolatore..."
        case "foto_ripristino":
            return "Es: caldaia, televisore..."
        default:
            return "Inserisci testo..."
        }
    }
}
