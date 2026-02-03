import Foundation
import IOKit.pwr_mgt

/// Manager per mantenere il sistema attivo durante il lavoro in background
class BackgroundActivityManager {
    static let shared = BackgroundActivityManager()
    
    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false
    private let resourceMonitor = ResourceMonitor.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Avvia la prevenzione del sleep (solo se collegato all'alimentazione)
    @MainActor
    func startPreventingSleep() -> Bool {
        guard resourceMonitor.isOnACPower() else {
            print("[BackgroundActivity] Sistema non collegato all'alimentazione, non previene sleep")
            return false
        }
        
        guard !isPreventingSleep else {
            return true
        }
        
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "PerX AI Background Processing" as CFString,
            &assertionID
        ) == kIOReturnSuccess
        
        if success {
            isPreventingSleep = true
            print("[BackgroundActivity] ✅ Prevenzione sleep attivata")
        } else {
            print("[BackgroundActivity] ❌ Impossibile attivare prevenzione sleep")
        }
        
        return success
    }
    
    /// Ferma la prevenzione del sleep
    func stopPreventingSleep() {
        guard isPreventingSleep else {
            return
        }
        
        let success = IOPMAssertionRelease(assertionID) == kIOReturnSuccess
        
        if success {
            isPreventingSleep = false
            assertionID = 0
            print("[BackgroundActivity] ✅ Prevenzione sleep disattivata")
        } else {
            print("[BackgroundActivity] ❌ Errore nel rilasciare prevenzione sleep")
        }
    }
    
    /// Verifica se il sistema può lavorare in background
    @MainActor
    func canWorkInBackground() -> Bool {
        return resourceMonitor.isOnACPower() && !resourceMonitor.isLowOnResources
    }
    
    /// Gestisce automaticamente la prevenzione del sleep in base alle condizioni
    func updateSleepPrevention() {
        Task { @MainActor in
            let canWork = canWorkInBackground()
            let queueSize = AIManager.shared.queueSize
            
            if canWork && queueSize > 0 {
                _ = startPreventingSleep()
            } else {
                stopPreventingSleep()
            }
        }
    }
    
    private var monitoringTimer: Timer?
    
    /// Avvia il monitoraggio automatico
    func startMonitoring() {
        stopMonitoring()
        // Monitora periodicamente le condizioni
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateSleepPrevention()
        }
    }
    
    /// Ferma il monitoraggio automatico
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    deinit {
        stopMonitoring()
        stopPreventingSleep()
    }
}

