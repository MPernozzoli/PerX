import SwiftUI
import CoreData

struct TotaliBeneView: View {
    @ObservedObject var bene: Bene
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var calcoliService = CalcoliService.shared
    
    @Binding var deprezzamento: Double
    @Binding var aliquotaIVA: Double
    let ivaInclusa: Bool
    let determinazioneDanno: String
    var riconosciIVA: Bool = true
    
    @State private var showForzaturaPopover: Bool = false
    @State private var importoForzato: String = ""
    
    var totali: (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        calcoliService.calcolaTotaliBene(
            vociCosto: bene.vociCostoArray.filter { $0.indennizzabile },
            deprezzamento: NSDecimalNumber(value: deprezzamento),
            determinazioneDanno: determinazioneDanno
        )
    }
    
    var totaleImponibile: NSDecimalNumber {
        totali.totale
    }
    
    var totaleIVA: NSDecimalNumber {
        if ivaInclusa {
            return NSDecimalNumber.zero
        }
        let percentuale = aliquotaIVA / 100.0
        return totaleImponibile.multiplying(by: NSDecimalNumber(value: percentuale))
    }
    
    var totaleComplessivo: NSDecimalNumber {
        totaleImponibile.adding(totaleIVA)
    }
    
    /// Totale da liquidare (senza IVA se riconosciIVA è false)
    var totaleDaLiquidare: NSDecimalNumber {
        if let forzato = bene.liquidazioneForzata, forzato.doubleValue > 0 {
            return forzato
        }
        return riconosciIVA ? totaleComplessivo : totaleImponibile
    }
    
    var isLiquidazioneForzata: Bool {
        bene.liquidazioneForzata != nil && bene.liquidazioneForzata!.doubleValue > 0
    }
    
    // MARK: - Non indennizzabile
    
    var totaliNonIndennizzabili: (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        calcoliService.calcolaTotaliBene(
            vociCosto: bene.vociCostoArray.filter { !$0.indennizzabile },
            deprezzamento: NSDecimalNumber(value: deprezzamento),
            determinazioneDanno: determinazioneDanno
        )
    }
    
    var haVociNonIndennizzabili: Bool {
        !bene.vociCostoArray.filter { !$0.indennizzabile }.isEmpty
    }
    
    var tuttoNonIndennizzabile: Bool {
        bene.vociCostoArray.filter { $0.indennizzabile }.isEmpty && haVociNonIndennizzabili
    }
    
    var totaleNonIndennizzabile: Double {
        let totale = totaliNonIndennizzabili.totale.doubleValue
        if !riconosciIVA || ivaInclusa {
            return totale
        }
        // Aggiungi IVA se riconosciuta e non inclusa
        return totale + (totale * aliquotaIVA / 100.0)
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Totali")
                    .font(.headline)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("VSU del bene:")
                            .foregroundColor(.secondary)
                        Text(CurrencyFormatter.shared.formatWithSymbol(totali.vsu.doubleValue))
                    }
                    
                    GridRow {
                        Text("SI del bene:")
                            .foregroundColor(.secondary)
                        Text(CurrencyFormatter.shared.formatWithSymbol(totali.si.doubleValue))
                    }
                    
                    GridRow {
                        Text("Totale imponibile:")
                            .foregroundColor(.secondary)
                        Text(CurrencyFormatter.shared.formatWithSymbol(totaleImponibile.doubleValue))
                            .fontWeight(.semibold)
                    }
                    
                    if !ivaInclusa && aliquotaIVA > 0 {
                        GridRow {
                            Text("Totale IVA:")
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(totaleIVA.doubleValue))
                        }
                        
                        GridRow {
                            Text("Totale con IVA:")
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(totaleComplessivo.doubleValue))
                        }
                    }
                    
                    Divider()
                        .gridCellColumns(2)
                    
                    GridRow {
                        Text(riconosciIVA ? "Danno accertato:" : "Danno accertato (senza IVA):")
                            .font(.headline)
                        
                        HStack(spacing: 4) {
                            if showForzaturaPopover {
                                // Campo inline per forzatura
                                TextField("€", text: $importoForzato)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .font(.headline)
                                    .onSubmit { 
                                        applicaForzatura()
                                        showForzaturaPopover = false
                                    }
                                
                                Button {
                                    applicaForzatura()
                                    showForzaturaPopover = false
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    showForzaturaPopover = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Chevron giù decina
                                Button { arrotondaDecina(giu: true) } label: {
                                    Image(systemName: "chevron.down.2")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Arrotonda alla decina inferiore")
                                
                                // Chevron giù unità
                                Button { arrotondaUnita(giu: true) } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Arrotonda all'unità inferiore")
                                
                                Text(CurrencyFormatter.shared.formatWithSymbol(totaleDaLiquidare.doubleValue))
                                    .font(.headline)
                                    .foregroundColor(isLiquidazioneForzata ? .orange : .green)
                                
                                // Mostra variazione se arrotondato
                                if isLiquidazioneForzata {
                                    let calcolato = (riconosciIVA ? totaleComplessivo : totaleImponibile).doubleValue
                                    let variazione = totaleDaLiquidare.doubleValue - calcolato
                                    Text("(\(variazione >= 0 ? "+" : "")\(CurrencyFormatter.shared.format(variazione)))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fontWeight(.light)
                                }
                                
                                // Chevron su unità
                                Button { arrotondaUnita(giu: false) } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Arrotonda all'unità superiore")
                                
                                // Chevron su decina
                                Button { arrotondaDecina(giu: false) } label: {
                                    Image(systemName: "chevron.up.2")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .help("Arrotonda alla decina superiore")
                                
                                Button {
                                    importoForzato = CurrencyFormatter.shared.format(totaleDaLiquidare.doubleValue)
                                    showForzaturaPopover = true
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Imposta importo manuale")
                                
                                if isLiquidazioneForzata {
                                    Button {
                                        bene.liquidazioneForzata = nil
                                        try? viewContext.save()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Rimuovi forzatura")
                                }
                            }
                        }
                    }
                    
                    if !riconosciIVA && !ivaInclusa && aliquotaIVA > 0 {
                        GridRow {
                            Text("IVA a saldo:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(CurrencyFormatter.shared.formatWithSymbol(totaleIVA.doubleValue))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // === NON INDENNIZZABILE ===
                    if haVociNonIndennizzabili && !tuttoNonIndennizzabile {
                        Divider()
                            .gridCellColumns(2)
                        
                        GridRow {
                            Text("NON INDENNIZZABILE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                        .gridCellColumns(2)
                        
                        GridRow {
                            Text("VSU (non riconosciuto):")
                                .foregroundColor(.red.opacity(0.7))
                            Text(CurrencyFormatter.shared.formatWithSymbol(totaliNonIndennizzabili.vsu.doubleValue))
                                .foregroundColor(.red)
                        }
                        
                        if totaliNonIndennizzabili.si.doubleValue > 0 {
                            GridRow {
                                Text("SI (non riconosciuto):")
                                    .foregroundColor(.red.opacity(0.7))
                                Text(CurrencyFormatter.shared.formatWithSymbol(totaliNonIndennizzabili.si.doubleValue))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        GridRow {
                            Text("Danno non riconosciuto:")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text(CurrencyFormatter.shared.formatWithSymbol(totaleNonIndennizzabile))
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        CurrencyFormatter.shared.format(value)
    }
    
    // MARK: - Arrotondamento rapido
    
    private func arrotondaUnita(giu: Bool) {
        let totale = totaleDaLiquidare.doubleValue
        let arrotondato = giu ? floor(totale) : ceil(totale)
        bene.liquidazioneForzata = NSDecimalNumber(value: arrotondato)
        try? viewContext.save()
    }
    
    private func arrotondaDecina(giu: Bool) {
        let totale = totaleDaLiquidare.doubleValue
        let arrotondato = giu ? floor(totale / 10) * 10 : ceil(totale / 10) * 10
        bene.liquidazioneForzata = NSDecimalNumber(value: arrotondato)
        try? viewContext.save()
    }
    
    /// Applica la forzatura e ricalcola le percentuali
    private func applicaForzatura() {
        // Parsing importo con formato italiano
        let normalized = importoForzato
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        
        guard let importoTarget = Double(normalized), importoTarget > 0 else { return }
        
        let totaleCalcolato = (riconosciIVA ? totaleComplessivo : totaleImponibile).doubleValue
        let differenza = totaleCalcolato - importoTarget
        
        if abs(differenza) < 0.01 {
            // Nessuna differenza significativa
            return
        }
        
        // Salva la liquidazione forzata
        bene.liquidazioneForzata = NSDecimalNumber(value: importoTarget)
        
        // Ricalcola le percentuali per adattare la differenza
        ricalcolaPercentualiPerDifferenza(differenza)
        
        try? viewContext.save()
    }
    
    /// Ricalcola le percentuali di miglioria/illesi per adattare la differenza
    private func ricalcolaPercentualiPerDifferenza(_ differenza: Double) {
        let vociIndennizzabili = bene.vociCostoArray.filter { $0.indennizzabile }
        guard !vociIndennizzabili.isEmpty else { return }
        
        // Calcola il totale a nuovo complessivo
        let totaleANuovo = vociIndennizzabili.reduce(0.0) { $0 + ($1.totaleANuovo?.doubleValue ?? 0) }
        guard totaleANuovo > 0 else { return }
        
        // Distribuisce la differenza proporzionalmente su miglioria e illesi
        let differenzaPerVoce = differenza / Double(vociIndennizzabili.count)
        
        for voce in vociIndennizzabili {
            let totaleVoce = voce.totaleANuovo?.doubleValue ?? 0
            guard totaleVoce > 0 else { continue }
            
            // Calcola l'incremento percentuale necessario
            // Applichiamo la differenza come incremento su migliorie
            let percentualeMigliorieAttuale = voce.percentualeMigliorie?.doubleValue ?? 0
            let percentualeIllesiAttuale = voce.percentualeIllesi?.doubleValue ?? 0
            
            if percentualeMigliorieAttuale > 0 || percentualeIllesiAttuale > 0 {
                // Ricalcola distribuendo la differenza
                let nettoMigliorieAttuale = voce.nettoMigliorie?.doubleValue ?? totaleVoce
                let nettoIllesiAttuale = voce.nettoIllesi?.doubleValue ?? nettoMigliorieAttuale
                
                // Nuovo netto illesi necessario
                let nuovoNettoIllesi = nettoIllesiAttuale - differenzaPerVoce
                
                if nuovoNettoIllesi > 0 && nuovoNettoIllesi < nettoMigliorieAttuale {
                    // Aggiusta percentuale illesi
                    let nuovaPercentualeIllesi = (1 - nuovoNettoIllesi / nettoMigliorieAttuale) * 100
                    voce.percentualeIllesi = NSDecimalNumber(value: max(0, min(100, nuovaPercentualeIllesi)))
                    voce.nettoIllesi = NSDecimalNumber(value: nuovoNettoIllesi)
                } else if nuovoNettoIllesi <= 0 {
                    // Necessario anche migliorie
                    voce.percentualeIllesi = NSDecimalNumber(value: 100)
                    voce.nettoIllesi = NSDecimalNumber.zero
                }
            }
        }
    }
}

