import SwiftUI

struct SplashScreenView: View {
    @StateObject private var authService = GoogleAuthService.shared
    @State private var isAnimating = false
    @State private var shouldProceed = false
    @State private var isCheckingAuth = true
    @State private var isOffline = false
    
    var body: some View {
        ZStack {
            if shouldProceed {
                ContentView()
            } else {
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
                        } else if authService.isAuthenticated {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.green)
                                Text(authService.userEmail ?? "")
                                    .foregroundColor(.primary)
                            }
                            
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 8))
                                Text("Connesso")
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Procedi") {
                                withAnimation {
                                    shouldProceed = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else if isOffline && authService.hasValidToken {
                            VStack(spacing: 10) {
                                HStack {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.orange)
                                    Text("Connessione non disponibile")
                                        .foregroundColor(.secondary)
                                }
                                
                                Button("Prosegui Offline") {
                                    withAnimation {
                                        shouldProceed = true
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            VStack(spacing: 10) {
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
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
            
            Task {
                isCheckingAuth = true
                do {
                    if let token = try? await authService.getAccessToken() {
                        authService.isAuthenticated = true
                    }
                } catch {
                    if error is URLError {
                        isOffline = true
                    }
                }
                isCheckingAuth = false
            }
        }
    }
} 
