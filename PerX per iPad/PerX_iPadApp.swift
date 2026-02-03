//
//  PerX_iPadApp.swift
//  PerX per iPad
//
//  Created by Massimo Pernozzoli on 21/01/26.
//

import SwiftUI
import CoreData

@main
struct PerX_iPadApp: App {
    @StateObject private var sessionCoordinator = SessionCoordinator.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionCoordinator)
        }
    }
}

// MARK: - Root View (gestisce login/logout e switch utente)

struct RootView: View {
    @EnvironmentObject var session: SessionCoordinator
    
    var body: some View {
        Group {
            if session.isAuthenticated {
                iPadContentView()
                    .environment(\.managedObjectContext, session.viewContext)
                    .id(session.currentUserEmail) // Force refresh on user change
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: session.isAuthenticated)
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left side - branding
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("PerX")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    
                    Text("Gestione Sinistri Professionale")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .frame(width: geometry.size.width * 0.5)
                .background(Color(.systemBackground))
                
                // Right side - login
                VStack(spacing: 32) {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Text("Accedi")
                            .font(.title.bold())
                        
                        Text("Usa il tuo account Google aziendale")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if isLoggingIn {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(40)
                    } else {
                        Button {
                            Task { await signIn() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.title3)
                                Text("Accedi con Google")
                                    .font(.headline)
                            }
                            .frame(maxWidth: 280)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Text("Versione iPad • CloudKit-first")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom)
                }
                .frame(width: geometry.size.width * 0.5)
                .background(Color(.secondarySystemBackground))
            }
        }
        .ignoresSafeArea()
    }
    
    private func signIn() async {
        isLoggingIn = true
        errorMessage = nil
        
        do {
            try await session.signIn()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoggingIn = false
    }
}

// MARK: - iPad Content View (Main Navigation)

struct iPadContentView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedSection: NavigationSection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    enum NavigationSection: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case sinistri = "Sinistri"
        case comunicazioni = "Comunicazioni"
        case chat = "Chat"
        case consuntivo = "Consuntivo"
        case programmazione = "Programmazione"
        case impostazioni = "Impostazioni"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .sinistri: return "folder.fill"
            case .comunicazioni: return "envelope.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .consuntivo: return "chart.bar.fill"
            case .programmazione: return "calendar.badge.clock"
            case .impostazioni: return "gear"
            }
        }
        
        var isSettings: Bool { self == .impostazioni }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(selection: $selectedSection) {
                Section {
                    ForEach(NavigationSection.allCases.filter { !$0.isSettings }) { section in
                        NavigationLink(value: section) {
                            Label(section.rawValue, systemImage: section.icon)
                        }
                    }
                }
                
                Section {
                    NavigationLink(value: NavigationSection.impostazioni) {
                        Label("Impostazioni", systemImage: "gear")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("PerX")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text(session.currentUserEmail ?? "")
                        Divider()
                        Button(role: .destructive) {
                            Task { await session.signOut() }
                        } label: {
                            Label("Esci", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                    }
                }
            }
        } detail: {
            // Detail content based on selection
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            iPadDashboardView()
        case .sinistri:
            SinistriListView()
        case .comunicazioni:
            ComunicazioniListView()
        case .chat:
            ChatListView()
        case .consuntivo:
            iPadConsuntivoView()
        case .programmazione:
            iPadProgrammazioneView()
        case .impostazioni:
            SettingsView()
        }
    }
}
