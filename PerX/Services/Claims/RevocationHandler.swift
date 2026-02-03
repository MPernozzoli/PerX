import Foundation
import CoreData

@MainActor
class RevocationHandler {
    static let shared = RevocationHandler()
    private let taskManager = TaskManager.shared
    
    private init() {}
    
    /// Processa la revoca: stato, cleanup task, PDF riassuntivo
    func processRevocation(for sinistro: Sinistro, email: Email?, context: NSManagedObjectContext) async {
        guard let riferimento = sinistro.riferimento else { return }
        
        let statoPrecedente = sinistro.stato ?? ""
        let oldStateEnum = StatoManager.StatoSinistro.allCases.first { $0.descrizione == statoPrecedente }
        
        // Verifica se la revoca è permessa (non permessa se chiuso, tranne se già revocato)
        if let oldState = oldStateEnum, oldState == .chiusa {
            print("[RevocationHandler] ⚠️ Impossibile revocare sinistro chiuso: \(riferimento)")
            return
        }
        
        // Aggiorna stato con validazione
        do {
            try await StatoManager.shared.changeState(
                for: sinistro,
                to: .revocata,
                context: context
            )
            sinistro.dataRevoca = Date()
        } catch {
            print("[RevocationHandler] ❌ Errore aggiornamento stato revoca: \(error.localizedDescription)")
            return
        }
        
        // Notifica cambio stato (per TaskManager e UI) - già fatto da StatoManager.changeState
        
        // Rimuove tutte le task collegate
        taskManager.removeAllTasks(for: riferimento)
        
        // Recupera comunicazioni completate per il riepilogo
        let communications = sinistro.diarioArray.filter { entry in
            switch entry.tipo {
            case .email, .whatsapp, .aggiornamento, .notaUtente:
                return true
            default:
                return false
            }
        }
        
        // Genera PDF riassuntivo
        _ = RevocationPDFService.shared.generateSummary(for: sinistro, communications: communications)
        
        // Notifica evento dedicato per il cruscotto
        NotificationCenter.default.post(
            name: .revocationCompleted,
            object: nil,
            userInfo: [
                "sinistroIDs": [riferimento],
                "emailSubject": email?.subject ?? "Revoca incarico videoperizia",
                "emailId": email?.id ?? ""
            ]
        )
        
        print("[RevocationHandler] ✅ Sinistro \(riferimento) revocato e task ripulite")
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let revocationCompleted = Notification.Name("revocationCompleted")
}

