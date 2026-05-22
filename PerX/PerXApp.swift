//
//  PerXApp.swift
//  PerX
//
//  Created by Massimo Pernozzoli on 13/11/24.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct PerXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService = GoogleAuthService.shared
    @StateObject private var whatsNewService = WhatsNewService.shared
    @StateObject private var onboardingService = OnboardingService.shared
    let persistenceController = PersistenceController.shared
    @State private var showWhatsNew = false
    @State private var showOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // ContentView solo quando autenticato (così non è in memoria sulla splash)
                if authService.isAuthenticated {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .onAppear {
                            setupFolderScanning()
                            _ = FatturatoCacheInvalidator.shared
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if whatsNewService.hasUnseenUpdates {
                                    showWhatsNew = true
                                }
                            }
                        }
                        .background(WindowTitleHider())
                }
                
                // Splash SEMPRE in albero così non viene mai distrutta e .task parte una sola volta
                SplashScreenView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .opacity(authService.isAuthenticated ? 0 : 1)
                    .allowsHitTesting(!authService.isAuthenticated)
                    .zIndex(authService.isAuthenticated ? 0 : 1)
                    .onAppear {
                        guard !authService.isAuthenticated else { return }
                        setupFolderScanning()
                        _ = FatturatoCacheInvalidator.shared
                    }
                
                // Onboarding overlay (priorità più alta)
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                        .transition(.opacity)
                        .zIndex(1000)
                }
                
                // WhatsNew overlay
                if showWhatsNew {
                    WhatsNewView(isPresented: $showWhatsNew)
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .onChange(of: onboardingService.shouldShowOnboarding) { newValue in
                showOnboarding = newValue
            }
            .onChange(of: authService.isAuthenticated) { newValue in
                if newValue {
                    Task { await TenantAIKeysService.shared.fetchIfNeeded() }
                } else {
                    // Logout: ferma tutti i servizi, ma SEMPRE fuori dal ciclo di rendering SwiftUI
                    DispatchQueue.main.async {
                        handleLogout()
                    }
                }
            }
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Cerca") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenSearch"),
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
    
    // MARK: - Logout Handling
    
    private func handleLogout() {
        Task { @MainActor in
            print("[PerXApp] 🚪 Logout rilevato - pulizia servizi")
            
            // Ferma servizi CloudKit
            CloudKitSyncService.shared.stop()
            CloudKitSinistroSyncService.shared.stopBackgroundSync()
            
            // Ferma Hub heartbeat
            HubConfigService.shared.stopHeartbeatTimer()
            
            // Ferma monitoring email
            MailViewModel.shared.stopMonitoring()
            
            // Ferma sync claims
            ClaimSyncService.shared.stopBackgroundSync()
            
            // Ferma trigger passivi
            PassiveTriggerService.shared.stopMonitoring()
            
            // Ferma folder packager per iPad
            CloudKitFolderPackagerService.shared.stop()
            
            // Chiudi tutte le tab aperte
            AppState.shared.closeAllTabs()
            
            print("[PerXApp] ✅ Servizi fermati per logout")
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupFolderScanning() {
        // Inizializza ImportService
        ImportService.configure(with: persistenceController.container.viewContext)
        
        // Esegui l'inizializzazione in modo asincrono per evitare blocchi
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Aspetta 1 secondo
            await CPUThrottler.shared.throttleIfNeeded()

            await MainActor.run {
                // Verifica dipendenze all'avvio
                Task {
                    await CPUThrottler.shared.runAtStartup {
                        print("[PerXApp] Verifica dipendenze sistema...")
                        await DependencyManager.shared.checkAllDependencies()
                    }
                }

                // I file sono ora gestiti internamente in Application Support
                print("[PerXApp] Gestione file interna attiva")

                // Pulisci la root di Claims spostando file/cartelle nelle cartelle corrette
                Task {
                    await CPUThrottler.shared.runAtStartup {
                        FileService.shared.cleanupClaimsRoot()
                    }
                }

                // Avvia il monitoring delle email se autenticato
                if GoogleAuthService.shared.isAuthenticated {
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            print("[PerXApp] Avvio monitoring persistente delle email")
                            MailViewModel.shared.startMonitoring()
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            _ = AutomaticClaimAssignmentService.shared
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            await UserProfileService.shared.refreshCurrentProfile()
                            await UserProfileService.shared.refreshAllProfiles()
                            await AutomaticClaimAssignmentService.shared.runNow(reason: "startup")
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            ClaimAssignmentBackfillService.shared.runIfNeeded(
                                context: persistenceController.container.viewContext,
                                currentUserEmail: GoogleAuthService.shared.userEmail
                            )
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            AssignmentDateValidationService.shared.runIfNeeded(
                                context: persistenceController.container.viewContext
                            )
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            OldSinistriCleanupService.shared.runIfNeeded(
                                context: persistenceController.container.viewContext
                            )
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            CloudKitSyncService.shared.startIfEnabled(email: GoogleAuthService.shared.userEmail)
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            await CloudKitSyncService.shared.syncNow(reason: "startup")
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            CloudKitSinistroSyncService.shared.startBackgroundSync()
                        }
                    }
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await SinistroReclaimNotificationService.shared.checkAndShowLocalNotifications()
                        }
                    }
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await CPUThrottler.shared.runAtStartup {
                            print("[PerXApp] Precaricamento PrincipaleViewModel in background")
                            await PrincipaleViewModel.shared.preload()
                        }
                    }
                }

                Task {
                    await CPUThrottler.shared.runAtStartup {
                        if BuildFeatures.localWhatsAppServerEnabled {
                            await setupWhatsApp()
                        } else {
                            print("[PerXApp] ℹ️ WhatsApp sospeso (Release/produzione)")
                        }
                    }
                }

                Task {
                    await CPUThrottler.shared.runAtStartup {
                        if BuildFeatures.localOllamaEnabled {
                            await OllamaService.shared.startOllama()
                        } else {
                            print("[PerXApp] ℹ️ Ollama sospeso (Release/produzione)")
                        }
                    }
                }

                Task {
                    await CPUThrottler.shared.runAtStartup {
                        PassiveTriggerService.shared.startMonitoring()
                    }
                }
                
                // Nota: Email/WA per iPad passano direttamente all'Hub, non serve worker Mac
                // CloudKitFolderPackagerService gestisce richieste cartelle da iPad via Hub
                if GoogleAuthService.shared.isAuthenticated {
                    Task {
                        await CPUThrottler.shared.runAtStartup {
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 secondi dopo avvio
                            print("[PerXApp] 📦 Avvio folder packager per richieste da iPad")
                            CloudKitFolderPackagerService.shared.start()
                        }
                    }
                }
            }
        }
    }
    
    private func setupWhatsApp() async {
        // WhatsApp funziona esclusivamente tramite Hub (già dentro runAtStartup del chiamante)
        print("[PerXApp] WhatsApp: gestione tramite Hub")
        WhatsAppService.shared.start()
        print("[PerXApp] WhatsApp: servizio avviato, accountId: \(WhatsAppService.shared.selectedAccountId)")
        WhatsAppNotificationService.shared.startPolling()
        print("[PerXApp] WhatsApp: polling notifiche avviato")
    }
}

// MARK: - AppDelegate per gestire la chiusura dell'app e notifiche push
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var shutdownInProgress = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registra per notifiche remote (CloudKit push)
        NSApplication.shared.registerForRemoteNotifications()
        print("[PerXApp] 📱 Registrazione notifiche remote CloudKit")
        
        // Imposta il delegate per le notifiche locali
        UNUserNotificationCenter.current().delegate = self
        
        // Backfill solleciti consolidati sui sinistri esistenti (una tantum)
        Task { @MainActor in
            await CPUThrottler.shared.runAtStartup {
                await SollecitiBackfillService.shared.runBackfillIfNeeded()
            }
        }
        
        // Osserva notifiche di sleep/wake per gestire la memoria
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }
    
    @objc private func handleSystemWillSleep() {
        print("[PerXApp] 💤 Sistema in standby - pulizia risorse")
        cleanupResourcesForBackground()
    }
    
    @objc private func handleSystemDidWake() {
        print("[PerXApp] ☀️ Sistema riattivato - ripristino risorse")
        restoreResourcesForForeground()
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        print("[PerXApp] 🔄 App in background - pulizia risorse")
        cleanupResourcesForBackground()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        print("[PerXApp] ✅ App in foreground - ripristino risorse")
        restoreResourcesForForeground()
    }
    
    private func cleanupResourcesForBackground() {
        Task { @MainActor in
            // Pulisci cache media
            MediaCacheService.shared.clearCache()
            
            // Ferma timer di monitoraggio
            PassiveTriggerService.shared.stopMonitoring()
            
            // Ferma prevenzione sleep
            BackgroundActivityManager.shared.stopPreventingSleep()
            BackgroundActivityManager.shared.stopMonitoring()
            
            // Ferma sync temporanee
            await ClaimSyncService.shared.pauseAllTemporarySyncs()
            
            // Ferma sync CloudKit
            CloudKitSinistroSyncService.shared.stopBackgroundSync()
            CloudKitSyncService.shared.stop()
            
            // Ferma polling chat
            CloudKitChatService.shared.stopPolling()
        }
    }
    
    private func restoreResourcesForForeground() {
        Task { @MainActor in
            // Ripristina monitoraggio trigger
            PassiveTriggerService.shared.startMonitoring()
            
            // Ripristina sync se necessario
            await ClaimSyncService.shared.resumeTemporarySyncsIfNeeded()
            
            // Ripristina sync CloudKit se abilitata
            if CloudKitSettingsService.shared.isEnabled {
                CloudKitSinistroSyncService.shared.startBackgroundSync()
            }
            
            // Ripristina polling chat
            CloudKitChatService.shared.startPolling()
            
            // Controlla notifiche di reclamo sinistro pending
            await SinistroReclaimNotificationService.shared.checkAndShowLocalNotifications()
        }
    }
    
    // MARK: - Remote Notifications (CloudKit Push)
    
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[PerXApp] ✅ Registrato per notifiche remote: \(tokenString.prefix(20))...")
    }
    
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PerXApp] ⚠️ Errore registrazione notifiche remote: \(error.localizedDescription)")
    }
    
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        // Notifica CloudKit ricevuta - fetch immediato!
        print("[PerXApp] 📨 Notifica CloudKit ricevuta")
        
        // Verifica se è una notifica CloudKit
        if let ck = userInfo["ck"] as? [String: Any] {
            print("[PerXApp] 📨 CloudKit notification: \(ck)")
            
            // Fetch immediato dei messaggi e sinistri
            Task { @MainActor in
                // Chat
                let chatService = CloudKitChatService.shared
                await chatService.handleCloudKitNotification()
                
                // Sinistri
                await CloudKitSinistroSyncService.shared.handleCloudKitNotification()
            }
        }
    }
    
    // MARK: - User Notifications Delegate
    
    /// Mostra notifica anche quando l'app è in primo piano (per WhatsApp)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // Per notifiche WhatsApp, mostra solo se non è la chat attiva
        if let type = userInfo["type"] as? String, type == "whatsapp_message" {
            if let chatId = userInfo["chatId"] as? String {
                Task { @MainActor in
                    if WhatsAppNotificationService.shared.activeChatId == chatId {
                        // Chat attiva - non mostrare
                        completionHandler([])
                    } else {
                        // Chat diversa - mostra banner e suono
                        completionHandler([.banner, .sound])
                    }
                }
                return
            }
        }
        
        // Per altri tipi di notifica, mostra sempre
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Gestisci notifiche di file scaricati/aggiornati
        if let type = userInfo["type"] as? String,
           (type == "new_files" || type == "files_updated"),
           let riferimento = userInfo["riferimento"] as? String {
            
            print("[PerXApp] 📬 Tap su notifica file per sinistro: \(riferimento)")
            
            Task { @MainActor in
                await handleFileNotificationTap(riferimento: riferimento)
            }
        }
        
        // Gestisci notifiche di sinistro reclamato
        if let type = userInfo["type"] as? String,
           type == "sinistro_reclaimed",
           let riferimento = userInfo["riferimento"] as? String {
            
            print("[PerXApp] 📬 Tap su notifica reclamo sinistro: \(riferimento)")
            
            Task { @MainActor in
                await handleSinistroReclaimedTap(riferimento: riferimento)
            }
        }
        
        // Gestisci notifiche WhatsApp
        if let type = userInfo["type"] as? String,
           type == "whatsapp_message",
           let chatId = userInfo["chatId"] as? String {
            
            let chatName = userInfo["chatName"] as? String ?? chatId
            let phoneNumber = userInfo["phoneNumber"] as? String ?? ""
            let sinistroRef = userInfo["sinistroRef"] as? String
            
            print("[PerXApp] 📬 Tap su notifica WhatsApp: \(chatName)")
            
            Task { @MainActor in
                WhatsAppNotificationService.shared.openChatWindow(
                    chatId: chatId,
                    chatName: chatName,
                    phoneNumber: phoneNumber,
                    sinistroRef: sinistroRef?.isEmpty == true ? nil : sinistroRef
                )
            }
        }
        
        completionHandler()
    }
    
    @MainActor
    private func handleFileNotificationTap(riferimento: String) async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        guard let sinistro = try? context.fetch(fetchRequest).first else {
            print("[PerXApp] ⚠️ Sinistro \(riferimento) non trovato")
            return
        }
        
        // Attiva l'app prima di aprire il sinistro
        NSApp.activate(ignoringOtherApps: true)
        
        // Apri il sinistro (se già aperto, lo porta in primo piano)
        AppState.shared.openSinistro(sinistro)
        
        // Aspetta un attimo per permettere all'apertura di completarsi
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 secondi
        
        // Evidenzia il sinistro aprendo la tab Cartella
        var found = false
        
        // Cerca nella finestra principale
        if let tab = AppState.shared.openTabs.first(where: { $0.sinistro.riferimento == riferimento }),
           let index = AppState.shared.openTabs.firstIndex(where: { $0.id == tab.id }) {
            AppState.shared.openTabs[index].selectedTab = "Cartella"
            AppState.shared.selectedTabId = tab.id
            AppState.shared.selectedView = "sinistri"
            AppState.shared.saveTabs()
            found = true
        } else {
            // Cerca nelle finestre detached
            for (windowId, var windowState) in AppState.shared.detachedWindows {
                if let tab = windowState.tabs.first(where: { $0.sinistro.riferimento == riferimento }),
                   let index = windowState.tabs.firstIndex(where: { $0.id == tab.id }) {
                    windowState.tabs[index].selectedTab = "Cartella"
                    windowState.selectedTabId = tab.id
                    AppState.shared.detachedWindows[windowId] = windowState
                    found = true
                    
                    // Porta la finestra in primo piano
                    if let window = WindowManager.shared.getWindow(identifier: windowId) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    break
                }
            }
        }
        
        // Evidenzia il sinistro con una notifica (solo se trovato)
        if found {
            NotificationCenter.default.post(
                name: NSNotification.Name("HighlightSinistroFromNotification"),
                object: nil,
                userInfo: ["riferimento": riferimento]
            )
        }
    }
    
    @MainActor
    private func handleSinistroReclaimedTap(riferimento: String) async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        
        guard let sinistro = try? context.fetch(fetchRequest).first else {
            print("[PerXApp] ⚠️ Sinistro \(riferimento) non trovato")
            return
        }
        
        // Attiva l'app e porta in primo piano
        NSApp.activate(ignoringOtherApps: true)
        
        // Apri il sinistro in una nuova finestra detached
        AppState.shared.openSinistro(sinistro, openInNewWindow: true)
        
        // Evidenzia il sinistro
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 secondi
        NotificationCenter.default.post(
            name: NSNotification.Name("HighlightSinistroFromNotification"),
            object: nil,
            userInfo: ["riferimento": riferimento]
        )
    }
    
    // MARK: - App Termination
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Se lo shutdown è già in corso, termina immediatamente
        if shutdownInProgress {
            return .terminateNow
        }
        
        print("[PerXApp] 🛑 Chiusura app rilevata")
        shutdownInProgress = true
        
        // WhatsApp Bridge è esterno, non richiede shutdown
        WhatsAppService.shared.stop()
        print("[PerXApp] ✅ Shutdown completato")
        
        return .terminateNow
    }
}

// ViewModifier per nascondere il titolo della finestra
struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
            }
        }
    }
}
