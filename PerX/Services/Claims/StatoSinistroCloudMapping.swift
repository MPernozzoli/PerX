import Foundation

/// Mappatura dal raw value legacy SV* (`StatoManager.StatoSinistro`) agli slug
/// canonici usati dal backend post-migration 020 (es. "in_attesa_documentale",
/// "atto_ricevuto", "chiusa").
///
/// Mantenere CoreData in SV (legacy) e tradurre solo nel transport evita di
/// migrare la persistenza locale. Quando l'enum lato iOS verrà ricodato in
/// slug puri, questa extension diventa identity (o sparisce).
///
/// Per gli stati con substato implicito (SV022→in_attesa_terzi[assicurato],
/// SV032→atto_ricevuto[sottoscritto], SV050→sopralluogo[fissato], …) il
/// substato non viene trasportato: il backend riceve solo lo slug base.
/// È una limitazione nota e accettata in questa fase di cutover.
extension StatoManager.StatoSinistro {
    /// Slug canonico backend, o `nil` se lo stato è puramente locale (es. stati
    /// di sistema SI*) o non ha equivalente server.
    var cloudSlug: String? {
        switch self {
        // Ingresso
        case .daScaricare, .istruzione:          return "istruzione"
        case .inAttesaDocumentale:               return "in_attesa_documentale"
        case .periziaDaEseguire:                 return "da_gestire_tradizionale"
        case .videoperiziaDaFissare:             return "videoperizia_da_eseguire"
        case .periziaDaEseguireNoResidui:        return "da_gestire_no_residui"
        case .primoContatto:                     return "primo_contatto"
        case .secondoContatto:                   return "secondo_contatto"
        case .inAttesaAssegnazione:              return "in_attesa_assegnazione"

        // Avanzamento
        case .periziaDaEseguireDocumentale:      return "da_gestire_documentale"
        case .inGestioneDocumentale:             return "da_gestire_documentale"
        case .inGestione:                        return "in_gestione"
        case .inGestioneVideoperizia:            return "da_gestire_video"
        case .videoperiziaFissata:               return "da_gestire_video"
        case .sopralluogoAssegnato:              return "sopralluogo"
        case .videoperiziaDaEseguire:            return "videoperizia_da_eseguire"
        case .daGestireVideoperizia:             return "da_gestire_video"
        case .daGestireTradizionale:             return "da_gestire_tradizionale"
        case .daGestireDocumentale:              return "da_gestire_documentale"
        case .attoDaInviare:                     return "atto_da_inviare"
        case .esitoDaComunicare:                 return "esito_da_comunicare"
        case .inAttesaDaAssicurato:              return "in_attesa_terzi"
        case .inAttesaDaAgenzia:                 return "in_attesa_terzi"
        case .inAttesaDaTerzi:                   return "in_attesa_terzi"
        case .attesaPassiva:                     return "attesa_passiva"
        case .daGestireNoResidui:                return "da_gestire_no_residui"
        case .esitoComunicato:                   return "esito_comunicato"
        case .attoInviato:                       return "atto_inviato"
        case .attoRicevutoSottoscritto:          return "atto_ricevuto"
        case .accettataVerbalmente:              return "atto_ricevuto"
        case .inControllo:                       return "da_controllare"
        case .controllata:                       return "controllata"
        case .richiestaAutorizzazione:           return "richiesta_autorizzazione"
        case .supervisioneNonConcordata:         return "supervisione_non_concordata"
        case .daControllare:                     return "da_controllare"
        case .daChiudereASistema:                return "da_chiudere_a_sistema"
        case .sopralluogoFissato:                return "sopralluogo"
        case .sopralluogoRestituito:             return "sopralluogo"
        case .sopralluogoDaFissare:              return "sopralluogo"
        case .sopralluogoDaConcordare:           return "sopralluogo"

        // Chiusura
        case .chiusa:                            return "chiusa"
        case .richiestaRevisione:                return "da_revisionare"
        case .daRevisionare:                     return "da_revisionare"

        // Stati di sistema: nessun equivalente cloud
        case .revocata, .annullata:              return nil
        }
    }

    /// Substato implicito da emettere insieme allo slug base, per gli stati
    /// che pre-cutover erano stati separati e ora sono "stato base + substato".
    var impliedSubstato: String? {
        switch self {
        case .inAttesaDaAssicurato:      return "assicurato"
        case .inAttesaDaAgenzia:         return "agenzia"
        case .attoRicevutoSottoscritto:  return "sottoscritto"
        case .accettataVerbalmente:      return "verbale"
        case .sopralluogoFissato:        return "fissato"
        case .sopralluogoRestituito:     return "da_rifissare"
        case .sopralluogoDaFissare:      return "da_fissare"
        case .sopralluogoDaConcordare:   return "da_concordare"
        case .videoperiziaFissata:       return "fissata"
        case .periziaDaEseguireDocumentale: return "da_aprire"
        default:                          return nil
        }
    }
}

/// Mappatura inversa: slug backend → SV legacy. Usata da
/// `ClaimAdapter.fetchCurrentStateLocally` quando vuole risolvere lo
/// `stato_corrente` salvato in CoreData (SV) per inviare `from_state` al server.
enum BackendStatoMapping {
    /// Slug canonico dato il raw value SV salvato in CoreData. Identity per
    /// valori già in slug (forward-compatible se in futuro CoreData migrasse).
    static func cloudSlug(forCoreDataRaw raw: String) -> String? {
        if let known = StatoManager.StatoSinistro(rawValue: raw) {
            return known.cloudSlug
        }
        return raw  // assumiamo già slug
    }

    /// Stato iOS (SV) dato uno slug canonico del backend. Per slug che
    /// rappresentano una fusione di più stati legacy (es. "atto_ricevuto",
    /// "sopralluogo", "in_attesa_terzi", "da_gestire_video") restituisce il
    /// rappresentante più informativo; il substato eventuale va letto da
    /// `stato_substati` separato.
    static func statoSinistro(forCloudSlug slug: String) -> StatoManager.StatoSinistro? {
        switch slug {
        case "istruzione":                   return .istruzione
        case "primo_contatto":               return .primoContatto
        case "secondo_contatto":             return .secondoContatto
        case "in_attesa_assegnazione":       return .inAttesaAssegnazione
        case "in_attesa_documentale":       return .inAttesaDocumentale
        case "videoperizia_da_eseguire":     return .videoperiziaDaEseguire
        case "da_gestire_tradizionale":     return .daGestireTradizionale
        case "da_gestire_documentale":      return .daGestireDocumentale
        case "da_gestire_video":             return .daGestireVideoperizia
        case "da_gestire_no_residui":       return .daGestireNoResidui
        case "in_attesa_terzi":              return .inAttesaDaTerzi
        case "attesa_passiva":               return .attesaPassiva
        case "sopralluogo":                  return .sopralluogoFissato
        case "in_gestione":                  return .inGestione
        case "esito_da_comunicare":          return .esitoDaComunicare
        case "esito_comunicato":             return .esitoComunicato
        case "atto_da_inviare":              return .attoDaInviare
        case "atto_inviato":                 return .attoInviato
        case "atto_ricevuto":                return .attoRicevutoSottoscritto
        case "da_controllare":               return .daControllare
        case "controllata":                  return .controllata
        case "da_revisionare":               return .daRevisionare
        case "da_chiudere_a_sistema":       return .daChiudereASistema
        case "chiusa":                       return .chiusa
        case "richiesta_autorizzazione":    return .richiestaAutorizzazione
        case "supervisione_non_concordata": return .supervisioneNonConcordata
        default:                              return nil
        }
    }
}

/// Substato in arrivo dal backend (entry della colonna JSONB `stato_substati`).
struct CloudSubstato: Codable, Equatable {
    let tag: String
    let source: String           // "user" | "ai" | "system"
    let added_at: String?
}

extension CloudSubstato {
    /// Etichetta human-readable. Tag generati dalla IA sono prefissati con ✨
    /// per distinguerli a colpo d'occhio da quelli inseriti da utente o
    /// automazione deterministica.
    var displayLabel: String {
        let pretty = tag.replacingOccurrences(of: "_", with: " ")
        return source == "ai" ? "✨ \(pretty)" : pretty
    }
}

extension Array where Element == CloudSubstato {
    /// Stringa già parenthesized "(a · b)" pronta da accodare allo stato base.
    /// Vuota se la lista è vuota.
    var inlineDisplay: String {
        guard !isEmpty else { return "" }
        return " (\(map(\.displayLabel).joined(separator: " · ")))"
    }
}
