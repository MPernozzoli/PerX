import Foundation
import IOKit.pwr_mgt

/// Mantiene il Mac sveglio durante sincronizzazioni lunghe (solo su alimentazione).
/// Nota: non permette di lavorare "in standby": evita che il sistema entri in idle-sleep mentre la sync è attiva.
@MainActor
final class SyncSleepManager {
    static let shared = SyncSleepManager()
    
    private var assertionID: IOPMAssertionID = 0
    private var isActive: Bool = false
    private let resourceMonitor = ResourceMonitor.shared
    
    private init() {}
    
    func update(shouldPreventSleep: Bool) {
        if shouldPreventSleep {
            startIfPossible()
        } else {
            stop()
        }
    }
    
    private func startIfPossible() {
        guard resourceMonitor.isOnACPower() else { return }
        guard !isActive else { return }
        
        let ok = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "PerX Sync Agent - active transfer" as CFString,
            &assertionID
        ) == kIOReturnSuccess
        
        if ok {
            isActive = true
        } else {
            assertionID = 0
            isActive = false
        }
    }
    
    private func stop() {
        guard isActive else { return }
        _ = IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}

