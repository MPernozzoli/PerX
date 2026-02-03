import SwiftUI
import CoreData

struct GaranzieSectionView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isAddingGaranzia = false
    
    private var garanzieArray: [Garanzia] {
        guard let garanzieSet = perizia.garanzie as? Set<Garanzia> else { return [] }
        return Array(garanzieSet).sorted { $0.ordine < $1.ordine }
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Garanzie")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation {
                            isAddingGaranzia.toggle()
                        }
                    } label: {
                        Label(isAddingGaranzia ? "Annulla" : "Aggiungi Garanzia", systemImage: isAddingGaranzia ? "xmark.circle" : "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                if isAddingGaranzia {
                    GaranziaEditBox(perizia: perizia, garanzia: nil, onSave: {
                        withAnimation {
                            isAddingGaranzia = false
                        }
                    })
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if garanzieArray.isEmpty {
                    Text("Nessuna garanzia aggiunta")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(garanzieArray) { garanzia in
                            GaranziaCardView(garanzia: garanzia)
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
}

struct GaranziaCardView: View {
    @ObservedObject var garanzia: Garanzia
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isEditing = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        if isEditing {
            GaranziaEditBox(garanzia: garanzia, onSave: {
                withAnimation {
                    isEditing = false
                }
            })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(garanzia.nomeEditabile)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(garanzia.tipologia)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(CurrencyFormatter.shared.formatWithSymbol(garanzia.massimale))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                
                // Mostra franchigia/scoperto se presenti
                if let franchigia = garanzia.franchigiaMinimo, franchigia.doubleValue > 0 {
                    Text("Franchigia: \(CurrencyFormatter.shared.formatWithSymbol(franchigia.doubleValue))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let scoperto = garanzia.scopertoPercentuale, scoperto.doubleValue > 0 {
                    Text("Scoperto: \(scoperto.doubleValue, specifier: "%.0f")%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            isEditing = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.textBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .alert("Elimina Garanzia", isPresented: $showDeleteAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Elimina", role: .destructive) {
                    deleteGaranzia()
                }
            } message: {
                Text("Sei sicuro di voler eliminare questa garanzia?")
            }
        }
    }
    
    private func deleteGaranzia() {
        viewContext.delete(garanzia)
        try? viewContext.save()
    }
}

struct GaranziaEditBox: View {
    @Environment(\.managedObjectContext) private var viewContext
    let perizia: Perizia?
    let garanzia: Garanzia?
    let onSave: () -> Void
    
    init(perizia: Perizia? = nil, garanzia: Garanzia?, onSave: @escaping () -> Void) {
        self.perizia = perizia ?? garanzia?.perizia
        self.garanzia = garanzia
        self.onSave = onSave
    }
    
    private var periziaToUse: Perizia? {
        return perizia ?? garanzia?.perizia
    }
    
    @State private var tipoGaranzia: String = "Fenomeno Elettrico"
    @State private var nomeFornitoCompagnia: String = ""
    @State private var nomeEditabile: String = ""
    @State private var tipologia: String = "Primo Rischio Assoluto"
    @State private var valorePRA: String = ""
    @State private var massimale: String = ""
    @State private var massimaleUnico: Bool = true
    @State private var scopertoPercentuale: String = ""
    @State private var scopertoMinimo: String = ""
    @State private var scopertoMassimo: String = ""
    @State private var franchigiaMinimo: String = ""
    @State private var franchigiaMassimo: String = ""
    
    private let tipiGaranzia = ["Fenomeno Elettrico", "Mancato Freddo", "Guasti Meccanici ed Elettrici", "Acqua Condotta", "Eventi Atmosferici"]
    private let tipologie = ["Valore Intero", "Primo Rischio Assoluto", "PRA fino a"]
    
    private var hasScoperto: Bool {
        guard let scoperto = scopertoPercentuale.isEmpty ? nil : NSDecimalNumber(string: scopertoPercentuale) else {
            return false
        }
        return scoperto.doubleValue > 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Tipo garanzia")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $tipoGaranzia) {
                        ForEach(tipiGaranzia, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    .frame(width: 250)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Nome compagnia")
                        .frame(width: 120, alignment: .leading)
                    TextField("", text: $nomeFornitoCompagnia)
                        .disabled(true)
                        .frame(width: 200)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Nome editabile")
                        .frame(width: 120, alignment: .leading)
                    TextField("", text: $nomeEditabile)
                        .frame(width: 200)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Tipologia")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $tipologia) {
                        ForEach(tipologie, id: \.self) { tipologia in
                            Text(tipologia).tag(tipologia)
                        }
                    }
                    .frame(width: 200)
                }
                
                if tipologia == "PRA fino a" {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Valore PRA")
                            .frame(width: 120, alignment: .leading)
                        TextField("", text: $valorePRA)
                            .frame(width: 150)
                    }
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Massimale")
                        .frame(width: 120, alignment: .leading)
                    HStack(spacing: 4) {
                        Text("€")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $massimale)
                            .frame(width: 120)
                    }
                    
                    Toggle("Unico per tutte le partite", isOn: $massimaleUnico)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Scoperto (%)")
                        .frame(width: 120, alignment: .leading)
                    TextField("0", text: $scopertoPercentuale)
                        .frame(width: 60)
                    
                    if hasScoperto {
                        Text("Min €")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $scopertoMinimo)
                            .frame(width: 100)
                        Text("Max €")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $scopertoMassimo)
                            .frame(width: 100)
                    }
                }
                
                if !hasScoperto {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Franchigia")
                            .frame(width: 120, alignment: .leading)
                        Text("Min €")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $franchigiaMinimo)
                            .frame(width: 100)
                        Text("Max €")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $franchigiaMassimo)
                            .frame(width: 100)
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Salva") {
                        saveGaranzia()
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
            )
        }
        .onAppear {
            if let garanzia = garanzia {
                loadGaranzia(garanzia)
            } else {
                nomeEditabile = tipoGaranzia
            }
        }
    }
    
    private func loadGaranzia(_ garanzia: Garanzia) {
        tipoGaranzia = garanzia.tipoGaranzia
        nomeFornitoCompagnia = garanzia.nomeFornitoCompagnia ?? ""
        nomeEditabile = garanzia.nomeEditabile
        tipologia = garanzia.tipologia
        valorePRA = garanzia.valorePRA?.stringValue ?? ""
        massimale = garanzia.massimale.stringValue
        massimaleUnico = garanzia.massimaleUnico
        scopertoPercentuale = garanzia.scopertoPercentuale?.stringValue ?? ""
        scopertoMinimo = garanzia.scopertoMinimo?.stringValue ?? ""
        scopertoMassimo = garanzia.scopertoMassimo?.stringValue ?? ""
        franchigiaMinimo = garanzia.franchigiaMinimo?.stringValue ?? ""
        franchigiaMassimo = garanzia.franchigiaMassimo?.stringValue ?? ""
    }
    
    private func saveGaranzia() {
        viewContext.performAndWait {
            let garanziaToSave: Garanzia
            if let existingGaranzia = garanzia {
                garanziaToSave = existingGaranzia
            } else {
                guard let perizia = periziaToUse else { return }
                garanziaToSave = Garanzia(context: viewContext)
                garanziaToSave.id = UUID()
                garanziaToSave.perizia = perizia
                garanziaToSave.ordine = Int16(perizia.garanzieArray.count)
            }
            
            garanziaToSave.tipoGaranzia = tipoGaranzia
            garanziaToSave.nomeFornitoCompagnia = nomeFornitoCompagnia.isEmpty ? nil : nomeFornitoCompagnia
            garanziaToSave.nomeEditabile = nomeEditabile.isEmpty ? tipoGaranzia : nomeEditabile
            garanziaToSave.tipologia = tipologia
            garanziaToSave.valorePRA = (tipologia == "PRA fino a" && !valorePRA.isEmpty) ? NSDecimalNumber(string: valorePRA) : nil
            garanziaToSave.massimale = NSDecimalNumber(string: massimale)
            garanziaToSave.massimaleUnico = massimaleUnico
            
            // Gestione scoperto/franchigia
            let scopertoPerc = scopertoPercentuale.isEmpty ? nil : NSDecimalNumber(string: scopertoPercentuale)
            let hasScoperto = scopertoPerc != nil && scopertoPerc!.doubleValue > 0
            
            if hasScoperto {
                garanziaToSave.scopertoPercentuale = scopertoPerc
                garanziaToSave.scopertoMinimo = scopertoMinimo.isEmpty ? nil : NSDecimalNumber(string: scopertoMinimo)
                garanziaToSave.scopertoMassimo = scopertoMassimo.isEmpty ? nil : NSDecimalNumber(string: scopertoMassimo)
                garanziaToSave.franchigiaMinimo = nil
                garanziaToSave.franchigiaMassimo = nil
            } else {
                garanziaToSave.scopertoPercentuale = nil
                garanziaToSave.scopertoMinimo = nil
                garanziaToSave.scopertoMassimo = nil
                garanziaToSave.franchigiaMinimo = franchigiaMinimo.isEmpty ? nil : NSDecimalNumber(string: franchigiaMinimo)
                garanziaToSave.franchigiaMassimo = franchigiaMassimo.isEmpty ? nil : NSDecimalNumber(string: franchigiaMassimo)
            }
            
            try? viewContext.save()
        }
    }
}
