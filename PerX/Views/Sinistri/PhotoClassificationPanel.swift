import SwiftUI

// MARK: - Photo Classification Panel

/// Panel per classificazione rapida delle foto con design glassmorphism
struct PhotoClassificationPanel: View {
    let filePath: String
    let sinistroPath: String?
    
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var isEditingTextField: Bool
    
    @StateObject private var commonItemsManager = CommonItemsManager.shared
    @State private var includeInClosure: Bool = true
    @State private var isExpanded: Bool = true
    @State private var cachedAppliedTags: Set<FileTagManager.FileTag> = []
    @State private var updateTrigger: UUID = UUID()
    
    private var photoTags: [FileTagManager.FileTag] {
        FileTagManager.FileTag.unifiedTagsForUI().filter { $0.category == .foto }
    }
    
    private var appliedTags: Set<FileTagManager.FileTag> {
        cachedAppliedTags
    }
    
    private var appliedPhotoTags: [FileTagManager.FileTag] {
        photoTags.filter { tag in
            // Per tag unificati, controlla se uno dei tag individuali è presente
            if tag.id == "foto_ubicazione" {
                return appliedTags.contains(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) })
            }
            return appliedTags.contains(tag)
        }
    }
    
    /// Verifica se un tag (inclusi quelli unificati) è applicato
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
        appliedPhotoTags.contains { fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: $0.id) }
    }
    
    private func refreshCachedTags() {
        cachedAppliedTags = fileTagManager.getTagsForFile(at: filePath)
    }
    
    var body: some View {
        GlassmorphicPanel(material: .thin, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                
                if isExpanded {
                    GlassmorphicDivider()
                    
                    // Tag list in due colonne
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(photoTags, id: \.id) { tag in
                                PhotoTagItem(
                                    tag: tag,
                                    filePath: filePath,
                                    sinistroPath: sinistroPath,
                                    fileTagManager: fileTagManager,
                                    commonItemsManager: commonItemsManager,
                                    isApplied: isTagApplied(tag),
                                    hasFields: hasAdditionalFields(tag),
                                    isEditingTextField: $isEditingTextField,
                                    includeInClosure: $includeInClosure,
                                    onTagSelected: { handleTagSelection(tag) }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxHeight: 350)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
        }
        .onAppear {
            refreshCachedTags()
            syncIncludeInClosureFromTags()
        }
        .onChange(of: filePath) { _ in
            refreshCachedTags()
            syncIncludeInClosureFromTags()
        }
        .onChange(of: updateTrigger) { _ in
            syncIncludeInClosureFromTags()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    
                    Text("Classifica Foto")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Badge conteggio tag applicati
            let appliedCount = appliedPhotoTags.count
            if appliedCount > 0 {
                GlassmorphicBadge(text: "\(appliedCount) tag", color: .accentColor)
            }
            
            // Toggle allega in chiusura
            Toggle(isOn: $includeInClosure) {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                    Text("Allega")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(includeInClosure ? .accentColor : .secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .onChange(of: includeInClosure) { newValue in
                setPinnedForAllPhotoTags(newValue)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func syncIncludeInClosureFromTags() {
        guard !appliedPhotoTags.isEmpty else { return }
        includeInClosure = isAnyPhotoTagPinned
    }
    
    private func setPinnedForAllPhotoTags(_ pinned: Bool) {
        for tag in photoTags {
            fileTagManager.setDaAllegareInChiusura(pinned, forFile: filePath, tagId: tag.id)
        }
    }
    
    private func handleTagSelection(_ tag: FileTagManager.FileTag) {
        let isUbicazioneTag = tag.id == "foto_ubicazione"
        
        // Usa i tag correnti da cache
        let currentAppliedTags = cachedAppliedTags
        
        // Per tag unificati, controlla se uno dei tag individuali è presente
        let isCurrentlyApplied: Bool
        if isUbicazioneTag {
            isCurrentlyApplied = currentAppliedTags.contains(where: { FileTagManager.FileTag.ubicazioneTags.contains($0.id) })
        } else {
            isCurrentlyApplied = currentAppliedTags.contains(tag)
        }
        
        if isCurrentlyApplied {
            // RIMOZIONE - usa removeCurrentTag per coerenza con il nuovo sistema
            fileTagManager.removeCurrentTag(fromFile: filePath)
            refreshCachedTags()
            updateTrigger = UUID()
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
            refreshCachedTags()
            updateTrigger = UUID()
        }
    }
}

// MARK: - Photo Tag Item

struct PhotoTagItem: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @ObservedObject var commonItemsManager: CommonItemsManager
    let isApplied: Bool
    let hasFields: Bool
    @Binding var isEditingTextField: Bool
    @Binding var includeInClosure: Bool
    let onTagSelected: () -> Void
    
    @State private var isHovered = false
    @State private var additionalText: String = ""
    @State private var beneRiferimento: String = ""
    @State private var showSuggestions = false
    @FocusState private var isFieldFocused: Bool
    
    private var tagIcon: String {
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Tag button
            Button(action: onTagSelected) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(isApplied ? Color.white.opacity(0.2) : tag.tagColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: tagIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isApplied ? .white : tag.tagColor)
                    }
                    .shadow(color: isApplied ? tag.tagColor.opacity(0.4) : .clear, radius: 4)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.name)
                            .font(.system(size: 13, weight: isApplied ? .semibold : .medium))
                            .foregroundColor(isApplied ? .white : .primary)
                        
                        // Preview del valore aggiuntivo
                        if isApplied {
                            let text = fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id) ?? ""
                            let bene = fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id) ?? ""
                            
                            if !text.isEmpty || !bene.isEmpty {
                                Text([text, bene].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Checkmark
                    if isApplied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isApplied ? tag.tagColor : (isHovered ? tag.tagColor.opacity(0.1) : GlassmorphismDesignSystem.Colors.secondaryGlass))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            tag.tagColor.opacity(isApplied ? 0 : (isHovered ? 0.4 : 0.15)),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isApplied ? tag.tagColor.opacity(0.3) : .clear,
                    radius: 6,
                    x: 0,
                    y: 3
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                    isHovered = hovering
                }
            }
            
            // Campi aggiuntivi
            if isApplied && hasFields {
                if tag.id == "foto_ubicazione" {
                    // Per tag ubicazione unificato, mostra il picker sottotipo
                    UbicazioneSubtypePickerView(
                        filePath: filePath,
                        fileTagManager: fileTagManager,
                        includeInClosure: includeInClosure
                    )
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity
                    ))
                } else {
                    PhotoTagFieldsView(
                        tag: tag,
                        filePath: filePath,
                        sinistroPath: sinistroPath,
                        fileTagManager: fileTagManager,
                        commonItemsManager: commonItemsManager,
                        isEditingTextField: $isEditingTextField
                    )
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity
                    ))
                }
            }
        }
        .animation(GlassmorphismDesignSystem.Animations.spring, value: isApplied)
    }
}

// MARK: - Photo Tag Fields View

struct PhotoTagFieldsView: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @ObservedObject var commonItemsManager: CommonItemsManager
    @Binding var isEditingTextField: Bool
    
    @State private var additionalText: String = ""
    @State private var beneRiferimento: String = ""
    @State private var showSuggestions = false
    @State private var showBeneSuggestions = false
    @FocusState private var isTextFocused: Bool
    @FocusState private var isBeneFocused: Bool
    
    private var needsBeneRiferimento: Bool {
        FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Campo principale (se richiesto)
            if tag.requiresAdditionalText {
                GlassmorphicTextField(
                    getPlaceholder(),
                    text: $additionalText,
                    icon: getIcon()
                )
                .focused($isTextFocused)
                .onChange(of: isTextFocused) { focused in
                    isEditingTextField = focused
                }
                .onChange(of: additionalText) { newValue in
                    saveDebounced(text: newValue)
                }
            }
            
            // Campo bene di riferimento
            if needsBeneRiferimento {
                GlassmorphicTextField(
                    "Bene di riferimento",
                    text: $beneRiferimento,
                    icon: "cube"
                )
                .focused($isBeneFocused)
                .onChange(of: isBeneFocused) { focused in
                    isEditingTextField = focused
                }
                .onChange(of: beneRiferimento) { newValue in
                    saveBeneDebounced(text: newValue)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GlassmorphismDesignSystem.Colors.tertiaryGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tag.tagColor.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            loadExistingValues()
        }
        .onChange(of: filePath) { _ in
            loadExistingValues()
        }
    }
    
    private func getPlaceholder() -> String {
        switch tag.id {
        case "foto_bene": return "Es: Lavatrice, Frigorifero..."
        case "foto_componente": return "Es: Scheda, Inverter..."
        case "foto_ripristino": return "Es: Sostituzione..."
        default: return "Descrizione..."
        }
    }
    
    private func getIcon() -> String {
        switch tag.id {
        case "foto_bene": return "cube"
        case "foto_componente": return "gearshape"
        case "foto_ripristino": return "wrench.and.screwdriver"
        default: return "text.cursor"
        }
    }
    
    private func loadExistingValues() {
        additionalText = fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id) ?? ""
        beneRiferimento = fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id) ?? ""
    }
    
    @State private var saveTask: Task<Void, Never>?
    @State private var saveBeneTask: Task<Void, Never>?
    
    private func saveDebounced(text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            // Usa applyTag per salvare con riconciliazione centralizzata
            var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
            tagData.additionalText = text.isEmpty ? nil : text
            tagData.beneRiferimento = beneRiferimento.isEmpty ? nil : beneRiferimento
            
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
        }
    }
    
    private func saveBeneDebounced(text: String) {
        saveBeneTask?.cancel()
        saveBeneTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            // Usa applyTag per salvare con riconciliazione centralizzata
            var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
            tagData.additionalText = additionalText.isEmpty ? nil : additionalText
            tagData.beneRiferimento = text.isEmpty ? nil : text
            
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
        }
    }
}
