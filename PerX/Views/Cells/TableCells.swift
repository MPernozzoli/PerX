import SwiftUI
import CoreData

struct RiferimentoCell: View {
    let sinistro: Sinistro
    
    var body: some View {
        Text(sinistro.riferimentoVisualizzato)
            .contextMenu {
                Button("Copia Riferimento") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sinistro.riferimento ?? "", forType: .string)
                }
            }
    }
}

struct StatoCell: View {
    let sinistro: Sinistro
    let options: [String]
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        Picker("Stato", selection: Binding(
            get: { sinistro.stato ?? "In Gestione" },
            set: { newValue in
                sinistro.stato = newValue
                try? viewContext.save()
            }
        )) {
            ForEach(options, id: \.self) { stato in
                Text(stato).tag(stato)
            }
        }
    }
}

struct DataCell: View {
    let date: Date?
    
    var body: some View {
        if let date = date {
            Text(date, style: .date)
        } else {
            Text("-")
        }
    }
}

struct RichiestaCell: View {
    let richiesta: NSDecimalNumber?
    
    var body: some View {
        if let richiesta = richiesta {
            Text("€ \(richiesta.stringValue)")
                .foregroundColor(.secondary)
        } else {
            Text("€ 0,00")
                .foregroundColor(.secondary)
        }
    }
} 