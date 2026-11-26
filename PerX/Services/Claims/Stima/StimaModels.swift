import Foundation

// MARK: - Motore di stima deterministico: modelli
//
// Il motore lavora su una fotografia della perizia (StimaInput) fatta di soli valori, mai su
// oggetti Core Data: lo stesso input produce sempre lo stesso calcolo e lo stesso hash.
// Gli importi sono Decimal arrotondati al centesimo con ROUND_HALF_UP (.plain).
// Riferimento: Documentation/Funzionalita/Motore-di-Stima.md

// MARK: - Enumerazioni di dominio

/// Esito della perizia. Guida importi, riserva, testi e workflow.
enum EsitoStima: String, Codable, CaseIterable, Identifiable {
    case inLavorazione = "IN_LAVORAZIONE"
    case concordato = "CONCORDATO"
    case nonConcordato = "NON_CONCORDATO"
    case negativo = "NEGATIVO"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .inLavorazione: return "In lavorazione"
        case .concordato: return "Concordato"
        case .nonConcordato: return "Non concordato"
        case .negativo: return "Negativo"
        }
    }

    init(stringa: String?) {
        self = EsitoStima(rawValue: (stringa ?? "").uppercased()) ?? .inLavorazione
    }
}

/// Perché una voce non è riconosciuta. L'etichetta è per il perito, la frase va nei testi verso
/// assicurato/agenzia: sobria, senza importi né criteri peritali.
enum MotivoEsclusione: String, Codable, CaseIterable, Identifiable {
    case nonIndennizzabile = "non_indennizzabile"
    case dannoIndiretto = "danno_indiretto"
    case beneNonVisionato = "bene_non_visionato"
    case nonPertinente = "non_pertinente"
    case nonDocumentato = "non_documentato"
    case fuoriGaranzia = "fuori_garanzia"
    case duplicato = "duplicato"
    case opereAccessorie = "opere_accessorie"
    case residuiNonMantenuti = "residui_non_mantenuti"
    case altro = "altro"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .nonIndennizzabile: return "Non indennizzabile"
        case .dannoIndiretto: return "Danno indiretto"
        case .beneNonVisionato: return "Bene non visionato"
        case .nonPertinente: return "Non pertinente al sinistro"
        case .nonDocumentato: return "Non documentato"
        case .fuoriGaranzia: return "Fuori garanzia"
        case .duplicato: return "Voce duplicata"
        case .opereAccessorie: return "Opere edili/idrauliche accessorie"
        case .residuiNonMantenuti: return "Residui non mantenuti"
        case .altro: return "Altro"
        }
    }

    var etichettaPlurale: String {
        switch self {
        case .nonIndennizzabile: return "Voci non indennizzabili"
        case .dannoIndiretto: return "Danni indiretti"
        case .beneNonVisionato: return "Beni non visionati"
        case .nonPertinente: return "Voci non pertinenti al sinistro"
        case .nonDocumentato: return "Voci non documentate"
        case .fuoriGaranzia: return "Voci fuori garanzia"
        case .duplicato: return "Voci duplicate"
        case .opereAccessorie: return "Opere edili/idrauliche accessorie"
        case .residuiNonMantenuti: return "Residui non mantenuti"
        case .altro: return "Altre voci escluse"
        }
    }

    /// Frase dell'accompagnatoria: «Non sono state riconosciute le voci relative a …, {frase}.»
    var fraseAccompagnatoria: String {
        switch self {
        case .nonIndennizzabile, .altro:
            return "in quanto non indennizzabili a termini di polizza"
        case .dannoIndiretto:
            return "in quanto conseguenza del guasto di altri componenti e non effetto diretto dell'evento, costituendo un danno indiretto non indennizzabile a termini di polizza"
        case .beneNonVisionato:
            return "in quanto riferite a beni non visionati, per i quali non è stato possibile accertare il danno"
        case .nonPertinente:
            return "in quanto non riconducibili all'evento denunciato"
        case .nonDocumentato:
            return "in quanto non è stato possibile accertarne il danno"
        case .fuoriGaranzia:
            return "in quanto non rientranti nella garanzia prestata dalla polizza"
        case .duplicato:
            return "in quanto già comprese in altre voci"
        case .opereAccessorie:
            return "in quanto interventi edili ed idraulici non coperti da nessuna delle garanzie prestate dalla Polizza"
        case .residuiNonMantenuti:
            return "in quanto i residui non sono stati mantenuti a disposizione per gli accertamenti peritali"
        }
    }
}

/// Motivo della chiusura non concordata: diventa la frase delle conclusioni.
enum MotivoNonConcordato: String, Codable, CaseIterable, Identifiable {
    case senzaRisposta = "senza_risposta"
    case solleciti = "solleciti"
    case rifiutato = "rifiutato"
    case documentiMancanti = "documenti_mancanti"
    case irreperibile = "irreperibile"
    case intestazioneContestata = "intestazione_contestata"
    case altro = "altro"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .senzaRisposta: return "Atto non restituito"
        case .solleciti: return "Atto non restituito dopo solleciti"
        case .rifiutato: return "Quantificazione non condivisa"
        case .documentiMancanti: return "Documenti mancanti"
        case .irreperibile: return "Assicurato irreperibile"
        case .intestazioneContestata: return "Intestazione pagamento contestata"
        case .altro: return "Altro (testo libero)"
        }
    }

    private static let esitoInviato = "Abbiamo provveduto a comunicare l'esito della perizia all'Assicurato, inviando l'atto di liquidazione"

    var frase: String {
        switch self {
        case .senzaRisposta:
            return "\(Self.esitoInviato) che ad oggi non è pervenuto sottoscritto."
        case .solleciti:
            return "\(Self.esitoInviato) che, nonostante i successivi solleciti, ad oggi non è pervenuto sottoscritto."
        case .rifiutato:
            return "\(Self.esitoInviato) che l'Assicurato non ha ritenuto di sottoscrivere, non condividendo la quantificazione del danno."
        case .documentiMancanti:
            return "\(Self.esitoInviato) e richiedendo la documentazione necessaria: ad oggi non sono pervenuti né l'atto sottoscritto né la documentazione richiesta."
        case .irreperibile:
            return "Nonostante i ripetuti tentativi di contatto, non è stato possibile definire il danno con l'Assicurato; l'atto di liquidazione inviato ad oggi non è pervenuto sottoscritto."
        case .intestazioneContestata:
            return "\(Self.esitoInviato) che non è pervenuto sottoscritto: è stata richiesta una diversa intestazione del pagamento rispetto al contraente di polizza, che si rimette alla valutazione della Compagnia."
        case .altro:
            return ""
        }
    }
}

/// Criterio di determinazione del danno (stringhe storiche di PerX, salvate su Partita/Bene).
enum CriterioIndennizzo: String, Codable, CaseIterable, Identifiable {
    case valoreANuovo = "Valore a nuovo"
    case vsuPiuSupplemento = "Valore allo stato d'uso più supplemento d'indennizzo"
    case vsuPiuSupplementoMaxDoppio = "VSU + SI (max doppio)"
    case vsuPiuSupplementoMaxTriplo = "VSU + SI (max triplo)"
    case vsuPiuSupplementoMaxQuadruplo = "VSU + SI (max quadruplo)"
    case statoDUso = "Valore allo stato d'uso"

    var id: String { rawValue }

    /// Valori sconosciuti ("regole speciali") si comportano come VSU + supplemento pieno, come prima.
    init(stringa: String?) {
        let s = (stringa ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self = s.isEmpty ? .valoreANuovo : (CriterioIndennizzo(rawValue: s) ?? .vsuPiuSupplemento)
    }

    var abbreviazione: String {
        switch self {
        case .valoreANuovo: return "Valore a nuovo"
        case .vsuPiuSupplemento: return "VSU + SI"
        case .vsuPiuSupplementoMaxDoppio: return "VSU + SI (max doppio)"
        case .vsuPiuSupplementoMaxTriplo: return "VSU + SI (max triplo)"
        case .vsuPiuSupplementoMaxQuadruplo: return "VSU + SI (max quadruplo)"
        case .statoDUso: return "VSU"
        }
    }

    /// Il deprezzamento si applica solo ai criteri allo stato d'uso: a valore a nuovo l'indennizzo è il costo di rimpiazzo.
    var applicaDeprezzamento: Bool { self != .valoreANuovo }

    /// Moltiplicatore massimo del supplemento rispetto al VSU (nil = senza limite).
    var limiteSupplemento: Decimal? {
        switch self {
        case .vsuPiuSupplementoMaxDoppio: return 2
        case .vsuPiuSupplementoMaxTriplo: return 3
        case .vsuPiuSupplementoMaxQuadruplo: return 4
        default: return nil
        }
    }

    var prevedeSupplemento: Bool {
        switch self {
        case .valoreANuovo, .statoDUso: return false
        default: return true
        }
    }
}

/// Forma di garanzia della partita.
enum FormaGaranzia: String, Codable, CaseIterable, Identifiable {
    case valoreIntero = "Valore Intero"
    case primoRischioAssoluto = "Primo Rischio Assoluto"
    case primoRischioRelativo = "Primo Rischio Relativo"

    var id: String { rawValue }

    init(stringa: String?) {
        let s = (stringa ?? "").lowercased()
        if s.contains("relativo") { self = .primoRischioRelativo }
        else if s.contains("primo") { self = .primoRischioAssoluto }
        else { self = .valoreIntero }
    }
}

enum TipoTrattenuta: String, Codable {
    case nessuna
    case franchigia
    case scoperto
}

// MARK: - Input

struct StimaInput: Codable, Equatable {
    var versioneSchema: Int = 1
    var riferimento: String?
    /// Richiesta a corpo per l'intero sinistro: se presente prevale su quella dei beni.
    var richiestaSinistro: Decimal?
    var partite: [PartitaInput] = []
    var garanzie: [GaranziaInput] = []
    var beni: [BeneInput] = []
    /// Beni in bozza (senza partita): non entrano nel calcolo, solo negli avvisi.
    var beniInBozza: [String] = []
    /// Arrotondamento con segno (|x| ≤ 100), sommato al danno accertato prima di franchigia/scoperto.
    var arrotondamento: Decimal = 0
    var arrotondamentoGaranziaId: String?
    /// Ordine alternativo: limite partite e massimale prima della franchigia/scoperto.
    var massimalePrimaDellaTrattenuta: Bool = false
    /// Rettifiche manuali dopo i limiti (le "voci personalizzate" della liquidazione).
    var rettifiche: [RettificaInput] = []
    var esito: EsitoStima = .inLavorazione
    /// Negativa con stima conservativa: danno non verificabile, la stima diventa la riserva.
    var dannoNonAccertato: Bool = false
    var motivoNonConcordato: MotivoNonConcordato?
    var motivoNonConcordatoTesto: String?
    var riservaMotivo: String?
    var riparto1910: Riparto1910Input?
    var accompagnatoriaExtra: String?
    var iban: String?
    var beneficiario: String?
    /// Soglia oltre la quale servono relazione completa e passaggio al controllore.
    var sogliaControllo: Decimal = 5000
}

struct PartitaInput: Codable, Equatable {
    var id: String
    var nome: String
    var tipo: String = "Fabbricato"
    var forma: FormaGaranzia = .valoreIntero
    /// Somma assicurata della partita: l'indennizzo della partita non la supera.
    var sommaAssicurata: Decimal = 0
    /// Valore reale del bene assicurato al momento del sinistro (solo per la regola proporzionale).
    var valoreReale: Decimal?
    var percentualeDeroga: Decimal?
    var acquistata: Bool = true
}

struct GaranziaInput: Codable, Equatable {
    var id: String
    var nome: String
    var massimale: Decimal = 0
    var franchigia: Decimal = 0
    var franchigiaMassimo: Decimal = 0
    var scopertoPercentuale: Decimal = 0
    var scopertoMinimo: Decimal = 0
    var scopertoMassimo: Decimal = 0
}

struct BeneInput: Codable, Equatable {
    var id: String
    var nome: String
    /// "m" o "f": serve solo alla grammatica dei testi («del frigorifero», «della lavatrice»).
    var genere: String = "m"
    var sostituzione: Bool = false
    var partitaId: String?
    var garanziaId: String?
    var richiesta: Decimal?
    var criterio: CriterioIndennizzo = .valoreANuovo
    var deprezzamentoPercentuale: Decimal = 20
    var aliquotaIVA: Decimal = 22
    /// I valori unitari inseriti comprendono già l'IVA (va scorporata).
    var ivaInclusaNeiValori: Bool = false
    var ivaRiconosciuta: Bool = true
    var ripristiniUltimati: Bool = true
    /// Importo finale del bene imposto dal perito: imponibile + IVA se riconosciuta (come nella scheda bene).
    var liquidazioneForzata: Decimal?
    /// Bene a servizio comune: si imputa a questa polizza solo la quota (0 < q < 100).
    var quotaComunePercentuale: Decimal?
    var unitaServite: Int?
    var voci: [VoceInput] = []
}

struct VoceInput: Codable, Equatable {
    var id: String
    var descrizione: String
    var quantita: Decimal = 1
    var valoreUnitario: Decimal = 0
    var percentualeMigliorie: Decimal = 0
    var percentualeIllesi: Decimal = 0
    /// Override per riga di deprezzamento e aliquota IVA (nil = valori del bene).
    var deprezzamentoPercentuale: Decimal?
    var aliquotaIVA: Decimal?
    /// Valori forzati a mano dal perito (modalità «Forzatura»): sostituiscono il passaggio di calcolo.
    var totaleANuovoForzato: Decimal?
    var nettoMigliorieForzato: Decimal?
    var nettoIllesiForzato: Decimal?
    var vsuForzato: Decimal?
    var siForzato: Decimal?
    var ammessa: Bool = true
    var motivoEsclusione: MotivoEsclusione?
    var nota: String?
    /// La voce è documentata da un giustificativo (fattura/preventivo).
    var giustificativo: Bool = false
    /// Importo richiesto per la voce, letto dal giustificativo.
    var richiesta: Decimal?
    /// Il giustificativo è IVA inclusa: la scomposizione mostra l'IVA non riconosciuta.
    var richiestaIvaInclusa: Bool = false
}

struct RettificaInput: Codable, Equatable {
    var id: String
    var descrizione: String
    var importo: Decimal
}

struct Riparto1910Input: Codable, Equatable {
    var attivo: Bool = true
    var altrePolizze: [AltraPolizzaInput] = []
}

struct AltraPolizzaInput: Codable, Equatable {
    var descrizione: String = ""
    var compagnia: String = ""
    var polizza: String = ""
    var sinistro: String = ""
    var indennizzoVirtuale: Decimal = 0
}

// MARK: - Output

struct VoceCalcolata: Codable, Equatable, Identifiable {
    var id: String
    var descrizione: String
    var ammessa: Bool
    var motivoEsclusione: MotivoEsclusione?
    var quantita: Decimal
    var valoreUnitario: Decimal
    var totaleANuovo: Decimal
    var nettoMigliorie: Decimal
    var nettoIllesi: Decimal
    var deprezzamentoApplicato: Decimal
    var vsu: Decimal
    var si: Decimal
    /// VSU + SI imputati a questa polizza (dopo la quota del bene comune, prima di IVA/forzatura).
    var importo: Decimal
    var imponibile: Decimal
    var iva: Decimal
    var aliquotaIVA: Decimal
    var richiesta: Decimal?
    var giustificativo: Bool
}

struct BeneCalcolato: Codable, Equatable, Identifiable {
    var id: String
    var nome: String
    var genere: String
    var sostituzione: Bool
    var partitaId: String?
    var garanziaId: String?
    var criterio: CriterioIndennizzo
    var voci: [VoceCalcolata]
    /// Voci ammesse: valori imponibili e IVA (dopo eventuale forzatura del bene).
    var vsu: Decimal
    var si: Decimal
    var imponibile: Decimal
    var ivaInLiquidazione: Decimal
    var ivaASaldo: Decimal
    var ivaNonRiconosciuta: Decimal
    /// IVA calcolata sulle voci ammesse, riconosciuta o no (per i totali della scheda bene).
    var ivaCalcolata: Decimal
    /// Imponibile + IVA in liquidazione delle voci ammesse.
    var totaleAmmesso: Decimal
    /// Voci escluse (valore della riserva), IVA compresa se riconosciuta.
    var totaleEscluso: Decimal
    var richiestaEffettiva: Decimal?
    var liquidazioneForzata: Decimal?
    var quotaComunePercentuale: Decimal?
    var totaleInteroBeneComune: Decimal?
    var ripristiniUltimati: Bool
}

struct DettaglioPartita: Codable, Equatable {
    var partitaId: String
    var nome: String
    var dannoAccertato: Decimal
    /// Rapporto somma assicurata / valore reale se si applica la regola proporzionale.
    var rapportoProporzionale: Decimal?
    var dopoRegolaProporzionale: Decimal
    var sommaAssicurata: Decimal
    var limitata: Bool
    var liquidabile: Decimal
}

struct LiquidazioneGaranzia: Codable, Equatable, Identifiable {
    var id: String { garanziaId }
    var garanziaId: String
    var nome: String
    var totaleVoci: Decimal
    var arrotondamento: Decimal
    var vsu: Decimal
    var si: Decimal
    var ivaInLiquidazione: Decimal
    var ivaASaldo: Decimal
    /// Danno accertato: imponibile ammesso + IVA in liquidazione + arrotondamento.
    var dannoAccertato: Decimal
    var riduzioneProporzionale: Decimal
    var tipoTrattenuta: TipoTrattenuta
    var trattenuta: Decimal
    var dopoTrattenuta: Decimal
    var partite: [DettaglioPartita]
    var limitePartite: Decimal?
    var massimale: Decimal
    var massimaleApplicato: Bool
    var liquidabilePrimaRiparto: Decimal?
    var liquidabile: Decimal
    /// Quota del liquidabile da pagare a ripristini ultimati (supplemento dei beni non ripristinati).
    var liquidabileDifferito: Decimal
    var dannoNonIndennizzabile: Decimal
    var tuttoNonIndennizzabile: Bool
}

struct RipartoCalcolato: Codable, Equatable {
    var dannoAccertato: Decimal
    var indennizzoVirtuale: Decimal
    var sommaIndennizziVirtuali: Decimal
    var quota: Decimal
    var righe: [RigaRiparto]
}

struct RigaRiparto: Codable, Equatable {
    var descrizione: String
    var importo: Decimal
}

struct TotaliStima: Codable, Equatable {
    var richiesta: Decimal?
    var dannoAccertato: Decimal
    var liquidabile: Decimal
    var liquidabileImmediato: Decimal
    var liquidabileDifferito: Decimal
    var ivaASaldo: Decimal
    var rettifiche: Decimal
    /// Riserva: voci escluse; nelle negative tutta la stima; con danno non accertato la stima conservativa.
    var riserva: Decimal
    var stimaConservativa: Decimal?
}

enum FaseScomposizione: String, Codable {
    case richiestaAccertato
    case accertatoLiquidabile
}

struct PassoScomposizione: Codable, Equatable, Identifiable {
    var id: String { "\(fase.rawValue)-\(etichetta)" }
    var fase: FaseScomposizione
    var etichetta: String
    var importo: Decimal
    var nota: String
}

struct TestiStima: Codable, Equatable {
    /// Testo per l'atto: voci escluse, franchigia/scoperto, limiti. Sobrio, senza criteri peritali.
    var accompagnatoria: String
    /// Frase delle conclusioni della relazione (non concordato, negativa, danno non accertato).
    var conclusioniEsito: String
    /// «IVA esclusa» / «IVA inclusa» / «IVA parzialmente inclusa».
    var iva: String
    /// «del frigorifero» / «dei seguenti beni: …».
    var visioneBeni: String
}

struct WorkflowStima: Codable, Equatable {
    var soglia: Decimal
    var sopraSoglia: Bool
    /// Serve la relazione peritale completa (sopra soglia, non concordato, negativo).
    var relazioneCompleta: Bool
    var motivo: String
}

struct StimaCalcolo: Codable, Equatable {
    var esito: EsitoStima
    var dannoNonAccertato: Bool
    var beni: [BeneCalcolato]
    var liquidazioni: [LiquidazioneGaranzia]
    var riparto1910: RipartoCalcolato?
    var rettifiche: [RettificaInput]
    var totali: TotaliStima
    var scomposizione: [PassoScomposizione]
    var avvisi: [String]
    var testi: TestiStima
    var workflow: WorkflowStima
    var hashCalcolo: String = ""
    var hashEconomico: String = ""
}

/// Errori bloccanti: il calcolo non è affidabile finché non sono corretti.
struct StimaErrori: Error, LocalizedError, Equatable {
    var messaggi: [String]
    var errorDescription: String? { messaggi.joined(separator: "\n") }
}
