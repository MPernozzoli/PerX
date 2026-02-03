import SwiftUI

struct DannoAccertatoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var sinistro: Sinistro
    @State private var importo: String = ""
    
    init(sinistro: Sinistro) {
        self.sinistro = sinistro
        _importo = State(initialValue: sinistro.dannoAccertato?.stringValue ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Danno accertato", text: $importo)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: importo) { newValue in
                            // Permetti solo numeri e virgola
                            let filtered = newValue.filter { "0123456789,".contains($0) }
                            if filtered != newValue {
                                importo = filtered
                            }
                        }
                }
                
                if sinistro.dannoAccertato != nil {
                    Section {
                        Button("Rimuovi importo") {
                            sinistro.dannoAccertato = nil
                            try? viewContext.save()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .frame(minWidth: 300)
            .navigationTitle("Danno Accertato")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveDannoAccertato()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveDannoAccertato() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.numberStyle = .decimal
        
        if let number = formatter.number(from: importo.replacingOccurrences(of: ",", with: ".")) {
            sinistro.dannoAccertato = NSDecimalNumber(value: number.doubleValue)
            try? viewContext.save()
        }
    }
} 