import Foundation
import SwiftUI

struct FatturaMensile: Codable {
    var monthKey: String // formato: "YYYY-MM"
    var importoFatturato: Double?
    var pdfPath: String? // percorso relativo al PDF salvato nel filesystem
    
    static func monthKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    var pdfURL: URL? {
        guard let pdfPath = pdfPath else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fatturePath = documentsPath.appendingPathComponent("Fatture")
        return fatturePath.appendingPathComponent(pdfPath)
    }
}

class FatturaMensileService: ObservableObject {
    static let shared = FatturaMensileService()
    
    @Published private var fatture: [String: FatturaMensile] = [:]
    
    private let userDefaultsKey = "fattureMensili"
    private var fattureDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fatturePath = documentsPath.appendingPathComponent("Fatture")
        try? FileManager.default.createDirectory(at: fatturePath, withIntermediateDirectories: true)
        return fatturePath
    }
    
    private init() {
        loadFatture()
    }
    
    private func loadFatture() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: FatturaMensile].self, from: data) {
            fatture = decoded
        }
    }
    
    private func saveFatture() {
        if let encoded = try? JSONEncoder().encode(fatture) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func getFattura(for date: Date) -> FatturaMensile? {
        let key = FatturaMensile.monthKey(from: date)
        return fatture[key]
    }
    
    func getFatturatoEffettivo(for date: Date) -> Double? {
        return getFattura(for: date)?.importoFatturato
    }
    
    func setImportoFatturato(_ importo: Double, for date: Date) {
        let key = FatturaMensile.monthKey(from: date)
        let existingFattura = fatture[key]
        var fattura = existingFattura ?? FatturaMensile(monthKey: key, importoFatturato: nil, pdfPath: nil)
        fattura.importoFatturato = importo
        fatture[key] = fattura
        saveFatture()
        objectWillChange.send()
    }
    
    func setPdf(from url: URL, for date: Date) throws {
        let key = FatturaMensile.monthKey(from: date)
        let fileName = "Fattura_\(key).pdf"
        let destinationURL = fattureDirectory.appendingPathComponent(fileName)
        
        // Rimuovi il PDF precedente se esiste
        if let fattura = fatture[key], let oldPath = fattura.pdfPath {
            let oldURL = fattureDirectory.appendingPathComponent(oldPath)
            try? FileManager.default.removeItem(at: oldURL)
        }
        
        // Copia il nuovo PDF
        try FileManager.default.copyItem(at: url, to: destinationURL)
        
        let existingFattura = fatture[key]
        var fattura = existingFattura ?? FatturaMensile(monthKey: key, importoFatturato: nil, pdfPath: nil)
        fattura.pdfPath = fileName
        fatture[key] = fattura
        saveFatture()
        objectWillChange.send()
    }
    
    func getPdfURL(for date: Date) -> URL? {
        return getFattura(for: date)?.pdfURL
    }
    
    func hasFattura(for date: Date) -> Bool {
        let key = FatturaMensile.monthKey(from: date)
        return fatture[key]?.importoFatturato != nil || fatture[key]?.pdfPath != nil
    }
    
    func isMonthCompleted(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.date(byAdding: .month, value: 1, to: date)! <= now
    }
}

struct FatturatoBreakdown {
    var totaleSinistri: Int
    var importoBase: Double
    var sinistriBase: Int
    var importoFascia: Double
    var sinistriFascia: Int
    var numeroFascia: Int? // Numero della fascia applicabile (es: 50, 75, 100, 130)
    var importoDieciBeni: Double
    var sinistriDieciBeni: Int
    var totaleFatturato: Double
    var bonusMensili: Double
    var bonusMensiliList: [BonusMensileDetail] // Dettaglio bonus per tipo
    // Nuovi campi per compensi per danno
    var compensiDanno: Double // Totale compensi per danno
    var sinistriConCompensoDanno: Int // Numero sinistri che hanno ricevuto compenso danno
    var dettaglioCompensiDanno: [CompensoDannoDetail] // Dettaglio per compagnia
}

struct CompensoDannoDetail: Codable {
    var compagnia: String
    var numeroSinistri: Int
    var totaleCompenso: Double
}

public struct BonusMensileDetail: Codable {
    var nome: String
    var tipo: TipoBonus
    var importo: Double
}

struct FatturatoFiscaleBreakdown {
    var totaleParziale: Double
    var marcaDaBollo: Double
    var totaleConMarca: Double
    var rivalsaINPS: Double
    var fatturatoLordo: Double
    var coefficienteSpesa: Double
    var imponibileContributivo: Double
    var contributiINPS: Double
    var imponibileFiscale: Double
    var tasse: Double
    var utileNetto: Double
}

extension FatturatoSettings {
    func calcolaBreakdownFatturato(sinistri: [Sinistro], bonusMensili: Double = 0, bonusMensiliList: [BonusMensileDetail] = []) -> FatturatoBreakdown {
        let totaleSinistri = sinistri.count
        
        // Determina la fascia di prezzo basata sul numero totale di sinistri
        var importoFascia = importoBase
        var numeroFascia: Int? = nil
        if let fascia = fasce.sorted(by: { $0.numeroSinistri > $1.numeroSinistri })
            .first(where: { totaleSinistri >= $0.numeroSinistri }) {
            importoFascia = fascia.importoFatturazione
            numeroFascia = fascia.numeroSinistri
        }
        
        var totaleFatturato = 0.0
        var sinistriBase = 0
        var sinistriDieciBeni = 0
        
        // Variabili per compensi per danno
        var compensiDanno = 0.0
        var sinistriConCompensoDanno = 0
        var compensiPerCompagnia: [String: (count: Int, totale: Double)] = [:]
        
        for sinistro in sinistri {
            // Compenso base o per 10+ beni (importo fisso, senza moltiplicatore)
            if sinistro.oltreDieciBeni {
                totaleFatturato += importoBaseDieciBeni
                sinistriDieciBeni += 1
            } else {
                totaleFatturato += importoFascia
                sinistriBase += 1
            }
            
            // Calcola compenso per danno (basato sulla compagnia)
            if let dannoAccertato = sinistro.dannoAccertato?.doubleValue, dannoAccertato > 0 {
                let compagnia = sinistro.nomeCompagnia
                let compensoDanno = calcolaCompensoDanno(dannoAccertato: dannoAccertato, compagnia: compagnia)
                if compensoDanno > 0 {
                    compensiDanno += compensoDanno
                    sinistriConCompensoDanno += 1
                    
                    // Raggruppa per compagnia per il dettaglio
                    let nomeCompagnia = compagnia?.trimmingCharacters(in: .whitespaces) ?? "Non specificata"
                    let existing = compensiPerCompagnia[nomeCompagnia] ?? (count: 0, totale: 0)
                    compensiPerCompagnia[nomeCompagnia] = (count: existing.count + 1, totale: existing.totale + compensoDanno)
                }
            }
        }
        
        // Aggiungi compensi per danno al totale
        totaleFatturato += compensiDanno
        
        // Aggiungi bonus mensili al totale
        totaleFatturato += bonusMensili
        
        // Costruisci dettaglio compensi per compagnia
        let dettaglioCompensiDanno = compensiPerCompagnia.map { (compagnia, info) in
            CompensoDannoDetail(compagnia: compagnia, numeroSinistri: info.count, totaleCompenso: info.totale)
        }.sorted { $0.compagnia < $1.compagnia }
        
        return FatturatoBreakdown(
            totaleSinistri: totaleSinistri,
            importoBase: importoBase,
            sinistriBase: sinistriBase,
            importoFascia: importoFascia,
            sinistriFascia: sinistriBase,
            numeroFascia: numeroFascia,
            importoDieciBeni: importoBaseDieciBeni,
            sinistriDieciBeni: sinistriDieciBeni,
            totaleFatturato: totaleFatturato,
            bonusMensili: bonusMensili,
            bonusMensiliList: bonusMensiliList,
            compensiDanno: compensiDanno,
            sinistriConCompensoDanno: sinistriConCompensoDanno,
            dettaglioCompensiDanno: dettaglioCompensiDanno
        )
    }
    
    func calcolaFatturatoFiscale(
        breakdown: FatturatoBreakdown,
        fiscaleSettings: FatturatoFiscaleSettings,
        for date: Date
    ) -> FatturatoFiscaleBreakdown {
        let totaleParziale = breakdown.totaleFatturato
        
        // Marca da bollo: €2.00 se totale > €77.47
        let marcaDaBollo = (fiscaleSettings.marcaDaBolloAbilitata && totaleParziale > 77.47) ? 2.0 : 0.0
        let totaleConMarca = totaleParziale + marcaDaBollo
        
        // Rivalsa INPS: percentuale configurabile sul totale con marca
        let rivalsaINPS = fiscaleSettings.rivalsaINPSAbilitata
            ? totaleConMarca * (fiscaleSettings.rivalsaINPSPercentuale / 100.0)
            : 0.0
        let fatturatoLordo = totaleConMarca + rivalsaINPS
        
        // Coefficiente di redditività: percentuale configurabile del fatturato lordo
        let coefficienteSpesa = fatturatoLordo * (fiscaleSettings.coefficienteRedditivita / 100.0)
        
        // Imponibile contributivo = Fatturato lordo - Coefficiente di spesa
        let imponibileContributivo = fatturatoLordo - coefficienteSpesa
        
        // Contributi INPS = Imponibile contributivo * percentuale INPS
        let percentualeINPS = fiscaleSettings.getContributiINPS(for: date)
        let contributiINPS = imponibileContributivo * (percentualeINPS / 100.0)
        
        // Imponibile fiscale = Imponibile contributivo - Contributi INPS
        let imponibileFiscale = imponibileContributivo - contributiINPS
        
        // Tasse = Imponibile fiscale * percentuale tasse
        let tasse = imponibileFiscale * (fiscaleSettings.percentualeTasse / 100.0)
        
        // Utile netto = Imponibile fiscale - Tasse + Coefficiente di spesa
        let utileNetto = imponibileFiscale - tasse + coefficienteSpesa
        
        return FatturatoFiscaleBreakdown(
            totaleParziale: totaleParziale,
            marcaDaBollo: marcaDaBollo,
            totaleConMarca: totaleConMarca,
            rivalsaINPS: rivalsaINPS,
            fatturatoLordo: fatturatoLordo,
            coefficienteSpesa: coefficienteSpesa,
            imponibileContributivo: imponibileContributivo,
            contributiINPS: contributiINPS,
            imponibileFiscale: imponibileFiscale,
            tasse: tasse,
            utileNetto: utileNetto
        )
    }
    
    /// Calcola il breakdown fiscale partendo da un importo lordo effettivo (fattura emessa)
    /// Questo importo è già comprensivo di marca da bollo e rivalsa INPS
    func calcolaFatturatoFiscaleDaImportoEffettivo(
        importoLordo: Double,
        fiscaleSettings: FatturatoFiscaleSettings,
        for date: Date
    ) -> FatturatoFiscaleBreakdown {
        // L'importo lordo è già il fatturato lordo (include marca e rivalsa)
        let fatturatoLordo = importoLordo
        
        // Coefficiente di redditività: percentuale configurabile del fatturato lordo
        let coefficienteSpesa = fatturatoLordo * (fiscaleSettings.coefficienteRedditivita / 100.0)
        
        // Imponibile contributivo = Fatturato lordo - Coefficiente di spesa
        let imponibileContributivo = fatturatoLordo - coefficienteSpesa
        
        // Contributi INPS = Imponibile contributivo * percentuale INPS
        let percentualeINPS = fiscaleSettings.getContributiINPS(for: date)
        let contributiINPS = imponibileContributivo * (percentualeINPS / 100.0)
        
        // Imponibile fiscale = Imponibile contributivo - Contributi INPS
        let imponibileFiscale = imponibileContributivo - contributiINPS
        
        // Tasse = Imponibile fiscale * percentuale tasse
        let tasse = imponibileFiscale * (fiscaleSettings.percentualeTasse / 100.0)
        
        // Utile netto = Imponibile fiscale - Tasse + Coefficiente di spesa
        let utileNetto = imponibileFiscale - tasse + coefficienteSpesa
        
        return FatturatoFiscaleBreakdown(
            totaleParziale: 0, // Non applicabile per importo effettivo
            marcaDaBollo: 0,   // Già inclusa nell'importo
            totaleConMarca: 0, // Non applicabile
            rivalsaINPS: 0,    // Già inclusa nell'importo
            fatturatoLordo: fatturatoLordo,
            coefficienteSpesa: coefficienteSpesa,
            imponibileContributivo: imponibileContributivo,
            contributiINPS: contributiINPS,
            imponibileFiscale: imponibileFiscale,
            tasse: tasse,
            utileNetto: utileNetto
        )
    }
}

