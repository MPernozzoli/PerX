import SwiftUI
import AppKit

struct PerxiaBeneCompactView: View {
    let bene: PerxiaService.PhiBeniResult.Bene
    let onFeedback: (Bool, String?) -> Void
    
    @State private var showFeedback = false
    @State private var feedbackText = ""
    @State private var showFotoPopover = false
    @State private var fotoPopoverField: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header con nome (più specifico) e certezza nome
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(bene.nome)
                            .font(.headline)
                            .lineLimit(2)
                        
                        if let certezzaNome = bene.certezzaNome {
                            certaintyBadge(certezzaNome, size: .small)
                        }
                    }
                    
                    // Marca, Modello e Anno insieme se disponibili
                    HStack(spacing: 6) {
                        if let marca = bene.marca, !marca.isEmpty {
                            Text(marca)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        if let modello = bene.modello, !modello.isEmpty {
                            if bene.marca?.isEmpty == false {
                                Text("•")
                                    .foregroundColor(.secondary)
                            }
                            Text(modello)
                                .font(.subheadline)
                                .foregroundColor(bene.marca?.isEmpty == false ? .secondary : .primary)
                            
                            if let certezzaModello = bene.certezzaModello {
                                certaintyBadge(certezzaModello, size: .small)
                            }
                        }
                        
                        // Anno: mostra prima anno certo, poi stimato con "(stima)"
                        if let anno = bene.anno, !anno.isEmpty {
                            if (bene.marca?.isEmpty == false) || (bene.modello?.isEmpty == false) {
                                Text("•")
                                    .foregroundColor(.secondary)
                            }
                            Text(anno)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let certezzaAnno = bene.certezzaAnno {
                                certaintyBadge(certezzaAnno, size: .small)
                            }
                        } else if let annoStimato = bene.annoStimato, !annoStimato.isEmpty {
                            if (bene.marca?.isEmpty == false) || (bene.modello?.isEmpty == false) {
                                Text("•")
                                    .foregroundColor(.secondary)
                            }
                            Text("\(annoStimato) (stima)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let certezzaAnno = bene.certezzaAnno {
                                certaintyBadge(certezzaAnno, size: .small)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Feedback buttons
                HStack(spacing: 6) {
                    Button {
                        onFeedback(true, nil)
                    } label: {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Feedback positivo")
                    
                    Button {
                        showFeedback.toggle()
                    } label: {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Feedback negativo")
                }
            }
            
            Divider()
            
            // Dettagli anagrafici
            VStack(alignment: .leading, spacing: 8) {
                // Anno
                if let anno = bene.anno, !anno.isEmpty {
                    infoRowWithFoto(
                        label: "Anno",
                        value: anno,
                        certezza: bene.certezzaAnno,
                        fieldName: "Anno",
                        foto: bene.fonti ?? []
                    )
                } else if let annoStimato = bene.annoStimato, !annoStimato.isEmpty {
                    infoRowWithFoto(
                        label: "Anno",
                        value: "\(annoStimato) (stima)",
                        certezza: bene.certezzaAnno,
                        fieldName: "Anno",
                        foto: bene.fonti ?? []
                    )
                }
                
                // Componenti
                if let componenti = bene.componenti, !componenti.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button {
                                fotoPopoverField = "Componenti"
                                showFotoPopover = true
                            } label: {
                                Text("Componenti:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor((bene.fotoComponenti?.isEmpty == false) ? .blue : .secondary)
                                    .underline((bene.fotoComponenti?.isEmpty == false))
                            }
                            .buttonStyle(.plain)
                            .help("Mostra foto componenti")
                            
                            Spacer()
                            
                            if bene.fotoComponenti?.isEmpty == false {
                                Image(systemName: "photo.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        ForEach(componenti, id: \.self) { componente in
                            Text("• \(componente)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Divider()
            
            // Analisi tecnica
            VStack(alignment: .leading, spacing: 8) {
                // Osservazioni
                if let osservazioni = bene.osservazioni, !osservazioni.isEmpty,
                   let certezza = bene.certezzaOsservazioni, certezza >= 0.5 {
                    infoRowWithFoto(
                        label: "Osservazioni",
                        value: osservazioni,
                        certezza: certezza,
                        fieldName: "Osservazioni",
                        foto: bene.fotoOsservazioni ?? []
                    )
                }
                
                // Test
                if let test = bene.test, !test.isEmpty,
                   let certezza = bene.certezzaTest, certezza >= 0.5 {
                    infoRowWithFoto(
                        label: "Test",
                        value: test,
                        certezza: certezza,
                        fieldName: "Test",
                        foto: bene.fotoTest ?? []
                    )
                }
                
                // Compatibilità FE (senza foto)
                if let compatibilita = bene.compatibilitaDanno, !compatibilita.isEmpty,
                   let certezza = bene.certezzaCompatibilita, certezza >= 0.5 {
                    infoRowWithFoto(
                        label: "Compatibilità FE",
                        value: compatibilita,
                        certezza: certezza,
                        fieldName: "Compatibilità FE",
                        foto: []  // Nessuna foto per compatibilità
                    )
                }
                
                // Stima
                if let stima = bene.stima, !stima.isEmpty,
                   let certezza = bene.certezzaStima, certezza >= 0.5 {
                    infoRowWithFoto(
                        label: "Stima",
                        value: stima,
                        certezza: certezza,
                        fieldName: "Stima",
                        foto: bene.fonti ?? []
                    )
                }
            }
            
            // Feedback negativo form
            if showFeedback {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    TextField("Motivo feedback negativo...", text: $feedbackText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(3...6)
                    
                    HStack {
                        Button("Invia") {
                            onFeedback(false, feedbackText.isEmpty ? nil : feedbackText)
                            showFeedback = false
                            feedbackText = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Annulla") {
                            showFeedback = false
                            feedbackText = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .popover(isPresented: $showFotoPopover, attachmentAnchor: .point(.top)) {
            fotoPopoverView
        }
    }
    
    private func infoRowWithFoto(
        label: String,
        value: String,
        certezza: Double?,
        fieldName: String,
        foto: [String]
    ) -> some View {
        let hasFoto = !foto.isEmpty
        
        return HStack(alignment: .top, spacing: 6) {
            // Indicatore certezza
            if let certezza = certezza {
                Circle()
                    .fill(color(for: certezza))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 8, height: 8)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Nome campo cliccabile se ci sono foto
                    if hasFoto {
                        Button {
                            fotoPopoverField = fieldName
                            showFotoPopover = true
                        } label: {
                            Text("\(label):")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .help("Clicca per vedere le foto usate per \(fieldName)")
                    } else {
                        Text("\(label):")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    if let certezza = certezza {
                        certaintyBadge(certezza, size: .tiny)
                    }
                    
                    if hasFoto {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                // Valore sempre normale (non cliccabile)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
    
    private var fotoPopoverView: some View {
        // Usa foto specifiche per il campo selezionato
        let fotoSpecifiche: [String]
        switch fotoPopoverField {
        case "Osservazioni":
            fotoSpecifiche = bene.fotoOsservazioni ?? []
        case "Test":
            fotoSpecifiche = bene.fotoTest ?? []
        case "Componenti":
            fotoSpecifiche = bene.fotoComponenti ?? []
        default:
            // Per altri campi usa fonti generali
            fotoSpecifiche = bene.fonti ?? []
        }
        let uniqueFoto = Array(Set(fotoSpecifiche))
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Foto per \(fotoPopoverField ?? "questo dato")")
                .font(.headline)
                .padding(.bottom, 4)
            
            if uniqueFoto.isEmpty {
                Text("Nessuna foto disponibile")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                        ForEach(uniqueFoto, id: \.self) { path in
                            if FileManager.default.fileExists(atPath: path),
                               let image = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                                VStack(spacing: 6) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    Text((path as NSString).lastPathComponent)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 100)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                VStack(spacing: 6) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.1))
                                        .frame(width: 100, height: 100)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.secondary)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    
                                    Text((path as NSString).lastPathComponent)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 100)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding()
        .frame(width: 450)
    }
    
    private enum BadgeSize {
        case tiny, small, medium
    }
    
    private func certaintyBadge(_ certezza: Double, size: BadgeSize = .small) -> some View {
        let fontSize: Font = size == .tiny ? .caption2 : (size == .small ? .caption : .subheadline)
        let padding: CGFloat = size == .tiny ? 2 : (size == .small ? 4 : 6)
        
        return Text(String(format: "%.0f%%", certezza * 100))
            .font(fontSize)
            .fontWeight(.semibold)
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .background(color(for: certezza).opacity(0.2))
            .foregroundColor(color(for: certezza))
            .clipShape(Capsule())
    }
    
    private func color(for confidence: Double) -> Color {
        switch confidence {
        case let x where x >= 0.95: return .green
        case let x where x >= 0.85: return .yellow
        case let x where x >= 0.6: return .orange
        default: return .red
        }
    }
}
