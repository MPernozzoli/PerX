import SwiftUI

struct ImpostazioniView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        Form {
            AccountSettingsView()
        }
    }
} 
