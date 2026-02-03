import SwiftUI
import CoreData

struct ObblighiView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Obblighi dell'assicurato")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Denuncia tardiva
                    HStack {
                        Text("Denuncia tardiva:")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                perizia.denunciaTardiva = true
                                try? viewContext.save()
                            } label: {
                                Text("Si")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(perizia.denunciaTardiva ? .blue : .gray)
                            
                            Button {
                                perizia.denunciaTardiva = false
                                try? viewContext.save()
                            } label: {
                                Text("No")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(!perizia.denunciaTardiva ? .blue : .gray)
                        }
                    }
                    
                    Divider()
                    
                    // Mantenimento residui
                    HStack {
                        Text("Mantenimento residui:")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                perizia.mantenimentoResidui = "Si"
                                try? viewContext.save()
                            } label: {
                                Text("Si")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(perizia.mantenimentoResidui == "Si" ? .blue : .gray)
                            
                            Button {
                                perizia.mantenimentoResidui = "Parziale"
                                try? viewContext.save()
                            } label: {
                                Text("Parziale")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(perizia.mantenimentoResidui == "Parziale" ? .blue : .gray)
                            
                            Button {
                                perizia.mantenimentoResidui = "No"
                                try? viewContext.save()
                            } label: {
                                Text("No")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .tint(perizia.mantenimentoResidui == "No" ? .blue : .gray)
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
}

