import SwiftUI
import CoreData

struct PartiteSectionView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isAddingPartita = false
    
    private var partiteArray: [Partita] {
        guard let partiteSet = perizia.partite as? Set<Partita> else { return [] }
        return Array(partiteSet).sorted { $0.ordine < $1.ordine }
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Partite")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation {
                            isAddingPartita.toggle()
                        }
                    } label: {
                        Label(isAddingPartita ? "Annulla" : "Aggiungi Partita", systemImage: isAddingPartita ? "xmark.circle" : "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                if isAddingPartita {
                    PartitaEditBox(perizia: perizia, partita: nil, onSave: {
                        withAnimation {
                            isAddingPartita = false
                        }
                    })
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if partiteArray.isEmpty {
                    Text("Nessuna partita aggiunta")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(partiteArray) { partita in
                            PartitaCardView(partita: partita)
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
}

struct PartitaCardView: View {
    @ObservedObject var partita: Partita
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isEditing = false
    @State private var showDeleteAlert = false
    
    private var tagColor: Color {
        switch partita.tipoPartita {
        case "Fabbricato":
            return .blue.opacity(0.2)
        case "Contenuto":
            return .blue.opacity(0.2)
        case "Macchinari":
            return .purple.opacity(0.2)
        case "Impianti solari":
            return .orange.opacity(0.2)
        default:
            return .gray.opacity(0.2)
        }
    }
    
    private var tagText: String {
        switch partita.tipoPartita {
        case "Fabbricato":
            return "FABBRICATO"
        case "Contenuto":
            return "CONTENUTO"
        case "Macchinari":
            return "MACCHINARI"
        case "Impianti solari":
            return "IMPIANTI"
        default:
            return partita.tipoPartita.uppercased()
        }
    }
    
    var body: some View {
        if isEditing {
            PartitaEditBox(partita: partita, onSave: {
                withAnimation {
                    isEditing = false
                }
            })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(partita.nomeEditabile)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(tagText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(tagColor)
                        )
                }
                
                Text(partita.tipologia)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(CurrencyFormatter.shared.formatWithSymbol(calcolaValorePartita(partita)))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                
                if partita.determinazioneDanno != "Valore a nuovo" {
                    Text(partita.determinazioneDanno)
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
            .alert("Elimina Partita", isPresented: $showDeleteAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Elimina", role: .destructive) {
                    deletePartita()
                }
            } message: {
                Text("Sei sicuro di voler eliminare questa partita?")
            }
        }
    }
    
    private func calcolaValorePartita(_ partita: Partita) -> Double {
        let valoreBase = partita.valoreAssicurato.doubleValue
        
        if partita.tipologia == "Valore Intero", let deroga = partita.percentualeDeroga {
            let percentualeDeroga = deroga.doubleValue
            return valoreBase + (valoreBase * percentualeDeroga / 100)
        }
        
        return valoreBase
    }
    
    private func deletePartita() {
        viewContext.delete(partita)
        try? viewContext.save()
    }
}

struct PartitaEditBox: View {
    @Environment(\.managedObjectContext) private var viewContext
    let perizia: Perizia?
    let partita: Partita?
    let onSave: () -> Void
    
    init(perizia: Perizia? = nil, partita: Partita?, onSave: @escaping () -> Void) {
        self.perizia = perizia ?? partita?.perizia
        self.partita = partita
        self.onSave = onSave
    }
    
    private var periziaToUse: Perizia? {
        return perizia ?? partita?.perizia
    }
    
    @State private var tipoPartita: String = "Fabbricato"
    @State private var nomeFornitoCompagnia: String = ""
    @State private var nomeEditabile: String = ""
    @State private var tipologia: String = "Valore Intero"
    @State private var valoreAssicurato: String = ""
    @State private var percentualeDeroga: String = ""
    @State private var determinazioneDanno: String = "Valore a nuovo"
    @State private var regoleSpeciali: String = ""
    
    private let tipiPartita = ["Fabbricato", "Contenuto", "Macchinari", "Impianti solari"]
    private let tipologie = ["Valore Intero", "Primo Rischio Assoluto"]
    private let determinazioniDanno = [
        "Valore a nuovo",
        "Valore allo stato d'uso più supplemento d'indennizzo",
        "VSU + SI (max doppio)",
        "VSU + SI (max triplo)",
        "VSU + SI (max quadruplo)",
        "Valore allo stato d'uso",
        "Regole speciali"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Tipo partita")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $tipoPartita) {
                        ForEach(tipiPartita, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    .frame(width: 200)
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
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Valore assicurato")
                        .frame(width: 120, alignment: .leading)
                    HStack(spacing: 4) {
                        Text("€")
                            .foregroundColor(.secondary)
                        TextField("0,00", text: $valoreAssicurato)
                            .frame(width: 130)
                    }
                    
                    if tipologia == "Valore Intero" {
                        Text("Deroga (%)")
                            .frame(width: 80, alignment: .leading)
                        TextField("0", text: $percentualeDeroga)
                            .frame(width: 50)
                    }
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("Determinazione danno")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $determinazioneDanno) {
                        ForEach(determinazioniDanno, id: \.self) { det in
                            Text(det).tag(det)
                        }
                    }
                    .frame(width: 300)
                }
                
                if determinazioneDanno == "Regole speciali" {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Regole speciali")
                            .frame(width: 120, alignment: .leading)
                        TextField("", text: $regoleSpeciali, axis: .vertical)
                            .lineLimit(3...6)
                            .frame(width: 300)
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Salva") {
                        savePartita()
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
            if let partita = partita {
                loadPartita(partita)
            } else {
                nomeEditabile = tipoPartita
            }
        }
    }
    
    private func loadPartita(_ partita: Partita) {
        tipoPartita = partita.tipoPartita
        nomeFornitoCompagnia = partita.nomeFornitoCompagnia ?? ""
        nomeEditabile = partita.nomeEditabile
        tipologia = partita.tipologia
        valoreAssicurato = partita.valoreAssicurato.stringValue
        percentualeDeroga = partita.percentualeDeroga?.stringValue ?? ""
        determinazioneDanno = partita.determinazioneDanno
        regoleSpeciali = partita.regoleSpeciali ?? ""
    }
    
    private func savePartita() {
        viewContext.performAndWait {
            let partitaToSave: Partita
            if let existingPartita = partita {
                partitaToSave = existingPartita
            } else {
                guard let perizia = periziaToUse else { return }
                partitaToSave = Partita(context: viewContext)
                partitaToSave.id = UUID()
                partitaToSave.perizia = perizia
                partitaToSave.ordine = Int16(perizia.partiteArray.count)
            }
            
            partitaToSave.tipoPartita = tipoPartita
            partitaToSave.nomeFornitoCompagnia = nomeFornitoCompagnia.isEmpty ? nil : nomeFornitoCompagnia
            partitaToSave.nomeEditabile = nomeEditabile.isEmpty ? tipoPartita : nomeEditabile
            partitaToSave.tipologia = tipologia
            partitaToSave.valoreAssicurato = NSDecimalNumber(string: valoreAssicurato)
            partitaToSave.percentualeDeroga = percentualeDeroga.isEmpty ? nil : NSDecimalNumber(string: percentualeDeroga)
            partitaToSave.determinazioneDanno = determinazioneDanno
            partitaToSave.regoleSpeciali = regoleSpeciali.isEmpty ? nil : regoleSpeciali
            
            try? viewContext.save()
        }
    }
}
