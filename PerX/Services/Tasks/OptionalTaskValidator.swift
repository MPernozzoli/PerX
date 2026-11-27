import Foundation
import CoreData

/// Valida se una task opzionale deve essere creata o meno
/// Previene "rumore" verificando condizioni specifiche prima di generare task non essenziali
@MainActor
class OptionalTaskValidator {
    static let shared = OptionalTaskValidator()
    
    private init() {}
    
    /// Verifica se servono foto ubicazione
    /// Ritorna true se ci sono meno di 2 foto con tag "foto ubicazione del rischio" e allegare: true
    func needsFotoUbicazione(sinistro: Sinistro) async -> Bool {
        guard let riferimento = sinistro.riferimento else { return false }
        let count = await Self.countTaggedFiles(
            riferimento: riferimento,
            tag: "foto ubicazione del rischio"
        )
        return count < 2
    }
    
    /// Verifica se serve polizza
    /// Ritorna true se manca il documento polizza (o simplo di polizza).
    /// Usa "simplo_di_polizza" come in FileTagManager / TagManager.
    func needsPolizza(sinistro: Sinistro) async -> Bool {
        guard let riferimento = sinistro.riferimento else { return false }
        async let polizza = Self.countTaggedFiles(riferimento: riferimento, tag: "polizza")
        async let simplo = Self.countTaggedFiles(riferimento: riferimento, tag: "simplo_di_polizza")
        let polizzaCount = await polizza
        let simploCount = await simplo
        return polizzaCount == 0 && simploCount == 0
    }
    
    /// Verifica se servono preventivi (solo se danneggiato non assicurato).
    /// Ritorna false se: (a) c'è "preventivo" o "giustificativo", (b) atto già inviato (non ha senso chiederli).
    func needsPreventivo(sinistro: Sinistro) async -> Bool {
        guard let riferimento = sinistro.riferimento else { return false }
        let postAtto: [StatoManager.StatoSinistro] = [
            .attoInviato, .esitoComunicato, .esitoDaComunicare,
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa
        ]
        if let statoDesc = sinistro.stato,
           let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoDesc }),
           postAtto.contains(stato) {
            return false
        }
        async let preventivi = Self.countTaggedFiles(riferimento: riferimento, tag: "preventivo")
        async let giustificativi = Self.countTaggedFiles(riferimento: riferimento, tag: "giustificativo")
        let preventiviCount = await preventivi
        let giustificativiCount = await giustificativi
        if preventiviCount > 0 || giustificativiCount > 0 { return false }
        return sinistro.nomeDanneggiato != nil
    }

    /// Conta i file sul disco fuori dal thread della UI.
    private static func countTaggedFiles(riferimento: String, tag: String) async -> Int {
        await Task.detached(priority: .utility) {
            guard let folderPath = FileService.shared.getSinistroPath(riferimento: riferimento, create: false) else {
                return 0
            }
            return FileService.shared.countFilesWithTag(in: folderPath, tag: tag, allegare: true)
        }.value
    }
    
    /// Verifica se servono coordinate bancarie
    /// Ritorna true se manca IBAN e serve liquidazione
    func needsIBAN(sinistro: Sinistro) -> Bool {
        // Se IBAN già presente (flag a true), non serve
        if sinistro.iban {
            return false
        }
        
        // Serve IBAN se c'è un importo liquidato o c'è un assicurato
        let hasAmount = (sinistro.liquidato?.doubleValue ?? 0) > 0
        let hasAssicurato = sinistro.nomeAssicurato != nil && !(sinistro.nomeAssicurato?.isEmpty ?? true)
        
        return hasAmount || hasAssicurato
    }
}
