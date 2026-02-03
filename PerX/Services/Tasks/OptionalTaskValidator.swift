import Foundation
import CoreData

/// Valida se una task opzionale deve essere creata o meno
/// Previene "rumore" verificando condizioni specifiche prima di generare task non essenziali
@MainActor
class OptionalTaskValidator {
    static let shared = OptionalTaskValidator()
    
    private let fileService = FileService.shared
    
    private init() {}
    
    /// Verifica se servono foto ubicazione
    /// Ritorna true se ci sono meno di 2 foto con tag "foto ubicazione del rischio" e allegare: true
    func needsFotoUbicazione(sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let folderPath = fileService.getSinistroPath(riferimento: riferimento, create: false) else {
            return false
        }
        
        // Conta file con tag "foto ubicazione del rischio" e allegare: true
        let fotoUbicazioneCount = fileService.countFilesWithTag(
            in: folderPath,
            tag: "foto ubicazione del rischio",
            allegare: true
        )
        
        // Se < 2, serve richiedere
        return fotoUbicazioneCount < 2
    }
    
    /// Verifica se serve polizza
    /// Ritorna true se manca il documento polizza (o simplo di polizza).
    /// Usa "simplo_di_polizza" come in FileTagManager / TagManager.
    func needsPolizza(sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let folderPath = fileService.getSinistroPath(riferimento: riferimento, create: false) else {
            return false
        }
        
        let polizza = fileService.countFilesWithTag(in: folderPath, tag: "polizza", allegare: true)
        let simploPolizza = fileService.countFilesWithTag(in: folderPath, tag: "simplo_di_polizza", allegare: true)
        
        return polizza == 0 && simploPolizza == 0
    }
    
    /// Verifica se servono preventivi (solo se danneggiato non assicurato).
    /// Ritorna false se: (a) c'è "preventivo" o "giustificativo", (b) atto già inviato (non ha senso chiederli).
    func needsPreventivo(sinistro: Sinistro) -> Bool {
        guard let riferimento = sinistro.riferimento,
              let folderPath = fileService.getSinistroPath(riferimento: riferimento, create: false) else {
            return false
        }
        
        // Una volta inviato l'atto, non ha senso richiedere preventivo/fattura
        let postAtto: [StatoManager.StatoSinistro] = [
            .attoInviato, .esitoComunicato, .esitoDaComunicare,
            .attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa
        ]
        if let statoDesc = sinistro.stato,
           let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoDesc }),
           postAtto.contains(stato) {
            return false
        }
        
        let preventivi = fileService.countFilesWithTag(in: folderPath, tag: "preventivo", allegare: true)
        let giustificativi = fileService.countFilesWithTag(in: folderPath, tag: "giustificativo", allegare: true)
        
        if preventivi > 0 || giustificativi > 0 { return false }
        
        return sinistro.nomeDanneggiato != nil
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
