import SwiftUI

struct FileTagPopover: View {
    let url: URL
    let sinistroPath: String?
    @StateObject private var fileTagManager = FileTagManager.shared
    @State private var expandedCategories: Set<FileTagManager.FileTag.TagCategory?> = [.foto]
    @State private var editingTagId: String?
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    init(url: URL, sinistroPath: String? = nil) {
        self.url = url
        self.sinistroPath = sinistroPath
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Tag")
                    .font(.headline)
                Spacer()
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Lista tag organizzati per categoria (unificati per UI)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Tag senza categoria
                    if let noCategoryTags = FileTagManager.FileTag.unifiedTagsByCategory()[nil], !noCategoryTags.isEmpty {
                        TagSection(
                            tags: noCategoryTags,
                            filePath: url.path,
                            sinistroPath: sinistroPath,
                            fileTagManager: fileTagManager,
                            editingTagId: $editingTagId,
                            editingText: $editingText,
                            isTextFieldFocused: _isTextFieldFocused
                        )
                    }
                    
                    // Categoria Foto
                    if let fotoTags = FileTagManager.FileTag.unifiedTagsByCategory()[.foto], !fotoTags.isEmpty {
                        CategorySection(
                            category: .foto,
                            tags: fotoTags,
                            filePath: url.path,
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
        .padding()
        .frame(width: 320)
    }
}

struct CategorySection: View {
    let category: FileTagManager.FileTag.TagCategory
    let tags: [FileTagManager.FileTag]
    let filePath: String
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
                withAnimation {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                TagSection(
                    tags: tags,
                    filePath: filePath,
                    sinistroPath: sinistroPath,
                    fileTagManager: fileTagManager,
                    editingTagId: $editingTagId,
                    editingText: $editingText,
                    isTextFieldFocused: _isTextFieldFocused
                )
                .padding(.leading, 20)
            }
        }
    }
}

struct TagSection: View {
    let tags: [FileTagManager.FileTag]
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags) { tag in
                TagRow(
                    tag: tag,
                    filePath: filePath,
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

struct TagRow: View {
    let tag: FileTagManager.FileTag
    let filePath: String
    let sinistroPath: String?
    @ObservedObject var fileTagManager: FileTagManager
    @Binding var editingTagId: String?
    @Binding var editingText: String
    @FocusState var isTextFieldFocused: Bool
    
    @State private var attoSottotipo: String = ""
    @State private var attoStato: String = ""
    @State private var giustificativiTipo: String = ""
    @State private var fulminazioneSottotipo: String = ""
    @State private var allegatiAttoSottotipo: String = ""
    @State private var selectedBene: String = ""
    
    var isSelected: Bool {
        // Per tag unificati, verifica se uno dei tag sottostanti è presente
        if tag.id == "atto" {
            let tags = fileTagManager.getTagsForFile(at: filePath)
            return tags.contains(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })
        } else if tag.id == "giustificativi" {
            let tags = fileTagManager.getTagsForFile(at: filePath)
            return tags.contains(where: { $0.id == "fattura" || $0.id == "preventivo" })
        } else {
            return fileTagManager.getTagsForFile(at: filePath).contains(tag)
        }
    }
    
    var currentAdditionalText: String {
        fileTagManager.getAdditionalText(forFile: filePath, tagId: tag.id) ?? ""
    }
    
    var isEditing: Bool {
        editingTagId == tag.id
    }
    
    @State private var availableBeni: [String] = []
    
    private func loadAvailableBeni() {
        guard let path = sinistroPath else { return }
        Task { @MainActor in
            availableBeni = await ClosureFilesService.shared.getTaggedBeni(inSinistroPath: path)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleTag()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? tag.tagColor : .secondary)
                            .font(.system(size: 14))
                        
                        Text(tag.name)
                            .font(.system(size: 13))
                            .foregroundColor(isSelected ? tag.tagColor : .primary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            // Campo testo aggiuntivo per tag che lo richiedono
            if isSelected && tag.requiresAdditionalText {
                if isEditing {
                    HStack(spacing: 6) {
                        TextField(placeholderForTag(tag), text: $editingText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                saveAdditionalText()
                            }
                        
                        Button {
                            saveAdditionalText()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            cancelEditing()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 20)
                } else {
                    HStack(spacing: 6) {
                        if !currentAdditionalText.isEmpty {
                            Text(currentAdditionalText)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tag.tagColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Button {
                            startEditing()
                        } label: {
                            Image(systemName: currentAdditionalText.isEmpty ? "plus.circle" : "pencil.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 20)
                }
            }
            
            // Opzioni per tag atto unificato
            if isSelected && tag.id == "atto" {
                HStack(spacing: 6) {
                    Text("Stato:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $attoStato) {
                        Text("--").tag("")
                        Text("Firmato").tag("firmato")
                        Text("Da Firmare").tag("da_firmare")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    .onChange(of: attoStato) { newValue in
                        fileTagManager.setAttoStato(newValue.isEmpty ? nil : newValue, forFile: filePath)
                    }
                }
                .padding(.leading, 20)
                
                HStack(spacing: 6) {
                    Text("Tipo:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $attoSottotipo) {
                        Text("--").tag("")
                        Text("Liquidazione").tag("liquidazione")
                        Text("Accertamento").tag("accertamento")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    .onChange(of: attoSottotipo) { newValue in
                        // Ottieni il tag atto corrente per passare il tagId corretto
                        let tags = fileTagManager.getTagsForFile(at: filePath)
                        let attoTagId = tags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })?.id ?? "atto_da_firmare"
                        fileTagManager.setAttoSottotipo(newValue.isEmpty ? nil : newValue, forFile: filePath, tagId: attoTagId)
                    }
                }
                .padding(.leading, 20)
            }
            
            // Tipo giustificativi unificato
            if isSelected && tag.id == "giustificativi" {
                HStack(spacing: 6) {
                    Text("Tipo:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $giustificativiTipo) {
                        Text("--").tag("")
                        Text("Fattura").tag("fattura")
                        Text("Preventivo").tag("preventivo")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    .onChange(of: giustificativiTipo) { newValue in
                        fileTagManager.setGiustificativiTipo(newValue.isEmpty ? nil : newValue, forFile: filePath)
                    }
                }
                .padding(.leading, 20)
            }
            
            // Sottotipo fulminazione
            if isSelected && FileTagManager.FileTag.fulminazioneTags.contains(tag.id) {
                HStack(spacing: 6) {
                    Text("Esito:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $fulminazioneSottotipo) {
                        Text("--").tag("")
                        Text("Positiva").tag("positiva")
                        Text("Negativa").tag("negativa")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    .onChange(of: fulminazioneSottotipo) { newValue in
                        fileTagManager.setFulminazioneSottotipo(newValue.isEmpty ? nil : newValue, forFile: filePath, tagId: tag.id)
                        
                        // Aggiorna il campo fulminazione del sinistro
                        fileTagManager.updateSinistroFulminazioneIfNeeded(forFile: filePath)
                    }
                }
                .padding(.leading, 20)
            }
            
            // Sottotipo allegati atto
            if isSelected && FileTagManager.FileTag.allegatiAttoTags.contains(tag.id) {
                HStack(spacing: 6) {
                    Text("Tipo:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $allegatiAttoSottotipo) {
                        Text("--").tag("")
                        Text("Accettazione").tag("accettazione")
                        Text("IBAN").tag("iban")
                        Text("Delega").tag("delega")
                        Text("Documenti").tag("documenti")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    .onChange(of: allegatiAttoSottotipo) { newValue in
                        Task { @MainActor in
                            await fileTagManager.setAllegatiAttoSottotipo(newValue.isEmpty ? nil : newValue, forFile: filePath, tagId: tag.id)
                        }
                    }
                }
                .padding(.leading, 20)
            }
            
            // Bene di riferimento (per componente, test funzionali, test strumentali)
            if isSelected && FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                HStack(spacing: 6) {
                    Text("Bene:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if availableBeni.isEmpty {
                        TextField("Es: gruppo di continuità", text: $selectedBene)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 150, maxWidth: 200)
                            .font(.caption)
                            .onChange(of: selectedBene) { newValue in
                                fileTagManager.setBeneRiferimento(newValue.isEmpty ? nil : newValue, forFile: filePath, tagId: tag.id)
                            }
                    } else {
                        Picker("", selection: $selectedBene) {
                            Text("--").tag("")
                            ForEach(availableBeni, id: \.self) { bene in
                                Text(bene).tag(bene)
                            }
                        }
                        .frame(maxWidth: 120)
                        .onChange(of: selectedBene) { newValue in
                            fileTagManager.setBeneRiferimento(newValue.isEmpty ? nil : newValue, forFile: filePath, tagId: tag.id)
                        }
                    }
                }
                .padding(.leading, 20)
            }
            
            // Toggle "Da allegare" per tag selezionati
            if isSelected {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Toggle("Da allegare in chiusura", isOn: Binding(
                        get: {
                            // Per tag unificati, verifica sui tag sottostanti
                            if tag.id == "atto" {
                                let tags = fileTagManager.getTagsForFile(at: filePath)
                                let attoTagId = tags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })?.id
                                return attoTagId.flatMap { fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: $0) } ?? false
                            } else if tag.id == "giustificativi" {
                                let tags = fileTagManager.getTagsForFile(at: filePath)
                                let giustTagId = tags.first(where: { $0.id == "fattura" || $0.id == "preventivo" })?.id
                                return giustTagId.flatMap { fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: $0) } ?? false
                            } else {
                                return fileTagManager.getDaAllegareInChiusura(forFile: filePath, tagId: tag.id)
                            }
                        },
                        set: { newValue in
                            // Per tag unificati, imposta sui tag sottostanti
                            if tag.id == "atto" {
                                let tags = fileTagManager.getTagsForFile(at: filePath)
                                let attoTagId = tags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })?.id ?? "atto_da_firmare"
                                fileTagManager.setDaAllegareInChiusura(newValue, forFile: filePath, tagId: attoTagId)
                            } else if tag.id == "giustificativi" {
                                let tags = fileTagManager.getTagsForFile(at: filePath)
                                let giustTagId = tags.first(where: { $0.id == "fattura" || $0.id == "preventivo" })?.id ?? "fattura"
                                fileTagManager.setDaAllegareInChiusura(newValue, forFile: filePath, tagId: giustTagId)
                            } else {
                                fileTagManager.setDaAllegareInChiusura(newValue, forFile: filePath, tagId: tag.id)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .task {
            loadAvailableBeni()
        }
        .onAppear {
            loadExistingValues()
        }
    }
    
    private func loadExistingValues() {
        Task { @MainActor in
            // Per tag unificati, carica dai tag sottostanti
            if tag.id == "atto" {
                attoStato = await fileTagManager.getAttoStato(forFile: filePath) ?? ""
                let tags = await fileTagManager.getTagsForFile(at: filePath)
                let attoTagId = tags.first(where: { $0.id == "atto_da_firmare" || $0.id == "atto_firmato" })?.id
                if let attoTagId = attoTagId {
                    attoSottotipo = await fileTagManager.getAttoSottotipo(forFile: filePath, tagId: attoTagId) ?? ""
                }
            } else if tag.id == "giustificativi" {
                giustificativiTipo = await fileTagManager.getGiustificativiTipo(forFile: filePath) ?? ""
            } else {
                attoSottotipo = await fileTagManager.getAttoSottotipo(forFile: filePath, tagId: tag.id) ?? ""
                fulminazioneSottotipo = await fileTagManager.getFulminazioneSottotipo(forFile: filePath, tagId: tag.id) ?? ""
                allegatiAttoSottotipo = await fileTagManager.getAllegatiAttoSottotipo(forFile: filePath, tagId: tag.id) ?? ""
                selectedBene = await fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id) ?? ""
            }
        }
    }
    
    private func toggleTag() {
        Task { @MainActor in
            if isSelected {
                // RIMOZIONE - usa removeCurrentTag per rimuovere tutti i tag
                fileTagManager.removeCurrentTag(fromFile: filePath)
                
                if isEditing {
                    cancelEditing()
                }
                
                // Reset stato locale
                attoStato = ""
                attoSottotipo = ""
                giustificativiTipo = ""
                fulminazioneSottotipo = ""
                allegatiAttoSottotipo = ""
                selectedBene = ""
            } else {
                // AGGIUNTA - usa applyTag con TagApplicationData
                var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
                
                // Imposta valori di default per tag unificati
                if tag.id == "atto" {
                    if attoStato.isEmpty {
                        attoStato = "da_firmare"
                    }
                    tagData.attoStato = attoStato
                } else if tag.id == "giustificativi" {
                    if giustificativiTipo.isEmpty {
                        giustificativiTipo = "fattura"
                    }
                    tagData.giustificativiTipo = giustificativiTipo
                }
                
                // Applica il tag usando il sistema centralizzato
                await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
                
                if tag.requiresAdditionalText {
                    startEditing()
                }
            }
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
        // Usa applyTag per salvare con riconciliazione
        var tagData = FileTagManager.TagApplicationData(tagId: tag.id)
        tagData.additionalText = editingText.isEmpty ? nil : editingText
        tagData.beneRiferimento = selectedBene.isEmpty ? nil : selectedBene
        tagData.attoStato = attoStato.isEmpty ? nil : attoStato
        tagData.attoSottotipo = attoSottotipo.isEmpty ? nil : attoSottotipo
        tagData.giustificativiTipo = giustificativiTipo.isEmpty ? nil : giustificativiTipo
        tagData.fulminazioneSottotipo = fulminazioneSottotipo.isEmpty ? nil : fulminazioneSottotipo
        tagData.allegatiAttoSottotipo = allegatiAttoSottotipo.isEmpty ? nil : allegatiAttoSottotipo
        
        Task {
            await fileTagManager.applyTag(tagData, toFile: filePath, sinistroPath: sinistroPath)
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
            return "Es: scheda, circolatore, encoder..."
        case "foto_ripristino":
            return "Es: caldaia, televisore..."
        default:
            return "Inserisci testo..."
        }
    }
}

