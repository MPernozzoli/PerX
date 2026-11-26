import Foundation
import CryptoKit

// MARK: - Aritmetica monetaria

extension Decimal {
    /// Arrotondamento al centesimo (o alla scala indicata) con ROUND_HALF_UP.
    func arrotondato(_ scala: Int = 2) -> Decimal {
        var valore = self
        var risultato = Decimal()
        NSDecimalRound(&risultato, &valore, scala, .plain)
        return risultato
    }

    var haCentesimi: Bool { self != arrotondato(0) }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

private let cento: Decimal = 100

private func somma<S: Sequence>(_ valori: S) -> Decimal where S.Element == Decimal {
    valori.reduce(Decimal(0), +)
}

/// Importo nei testi italiani: 1.075,00
func euroIt(_ valore: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.roundingMode = .halfUp
    return formatter.string(from: NSDecimalNumber(decimal: valore.arrotondato())) ?? "\(valore)"
}

/// Percentuale nei testi italiani: 33,33%
func percentualeIt(_ valore: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "it_IT")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return (formatter.string(from: NSDecimalNumber(decimal: valore)) ?? "\(valore)") + "%"
}

// MARK: - Motore

/// Motore di stima deterministico: valida l'input, calcola importi, avvisi, scomposizione e testi.
/// L'IA o l'interfaccia possono compilare l'input, mai i totali.
enum StimaEngine {

    static let arrotondamentoMassimo: Decimal = 100

    // MARK: Entry point

    static func calcola(_ input: StimaInput) throws -> StimaCalcolo {
        let errori = valida(input)
        if !errori.isEmpty { throw StimaErrori(messaggi: errori) }

        let negativa = input.esito == .negativo
        let beni = input.beni.map { calcolaBene($0) }
        let garanziaIds = Set(input.garanzie.map(\.id))
        let arrotondaGid = garanziaArrotondamento(input)

        var liquidazioni: [LiquidazioneGaranzia] = []
        for garanzia in input.garanzie {
            let beniGaranzia = beni.filter { $0.garanziaId == garanzia.id }
            liquidazioni.append(liquida(
                garanzia: garanzia,
                beni: beniGaranzia,
                partite: input.partite,
                arrotondamento: (garanzia.id == arrotondaGid && !negativa) ? input.arrotondamento : 0,
                negativa: negativa,
                massimalePrima: input.massimalePrimaDellaTrattenuta
            ))
        }

        var riparto: RipartoCalcolato?
        if let raw = input.riparto1910, raw.attivo, !raw.altrePolizze.isEmpty, !negativa {
            riparto = applicaRiparto1910(raw, liquidazioni: &liquidazioni)
        }

        let rettifiche = negativa ? [] : input.rettifiche
        let totaleRettifiche = somma(rettifiche.map(\.importo)).arrotondato()
        let liquidabileGaranzie = somma(liquidazioni.map(\.liquidabile))
        let liquidabile = max(0, liquidabileGaranzie + totaleRettifiche)
        let differito = min(liquidabile, somma(liquidazioni.map(\.liquidabileDifferito)))

        let richiesteBeni = beni.compactMap(\.richiestaEffettiva)
        let richiesta = input.richiestaSinistro ?? (richiesteBeni.isEmpty ? nil : somma(richiesteBeni))

        let stimaConservativa = input.dannoNonAccertato ? somma(beni.map(\.totaleAmmesso)) : nil
        let riserva: Decimal = {
            if let conservativa = stimaConservativa { return conservativa }
            if negativa { return somma(beni.map { $0.totaleAmmesso + $0.totaleEscluso }) }
            return somma(liquidazioni.map(\.dannoNonIndennizzabile))
        }()

        let totali = TotaliStima(
            richiesta: richiesta?.arrotondato(),
            dannoAccertato: somma(liquidazioni.map(\.dannoAccertato)),
            liquidabile: liquidabile,
            liquidabileImmediato: liquidabile - differito,
            liquidabileDifferito: differito,
            ivaASaldo: negativa ? 0 : somma(liquidazioni.map(\.ivaASaldo)),
            rettifiche: totaleRettifiche,
            riserva: riserva,
            stimaConservativa: stimaConservativa
        )

        let workflow = calcolaWorkflow(input: input, liquidabile: liquidabile)

        var avvisi = calcolaAvvisi(input: input, beni: beni, liquidazioni: liquidazioni, totali: totali,
                                   garanziaIds: garanziaIds, workflow: workflow)
        if let riparto {
            avvisi.append("Riparto art. 1910 c.c.: quota a carico della polizza € \(euroIt(riparto.quota)).")
        }

        var calcolo = StimaCalcolo(
            esito: input.esito,
            dannoNonAccertato: input.dannoNonAccertato,
            beni: beni,
            liquidazioni: liquidazioni,
            riparto1910: riparto,
            rettifiche: rettifiche,
            totali: totali,
            scomposizione: [],
            avvisi: avvisi,
            testi: TestiStima(accompagnatoria: "", conclusioniEsito: "", iva: "", visioneBeni: ""),
            workflow: workflow
        )
        calcolo.scomposizione = scomposizione(input: input, calcolo: calcolo)
        calcolo.testi = StimaTesti.genera(input: input, calcolo: calcolo)
        calcolo.hashEconomico = StimaHash.economico(calcolo)
        calcolo.hashCalcolo = StimaHash.completo(calcolo)
        return calcolo
    }

    // MARK: Validazione (errori bloccanti)

    static func valida(_ input: StimaInput) -> [String] {
        var errori: [String] = []
        func percentuale(_ v: Decimal?, _ campo: String) {
            guard let v else { return }
            if v.isNaN || v < 0 || v > cento { errori.append("\(campo): percentuale tra 0 e 100") }
        }
        func nonNegativo(_ v: Decimal?, _ campo: String) {
            guard let v else { return }
            if v.isNaN || v < 0 { errori.append("\(campo): deve essere maggiore o uguale a zero") }
        }

        var idsGaranzie = Set<String>()
        for g in input.garanzie {
            if !idsGaranzie.insert(g.id).inserted { errori.append("Garanzia duplicata: \(g.nome)") }
            let nome = "Garanzia «\(g.nome)»"
            nonNegativo(g.massimale, "\(nome) massimale")
            nonNegativo(g.franchigia, "\(nome) franchigia")
            nonNegativo(g.franchigiaMassimo, "\(nome) franchigia massima")
            percentuale(g.scopertoPercentuale, "\(nome) scoperto")
            nonNegativo(g.scopertoMinimo, "\(nome) minimo scoperto")
            nonNegativo(g.scopertoMassimo, "\(nome) massimo scoperto")
            if g.scopertoMassimo > 0 && g.scopertoMinimo > g.scopertoMassimo {
                errori.append("\(nome): minimo scoperto superiore al massimo")
            }
        }
        for p in input.partite {
            let nome = "Partita «\(p.nome)»"
            nonNegativo(p.sommaAssicurata, "\(nome) somma assicurata")
            nonNegativo(p.valoreReale, "\(nome) valore reale")
            percentuale(p.percentualeDeroga, "\(nome) deroga")
        }
        for b in input.beni {
            let nome = "Bene «\(b.nome)»"
            percentuale(b.deprezzamentoPercentuale, "\(nome) deprezzamento")
            percentuale(b.aliquotaIVA, "\(nome) aliquota IVA")
            nonNegativo(b.richiesta, "\(nome) richiesta")
            nonNegativo(b.liquidazioneForzata, "\(nome) liquidazione forzata")
            if let q = b.quotaComunePercentuale, !(q > 0 && q < cento) {
                errori.append("\(nome): quota del bene comune tra 0 e 100 esclusi")
            }
            if let u = b.unitaServite, u < 2 {
                errori.append("\(nome): un bene comune serve almeno 2 unità")
            }
            for v in b.voci {
                let voce = "\(nome), voce «\(v.descrizione)»"
                nonNegativo(v.quantita, "\(voce) quantità")
                nonNegativo(v.valoreUnitario, "\(voce) valore unitario")
                percentuale(v.percentualeMigliorie, "\(voce) migliorie")
                percentuale(v.percentualeIllesi, "\(voce) illesi")
                percentuale(v.deprezzamentoPercentuale, "\(voce) deprezzamento")
                percentuale(v.aliquotaIVA, "\(voce) aliquota IVA")
                nonNegativo(v.richiesta, "\(voce) richiesta")
                for (forzato, campo) in [(v.totaleANuovoForzato, "totale a nuovo"), (v.nettoMigliorieForzato, "netto migliorie"),
                                         (v.nettoIllesiForzato, "netto illesi"), (v.vsuForzato, "VSU"), (v.siForzato, "SI")] {
                    nonNegativo(forzato, "\(voce) \(campo) forzato")
                }
                if v.richiestaIvaInclusa && v.richiesta == nil {
                    errori.append("\(voce): «richiesta IVA inclusa» senza importo richiesto")
                }
            }
        }
        if input.arrotondamento.isNaN || abs(input.arrotondamento) > arrotondamentoMassimo {
            errori.append("Arrotondamento: al massimo ±\(euroIt(arrotondamentoMassimo)) € (oltre, si escludono o riducono le voci)")
        }
        if let gid = input.arrotondamentoGaranziaId, input.arrotondamento != 0, !idsGaranzie.contains(gid) {
            errori.append("Arrotondamento: garanzia inesistente")
        }
        if input.dannoNonAccertato {
            if input.esito != .negativo {
                errori.append("Danno non accertato: solo con esito Negativo (indennizzo nullo con stima conservativa)")
            } else if !input.beni.contains(where: { $0.voci.contains { $0.ammessa && $0.quantita * $0.valoreUnitario > 0 } }) {
                errori.append("Danno non accertato: serve la stima conservativa (voci ammesse con importo), è la riserva")
            }
        }
        if input.esito == .nonConcordato, input.motivoNonConcordato == .altro,
           (input.motivoNonConcordatoTesto ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            errori.append("Non concordato «Altro»: serve il testo del motivo")
        }
        if let riparto = input.riparto1910, riparto.attivo {
            if riparto.altrePolizze.isEmpty {
                errori.append("Riparto art. 1910: indicare almeno un'altra polizza")
            }
            for (i, a) in riparto.altrePolizze.enumerated() where a.indennizzoVirtuale <= 0 || a.indennizzoVirtuale.isNaN {
                errori.append("Riparto art. 1910, polizza \(i + 1): indennizzo virtuale maggiore di zero")
            }
        }
        if !errori.isEmpty { return errori }

        // L'arrotondamento non può rendere negativo il danno della garanzia.
        if input.arrotondamento < 0, let gid = garanziaArrotondamento(input) {
            let totale = somma(input.beni.filter { $0.garanziaId == gid }.map { calcolaBene($0).totaleAmmesso })
            if totale + input.arrotondamento < 0 {
                errori.append("Arrotondamento: il danno accertato non può diventare negativo")
            }
        }
        return errori
    }

    static func garanziaArrotondamento(_ input: StimaInput) -> String? {
        if let gid = input.arrotondamentoGaranziaId, input.garanzie.contains(where: { $0.id == gid }) { return gid }
        // Senza scelta: la garanzia con il danno maggiore (a parità, la prima).
        let totali = input.garanzie.map { g in
            (g.id, somma(input.beni.filter { $0.garanziaId == g.id }.flatMap(\.voci).filter(\.ammessa).map { $0.quantita * $0.valoreUnitario }))
        }
        return totali.max { a, b in a.1 < b.1 }.map(\.0) ?? input.garanzie.first?.id
    }

    // MARK: Bene e voci

    private struct ValoriVoce {
        var vsuImponibile: Decimal = 0
        var siImponibile: Decimal = 0
        var iva: Decimal = 0
    }

    static func calcolaBene(_ bene: BeneInput) -> BeneCalcolato {
        var voci: [VoceCalcolata] = []
        var ammesse = ValoriVoce(), escluse = ValoriVoce()
        var richiestaVoci: Decimal = 0
        var vociConRichiesta = false
        var totaleIntero: Decimal = 0

        for v in bene.voci {
            let totaleANuovo = (v.totaleANuovoForzato ?? v.quantita * v.valoreUnitario).arrotondato()
            let nettoMigliorie = (v.nettoMigliorieForzato ?? totaleANuovo * (1 - v.percentualeMigliorie / cento)).arrotondato()
            let nettoIllesi = (v.nettoIllesiForzato ?? nettoMigliorie * (1 - v.percentualeIllesi / cento)).arrotondato()
            let deprezzamento = bene.criterio.applicaDeprezzamento ? (v.deprezzamentoPercentuale ?? bene.deprezzamentoPercentuale) : 0
            let vsuPieno = (v.vsuForzato ?? nettoIllesi * (1 - deprezzamento / cento)).arrotondato()
            let siCalcolato: Decimal = {
                guard bene.criterio.prevedeSupplemento else { return 0 }
                let differenza = max(0, nettoIllesi - vsuPieno)
                if let k = bene.criterio.limiteSupplemento { return min(differenza, vsuPieno * k) }
                return differenza
            }()
            let siPieno = (v.siForzato ?? siCalcolato).arrotondato()
            var vsu = vsuPieno, si = siPieno
            if let q = bene.quotaComunePercentuale {
                vsu = (vsuPieno * q / cento).arrotondato()
                si = (siPieno * q / cento).arrotondato()
            }
            let aliquota = v.aliquotaIVA ?? bene.aliquotaIVA
            var valori = ValoriVoce()
            if bene.ivaInclusaNeiValori {
                let divisore = 1 + aliquota / cento
                valori.vsuImponibile = (vsu / divisore).arrotondato()
                valori.siImponibile = (si / divisore).arrotondato()
                valori.iva = vsu + si - valori.vsuImponibile - valori.siImponibile
            } else {
                valori.vsuImponibile = vsu
                valori.siImponibile = si
                valori.iva = ((vsu + si) * aliquota / cento).arrotondato()
            }
            if v.ammessa {
                ammesse.vsuImponibile += valori.vsuImponibile
                ammesse.siImponibile += valori.siImponibile
                ammesse.iva += valori.iva
                totaleIntero += vsuPieno + siPieno
            } else {
                escluse.vsuImponibile += valori.vsuImponibile
                escluse.siImponibile += valori.siImponibile
                escluse.iva += valori.iva
            }
            if let r = v.richiesta {
                richiestaVoci += r
                vociConRichiesta = true
            }
            voci.append(VoceCalcolata(
                id: v.id, descrizione: v.descrizione, ammessa: v.ammessa,
                motivoEsclusione: v.ammessa ? nil : (v.motivoEsclusione ?? .nonIndennizzabile),
                quantita: v.quantita, valoreUnitario: v.valoreUnitario,
                totaleANuovo: totaleANuovo, nettoMigliorie: nettoMigliorie, nettoIllesi: nettoIllesi,
                deprezzamentoApplicato: deprezzamento, vsu: vsuPieno, si: siPieno, importo: vsu + si,
                imponibile: valori.vsuImponibile + valori.siImponibile, iva: valori.iva, aliquotaIVA: aliquota,
                richiesta: v.richiesta, giustificativo: v.giustificativo
            ))
        }

        let ivaCalcolataPrimaForzatura = ammesse.iva
        // Liquidazione forzata del bene: è l'importo finale (imponibile + IVA se riconosciuta), come lo
        // mostra la scheda bene. L'imponibile si ripartisce tra VSU e SI in proporzione al calcolo.
        if let forzata = bene.liquidazioneForzata, forzata > 0 {
            let imponibile = bene.ivaRiconosciuta ? (forzata / (1 + bene.aliquotaIVA / cento)).arrotondato() : forzata
            let base = ammesse.vsuImponibile + ammesse.siImponibile
            let vsuF = base > 0 ? (imponibile * ammesse.vsuImponibile / base).arrotondato() : imponibile
            ammesse.vsuImponibile = vsuF
            ammesse.siImponibile = imponibile - vsuF
            ammesse.iva = bene.ivaRiconosciuta ? forzata - imponibile : 0
        }

        var ivaLiquidazione: Decimal = 0, ivaSaldo: Decimal = 0, ivaNonRiconosciuta: Decimal = 0
        if bene.ivaRiconosciuta {
            if bene.ripristiniUltimati { ivaLiquidazione = ammesse.iva } else { ivaSaldo = ammesse.iva }
        } else if bene.ivaInclusaNeiValori {
            ivaNonRiconosciuta = ammesse.iva
        }
        let imponibile = ammesse.vsuImponibile + ammesse.siImponibile
        let totaleEscluso = escluse.vsuImponibile + escluse.siImponibile + (bene.ivaRiconosciuta ? escluse.iva : 0)

        var richiestaEffettiva = bene.richiesta ?? (vociConRichiesta ? richiestaVoci : nil)
        if let q = bene.quotaComunePercentuale, let r = richiestaEffettiva {
            richiestaEffettiva = (r * q / cento).arrotondato()
        }

        return BeneCalcolato(
            id: bene.id, nome: bene.nome, genere: bene.genere, sostituzione: bene.sostituzione,
            partitaId: bene.partitaId, garanziaId: bene.garanziaId, criterio: bene.criterio, voci: voci,
            vsu: ammesse.vsuImponibile, si: ammesse.siImponibile, imponibile: imponibile,
            ivaInLiquidazione: ivaLiquidazione, ivaASaldo: ivaSaldo, ivaNonRiconosciuta: ivaNonRiconosciuta,
            ivaCalcolata: ivaCalcolataPrimaForzatura,
            totaleAmmesso: imponibile + ivaLiquidazione, totaleEscluso: totaleEscluso,
            richiestaEffettiva: richiestaEffettiva,
            liquidazioneForzata: (bene.liquidazioneForzata ?? 0) > 0 ? bene.liquidazioneForzata : nil,
            quotaComunePercentuale: bene.quotaComunePercentuale,
            totaleInteroBeneComune: bene.quotaComunePercentuale != nil ? totaleIntero : nil,
            ripristiniUltimati: bene.ripristiniUltimati
        )
    }

    // MARK: Garanzia

    static func liquida(garanzia: GaranziaInput, beni: [BeneCalcolato], partite: [PartitaInput],
                        arrotondamento: Decimal, negativa: Bool, massimalePrima: Bool) -> LiquidazioneGaranzia {
        let vsu = somma(beni.map(\.vsu))
        let si = somma(beni.map(\.si))
        let ivaLiq = somma(beni.map(\.ivaInLiquidazione))
        let ivaSaldo = somma(beni.map(\.ivaASaldo))
        let totaleVoci = vsu + si + ivaLiq
        let escluso = somma(beni.map(\.totaleEscluso))
        let haAmmesse = beni.contains { $0.voci.contains(where: \.ammessa) }
        let haEscluse = beni.contains { $0.voci.contains { !$0.ammessa } }
        let tuttoNonIndennizzabile = !haAmmesse && haEscluse

        // Danno per partita (l'arrotondamento va sulla partita con l'importo maggiore).
        let infoPartite = Dictionary(partite.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ordine: [String] = partite.map(\.id).filter { pid in beni.contains { $0.partitaId == pid } }
        let senzaPartita = beni.filter { b in b.partitaId == nil || infoPartite[b.partitaId!] == nil }
        if !senzaPartita.isEmpty { ordine.append("") }
        var lordi: [String: Decimal] = [:]
        for pid in ordine {
            lordi[pid] = somma(beni.filter { ($0.partitaId.flatMap { infoPartite[$0] != nil ? $0 : nil } ?? "") == pid }.map(\.totaleAmmesso))
        }
        if negativa { for k in lordi.keys { lordi[k] = 0 } }
        if arrotondamento != 0, let pmax = ordine.max(by: { (lordi[$0] ?? 0) < (lordi[$1] ?? 0) }) {
            lordi[pmax] = max(0, (lordi[pmax] ?? 0) + arrotondamento)
        }
        let lordo = negativa ? 0 : max(0, totaleVoci + arrotondamento)

        // Regola proporzionale (art. 1907 c.c.): solo a valore intero e se il valore reale supera la somma oltre la deroga.
        var dopoRegola: [String: Decimal] = lordi
        var rapporti: [String: Decimal] = [:]
        for pid in ordine where !pid.isEmpty {
            guard let p = infoPartite[pid], p.forma == .valoreIntero, let reale = p.valoreReale,
                  reale > 0, p.sommaAssicurata > 0 else { continue }
            let tolleranza = p.sommaAssicurata * (1 + (p.percentualeDeroga ?? 0) / cento)
            guard reale > tolleranza else { continue }
            let rapporto = p.sommaAssicurata / reale
            rapporti[pid] = rapporto.arrotondato(6)
            dopoRegola[pid] = ((lordi[pid] ?? 0) * rapporto).arrotondato()
        }
        let riduzioneProporzionale = somma(ordine.map { (lordi[$0] ?? 0) - (dopoRegola[$0] ?? 0) })
        let base = lordo - riduzioneProporzionale

        // Franchigia o scoperto: una per garanzia, mai oltre il danno.
        var tipo: TipoTrattenuta = .nessuna
        var trattenuta: Decimal = 0
        if !negativa {
            if garanzia.scopertoPercentuale > 0 {
                trattenuta = (base * garanzia.scopertoPercentuale / cento).arrotondato()
                if garanzia.scopertoMinimo > 0 && trattenuta < garanzia.scopertoMinimo { trattenuta = garanzia.scopertoMinimo }
                if garanzia.scopertoMassimo > 0 && trattenuta > garanzia.scopertoMassimo { trattenuta = garanzia.scopertoMassimo }
                tipo = .scoperto
            } else if garanzia.franchigia > 0 {
                trattenuta = garanzia.franchigiaMassimo > 0 ? min(garanzia.franchigia, garanzia.franchigiaMassimo) : garanzia.franchigia
                tipo = .franchigia
            }
            trattenuta = min(trattenuta, base)
        }

        // Somme assicurate per partita: ogni partita paga al più la sua somma.
        let conLimite = ordine.contains { pid in (infoPartite[pid]?.sommaAssicurata ?? 0) > 0 }
        var dettaglio: [DettaglioPartita] = []
        var limitePartite: Decimal?
        var limitati: [String: Decimal] = [:]
        if conLimite && !negativa {
            for pid in ordine {
                let somma = infoPartite[pid]?.sommaAssicurata ?? 0
                limitati[pid] = somma > 0 ? min(dopoRegola[pid] ?? 0, somma) : (dopoRegola[pid] ?? 0)
            }
            limitePartite = somma(ordine.map { limitati[$0] ?? 0 })
        }

        let dopoTrattenuta: Decimal
        let preMassimale: Decimal
        if massimalePrima {
            preMassimale = min(base, limitePartite ?? base)
            let dopoMassimale = garanzia.massimale > 0 ? min(preMassimale, garanzia.massimale) : preMassimale
            dopoTrattenuta = max(0, dopoMassimale - trattenuta)
        } else {
            dopoTrattenuta = max(0, base - trattenuta)
            preMassimale = min(dopoTrattenuta, limitePartite ?? dopoTrattenuta)
        }
        let massimaleApplicato = garanzia.massimale > 0 && preMassimale > garanzia.massimale
        var liquidabile = massimalePrima ? dopoTrattenuta
            : (garanzia.massimale > 0 ? min(preMassimale, garanzia.massimale) : preMassimale)
        if negativa || tuttoNonIndennizzabile { liquidabile = 0 }

        if limitePartite != nil {
            // La trattenuta si sconta prima sulle eccedenze oltre i limiti, poi sulle partite in ordine.
            var residuo = massimalePrima ? trattenuta
                : max(0, trattenuta - somma(ordine.map { (dopoRegola[$0] ?? 0) - (limitati[$0] ?? 0) }))
            for pid in ordine {
                let limitato = limitati[pid] ?? 0
                let tolto = min(residuo, limitato)
                residuo -= tolto
                let p = infoPartite[pid]
                dettaglio.append(DettaglioPartita(
                    partitaId: pid, nome: p?.nome ?? "Senza partita",
                    dannoAccertato: lordi[pid] ?? 0, rapportoProporzionale: rapporti[pid],
                    dopoRegolaProporzionale: dopoRegola[pid] ?? 0, sommaAssicurata: p?.sommaAssicurata ?? 0,
                    limitata: (dopoRegola[pid] ?? 0) > limitato, liquidabile: limitato - tolto
                ))
            }
        } else if !rapporti.isEmpty {
            for pid in ordine {
                let p = infoPartite[pid]
                dettaglio.append(DettaglioPartita(
                    partitaId: pid, nome: p?.nome ?? "Senza partita", dannoAccertato: lordi[pid] ?? 0,
                    rapportoProporzionale: rapporti[pid], dopoRegolaProporzionale: dopoRegola[pid] ?? 0,
                    sommaAssicurata: p?.sommaAssicurata ?? 0, limitata: false, liquidabile: dopoRegola[pid] ?? 0
                ))
            }
        }

        // Supplemento dei beni non ripristinati: si paga a ripristini ultimati.
        let siNonUltimati = somma(beni.filter { !$0.ripristiniUltimati }.map(\.si))
        let differito: Decimal = (liquidabile > 0 && siNonUltimati > 0 && totaleVoci > 0)
            ? min(liquidabile, (liquidabile * siNonUltimati / totaleVoci).arrotondato()) : 0

        // Riserva: voci escluse. Se tutto è escluso si applicano franchigia/scoperto e massimale come se fosse indennizzabile.
        var dannoNonIndennizzabile = escluso
        if tuttoNonIndennizzabile && !negativa {
            var x: Decimal
            var t: Decimal = 0
            if garanzia.scopertoPercentuale > 0 {
                t = (escluso * garanzia.scopertoPercentuale / cento).arrotondato()
                if garanzia.scopertoMinimo > 0 && t < garanzia.scopertoMinimo { t = garanzia.scopertoMinimo }
                if garanzia.scopertoMassimo > 0 && t > garanzia.scopertoMassimo { t = garanzia.scopertoMassimo }
            } else if garanzia.franchigia > 0 {
                t = garanzia.franchigiaMassimo > 0 ? min(garanzia.franchigia, garanzia.franchigiaMassimo) : garanzia.franchigia
            }
            if massimalePrima {
                x = garanzia.massimale > 0 ? min(escluso, garanzia.massimale) : escluso
                x = max(0, x - t)
            } else {
                x = max(0, escluso - t)
                if garanzia.massimale > 0 { x = min(x, garanzia.massimale) }
            }
            dannoNonIndennizzabile = x
        }

        return LiquidazioneGaranzia(
            garanziaId: garanzia.id, nome: garanzia.nome,
            totaleVoci: negativa ? 0 : totaleVoci, arrotondamento: negativa ? 0 : arrotondamento,
            vsu: negativa ? 0 : vsu, si: negativa ? 0 : si,
            ivaInLiquidazione: negativa ? 0 : ivaLiq, ivaASaldo: negativa ? 0 : ivaSaldo,
            dannoAccertato: lordo, riduzioneProporzionale: riduzioneProporzionale,
            tipoTrattenuta: tipo, trattenuta: (negativa || tuttoNonIndennizzabile) ? 0 : trattenuta,
            dopoTrattenuta: (negativa || tuttoNonIndennizzabile) ? 0 : dopoTrattenuta,
            partite: dettaglio, limitePartite: limitePartite,
            massimale: garanzia.massimale, massimaleApplicato: massimaleApplicato && !negativa && !tuttoNonIndennizzabile,
            liquidabilePrimaRiparto: nil, liquidabile: liquidabile, liquidabileDifferito: differito,
            dannoNonIndennizzabile: dannoNonIndennizzabile, tuttoNonIndennizzabile: tuttoNonIndennizzabile
        )
    }

    // MARK: Riparto art. 1910 c.c.

    /// Stesso rischio assicurato con altre polizze: quota = danno × indennizzo virtuale proprio / somma
    /// degli indennizzi virtuali, mai oltre l'indennizzo proprio. Il liquidabile di ogni garanzia si riduce in proporzione.
    static func applicaRiparto1910(_ raw: Riparto1910Input, liquidazioni: inout [LiquidazioneGaranzia]) -> RipartoCalcolato? {
        let propria = somma(liquidazioni.map(\.liquidabile))
        let danno = somma(liquidazioni.map(\.dannoAccertato))
        let altre = somma(raw.altrePolizze.map(\.indennizzoVirtuale))
        let totale = propria + altre
        guard propria > 0, totale > 0 else { return nil }
        let quota = min(propria, (danno * propria / totale).arrotondato())
        var assegnato: Decimal = 0
        for i in liquidazioni.indices {
            let prima = liquidazioni[i].liquidabile
            let nuovo = i == liquidazioni.count - 1 ? quota - assegnato : (prima * quota / propria).arrotondato()
            assegnato += nuovo
            liquidazioni[i].liquidabilePrimaRiparto = prima
            liquidazioni[i].liquidabile = nuovo
            liquidazioni[i].liquidabileDifferito = min(nuovo, liquidazioni[i].liquidabileDifferito)
        }
        var righe: [RigaRiparto] = []
        var resto = quota - danno
        for (k, a) in raw.altrePolizze.enumerated() {
            let importo = k == raw.altrePolizze.count - 1 ? resto : -(danno * a.indennizzoVirtuale / totale).arrotondato()
            resto -= importo
            let nome = (!a.compagnia.isEmpty && !a.polizza.isEmpty) ? "\(a.compagnia) n. \(a.polizza)"
                : (a.descrizione.isEmpty ? "altra polizza" : a.descrizione)
            righe.append(RigaRiparto(
                descrizione: "Quota assolta dalla polizza \(nome)" + (a.sinistro.isEmpty ? "" : " (sinistro \(a.sinistro))") + " – riparto art. 1910 c.c.",
                importo: importo))
        }
        return RipartoCalcolato(dannoAccertato: danno, indennizzoVirtuale: propria,
                                sommaIndennizziVirtuali: totale, quota: quota, righe: righe)
    }

    // MARK: Workflow

    static func calcolaWorkflow(input: StimaInput, liquidabile: Decimal) -> WorkflowStima {
        let sopra = liquidabile > input.sogliaControllo
        let motivo: String
        switch input.esito {
        case .negativo: motivo = "Esito negativo: relazione completa con motivazione"
        case .nonConcordato: motivo = "Non concordato: relazione completa a qualsiasi importo"
        default:
            motivo = sopra
                ? "Liquidabile oltre \(euroIt(input.sogliaControllo)) €: relazione completa e controllo"
                : "Liquidabile entro \(euroIt(input.sogliaControllo)) €: perizia semplificata"
        }
        return WorkflowStima(soglia: input.sogliaControllo, sopraSoglia: sopra,
                             relazioneCompleta: sopra || input.esito == .negativo || input.esito == .nonConcordato,
                             motivo: motivo)
    }

    // MARK: Avvisi (non bloccanti)

    static func calcolaAvvisi(input: StimaInput, beni: [BeneCalcolato], liquidazioni: [LiquidazioneGaranzia],
                              totali: TotaliStima, garanziaIds: Set<String>, workflow: WorkflowStima) -> [String] {
        var out: [String] = []
        let negativa = input.esito == .negativo
        if !negativa && totali.liquidabile.haCentesimi {
            out.append("Il liquidabile ha i centesimi: valuta un arrotondamento (per difetto).")
        }
        if !negativa, let r = totali.richiesta, totali.liquidabile > r {
            out.append("Il liquidabile supera la richiesta dell'assicurato.")
        }
        if input.arrotondamento > 0 && !negativa {
            out.append("Arrotondamento in aumento: di regola si arrotonda per difetto.")
        }
        if !input.beniInBozza.isEmpty {
            out.append("\(input.beniInBozza.count) ben\(input.beniInBozza.count == 1 ? "e" : "i") in bozza senza partita: non conteggiat\(input.beniInBozza.count == 1 ? "o" : "i") nella stima.")
        }
        for b in input.beni where b.garanziaId == nil || !garanziaIds.contains(b.garanziaId!) {
            out.append("Il bene «\(b.nome)» non è collegato a una garanzia: escluso dal calcolo.")
        }
        for b in input.beni {
            let conGiustificativo = b.voci.contains(where: \.giustificativo)
            if b.richiesta != nil && !conGiustificativo {
                out.append("Bene «\(b.nome)»: richiesta senza voci con giustificativo (la richiesta va letta da fattura/preventivo).")
            }
            if (b.liquidazioneForzata ?? 0) > 0 {
                out.append("Bene «\(b.nome)»: liquidazione forzata a € \(euroIt(b.liquidazioneForzata!)).")
            }
            for v in b.voci where !v.ammessa && v.motivoEsclusione == nil {
                out.append("Voce «\(v.descrizione)» esclusa senza motivo: nei testi risulterà «non indennizzabile».")
            }
            for v in b.voci where v.ammessa && v.quantita * v.valoreUnitario == 0 && v.totaleANuovoForzato == nil {
                out.append("Voce «\(v.descrizione)» ammessa con importo zero.")
            }
        }
        for p in input.partite where !p.acquistata {
            if input.beni.contains(where: { $0.partitaId == p.id }) {
                out.append("La partita «\(p.nome)» risulta non acquistata in polizza ma ha beni in stima.")
            }
        }
        for l in liquidazioni {
            if l.massimaleApplicato {
                out.append("Garanzia «\(l.nome)»: indennizzo contenuto nel massimale di € \(euroIt(l.massimale)).")
            }
            for p in l.partite where p.limitata {
                out.append("Partita «\(p.nome)»: indennizzo contenuto nella somma assicurata di € \(euroIt(p.sommaAssicurata)).")
            }
            for p in l.partite where p.rapportoProporzionale != nil {
                out.append("Partita «\(p.nome)»: applicata la regola proporzionale (art. 1907 c.c.).")
            }
            if l.tuttoNonIndennizzabile {
                out.append("Garanzia «\(l.nome)»: tutte le voci sono escluse, liquidabile a zero.")
            }
        }
        if !totali.ivaASaldo.isZero {
            out.append("IVA a saldo di € \(euroIt(totali.ivaASaldo)): riconosciuta a ripristini ultimati, non entra nell'importo dell'atto.")
        }
        if totali.rettifiche != 0 {
            out.append("Rettifiche manuali dopo i limiti: € \(euroIt(totali.rettifiche)).")
        }
        if input.esito == .nonConcordato && input.motivoNonConcordato == nil {
            out.append("Non concordato senza motivo: le conclusioni useranno «atto non restituito».")
        }
        if negativa && !input.dannoNonAccertato && (input.riservaMotivo ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("Esito negativo senza motivo della riserva.")
        }
        if (input.esito == .concordato || input.esito == .nonConcordato) && totali.liquidabile == 0 {
            out.append("Esito \(input.esito.etichetta.lowercased()) con liquidabile a zero: valuta l'esito negativo.")
        }
        if let iban = input.iban?.replacingOccurrences(of: " ", with: ""), !iban.isEmpty, !StimaEngine.ibanValido(iban) {
            out.append("IBAN non valido (controllo mod 97): verificarlo prima dell'atto.")
        }
        if !input.rettifiche.isEmpty && negativa {
            out.append("Esito negativo: le rettifiche manuali sono ignorate.")
        }
        return out
    }

    // MARK: Scomposizione richiesto → accertato → liquidabile

    static func scomposizione(input: StimaInput, calcolo: StimaCalcolo) -> [PassoScomposizione] {
        var passi: [PassoScomposizione] = []
        var gruppiEsclusi: [MotivoEsclusione: (Decimal, [String])] = [:]
        var ordineMotivi: [MotivoEsclusione] = []
        var lordoVoci: Decimal = 0
        var rettifiche: Decimal = 0, nomiRettifiche: [String] = []
        var riduzioni: Decimal = 0, nomiRiduzioni: [String] = []
        var ivaNon: Decimal = 0, nomiIva: [String] = []
        var ivaScorporata: Decimal = 0, nomiIvaScorporata: [String] = []
        var ivaAggiunta: Decimal = 0
        var ivaSaldoLorda: Decimal = 0, nomiIvaSaldo: [String] = []
        var quote: Decimal = 0, nomiQuote: [String] = []

        let beniInput = Dictionary(input.beni.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for bene in calcolo.beni {
            guard let bi = beniInput[bene.id] else { continue }
            let vociInput = Dictionary(bi.voci.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for v in bene.voci {
                guard let vi = vociInput[v.id] else { continue }
                let pieno = v.totaleANuovo
                if !v.ammessa {
                    let valore = v.richiesta ?? pieno
                    let motivo = v.motivoEsclusione ?? .nonIndennizzabile
                    if gruppiEsclusi[motivo] == nil { ordineMotivi.append(motivo); gruppiEsclusi[motivo] = (0, []) }
                    gruppiEsclusi[motivo]!.0 += valore
                    gruppiEsclusi[motivo]!.1.append(v.descrizione)
                    lordoVoci += valore
                    continue
                }
                lordoVoci += v.richiesta ?? pieno
                let rettifica = pieno - (v.vsu + v.si)
                if rettifica > 0 { rettifiche += rettifica; nomiRettifiche.append(v.descrizione) }
                if v.vsu + v.si > v.importo { quote += v.vsu + v.si - v.importo; nomiQuote.append(v.descrizione) }
                if var base = v.richiesta {
                    // Giustificativo IVA inclusa con valori di stima netti: l'IVA della richiesta è una riga a sé.
                    if vi.richiestaIvaInclusa && !bi.ivaInclusaNeiValori {
                        let iva = (base - base / (1 + v.aliquotaIVA / cento)).arrotondato()
                        if iva > 0 {
                            if bi.ivaRiconosciuta { ivaScorporata += iva; nomiIvaScorporata.append(v.descrizione) }
                            else { ivaNon += iva; nomiIva.append(v.descrizione) }
                        }
                        base -= iva
                    }
                    let riduzione = base - pieno
                    if riduzione > 0 { riduzioni += riduzione; nomiRiduzioni.append(v.descrizione) }
                }
            }
            if bi.ivaInclusaNeiValori {
                // Valori lordi: l'IVA scorporata e non riconosciuta, o rinviata a saldo, esce dall'accertato.
                if !bi.ivaRiconosciuta && bene.ivaCalcolata > 0 { ivaNon += bene.ivaCalcolata; nomiIva.append(bene.nome) }
                if bene.ivaASaldo > 0 { ivaSaldoLorda += bene.ivaASaldo; nomiIvaSaldo.append(bene.nome) }
            } else {
                ivaAggiunta += bene.ivaInLiquidazione
            }
        }
        let negativa = calcolo.esito == .negativo
        let richiesta = calcolo.totali.richiesta ?? lordoVoci
        func elenco(_ nomi: [String]) -> String {
            let unici = nomi.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return unici.count > 3 ? unici.prefix(3).joined(separator: ", ") + " e altre \(unici.count - 3)" : unici.joined(separator: ", ")
        }
        func passo(_ fase: FaseScomposizione, _ etichetta: String, _ importo: Decimal, _ nota: String = "") {
            passi.append(PassoScomposizione(fase: fase, etichetta: etichetta, importo: importo.arrotondato(), nota: nota))
        }
        for motivo in ordineMotivi {
            let (valore, nomi) = gruppiEsclusi[motivo]!
            passo(.richiestaAccertato, nomi.count > 1 ? motivo.etichettaPlurale : motivo.etichetta, -valore, elenco(nomi))
        }
        if rettifiche > 0 { passo(.richiestaAccertato, "Migliorie, illesi e deprezzamento", -rettifiche, elenco(nomiRettifiche)) }
        if ivaScorporata > 0 { passo(.richiestaAccertato, "IVA scorporata dalla richiesta", -ivaScorporata, "riconosciuta sull'accertato: " + elenco(nomiIvaScorporata)) }
        if ivaNon > 0 { passo(.richiestaAccertato, "IVA non riconosciuta", -ivaNon, "scorporata: " + elenco(nomiIva)) }
        if riduzioni > 0 { passo(.richiestaAccertato, "Valutazione inferiore al richiesto", -riduzioni, elenco(nomiRiduzioni)) }
        if quote > 0 { passo(.richiestaAccertato, "Quota beni comuni di altre polizze", -quote, elenco(nomiQuote)) }
        if ivaSaldoLorda > 0 { passo(.richiestaAccertato, "IVA a saldo", -ivaSaldoLorda, "riconosciuta a ripristini ultimati: " + elenco(nomiIvaSaldo)) }
        let forzature = calcolo.beni.filter { $0.liquidazioneForzata != nil }
        let arr = input.esito == .negativo ? 0 : input.arrotondamento
        if !forzature.isEmpty {
            let delta = somma(forzature.map { b -> Decimal in
                var d = b.vsu + b.si - somma(b.voci.filter(\.ammessa).map(\.imponibile))
                if let bi = beniInput[b.id], bi.ivaInclusaNeiValori, bi.ivaRiconosciuta {
                    d += b.ivaInLiquidazione + b.ivaASaldo - b.ivaCalcolata
                }
                return d
            })
            if delta != 0 { passo(.richiestaAccertato, "Liquidazione forzata sul bene", delta, elenco(forzature.map(\.nome))) }
        }
        if ivaAggiunta > 0 { passo(.richiestaAccertato, "IVA riconosciuta", ivaAggiunta, "aggiunta ai valori di stima") }
        if !negativa {
            if arr != 0 { passo(.richiestaAccertato, "Arrotondamento", arr, arr > 0 ? "per eccesso" : "per difetto") }
        } else {
            let accertabile = somma(calcolo.beni.map { $0.totaleAmmesso })
            if accertabile > 0 {
                passo(.richiestaAccertato, input.dannoNonAccertato ? "Stima conservativa (non accertata)" : "Danno non indennizzabile",
                      -accertabile, "esito negativo")
            }
        }
        let accertato = calcolo.totali.dannoAccertato
        let resto = accertato - richiesta - somma(passi.map(\.importo))
        if abs(resto) > Decimal(string: "0.5")! {
            passo(.richiestaAccertato, resto < 0 ? "Differenza sulla richiesta" : "Voci oltre la richiesta", resto,
                  resto < 0 ? "richiesta a corpo superiore alle voci stimate" : "stima superiore all'importo richiesto")
        }

        // Accertato → liquidabile
        for l in calcolo.liquidazioni where !negativa {
            let suffisso = calcolo.liquidazioni.count > 1 ? " – \(l.nome)" : ""
            if l.riduzioneProporzionale > 0 {
                passo(.accertatoLiquidabile, "Regola proporzionale" + suffisso, -l.riduzioneProporzionale, "art. 1907 c.c.")
            }
            if l.trattenuta > 0 {
                passo(.accertatoLiquidabile, (l.tipoTrattenuta == .scoperto ? "Scoperto" : "Franchigia") + suffisso, -l.trattenuta,
                      l.tipoTrattenuta == .scoperto ? "contrattuale" : "contrattuale")
            }
            let base = l.dannoAccertato - l.riduzioneProporzionale - l.trattenuta
            let primaRiparto = l.liquidabilePrimaRiparto ?? l.liquidabile
            let limiti = max(0, base) - primaRiparto
            if limiti > 0 {
                let nota = l.massimaleApplicato ? "massimale € \(euroIt(l.massimale))" : "somma assicurata della partita"
                passo(.accertatoLiquidabile, "Limiti di polizza" + suffisso, -limiti, nota)
            }
            if l.tuttoNonIndennizzabile && l.dannoAccertato > 0 {
                passo(.accertatoLiquidabile, "Non indennizzabile" + suffisso, -l.dannoAccertato, "tutte le voci escluse")
            }
            if let prima = l.liquidabilePrimaRiparto, prima != l.liquidabile {
                passo(.accertatoLiquidabile, "Riparto art. 1910 c.c." + suffisso, l.liquidabile - prima, "quote di altre polizze")
            }
        }
        for r in calcolo.rettifiche where r.importo != 0 {
            passo(.accertatoLiquidabile, r.descrizione.isEmpty ? "Rettifica" : r.descrizione, r.importo, "rettifica manuale")
        }
        return passi
    }

    // MARK: Arrotondamento assistito

    /// Arrotondamento (entro ±100) che porta il liquidabile esattamente a `obiettivo`, se esiste.
    static func arrotondamentoPer(obiettivo: Decimal, input: StimaInput) -> Decimal? {
        guard let attuale = try? calcola(input) else { return nil }
        let delta = obiettivo - attuale.totali.liquidabile
        if delta == 0 { return input.arrotondamento }
        var candidati: [Decimal] = [input.arrotondamento + delta]
        if let gid = garanziaArrotondamento(input), let g = input.garanzie.first(where: { $0.id == gid }),
           g.scopertoPercentuale > 0, g.scopertoPercentuale < cento {
            let corretto = (input.arrotondamento + delta / (1 - g.scopertoPercentuale / cento)).arrotondato()
            candidati += [corretto, corretto - Decimal(string: "0.01")!, corretto + Decimal(string: "0.01")!]
        }
        for c in candidati where abs(c) <= arrotondamentoMassimo {
            var prova = input
            prova.arrotondamento = c
            if let r = try? calcola(prova), r.totali.liquidabile == obiettivo { return c }
        }
        return nil
    }

    // MARK: IBAN

    static func ibanValido(_ iban: String) -> Bool {
        let x = iban.replacingOccurrences(of: " ", with: "").uppercased()
        guard x.count >= 15, x.count <= 34, x.prefix(2).allSatisfy(\.isLetter), x.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return false
        }
        let riordinato = x.dropFirst(4) + x.prefix(4)
        var resto = 0
        for c in riordinato {
            guard let v = Int(String(c), radix: 36) else { return false }
            for cifra in String(v) {
                resto = (resto * 10 + Int(String(cifra))!) % 97
            }
        }
        return resto == 1
    }
}

// MARK: - Hash

enum StimaHash {
    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hash dell'intera fotografia (importi, testi, avvisi).
    static func completo(_ calcolo: StimaCalcolo) -> String {
        var c = calcolo
        c.hashCalcolo = ""
        c.hashEconomico = ""
        return sha256((try? encoder().encode(c)) ?? Data())
    }

    /// Impronta economica: cambia solo se cambia la stima in denaro (esito, voci, limiti, totali).
    /// Testi, nomi, note e dati di pagamento non contano: se l'impronta non cambia l'approvazione si eredita.
    static func economico(_ calcolo: StimaCalcolo) -> String {
        struct VoceEco: Encodable {
            let quantita, valoreUnitario, totaleANuovo, nettoIllesi, vsu, si, importo, imponibile, iva: Decimal
            let richiesta: Decimal?
            let ammessa: Bool
        }
        struct BeneEco: Encodable {
            let partitaId, garanziaId: String?
            let criterio: String
            let totaleAmmesso, totaleEscluso, ivaASaldo: Decimal
            let richiesta, forzata, quota: Decimal?
            let voci: [VoceEco]
        }
        struct LiqEco: Encodable {
            let garanziaId: String
            let dannoAccertato, arrotondamento, riduzioneProporzionale, trattenuta, massimale, liquidabile, differito: Decimal
            let tipo: String
            let partite: [String]
        }
        struct Impronta: Encodable {
            let esito: String
            let dannoNonAccertato: Bool
            let totali: TotaliStima
            let beni: [BeneEco]
            let liquidazioni: [LiqEco]
            let riparto: Decimal?
            let rettifiche: [Decimal]
        }
        let esito: String
        switch calcolo.esito {
        case .negativo: esito = "NEGATIVO"
        case .nonConcordato: esito = "NON_CONCORDATO"
        default: esito = "POSITIVO" // in lavorazione e concordato hanno lo stesso importo
        }
        let impronta = Impronta(
            esito: esito,
            dannoNonAccertato: calcolo.dannoNonAccertato,
            totali: calcolo.totali,
            beni: calcolo.beni.map { b in
                BeneEco(partitaId: b.partitaId, garanziaId: b.garanziaId, criterio: b.criterio.rawValue,
                        totaleAmmesso: b.totaleAmmesso, totaleEscluso: b.totaleEscluso, ivaASaldo: b.ivaASaldo,
                        richiesta: b.richiestaEffettiva, forzata: b.liquidazioneForzata, quota: b.quotaComunePercentuale,
                        voci: b.voci.map { v in
                            VoceEco(quantita: v.quantita, valoreUnitario: v.valoreUnitario, totaleANuovo: v.totaleANuovo,
                                    nettoIllesi: v.nettoIllesi, vsu: v.vsu, si: v.si, importo: v.importo,
                                    imponibile: v.imponibile, iva: v.iva, richiesta: v.richiesta, ammessa: v.ammessa)
                        })
            },
            liquidazioni: calcolo.liquidazioni.map { l in
                LiqEco(garanziaId: l.garanziaId, dannoAccertato: l.dannoAccertato, arrotondamento: l.arrotondamento,
                       riduzioneProporzionale: l.riduzioneProporzionale, trattenuta: l.trattenuta, massimale: l.massimale,
                       liquidabile: l.liquidabile, differito: l.liquidabileDifferito, tipo: l.tipoTrattenuta.rawValue,
                       partite: l.partite.filter(\.limitata).map { "\($0.partitaId):\($0.sommaAssicurata):\($0.liquidabile)" })
            },
            riparto: calcolo.riparto1910?.quota,
            rettifiche: calcolo.rettifiche.map(\.importo)
        )
        return sha256((try? encoder().encode(impronta)) ?? Data())
    }
}
