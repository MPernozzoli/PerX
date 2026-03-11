import Foundation
import CloudKit

/// Sync di segreti su CloudKit. Sync Agent e WhatsApp Bridge sono gestiti solo via Hub, non più config locali.
@MainActor
final class CloudKitKeychainSyncService {
    static let shared = CloudKitKeychainSyncService()

    private init() {}

    func syncSharedSecrets(container: CKContainer) async {
        // Nessun segreto condiviso locale: Sync Agent rimosso, tutto via Hub
    }

    func syncUserSecrets(container: CKContainer, userEmail: String) async {
        // WhatsApp gestito solo via Hub, nessun segreto utente da sincronizzare
    }
}
