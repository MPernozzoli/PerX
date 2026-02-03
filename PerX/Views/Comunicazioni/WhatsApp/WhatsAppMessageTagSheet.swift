import SwiftUI
import CoreData

/// Sheet per taggare un messaggio WhatsApp e associarlo a sinistri
struct WhatsAppMessageTagSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let message: WhatsAppMessage
    let chatId: String
    
    @StateObject private var tagManager = WhatsAppMessageTagManager.shared
    @State private var selectedTags: Set<WhatsAppMessageTag> = []
    @State private var selectedSinistri: Set<Sinistro> = []
    @State private var searchText = ""
    @State private var note = ""
    @State private var showingSinistroSearch = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: false)],
        predicate: NSPredicate(format: "stato != %@", "Chiuso"),
        animation: .default
    ) private var sinistri: FetchedResults<Sinistro>
    
    private var currentTagData: WhatsAppMessageTagData? {
        tagManager.getTagData(forMessageId: message.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Anteprima messaggio
                    messagePreview
                    
                    // Sezione tag
                    tagSelectionSection
                    
                    // Sezione sinistro
                    sinistroSelectionSection
                    
                    // Note
                    noteSection
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer con azioni
            footerView
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadCurrentState()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tag Messaggio")
                    .font(.headline)
                Text("Categorizza e associa a sinistri")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Message Preview
    
    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Messaggio")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 12) {
                // Icona tipo
                ZStack {
                    Circle()
                        .fill(message.isSent ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: message.isSent ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(message.isSent ? .green : .blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.body)
                        .font(.body)
                        .lineLimit(3)
                    
                    HStack(spacing: 8) {
                        Text(message.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if message.type != .text {
                            Label(message.type.displayName, systemImage: message.type.iconName)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Tag Selection
    
    private var tagSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120), spacing: 8)
            ], spacing: 10) {
                ForEach(WhatsAppMessageTag.allCases) { tag in
                    TagSelectionButton(
                        tag: tag,
                        isSelected: selectedTags.contains(tag),
                        onToggle: {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Sinistro Selection
    
    private var sinistroSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sinistro Associato")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    showingSinistroSearch.toggle()
                } label: {
                    Label(showingSinistroSearch ? "Nascondi" : "Cerca", systemImage: showingSinistroSearch ? "chevron.up" : "magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            // Sinistri selezionati
            if !selectedSinistri.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(selectedSinistri), id: \.objectID) { sinistro in
                        SelectedSinistroRow(sinistro: sinistro) {
                            selectedSinistri.remove(sinistro)
                        }
                    }
                }
            } else if !showingSinistroSearch {
                HStack {
                    Image(systemName: "link.badge.plus")
                        .foregroundColor(.secondary)
                    Text("Nessun sinistro associato")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
            }
            
            // Ricerca sinistro
            if showingSinistroSearch {
                VStack(spacing: 8) {
                    // Barra ricerca
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Cerca per riferimento, nome, numero...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    
                    // Lista sinistri filtrati
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredSinistri) { sinistro in
                                SinistroSearchRow(
                                    sinistro: sinistro,
                                    isSelected: selectedSinistri.contains(sinistro)
                                ) {
                                    if selectedSinistri.contains(sinistro) {
                                        selectedSinistri.remove(sinistro)
                                    } else {
                                        selectedSinistri.insert(sinistro)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Note Section
    
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            TextEditor(text: $note)
                .font(.body)
                .frame(height: 60)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            if currentTagData != nil {
                Button(role: .destructive) {
                    clearAllTags()
                } label: {
                    Text("Rimuovi tutto")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Button("Annulla") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Salva") {
                saveTags()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTags.isEmpty && selectedSinistri.isEmpty && note.isEmpty)
        }
        .padding()
    }
    
    // MARK: - Computed
    
    private var filteredSinistri: [Sinistro] {
        if searchText.isEmpty {
            return Array(sinistri.prefix(20))
        }
        
        return sinistri.filter { sinistro in
            (sinistro.riferimento ?? "").localizedCaseInsensitiveContains(searchText) ||
            (sinistro.nomeAssicurato ?? "").localizedCaseInsensitiveContains(searchText) ||
            (sinistro.nomeContraente ?? "").localizedCaseInsensitiveContains(searchText) ||
            (sinistro.numeroSinistroCompagnia ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - Actions
    
    private func loadCurrentState() {
        if let data = currentTagData {
            selectedTags = data.tags
            note = data.note ?? ""
            
            // Carica sinistro associato
            if let rif = data.sinistroRiferimento,
               let sinistro = sinistri.first(where: { $0.riferimento == rif }) {
                selectedSinistri.insert(sinistro)
            }
        }
    }
    
    private func saveTags() {
        let sinistroRif = selectedSinistri.first?.riferimento
        tagManager.setTags(selectedTags, forMessageId: message.id, sinistroRif: sinistroRif, note: note.isEmpty ? nil : note)
        dismiss()
    }
    
    private func clearAllTags() {
        tagManager.setTags([], forMessageId: message.id, sinistroRif: nil, note: nil)
        dismiss()
    }
}

// MARK: - Supporting Views

private struct TagSelectionButton: View {
    let tag: WhatsAppMessageTag
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: tag.iconName)
                    .font(.system(size: 14))
                Text(tag.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : tag.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? tag.color : tag.color.opacity(0.12))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct SelectedSinistroRow: View {
    let sinistro: Sinistro
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sinistro.riferimentoVisualizzato)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let nome = sinistro.nomeAssicurato, !nome.isEmpty {
                    Text(nome)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
}

private struct SinistroSearchRow: View {
    let sinistro: Sinistro
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sinistro.riferimentoVisualizzato)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        if let nome = sinistro.nomeAssicurato, !nome.isEmpty {
                            Text(nome)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let stato = sinistro.stato {
                            Text(stato)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WhatsAppMediaType Extensions

extension WhatsAppMediaType {
    var displayName: String {
        switch self {
        case .text: return "Testo"
        case .image: return "Immagine"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Documento"
        case .sticker: return "Sticker"
        case .location: return "Posizione"
        case .contact: return "Contatto"
        case .ptt: return "Vocale"
        }
    }
    
    var iconName: String {
        switch self {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .document: return "doc"
        case .sticker: return "face.smiling"
        case .location: return "location"
        case .contact: return "person.crop.circle"
        case .ptt: return "mic"
        }
    }
}
