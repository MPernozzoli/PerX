import SwiftUI
import CoreData

struct SinistriTable: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default)
    private var sinistri: FetchedResults<Sinistro>
    
    var body: some View {
        Table(sinistri) {
            TableColumn("Riferimento") { sinistro in
                Text(sinistro.riferimentoVisualizzato)
            }
            TableColumn("Stato") { sinistro in
                Text(sinistro.stato ?? "")
            }
            TableColumn("Assicurato") { sinistro in
                Text(sinistro.nomeAssicurato ?? "")
            }
            TableColumn("Richiesta") { sinistro in
                if let richiesta = sinistro.richiesta?.doubleValue {
                    Text(CurrencyFormatter.shared.formatWithSymbol(richiesta))
                } else {
                    Text("-")
                }
            }
            TableColumn("Liquidato") { sinistro in
                if let liquidato = sinistro.liquidato?.doubleValue {
                    Text(CurrencyFormatter.shared.formatWithSymbol(liquidato))
                } else {
                    Text("-")
                }
            }
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.shared.format(value)
    }
} 