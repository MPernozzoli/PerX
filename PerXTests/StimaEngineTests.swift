//
//  StimaEngineTests.swift
//  PerXTests
//
//  Motore di stima deterministico: casi portati dai test di riferimento (franchigia e massimale,
//  scoperto minimo, IVA, priorità della richiesta, arrotondamento, somme per partita, riparto 1910,
//  esiti) più i criteri PerX (VSU/SI, IVA a saldo, liquidazione forzata).
//  Documentazione: Documentation/Funzionalita/Motore-di-Stima.md
//

import Foundation
import Testing
@testable import PerX

private func d(_ s: String) -> Decimal { Decimal(string: s)! }

/// Caldaia su FE: massimale 1.000, franchigia 250; scheda 800, sonda 2×100, gas 300 escluso.
private func esempio() -> StimaInput {
    var x = StimaInput()
    x.partite = [PartitaInput(id: "fab", nome: "Fabbricato")]
    x.garanzie = [GaranziaInput(id: "fe", nome: "Fenomeno elettrico", massimale: 1000, franchigia: 250)]
    x.beni = [BeneInput(id: "caldaia", nome: "caldaia", genere: "f", partitaId: "fab", garanziaId: "fe",
                        criterio: .valoreANuovo, ivaRiconosciuta: false, voci: [
        VoceInput(id: "v1", descrizione: "scheda", quantita: 1, valoreUnitario: 800, giustificativo: true),
        VoceInput(id: "v2", descrizione: "sonda", quantita: 2, valoreUnitario: 100, giustificativo: true),
        VoceInput(id: "v3", descrizione: "gas", quantita: 1, valoreUnitario: 300, ammessa: false, giustificativo: true),
    ])]
    return x
}

private func partite(franchigia: Decimal = 150, limiteF: Decimal = 3000) -> StimaInput {
    var x = StimaInput()
    x.partite = [PartitaInput(id: "f", nome: "Fabbricato", forma: .primoRischioAssoluto, sommaAssicurata: limiteF),
                 PartitaInput(id: "c", nome: "Contenuto", tipo: "Contenuto", forma: .primoRischioAssoluto, sommaAssicurata: 1500)]
    x.garanzie = [GaranziaInput(id: "g", nome: "FE", franchigia: franchigia)]
    x.beni = [BeneInput(id: "b1", nome: "cancello", partitaId: "f", garanziaId: "g", criterio: .valoreANuovo, ivaRiconosciuta: false,
                        voci: [VoceInput(id: "m", descrizione: "motore", valoreUnitario: 4000)]),
              BeneInput(id: "b2", nome: "tv", partitaId: "c", garanziaId: "g", criterio: .valoreANuovo, ivaRiconosciuta: false,
                        voci: [VoceInput(id: "t", descrizione: "tv", valoreUnitario: 500)])]
    return x
}

struct StimaEngineTests {

    @Test func franchigiaPoiMassimale() throws {
        let r = try StimaEngine.calcola(esempio())
        #expect(r.totali.dannoAccertato == 1000)
        #expect(r.totali.liquidabile == 750)
        #expect(r.totali.riserva == 300)
        #expect(r.testi.accompagnatoria.contains("Non sono state riconosciute le voci relative a gas"))
        #expect(r.testi.accompagnatoria.contains("franchigia contrattuale di € 250,00"))
    }

    @Test func scopertoMinimoEMassimale() throws {
        var x = esempio()
        x.garanzie[0].franchigia = 0
        x.garanzie[0].scopertoPercentuale = 10
        x.garanzie[0].scopertoMinimo = 150
        x.garanzie[0].massimale = 700
        let r = try StimaEngine.calcola(x)
        #expect(r.liquidazioni[0].trattenuta == 150)
        #expect(r.totali.liquidabile == 700)
        #expect(r.liquidazioni[0].massimaleApplicato)
    }

    @Test func ivaSoloSeRiconosciuta() throws {
        var x = esempio()
        x.beni[0].ivaRiconosciuta = true
        x.beni[0].ripristiniUltimati = true
        x.beni[0].voci[1].aliquotaIVA = 0
        x.beni[0].voci[2].aliquotaIVA = 0
        let r = try StimaEngine.calcola(x)
        #expect(r.totali.dannoAccertato == 1176)
        #expect(r.totali.liquidabile == 926)
    }

    @Test func prioritaRichiesta() throws {
        var x = esempio()
        x.richiestaSinistro = 1800
        x.beni[0].richiesta = 1500
        x.beni[0].voci[0].richiesta = 900
        #expect(try StimaEngine.calcola(x).totali.richiesta == 1800)
        x.richiestaSinistro = nil
        #expect(try StimaEngine.calcola(x).totali.richiesta == 1500)
        x.beni[0].richiesta = nil
        x.beni[0].voci[1].richiesta = 250
        #expect(try StimaEngine.calcola(x).totali.richiesta == 1150)
    }

    @Test func arrotondamentoPrimaDellaFranchigia() throws {
        var x = esempio()
        x.garanzie[0].massimale = 0
        x.beni[0].voci[1].valoreUnitario = d("101.5")
        x.arrotondamento = -3
        let r = try StimaEngine.calcola(x)
        #expect(r.totali.dannoAccertato == 1000)
        #expect(r.totali.liquidabile == 750)
        x.arrotondamento = -150
        #expect(throws: StimaErrori.self) { try StimaEngine.calcola(x) }
    }

    @Test func arrotondamentoAssistito() throws {
        var x = esempio()
        x.garanzie[0].massimale = 0
        x.beni[0].voci[1].valoreUnitario = d("101.37")
        #expect(StimaEngine.arrotondamentoPer(obiettivo: 750, input: x) == d("-2.74"))
    }

    @Test func sommeAssicuratePerPartita() throws {
        let r = try StimaEngine.calcola(partite())
        #expect(r.totali.liquidabile == 3500)
        #expect(r.liquidazioni[0].partite.map(\.liquidabile) == [3000, 500])
        #expect(try StimaEngine.calcola(partite(limiteF: 10000)).totali.liquidabile == 4350)
    }

    @Test func regolaProporzionale() throws {
        var x = partite(franchigia: 0, limiteF: 100000)
        x.partite[0].forma = .valoreIntero
        x.partite[0].valoreReale = 125000
        x.partite[0].percentualeDeroga = 10
        let r = try StimaEngine.calcola(x)
        #expect(r.liquidazioni[0].riduzioneProporzionale == 800)
        #expect(r.totali.liquidabile == 3700)
    }

    @Test func riparto1910() throws {
        var x = esempio()
        x.garanzie[0].franchigia = 100
        x.garanzie[0].massimale = 0
        x.beni[0].voci = [VoceInput(id: "s", descrizione: "split", valoreUnitario: 2250)]
        x.riparto1910 = Riparto1910Input(altrePolizze: [AltraPolizzaInput(compagnia: "Linear", polizza: "40150247", indennizzoVirtuale: 2000)])
        let r = try StimaEngine.calcola(x)
        #expect(r.totali.liquidabile == d("1165.66"))
        #expect(r.riparto1910?.righe.first?.importo == d("-1084.34"))
        x.riparto1910?.attivo = false
        #expect(try StimaEngine.calcola(x).totali.liquidabile == 2150)
    }

    @Test func esiti() throws {
        var x = esempio()
        x.esito = .negativo
        let negativa = try StimaEngine.calcola(x)
        #expect(negativa.totali.liquidabile == 0)
        #expect(negativa.totali.riserva == 1300)
        x.dannoNonAccertato = true
        #expect(try StimaEngine.calcola(x).totali.stimaConservativa == 1000)
        var y = esempio()
        y.dannoNonAccertato = true
        #expect(throws: StimaErrori.self) { try StimaEngine.calcola(y) }
    }

    @Test func vsuSupplementoEIvaASaldo() throws {
        var x = StimaInput()
        x.partite = [PartitaInput(id: "f", nome: "Fabbricato")]
        x.garanzie = [GaranziaInput(id: "g", nome: "Incendio")]
        x.beni = [BeneInput(id: "b", nome: "infissi", partitaId: "f", garanziaId: "g", criterio: .vsuPiuSupplemento,
                            deprezzamentoPercentuale: 30, aliquotaIVA: 10, ivaRiconosciuta: true, ripristiniUltimati: false,
                            voci: [VoceInput(id: "v", descrizione: "serramenti", quantita: 2, valoreUnitario: 1000)])]
        let r = try StimaEngine.calcola(x)
        #expect(r.beni[0].vsu == 1400 && r.beni[0].si == 600)
        #expect(r.totali.liquidabile == 2000)
        #expect(r.totali.ivaASaldo == 200)
        #expect(r.totali.liquidabileDifferito == 600)
        x.beni[0].criterio = .valoreANuovo
        #expect(try StimaEngine.calcola(x).beni[0].vsu == 2000)
    }

    @Test func liquidazioneForzataIvaCompresa() throws {
        var x = esempio()
        x.garanzie[0].franchigia = 0
        x.garanzie[0].massimale = 0
        x.beni[0].ivaRiconosciuta = true
        x.beni[0].ripristiniUltimati = true
        x.beni[0].voci = [VoceInput(id: "v", descrizione: "scheda", valoreUnitario: 1000)]
        x.beni[0].liquidazioneForzata = 1200
        let r = try StimaEngine.calcola(x)
        #expect(r.totali.liquidabile == 1200)
        #expect(r.beni[0].imponibile == d("983.61"))
    }

    @Test func scomposizioneTornaConAccertatoELiquidabile() throws {
        var x = esempio()
        x.beni[0].voci[0].richiesta = 1000
        x.beni[0].voci[1].richiesta = 200
        x.beni[0].voci[2].richiesta = 300
        x.beni[0].voci[2].motivoEsclusione = .dannoIndiretto
        let r = try StimaEngine.calcola(x)
        let fase1 = r.scomposizione.filter { $0.fase == .richiestaAccertato }.reduce(Decimal(0)) { $0 + $1.importo }
        let fase2 = r.scomposizione.filter { $0.fase == .accertatoLiquidabile }.reduce(Decimal(0)) { $0 + $1.importo }
        #expect(r.totali.richiesta! + fase1 == r.totali.dannoAccertato)
        #expect(r.totali.dannoAccertato + fase2 == r.totali.liquidabile)
    }

    @Test func hashEconomicoIgnoraITesti() throws {
        var x = esempio()
        let a = try StimaEngine.calcola(x)
        x.accompagnatoriaExtra = "Si dà atto del vincolo bancario."
        let b = try StimaEngine.calcola(x)
        #expect(a.hashCalcolo != b.hashCalcolo)
        #expect(a.hashEconomico == b.hashEconomico)
        x.beni[0].voci[0].valoreUnitario = 801
        #expect(try StimaEngine.calcola(x).hashEconomico != a.hashEconomico)
    }

    @Test func grammaticaEIban() {
        #expect(StimaTesti.articolato("scaldabagno", genere: "m") == "dello scaldabagno")
        #expect(StimaTesti.articolato("inverter", genere: "m") == "dell'inverter")
        #expect(StimaTesti.articolato("lavatrice", genere: "f") == "della lavatrice")
        #expect(StimaEngine.ibanValido("IT60X0542811101000000123456"))
        #expect(!StimaEngine.ibanValido("IT60X0542811101000000123457"))
    }
}
