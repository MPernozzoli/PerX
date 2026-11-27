import Foundation

/// Monitora e limita l'uso della CPU per operazioni intensive in background.
///
/// **Regole:**
/// - **MAI dalla UI**: non chiamare da View, body, onAppear sincrono, o da codice che blocca il main thread.
/// - Solo da processi automatici (sync, mail, manager, timer) eseguiti in Task/Task.detached.
/// - Se la UI dipende da dati di questi processi: mostrare skeleton/ProgressView e osservare @Published; non attendere await sul main.
actor CPUThrottler {
    static let shared = CPUThrottler()

    private let maxCPUUsage: Double = 0.30 // 30%
    private var lastCheckTime: Date = Date()
    private let checkInterval: TimeInterval = 1.0
    private var previousCPUTicks: [Int32]?

    private init() {}

    /// Esegue un blocco di lavoro pesante dopo aver applicato il throttle. Solo per processi automatici, mai dalla UI.
    func runWithThrottle<T>(_ block: () async throws -> T) async rethrows -> T {
        await throttleIfNeeded()
        return try await block()
    }

    /// Come runWithThrottle, alias per avvii/startup.
    func runAtStartup<T>(_ block: () async throws -> T) async rethrows -> T {
        await throttleIfNeeded()
        return try await block()
    }

    /// Verifica se la CPU è sotto il limite e aspetta se necessario. Solo da background, mai dalla UI.
    func throttleIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastCheckTime) >= checkInterval else {
            return
        }
        lastCheckTime = now
        let cpuUsage = getCurrentCPUUsage()
        if cpuUsage > maxCPUUsage {
            let waitTime = calculateWaitTime(for: cpuUsage)
            print("[CPUThrottler] ⏸️ CPU al \(Int(cpuUsage * 100))%, pausa di \(Int(waitTime * 1000))ms")
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }

    private func calculateWaitTime(for usage: Double) -> TimeInterval {
        let overage = usage - maxCPUUsage
        let baseWait = 0.5
        let multiplier = overage / maxCPUUsage
        return baseWait * (1.0 + multiplier)
    }

    private func getCurrentCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: uint = 0

        var mibKeys: [Int32] = [CTL_HW, HW_NCPU]
        var sizeOfNumCPUs = MemoryLayout<uint>.size
        let status = sysctl(&mibKeys, 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
        if status != 0 { return 0.0 }

        var numCPUsU = natural_t(numCPUs)
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else { return 0.0 }
        let sampleCount = Int(numCpuInfo)
        var ticks = [Int32](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            ticks[index] = cpuInfo[index]
        }
        let sampleSize = MemoryLayout<integer_t>.stride * sampleCount
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(sampleSize))

        let previous = previousCPUTicks
        previousCPUTicks = ticks
        guard let previous, previous.count == ticks.count else { return 0.0 }

        let cpuCount = Int(numCPUs)
        let stateMax = Int(CPU_STATE_MAX)
        var totalUsage: Double = 0.0
        for i in 0..<cpuCount {
            let base = stateMax * i
            guard base + Int(CPU_STATE_IDLE) < ticks.count else { break }
            let inUse = (ticks[base + Int(CPU_STATE_USER)] - previous[base + Int(CPU_STATE_USER)])
                + (ticks[base + Int(CPU_STATE_SYSTEM)] - previous[base + Int(CPU_STATE_SYSTEM)])
                + (ticks[base + Int(CPU_STATE_NICE)] - previous[base + Int(CPU_STATE_NICE)])
            let total = inUse + (ticks[base + Int(CPU_STATE_IDLE)] - previous[base + Int(CPU_STATE_IDLE)])
            if total > 0 { totalUsage += Double(inUse) / Double(total) }
        }
        return cpuCount > 0 ? totalUsage / Double(cpuCount) : 0.0
    }
}
