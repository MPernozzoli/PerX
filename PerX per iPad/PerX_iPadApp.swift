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
                AccountSelectorView()
            }
        }
        .animation(.easeInOut, value: session.isAuthenticated)
    }
}

// MARK: - iPad Content View (Main Navigation)

struct iPadContentView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedSection: NavigationSection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    enum NavigationSection: String, CaseIterable, Identifiable, Hashable {
        case dashboard = "Dashboard"
        case sinistri = "Sinistri"
        case mail = "Email"
        case whatsapp = "WhatsApp"
        case chat = "Chat AI"
        case consuntivo = "Consuntivo"
        case programmazione = "Programmazione"
        case routes = "Route"
        case impostazioni = "Impostazioni"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .sinistri: return "folder.fill"
            case .mail: return "envelope.fill"
            case .whatsapp: return "message.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .consuntivo: return "chart.bar.fill"
            case .programmazione: return "calendar.badge.clock"
            case .routes: return "point.topleft.down.curvedto.point.bottomright.up"
            case .impostazioni: return "gear"
            }
        }
        
        var isSettings: Bool { self == .impostazioni }
    }

    private var availableSections: [NavigationSection] {
        if session.isCATUser {
            return [.dashboard, .programmazione, .routes, .impostazioni]
        }
        return [.dashboard, .sinistri, .mail, .whatsapp, .chat, .consuntivo, .programmazione, .impostazioni]
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List {
                ForEach(availableSections.filter { !$0.isSettings }, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                    .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                
                Section {
                    if availableSections.contains(.impostazioni) {
                        Button {
                            selectedSection = .impostazioni
                        } label: {
                            Label(NavigationSection.impostazioni.rawValue, systemImage: NavigationSection.impostazioni.icon)
                        }
                        .listRowBackground(selectedSection == .impostazioni ? Color.accentColor.opacity(0.2) : Color.clear)
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
        .onAppear {
            clampSelectionIfNeeded()
        }
        .onChange(of: session.isCATUser) {
            clampSelectionIfNeeded()
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            if session.isCATUser {
                iPadCATDashboardView()
            } else {
                iPadDashboardView()
            }
        case .sinistri:
            SinistriListView()
        case .mail:
            iPadMailView()
        case .whatsapp:
            iPadWhatsAppView()
        case .chat:
            ChatListView()
        case .consuntivo:
            iPadConsuntivoView()
        case .programmazione:
            if session.isCATUser {
                iPadCATProgrammazioneView()
            } else {
                iPadProgrammazioneView()
            }
        case .routes:
            iPadCATRoutesView()
        case .impostazioni:
            SettingsView()
        }
    }

    private func clampSelectionIfNeeded() {
        guard availableSections.contains(selectedSection) else {
            selectedSection = .dashboard
            return
        }
    }
}
