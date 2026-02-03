import SwiftUI

struct NoResultsView: View {
    let searchInFilteredOnly: Bool
    let onToggleSearch: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            if searchInFilteredOnly {
                Text("Nessun risultato negli stati filtrati")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Button {
                    onToggleSearch()
                } label: {
                    HStack {
                        Image(systemName: "eye")
                        Text("Attiva ricerca avanzata")
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Nessun risultato trovato")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Prova a modificare i termini di ricerca")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 