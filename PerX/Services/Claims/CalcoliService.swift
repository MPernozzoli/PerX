import Foundation
import CoreData
import SwiftUI

class CalcoliService: ObservableObject {
    static let shared = CalcoliService()
    
    private init() {}
    
    // Calcola VSU (Valore allo Stato d'Uso)
    func calcolaVSU(nettoIllesi: NSDecimalNumber, deprezzamento: NSDecimalNumber) -> NSDecimalNumber {
        let deprezzamentoDecimal = deprezzamento.doubleValue / 100.0
        let deprezzamentoAmount = nettoIllesi.multiplying(by: NSDecimalNumber(value: deprezzamentoDecimal))
        return nettoIllesi.subtracting(deprezzamentoAmount)
    }
    
    // Calcola SI (Supplemento d'Indennizzo) in base alla determinazione del danno
    func calcolaSI(
        nettoIllesi: NSDecimalNumber,
        vsu: NSDecimalNumber,
        determinazioneDanno: String
    ) -> NSDecimalNumber {
        let differenza = nettoIllesi.subtracting(vsu)
        
        switch determinazioneDanno {
        case "Valore a nuovo":
            return NSDecimalNumber.zero
            
        case "Valore allo stato d'uso più supplemento d'indennizzo":
            return differenza
            
        case "VSU + SI (max doppio)":
            let maxSI = vsu.multiplying(by: NSDecimalNumber(value: 2))
            return differenza.compare(maxSI) == .orderedAscending ? differenza : maxSI
            
        case "VSU + SI (max triplo)":
            let maxSI = vsu.multiplying(by: NSDecimalNumber(value: 3))
            return differenza.compare(maxSI) == .orderedAscending ? differenza : maxSI
            
        case "VSU + SI (max quadruplo)":
            let maxSI = vsu.multiplying(by: NSDecimalNumber(value: 4))
            return differenza.compare(maxSI) == .orderedAscending ? differenza : maxSI
            
        case "Valore allo stato d'uso":
            return NSDecimalNumber.zero
            
        default:
            // Regole speciali - placeholder
            return differenza
        }
    }
    
    // Overload per Double (usato in VociCostoView)
    func calcolaSI(
        nettoIllesi: Double,
        vsu: Double,
        determinazioneDanno: String
    ) -> Double {
        let differenza = nettoIllesi - vsu
        
        switch determinazioneDanno {
        case "Valore a nuovo":
            return 0.0
            
        case "Valore allo stato d'uso più supplemento d'indennizzo":
            return differenza
            
        case "VSU + SI (max doppio)":
            let maxSI = vsu * 2
            return differenza < maxSI ? differenza : maxSI
            
        case "VSU + SI (max triplo)":
            let maxSI = vsu * 3
            return differenza < maxSI ? differenza : maxSI
            
        case "VSU + SI (max quadruplo)":
            let maxSI = vsu * 4
            return differenza < maxSI ? differenza : maxSI
            
        case "Valore allo stato d'uso":
            return 0.0
            
        default:
            // Regole speciali - placeholder
            return differenza
        }
    }
    
    // Calcola totale per un bene
    func calcolaTotaliBene(
        vociCosto: [VoceCosto],
        deprezzamento: NSDecimalNumber,
        determinazioneDanno: String
    ) -> (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        var totaleVSU = NSDecimalNumber.zero
        var totaleSI = NSDecimalNumber.zero
        
        for voce in vociCosto where voce.indennizzabile {
            if let nettoIllesi = voce.nettoIllesi {
                let vsu = calcolaVSU(nettoIllesi: nettoIllesi, deprezzamento: deprezzamento)
                let si = calcolaSI(nettoIllesi: nettoIllesi, vsu: vsu, determinazioneDanno: determinazioneDanno)
                
                totaleVSU = totaleVSU.adding(vsu)
                totaleSI = totaleSI.adding(si)
            }
        }
        
        let totale = totaleVSU.adding(totaleSI)
        return (totaleVSU, totaleSI, totale)
    }
    
    // Calcola totale per una partita
    func calcolaTotaliPartita(
        beni: [Bene],
        deprezzamento: NSDecimalNumber
    ) -> (vsu: NSDecimalNumber, si: NSDecimalNumber, totale: NSDecimalNumber) {
        var totaleVSU = NSDecimalNumber.zero
        var totaleSI = NSDecimalNumber.zero
        
        for bene in beni {
            let determinazione = bene.determinazioneDannoEffettiva
            let voci = bene.vociCostoArray.filter { $0.indennizzabile }
            let totali = calcolaTotaliBene(
                vociCosto: voci,
                deprezzamento: deprezzamento,
                determinazioneDanno: determinazione
            )
            
            totaleVSU = totaleVSU.adding(totali.vsu)
            totaleSI = totaleSI.adding(totali.si)
        }
        
        let totale = totaleVSU.adding(totaleSI)
        return (totaleVSU, totaleSI, totale)
    }
    
    // Aggiorna tutti i calcoli per una voce di costo
    func aggiornaCalcoliVoce(
        _ voce: VoceCosto,
        deprezzamento: NSDecimalNumber,
        determinazioneDanno: String
    ) {
        // Calcola totale a nuovo
        voce.totaleANuovo = voce.quantita.multiplying(by: voce.valoreUnitario)
        
        // Calcola netto migliorie
        if let totaleANuovo = voce.totaleANuovo, let percentualeMigliorie = voce.percentualeMigliorie {
            let percentuale = percentualeMigliorie.doubleValue / 100.0
            let migliorie = totaleANuovo.multiplying(by: NSDecimalNumber(value: percentuale))
            voce.nettoMigliorie = totaleANuovo.subtracting(migliorie)
        }
        
        // Calcola netto illesi
        if let nettoMigliorie = voce.nettoMigliorie, let percentualeIllesi = voce.percentualeIllesi {
            let percentuale = percentualeIllesi.doubleValue / 100.0
            let illesi = nettoMigliorie.multiplying(by: NSDecimalNumber(value: percentuale))
            voce.nettoIllesi = nettoMigliorie.subtracting(illesi)
        }
        
        // Calcola VSU
        if let nettoIllesi = voce.nettoIllesi {
            voce.vsu = calcolaVSU(nettoIllesi: nettoIllesi, deprezzamento: deprezzamento)
        }
        
        // Calcola SI
        if let nettoIllesi = voce.nettoIllesi, let vsu = voce.vsu {
            voce.si = calcolaSI(nettoIllesi: nettoIllesi, vsu: vsu, determinazioneDanno: determinazioneDanno)
        }
    }
    
    // MARK: - Calcolo Liquidazione
    
    /// Struttura helper per i valori calcolati di un bene
    private struct ValoriBeneCalcolati {
        var vsuImponibile: Double = 0
        var siImponibile: Double = 0
        var ivaInLiquidazione: Double = 0
        var ivaASaldo: Double = 0
    }
    
    /// Calcola VSU, SI e IVA per un set di voci di un bene
    private func calcolaValoriBene(
        voci: [VoceCosto],
        bene: Bene,
        liquidazioneForzata: NSDecimalNumber? = nil
    ) -> ValoriBeneCalcolati {
        var result = ValoriBeneCalcolati()
        
        guard !voci.isEmpty else { return result }
        
        let determinazione = bene.determinazioneDannoEffettiva
        let totali = calcolaTotaliBene(
            vociCosto: voci,
            deprezzamento: NSDecimalNumber(value: bene.deprezzamento > 0 ? bene.deprezzamento : 20.0),
            determinazioneDanno: determinazione
        )
        
        var vsu = totali.vsu.doubleValue
        var si = totali.si.doubleValue
        
        // Se c'è un importo forzato, usa quello proporzionato tra VSU e SI
        if let forzato = liquidazioneForzata, forzato.doubleValue > 0 {
            let totaleCalcolato = vsu + si
            if totaleCalcolato > 0 {
                let ratioVSU = vsu / totaleCalcolato
                let ratioSI = si / totaleCalcolato
                vsu = forzato.doubleValue * ratioVSU
                si = forzato.doubleValue * ratioSI
            } else {
                vsu = forzato.doubleValue
                si = 0
            }
        }
        
        // Parametri IVA del bene
        let beneRiconosciIVA = bene.riconosciIVA
        let beneIvaInclusa = bene.ivaInclusa
        let beneRipristiniUltimati = bene.ripristiniUltimati
        let aliquotaIVA = bene.aliquotaIVA > 0 ? bene.aliquotaIVA : 22.0
        
        if !beneRiconosciIVA {
            // IVA non riconosciuta: lavoriamo solo con imponibili
            if beneIvaInclusa {
                let divisore = 1 + aliquotaIVA / 100.0
                result.vsuImponibile = vsu / divisore
                result.siImponibile = si / divisore
            } else {
                result.vsuImponibile = vsu
                result.siImponibile = si
            }
        } else {
            // IVA riconosciuta
            if beneIvaInclusa {
                let divisore = 1 + aliquotaIVA / 100.0
                result.vsuImponibile = vsu / divisore
                result.siImponibile = si / divisore
                let ivaTotale = (vsu + si) - (result.vsuImponibile + result.siImponibile)
                
                if beneRipristiniUltimati {
                    result.ivaInLiquidazione = ivaTotale
                } else {
                    result.ivaASaldo = ivaTotale
                }
            } else {
                result.vsuImponibile = vsu
                result.siImponibile = si
                let ivaSuVSU = vsu * aliquotaIVA / 100.0
                let ivaSuSI = si * aliquotaIVA / 100.0
                
                if beneRipristiniUltimati {
                    result.ivaInLiquidazione = ivaSuVSU + ivaSuSI
                } else {
                    result.ivaASaldo = ivaSuVSU + ivaSuSI
                }
            }
        }
        
        return result
    }
    
    /// Calcola la liquidazione per una garanzia
    /// L'IVA viene calcolata per bene in base a: riconosciIVA, ivaInclusa, ripristiniUltimati
    /// Calcola anche il danno non indennizzabile (riserva) per le voci con indennizzabile = false
    func calcolaLiquidazione(
        garanzia: Garanzia,
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> LiquidazioneResult {
        var result = LiquidazioneResult(garanzia: garanzia)
        
        let beniGaranzia = garanzia.beniArray
        
        // === ACCUMULATORI INDENNIZZABILI ===
        var vsuPerPartita: [UUID: Double] = [:]
        var siPerPartita: [UUID: Double] = [:]
        var totaleVSUImponibile: Double = 0
        var totaleSIImponibile: Double = 0
        var totaleIVAInLiquidazione: Double = 0
        var totaleIVAASaldo: Double = 0
        var tuttiRipristiniUltimati = true
        var tutteIvaInclusa = true
        var almenoUnBeneRiconosciIVA = false
        var conteggioVociIndennizzabili = 0
        
        // === ACCUMULATORI NON INDENNIZZABILI ===
        var vsuNonIndPerPartita: [UUID: Double] = [:]
        var siNonIndPerPartita: [UUID: Double] = [:]
        var totaleVSUNonInd: Double = 0
        var totaleSINonInd: Double = 0
        var totaleIVANonInd: Double = 0
        var conteggioVociNonIndennizzabili = 0
        
        for bene in beniGaranzia {
            guard let partita = bene.partita else { continue }
            let partitaID = partita.id ?? UUID()
            
            let vociIndennizzabili = bene.vociCostoArray.filter { $0.indennizzabile }
            let vociNonIndennizzabili = bene.vociCostoArray.filter { !$0.indennizzabile }
            
            // --- Calcolo voci INDENNIZZABILI ---
            if !vociIndennizzabili.isEmpty {
                conteggioVociIndennizzabili += vociIndennizzabili.count
                
                let valori = calcolaValoriBene(
                    voci: vociIndennizzabili,
                    bene: bene,
                    liquidazioneForzata: bene.liquidazioneForzata
                )
                
                vsuPerPartita[partitaID, default: 0] += valori.vsuImponibile
                siPerPartita[partitaID, default: 0] += valori.siImponibile
                totaleVSUImponibile += valori.vsuImponibile
                totaleSIImponibile += valori.siImponibile
                totaleIVAInLiquidazione += valori.ivaInLiquidazione
                totaleIVAASaldo += valori.ivaASaldo
                
                if bene.riconosciIVA {
                    almenoUnBeneRiconosciIVA = true
                }
                if !bene.ripristiniUltimati {
                    tuttiRipristiniUltimati = false
                }
                if !bene.ivaInclusa {
                    tutteIvaInclusa = false
                }
            }
            
            // --- Calcolo voci NON INDENNIZZABILI ---
            if !vociNonIndennizzabili.isEmpty {
                conteggioVociNonIndennizzabili += vociNonIndennizzabili.count
                
                // Per le non indennizzabili non usiamo liquidazioneForzata
                let valori = calcolaValoriBene(
                    voci: vociNonIndennizzabili,
                    bene: bene,
                    liquidazioneForzata: nil
                )
                
                vsuNonIndPerPartita[partitaID, default: 0] += valori.vsuImponibile
                siNonIndPerPartita[partitaID, default: 0] += valori.siImponibile
                totaleVSUNonInd += valori.vsuImponibile
                totaleSINonInd += valori.siImponibile
                // Per non indennizzabili, l'IVA va comunque calcolata per mostrare il danno totale
                totaleIVANonInd += valori.ivaInLiquidazione + valori.ivaASaldo
            }
        }
        
        // === POPOLA RISULTATO INDENNIZZABILE ===
        result.vsuPerPartita = vsuPerPartita
        result.siPerPartita = siPerPartita
        result.ripristiniUltimati = tuttiRipristiniUltimati
        result.ivaInclusa = tutteIvaInclusa
        result.ivaRiconosciuta = almenoUnBeneRiconosciIVA
        result.totaleVSU = totaleVSUImponibile
        result.totaleSI = totaleSIImponibile
        result.iva = totaleIVAInLiquidazione
        result.ivaASaldo = totaleIVAASaldo
        
        // === POPOLA RISULTATO NON INDENNIZZABILE ===
        result.vsuNonIndennizzabilePerPartita = vsuNonIndPerPartita
        result.siNonIndennizzabilePerPartita = siNonIndPerPartita
        result.totaleVSUNonIndennizzabile = totaleVSUNonInd
        result.totaleSINonIndennizzabile = totaleSINonInd
        result.ivaNonIndennizzabile = totaleIVANonInd
        
        // Determina se TUTTO è non indennizzabile
        let tuttoNonIndennizzabile = conteggioVociIndennizzabili == 0 && conteggioVociNonIndennizzabili > 0
        result.tuttoNonIndennizzabile = tuttoNonIndennizzabile
        
        // === CALCOLO FRANCHIGIA/SCOPERTO ===
        let totaleImponibile = totaleVSUImponibile + totaleSIImponibile
        let totaleImponibileNonInd = totaleVSUNonInd + totaleSINonInd
        
        // Franchigia/scoperto solo su indennizzabile (o su non indennizzabile se tutto è non indennizzabile)
        let basePerScoperto = tuttoNonIndennizzabile ? totaleImponibileNonInd : totaleImponibile
        let vsuPerScoperto = tuttoNonIndennizzabile ? totaleVSUNonInd : totaleVSUImponibile
        let siPerScoperto = tuttoNonIndennizzabile ? totaleSINonInd : totaleSIImponibile
        
        let dettaglioScoperto = calcolaScoperto(
            garanzia: garanzia,
            totaleVSU: vsuPerScoperto,
            totaleSI: siPerScoperto
        )
        
        result.franchigia = dettaglioScoperto.tipoApplicato == .franchigia ? dettaglioScoperto.importoApplicato : 0
        result.scoperto = dettaglioScoperto.tipoApplicato == .percentuale ? dettaglioScoperto.importoApplicato : 0
        result.massimale = garanzia.massimale.doubleValue
        
        // === CALCOLO DANNO INDENNIZZABILE ===
        if !tuttoNonIndennizzabile {
            var danno = totaleImponibile + totaleIVAInLiquidazione
            
            if massimalePrimaFranchigia {
                if result.massimale > 0 && danno > result.massimale {
                    danno = result.massimale
                }
                danno -= (result.franchigia + result.scoperto)
            } else {
                danno -= (result.franchigia + result.scoperto)
                if result.massimale > 0 && danno > result.massimale {
                    danno = result.massimale
                }
            }
            
            result.dannoIndennizzabile = max(0, danno)
            
            // Separazione VSU/SI per ripristini non ultimati
            if tuttiRipristiniUltimati {
                result.liquidazioneVSU = result.dannoIndennizzabile
                result.liquidazioneSI = 0
            } else {
                let proporzioneScoperto = totaleImponibile > 0 ? totaleVSUImponibile / totaleImponibile : 0
                let scopertoVSU = (result.franchigia + result.scoperto) * proporzioneScoperto
                result.liquidazioneVSU = max(0, totaleVSUImponibile - scopertoVSU)
                
                let scopertoResiduo = (result.franchigia + result.scoperto) - scopertoVSU
                let liquidazioneSI = totaleSIImponibile + totaleIVAASaldo - scopertoResiduo
                result.liquidazioneSI = max(0, liquidazioneSI)
            }
        }
        
        // === CALCOLO DANNO NON INDENNIZZABILE (RISERVA) ===
        if conteggioVociNonIndennizzabili > 0 {
            if tuttoNonIndennizzabile {
                // Tutto non indennizzabile: applica franchigia/scoperto come se fosse indennizzabile
                var dannoNonInd = totaleImponibileNonInd + totaleIVANonInd
                
                if massimalePrimaFranchigia {
                    if result.massimale > 0 && dannoNonInd > result.massimale {
                        dannoNonInd = result.massimale
                    }
                    dannoNonInd -= (result.franchigia + result.scoperto)
                } else {
                    dannoNonInd -= (result.franchigia + result.scoperto)
                    if result.massimale > 0 && dannoNonInd > result.massimale {
                        dannoNonInd = result.massimale
                    }
                }
                
                result.dannoNonIndennizzabile = max(0, dannoNonInd)
            } else {
                // Parziale non indennizzabile: NO franchigia/scoperto, solo somma al netto di deprezzamento
                result.dannoNonIndennizzabile = totaleImponibileNonInd + totaleIVANonInd
            }
        }
        
        return result
    }
    
    /// Calcola scoperto/franchigia per una garanzia
    private func calcolaScoperto(
        garanzia: Garanzia,
        totaleVSU: Double,
        totaleSI: Double
    ) -> (tipoApplicato: TipoScoperto, importoApplicato: Double) {
        let dannoTotale = totaleVSU + totaleSI
        
        // Scoperto percentuale con min/max
        let scopertoPercentuale = garanzia.scopertoPercentuale?.doubleValue ?? 0
        let scopertoMinimo = garanzia.scopertoMinimo?.doubleValue ?? 0
        let scopertoMassimo = garanzia.scopertoMassimo?.doubleValue ?? 0
        
        // Franchigia fissa
        let franchigiaMinimo = garanzia.franchigiaMinimo?.doubleValue ?? 0
        let franchigiaMassimo = garanzia.franchigiaMassimo?.doubleValue ?? 0
        
        // Se c'è percentuale di scoperto valorizzata, è uno scoperto percentuale
        if scopertoPercentuale > 0 {
            var scoperto = dannoTotale * (scopertoPercentuale / 100.0)
            
            // Applica minimo scoperto
            if scopertoMinimo > 0 && scoperto < scopertoMinimo {
                scoperto = scopertoMinimo
            }
            
            // Applica massimo scoperto
            if scopertoMassimo > 0 && scoperto > scopertoMassimo {
                scoperto = scopertoMassimo
            }
            
            return (.percentuale, scoperto)
        }
        
        // Se c'è franchigia, usa quella
        if franchigiaMinimo > 0 {
            var franchigia = franchigiaMinimo
            
            // Applica massimo franchigia se presente
            if franchigiaMassimo > 0 && franchigia > franchigiaMassimo {
                franchigia = franchigiaMassimo
            }
            
            // La franchigia non può eccedere il danno totale
            franchigia = min(franchigia, dannoTotale)
            
            return (.franchigia, franchigia)
        }
        
        return (.nessuno, 0)
    }
    
    /// Calcola il riepilogo di liquidazione per tutta la perizia
    /// L'IVA viene calcolata per bene in base a: riconosciIVA, ivaInclusa, ripristiniUltimati
    func calcolaRiepilogoLiquidazione(
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> RiepilogoLiquidazione {
        var riepilogo = RiepilogoLiquidazione()
        
        for garanzia in perizia.garanzieArray {
            let risultato = calcolaLiquidazione(
                garanzia: garanzia,
                perizia: perizia,
                massimalePrimaFranchigia: massimalePrimaFranchigia
            )
            riepilogo.risultatiPerGaranzia.append(risultato)
        }
        
        return riepilogo
    }
    
    enum TipoScoperto {
        case percentuale
        case franchigia
        case nessuno
    }
    
    /// Calcola il danno accertato lordo (somma di tutte le voci indennizzabili senza deprezzamenti, migliorie, illesi, franchigie, etc.)
    /// È la somma di valoreUnitario * quantita per tutte le voci indennizzabili di tutti i beni
    func calcolaDannoAccertatoLordo(perizia: Perizia) -> Double {
        var totale: Double = 0
        
        // Itera su tutte le partite
        for partita in perizia.partiteArray {
            // Itera su tutti i beni della partita
            for bene in partita.beniArray {
                // Itera su tutte le voci di costo indennizzabili del bene
                for voce in bene.vociCostoArray where voce.indennizzabile {
                    // Somma valoreUnitario * quantita (totale a nuovo)
                    let importo = voce.valoreUnitario.doubleValue * voce.quantita.doubleValue
                    totale += importo
                }
            }
        }
        
        return totale
    }
    
    /// Calcola la richiesta totale (somma delle richieste dei beni della perizia)
    /// - Includes: beni in partite + beni in bozza
    func calcolaRichiestaTotale(perizia: Perizia) -> Double {
        var totale: Double = 0
        
        // Beni per partita
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                totale += bene.richiesta?.doubleValue ?? 0
            }
        }
        
        // Beni in bozza
        for bene in perizia.beniBozzaArray {
            totale += bene.richiesta?.doubleValue ?? 0
        }
        
        return totale
    }
    
    /// Calcola la stima del danno (danno indennizzabile al netto di deprezzamento, franchigia, scoperto, massimale + arrotondamento)
    /// L'IVA viene calcolata per bene in base a: riconosciIVA, ivaInclusa, ripristiniUltimati
    /// - Parameters:
    ///   - perizia: La perizia da cui calcolare la stima
    ///   - massimalePrimaFranchigia: Se applicare il massimale prima della franchigia (default: false)
    /// - Returns: La stima del danno (danno indennizzabile totale + arrotondamento)
    func calcolaStimaDanno(
        perizia: Perizia,
        massimalePrimaFranchigia: Bool = false
    ) -> Double {
        // Calcola riepilogo liquidazione (IVA calcolata per bene)
        let riepilogo = calcolaRiepilogoLiquidazione(
            perizia: perizia,
            massimalePrimaFranchigia: massimalePrimaFranchigia
        )
        
        // Stima del danno: danno indennizzabile totale + arrotondamento
        let arrotondamento = perizia.arrotondamentoLiquidazione?.doubleValue ?? 0
        return riepilogo.dannoIndennizzabileTotale + arrotondamento
    }
}

