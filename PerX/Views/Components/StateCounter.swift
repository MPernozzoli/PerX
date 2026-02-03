import SwiftUI

struct StateCounter: View {
    let sinistri: FetchedResults<Sinistro>
    
    var body: some View {
        HStack(spacing: 16) {
            countView(for: "Da Scaricare", color: .orange)
            countView(for: "In Gestione", color: .blue)
            countView(for: "Atto Inviato", color: .purple)
            countView(for: "Chiuso", color: .green)
            countView(for: "Revocato", color: .red)
        }
    }
    
    private func countView(for stato: String, color: Color) -> some View {
        let count = sinistri.filter { $0.stato == stato }.count
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(stato)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
} 