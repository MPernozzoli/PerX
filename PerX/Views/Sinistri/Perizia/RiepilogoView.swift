import SwiftUI
import CoreData
import AppKit

// MARK: - Dimensioni A4
private enum A4 {
    static let width: CGFloat = 595.0   // punti (210mm)
    static let height: CGFloat = 842.0  // punti (297mm)
    static let margin: CGFloat = 40.0
    static let innerWidth: CGFloat = width - (margin * 2)
}

// MARK: - RiepilogoView
struct RiepilogoView: View {
    @ObservedObject var sinistro: Sinistro
    @Binding var perizia: Perizia?
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    
    @State private var showPrintDialog = false
    @State private var pdfData: Data?
    
    private let calcoliService = CalcoliService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Toolbar con azioni
                toolbarView
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                // Documento A4 (scalabile)
                documentoA4
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Toolbar
    private var toolbarView: some View {
        HStack {
            Text("Riepilogo Perizia")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                esportaPDF()
            } label: {
                Label("Esporta PDF", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.bordered)
            
            Button {
                stampaPDF()
            } label: {
                Label("Stampa", systemImage: "printer.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Documento A4
    private var documentoA4: some View {
        VStack(spacing: 0) {
            // Container con sfondo carta
            VStack(alignment: .leading, spacing: 24) {
                // PAGINA 1: Intestazione e Dati Generali
                intestazioneSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Dati sinistro
                datiSinistroSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Partite e Garanzie
                partiteGaranzieSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Descrizione Rischio
                descrizioneRischioSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Relazione Peritale
                relazionePeritaleSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Beni Periziati
                beniPeriziatiSection
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Note Conclusive
                noteConclusiveSection
                
                // Riserve / Osservazioni (se presenti)
                if perizia?.hasRiserva == true || !(perizia?.noteOsservazioni?.isEmpty ?? true) {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    riserveOsservazioniSection
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Importo Liquidazione (enfatizzato)
                importoLiquidazioneSection
                
                Spacer(minLength: 40)
            }
            .padding(A4.margin)
            .frame(minWidth: A4.width)
            .background(Color.white)
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
    }
    
    // MARK: - Intestazione
    private var intestazioneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                // Logo/Titolo Studio
                VStack(alignment: .leading, spacing: 4) {
                    Text("ELABORATO PERITALE")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(Color(red: 0.15, green: 0.25, blue: 0.45))
                    
                    Text("Sinistro n. \(sinistro.numeroSinistroCompagnia ?? sinistro.riferimento ?? "N/A")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Compagnia
                VStack(alignment: .trailing, spacing: 4) {
                    Text(sinistro.nomeCompagnia ?? "Compagnia")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if let gruppo = sinistro.gruppo, !gruppo.isEmpty {
                        Text("Gruppo \(gruppo)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Rif. \(sinistro.riferimento ?? "N/A")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Dati Sinistro
    private var datiSinistroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("DATI SINISTRO", icon: "doc.text.fill", editAction: nil)
            
            HStack(alignment: .top, spacing: 32) {
                // Colonna sinistra: Attori
                VStack(alignment: .leading, spacing: 12) {
                    attoreRow(titolo: "Contraente/Assicurato", 
                              nome: sinistro.nomeContraente ?? sinistro.nomeAssicurato ?? "N/A",
                              indirizzo: sinistro.indirizzoContraente ?? sinistro.indirizzoAssicurato)
                    
                    if let danneggiato = sinistro.nomeDanneggiato, !danneggiato.isEmpty,
                       danneggiato != sinistro.nomeContraente && danneggiato != sinistro.nomeAssicurato {
                        attoreRow(titolo: "Danneggiato",
                                  nome: danneggiato,
                                  indirizzo: sinistro.indirizzoDanneggiato)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Colonna destra: Date con giorni trascorsi
                VStack(alignment: .leading, spacing: 6) {
                    // Data Sinistro
                    dateRowWithDays("Data Sinistro", date: sinistro.dataSinistro, referenceDate: nil)
                    
                    // Data Denuncia (con giorni da sinistro)
                    dateRowWithDays("Data Denuncia", date: sinistro.dataDenuncia, referenceDate: sinistro.dataSinistro)
                    
                    // Denuncia tardiva
                    if let perizia = perizia, perizia.denunciaTardiva {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text("DENUNCIA TARDIVA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.leading, 100)
                    }
                    
                    // Data Incarico (con giorni da denuncia)
                    dateRowWithDays("Data Incarico", date: sinistro.dataIncarico, referenceDate: sinistro.dataDenuncia)
                    
                    // Data Sopralluogo
                    if sinistro.sopralluogo {
                        dateRowWithDays("Data Sopralluogo", date: sinistro.dataSopralluogo, referenceDate: sinistro.dataIncarico)
                    }
                    
                    // Data Chiusura (con colorazione tempo gestione)
                    if let dataChiusura = sinistro.dataChiusura {
                        dataChiusuraRow(dataChiusura)
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    infoRow("N. Polizza", value: sinistro.numeroPolizza ?? "N/A")
                    infoRow("Tipo Polizza", value: sinistro.tipoPolizza ?? "N/A")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func dateRowWithDays(_ label: String, date: Date?, referenceDate: Date?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            if let date = date {
                Text(formatDate(date))
                    .font(.system(size: 11, weight: .medium))
                
                // Mostra giorni trascorsi dalla data di riferimento
                if let ref = referenceDate {
                    let days = Calendar.current.dateComponents([.day], from: ref, to: date).day ?? 0
                    Text("(\(days) gg)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
    
    private func dataChiusuraRow(_ dataChiusura: Date) -> some View {
        let giorniGestione = Calendar.current.dateComponents([.day], from: sinistro.dataIncarico ?? Date(), to: dataChiusura).day ?? 0
        
        let colore: Color = {
            if giorniGestione < 30 {
                return .green
            } else if giorniGestione <= 58 {
                return .primary
            } else {
                return .red
            }
        }()
        
        return HStack {
            Text("Data Chiusura")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(formatDate(dataChiusura))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colore)
            
            Text("(\(giorniGestione) gg)")
                .font(.system(size: 9, weight: giorniGestione > 58 ? .bold : .regular))
                .foregroundColor(colore)
            
            if giorniGestione < 30 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            } else if giorniGestione > 58 {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Partite e Garanzie
    private var partiteGaranzieSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("PARTITE E GARANZIE", icon: "shield.fill", editAction: {
                navigateToTab("Perizia")
            })
            
            if let perizia = perizia {
                // Partite
                if !perizia.partiteArray.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Partite Assicurate")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ForEach(perizia.partiteArray, id: \.id) { partita in
                            partitaRow(partita)
                        }
                    }
                }
                
                // Garanzie
                if !perizia.garanzieArray.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Garanzie")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ForEach(perizia.garanzieArray, id: \.id) { garanzia in
                            garanziaRow(garanzia)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                Text("Nessuna perizia disponibile")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    private func partitaRow(_ partita: Partita) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(partita.partitaAcquistata ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(partita.nomeEditabile)
                    .font(.system(size: 12))
                    .foregroundColor(partita.partitaAcquistata ? .primary : .secondary)
                
                // Tipologia
                Text(partita.tipologia)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(CurrencyFormatter.shared.formatWithSymbol(partita.valoreAssicurato.doubleValue))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            
            Text(partita.determinazioneDanno)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
    
    private func garanziaRow(_ garanzia: Garanzia) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(garanzia.nomeEditabile)
                    .font(.system(size: 12))
                
                // Tipologia
                Text(garanzia.tipologia)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Max: \(CurrencyFormatter.shared.formatWithSymbol(garanzia.massimale.doubleValue))")
                    .font(.system(size: 11, design: .monospaced))
                
                if let franchigia = garanzia.franchigiaMinimo, franchigia.doubleValue > 0 {
                    Text("Fr: \(CurrencyFormatter.shared.formatWithSymbol(franchigia.doubleValue))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if let scoperto = garanzia.scopertoPercentuale, scoperto.doubleValue > 0 {
                    Text("Sc: \(Int(scoperto.doubleValue))%")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Descrizione Rischio
    private var descrizioneRischioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("PREESISTENZA E DESCRIZIONE DEL RISCHIO", icon: "house.fill", editAction: {
                navigateToTab("Perizia")
            })
            
            if let perizia = perizia {
                HStack(alignment: .top, spacing: 20) {
                    // Colonna sinistra: Descrizione testuale
                    VStack(alignment: .leading, spacing: 12) {
                        // Tipo perizia e fulminazione
                        HStack(spacing: 16) {
                            Label(sinistro.sopralluogo ? "Perizia Tradizionale" : "Perizia Documentale",
                                  systemImage: sinistro.sopralluogo ? "figure.walk" : "doc.text.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                            
                            if let fulminazione = sinistro.fulminazione, !fulminazione.isEmpty {
                                Label(fulminazione, systemImage: "bolt.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // Caratteristiche costruttive sintetiche
                        VStack(alignment: .leading, spacing: 6) {
                            if let struttura = perizia.strutturaPortante, !struttura.isEmpty {
                                caratteristicaRow("Struttura", value: struttura)
                            }
                            if let tamponamenti = perizia.tamponamenti, !tamponamenti.isEmpty {
                                caratteristicaRow("Tamponamenti", value: tamponamenti)
                            }
                            if let orditura = perizia.ordituraTetto, !orditura.isEmpty {
                                caratteristicaRow("Orditura tetto", value: orditura)
                            }
                            if let copertura = perizia.copertura, !copertura.isEmpty {
                                caratteristicaRow("Copertura", value: copertura)
                            }
                            if let finiture = perizia.finiture, !finiture.isEmpty {
                                caratteristicaRow("Finiture", value: finiture)
                            }
                        }
                        
                        // Caratteristiche numeriche
                        HStack(spacing: 20) {
                            if perizia.annoCostruzione > 0 {
                                caratteristicaRow("Anno costr.", value: "\(perizia.annoCostruzione)")
                            }
                            if perizia.numeroPiani > 0 {
                                caratteristicaRow("Piani", value: "\(perizia.numeroPiani)")
                            }
                            if let condizione = perizia.condizioneRischio, !condizione.isEmpty {
                                caratteristicaRow("Stato", value: condizione)
                            }
                        }
                        
                        // Descrizione rischio generata
                        if let descrizione = perizia.descrizioneRischio, !descrizione.isEmpty {
                            Text(descrizione)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Colonna destra: Rappresentazione grafica piccola
                    Fabbricato2DViewMini(
                        strutturaPortante: perizia.strutturaPortante,
                        tamponamenti: perizia.tamponamenti,
                        ordituraTetto: perizia.ordituraTetto,
                        copertura: perizia.copertura
                    )
                    .frame(width: 100, height: 100)
                }
            }
        }
    }
    
    private func caratteristicaRow(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
    }
    
    // MARK: - Relazione Peritale
    private var relazionePeritaleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("RELAZIONE PERITALE", icon: "doc.text.fill", editAction: {
                navigateToTab("Perizia")
            })
            
            if let perizia = perizia {
                VStack(alignment: .leading, spacing: 12) {
                    // Evento causato da
                    if let evento = perizia.eventoCausatoDa, !evento.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Evento causato da:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(evento)
                                .font(.system(size: 12))
                        }
                    }
                    
                    // Relazione completa
                    if let relazione = perizia.relazionePerizia, !relazione.isEmpty {
                        Text(relazione)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    } else {
                        Text("Relazione non ancora compilata")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
    }
    
    // MARK: - Beni Periziati
    private var beniPeriziatiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("BENI PERIZIATI", icon: "cube.box.fill", editAction: {
                navigateToTab("Perizia")
            })
            
            if let perizia = perizia {
                let tuttiBeni = perizia.partiteArray.flatMap { $0.beniArray }
                
                if tuttiBeni.isEmpty {
                    Text("Nessun bene inserito")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    VStack(spacing: 16) {
                        ForEach(tuttiBeni, id: \.id) { bene in
                            beneCard(bene)
                        }
                    }
                }
            }
        }
    }
    
    // Struttura per passare i dati calcolati del bene
    private struct BeneCalcoli {
        let vociIndennizzabili: [VoceCosto]
        let vociNonIndennizzabili: [VoceCosto]
        let isIndennizzabile: Bool
        let totaleVSU: Double
        let totaleSI: Double
        let totaleBene: Double
        let totaleANuovo: Double
        let totaleMigliorieIllesi: Double
        let nettoIllesiTotale: Double
        let deprezzamentoPerc: Double
        let deprezzamentoImporto: Double
        let franchigiaGaranzia: Double
    }
    
    private func calcolaBeneData(_ bene: Bene) -> BeneCalcoli {
        let vociInd = bene.vociCostoArray.filter { $0.indennizzabile }
        let vociNon = bene.vociCostoArray.filter { !$0.indennizzabile }
        
        // Usa i valori già salvati nelle voci
        let totVSU = vociInd.reduce(0.0) { $0 + ($1.vsu?.doubleValue ?? 0) }
        let totSI = vociInd.reduce(0.0) { $0 + ($1.si?.doubleValue ?? 0) }
        let totANuovo = vociInd.reduce(0.0) { $0 + ($1.totaleANuovo?.doubleValue ?? 0) }
        let nettoIllesi = vociInd.reduce(0.0) { $0 + ($1.nettoIllesi?.doubleValue ?? 0) }
        
        let miglioriIllesi = vociInd.reduce(0.0) { acc, v in
            let mig = (v.totaleANuovo?.doubleValue ?? 0) - (v.nettoMigliorie?.doubleValue ?? v.totaleANuovo?.doubleValue ?? 0)
            let ill = (v.nettoMigliorie?.doubleValue ?? 0) - (v.nettoIllesi?.doubleValue ?? v.nettoMigliorie?.doubleValue ?? 0)
            return acc + mig + ill
        }
        
        let deprPerc = bene.deprezzamento > 0 ? bene.deprezzamento : 20
        let deprImporto = nettoIllesi * (deprPerc / 100)
        let franchigia = bene.garanzia?.franchigiaMinimo?.doubleValue ?? 0
        
        return BeneCalcoli(
            vociIndennizzabili: vociInd,
            vociNonIndennizzabili: vociNon,
            isIndennizzabile: !vociInd.isEmpty,
            totaleVSU: totVSU,
            totaleSI: totSI,
            totaleBene: totVSU + totSI,
            totaleANuovo: totANuovo,
            totaleMigliorieIllesi: miglioriIllesi,
            nettoIllesiTotale: nettoIllesi,
            deprezzamentoPerc: deprPerc,
            deprezzamentoImporto: deprImporto,
            franchigiaGaranzia: franchigia
        )
    }
    
    private func beneCard(_ bene: Bene) -> some View {
        let calc = calcolaBeneData(bene)
        
        return VStack(alignment: .leading, spacing: 10) {
            beneCardHeader(bene, isIndennizzabile: calc.isIndennizzabile)
            beneCardContent(bene, calc: calc)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(calc.isIndennizzabile ? Color.green.opacity(0.03) : Color.red.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(calc.isIndennizzabile ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func beneCardHeader(_ bene: Bene, isIndennizzabile: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                beneNomeRow(bene)
                beneMarcaModelloAnno(bene)
                benePartitaGaranzia(bene)
                beneInfoRow(bene)
            }
            
            Spacer()
            
            Text(isIndennizzabile ? "INDENNIZZABILE" : "NON INDENNIZZABILE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isIndennizzabile ? .white : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isIndennizzabile ? Color.green : Color.red.opacity(0.15))
                .cornerRadius(4)
        }
    }
    
    private func beneNomeRow(_ bene: Bene) -> some View {
        HStack(spacing: 8) {
            Text(bene.nome)
                .font(.system(size: 13, weight: .semibold))
            
            if bene.stimata {
                Text("STIMATO")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(3)
            }
        }
    }
    
    private func beneMarcaModelloAnno(_ bene: Bene) -> some View {
        HStack(spacing: 6) {
            if let marca = bene.marca, !marca.isEmpty {
                Text(marca).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let modello = bene.modello, !modello.isEmpty {
                Text(modello).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if bene.anno > 0 {
                Text("Anno \(String(bene.anno))").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }
    
    private func benePartitaGaranzia(_ bene: Bene) -> some View {
        HStack(spacing: 12) {
            if let partita = bene.partita {
                HStack(spacing: 3) {
                    Image(systemName: "folder.fill").font(.system(size: 8)).foregroundColor(.blue)
                    Text(partita.nomeEditabile).font(.system(size: 9)).foregroundColor(.blue)
                }
            }
            if let garanzia = bene.garanzia {
                HStack(spacing: 3) {
                    Image(systemName: "shield.fill").font(.system(size: 8)).foregroundColor(.purple)
                    Text(garanzia.nomeEditabile).font(.system(size: 9)).foregroundColor(.purple)
                }
            }
        }
    }
    
    private func beneInfoRow(_ bene: Bene) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                Image(systemName: bene.ripristiniUltimati ? "checkmark.circle.fill" : "clock.fill")
                    .font(.system(size: 8))
                    .foregroundColor(bene.ripristiniUltimati ? .green : .orange)
                Text(bene.ripristiniUltimati ? "Ripristinato" : "Non ripristinato")
                    .font(.system(size: 9))
                    .foregroundColor(bene.ripristiniUltimati ? .green : .orange)
            }
            
            if let residui = bene.residuiMantenuti, !residui.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: residuiIcon(residui)).font(.system(size: 8)).foregroundColor(residuiColor(residui))
                    Text("Residui: \(residuiLabel(residui))").font(.system(size: 9)).foregroundColor(residuiColor(residui))
                }
            }
            
            if let richiesta = bene.richiesta, richiesta.doubleValue > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "eurosign.circle").font(.system(size: 8)).foregroundColor(.secondary)
                    Text("Rich: \(CurrencyFormatter.shared.format(richiesta.doubleValue))").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func beneCardContent(_ bene: Bene, calc: BeneCalcoli) -> some View {
        HStack(alignment: .top, spacing: 16) {
            beneRelazioneColumn(bene)
            beneCalcoliColumn(calc)
        }
    }
    
    private func beneRelazioneColumn(_ bene: Bene) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Relazione Tecnica")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            
            if let relazione = bene.relazioneTecnica, !relazione.isEmpty {
                Text(relazione)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
            } else {
                Text("Non compilata")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func beneCalcoliColumn(_ calc: BeneCalcoli) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !calc.vociIndennizzabili.isEmpty || !calc.vociNonIndennizzabili.isEmpty {
                beneVociTable(calc)
            }
            
            if calc.isIndennizzabile && calc.totaleANuovo > 0 {
                beneRiepilogoCalcolo(calc)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func beneVociTable(_ calc: BeneCalcoli) -> some View {
        VStack(spacing: 0) {
            beneVociTableHeader()
            
            ForEach(calc.vociIndennizzabili, id: \.id) { voce in
                voceCostoRowDettagliato(voce, indennizzabile: true)
            }
            
            ForEach(calc.vociNonIndennizzabili, id: \.id) { voce in
                voceCostoRowDettagliato(voce, indennizzabile: false)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
    
    private func beneVociTableHeader() -> some View {
        HStack {
            Text("Descrizione").frame(maxWidth: .infinity, alignment: .leading)
            Text("Qtà × €/u").frame(width: 70, alignment: .trailing)
            Text("A Nuovo").frame(width: 60, alignment: .trailing)
            Text("Migl./Ill.").frame(width: 55, alignment: .trailing)
            Text("Netto").frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(Color.gray.opacity(0.1))
    }
    
    private func beneRiepilogoCalcolo(_ calc: BeneCalcoli) -> some View {
        VStack(spacing: 3) {
            VStack(alignment: .trailing, spacing: 1) {
                calcoloRowCompact("Totale a nuovo:", value: calc.totaleANuovo, color: .primary)
                if calc.totaleMigliorieIllesi > 0 {
                    calcoloRowCompact("– Migl./Illesi:", value: -calc.totaleMigliorieIllesi, color: .orange)
                }
                calcoloRowCompact("= Netto:", value: calc.nettoIllesiTotale, color: .primary)
                calcoloRowCompact("– Depr. (\(Int(calc.deprezzamentoPerc))%):", value: -calc.deprezzamentoImporto, color: .red)
                if calc.franchigiaGaranzia > 0 {
                    calcoloRowCompact("– Franchigia:", value: -calc.franchigiaGaranzia, color: .purple)
                }
            }
            
            Divider()
            
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("VSU").font(.system(size: 7)).foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.format(calc.totaleVSU))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("SI").font(.system(size: 7)).foregroundColor(.secondary)
                    Text(CurrencyFormatter.shared.format(calc.totaleSI))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                
                Text(CurrencyFormatter.shared.formatWithSymbol(calc.totaleBene))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
        }
        .padding(6)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(4)
    }
    
    // Helper per residui
    private func residuiIcon(_ residui: String) -> String {
        switch residui.lowercased() {
        case "si": return "checkmark.circle.fill"
        case "parziali": return "circle.lefthalf.filled"
        case "no": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private func residuiColor(_ residui: String) -> Color {
        switch residui.lowercased() {
        case "si": return .green
        case "parziali": return .orange
        case "no": return .red
        default: return .secondary
        }
    }
    
    private func residuiLabel(_ residui: String) -> String {
        switch residui.lowercased() {
        case "si": return "Mantenuti"
        case "parziali": return "Parziali"
        case "no": return "Non mantenuti"
        default: return residui
        }
    }
    
    private func calcoloRowCompact(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(CurrencyFormatter.shared.format(abs(value)))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func voceCostoRowDettagliato(_ voce: VoceCosto, indennizzabile: Bool) -> some View {
        let migliorieIllesi = ((voce.totaleANuovo?.doubleValue ?? 0) - (voce.nettoIllesi?.doubleValue ?? voce.totaleANuovo?.doubleValue ?? 0))
        
        return HStack {
            Text(voce.descrizione)
                .font(.system(size: 9))
                .foregroundColor(indennizzabile ? .primary : .secondary)
                .strikethrough(!indennizzabile)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("\(voce.quantita.stringValue)×\(CurrencyFormatter.shared.format(voce.valoreUnitario.doubleValue))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Text(CurrencyFormatter.shared.format(voce.totaleANuovo?.doubleValue ?? 0))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(indennizzabile ? .primary : .secondary.opacity(0.6))
                .frame(width: 70, alignment: .trailing)
            
            if migliorieIllesi > 0 {
                Text("-\(CurrencyFormatter.shared.format(migliorieIllesi))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: 60, alignment: .trailing)
            }
            
            Text(CurrencyFormatter.shared.format(voce.nettoIllesi?.doubleValue ?? voce.totaleANuovo?.doubleValue ?? 0))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(indennizzabile ? .primary : .secondary.opacity(0.6))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(!indennizzabile ? Color.red.opacity(0.05) : Color.clear)
    }
    
    private func calcoloRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(CurrencyFormatter.shared.formatWithSymbol(abs(value)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Note Conclusive
    private var noteConclusiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("NOTE CONCLUSIVE", icon: "checkmark.seal.fill", editAction: {
                navigateToTab("Perizia")
            })
            
            if let perizia = perizia, let note = perizia.noteConclusive, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
            } else {
                Text("Note conclusive non compilate")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // MARK: - Riserve / Osservazioni
    private var riserveOsservazioniSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if perizia?.hasRiserva == true {
                sectionHeader("RISERVE", icon: "exclamationmark.triangle.fill", editAction: {
                    navigateToTab("Perizia")
                })
                
                if let riserve = perizia?.noteRiserva, !riserve.isEmpty {
                    Text(riserve)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .lineSpacing(4)
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                }
            } else if let osservazioni = perizia?.noteOsservazioni, !osservazioni.isEmpty {
                sectionHeader("OSSERVAZIONI", icon: "bubble.left.fill", editAction: {
                    navigateToTab("Perizia")
                })
                
                Text(osservazioni)
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .lineSpacing(4)
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Importo Liquidazione
    private var importoLiquidazioneSection: some View {
        let riepilogoCalcolo = calcolaRiepilogoLiquidazione()
        
        return VStack(alignment: .center, spacing: 20) {
            // Determinazione
            if let determinazione = perizia?.determinazione ?? sinistro.definizione, !determinazione.isEmpty {
                VStack(spacing: 8) {
                    Text("DETERMINAZIONE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .kerning(2)
                    
                    Text(determinazione)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(coloreDeterminazione(determinazione))
                        .multilineTextAlignment(.center)
                }
            }
            
            // Richiesta (se presente)
            let richiesta = calcolaRichiestaTotale()
            if richiesta > 0 {
                VStack(spacing: 6) {
                    Text("RICHIESTA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .kerning(2)
                    
                    Text(CurrencyFormatter.shared.formatWithSymbol(richiesta))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                }
            }
            
            // Dettaglio calcolo liquidazione
            if sinistro.haLiquidazione {
                VStack(spacing: 6) {
                    dettaglioLiquidazioneRow("Totale VSU:", value: riepilogoCalcolo.totaleVSU)
                    dettaglioLiquidazioneRow("Totale SI:", value: riepilogoCalcolo.totaleSI)
                    if riepilogoCalcolo.totaleIVA > 0 {
                        dettaglioLiquidazioneRow("IVA riconosciuta:", value: riepilogoCalcolo.totaleIVA)
                    }
                    if riepilogoCalcolo.totaleFranchigia > 0 {
                        dettaglioLiquidazioneRow("– Franchigia:", value: -riepilogoCalcolo.totaleFranchigia, color: .purple)
                    }
                    if riepilogoCalcolo.totaleScoperto > 0 {
                        dettaglioLiquidazioneRow("– Scoperto:", value: -riepilogoCalcolo.totaleScoperto, color: .red)
                    }
                }
                .padding(.horizontal, 40)
                
                Divider()
                    .frame(width: 200)
            }
            
            // Importo principale
            VStack(spacing: 8) {
                Text(sinistro.haLiquidazione ? "IMPORTO LIQUIDAZIONE" : "DANNO ACCERTATO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(2)
                
                let importo = calcolaImportoFinale()
                
                Text(CurrencyFormatter.shared.formatWithSymbol(importo))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(sinistro.haLiquidazione ? Color(red: 0.15, green: 0.5, blue: 0.25) : .orange)
                
                if !sinistro.haLiquidazione {
                    Text("(non indennizzabile)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Arrotondamento se presente
            if let arrotondamento = perizia?.arrotondamentoLiquidazione, arrotondamento.doubleValue != 0 {
                Text("(incl. arrotondamento: \(CurrencyFormatter.shared.formatWithSymbol(arrotondamento.doubleValue)))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 1.0),
                            Color.white
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.15, green: 0.25, blue: 0.45).opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String, editAction: (() -> Void)?) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.15, green: 0.25, blue: 0.45))
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.15, green: 0.25, blue: 0.45))
                    .kerning(1)
            }
            
            Spacer()
            
            if let action = editAction {
                Button(action: action) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Modifica")
            }
        }
    }
    
    private func attoreRow(titolo: String, nome: String, indirizzo: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(nome)
                .font(.system(size: 12, weight: .medium))
            
            if let indirizzo = indirizzo, !indirizzo.isEmpty {
                Text(indirizzo)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func dateRow(_ label: String, date: Date?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            if let date = date {
                Text(formatDate(date))
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
    
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatLong(date)
    }
    
    private func coloreDeterminazione(_ determinazione: String) -> Color {
        let upper = determinazione.uppercased()
        if upper.contains("CONCORDATO") && !upper.contains("NON") {
            return Color(red: 0.15, green: 0.5, blue: 0.25)
        } else if upper.contains("NON CONCORDATO") {
            return .orange
        } else if upper.contains("RISERVA") {
            return .red
        }
        return .primary
    }
    
    private func calcolaImportoFinale() -> Double {
        if let perizia = perizia {
            // Unica fonte: importo già calcolato/salvato dalla sezione calcoli (LiquidazioneView)
            if let salvato = perizia.stimaDannoIndennizzabile?.doubleValue, salvato > 0 {
                return salvato
            }
        }
        return sinistro.stimaDanno?.doubleValue ?? sinistro.liquidato?.doubleValue ?? sinistro.dannoAccertato?.doubleValue ?? 0
    }

    private func calcolaRichiestaTotale() -> Double {
        let salvata = sinistro.richiesta?.doubleValue ?? 0
        if salvata > 0 { return salvata }

        guard let perizia = perizia else { return 0 }
        let totale = calcoliService.calcolaRichiestaTotale(perizia: perizia)

        if totale > 0, salvata <= 0 {
            sinistro.richiesta = NSDecimalNumber(value: totale)
            try? viewContext.save()
        }

        return totale
    }
    
    private func calcolaRiepilogoLiquidazione() -> RiepilogoLiquidazione {
        guard let perizia = perizia else {
            return RiepilogoLiquidazione()
        }
        
        return calcoliService.calcolaRiepilogoLiquidazione(
            perizia: perizia,
            massimalePrimaFranchigia: false
        )
    }
    
    private func dettaglioLiquidazioneRow(_ label: String, value: Double, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(CurrencyFormatter.shared.formatWithSymbol(abs(value)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func navigateToTab(_ tabName: String) {
        // Trova l'indice del tab "Perizia" e aggiorna la selezione
        // Questo richiede che la SinistroDetailView gestisca la navigazione
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToPeriziaTab"),
            object: tabName,
            userInfo: ["sinistroId": sinistro.riferimento ?? ""]
        )
    }
    
    // MARK: - Export/Print
    
    private func esportaPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Perizia_\(sinistro.riferimento ?? "sinistro").pdf"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                generaPDFToFile(url: url)
            }
        }
    }
    
    private func stampaPDF() {
        // Genera PDF temporaneo e stampa
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Perizia_\(sinistro.riferimento ?? "temp").pdf")
        
        generaPDFToFile(url: tempURL)
        
        // Apri dialogo stampa
        if FileManager.default.fileExists(atPath: tempURL.path) {
            NSWorkspace.shared.open(tempURL)
        }
    }
    
    private func generaPDFToFile(url: URL) {
        // Implementazione base - può essere estesa con PDFKit per rendering più preciso
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: A4.width, height: A4.height)
        printInfo.topMargin = A4.margin
        printInfo.bottomMargin = A4.margin
        printInfo.leftMargin = A4.margin
        printInfo.rightMargin = A4.margin
        
        // Per ora apriamo la preview di stampa del sistema
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Rappresentazione 2D stilizzata del fabbricato (versione mini per riepilogo)
struct Fabbricato2DViewMini: View {
    let strutturaPortante: String?
    let tamponamenti: String?
    let ordituraTetto: String?
    let copertura: String?
    
    var body: some View {
        ZStack {
            // Sfondo
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.9)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 1)
            
            // Rappresentazione stilizzata
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                VStack(spacing: 0) {
                    // Tetto
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h * 0.2))
                            path.addLine(to: CGPoint(x: w * 0.5, y: 0))
                            path.addLine(to: CGPoint(x: w, y: h * 0.2))
                            path.addLine(to: CGPoint(x: w, y: h * 0.3))
                            path.addLine(to: CGPoint(x: 0, y: h * 0.3))
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
                    }
                    .frame(height: h * 0.3)
                    
                    // Fabbricato
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(white: 0.85), Color(white: 0.75)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        // Finestre
                        HStack(spacing: w * 0.15) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: w * 0.12, height: h * 0.15)
                            
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: w * 0.12, height: h * 0.15)
                        }
                    }
                    .frame(height: h * 0.7)
                }
            }
            .padding(6)
        }
    }
}

// MARK: - Preview
#Preview {
    RiepilogoView(
        sinistro: Sinistro(),
        perizia: .constant(nil)
    )
}