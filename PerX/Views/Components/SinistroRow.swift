import SwiftUI

struct SinistroRow: View {
    let sinistro: Sinistro
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sinistro.riferimentoVisualizzato)
                    .fontWeight(.medium)
                Text(sinistro.nomeAssicurato ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stato del sinistro
            if let stato = sinistro.stato {
                Text(stato)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
} 