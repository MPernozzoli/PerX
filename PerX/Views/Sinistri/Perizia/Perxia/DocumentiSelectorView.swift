import SwiftUI

struct DocumentiSelectorView: View {
    @ObservedObject var sinistro: Sinistro
    @StateObject private var fileTagManager = FileTagManager.shared
    
    @Binding var includeGiustificativi: Bool
    @Binding var includeDenuncia: Bool
    @Binding var fotoSelection: FotoSelection
    @Binding var selectedFoto: Set<URL>
    
    private let fileService = FileService.shared
    
    enum FotoSelection: String, CaseIterable {
        case tutte = "Tutte le foto"
        case perCategoria = "Per categoria"
        case manuale = "Seleziona manualmente"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Documentazione")
                .font(.headline)
            
            // Giustificativi
            Toggle("Giustificativi (preventivi e fatture)", isOn: $includeGiustificativi)
            
            // Denuncia
            Toggle("Denuncia", isOn: $includeDenuncia)
            
            Divider()
            
            // Foto
            VStack(alignment: .leading, spacing: 12) {
                Text("Foto")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Picker("", selection: $fotoSelection) {
                    ForEach(FotoSelection.allCases, id: \.self) { selection in
                        Text(selection.rawValue).tag(selection)
                    }
                }
                .pickerStyle(.segmented)
                
                if fotoSelection == .perCategoria {
                    fotoCategoriaView
                } else if fotoSelection == .manuale {
                    fotoManualeView
                }
            }
        }
    }
    
    @State private var selectedFotoTags: Set<String> = []
    
    private var fotoCategoriaView: some View {
        let fotoTags = FileTagManager.FileTag.availableTags.filter { $0.category == .foto }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(fotoTags, id: \.id) { tag in
                Toggle(isOn: Binding(
                    get: { selectedFotoTags.contains(tag.id) },
                    set: { isOn in
                        if isOn { selectedFotoTags.insert(tag.id) } else { selectedFotoTags.remove(tag.id) }
                    }
                )) {
                    HStack {
                        Circle()
                            .fill(tag.tagColor)
                            .frame(width: 10, height: 10)
                        Text(tag.name)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var fotoManualeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(getAllFoto(), id: \.self) { fotoURL in
                    HStack {
                        Image(systemName: icon(for: fotoURL))
                            .foregroundColor(.secondary)
                        Text(fotoURL.lastPathComponent)
                            .font(.caption)
                        Spacer()
                        let tags = fileTagManager.getTagsForFile(at: fotoURL.path)
                        if !tags.isEmpty {
                            Text(tags.map { $0.name }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { selectedFoto.contains(fotoURL) },
                            set: { isSelected in
                                if isSelected {
                                    selectedFoto.insert(fotoURL)
                                } else {
                                    selectedFoto.remove(fotoURL)
                                }
                            }
                        ))
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.leading, 16)
        }
        .frame(maxHeight: 200)
    }
    
    private func getAllFoto() -> [URL] {
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return [] }
        let extensions = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]
        let files = fileService.listFilesRecursive(inDirectory: cartella, withExtensions: extensions)
        return files
    }
    
    func getSelectedDocumenti() -> [URL] {
        var documenti: [URL] = []
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return documenti }
        
        let files = fileService.listFilesRecursive(inDirectory: cartella)
        
        if includeGiustificativi {
            let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
            let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
            
            for file in files {
                let tags = fileTagManager.getTagsForFile(at: file.path)
                if let preventivoTag = preventivoTag, tags.contains(preventivoTag) {
                    documenti.append(file)
                } else if let fatturaTag = fatturaTag, tags.contains(fatturaTag) {
                    documenti.append(file)
                }
            }
        }
        
        if includeDenuncia {
            let denunciaTag = FileTagManager.FileTag.availableTags.first { $0.id == "denuncia" }
            
            for file in files {
                let tags = fileTagManager.getTagsForFile(at: file.path)
                if let denunciaTag = denunciaTag, tags.contains(denunciaTag) {
                    documenti.append(file)
                }
            }
        }
        
        return documenti
    }
    
    func getSelectedFoto() -> [URL] {
        switch fotoSelection {
        case .tutte:
            return filterMediaForModel(getAllFoto())
            
        case .perCategoria:
            let all = getAllFoto()
            return all.filter { url in
                let tags = fileTagManager.getTagsForFile(at: url.path)
                let ids = Set(tags.map { $0.id })
                return !ids.isDisjoint(with: selectedFotoTags)
            }
            
        case .manuale:
            return filterMediaForModel(Array(selectedFoto))
        }
    }
    
    private func filterMediaForModel(_ urls: [URL]) -> [URL] {
        // Solo immagini: i PDF sono gestiti a parte come documenti selezionati
        return urls.filter { $0.pathExtension.lowercased() != "pdf" }
    }
    
    private func icon(for url: URL) -> String {
        return url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo"
    }
}

