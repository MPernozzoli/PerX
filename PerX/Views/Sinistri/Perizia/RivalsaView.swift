import SwiftUI
import CoreData

struct RivalsaView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    @State private var nota: String = ""
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Rivalsa")
                        .font(.headline)
                    Spacer()
                    Toggle("Presente", isOn: Binding(
                        get: { perizia.rivalsaPresente },
                        set: { 
                            perizia.rivalsaPresente = $0
                            try? viewContext.save()
                        }
                    ))
                }
                
                if perizia.rivalsaPresente {
                    TextField("Nota rivalsa", text: Binding(
                        get: { perizia.rivalsaNota ?? "" },
                        set: { 
                            perizia.rivalsaNota = $0.isEmpty ? nil : $0
                            try? viewContext.save()
                        }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
}

