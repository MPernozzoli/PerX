//
//  PerX_iPadApp.swift
//  PerX per iPad
//
//  Created by Massimo Pernozzoli on 21/01/26.
//

import SwiftUI
import CoreData
import Combine
import UserNotifications

@main
struct PerX_iPadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateAdapter.self) var appDelegate
    @StateObject private var sessionCoordinator = SessionCoordinator.shared

    init() {
        // Registra il transport HTTP del Videoperizia service (iPad → HubAPIClient).
        VideoperiziaService.configure(transport: HubAPIClient.shared)
        CommunicationStartService.configure(transport: HubAPIClient.shared)
        CommunicationNotificationService.shared.registerNotificationCategories()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // CallKit + PushKit: VoIP push + UI di chiamata nativa iPadOS.
        let pushAPI = IPadPushAPI(hub: HubAPIClient.shared)
        PushDispatcher.shared.configure(
            api: pushAPI,
            bundleId: Bundle.main.bundleIdentifier,
            appIdentifier: "perx_ipad",
            environment: "production"
        )
        CallSessionShared.shared.api = pushAPI
        PushDispatcher.shared.incomingCallHandler = { payload, completion in
            CallProviderShared.shared.reportIncomingCall(payload) { _ in completion() }
        }
        CallProviderShared.shared.onAnswer = { sessionId in
            await CallSessionShared.shared.connect(toSessionId: sessionId)
        }
        CallProviderShared.shared.onEnd = { _ in
            await CallSessionShared.shared.endActive()
        }
    }

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
    @State private var incomingCall: CommunicationIncomingCallItem?
    @State private var showIncomingCallAlert = false
    @State private var activeIncomingToken: CommunicationLiveKitToken?

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
        .onChange(of: session.isAuthenticated, initial: true) { _, isAuth in
            if isAuth {
                IncomingCallPoller.shared.start()
                PushDispatcher.shared.start()
            } else {
                IncomingCallPoller.shared.stop()
                Task { await PushDispatcher.shared.unregisterAll() }
            }
        }
        .onReceive(IncomingCallPoller.shared.incomingCall) { item in
            incomingCall = item
            showIncomingCallAlert = true
            RingbackPlayer.shared.start(incoming: true)
        }
        .alert(
            "Chiamata in arrivo",
            isPresented: $showIncomingCallAlert,
            presenting: incomingCall
        ) { item in
            Button("Rispondi") {
                RingbackPlayer.shared.stop()
                Task {
                    do {
                        let result = try await CommunicationStartService.shared
                            .performNotificationAction(sessionId: item.sessionId, actionType: .answer)
                        if let token = result?.livekitToken {
                            await MainActor.run { activeIncomingToken = token }
                        }
                    } catch {
                        print("[iPad incoming] answer failed: \(error)")
                    }
                }
            }
            Button("Rifiuta", role: .destructive) {
                RingbackPlayer.shared.stop()
                Task {
                    _ = try? await CommunicationStartService.shared
                        .performNotificationAction(sessionId: item.sessionId, actionType: .end)
                }
            }
        } message: { item in
            Text(item.displayName ?? "Comunicazione PerX")
        }
        .sheet(item: $activeIncomingToken) { token in
            CommunicationLiveKitCallView(
                token: token,
                displayName: incomingCall?.displayName ?? "Chiamata PerX"
            ) {
                let sid = token.sessionId
                activeIncomingToken = nil
                Task {
                    _ = try? await CommunicationStartService.shared
                        .performNotificationAction(sessionId: sid, actionType: .end)
                }
            }
        }
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
        case comunicazioni = "Comunicazioni"
        case consuntivo = "Consuntivo"
        case programmazione = "Programmazione"
        case routes = "Route"
        case impostazioni = "Impostazioni"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
            case .sinistri: return "folder.fill"
            case .comunicazioni: return "bubble.left.and.bubble.right.fill"
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
            return [.dashboard, .comunicazioni, .programmazione, .routes, .impostazioni]
        }
        return [.dashboard, .sinistri, .comunicazioni, .consuntivo, .programmazione, .impostazioni]
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
        case .comunicazioni:
            ComunicazioniListView()
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
