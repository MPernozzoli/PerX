import Foundation
import CoreData
import SwiftUI

// MARK: - Strutture Dati

/// Tipo di bonus
enum TipoBonus: String, Codable {
    case unaTantum = "una_tantum"
    case dinamico = "dinamico"
}

/// Tipo di condizione per le regole
enum TipoCondizione: String, Codable {
    // Date - Dopo (successiva a)
    case dataAperturaGestioneDopo = "data_apertura_gestione_dopo"
    case dataAssegnazioneDopo = "data_assegnazione_dopo"
    case dataIncaricoDopo = "data_incarico_dopo"
    case dataInvioAttoDopo = "data_invio_atto_dopo"
    case dataChiusuraDopo = "data_chiusura_dopo"
    case dataRevocaDopo = "data_revoca_dopo"
    case dataSinistroDopo = "data_sinistro_dopo"
    case dataDenunciaDopo = "data_denuncia_dopo"
    case dataSopralluogoDopo = "data_sopralluogo_dopo"
    
    // Date - Prima (antecedente a)
    case dataAperturaGestionePrima = "data_apertura_gestione_prima"
    case dataAssegnazionePrima = "data_assegnazione_prima"
    case dataIncaricoPrima = "data_incarico_prima"
    case dataInvioAttoPrima = "data_invio_atto_prima"
    case dataChiusuraPrima = "data_chiusura_prima"
    case dataRevocaPrima = "data_revoca_prima"
    case dataSinistroPrima = "data_sinistro_prima"
    case dataDenunciaPrima = "data_denuncia_prima"
    case dataSopralluogoPrima = "data_sopralluogo_prima"
    
    // Date - Tra (range)
    case dataAperturaGestioneTra = "data_apertura_gestione_tra"
    case dataAssegnazioneTra = "data_assegnazione_tra"
    case dataIncaricoTra = "data_incarico_tra"
    case dataInvioAttoTra = "data_invio_atto_tra"
    case dataChiusuraTra = "data_chiusura_tra"
    case dataRevocaTra = "data_revoca_tra"
    case dataSinistroTra = "data_sinistro_tra"
    case dataDenunciaTra = "data_denuncia_tra"
    case dataSopralluogoTra = "data_sopralluogo_tra"
    
    // Definizioni
    case definizioneIn = "definizione_in"
    
    // Compagnia
    case compagniaIn = "compagnia_in"
    
    // Stato sinistro (condizioni dirette sul singolo sinistro)
    case sinistroIsNegativo = "sinistro_is_negativo"
    case sinistroIsConcordato = "sinistro_is_concordato"
    case sinistroIsNonConcordato = "sinistro_is_non_concordato"
    case sinistroIsInPL = "sinistro_is_in_pl"
    
    // Percentuali (calcolate su mese o anno)
    case percentualeNegativeSuperiore = "percentuale_negative_superiore"
    case percentualeNegativeTra = "percentuale_negative_tra"
    case percentualeConcordateSuperiore = "percentuale_concordate_superiore"
    case percentualeConcordateTra = "percentuale_concordate_tra"
    case percentualeNonConcordateSuperiore = "percentuale_non_concordate_superiore"
    case percentualeNonConcordateTra = "percentuale_non_concordate_tra"
    case percentualePLSuperiore = "percentuale_pl_superiore"
    case percentualePLTra = "percentuale_pl_tra"
    
    // Anno di Competenza (estratto dal riferimento sinistro)
    case competenzaAnnoCorrente = "competenza_anno_corrente"           // Anno corrente (dinamico)
    case competenzaAnnoPrecedente = "competenza_anno_precedente"       // Anno precedente (dinamico)
    case competenzaAnnoSpecifico = "competenza_anno_specifico"         // Anno specifico (es: 2024)
    case competenzaAnnoTra = "competenza_anno_tra"                     // Range di anni (es: 2023-2025)
}

/// Periodo per calcolare le percentuali
enum PeriodoCalcoloPercentuale: String, Codable {
    case mese = "mese"
    case anno = "anno"
}

/// A quali sinistri applicare il bonus quando la condizione percentuale è soddisfatta
enum ApplicazioneBonusPercentuale: String, Codable {
    case soloQualificanti = "solo_qualificanti"  // Solo i sinistri che contribuiscono alla % (es: solo le negative)
    case tutti = "tutti"                          // Tutti i sinistri del periodo
}

/// Operatore logico per combinare condizioni
enum OperatoreLogico: String, Codable {
    case AND = "AND"
    case OR = "OR"
}

/// Condizione singola per un bonus dinamico
struct CondizioneBonus: Codable, Identifiable {
    var id: String = UUID().uuidString
    var tipo: TipoCondizione
    var valore: String // Valore della condizione (JSON-encoded per valori complessi)
    var operatore: OperatoreLogico? // Operatore per combinare con la condizione precedente
    var periodoPercentuale: PeriodoCalcoloPercentuale? // Solo per condizioni percentuali: mese o anno
    var applicazionePercentuale: ApplicazioneBonusPercentuale? // A quali sinistri applicare (solo per percentuali)
    
    // Helper per valori semplici
    var dataValore: Date? {
        get {
            guard let data = try? JSONDecoder().decode(DateCodable.self, from: valore.data(using: .utf8) ?? Data()) else {
                return nil
            }
            return data.date
        }
        set {
            if let date = newValue {
                let codable = DateCodable(date: date)
                if let data = try? JSONEncoder().encode(codable),
                   let string = String(data: data, encoding: .utf8) {
                    valore = string
                }
            }
        }
    }
    
    var definizioniArray: [String]? {
        get {
            guard let data = valore.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            if let array = newValue,
               let data = try? JSONEncoder().encode(array),
               let string = String(data: data, encoding: .utf8) {
                valore = string
            }
        }
    }
    
    var compagnieArray: [String]? {
        get {
            guard let data = valore.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            if let array = newValue,
               let data = try? JSONEncoder().encode(array),
               let string = String(data: data, encoding: .utf8) {
                valore = string
            }
        }
    }
    
    var percentualeValore: Double? {
        get {
            return Double(valore)
        }
        set {
            if let val = newValue {
                valore = String(val)
            }
        }
    }
    
    var percentualeRange: (min: Double, max: Double)? {
        get {
            guard let data = valore.data(using: .utf8),
                  let range = try? JSONDecoder().decode(PercentualeRange.self, from: data) else {
                return nil
            }
            return (range.min, range.max)
        }
        set {
            if let range = newValue {
                let codable = PercentualeRange(min: range.min, max: range.max)
                if let data = try? JSONEncoder().encode(codable),
                   let string = String(data: data, encoding: .utf8) {
                    valore = string
                }
            }
        }
    }
    
    var dataRange: (from: Date, to: Date)? {
        get {
            guard let data = valore.data(using: .utf8),
                  let range = try? JSONDecoder().decode(DateRange.self, from: data) else {
                return nil
            }
            return (range.from, range.to)
        }
        set {
            if let range = newValue {
                let codable = DateRange(from: range.from, to: range.to)
                if let data = try? JSONEncoder().encode(codable),
                   let string = String(data: data, encoding: .utf8) {
                    valore = string
                }
            }
        }
    }
    
    // Anno specifico per competenza
    var annoValore: Int? {
        get {
            return Int(valore)
        }
        set {
            if let val = newValue {
                valore = String(val)
            }
        }
    }
    
    // Range di anni per competenza
    var annoRange: (from: Int, to: Int)? {
        get {
            guard let data = valore.data(using: .utf8),
                  let range = try? JSONDecoder().decode(AnnoRange.self, from: data) else {
                return nil
            }
            return (range.from, range.to)
        }
        set {
            if let range = newValue {
                let codable = AnnoRange(from: range.from, to: range.to)
                if let data = try? JSONEncoder().encode(codable),
                   let string = String(data: data, encoding: .utf8) {
                    valore = string
                }
            }
        }
    }
    
    private struct DateCodable: Codable {
        let date: Date
        
        enum CodingKeys: String, CodingKey {
            case date = "date"
        }
    }
    
    private struct DateRange: Codable {
        let from: Date
        let to: Date
    }
    
    private struct PercentualeRange: Codable {
        let min: Double
        let max: Double
    }
    
    private struct AnnoRange: Codable {
        let from: Int
        let to: Int
    }
    
    var periodoCalcolo: PeriodoCalcoloPercentuale {
        get {
            return periodoPercentuale ?? .mese
        }
        set {
            periodoPercentuale = newValue
        }
    }
    
    /// A quali sinistri applicare il bonus (default: solo quelli che contribuiscono alla %)
    var applicazione: ApplicazioneBonusPercentuale {
        get {
            return applicazionePercentuale ?? .soloQualificanti
        }
        set {
            applicazionePercentuale = newValue
        }
    }
}

/// Bonus mensile (una tantum o dinamico)
struct BonusMensile: Codable, Identifiable {
    var id: String = UUID().uuidString
    var nome: String
    var tipo: TipoBonus
    var importo: Double // Per una tantum: importo fisso, per dinamico: importo per sinistro
    var condizioni: [CondizioneBonus]? // Solo per bonus dinamici
    var attivo: Bool = true
}

/// Bonus mensili per un mese specifico
struct BonusMensili: Codable {
    var monthKey: String // formato: "YYYY-MM"
    var bonus: [BonusMensile] = []
}

// MARK: - Servizio

class BonusMensileService: ObservableObject {
    static let shared = BonusMensileService()
    
    @Published private var bonusPerMese: [String: BonusMensili] = [:]
    
    private let userDefaultsKey = "bonusMensili"
    
    private init() {
        loadBonus()
    }
    
    private func loadBonus() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: BonusMensili].self, from: data) {
            bonusPerMese = decoded
        }
    }
    
    private func saveBonus() {
        if let encoded = try? JSONEncoder().encode(bonusPerMese) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            objectWillChange.send()
        }
    }
    
    private func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    func getBonus(for date: Date) -> [BonusMensile] {
        let key = monthKey(for: date)
        return bonusPerMese[key]?.bonus ?? []
    }
    
    func addBonus(_ bonus: BonusMensile, for date: Date) {
        let key = monthKey(for: date)
        var bonusMensili = bonusPerMese[key] ?? BonusMensili(monthKey: key, bonus: [])
        bonusMensili.bonus.append(bonus)
        bonusPerMese[key] = bonusMensili
        saveBonus()
        // Invalida la cache per questo mese
        FatturatoCacheService.shared.invalidaCache(for: date)
    }
    
    func updateBonus(_ bonus: BonusMensile, for date: Date) {
        let key = monthKey(for: date)
        guard var bonusMensili = bonusPerMese[key] else { return }
        if let index = bonusMensili.bonus.firstIndex(where: { $0.id == bonus.id }) {
            bonusMensili.bonus[index] = bonus
            bonusPerMese[key] = bonusMensili
            saveBonus()
            // Invalida la cache per questo mese
            FatturatoCacheService.shared.invalidaCache(for: date)
        }
    }
    
    func deleteBonus(_ bonusId: String, for date: Date) {
        let key = monthKey(for: date)
        guard var bonusMensili = bonusPerMese[key] else { return }
        bonusMensili.bonus.removeAll { $0.id == bonusId }
        bonusPerMese[key] = bonusMensili
        saveBonus()
        // Invalida la cache per questo mese
        FatturatoCacheService.shared.invalidaCache(for: date)
    }
    
    func importaBonus(from sourceDate: Date, to targetDate: Date) {
        let sourceKey = monthKey(for: sourceDate)
        let targetKey = monthKey(for: targetDate)
        
        guard let sourceBonus = bonusPerMese[sourceKey] else { return }
        
        var targetBonus = bonusPerMese[targetKey] ?? BonusMensili(monthKey: targetKey, bonus: [])
        
        // Copia tutti i bonus dal mese sorgente (con nuovi ID per evitare conflitti)
        for var bonus in sourceBonus.bonus {
            bonus.id = UUID().uuidString
            targetBonus.bonus.append(bonus)
        }
        
        bonusPerMese[targetKey] = targetBonus
        saveBonus()
        // Invalida la cache per il mese di destinazione
        FatturatoCacheService.shared.invalidaCache(for: targetDate)
    }
    
    /// Calcola il totale dei bonus per un mese dato un array di sinistri chiusi
    func calcolaTotaleBonus(
        for date: Date,
        sinistriChiusi: [Sinistro],
        in context: NSManagedObjectContext
    ) -> Double {
        let bonusList = getBonus(for: date).filter { $0.attivo }
        var totale: Double = 0
        
        for bonus in bonusList {
            totale += calcolaImportoBonus(bonus, for: sinistriChiusi, in: context, month: date)
        }
        
        return totale
    }
    
    /// Calcola l'importo di un singolo bonus
    func calcolaImportoBonus(_ bonus: BonusMensile, for sinistriChiusi: [Sinistro], in context: NSManagedObjectContext, month: Date) -> Double {
        switch bonus.tipo {
        case .unaTantum:
            return bonus.importo
            
        case .dinamico:
            // Conta quanti sinistri soddisfano tutte le condizioni
            let sinistriQualificati = sinistriChiusi.filter { sinistro in
                verificaCondizioniPubbliche(bonus.condizioni ?? [], per: sinistro, in: sinistriChiusi, for: month, in: context)
            }
            return Double(sinistriQualificati.count) * bonus.importo
        }
    }
    
    /// Verifica se un sinistro soddisfa tutte le condizioni (pubblica per uso esterno)
    func verificaCondizioniPubbliche(
        _ condizioni: [CondizioneBonus],
        per sinistro: Sinistro,
        in tuttiSinistri: [Sinistro],
        for date: Date,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard !condizioni.isEmpty else { return true }
        
        var risultato: Bool = true
        var operatorePrecedente: OperatoreLogico? = nil
        
        for (index, condizione) in condizioni.enumerated() {
            let soddisfaCondizione = verificaCondizionePrivata(condizione, per: sinistro, in: tuttiSinistri, for: date, in: context)
            
            if index == 0 {
                risultato = soddisfaCondizione
            } else {
                // Applica l'operatore logico con la condizione precedente
                if let op = operatorePrecedente {
                    switch op {
                    case .AND:
                        risultato = risultato && soddisfaCondizione
                    case .OR:
                        risultato = risultato || soddisfaCondizione
                    }
                } else {
                    // Default: AND
                    risultato = risultato && soddisfaCondizione
                }
            }
            
            operatorePrecedente = condizione.operatore
        }
        
        return risultato
    }
    
    /// Helper per ottenere la data del sinistro in base al tipo di condizione
    private func getDataSinistro(for tipo: TipoCondizione, from sinistro: Sinistro) -> Date? {
        switch tipo {
        case .dataAperturaGestioneDopo, .dataAperturaGestionePrima, .dataAperturaGestioneTra:
            return sinistro.dataAperturaGestione
        case .dataAssegnazioneDopo, .dataAssegnazionePrima, .dataAssegnazioneTra:
            return sinistro.dataAssegnazione
        case .dataIncaricoDopo, .dataIncaricoPrima, .dataIncaricoTra:
            return sinistro.dataIncarico
        case .dataInvioAttoDopo, .dataInvioAttoPrima, .dataInvioAttoTra:
            return sinistro.dataInvioAtto
        case .dataChiusuraDopo, .dataChiusuraPrima, .dataChiusuraTra:
            return sinistro.dataChiusura
        case .dataRevocaDopo, .dataRevocaPrima, .dataRevocaTra:
            return sinistro.dataRevoca
        case .dataSinistroDopo, .dataSinistroPrima, .dataSinistroTra:
            return sinistro.dataSinistro
        case .dataDenunciaDopo, .dataDenunciaPrima, .dataDenunciaTra:
            return sinistro.dataDenuncia
        case .dataSopralluogoDopo, .dataSopralluogoPrima, .dataSopralluogoTra:
            return sinistro.dataSopralluogo
        default:
            return nil
        }
    }
    
    /// Verifica se un sinistro soddisfa una singola condizione (pubblica per uso esterno)
    func verificaCondizionePrivata(
        _ condizione: CondizioneBonus,
        per sinistro: Sinistro,
        in tuttiSinistri: [Sinistro],
        for date: Date,
        in context: NSManagedObjectContext
    ) -> Bool {
        switch condizione.tipo {
        // Date - Dopo (successiva a)
        case .dataAperturaGestioneDopo, .dataAssegnazioneDopo, .dataIncaricoDopo,
             .dataInvioAttoDopo, .dataChiusuraDopo, .dataRevocaDopo,
             .dataSinistroDopo, .dataDenunciaDopo, .dataSopralluogoDopo:
            guard let dataLimite = condizione.dataValore,
                  let data = getDataSinistro(for: condizione.tipo, from: sinistro) else {
                return false
            }
            return data > dataLimite
            
        // Date - Prima (antecedente a)
        case .dataAperturaGestionePrima, .dataAssegnazionePrima, .dataIncaricoPrima,
             .dataInvioAttoPrima, .dataChiusuraPrima, .dataRevocaPrima,
             .dataSinistroPrima, .dataDenunciaPrima, .dataSopralluogoPrima:
            guard let dataLimite = condizione.dataValore,
                  let data = getDataSinistro(for: condizione.tipo, from: sinistro) else {
                return false
            }
            return data < dataLimite
            
        // Date - Tra (range)
        case .dataAperturaGestioneTra, .dataAssegnazioneTra, .dataIncaricoTra,
             .dataInvioAttoTra, .dataChiusuraTra, .dataRevocaTra,
             .dataSinistroTra, .dataDenunciaTra, .dataSopralluogoTra:
            guard let range = condizione.dataRange,
                  let data = getDataSinistro(for: condizione.tipo, from: sinistro) else {
                return false
            }
            return data >= range.from && data <= range.to
            
        // Definizioni
        case .definizioneIn:
            guard let definizioni = condizione.definizioniArray,
                  let definizione = sinistro.definizione else {
                return false
            }
            return definizioni.contains(definizione)
            
        // Compagnia
        case .compagniaIn:
            guard let compagnie = condizione.compagnieArray,
                  let compagnia = sinistro.nomeCompagnia else {
                return false
            }
            return compagnie.contains(compagnia)
            
        // Stato sinistro (condizioni dirette)
        case .sinistroIsNegativo:
            return sinistro.isNegativa
            
        case .sinistroIsConcordato:
            return sinistro.isConcordata
            
        case .sinistroIsNonConcordato:
            return !sinistro.isConcordata
            
        case .sinistroIsInPL:
            return sinistro.isInPL
            
        // Percentuali Negative
        case .percentualeNegativeSuperiore:
            guard let percentualeLimite = condizione.percentualeValore else {
                return false
            }
            let percentuale = calcolaPercentualeNegative(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale > percentualeLimite
            // Se applicazione = soloQualificanti, il sinistro deve essere negativo
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isNegativa
            }
            return condizioneSoddisfatta
            
        case .percentualeNegativeTra:
            guard let range = condizione.percentualeRange else {
                return false
            }
            let percentuale = calcolaPercentualeNegative(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale >= range.min && percentuale <= range.max
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isNegativa
            }
            return condizioneSoddisfatta
            
        // Percentuali Concordate
        case .percentualeConcordateSuperiore:
            guard let percentualeLimite = condizione.percentualeValore else {
                return false
            }
            let percentuale = calcolaPercentualeConcordate(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale > percentualeLimite
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isConcordata
            }
            return condizioneSoddisfatta
            
        case .percentualeConcordateTra:
            guard let range = condizione.percentualeRange else {
                return false
            }
            let percentuale = calcolaPercentualeConcordate(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale >= range.min && percentuale <= range.max
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isConcordata
            }
            return condizioneSoddisfatta
            
        // Percentuali Non Concordate
        case .percentualeNonConcordateSuperiore:
            guard let percentualeLimite = condizione.percentualeValore else {
                return false
            }
            let percentuale = calcolaPercentualeNonConcordate(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale > percentualeLimite
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return !sinistro.isConcordata
            }
            return condizioneSoddisfatta
            
        case .percentualeNonConcordateTra:
            guard let range = condizione.percentualeRange else {
                return false
            }
            let percentuale = calcolaPercentualeNonConcordate(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale >= range.min && percentuale <= range.max
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return !sinistro.isConcordata
            }
            return condizioneSoddisfatta
            
        // Percentuali In PL
        case .percentualePLSuperiore:
            guard let percentualeLimite = condizione.percentualeValore else {
                return false
            }
            let percentuale = calcolaPercentualePL(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale > percentualeLimite
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isInPL
            }
            return condizioneSoddisfatta
            
        case .percentualePLTra:
            guard let range = condizione.percentualeRange else {
                return false
            }
            let percentuale = calcolaPercentualePL(
                for: date,
                periodo: condizione.periodoCalcolo,
                in: context,
                sinistriMese: tuttiSinistri
            )
            let condizioneSoddisfatta = percentuale >= range.min && percentuale <= range.max
            if condizioneSoddisfatta && condizione.applicazione == .soloQualificanti {
                return sinistro.isInPL
            }
            return condizioneSoddisfatta
            
        // Anno di Competenza
        case .competenzaAnnoCorrente:
            guard let annoCompetenza = getAnnoCompetenza(for: sinistro) else {
                return false
            }
            let annoCorrente = Calendar.current.component(.year, from: date)
            return annoCompetenza == annoCorrente
            
        case .competenzaAnnoPrecedente:
            guard let annoCompetenza = getAnnoCompetenza(for: sinistro) else {
                return false
            }
            let annoCorrente = Calendar.current.component(.year, from: date)
            return annoCompetenza == (annoCorrente - 1)
            
        case .competenzaAnnoSpecifico:
            guard let annoCompetenza = getAnnoCompetenza(for: sinistro),
                  let annoRichiesto = condizione.annoValore else {
                return false
            }
            return annoCompetenza == annoRichiesto
            
        case .competenzaAnnoTra:
            guard let annoCompetenza = getAnnoCompetenza(for: sinistro),
                  let range = condizione.annoRange else {
                return false
            }
            return annoCompetenza >= range.from && annoCompetenza <= range.to
        }
    }
    
    // MARK: - Helper per anno di competenza
    
    /// Estrae l'anno di competenza dal riferimento sinistro (primi 2 numeri)
    /// Esempio: "2514419" -> 2025
    private func getAnnoCompetenza(for sinistro: Sinistro) -> Int? {
        guard let riferimento = sinistro.riferimento, riferimento.count >= 2 else {
            // Fallback: usa data incarico se disponibile
            if let dataIncarico = sinistro.dataIncarico {
                return Calendar.current.component(.year, from: dataIncarico)
            }
            return nil
        }
        
        let firstTwo = String(riferimento.prefix(2))
        if let yearSuffix = Int(firstTwo) {
            return 2000 + yearSuffix
        }
        return nil
    }
    
    // MARK: - Helper per calcolo percentuali
    
    private func calcolaPercentualeNegative(
        for date: Date,
        periodo: PeriodoCalcoloPercentuale,
        in context: NSManagedObjectContext,
        sinistriMese: [Sinistro]
    ) -> Double {
        let sinistri = periodo == .mese ? sinistriMese : getSinistriAnno(for: date, in: context)
        guard !sinistri.isEmpty else { return 0 }
        let negative = sinistri.filter { $0.isNegativa }.count
        return (Double(negative) / Double(sinistri.count)) * 100.0
    }
    
    private func calcolaPercentualeConcordate(
        for date: Date,
        periodo: PeriodoCalcoloPercentuale,
        in context: NSManagedObjectContext,
        sinistriMese: [Sinistro]
    ) -> Double {
        let sinistri = periodo == .mese ? sinistriMese : getSinistriAnno(for: date, in: context)
        guard !sinistri.isEmpty else { return 0 }
        let concordate = sinistri.filter { $0.isConcordata }.count
        return (Double(concordate) / Double(sinistri.count)) * 100.0
    }
    
    private func calcolaPercentualeNonConcordate(
        for date: Date,
        periodo: PeriodoCalcoloPercentuale,
        in context: NSManagedObjectContext,
        sinistriMese: [Sinistro]
    ) -> Double {
        let sinistri = periodo == .mese ? sinistriMese : getSinistriAnno(for: date, in: context)
        guard !sinistri.isEmpty else { return 0 }
        let nonConcordate = sinistri.filter { !$0.isConcordata }.count
        return (Double(nonConcordate) / Double(sinistri.count)) * 100.0
    }
    
    private func calcolaPercentualePL(
        for date: Date,
        periodo: PeriodoCalcoloPercentuale,
        in context: NSManagedObjectContext,
        sinistriMese: [Sinistro]
    ) -> Double {
        let sinistri = periodo == .mese ? sinistriMese : getSinistriAnno(for: date, in: context)
        guard !sinistri.isEmpty else { return 0 }
        let inPL = sinistri.filter { $0.isInPL }.count
        return (Double(inPL) / Double(sinistri.count)) * 100.0
    }
    
    private func getSinistriAnno(for date: Date, in context: NSManagedObjectContext) -> [Sinistro] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        // Usa direttamente la funzione invece di tramite shared (che è @MainActor)
        return getYearlyClosedClaimsSuccessful(for: year, in: context)
    }
    
    private func getYearlyClosedClaimsSuccessful(for year: Int, in context: NSManagedObjectContext) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) ?? Date()
        
        let request: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
        request.predicate = NSPredicate(
            format: "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@",
            startOfYear as NSDate,
            endOfYear as NSDate,
            "Chiusa"
        )
        
        do {
            let sinistri = try context.fetch(request)
            return sinistri.filter { sinistro in
                sinistro.stato == "Chiusa"
            }
        } catch {
            print("Errore recupero sinistri chiusi annuali: \(error)")
            return []
        }
    }
}


// MARK: - Helper per ottenere sinistri chiusi con successo

extension ConsuntivoStatsService {
    /// Ottiene i sinistri chiusi con successo (escludendo "richiesta revisione")
    func getMonthlyClosedClaimsSuccessful(
        for month: Date,
        in context: NSManagedObjectContext,
        userEmail: String? = nil
    ) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        let endOfMonthEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfMonth)!
        
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonthEnd as NSDate, "Chiusa"]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request: NSFetchRequest<Sinistro> = Sinistro.fetchRequest
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        do {
            let sinistri = try context.fetch(request)
            // Filtra escludendo "richiesta revisione"
            return sinistri.filter { sinistro in
                sinistro.stato == "Chiusa"
            }
        } catch {
            print("Errore recupero sinistri chiusi: \(error)")
            return []
        }
    }
}

