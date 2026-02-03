import SwiftUI
import CoreData

struct DettaglioSinistriView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    let sinistri: [Sinistro]
    let month: Date
    let onOpenSinistro: (Sinistro) -> Void
    
    @StateObject private var fatturatoSettings = FatturatoSettings.shared
    @StateObject private var bonusMensileService = BonusMensileService.shared
    
    private var dettaglioSinistri: [SinistroFatturatoDetail] {
        let totaleSinistri = sinistri.count
        var importoFascia = fatturatoSettings.importoBase
        if let fascia = fatturatoSettings.fasce.sorted(by: { $0.numeroSinistri > $1.numeroSinistri })
            .first(where: { totaleSinistri >= $0.numeroSinistri }) {
            importoFascia = fascia.importoFatturazione
        }
        
        let bonusList = bonusMensileService.getBonus(for: month).filter { $0.attivo }
        
        return sinistri.map { sinistro in
            var importoBase: Double
            var tipoBase: String
            var bonus: [String: Double] = [:]
            var totale: Double = 0
            
            // Calcola importo base - i sinistri >10 beni hanno importo fisso (senza moltiplicatore fascia)
            if sinistro.oltreDieciBeni {
                importoBase = fatturatoSettings.importoBaseDieciBeni
                tipoBase = ">10 beni (fisso)"
            } else {
                importoBase = importoFascia
                tipoBase = "Base"
                if importoFascia != fatturatoSettings.importoBase {
                    // Aggiungi nota sulla fascia applicata
                    if let fascia = fatturatoSettings.fasce.sorted(by: { $0.numeroSinistri > $1.numeroSinistri })
                        .first(where: { totaleSinistri >= $0.numeroSinistri }) {
                        let incrementoFascia = importoFascia - fatturatoSettings.importoBase
                        bonus["Fascia \(fascia.numeroSinistri)"] = incrementoFascia
                    }
                }
            }
            
            totale = importoBase
            
            // Calcola compenso per danno (basato sulla compagnia)
            if let dannoAccertato = sinistro.dannoAccertato?.doubleValue, dannoAccertato > 0 {
                let compensoDanno = fatturatoSettings.calcolaCompensoDanno(
                    dannoAccertato: dannoAccertato,
                    compagnia: sinistro.nomeCompagnia
                )
                if compensoDanno > 0 {
                    let nomeCompagnia = sinistro.nomeCompagnia ?? "N/D"
                    bonus["Danno €\(Int(dannoAccertato)) (\(nomeCompagnia))"] = compensoDanno
                    totale += compensoDanno
                }
            }
            
            // Calcola solo bonus dinamici (i bonus una tantum sono totali, non per sinistro)
            let bonusService = BonusMensileService.shared
            for bonusItem in bonusList where bonusItem.tipo == .dinamico {
                if bonusService.verificaCondizioniPubbliche(bonusItem.condizioni ?? [], per: sinistro, in: sinistri, for: month, in: viewContext) {
                    bonus[bonusItem.nome] = bonusItem.importo
                    totale += bonusItem.importo
                }
            }
            
            return SinistroFatturatoDetail(
                sinistro: sinistro,
                importoBase: importoBase,
                tipoBase: tipoBase,
                bonus: bonus,
                totale: totale
            )
        }
    }
    
    // Le funzioni di verifica sono delegate al BonusMensileService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header con totali
                VStack(spacing: 8) {
                    HStack {
                        Text("Totale Sinistri: \(sinistri.count)")
                            .font(.headline)
                        Spacer()
                        Text("Totale Fatturato: \(CurrencyFormatter.shared.formatWithSymbol(dettaglioSinistri.reduce(0) { $0 + $1.totale }))")
                            .font(.headline)
                            .foregroundColor(.purple)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Tabella
                Table(dettaglioSinistri) {
                    TableColumn("Riferimento") { detail in
                        Button(action: {
                            onOpenSinistro(detail.sinistro)
                            dismiss()
                        }) {
                            Text(detail.sinistro.riferimento ?? "N/D")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("Importo Base") { detail in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CurrencyFormatter.shared.formatWithSymbol(detail.importoBase))
                                .fontWeight(.medium)
                            Text(detail.tipoBase)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Bonus") { detail in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(detail.bonus.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.caption)
                                    Spacer()
                                    Text(CurrencyFormatter.shared.formatWithSymbol(detail.bonus[key] ?? 0))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            if detail.bonus.isEmpty {
                                Text("Nessun bonus")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 200, ideal: 250)
                    
                    TableColumn("Totale per Sinistro") { detail in
                        Text(CurrencyFormatter.shared.formatWithSymbol(detail.totale))
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                    .width(min: 120, ideal: 150)
                }
            }
            .navigationTitle("Dettaglio Sinistri - \(monthString)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
    }
    
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: month).capitalized
    }
}

struct SinistroFatturatoDetail: Identifiable {
    let id: String
    let sinistro: Sinistro
    let importoBase: Double
    let tipoBase: String
    let bonus: [String: Double]
    let totale: Double
    
    init(sinistro: Sinistro, importoBase: Double, tipoBase: String, bonus: [String: Double], totale: Double) {
        self.id = sinistro.riferimento ?? UUID().uuidString
        self.sinistro = sinistro
        self.importoBase = importoBase
        self.tipoBase = tipoBase
        self.bonus = bonus
        self.totale = totale
    }
}

