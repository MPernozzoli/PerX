import Foundation
import SwiftUI

class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var syncError: String?
    
    private let mailManager = MailManager.shared
    
    func sync() async {
        isSyncing = true
        
        do {
            let context = PersistenceController.shared.container.viewContext
            await mailManager.syncAllMailboxes(context: context)
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
} 
