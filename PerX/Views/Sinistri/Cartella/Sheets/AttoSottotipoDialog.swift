import SwiftUI

// MARK: - Atto Sottotipo Dialog

struct AttoSottotipoDialog: View {
    let onSelect: (SottotipoAtto?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Tipo di Atto")
                .font(.headline)
            
            Text("Seleziona il tipo di atto per la chiusura:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button {
                    dismiss()
                    onSelect(.liquidazione)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "eurosign.circle.fill")
                            .font(.largeTitle)
                        Text("Liquidazione")
                            .font(.headline)
                    }
                    .frame(width: 120, height: 100)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    dismiss()
                    onSelect(.accertamento)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                        Text("Accertamento")
                            .font(.headline)
                    }
                    .frame(width: 120, height: 100)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            
            Button("Annulla") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(width: 350)
    }
}
