import Foundation
import CoreData

/// Ponte tra la perizia in Core Data e il motore di stima: fotografia dell'input, calcolo,
/// riscrittura dei valori derivati delle voci, revisioni e approvazione, verifica dell'atto firmato.
final class StimaService {
    static let shared = StimaService()
    private init() {}

    static let chiaveSogliaControllo = "perx.stima.sogliaControllo"

    /// Soglia (€) oltre la quale servono relazione completa e controllo. Default 5.000,00.
    var sogliaControllo: Decimal {
        let valore = UserDefaults.standard.double(forKey: Self.chiaveSogliaControllo)
        return valore > 0 ? decimale(valore) : 5000
    }

    // MARK: - Fotografia dell'input

    func input(per perizia: Perizia) -> StimaInput {
        var x = StimaInput()
        x.riferimento = perizia.sinistro?.riferimento
        x.richiestaSinistro = positivo(perizia.richiestaSinistro)
        x.sogliaControllo = sogliaControllo

        x.partite = perizia.partiteArray.map { p in
            PartitaInput(
                id: p.wrappedId.uuidString,
                nome: p.nomeEditabile.isEmpty ? p.tipoPartita : p.nomeEditabile,
                tipo: p.tipoPartita,
                forma: FormaGaranzia(stringa: p.tipologia),
                sommaAssicurata: decimale(p.valoreAssicurato) ?? 0,
                valoreReale: positivo(p.valoreReale),
                percentualeDeroga: decimale(p.percentualeDeroga),
                acquistata: p.partitaAcquistata
            )
        }
        let garanzie = perizia.garanzieArray
        x.garanzie = garanzie.map { g in
            GaranziaInput(
                id: g.wrappedId.uuidString,
                nome: g.nomeEditabile.isEmpty ? g.tipoGaranzia : g.nomeEditabile,
                massimale: decimale(g.massimale) ?? 0,
                franchigia: decimale(g.franchigiaMinimo) ?? 0,
                franchigiaMassimo: decimale(g.franchigiaMassimo) ?? 0,
                scopertoPercentuale: decimale(g.scopertoPercentuale) ?? 0,
                scopertoMinimo: decimale(g.scopertoMinimo) ?? 0,
                scopertoMassimo: decimale(g.scopertoMassimo) ?? 0
            )
        }
        // Con una sola garanzia i beni senza garanzia vi rientrano (come preseleziona la scheda del bene).
        let garanziaUnica = garanzie.count == 1 ? garanzie.first?.wrappedId.uuidString : nil
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                x.beni.append(beneInput(bene, partitaId: partita.wrappedId.uuidString, garanziaDefault: garanziaUnica))
            }
        }
        x.beniInBozza = perizia.beniBozzaArray.map(\.nome)

        x.arrotondamento = decimale(perizia.arrotondamentoLiquidazione) ?? 0
        x.arrotondamentoGaranziaId = perizia.arrotondamentoGaranziaId?.uuidString
        x.massimalePrimaDellaTrattenuta = perizia.massimalePrimaFranchigia
        x.rettifiche = rettifiche(perizia)
        x.esito = perizia.esitoStimaValue
        x.dannoNonAccertato = perizia.dannoNonAccertato
        x.motivoNonConcordato = perizia.motivoNonConcordato.flatMap(MotivoNonConcordato.init(rawValue:))
        x.motivoNonConcordatoTesto = perizia.motivoNonConcordatoTesto
        x.riservaMotivo = perizia.noteRiserva
        x.accompagnatoriaExtra = perizia.accompagnatoriaExtra

        if perizia.riparto1910Attivo, let sinistro = perizia.sinistro {
            let altre = sinistro.coassicurazioniArray
                .filter { $0.tipo.lowercased().contains("indiretta") }
                .map { c in
                    AltraPolizzaInput(descrizione: "", compagnia: c.compagnia, polizza: c.polizza,
                                      sinistro: c.numeroSinistro, indennizzoVirtuale: decimale(c.indennizzoVirtuale) ?? 0)
                }
            x.riparto1910 = Riparto1910Input(attivo: true, altrePolizze: altre)
        }
        return x
    }

    private func beneInput(_ bene: Bene, partitaId: String, garanziaDefault: String?) -> BeneInput {
        BeneInput(
            id: bene.wrappedId.uuidString,
            nome: bene.nome,
            genere: bene.genere == "f" ? "f" : "m",
            sostituzione: bene.sostituzioneIntero,
            partitaId: partitaId,
            garanziaId: bene.garanzia?.wrappedId.uuidString ?? garanziaDefault,
            richiesta: positivo(bene.richiesta),
            criterio: CriterioIndennizzo(stringa: bene.determinazioneDannoEffettiva),
            deprezzamentoPercentuale: decimale(bene.deprezzamento),
            aliquotaIVA: decimale(bene.aliquotaIVA > 0 ? bene.aliquotaIVA : 22),
            ivaInclusaNeiValori: bene.ivaInclusa,
            ivaRiconosciuta: bene.riconosciIVA,
            ripristiniUltimati: bene.ripristiniUltimati,
            liquidazioneForzata: positivo(bene.liquidazioneForzata),
            quotaComunePercentuale: positivo(bene.quotaComunePercentuale),
            unitaServite: bene.unitaServite > 0 ? Int(bene.unitaServite) : nil,
            voci: bene.vociCostoArray.map { voceInput($0, diversiPerRiga: bene.diversiPerRiga) }
        )
    }

    private func voceInput(_ v: VoceCosto, diversiPerRiga: Bool) -> VoceInput {
        func forzato(_ campo: String, _ valore: NSDecimalNumber?) -> Decimal? {
            v.isForzato(campo) ? decimale(valore) : nil
        }
        return VoceInput(
            id: v.wrappedId.uuidString,
            descrizione: v.descrizione,
            quantita: decimale(v.quantita) ?? 0,
            valoreUnitario: decimale(v.valoreUnitario) ?? 0,
            percentualeMigliorie: decimale(v.percentualeMigliorie) ?? 0,
            percentualeIllesi: decimale(v.percentualeIllesi) ?? 0,
            deprezzamentoPercentuale: diversiPerRiga ? decimale(v.deprezzamentoRiga) : nil,
            aliquotaIVA: diversiPerRiga ? decimale(v.aliquotaIVARiga) : nil,
            totaleANuovoForzato: forzato("totaleANuovo", v.totaleANuovo),
            nettoMigliorieForzato: forzato("nettoMigliorie", v.nettoMigliorie),
            nettoIllesiForzato: forzato("nettoIllesi", v.nettoIllesi),
            vsuForzato: forzato("vsu", v.vsu),
            siForzato: forzato("si", v.si),
            ammessa: v.indennizzabile,
            motivoEsclusione: v.indennizzabile ? nil : v.motivoEsclusioneValue,
            nota: v.notaVoce,
            giustificativo: v.giustificativo,
            richiesta: positivo(v.richiesta),
            richiestaIvaInclusa: v.richiestaIvaInclusa && positivo(v.richiesta) != nil
        )
    }

    private func rettifiche(_ perizia: Perizia) -> [RettificaInput] {
        guard let json = perizia.vociPersonalizzateJSON, let data = json.data(using: .utf8),
              let voci = try? JSONDecoder().decode([VocePersonalizzata].self, from: data) else { return [] }
        return voci.map { RettificaInput(id: $0.id.uuidString, descrizione: $0.descrizione, importo: decimale($0.valore).arrotondato()) }
    }

    // MARK: - Calcolo

    func calcola(_ perizia: Perizia) -> Result<StimaCalcolo, StimaErrori> {
        do {
            return .success(try StimaEngine.calcola(input(per: perizia)))
        } catch let errori as StimaErrori {
            return .failure(errori)
        } catch {
            return .failure(StimaErrori(messaggi: [error.localizedDescription]))
        }
    }

    func calcolo(_ perizia: Perizia) -> StimaCalcolo? {
        try? calcola(perizia).get()
    }

    /// Riscrive sulle voci i valori derivati del motore (totale a nuovo, netti, VSU, SI) senza toccare
    /// quelli forzati a mano, e aggiorna la stima del danno salvata in perizia. Non salva il contesto.
    @discardableResult
    func allineaValoriDerivati(_ perizia: Perizia) -> StimaCalcolo? {
        guard let calcolo = calcolo(perizia) else { return nil }
        let vociCalcolate = Dictionary(calcolo.beni.flatMap(\.voci).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for partita in perizia.partiteArray {
            for bene in partita.beniArray {
                for voce in bene.vociCostoArray {
                    guard let c = vociCalcolate[voce.wrappedId.uuidString] else { continue }
                    imposta(voce, "totaleANuovo", c.totaleANuovo) { voce.totaleANuovo = $0 } attuale: { voce.totaleANuovo }
                    imposta(voce, "nettoMigliorie", c.nettoMigliorie) { voce.nettoMigliorie = $0 } attuale: { voce.nettoMigliorie }
                    imposta(voce, "nettoIllesi", c.nettoIllesi) { voce.nettoIllesi = $0 } attuale: { voce.nettoIllesi }
                    imposta(voce, "vsu", c.vsu) { voce.vsu = $0 } attuale: { voce.vsu }
                    imposta(voce, "si", c.si) { voce.si = $0 } attuale: { voce.si }
                }
            }
        }
        let liquidabile = NSDecimalNumber(decimal: calcolo.totali.liquidabile)
        if perizia.stimaDannoIndennizzabile != liquidabile {
            perizia.stimaDannoIndennizzabile = liquidabile
        }
        return calcolo
    }

    private func imposta(_ voce: VoceCosto, _ campo: String, _ valore: Decimal,
                         _ set: (NSDecimalNumber) -> Void, attuale: () -> NSDecimalNumber?) {
        guard !voce.isForzato(campo) else { return }
        let nuovo = NSDecimalNumber(decimal: valore)
        if attuale()?.compare(nuovo) != .orderedSame { set(nuovo) }
    }

    /// Ricalcola i valori derivati della singola voce (dopo una modifica in tabella).
    func aggiornaVoce(_ voce: VoceCosto) {
        guard let bene = voce.bene else { return }
        let perizia = bene.partita?.perizia ?? bene.periziaBozza
        if let perizia, bene.partita != nil {
            allineaValoriDerivati(perizia)
            return
        }
        // Bene in bozza: calcolo del solo bene.
        let calcolato = StimaEngine.calcolaBene(beneInput(bene, partitaId: "", garanziaDefault: nil))
        if let c = calcolato.voci.first(where: { $0.id == voce.wrappedId.uuidString }) {
            imposta(voce, "totaleANuovo", c.totaleANuovo) { voce.totaleANuovo = $0 } attuale: { voce.totaleANuovo }
            imposta(voce, "nettoMigliorie", c.nettoMigliorie) { voce.nettoMigliorie = $0 } attuale: { voce.nettoMigliorie }
            imposta(voce, "nettoIllesi", c.nettoIllesi) { voce.nettoIllesi = $0 } attuale: { voce.nettoIllesi }
            imposta(voce, "vsu", c.vsu) { voce.vsu = $0 } attuale: { voce.vsu }
            imposta(voce, "si", c.si) { voce.si = $0 } attuale: { voce.si }
        }
    }

    /// Calcolo del singolo bene (anche in bozza), per i totali della scheda bene.
    func calcoloBene(_ bene: Bene, ignoraForzatura: Bool = false) -> BeneCalcolato {
        let garanzie = (bene.partita?.perizia ?? bene.periziaBozza)?.garanzieArray ?? []
        let garanziaUnica = garanzie.count == 1 ? garanzie.first?.wrappedId.uuidString : nil
        var input = beneInput(bene, partitaId: bene.partita?.wrappedId.uuidString ?? "", garanziaDefault: garanziaUnica)
        if ignoraForzatura { input.liquidazioneForzata = nil }
        return StimaEngine.calcolaBene(input)
    }

    // MARK: - Revisioni e approvazione

    enum StatoStima: Equatable {
        case errori([String])
        case nessunaRevisione
        /// La stima corrente non è ancora fotografata in una revisione.
        case daSalvare(ultima: Int32, economiaCambiata: Bool)
        case daApprovare(Int32)
        case approvata(Int32, ereditata: Bool)

        var etichetta: String {
            switch self {
            case .errori: return "Stima con errori"
            case .nessunaRevisione: return "Stima non salvata"
            case .daSalvare(let n, let eco): return eco ? "Modificata dopo la rev. \(n)" : "Testi modificati dopo la rev. \(n)"
            case .daApprovare(let n): return "Rev. \(n) da approvare"
            case .approvata(let n, let ereditata): return ereditata ? "Rev. \(n) approvata (ereditata)" : "Rev. \(n) approvata"
            }
        }

        var approvata: Bool {
            if case .approvata = self { return true }
            return false
        }
    }

    func ultimaRevisione(_ perizia: Perizia) -> StimaRevisione? {
        perizia.stimaRevisioniArray.last
    }

    /// Ultima revisione approvata e non superata: l'unica valida per l'atto.
    func revisioneValida(_ perizia: Perizia) -> StimaRevisione? {
        perizia.stimaRevisioniArray.last { $0.approvata && !$0.superata }
    }

    func stato(_ perizia: Perizia, calcolo: StimaCalcolo? = nil) -> StatoStima {
        let corrente: StimaCalcolo
        if let calcolo { corrente = calcolo } else {
            switch calcola(perizia) {
            case .success(let c): corrente = c
            case .failure(let e): return .errori(e.messaggi)
            }
        }
        guard let ultima = ultimaRevisione(perizia) else { return .nessunaRevisione }
        if ultima.hashCalcolo != corrente.hashCalcolo {
            // Testi o dati non economici cambiati: l'approvazione resta valida finché l'economia non cambia.
            let ecoCambiata = ultima.hashEconomico != corrente.hashEconomico
            if !ecoCambiata && ultima.approvata { return .approvata(ultima.numero, ereditata: ultima.ereditataDa > 0) }
            return .daSalvare(ultima: ultima.numero, economiaCambiata: ecoCambiata)
        }
        return ultima.approvata ? .approvata(ultima.numero, ereditata: ultima.ereditataDa > 0) : .daApprovare(ultima.numero)
    }

    /// Fotografa la stima corrente in una nuova revisione. Se la precedente era approvata e l'impronta
    /// economica è identica, l'approvazione si eredita (cambiano solo testi, nomi, note).
    @discardableResult
    func salvaRevisione(_ perizia: Perizia, context: NSManagedObjectContext, nota: String? = nil) throws -> StimaRevisione {
        let input = input(per: perizia)
        let calcolo = try StimaEngine.calcola(input)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let precedente = ultimaRevisione(perizia)

        let revisione = StimaRevisione(context: context)
        revisione.id = UUID()
        revisione.numero = (precedente?.numero ?? 0) + 1
        revisione.dataCreazione = Date()
        revisione.inputJSON = String(data: try encoder.encode(input), encoding: .utf8)
        revisione.calcoloJSON = String(data: try encoder.encode(calcolo), encoding: .utf8)
        revisione.hashCalcolo = calcolo.hashCalcolo
        revisione.hashEconomico = calcolo.hashEconomico
        revisione.liquidabile = NSDecimalNumber(decimal: calcolo.totali.liquidabile)
        revisione.dannoAccertato = NSDecimalNumber(decimal: calcolo.totali.dannoAccertato)
        revisione.richiesta = calcolo.totali.richiesta.map { NSDecimalNumber(decimal: $0) }
        revisione.esito = calcolo.esito.rawValue
        revisione.nota = nota
        revisione.perizia = perizia

        if let precedente, precedente.approvata, !precedente.superata, precedente.hashEconomico == calcolo.hashEconomico {
            revisione.approvata = true
            revisione.ereditataDa = precedente.numero
            revisione.approvataDa = "ereditata dalla revisione \(precedente.numero)"
            revisione.dataApprovazione = Date()
            supera(perizia, tranne: revisione)
        }
        perizia.stimaDannoIndennizzabile = NSDecimalNumber(decimal: calcolo.totali.liquidabile)
        try context.save()
        return revisione
    }

    /// Approva una revisione (di norma l'ultima). Tutte le precedenti diventano superate.
    func approva(_ revisione: StimaRevisione, da: String, context: NSManagedObjectContext) throws {
        revisione.approvata = true
        revisione.ereditataDa = 0
        revisione.approvataDa = da
        revisione.dataApprovazione = Date()
        if let perizia = revisione.perizia { supera(perizia, tranne: revisione) }
        try context.save()
    }

    func revocaApprovazione(_ revisione: StimaRevisione, context: NSManagedObjectContext) throws {
        revisione.approvata = false
        revisione.approvataDa = nil
        revisione.dataApprovazione = nil
        revisione.ereditataDa = 0
        try context.save()
    }

    private func supera(_ perizia: Perizia, tranne revisione: StimaRevisione) {
        for r in perizia.stimaRevisioniArray where r != revisione && r.numero < revisione.numero && !r.superata {
            r.superata = true
        }
    }

    // MARK: - Verifica dell'atto firmato

    enum EsitoVerificaAtto: String {
        case ok
        /// L'importo è il liquidabile di una revisione precedente: va firmato l'atto aggiornato.
        case stimaSuperata = "stima_superata"
        case importoDiverso = "importo_diverso"
        case senzaApprovazione = "senza_approvazione"

        var messaggio: String {
            switch self {
            case .ok: return "L'importo coincide con l'ultima stima approvata."
            case .stimaSuperata: return "L'importo è quello di una stima superata: va firmato l'atto aggiornato."
            case .importoDiverso: return "L'importo non corrisponde a nessuna stima: caso da valutare."
            case .senzaApprovazione: return "Nessuna stima approvata con cui confrontare l'atto."
            }
        }
    }

    /// Confronta l'importo dell'atto firmato con il liquidabile dell'ultima revisione approvata e lo registra.
    @discardableResult
    func verificaAttoFirmato(_ perizia: Perizia, importo: Decimal, context: NSManagedObjectContext) -> EsitoVerificaAtto {
        let importo = importo.arrotondato()
        let esito: EsitoVerificaAtto
        if let valida = revisioneValida(perizia), let liquidabile = valida.liquidabile?.decimalValue {
            if liquidabile.arrotondato() == importo {
                esito = .ok
            } else if perizia.stimaRevisioniArray.contains(where: { $0.superata && $0.liquidabile?.decimalValue.arrotondato() == importo }) {
                esito = .stimaSuperata
            } else {
                esito = .importoDiverso
            }
        } else {
            esito = .senzaApprovazione
        }
        perizia.attoFirmatoImporto = NSDecimalNumber(decimal: importo)
        perizia.attoFirmatoEsito = esito.rawValue
        perizia.attoFirmatoData = Date()
        try? context.save()
        return esito
    }

    // MARK: - Conversioni

    private func decimale(_ n: NSDecimalNumber?) -> Decimal? {
        guard let n, n != NSDecimalNumber.notANumber else { return nil }
        let d = n.decimalValue
        return d.isNaN ? nil : d
    }

    private func positivo(_ n: NSDecimalNumber?) -> Decimal? {
        guard let d = decimale(n), d > 0 else { return nil }
        return d
    }

    /// Double → Decimal passando dalla rappresentazione testuale (20.0 → 20, 0.1 → 0.1).
    private func decimale(_ d: Double) -> Decimal {
        guard d.isFinite else { return 0 }
        return Decimal(string: String(d)) ?? Decimal(d)
    }
}
