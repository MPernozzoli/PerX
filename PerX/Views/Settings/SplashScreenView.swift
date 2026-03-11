import SwiftUI

struct SplashScreenView: View {
    @ObservedObject private var authService = GoogleAuthService.shared
    @State private var isAnimating = false
    @State private var isCheckingAuth = true
    
    var body: some View {
        VStack(spacing: 40) {
            // Logo e titolo
            VStack(spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .opacity(isAnimating ? 1 : 0)
                    .scaleEffect(isAnimating ? 1 : 0.5)
                
                Text("PerX")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .opacity(isAnimating ? 1 : 0)
            }
            
            // Stato accesso
            VStack(spacing: 20) {
                if isCheckingAuth {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Verifico account ACT...")
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 10) {
                        if authService.needsReAuthentication {
                            // Sessione scaduta
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Sessione scaduta")
                                    .foregroundColor(.orange)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("Il token di accesso è scaduto.\nEffettua nuovamente il login per continuare.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Accedi di nuovo") {
                                authService.signIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            // Primo accesso
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 8))
                                Text("Non connesso")
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Accedi per iniziare")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Button("Accedi con Account ACT") {
                                authService.signIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                }
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
        .task(id: "authCheck") {
            let result = await authService.checkAuthenticationState()
            authService.applyAuthResult(result)
            // Nuovo task così l'aggiornamento stato non avviene dentro il ciclo del .task
            Task { @MainActor in
                isCheckingAuth = false
            }
        }
    }
}
