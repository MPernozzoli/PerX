import SwiftUI
import CoreData

struct ElaboratoCalcoliView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var perizia: Perizia?
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var fileTagManager = FileTagManager.shared
    @StateObject private var mediaViewerManager = MediaViewerWindowManager.shared
    
    private let fileService = FileService.shared
    @State private var selectedBene: Bene?
    @State private var showPartitaSelector: Bool = false
    @State private var selectedPartitaForNewBene: Partita? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
    }
    
    private var headerView: some View {
        HStack {
            Spacer()
            Button {
                apriBignami()
            } label: {
                Label("Apri Bignami", systemImage: "globe")
            }
            .buttonStyle(.bordered)
            
            Button {
                apriGiustificativi()
            } label: {
                Label("Apri Giustificativi", systemImage: "doc.text.fill")
            }
            .buttonStyle(.bordered)
            
            Button {
                apriFoto()
            } label: {
                Label("Apri Foto", systemImage: "photo")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var contentView: some View {
        if selectedBene != nil {
            detailView
        } else {
            mainView
        }
    }
    
    private var detailView: some View {
        HStack(spacing: 0) {
            beniListView
            Divider()
            beneDetailView
        }
    }
    
    private var beniListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if let perizia = perizia, !perizia.partiteArray.isEmpty {
                        ForEach(perizia.partiteArray) { partita in
                            if !partita.beniArray.isEmpty {
                                partitaBeniView(partita: partita)
                            }
                        }
                    }
                }
                .padding(12)
            }
            
            // Riepilogo totali in tempo reale
            if let perizia = perizia {
                Divider()
                RiepilogoTotaliSidebarView(perizia: perizia)
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func partitaBeniView(partita: Partita) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(partita.nomeEditabile)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            ForEach(partita.beniArray.sorted { $0.ordine < $1.ordine }) { bene in
                BeneCardView(
                    bene: bene,
                    partita: partita,
                    isSelected: selectedBene?.id == bene.id,
                    onSelect: {
                        selectedBene = bene
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var beneDetailView: some View {
        if let selectedBene = selectedBene {
            if let partita = selectedBene.partita,
               let perizia = partita.perizia {
                // Bene assegnato a partita
                BeneDetailView(
                    bene: selectedBene,
                    partita: partita,
                    perizia: perizia,
                    onClose: {
                        self.selectedBene = nil
                    }
                )
            } else if let perizia = selectedBene.periziaBozza {
                // Bene in bozza
                BeneBozzaDetailView(
                    bene: selectedBene,
                    perizia: perizia,
                    onClose: {
                        self.selectedBene = nil
                    }
                )
            }
        }
    }
    
    private var mainView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Sezione beni in bozza
                if let perizia = perizia, !perizia.beniBozzaArray.isEmpty {
                    beniBozzaSectionView
                    Divider()
                }
                
                if let perizia = perizia, !perizia.partiteArray.isEmpty {
                    // Beni per partita
                    ForEach(perizia.partiteArray) { partita in
                        partitaMainView(partita: partita)
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Riepilogo Liquidazione
                    LiquidazioneView(perizia: perizia)
                } else if perizia != nil && perizia!.beniBozzaArray.isEmpty {
                    Text("Nessuna partita disponibile. Aggiungi partite nella sezione Perizia o crea beni in bozza.")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                }
                
                // Bottone per aggiungere bene bozza
                if perizia != nil {
                    Button {
                        addBeneBozza()
                    } label: {
                        Label("Aggiungi Bene (Bozza)", systemImage: "plus.circle.dashed")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(16)
        }
    }
    
    @ViewBuilder
    private var beniBozzaSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.badge.ellipsis")
                    .foregroundColor(.orange)
                Text("Beni in Bozza")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Text("Da assegnare a partite")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                ForEach(perizia!.beniBozzaArray) { bene in
                    BeneBozzaCardView(
                        bene: bene,
                        isSelected: false,
                        onSelect: {
                            selectedBene = bene
                        }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
        )
    }
    
    private func addBeneBozza() {
        guard let perizia = perizia else { return }
        let newBene = Bene(context: viewContext)
        newBene.id = UUID()
        newBene.nome = "Nuovo Bene (Bozza)"
        newBene.periziaBozza = perizia
        newBene.ordine = Int16(perizia.beniBozzaArray.count)
        newBene.anno = 0
        newBene.stimata = false
        newBene.ivaInclusa = false
        newBene.ripristiniUltimati = false
        newBene.sostituzioneIntero = false
        
        try? viewContext.save()
        selectedBene = newBene
    }
    
    @ViewBuilder
    private func partitaMainView(partita: Partita) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Titolo partita
            HStack {
                Label(partita.nomeEditabile, systemImage: "folder.fill")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            if !partita.beniArray.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(partita.beniArray.sorted { $0.ordine < $1.ordine }) { bene in
                        BeneCardView(
                            bene: bene,
                            partita: partita,
                            isSelected: false,
                            onSelect: {
                                selectedBene = bene
                            }
                        )
                    }
                }
                
                addBeneButton(defaultPartita: partita)
            } else {
                HStack {
                    Text("Nessun bene per questa partita")
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                    addBeneButton(defaultPartita: partita)
                }
            }
        }
    }
    
    @ViewBuilder
    private func addBeneButton(defaultPartita: Partita) -> some View {
        if let perizia = perizia, perizia.partiteArray.count > 1 {
            // Menu per selezionare la partita
            Menu {
                ForEach(perizia.partiteArray) { partita in
                    Button(partita.nomeEditabile) {
                        addBene(to: partita)
                    }
                }
            } label: {
                Label("Aggiungi Bene", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                addBene(to: defaultPartita)
            } label: {
                Label("Aggiungi Bene", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func addBene(to partita: Partita) {
        let newBene = Bene(context: viewContext)
        newBene.id = UUID()
        newBene.nome = "Nuovo Bene"
        newBene.partita = partita
        newBene.ordine = Int16(partita.beniArray.count)
        newBene.anno = 0
        newBene.stimata = false
        newBene.ivaInclusa = false
        newBene.ripristiniUltimati = false
        newBene.sostituzioneIntero = false
        
        try? viewContext.save()
        selectedBene = newBene
    }
    
    private func apriBignami() {
        // Implementazione futura
        print("Apri Bignami - implementazione futura")
    }
    
    private func apriGiustificativi() {
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return }
        
        let files = fileService.listFilesRecursive(inDirectory: cartella)
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        
        Task { @MainActor in
            var giustificativiFiles: [URL] = []
            
            for file in files {
                let tags = await fileTagManager.getTagsForFile(at: file.path)
                if let preventivoTag = preventivoTag, tags.contains(preventivoTag) {
                    giustificativiFiles.append(file)
                } else if let fatturaTag = fatturaTag, tags.contains(fatturaTag) {
                    giustificativiFiles.append(file)
                }
            }
            
            // Rimuovi duplicati mantenendo l'ordine
            var seen = Set<URL>()
            giustificativiFiles = giustificativiFiles.filter { seen.insert($0).inserted }
            
            if let firstFile = giustificativiFiles.first {
                mediaViewerManager.openMediaViewer(for: firstFile, files: giustificativiFiles)
            }
        }
    }
    
    private func apriFoto() {
        guard let cartella = sinistro.cartella, !cartella.isEmpty else { return }
        
        let files = fileService.listFilesRecursive(inDirectory: cartella)
        
        // Trova tutti i tag della categoria foto
        let fotoTags = FileTagManager.FileTag.availableTags.filter { $0.category == .foto }
        
        Task { @MainActor in
            var fotoFiles: [URL] = []
            
            for file in files {
                let tags = await fileTagManager.getTagsForFile(at: file.path)
                // Controlla se il file ha almeno un tag della categoria foto
                if tags.contains(where: { fotoTags.contains($0) }) {
                    fotoFiles.append(file)
                }
            }
            
            // Rimuovi duplicati mantenendo l'ordine
            var seen = Set<URL>()
            fotoFiles = fotoFiles.filter { seen.insert($0).inserted }
            
            if let firstFile = fotoFiles.first {
                mediaViewerManager.openMediaViewer(for: firstFile, files: fotoFiles)
            }
        }
    }
}

struct BeneCardView: View {
    @ObservedObject var bene: Bene
    @ObservedObject var partita: Partita
    let isSelected: Bool
    let onSelect: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    
    /// Calcola il danno accertato (VSU + SI + IVA se riconosciuta)
    private var dannoAccertato: Double {
        // Se c'è un valore forzato, usa quello
        if let forzato = bene.liquidazioneForzata, forzato.doubleValue > 0 {
            return forzato.doubleValue
        }
        
        let deprezzamento = bene.deprezzamento > 0 ? bene.deprezzamento : 20.0
        let determinazione = bene.determinazioneDannoEffettiva
        let aliquotaIVA = bene.aliquotaIVA > 0 ? bene.aliquotaIVA : 22.0
        
        var totaleVSU: Double = 0
        var totaleSI: Double = 0
        
        for voce in bene.vociCostoArray where voce.indennizzabile {
            let nettoIllesi = voce.nettoIllesi?.doubleValue ?? 0
            let vsu = nettoIllesi * (1 - deprezzamento / 100)
            totaleVSU += vsu
            
            let si = calcoliService.calcolaSI(nettoIllesi: nettoIllesi, vsu: vsu, determinazioneDanno: determinazione)
            totaleSI += si
        }
        
        var imponibile = totaleVSU + totaleSI
        
        // Se IVA già inclusa, scorporiamo per avere l'imponibile
        if bene.ivaInclusa && bene.riconosciIVA {
            // I valori sono già lordi, il totale è già corretto
            return imponibile
        }
        
        // Se IVA riconosciuta e non inclusa, aggiungiamo l'IVA
        if bene.riconosciIVA && !bene.ivaInclusa {
            let iva = imponibile * (aliquotaIVA / 100.0)
            return imponibile + iva
        }
        
        // IVA non riconosciuta: solo imponibile
        return imponibile
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // Nome bene con eventuale garanzia
                HStack {
                    Text(bene.nome)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if let garanzia = bene.garanzia {
                        Label(garanzia.nomeEditabile, systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Importi: Richiesta e Liquidazione stimata
                HStack {
                    // Richiesta (in blu)
                    if let richiesta = bene.richiesta, richiesta.doubleValue > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Richiesta")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(richiesta.doubleValue))
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    // Danno accertato (in verde)
                    if dannoAccertato > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Danno accertato")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(dannoAccertato))
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BeneBozzaCardView: View {
    @ObservedObject var bene: Bene
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(bene.nome)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("BOZZA")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        )
                }
                
                HStack(spacing: 8) {
                    if let garanzia = bene.garanzia {
                        Label(garanzia.nomeEditabile, systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Label("Non assegnato", systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if let richiesta = bene.richiesta, richiesta.doubleValue > 0 {
                    HStack {
                        Spacer()
                        Text(CurrencyFormatter.shared.formatWithSymbol(richiesta.doubleValue))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Riepilogo totali in tempo reale nella sidebar
struct RiepilogoTotaliSidebarView: View {
    @ObservedObject var perizia: Perizia
    @StateObject private var calcoliService = CalcoliService.shared
    
    private var totali: (vsu: Double, si: Double, iva: Double, franchigia: Double, liquidazione: Double) {
        let deprezzamento = 20.0
        let aliquotaIVA = 22.0
        var totaleVSU: Double = 0
        var totaleSI: Double = 0
        var totaleIVA: Double = 0
        var totaleFranchigia: Double = 0
        
        // Calcola da tutti i beni di tutte le partite
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                let determinazione = bene.determinazioneDannoEffettiva
                
                for voce in bene.vociCostoArray where voce.indennizzabile {
                    let nettoIllesi = voce.nettoIllesi?.doubleValue ?? 0
                    let vsu = nettoIllesi * (1 - deprezzamento / 100)
                    totaleVSU += vsu
                    
                    let si = calcoliService.calcolaSI(nettoIllesi: nettoIllesi, vsu: vsu, determinazioneDanno: determinazione)
                    totaleSI += si
                }
            }
        }
        
        // IVA sul totale
        totaleIVA = (totaleVSU + totaleSI) * (aliquotaIVA / 100)
        
        // Calcola franchigia (semplificato - prima garanzia)
        if let primaGaranzia = perizia.garanzieArray.first {
            if let franchigia = primaGaranzia.franchigiaMinimo {
                totaleFranchigia = franchigia.doubleValue
            } else if let scopertoPerc = primaGaranzia.scopertoPercentuale {
                let dannoTotale = totaleVSU + totaleSI
                totaleFranchigia = dannoTotale * (scopertoPerc.doubleValue / 100)
                if let minimo = primaGaranzia.scopertoMinimo, totaleFranchigia < minimo.doubleValue {
                    totaleFranchigia = minimo.doubleValue
                }
            }
        }
        
        let liquidazione = totaleVSU + totaleSI - totaleFranchigia
        
        return (totaleVSU, totaleSI, totaleIVA, totaleFranchigia, max(0, liquidazione))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RIEPILOGO")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("VSU:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.formatWithSymbol(totali.vsu))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("SI:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.formatWithSymbol(totali.si))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if totali.franchigia > 0 {
                    GridRow {
                        Text("Franchigia:")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("- \(CurrencyFormatter.shared.formatWithSymbol(totali.franchigia))")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Divider()
                    .gridCellColumns(2)
                
                GridRow {
                    Text("Liquidazione:")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text(CurrencyFormatter.shared.formatWithSymbol(totali.liquidazione))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
