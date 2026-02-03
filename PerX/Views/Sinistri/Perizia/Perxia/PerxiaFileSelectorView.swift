import SwiftUI

struct PerxiaFileSelectorView: View {
    @Binding var files: [URL]
    @State private var showingImporter = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("File da analizzare")
                    .font(.headline)
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label("Aggiungi", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            
            if files.isEmpty {
                Text("Nessun file selezionato")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                List {
                    ForEach(files, id: \.self) { url in
                        HStack {
                            Image(systemName: icon(for: url))
                            Text(url.lastPathComponent)
                            Spacer()
                            Text(url.deletingLastPathComponent().lastPathComponent)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .onDelete { indexSet in
                        files.remove(atOffsets: indexSet)
                    }
                }
                .frame(minHeight: 150, maxHeight: 250)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                files.append(contentsOf: urls)
            case .failure:
                break
            }
        }
    }
    
    private func icon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext" }
        return "photo"
    }
}

