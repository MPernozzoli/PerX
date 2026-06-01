import Foundation

enum LocalDependency: String, CaseIterable, Codable, Hashable, Sendable {
    case homebrew
    case python
    case node
    case ollama
    case zip
    case unzip

    var displayName: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .python: return "Python 3"
        case .node: return "Node.js"
        case .ollama: return "Ollama"
        case .zip: return "ZIP"
        case .unzip: return "Unzip"
        }
    }

    var homebrewPackage: String? {
        switch self {
        case .python: return "python@3.11"
        case .node: return "node"
        case .ollama: return "ollama"
        case .homebrew, .zip, .unzip: return nil
        }
    }

    var installationURL: URL? {
        switch self {
        case .homebrew:
            return URL(string: "https://brew.sh")
        case .ollama:
            return URL(string: "https://ollama.com/download/mac")
        case .python, .node, .zip, .unzip:
            return nil
        }
    }
}

enum LocalDependencyState: String, Codable, Sendable {
    case installed
    case missing
    case installing
    case updating
    case error
}

struct LocalDependencyStatus: Codable, Equatable, Sendable {
    let dependency: LocalDependency
    let state: LocalDependencyState
    let executablePath: String?
    let version: String?
    let updateAvailable: Bool?
    let message: String?

    var isInstalled: Bool { state == .installed }
}

struct LocalAgentCommandResult: Codable, Equatable, Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String

    var combinedOutput: String {
        [output, errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct LocalAIModel: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let model: String?
    let modifiedAt: String?
    let size: Int64?
    let digest: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case modifiedAt = "modified_at"
        case size
        case digest
    }
}

enum PerXLocalAgentError: LocalizedError, Sendable {
    case agentUnavailable(String)
    case dependencyMissing(LocalDependency)
    case dependencyNotInstallable(LocalDependency)
    case dependencyNotUpdatable(LocalDependency)
    case homebrewRequired(LocalDependency)
    case invalidExecutable(String)
    case invalidInputFile(String)
    case invalidModelFile(String)
    case invalidRequest(String)
    case launchFailed(String)
    case commandTimedOut(TimeInterval)
    case commandFailed(exitCode: Int32, output: String)
    case ollamaStartupTimedOut(TimeInterval)
    case ollamaProcessExited
    case invalidServerResponse
    case localServiceFailed(String)

    var errorDescription: String? {
        switch self {
        case .agentUnavailable(let reason):
            return "PerX Local Agent non e disponibile: \(reason)"
        case .dependencyMissing(let dependency):
            return "\(dependency.displayName) non risulta installato. Installa la dipendenza e riprova."
        case .dependencyNotInstallable(let dependency):
            return "\(dependency.displayName) richiede installazione manuale."
        case .dependencyNotUpdatable(let dependency):
            return "\(dependency.displayName) non puo essere aggiornato automaticamente dal PerX Local Agent."
        case .homebrewRequired(let dependency):
            return "Homebrew e richiesto per installare o aggiornare \(dependency.displayName)."
        case .invalidExecutable(let path):
            return "Il comando locale non e eseguibile: \(path)."
        case .invalidInputFile(let path):
            return "Il file locale non e leggibile: \(path)."
        case .invalidModelFile(let path):
            return "Il file modello locale non e leggibile: \(path)."
        case .invalidRequest(let reason):
            return "PerX Local Agent ha ricevuto una richiesta non valida: \(reason)"
        case .launchFailed(let reason):
            return "PerX Local Agent non riesce ad avviare il comando locale: \(reason)"
        case .commandTimedOut(let timeout):
            return "Il comando locale non ha risposto entro \(Int(timeout)) secondi."
        case .commandFailed(let exitCode, let output):
            let details = output.isEmpty ? "nessun dettaglio disponibile" : output
            return "Il comando locale e terminato con codice \(exitCode): \(details)"
        case .ollamaStartupTimedOut(let timeout):
            return "Ollama non ha risposto su localhost:11434 entro \(Int(timeout)) secondi."
        case .ollamaProcessExited:
            return "Ollama si e chiuso prima di rendere disponibile il server locale."
        case .invalidServerResponse:
            return "Il servizio locale ha restituito una risposta non valida."
        case .localServiceFailed(let reason):
            return "Il servizio locale non ha completato la richiesta: \(reason)"
        }
    }
}
