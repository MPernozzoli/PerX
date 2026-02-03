import Foundation
import CoreData

@MainActor
final class ClaimAssignmentBackfillService {
    static let shared = ClaimAssignmentBackfillService()

    private let defaults = UserDefaults.standard
    private let backfillKey = "claimAssignmentBackfill_v1_done"

    private init() {}

    func runIfNeeded(context: NSManagedObjectContext, currentUserEmail: String?) {
        guard defaults.bool(forKey: backfillKey) == false else { return }
        let currentUser = CurrentUserService.shared.currentUsername ?? currentUserEmail
        guard let currentUser, !currentUser.isEmpty else { return }

        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "assignedToUserEmail == nil OR assignedToUserEmail == '' OR ownerEmail == nil OR ownerEmail == ''")

        do {
            let results = try context.fetch(request)
            guard !results.isEmpty else {
                defaults.set(true, forKey: backfillKey)
                return
            }

            for sinistro in results {
                let owner = (sinistro.ownerEmail?.isEmpty == false) ? sinistro.ownerEmail : currentUser

                if sinistro.ownerEmail?.isEmpty != false {
                    sinistro.ownerEmail = owner
                }
                if sinistro.assignedToUserEmail?.isEmpty != false {
                    sinistro.assignedToUserEmail = owner
                }
            }

            if context.hasChanges {
                try context.save()
            }
            defaults.set(true, forKey: backfillKey)
            print("[ClaimAssignmentBackfill] ✅ Backfill completato (\(results.count) sinistri)")
        } catch {
            print("[ClaimAssignmentBackfill] ❌ Errore backfill: \(error)")
        }
    }
}

