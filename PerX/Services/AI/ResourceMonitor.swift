import Foundation
import IOKit

/// Monitor delle risorse di sistema
@MainActor
class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()
    
    @Published var availableRAM: UInt64 = 0
    @Published var totalRAM: UInt64 = 0
    @Published var cpuUsage: Double = 0.0
    @Published var memoryPressure: MemoryPressure = .normal
    @Published var isLowOnResources: Bool = false
    
    private var monitoringTimer: Timer?
    private let updateInterval: TimeInterval = 2.0
    
    enum MemoryPressure {
        case normal
        case warning
        case critical
    }
    
    private init() {
        updateResources()
        startMonitoring()
    }
    
    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }
    
    /// Avvia il monitoraggio continuo
    func startMonitoring() {
        stopMonitoring()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateResources()
            }
        }
    }
    
    /// Ferma il monitoraggio
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    /// Aggiorna le informazioni sulle risorse
    func updateResources() {
        totalRAM = getTotalRAM()
        availableRAM = getAvailableRAM()
        cpuUsage = getCPUUsage()
        memoryPressure = calculateMemoryPressure()
        isLowOnResources = memoryPressure != .normal || cpuUsage > 0.85
    }
    
    /// Ottiene la RAM totale in bytes
    private func getTotalRAM() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            // Fallback: usa ProcessInfo
            return UInt64(ProcessInfo.processInfo.physicalMemory)
        }
        
        return UInt64(ProcessInfo.processInfo.physicalMemory)
    }
    
    /// Ottiene la RAM disponibile in bytes
    private func getAvailableRAM() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            // Fallback: stima basata su totalRAM
            return totalRAM / 2
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let freePages = UInt64(stats.free_count)
        let inactivePages = UInt64(stats.inactive_count)
        
        return (freePages + inactivePages) * pageSize
    }
    
    /// Ottiene l'uso della CPU come percentuale (0.0 - 1.0)
    private func getCPUUsage() -> Double {
        // Usa ProcessInfo come approssimazione più semplice
        // Per una misurazione più precisa servirebbe usare IOKit che è complesso
        let processInfo = ProcessInfo.processInfo
        let processorCount = processInfo.processorCount
        
        // Approssimazione basata su load average se disponibile
        // Per ora restituiamo un valore conservativo
        // In produzione si può integrare con librerie più avanzate
        return 0.0  // Placeholder - da implementare con libreria esterna se necessario
    }
    
    /// Calcola la pressione sulla memoria
    private func calculateMemoryPressure() -> MemoryPressure {
        guard totalRAM > 0 else { return .normal }
        
        let usedRAM = totalRAM - availableRAM
        let usagePercentage = Double(usedRAM) / Double(totalRAM)
        
        if usagePercentage > 0.90 {
            return .critical
        } else if usagePercentage > 0.75 {
            return .warning
        } else {
            return .normal
        }
    }
    
    /// Verifica se ci sono risorse sufficienti per un nuovo task
    func canStartNewTask(estimatedRAM: UInt64 = 0) -> Bool {
        updateResources()
        
        // Controlla memoria
        if estimatedRAM > 0 && availableRAM < estimatedRAM {
            return false
        }
        
        // Controlla pressione memoria
        if memoryPressure == .critical {
            return false
        }
        
        // Controlla CPU
        if cpuUsage > 0.90 {
            return false
        }
        
        return true
    }
    
    /// Ottiene la percentuale di RAM disponibile
    func getAvailableRAMPercentage() -> Double {
        guard totalRAM > 0 else { return 0.0 }
        return Double(availableRAM) / Double(totalRAM)
    }
    
    /// Ottiene la percentuale di RAM usata
    func getUsedRAMPercentage() -> Double {
        guard totalRAM > 0 else { return 0.0 }
        return 1.0 - getAvailableRAMPercentage()
    }
    
    /// Verifica se il sistema è collegato all'alimentazione
    func isOnACPower() -> Bool {
        // Usa IOKit per verificare lo stato dell'alimentazione
        // Nota: IOPowerSources è deprecato, usiamo un approccio semplificato
        // Per una soluzione completa servirebbe IOPowerSources.h che non è sempre disponibile
        
        // Approssimazione: su macOS desktop assume sempre AC, su laptop verifica
        #if os(macOS)
        // Per ora restituiamo true come default
        // In produzione si può integrare con IOKit.pwr_mgt se necessario
        return true
        #else
        return false
        #endif
    }
    
    /// Verifica se il sistema può lavorare in background
    func canWorkInBackground() -> Bool {
        return isOnACPower() && !isLowOnResources
    }
}

