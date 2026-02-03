import SwiftUI
import CoreData

struct CollegaSinistriView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let sinistroAttuale: Sinistro
    let onSelect: (Sinistro) -> Void
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Collega Sinistro")
                .font(.title2)
                .padding(.top)
            
            TextField("Cerca sinistro...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            if searchText.isEmpty {
                List {
                    // Sinistri Recenti (tab aperte)
                    if !appState.openTabs.isEmpty {
                        Section("Sinistri Recenti") {
                            ForEach(appState.openTabs.map { $0.sinistro }
                                .filter { $0.riferimento != sinistroAttuale.riferimento }, id: \.self) { sinistro in
                                SinistroRow(sinistro: sinistro) {
                                    onSelect(sinistro)
                                }
                            }
                        }
                    }
                    
                    // Sinistri Correlati (stesso assicurato)
                    if !sinistriCorrelati.isEmpty {
                        Section("Sinistri Correlati") {
                            ForEach(sinistriCorrelati, id: \.self) { sinistro in
                                SinistroRow(sinistro: sinistro) {
                                    onSelect(sinistro)
                                }
                            }
                        }
                    }
                }
            } else {
                List {
                    ForEach(filteredSinistri, id: \.self) { sinistro in
                        SinistroRow(sinistro: sinistro) {
                            onSelect(sinistro)
                        }
                    }
                }
            }
            
            Button("Annulla") {
                dismiss()
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
    
    private var sinistriCorrelati: [Sinistro] {
        guard let nomeAssicurato = sinistroAttuale.nomeAssicurato, !nomeAssicurato.isEmpty else { return [] }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "nomeAssicurato == %@ AND riferimento != %@ AND NOT (riferimento IN %@)",
                                      nomeAssicurato,
                                      sinistroAttuale.riferimento ?? "",
                                      Array(sinistroAttuale.collegamentiSet))
        return (try? viewContext.fetch(request)) ?? []
    }
    
    private var filteredSinistri: [Sinistro] {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        var predicates: [NSPredicate] = []
        
        // Escludi il sinistro corrente e quelli già collegati
        predicates.append(NSPredicate(format: "riferimento != %@ AND NOT (riferimento IN %@)",
                                    sinistroAttuale.riferimento ?? "",
                                    Array(sinistroAttuale.collegamentiSet)))
        
        // Filtra per testo di ricerca
        predicates.append(NSPredicate(format: "riferimento CONTAINS[cd] %@ OR nomeAssicurato CONTAINS[cd] %@",
                                    searchText, searchText))
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return (try? viewContext.fetch(request)) ?? []
    }
} 