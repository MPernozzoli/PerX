import SwiftUI

struct ParametriCalcoloView: View {
    @Binding var deprezzamento: Double
    @Binding var aliquotaIVA: Double
    @Binding var ivaInclusa: Bool
    @Binding var diversiPerRiga: Bool
    @Binding var riconosciIVA: Bool
    
    private let aliquoteIVA = [0.0, 4.0, 10.0, 22.0]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Parametri comuni di calcolo")
                    .font(.headline)
                
                HStack {
                    Text("Deprezzamento:")
                    Spacer()
                    HStack {
                        Button {
                            if deprezzamento >= 5 {
                                deprezzamento -= 5
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.bordered)
                        
                        TextField("", value: $deprezzamento, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                        
                        Text("%")
                        
                        Button {
                            deprezzamento += 5
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Riconosci IVA (sopra i campi IVA)
                HStack {
                    Text("Riconosci IVA:")
                    Spacer()
                    Toggle("", isOn: $riconosciIVA)
                        .toggleStyle(.switch)
                    Text(riconosciIVA ? "IVA inclusa nella liquidazione" : "IVA non riconosciuta")
                        .font(.caption)
                        .foregroundColor(riconosciIVA ? .secondary : .orange)
                }
                
                // Campi IVA (disabilitati se riconosciIVA = false)
                HStack {
                    Text("Aliquota IVA:")
                        .foregroundColor(riconosciIVA ? .primary : .secondary)
                    Spacer()
                    HStack {
                        Button {
                            if let currentIndex = aliquoteIVA.firstIndex(of: aliquotaIVA), currentIndex > 0 {
                                aliquotaIVA = aliquoteIVA[currentIndex - 1]
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!riconosciIVA)
                        
                        Picker("", selection: $aliquotaIVA) {
                            ForEach(aliquoteIVA, id: \.self) { aliquota in
                                Text(aliquota == 0 ? "Nessuna" : "\(Int(aliquota))%").tag(aliquota)
                            }
                        }
                        .frame(width: 100)
                        .disabled(!riconosciIVA)
                        
                        Button {
                            if let currentIndex = aliquoteIVA.firstIndex(of: aliquotaIVA), currentIndex < aliquoteIVA.count - 1 {
                                aliquotaIVA = aliquoteIVA[currentIndex + 1]
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!riconosciIVA)
                        
                        Toggle("IVA già compresa", isOn: $ivaInclusa)
                            .disabled(!riconosciIVA)
                    }
                    .opacity(riconosciIVA ? 1.0 : 0.5)
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
}

