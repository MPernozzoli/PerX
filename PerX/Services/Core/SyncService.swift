import Foundation
import SwiftUI

class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var syncError: String?
    
    func sync() async {
        isSyncing = true
        
        syncError = "La sincronizzazione email locale e' disabilitata: le email passano solo dal backend Resend."
        
        isSyncing = false
    }
} 
