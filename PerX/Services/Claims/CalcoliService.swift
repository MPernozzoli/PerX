import Foundation
import CoreData
import SwiftUI

/// Facciata storica dei calcoli peritali. Dal 26/11/2026 ogni importo viene dal motore di stima
/// deterministico (`StimaEngine`, via `StimaService`): qui restano solo adattatori per le viste
/// che usano ancora i vecchi tipi (`LiquidazioneResult`, Double).
/// Riferimento: Documentation/Funzionalita/Motore-di-Stima.md
class CalcoliService: ObservableObject {
    static let shared = CalcoliService()

    private let stima = StimaService.shared

    private init() {}

    // MARK: - Formule di base (coerenti con il motore)

    /// VSU (valore allo stato d'uso) di un netto illesi con deprezzamento percentuale.
    func calcolaVSU(nettoIllesi: NSDecimalNumber, deprezzamento: NSDecimalNumber) -> NSDecimalNumber {
        let netto = nettoIllesi.decimalValue
        let vsu = (netto * (1 - deprezzamento.decimalValue / 100)).arrotondato()
        return NSDecimalNumber(decimal: vsu)
    }

    /// Supplemento d'indennizzo in base al criterio di determinazione del danno.
    func calcolaSI(nettoIllesi: NSDecimalNumber, vsu: NSDecimalNumber, determinazioneDanno: String) -> NSDecimalNumber {
        NSDecimalNumber(decimal: supplemento(nettoIllesi.decimalValue, vsu.decimalValue, CriterioIndennizzo(stringa: determinazioneDanno)))
    }

    func calcolaSI(nettoIllesi: Double, vsu: Double, determinazioneDanno: String) -> Double {
        supplemento(Decimal(nettoIllesi), Decimal(vsu), CriterioIndennizzo(stringa: determinazioneDanno)).doubleValue
    }

    private func supplemento(_ nettoIllesi: Decimal, _ vsu: Decimal, _ criterio: CriterioIndennizzo) -> Decimal {
        guard criterio.prevedeSupplemento else { return 0 }
        let differenza = max(0, nettoIllesi - vsu)
        if let k = criterio.limiteSupplemento { return min(differenza, vsu * k).arrotondato() }
        return differenza.arrotondato()
    }

    // MARK: - Voci e beni

    /// Totali VSU/SI (prima di IVA) delle voci indicate, calcolati dal motore sul loro bene.
    func calcolaTotaliBene(
        vociCosto: [VoceCosto],
        deprezzamento: NSDecimalNumber,
        determinazioneDanno: String
    ) -> (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        var vsu: Decimal = 0, si: Decimal = 0
        var cache: [NSManagedObjectID: [String: VoceCalcolata]] = [:]
        for voce in vociCosto {
            guard let bene = voce.bene else { continue }
            if cache[bene.objectID] == nil {
                cache[bene.objectID] = Dictionary(stima.calcoloBene(bene).voci.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            }
            guard let c = cache[bene.objectID]?[voce.wrappedId.uuidString] else { continue }
            let rapporto = (c.vsu + c.si) > 0 ? c.importo / (c.vsu + c.si) : 1 // quota del bene comune
            vsu += (c.vsu * rapporto).arrotondato()
            si += c.importo - (c.vsu * rapporto).arrotondato()
        }
        return (NSDecimalNumber(decimal: vsu), NSDecimalNumber(decimal: si), NSDecimalNumber(decimal: vsu + si))
    }

    func calcolaTotaliPartita(
        beni: [Bene],
        deprezzamento: NSDecimalNumber
    ) -> (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        var vsu: Decimal = 0, si: Decimal = 0
        for bene in beni {
            let c = stima.calcoloBene(bene)
            vsu += c.vsu
            si += c.si
        }
        return (NSDecimalNumber(decimal: vsu), NSDecimalNumber(decimal: si), NSDecimalNumber(decimal: vsu + si))
    }

    /// Ricalcola i valori derivati della voce (rispettando i campi forzati). Non salva il contesto.
    func aggiornaCalcoliVoce(
        _ voce: VoceCosto,
        deprezzamento: NSDecimalNumber,
        determinazioneDanno: String
    ) {
        stima.aggiornaVoce(voce)
    }

    // MARK: - Liquidazione (adattatore verso LiquidazioneResult)

    func calcolaLiquidazione(
        garanzia: Garanzia,
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> LiquidazioneResult {
        let riepilogo = calcolaRiepilogoLiquidazione(perizia: perizia)
        return riepilogo.risultatiPerGaranzia.first { $0.garanzia == garanzia } ?? LiquidazioneResult(garanzia: garanzia)
    }

    /// Riepilogo per garanzia. L'ordine «massimale prima della franchigia» è quello salvato in perizia.
    func calcolaRiepilogoLiquidazione(
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> RiepilogoLiquidazione {
        var riepilogo = RiepilogoLiquidazione()
        guard let calcolo = stima.calcolo(perizia) else { return riepilogo }
        let garanzie = Dictionary(perizia.garanzieArray.map { ($0.wrappedId.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        for l in calcolo.liquidazioni {
            guard let garanzia = garanzie[l.garanziaId] else { continue }
            riepilogo.risultatiPerGaranzia.append(risultato(l, garanzia: garanzia, beni: calcolo.beni.filter { $0.garanziaId == l.garanziaId }))
        }
        return riepilogo
    }

    private func risultato(_ l: LiquidazioneGaranzia, garanzia: Garanzia, beni: [BeneCalcolato]) -> LiquidazioneResult {
        var r = LiquidazioneResult(garanzia: garanzia)
        for b in beni {
            guard let pid = b.partitaId.flatMap(UUID.init(uuidString:)) else { continue }
            r.vsuPerPartita[pid, default: 0] += b.vsu.doubleValue
            r.siPerPartita[pid, default: 0] += b.si.doubleValue
            for v in b.voci where !v.ammessa {
                let quotaVSU = (v.vsu + v.si) > 0 ? v.vsu / (v.vsu + v.si) : 1
                let vsuImp = (v.imponibile * quotaVSU).arrotondato()
                r.vsuNonIndennizzabilePerPartita[pid, default: 0] += vsuImp.doubleValue
                r.siNonIndennizzabilePerPartita[pid, default: 0] += (v.imponibile - vsuImp).doubleValue
                r.totaleVSUNonIndennizzabile += vsuImp.doubleValue
                r.totaleSINonIndennizzabile += (v.imponibile - vsuImp).doubleValue
                r.ivaNonIndennizzabile += v.iva.doubleValue
            }
        }
        let conVoci = beni.filter { $0.voci.contains(where: \.ammessa) }
        r.totaleVSU = l.vsu.doubleValue
        r.totaleSI = l.si.doubleValue
        r.iva = l.ivaInLiquidazione.doubleValue
        r.ivaASaldo = l.ivaASaldo.doubleValue
        r.franchigia = l.tipoTrattenuta == .franchigia ? l.trattenuta.doubleValue : 0
        r.scoperto = l.tipoTrattenuta == .scoperto ? l.trattenuta.doubleValue : 0
        r.massimale = l.massimale.doubleValue
        r.dannoIndennizzabile = l.liquidabile.doubleValue
        r.ripristiniUltimati = conVoci.allSatisfy(\.ripristiniUltimati)
        r.liquidazioneVSU = (l.liquidabile - l.liquidabileDifferito).doubleValue
        r.liquidazioneSI = r.ripristiniUltimati ? 0 : (l.liquidabileDifferito + l.ivaASaldo).doubleValue
        r.ivaRiconosciuta = conVoci.contains { $0.ivaInLiquidazione + $0.ivaASaldo > 0 }
        r.ivaInclusa = !conVoci.isEmpty && conVoci.allSatisfy { b in b.voci.contains { $0.ammessa && $0.imponibile != $0.importo } }
        r.dannoNonIndennizzabile = l.dannoNonIndennizzabile.doubleValue
        r.tuttoNonIndennizzabile = l.tuttoNonIndennizzabile
        return r
    }

    enum TipoScoperto {
        case percentuale
        case franchigia
        case nessuno
    }

    // MARK: - Totali di perizia

    /// Totale a nuovo delle voci ammesse (prima di migliorie, illesi, deprezzamento, franchigie).
    func calcolaDannoAccertatoLordo(perizia: Perizia) -> Double {
        guard let calcolo = stima.calcolo(perizia) else { return 0 }
        return calcolo.beni.flatMap(\.voci).filter(\.ammessa).reduce(Decimal(0)) { $0 + $1.totaleANuovo }.doubleValue
    }

    /// Richiesta dell'assicurato: a corpo per sinistro, altrimenti per bene, altrimenti somma delle voci.
    /// Comprende le richieste dei beni ancora in bozza.
    func calcolaRichiestaTotale(perizia: Perizia) -> Double {
        let bozza = perizia.beniBozzaArray.reduce(0.0) { $0 + ($1.richiesta?.doubleValue ?? 0) }
        if let richiesta = stima.calcolo(perizia)?.totali.richiesta {
            return richiesta.doubleValue + (perizia.richiestaSinistro == nil ? bozza : 0)
        }
        return bozza
    }

    /// Liquidabile del motore (dopo franchigia/scoperto, limiti, arrotondamento e rettifiche).
    func calcolaStimaDanno(
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> Double {
        stima.calcolo(perizia)?.totali.liquidabile.doubleValue ?? 0
    }
}
