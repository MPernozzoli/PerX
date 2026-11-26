import Foundation

/// Testi generati dal motore di stima. Il perito non li riscrive: li integra con l'«accompagnatoria
/// extra». Regola: verso assicurato e agenzia si dice quali voci non sono riconosciute e perché, in
/// modo sobrio, senza criteri peritali; gli importi compaiono solo per franchigia, scoperto e limiti.
enum StimaTesti {

    static let fraseNonAccertato = "in sede di sopralluogo non è stato possibile verificare né accertare il danno denunciato, in quanto ad oggi non è stato eseguito alcun intervento di riparazione, né è stata fornita documentazione a supporto."
    static let fraseRestiamoADisposizione = "Restiamo a disposizione per un seguito qualora i componenti danneggiati vengano messi a disposizione per gli accertamenti peritali."

    static func genera(input: StimaInput, calcolo: StimaCalcolo) -> TestiStima {
        TestiStima(
            accompagnatoria: accompagnatoria(input: input, calcolo: calcolo),
            conclusioniEsito: conclusioniEsito(input: input, calcolo: calcolo),
            iva: testoIva(calcolo.beni),
            visioneBeni: visioneBeni(calcolo.beni).oggetto
        )
    }

    // MARK: Grammatica

    private static let vocali = Set("aeiouàèéìòùhAEIOUÀÈÉÌÒÙH")

    /// «del/dello/dell'/della» + nome, per «preso visione …».
    static func articolato(_ nome: String, genere: String) -> String {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard let primo = n.first else { return "del bene" }
        if vocali.contains(primo) { return "dell'" + n }
        if genere == "f" { return "della " + n }
        let low = n.lowercased()
        let iniziali2 = String(low.prefix(2))
        let secondo = low.dropFirst().first
        if "zxy".contains(low.first!) || ["gn", "ps", "pn"].contains(iniziali2)
            || (low.first == "s" && secondo != nil && !vocali.contains(secondo!)) {
            return "dello " + n
        }
        return "del " + n
    }

    static func elenco(_ nomi: [String]) -> String {
        switch nomi.count {
        case 0: return ""
        case 1: return nomi[0]
        default: return nomi.dropLast().joined(separator: ", ") + " e " + nomi.last!
        }
    }

    /// Oggetto di «preso visione …» e desinenza del participio (o/a/i).
    static func visioneBeni(_ beni: [BeneCalcolato]) -> (oggetto: String, desinenza: String) {
        if beni.isEmpty { return ("del bene denunciato", "o") }
        if beni.count == 1 {
            let g = beni[0].genere
            return (articolato(beni[0].nome, genere: g), g == "f" ? "a" : "o")
        }
        return ("dei seguenti beni: " + elenco(beni.map(\.nome)), "i")
    }

    private static func minuscola(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first else { return "" }
        return first.lowercased() + s.dropFirst()
    }

    private static func conPunto(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }
        return [".", "!", "?"].contains(s.last!) ? s : s + "."
    }

    // MARK: Voci escluse

    static func frasiEscluse(_ beni: [BeneCalcolato]) -> [String] {
        var gruppi: [MotivoEsclusione: [String]] = [:]
        var ordine: [MotivoEsclusione] = []
        for b in beni {
            for v in b.voci where !v.ammessa {
                let nome = minuscola(v.descrizione)
                guard !nome.isEmpty else { continue }
                let motivo = v.motivoEsclusione ?? .nonIndennizzabile
                if gruppi[motivo] == nil { gruppi[motivo] = []; ordine.append(motivo) }
                if !gruppi[motivo]!.contains(nome) { gruppi[motivo]!.append(nome) }
            }
        }
        let frasi = ordine.compactMap { motivo -> String? in
            guard let nomi = gruppi[motivo], !nomi.isEmpty else { return nil }
            let lista = nomi.contains(where: { $0.contains(",") }) ? nomi.joined(separator: "; ") : elenco(nomi)
            return "Non sono state riconosciute le voci relative a \(lista), \(motivo.fraseAccompagnatoria)."
        }
        return frasi
    }

    // MARK: Accompagnatoria dell'atto

    static func accompagnatoria(input: StimaInput, calcolo: StimaCalcolo) -> String {
        let extra = (input.accompagnatoriaExtra ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if calcolo.esito == .negativo {
            if !extra.isEmpty { return extra }
            if calcolo.dannoNonAccertato {
                return conPunto(String(fraseNonAccertato.prefix(1)).uppercased() + fraseNonAccertato.dropFirst()) + " " + fraseRestiamoADisposizione
            }
            let motivo = minuscola(input.riservaMotivo ?? "")
            return motivo.isEmpty
                ? "Il danno lamentato non risulta indennizzabile a termini di polizza."
                : conPunto("Il danno lamentato non risulta indennizzabile a termini di polizza in quanto \(motivo)")
        }

        var parti = frasiEscluse(calcolo.beni)
        for l in calcolo.liquidazioni where !l.tuttoNonIndennizzabile {
            for p in l.partite where p.rapportoProporzionale != nil {
                parti.append("L'indennizzo della partita \(p.nome) è stato determinato in applicazione della regola proporzionale (art. 1907 c.c.).")
            }
            if l.tipoTrattenuta == .franchigia && l.trattenuta > 0 {
                parti.append("All'importo riconosciuto è stata applicata la franchigia contrattuale di € \(euroIt(l.trattenuta)).")
            } else if l.tipoTrattenuta == .scoperto && l.trattenuta > 0 {
                parti.append("All'importo riconosciuto è stato applicato lo scoperto contrattuale, pari a € \(euroIt(l.trattenuta)).")
            }
            if let limite = l.limitePartite, l.dopoTrattenuta > limite {
                for p in l.partite where p.limitata {
                    parti.append("Per la partita \(p.nome) l'indennizzo è contenuto nella somma assicurata di € \(euroIt(p.sommaAssicurata)).")
                }
            }
            if l.massimaleApplicato {
                parti.append("L'indennizzo è contenuto nel massimale contrattuale di € \(euroIt(l.massimale)).")
            }
        }
        for b in calcolo.beni {
            guard let q = b.quotaComunePercentuale, let intero = b.totaleInteroBeneComune else { continue }
            let servizio = input.beni.first(where: { $0.id == b.id })?.unitaServite.map { "a servizio comune di \($0) unità del fabbricato" }
                ?? "a servizio comune del fabbricato"
            parti.append("Il danno \(articolato(b.nome, genere: b.genere)), \(servizio), è stato stimato complessivamente in € \(euroIt(intero)); alla presente polizza è stata imputata la quota del \(percentualeIt(q)), pari a € \(euroIt(b.vsu + b.si)).")
        }
        if let riparto = calcolo.riparto1910 {
            parti.append("L'indennizzo è stato ripartito ai sensi dell'art. 1910 c.c. con le altre polizze che assicurano il medesimo rischio: quota a carico della presente polizza € \(euroIt(riparto.quota)).")
        }
        if calcolo.totali.liquidabileDifferito > 0 {
            parti.append("Dell'importo liquidabile, € \(euroIt(calcolo.totali.liquidabileDifferito)) relativi al supplemento d'indennizzo saranno corrisposti a ripristini ultimati, previa presentazione della relativa documentazione.")
        }
        if calcolo.totali.ivaASaldo > 0 {
            parti.append("L'IVA, pari a € \(euroIt(calcolo.totali.ivaASaldo)), sarà riconosciuta a ripristini ultimati su presentazione della fattura.")
        }
        if !extra.isEmpty { parti.append(extra) }
        return parti.joined(separator: " ")
    }

    // MARK: Conclusioni per esito

    static func conclusioniEsito(input: StimaInput, calcolo: StimaCalcolo) -> String {
        switch calcolo.esito {
        case .nonConcordato:
            let codice = input.motivoNonConcordato ?? .senzaRisposta
            let dettaglio = (input.motivoNonConcordatoTesto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return [codice.frase, dettaglio].filter { !$0.isEmpty }.map(conPunto).joined(separator: " ")
        case .negativo:
            if calcolo.dannoNonAccertato {
                let visione = visioneBeni(calcolo.beni).oggetto
                return "È stato denunciato un danno a carico \(visione). "
                    + String(fraseNonAccertato.prefix(1)).uppercased() + fraseNonAccertato.dropFirst()
                    + " Procediamo pertanto con la restituzione della perizia a indennizzo nullo, restando eventualmente a disposizione per un seguito qualora i componenti danneggiati vengano messi a disposizione per gli accertamenti peritali."
            }
            let motivo = minuscola(input.riservaMotivo ?? "")
            return "Sulla base degli accertamenti svolti e della documentazione esaminata, il danno lamentato non risulta indennizzabile a termini di polizza"
                + (motivo.isEmpty ? "." : conPunto(" in quanto \(motivo)"))
        case .concordato:
            return "Il danno è stato definito con l'Assicurato in € \(euroIt(calcolo.totali.liquidabile)), come da atto di liquidazione sottoscritto."
        case .inLavorazione:
            return ""
        }
    }

    // MARK: IVA

    static func testoIva(_ beni: [BeneCalcolato]) -> String {
        var modi = Set<String>()
        for b in beni where b.voci.contains(where: \.ammessa) {
            modi.insert((b.ivaInLiquidazione + b.ivaASaldo) > 0 ? "inclusa" : "esclusa")
        }
        if modi.count > 1 { return "IVA parzialmente inclusa" }
        return "IVA " + (modi.first ?? "esclusa")
    }
}
