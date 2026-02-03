import SwiftUI

/// Sezione Compagnia e Agenzia con DisclosureGroup espandibile
struct CompanySectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var isExpanded: Bool
    
    var body: some View {
        GroupBox {
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 16) {
                        // Griglia principale
                        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 16) {
                            // Prima riga - Gruppo e Compagnia
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Gruppo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.gruppo, fieldName: "Gruppo")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Compagnia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.nomeCompagnia, fieldName: "Compagnia")
                                }
                            }
                            
                            // Seconda riga - Area e Divisione
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Area")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.area, fieldName: "Area")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Divisione")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.nomeCompagnia, fieldName: "Divisione")
                                }
                            }
                            
                            // Terza riga - Numero sinistro e Agenzia
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Numero sinistro")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.numeroSinistroCompagnia, fieldName: "Numero sinistro")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Agenzia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        Button {
                                            // Implementare apertura rubrica
                                        } label: {
                                            Image(systemName: "person.crop.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Apri in Rubrica")
                                        
                                        DefaultableText(value: sinistro.agenzia, fieldName: "Nome agenzia")
                                    }
                                }
                            }
                            
                            // Quarta riga - Codice agenzia e Contatti
                            GridRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Codice agenzia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    DefaultableText(value: sinistro.codiceAgenzia, fieldName: "Codice agenzia")
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Contatti agenzia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let telefono = sinistro.telefonoAgenzia, !telefono.isEmpty {
                                            Text("📞 \(telefono)")
                                                .font(.caption)
                                        }
                                        if let email = sinistro.emailAgenzia, !email.isEmpty {
                                            Text("✉️ \(email)")
                                                .font(.caption)
                                        }
                                        if sinistro.telefonoAgenzia?.isEmpty != false && sinistro.emailAgenzia?.isEmpty != false {
                                            Text("Contatti mancanti")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                },
                label: {
                    HStack {
                        Text("Compagnia: \(sinistro.nomeCompagnia ?? sinistro.agenzia?.components(separatedBy: " ").first ?? "Non specificata")")
                            .font(.headline)
                        Spacer()
                        if !isExpanded {
                            let agenziaText = sinistro.agenzia?.isEmpty == false ? sinistro.agenzia! : "Nome agenzia"
                            let codiceText = sinistro.codiceAgenzia?.isEmpty == false ? sinistro.codiceAgenzia! : "Codice"
                            Text("\(agenziaText) - \(codiceText)")
                                .foregroundColor(.secondary)
                                .italic(sinistro.agenzia?.isEmpty != false || sinistro.codiceAgenzia?.isEmpty != false)
                        }
                    }
                }
            )
        }
        .backgroundStyle(.regularMaterial)
    }
}
