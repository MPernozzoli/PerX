import SwiftUI
import CoreData

struct CollegaSinistroView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sinistro: Sinistro
    @State private var idCollegato = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Collega Sinistro")
                .font(.title2)
                .bold()
            
            TextField("ID Sinistro da collegare", text: $idCollegato)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Collega") {
                    collegaSinistro()
                }
                .keyboardShortcut(.return)
                .disabled(idCollegato.isEmpty)
            }
            
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 300)
    }
    
    private func collegaSinistro() {
        if idCollegato == sinistro.riferimento {
            showError = true
            errorMessage = "Non puoi collegare un sinistro a se stesso"
            return
        }
        
        do {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", idCollegato)
            
            let results = try viewContext.fetch(request)
            
            if let sinistroCollegato = results.first {
                // Aggiorna il sinistro corrente
                var collegamenti1 = sinistro.collegamentiSet
                collegamenti1.insert(sinistroCollegato.riferimento ?? "")
                sinistro.collegamentiSet = collegamenti1
                
                // Aggiorna il sinistro collegato
                var collegamenti2 = sinistroCollegato.collegamentiSet
                collegamenti2.insert(sinistro.riferimento ?? "")
                sinistroCollegato.collegamentiSet = collegamenti2
                
                try viewContext.save()
                
                appState.openSinistro(sinistroCollegato)
                
                dismiss()
            } else {
                showError = true
                errorMessage = "Sinistro non trovato"
            }
        } catch {
            showError = true
            errorMessage = "Errore nel collegamento: \(error.localizedDescription)"
        }
    }
} 