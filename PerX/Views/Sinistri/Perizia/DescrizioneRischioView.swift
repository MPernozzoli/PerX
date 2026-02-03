import SwiftUI
import CoreData

struct DescrizioneRischioView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    private let aiService = AppleIntelligenceService.shared
    @State private var isGenerating = false
    
    private let strutturePortanti = ["Calcestruzzo", "Legno", "Muratura Portante"]
    private let tamponamenti = ["Laterizio", "Pennelli Metallici", "Legno"]
    private let orditureTetto = ["Calcestruzzo", "Legno", "Metallo", "Prefabbricati"]
    private let coperture = ["Tegole", "Pennelli Metallici"]
    private let finiture = ["Standard", "Economiche", "Di Pregio"]
    private let condizioniRischio = ["BUONO", "NORMALE", "MEDIOCRE", "PESSIMO"]
    private let rischi = ["Conforme", "Non Conforme"]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preesistenza e Descrizione del Rischio")
                    .font(.headline)
                
                HStack(alignment: .top, spacing: 20) {
                    // Colonna sinistra: Campi
                    VStack(alignment: .leading, spacing: 16) {
                        // Struttura Portante
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Struttura Portante")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(strutturePortanti, id: \.self) { struttura in
                                    Button {
                                        perizia.strutturaPortante = struttura
                                        try? viewContext.save()
                                    } label: {
                                        Text(struttura)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.strutturaPortante == struttura ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Tamponamenti
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tamponamenti")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(tamponamenti, id: \.self) { tamponamento in
                                    Button {
                                        perizia.tamponamenti = tamponamento
                                        try? viewContext.save()
                                    } label: {
                                        Text(tamponamento)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.tamponamenti == tamponamento ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Orditura Tetto
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Orditura Tetto")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(orditureTetto, id: \.self) { orditura in
                                    Button {
                                        perizia.ordituraTetto = orditura
                                        try? viewContext.save()
                                    } label: {
                                        Text(orditura)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.ordituraTetto == orditura ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Copertura
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Copertura")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(coperture, id: \.self) { copertura in
                                    Button {
                                        perizia.copertura = copertura
                                        try? viewContext.save()
                                    } label: {
                                        Text(copertura)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.copertura == copertura ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Finiture
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Finiture")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(finiture, id: \.self) { finitura in
                                    Button {
                                        perizia.finiture = finitura
                                        try? viewContext.save()
                                    } label: {
                                        Text(finitura)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.finiture == finitura ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Condizione Rischio
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Condizione Rischio")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(condizioniRischio, id: \.self) { condizione in
                                    Button {
                                        perizia.condizioneRischio = condizione
                                        try? viewContext.save()
                                    } label: {
                                        Text(condizione)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.condizioneRischio == condizione ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Rischio
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rischio")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(rischi, id: \.self) { rischio in
                                    Button {
                                        perizia.rischio = rischio
                                        try? viewContext.save()
                                    } label: {
                                        Text(rischio)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(perizia.rischio == rischio ? .blue : .secondary)
                                    .controlSize(.small)
                                }
                            }
                        }
                        
                        // Numero piani
                        HStack {
                            Text("Numero piani:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { Int(perizia.numeroPiani) },
                                set: { 
                                    perizia.numeroPiani = Int16($0)
                                    try? viewContext.save()
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        }
                        
                        // Anno costruzione
                        HStack {
                            Text("Anno costruzione:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("", value: Binding(
                                get: { Int(perizia.annoCostruzione) },
                                set: { 
                                    perizia.annoCostruzione = Int16($0)
                                    try? viewContext.save()
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        }
                        
                        // Deprezzamento
                        HStack {
                            Text("Deprezzamento fabbricato:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("10", value: Binding(
                                get: { perizia.deprezzamentoFabbricato?.doubleValue ?? 10 },
                                set: { perizia.deprezzamentoFabbricato = NSDecimalNumber(value: $0) }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            Text("%")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Colonna destra: Rappresentazione 2D
                    VStack {
                        Fabbricato2DView(
                            strutturaPortante: perizia.strutturaPortante,
                            tamponamenti: perizia.tamponamenti,
                            ordituraTetto: perizia.ordituraTetto,
                            copertura: perizia.copertura
                        )
                        .frame(width: 200, height: 200)
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // Descrizione generata
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Descrizione del Rischio")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            generateDescription()
                        } label: {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Label("Genera Descrizione", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)
                    }
                    
                    if let descrizione = perizia.descrizioneRischio, !descrizione.isEmpty {
                        Text(descrizione)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    } else {
                        Text("Nessuna descrizione generata")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(8)
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
    
    private func generateDescription() {
        isGenerating = true
        
        Task {
            var prompt = "Genera una descrizione tecnica del fabbricato assicurato con le seguenti caratteristiche:\n"
            
            if let struttura = perizia.strutturaPortante {
                prompt += "- Struttura portante: \(struttura)\n"
            }
            if let tamponamenti = perizia.tamponamenti {
                prompt += "- Tamponamenti: \(tamponamenti)\n"
            }
            if let orditura = perizia.ordituraTetto {
                prompt += "- Orditura tetto: \(orditura)\n"
            }
            if let copertura = perizia.copertura {
                prompt += "- Copertura: \(copertura)\n"
            }
            if let finiture = perizia.finiture {
                prompt += "- Finiture: \(finiture)\n"
            }
            if let condizione = perizia.condizioneRischio {
                prompt += "- Condizione rischio: \(condizione)\n"
            }
            if let rischio = perizia.rischio {
                prompt += "- Rischio: \(rischio)\n"
            }
            
            // Usa Apple Intelligence per generare la descrizione
            if let descrizione = await aiService.improveEmailText(subject: "Descrizione Fabbricato", body: prompt) {
                await MainActor.run {
                    perizia.descrizioneRischio = descrizione
                    try? viewContext.save()
                    isGenerating = false
                }
            } else {
                // Fallback: descrizione base
                await MainActor.run {
                    perizia.descrizioneRischio = prompt
                    try? viewContext.save()
                    isGenerating = false
                }
            }
        }
    }
}

// Rappresentazione 2D stilizzata del fabbricato
struct Fabbricato2DView: View {
    let strutturaPortante: String?
    let tamponamenti: String?
    let ordituraTetto: String?
    let copertura: String?
    
    var body: some View {
        ZStack {
            // Sfondo
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.95),
                            Color(white: 0.9)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.1), radius: 5, x: 2, y: 2)
            
            // Rappresentazione stilizzata
            VStack(spacing: 0) {
                // Tetto
                ZStack {
                    // Tetto principale
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 40))
                        path.addLine(to: CGPoint(x: 100, y: 0))
                        path.addLine(to: CGPoint(x: 200, y: 40))
                        path.addLine(to: CGPoint(x: 200, y: 60))
                        path.addLine(to: CGPoint(x: 0, y: 60))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.6, green: 0.4, blue: 0.3),
                                Color(red: 0.5, green: 0.3, blue: 0.2)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    
                    // Tegole/linee
                    if copertura == "Tegole" {
                        ForEach(0..<5) { i in
                            Path { path in
                                let x = CGFloat(i * 40 + 20)
                                path.move(to: CGPoint(x: x, y: 20))
                                path.addLine(to: CGPoint(x: x + 20, y: 10))
                            }
                            .stroke(Color(red: 0.4, green: 0.2, blue: 0.1), lineWidth: 1)
                        }
                    }
                }
                .frame(height: 60)
                
                // Fabbricato
                ZStack {
                    // Pareti
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(white: 0.85),
                                    Color(white: 0.75)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 0)
                    
                    // Finestre
                    HStack(spacing: 30) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 25, height: 30)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 25, height: 30)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)
                    }
                }
                .frame(height: 140)
            }
            .padding(10)
        }
    }
}

