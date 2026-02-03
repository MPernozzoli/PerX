import SwiftUI

struct PerxiaBeneCardView: View {
    struct Field {
        let label: String
        let value: String?
        let confidence: Double?
    }
    
    let titolo: String
    let anno: String?
    let fields: [Field]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titolo)
                    .font(.headline)
                    if let anno {
                        Text("Anno: \(anno)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                }
                }
                Spacer()
                }
                
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                if let rendered = renderedValue(for: field.value, confidence: field.confidence) {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(color(for: field.confidence))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(rendered)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                }
            }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }
    
    private func renderedValue(for value: String?, confidence: Double?) -> String? {
        let conf = confidence ?? 1.0
        if conf < 0.6 { return nil }
        return value ?? "Non determinabile"
    }
    
    private func color(for confidence: Double?) -> Color {
        let conf = confidence ?? 1.0
        switch conf {
        case let x where x >= 0.95: return .green
        case let x where x >= 0.85: return .yellow
        case let x where x >= 0.6: return .red
        default: return .clear
        }
    }
}
