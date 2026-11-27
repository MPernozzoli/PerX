import Foundation

/// Modello ReClaim del profilo Chiari. Stesse soglie di `backend/app/domain/chiari_stima.py`.
enum ChiariReclaimModello: String, Equatable {
    case light = "Light"
    case over = "Over"
    case senzaStima = "Sopralluogo Senza stima"
}

struct ChiariWorkflowDecision: Equatable {
    var modello: ChiariReclaimModello
    var compilareReclaim: Bool
    var generaRelazioneSalesforce: Bool
}

enum ChiariStimaWorkflow {
    static let sogliaOver = Decimal(5000)

    static func decide(
        liquidabile: Decimal,
        esito: String,
        reclaimOver: Bool = false,
        reclaimAssente: Bool = false
    ) -> ChiariWorkflowDecision {
        let esitoNorm = esito.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let negativa = esitoNorm == "NEGATIVO"
        let nonConcordata = esitoNorm == "NON_CONCORDATO"
        var over = liquidabile > sogliaOver || nonConcordata || reclaimOver
        let senzaStima = negativa || liquidabile == 0
        if senzaStima {
            over = false
        }
        let relazione = over || negativa || nonConcordata || reclaimAssente || senzaStima
        let modello: ChiariReclaimModello
        if senzaStima {
            modello = .senzaStima
        } else if over {
            modello = .over
        } else {
            modello = .light
        }
        return ChiariWorkflowDecision(
            modello: modello,
            compilareReclaim: !reclaimAssente,
            generaRelazioneSalesforce: relazione
        )
    }
}
