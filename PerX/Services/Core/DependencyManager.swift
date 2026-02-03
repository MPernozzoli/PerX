import Foundation
import AppKit
import Combine

/// Gestisce verifica e installazione automatica delle dipendenze del sistema
@MainActor
class DependencyManager {
    static let shared = DependencyManager()
    
    /// In sandbox (TestFlight/App Store) le dipendenze esterne non sono disponibili
    static var isInSandbox: Bool {
        NativeExcelReader.isRunningInSandbox
    }
    
    enum Dependency: String, CaseIterable {
        case python = "python3"
        case node = "node"
        case ollama = "ollama"
        case homebrew = "brew"
        
        var displayName: String {
            switch self {
            case .python: return "Python 3"
            case .node: return "Node.js"
            case .ollama: return "Ollama"
            case .homebrew: return "Homebrew"
            }
        }
        
        var homebrewPackage: String? {
            switch self {
            case .python: return "python@3.11"
            case .node: return "node"
            case .ollama: return "ollama"
            case .homebrew: return nil
            }
        }
        
        var installationURL: String? {
            switch self {
            case .python: return nil
            case .node: return nil
            case .ollama: return "https://ollama.com/download"
            case .homebrew: return "https://brew.sh"
            }
        }
    }
    
    enum DependencyStatus {
        case installed
        case missing
        case checking
        case installing
        case error(String)
    }
    
    @Published private(set) var statuses: [Dependency: DependencyStatus] = [:]
    @Published private(set) var isInstalling = false
    @Published private(set) var installationProgress: String = ""
    
    private var installationTasks: [Dependency: Task<Void, Never>] = [:]
    
    private init() {
        // Inizializza tutti i status a checking
        for dep in Dependency.allCases {
            statuses[dep] = .checking
        }
        
        // Verifica tutte le dipendenze all'avvio
        Task {
            await checkAllDependencies()
        }
    }
    
    // MARK: - Public API
    
    /// Verifica tutte le dipendenze
    func checkAllDependencies() async {
        for dependency in Dependency.allCases {
            await checkDependency(dependency)
        }
    }
    
    /// Verifica una singola dipendenza
    func checkDependency(_ dependency: Dependency) async {
        statuses[dependency] = .checking
        
        let isInstalled = await verifyDependency(dependency)
        
        statuses[dependency] = isInstalled ? .installed : .missing
        
        print("[DependencyManager] \(dependency.displayName): \(isInstalled ? "✅ Installato" : "❌ Mancante")")
    }
    
    /// Verifica se una dipendenza è installata
    func isDependencyInstalled(_ dependency: Dependency) async -> Bool {
        // In sandbox, le dipendenze esterne non sono disponibili
        if DependencyManager.isInSandbox {
            print("[DependencyManager] 📦 Sandbox mode - \(dependency.displayName) non disponibile")
            return false
        }
        
        // Controlla prima lo stato in memoria (siamo già su MainActor)
        if let currentStatus = statuses[dependency],
           case .installed = currentStatus {
            // Verifica comunque che sia ancora installata (potrebbe essere stata rimossa)
            let stillInstalled = await verifyDependency(dependency)
            if !stillInstalled {
                // Aggiorna lo stato se non è più installata
                statuses[dependency] = .missing
            }
            return stillInstalled
        }
        
        // Se non è installato in memoria, verifica sul sistema
        let isInstalled = await verifyDependency(dependency)
        if isInstalled {
            statuses[dependency] = .installed
        } else {
            statuses[dependency] = .missing
        }
        return isInstalled
    }
    
    /// Installa una dipendenza mancante
    func installDependency(_ dependency: Dependency) async -> Bool {
        // In sandbox, le installazioni non sono possibili
        if DependencyManager.isInSandbox {
            print("[DependencyManager] 📦 Sandbox mode - impossibile installare \(dependency.displayName)")
            statuses[dependency] = .error("Non disponibile in TestFlight/App Store")
            return false
        }
        
        // Verifica prima se è già installata
        if await isDependencyInstalled(dependency) {
            await checkDependency(dependency)
            return true
        }
        
        // Se è già in installazione, aspetta
        if let existingTask = installationTasks[dependency] {
            await existingTask.value
            return await isDependencyInstalled(dependency)
        }
        
        // Verifica che Homebrew sia installato (tranne per Homebrew stesso)
        if dependency != .homebrew {
            let homebrewInstalled = await isDependencyInstalled(.homebrew)
            if !homebrewInstalled {
                statuses[dependency] = .error("Homebrew richiesto per l'installazione")
                print("[DependencyManager] ⚠️ Homebrew non installato, impossibile installare \(dependency.displayName)")
                return false
            }
        }
        
        isInstalling = true
        statuses[dependency] = .installing
        installationProgress = "Installazione \(dependency.displayName) in corso..."
        
        let task = Task {
            let success = await performInstallation(dependency)
            await MainActor.run {
                if success {
                    statuses[dependency] = .installed
                    installationProgress = "✅ \(dependency.displayName) installato con successo"
                    NotificationService.shared.sendNotification(
                        title: "Installazione completata",
                        body: "\(dependency.displayName) è stato installato correttamente"
                    )
                } else {
                    statuses[dependency] = .error("Installazione fallita")
                    installationProgress = "❌ Errore durante l'installazione di \(dependency.displayName)"
                }
                isInstalling = false
                installationTasks.removeValue(forKey: dependency)
            }
        }
        
        installationTasks[dependency] = task
        await task.value
        return await isDependencyInstalled(dependency)
    }
    
    /// Gestisce errore da un servizio e avvia installazione se necessario
    func handleServiceError(_ error: Error, for dependency: Dependency) async {
        // Forza una nuova verifica (potrebbe essere cambiato qualcosa)
        await checkDependency(dependency)
        
        // Verifica se la dipendenza è installata
        let isInstalled = await isDependencyInstalled(dependency)
        
        if !isInstalled {
            print("[DependencyManager] 🔧 Dipendenza \(dependency.displayName) mancante, avvio installazione...")
            print("[DependencyManager] Errore originale: \(error.localizedDescription)")
            
            NotificationService.shared.sendNotification(
                title: "Dipendenza mancante",
                body: "Installazione automatica di \(dependency.displayName) in corso..."
            )
            
            let installed = await installDependency(dependency)
            if installed {
                print("[DependencyManager] ✅ \(dependency.displayName) installato con successo")
            } else {
                print("[DependencyManager] ❌ Impossibile installare \(dependency.displayName)")
                // Se c'è un URL di installazione manuale, suggeriscilo
                if let urlString = dependency.installationURL,
                   let url = URL(string: urlString) {
                    print("[DependencyManager] 💡 Installa manualmente da: \(urlString)")
                    await MainActor.run {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else {
            // Se è installata ma c'è comunque un errore, potrebbe essere un problema di configurazione
            print("[DependencyManager] ⚠️ \(dependency.displayName) è installato ma si verifica un errore: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Implementation
    
    private func verifyDependency(_ dependency: Dependency) async -> Bool {
        let possiblePaths = getPossiblePaths(for: dependency)
        
        // Verifica percorsi comuni
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                // Verifica anche che sia eseguibile
                if FileManager.default.isExecutableFile(atPath: path) {
                    // Per Ollama, verifica anche che funzioni effettivamente
                    if dependency == .ollama {
                        if await verifyOllamaExecutable(at: path) {
                            return true
                        }
                    } else {
                        return true
                    }
                }
            }
        }
        
        // Prova con 'command -v' (più robusto di which)
        let foundInPath = await checkInPath(dependency)
        if foundInPath && dependency == .ollama {
            // Se trovato nel PATH, verifica che funzioni
            let path = await getExecutablePath(dependency)
            if let path = path, !path.isEmpty {
                return await verifyOllamaExecutable(at: path)
            }
        }
        
        return foundInPath
    }
    
    private func getExecutablePath(_ dependency: Dependency) async -> String? {
        let command: String
        switch dependency {
        case .homebrew:
            command = "command -v brew"
        default:
            command = "command -v \(dependency.rawValue)"
        }
        
        let output = await runCommandWithOutput(command)
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
    
    private func verifyOllamaExecutable(at path: String) async -> Bool {
        // Verifica che Ollama sia eseguibile e risponda correttamente
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Se Ollama risponde con --version, è installato correttamente
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   !output.isEmpty,
                   output.lowercased().contains("ollama") {
                    return true
                }
            }
        } catch {
            // Se l'esecuzione fallisce, Ollama non è valido
            return false
        }
        
        return false
    }
    
    private func getPossiblePaths(for dependency: Dependency) -> [String] {
        switch dependency {
        case .python:
            return [
                "/usr/local/bin/python3",
                "/opt/homebrew/bin/python3",
                "/usr/bin/python3",
                "\(NSHomeDirectory())/.local/bin/python3"
            ]
        case .node:
            return [
                "/usr/local/bin/node",
                "/opt/homebrew/bin/node",
                "/usr/bin/node"
            ]
        case .ollama:
            return [
                "/usr/local/bin/ollama",
                "/opt/homebrew/bin/ollama",
                "/usr/bin/ollama",
                "\(NSHomeDirectory())/.local/bin/ollama"
            ]
        case .homebrew:
            return [
                "/usr/local/bin/brew",
                "/opt/homebrew/bin/brew"
            ]
        }
    }
    
    private func checkInPath(_ dependency: Dependency) async -> Bool {
        let command: String
        switch dependency {
        case .homebrew:
            command = "command -v brew"
        default:
            command = "command -v \(dependency.rawValue)"
        }
        
        let exitCode = await runCommand(command)
        if exitCode == 0 {
            // Verifica anche che il file esista e sia eseguibile
            if let path = await getExecutablePath(dependency),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path),
               FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        return false
    }
    
    private func performInstallation(_ dependency: Dependency) async -> Bool {
        switch dependency {
        case .homebrew:
            return await installHomebrew()
        case .python, .node, .ollama:
            guard let package = dependency.homebrewPackage else {
                return false
            }
            return await installViaHomebrew(package: package, dependency: dependency)
        }
    }
    
    private func installHomebrew() async -> Bool {
        await MainActor.run {
            installationProgress = "Installazione Homebrew in corso...\nApri il browser per completare l'installazione."
        }
        
        // Apri il browser per l'installazione manuale di Homebrew
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
        
        // Aspetta che l'utente installi Homebrew manualmente
        // Verifica ogni 2 secondi per max 5 minuti
        for _ in 0..<150 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if await verifyDependency(.homebrew) {
                await MainActor.run {
                    installationProgress = "✅ Homebrew installato"
                }
                return true
            }
        }
        
        return false
    }
    
    private func installViaHomebrew(package: String, dependency: Dependency) async -> Bool {
        await MainActor.run {
            installationProgress = "Installazione \(dependency.displayName) tramite Homebrew..."
        }
        
        // Trova il percorso di brew
        let brewPath = await findBrewPath()
        guard !brewPath.isEmpty else {
            await MainActor.run {
                installationProgress = "❌ Homebrew non trovato"
            }
            return false
        }
        
        // Esegui brew install
        let command = "\(brewPath) install \(package)"
        let exitCode = await runCommand(command)
        
        if exitCode == 0 {
            // Verifica che l'installazione sia riuscita
            // Aspetta un po' per permettere a Homebrew di completare l'installazione
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Verifica più volte (max 5 tentativi) perché l'installazione potrebbe richiedere tempo
            for _ in 0..<5 {
                if await verifyDependency(dependency) {
                    await MainActor.run {
                        statuses[dependency] = .installed
                    }
                    return true
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // Se dopo 5 tentativi non è ancora verificabile, potrebbe essere un problema
            await MainActor.run {
                installationProgress = "⚠️ Installazione completata ma verifica in corso..."
            }
            return false
        } else {
            // Cattura l'output dell'errore per debug
            let errorOutput = await runCommandWithOutput("\(brewPath) install \(package) 2>&1")
            await MainActor.run {
                installationProgress = "❌ Errore durante l'installazione"
                if !errorOutput.isEmpty {
                    print("[DependencyManager] Errore installazione \(dependency.displayName): \(errorOutput)")
                }
            }
            return false
        }
    }
    
    private func findBrewPath() async -> String {
        let possiblePaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Prova con which
        let whichResult = await runCommandWithOutput("command -v brew")
        if !whichResult.isEmpty {
            return whichResult.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    private func runCommand(_ command: String) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            print("[DependencyManager] ❌ Errore esecuzione comando: \(error)")
            return -1
        }
    }
    
    private func runCommandWithOutput(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            print("[DependencyManager] ❌ Errore esecuzione comando: \(error)")
            return ""
        }
    }
}

