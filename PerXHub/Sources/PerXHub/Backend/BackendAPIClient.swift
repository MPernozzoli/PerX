import Foundation
import PerXCore

// ============================================================================
// MARK: - BackendAPIClient
//
// Client backend FastAPI/Supabase per l'Hub.
//
// ENV VARS richieste al runtime:
//   PERX_API_URL          URL base del backend  (default: https://api.perx.it)
//   PERX_HUB_EMAIL        Email del service account Hub (es: hub-service@perx.it)
//   PERX_HUB_PASSWORD     Password del service account Hub
//
// Il service account deve essere creato nel backend con ruolo "hub" o "admin".
// ============================================================================

public actor BackendAPIClient {
    public static let shared = BackendAPIClient()

    private let session = URLSession.shared
    private var baseURL: String = "https://api.perx.it"
    private var serviceEmail: String?
    private var servicePassword: String?

    // JWT token state
    private var accessToken: String?
    private var tokenExpiresAt: Date?

    // ISO8601 formatter (no frazioni, compatibile con FastAPI)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {}

    // MARK: - Configuration

    public func configure(baseURL: String, email: String, password: String) {
        self.baseURL = baseURL
        self.serviceEmail = email
        self.servicePassword = password
        print("[BackendAPIClient] Configurato con baseURL: \(baseURL), email: \(email)")
    }

    /// Configura leggendo le variabili d'ambiente.
    /// Chiamare da main.swift prima di avviare il server.
    public func configureFromEnvironment() {
        self.baseURL = ProcessInfo.processInfo.environment["PERX_API_URL"] ?? "https://api.perx.it"
        self.serviceEmail = ProcessInfo.processInfo.environment["PERX_HUB_EMAIL"]
        self.servicePassword = ProcessInfo.processInfo.environment["PERX_HUB_PASSWORD"]
        let hasCredentials = serviceEmail != nil && servicePassword != nil
        print("[BackendAPIClient] Configurato da env. URL: \(baseURL), credenziali: \(hasCredentials ? "✅" : "⚠️ mancanti")")
    }

    // MARK: - Authentication

    /// Autentica il service account e salva il JWT token.
    private func authenticate() async throws {
        guard let email = serviceEmail, let password = servicePassword else {
            throw BackendAPIError.notConfigured
        }

        let url = try makeURL("/api/v1/auth/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form data (OAuth2PasswordRequestForm)
        let body = "username=\(urlEncode(email))&password=\(urlEncode(password))"
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        try validateHTTPResponse(response, data: data, context: "authenticate")

        let loginResp = try decode(BackendLoginResponse.self, from: data)
        self.accessToken = loginResp.access_token

        // Imposta scadenza: expires_in secondi (default 30 minuti se non restituito)
        let ttl = Double(loginResp.expires_in ?? 1800)
        self.tokenExpiresAt = Date().addingTimeInterval(ttl - 60) // 60s di anticipo
        print("[BackendAPIClient] 🔑 Autenticato. Token valido per \(Int(ttl))s")
    }

    /// Assicura che il token sia valido, autenticando se necessario.
    private func ensureAuthenticated() async throws {
        if let exp = tokenExpiresAt, exp > Date(), accessToken != nil {
            return // token ancora valido
        }
        try await authenticate()
    }

    // MARK: - HTTP Helpers

    private func makeURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw BackendAPIError.invalidURL(path)
        }
        return url
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? string
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "-"
            print("[BackendAPIClient] ❌ HTTP \(http.statusCode) in \(context): \(body)")
            throw BackendAPIError.httpError(http.statusCode, body)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "-"
            print("[BackendAPIClient] ⚠️ Decode error (\(type)): \(error) — data: \(preview)")
            throw BackendAPIError.decodingError(String(describing: error))
        }
    }

    /// Esegue una richiesta HTTP autenticata.
    /// Ritenta l'auth una volta in caso di 401.
    private func request<T: Decodable>(
        _ method: String,
        path: String,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await ensureAuthenticated()

        var urlComponents = URLComponents(string: "\(baseURL)\(path)")
        if let qi = queryItems, !qi.isEmpty {
            urlComponents?.queryItems = qi
        }
        guard let url = urlComponents?.url else {
            throw BackendAPIError.invalidURL(path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: req)

        // Retry una volta se 401 (token scaduto)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            print("[BackendAPIClient] 🔄 401 ricevuto, riautentico...")
            self.accessToken = nil
            self.tokenExpiresAt = nil
            try await authenticate()
            req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: req)
            try validateHTTPResponse(response2, data: data2, context: "\(method) \(path)")
            return try decode(T.self, from: data2)
        }

        try validateHTTPResponse(response, data: data, context: "\(method) \(path)")
        return try decode(T.self, from: data)
    }

    /// Versione che non aspetta un body di risposta (204, 200 senza body)
    private func requestVoid(_ method: String, path: String, body: Encodable? = nil) async throws {
        try await ensureAuthenticated()

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw BackendAPIError.invalidURL(path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            self.accessToken = nil
            self.tokenExpiresAt = nil
            try await authenticate()
            req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: req)
            try validateHTTPResponse(response2, data: data2, context: "\(method) \(path)")
            return
        }

        try validateHTTPResponse(response, data: data, context: "\(method) \(path)")
    }

    // MARK: - Claim ID lookup helper

    /// Cerca il backend claim id (UUID) dato un riferimento esterno.
    /// Usato prima di PUT /api/v1/claims/{id}.
    private func claimIDForRiferimento(_ riferimento: String) async throws -> String? {
        let items = try await fetchClaimsRaw(
            queryItems: [URLQueryItem(name: "search", value: riferimento)]
        )
        return items.first(where: { $0.external_ref == riferimento })?.id
    }

    /// Fetch lista claims raw (array o paginata)
    private func fetchClaimsRaw(queryItems: [URLQueryItem]) async throws -> [BackendClaimMinimal] {
        // Il backend può restituire sia un array diretto che un oggetto paginato.
        // Proviamo prima il paginato, poi l'array.
        try await ensureAuthenticated()

        var components = URLComponents(string: "\(baseURL)/api/v1/claims")!
        components.queryItems = queryItems
        guard let url = components.url else {
            throw BackendAPIError.invalidURL("/api/v1/claims")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            self.accessToken = nil
            self.tokenExpiresAt = nil
            try await authenticate()
            req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: req)
            try validateHTTPResponse(response2, data: data2, context: "fetchClaimsRaw")
            return try parseClaims(from: data2)
        }

        try validateHTTPResponse(response, data: data, context: "fetchClaimsRaw")
        return try parseClaims(from: data)
    }

    private func parseClaims(from data: Data) throws -> [BackendClaimMinimal] {
        let decoder = JSONDecoder()
        // Prova array diretto
        if let arr = try? decoder.decode([BackendClaimMinimal].self, from: data) {
            return arr
        }
        // Prova paginato
        if let page = try? decoder.decode(BackendClaimsPage.self, from: data) {
            return page.items ?? []
        }
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "-"
        print("[BackendAPIClient] ⚠️ parseClaims: formato non riconosciuto — \(preview)")
        return []
    }

    // MARK: - Diario helper

    /// Cerca il claim id e poi chiama POST /api/v1/diary
    private func saveDiaryEntryOnBackend(sinistroRef: String, entry: DiarioEntryDTO) async throws {
        // Cerca claim id dal riferimento
        let claimId: String
        if let cid = try await claimIDForRiferimento(sinistroRef) {
            claimId = cid
        } else {
            // fallback: usa il riferimento stesso
            claimId = sinistroRef
            print("[BackendAPIClient] ⚠️ Claim non trovato per ref \(sinistroRef), uso ref come claim_id")
        }

        let body = BackendCreateDiaryEntryBody(
            claim_id: claimId,
            timestamp: iso.string(from: entry.timestamp),
            testo: entry.testo,
            tipo: entry.tipo,
            titolo: entry.titolo,
            riassunto: entry.riassunto,
            contenuto_completo: entry.contenutoCompleto,
            created_by_email: entry.createdByEmail,
            external_entry_id: entry.id
        )

        // Prova prima il path nested, poi il path flat
        do {
            try await requestVoid("POST", path: "/api/v1/claims/\(claimId)/diary", body: body)
        } catch BackendAPIError.httpError(let code, _) where code == 404 {
            // Il backend non ha il path nested, usa il path flat
            try await requestVoid("POST", path: "/api/v1/diary", body: body)
        }
    }

    // MARK: - Public Interface

    // -------------------------------------------------------------------------
    // SINISTRI
    // -------------------------------------------------------------------------

    /// Recupera sinistri per un utente.
    /// Recupera sinistri dal backend Supabase.
    public func fetchSinistri(forUser user: String, fallbackEmail: String? = nil) async throws -> [SinistroDTO] {
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "500")
        ]
        let filterEmail = user.isEmpty ? fallbackEmail : user
        if let email = filterEmail, !email.isEmpty {
            qi.append(URLQueryItem(name: "assegnatario_email", value: email.lowercased()))
        }

        let claims = try await fetchClaimsRaw(queryItems: qi)
        print("[BackendAPIClient] fetchSinistri: \(claims.count) sinistri per \(user)")
        return claims.map { $0.toSinistroDTO() }
    }

    /// Recupera un sinistro per riferimento.
    /// Recupera un sinistro dal backend Supabase.
    public func fetchSinistro(riferimento: String) async throws -> SinistroDTO? {
        let claims = try await fetchClaimsRaw(
            queryItems: [URLQueryItem(name: "search", value: riferimento)]
        )
        guard let match = claims.first(where: { $0.external_ref == riferimento }) ?? claims.first else {
            return nil
        }
        return match.toSinistroDTO()
    }

    /// Salva / crea un sinistro (idempotente via external_ref).
    /// Salva un sinistro sul backend Supabase.
    public func saveSinistro(_ dto: SinistroDTO, modifiedBy userEmail: String) async throws {
        let body = dto.toBackendCreateBody(modifiedBy: userEmail)
        let _: BackendCreatedResponse = try await request(
            "POST",
            path: "/api/v1/claims",
            body: body,
            responseType: BackendCreatedResponse.self
        )
        print("[BackendAPIClient] ✅ saveSinistro: \(dto.riferimento)")
    }

    /// Aggiorna un sinistro esistente.
    /// Aggiorna un sinistro sul backend Supabase.
    public func updateSinistro(riferimento: String, data: SinistroUpdateRequest) async throws {
        guard let claimId = try await claimIDForRiferimento(riferimento) else {
            print("[BackendAPIClient] ⚠️ updateSinistro: claim non trovato per \(riferimento), skip")
            return
        }
        let body = data.toBackendUpdateBody()
        try await requestVoid("PUT", path: "/api/v1/claims/\(claimId)", body: body)
        print("[BackendAPIClient] ✅ updateSinistro: \(riferimento)")
    }

    // -------------------------------------------------------------------------
    // TASKS
    // -------------------------------------------------------------------------

    /// Recupera task per un utente.
    /// Recupera task dal backend Supabase.
    public func fetchTasks(forUser user: String, fallbackEmail: String? = nil) async throws -> [HubTask] {
        var qi: [URLQueryItem] = []
        let filterEmail = user.isEmpty ? fallbackEmail : user
        if let email = filterEmail, !email.isEmpty {
            qi.append(URLQueryItem(name: "assigned_to", value: email.lowercased()))
        }

        let tasks: [BackendTask] = try await {
            // Prova array diretto o paginato
            try await ensureAuthenticated()

            var components = URLComponents(string: "\(baseURL)/api/v1/tasks")!
            if !qi.isEmpty { components.queryItems = qi }
            guard let url = components.url else {
                throw BackendAPIError.invalidURL("/api/v1/tasks")
            }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: req)

            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self.accessToken = nil
                self.tokenExpiresAt = nil
                try await authenticate()
                req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
                let (d2, r2) = try await session.data(for: req)
                try validateHTTPResponse(r2, data: d2, context: "fetchTasks")
                return try parseTasks(from: d2)
            }

            try validateHTTPResponse(response, data: data, context: "fetchTasks")
            return try parseTasks(from: data)
        }()

        print("[BackendAPIClient] fetchTasks: \(tasks.count) task per \(user)")
        return tasks.map { $0.toHubTask() }
    }

    private func parseTasks(from data: Data) throws -> [BackendTask] {
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([BackendTask].self, from: data) { return arr }
        // Prova paginato generico {items: [...]}
        struct Page: Decodable { let items: [BackendTask]? }
        if let page = try? decoder.decode(Page.self, from: data) { return page.items ?? [] }
        return []
    }

    /// Salva un task.
    /// Salva task sul backend Supabase.
    public func saveTask(_ task: HubTask) async throws {
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        func fmt(_ d: Date?) -> String? { d.map { iso2.string(from: $0) } }

        let body = BackendCreateTaskBody(
            external_id: task.id,
            title: task.title,
            description: task.description,
            task_type: task.type.rawValue,
            priority: task.priority.rawValue,
            sinistro_ref: task.sinistroRef,
            due_date: fmt(task.dueDate),
            reminder_date: fmt(task.reminderDate),
            status: task.status.rawValue,
            assigned_to: task.assignedTo,
            created_by: task.createdBy,
            created_at: fmt(task.createdAt)
        )
        try await requestVoid("POST", path: "/api/v1/tasks", body: body)
        print("[BackendAPIClient] ✅ saveTask: \(task.id)")
    }

    // -------------------------------------------------------------------------
    // DIARIO
    // -------------------------------------------------------------------------

    /// Recupera le entry del diario per un sinistro.
    /// Recupera il diario dal backend Supabase.
    public func fetchDiario(sinistroRef: String) async throws -> [DiarioEntryDTO] {
        guard let claimId = try await claimIDForRiferimento(sinistroRef) else {
            print("[BackendAPIClient] fetchDiario: claim non trovato per \(sinistroRef)")
            return []
        }

        // Prova path nested
        let entries = try await fetchDiarioRaw(claimId: claimId)
        return entries.map { $0.toDiarioEntryDTO() }
    }

    private func fetchDiarioRaw(claimId: String) async throws -> [BackendDiaryEntry] {
        try await ensureAuthenticated()

        let path = "/api/v1/claims/\(claimId)/diary"
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw BackendAPIError.invalidURL(path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            self.accessToken = nil
            self.tokenExpiresAt = nil
            try await authenticate()
            req.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let (d2, r2) = try await session.data(for: req)
            try validateHTTPResponse(r2, data: d2, context: "fetchDiarioRaw")
            return try parseDiaryEntries(from: d2)
        }

        try validateHTTPResponse(response, data: data, context: "fetchDiarioRaw")
        return try parseDiaryEntries(from: data)
    }

    private func parseDiaryEntries(from data: Data) throws -> [BackendDiaryEntry] {
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([BackendDiaryEntry].self, from: data) { return arr }
        struct Page: Decodable { let items: [BackendDiaryEntry]? }
        if let page = try? decoder.decode(Page.self, from: data) { return page.items ?? [] }
        return []
    }

    /// Aggiunge una entry al diario.
    /// Aggiunge una voce diario sul backend Supabase.
    public func addDiarioEntry(sinistroRef: String, entry: DiarioEntryDTO) async throws {
        try await saveDiaryEntryOnBackend(sinistroRef: sinistroRef, entry: entry)
        print("[BackendAPIClient] ✅ addDiarioEntry: \(entry.id) per \(sinistroRef)")
    }

    /// Salva entry diario con campi espliciti.
    /// Salva una voce diario sul backend Supabase.
    public func saveDiarioEntry(
        entryId: UUID,
        sinistroRef: String,
        timestamp: Date,
        tipo: String,
        titolo: String?,
        riassunto: String,
        contenutoCompleto: String?,
        createdBy: String
    ) async throws {
        let entry = DiarioEntryDTO(
            id: entryId.uuidString,
            timestamp: timestamp,
            testo: riassunto,
            tipo: tipo,
            titolo: titolo,
            riassunto: riassunto,
            contenutoCompleto: contenutoCompleto,
            createdByEmail: createdBy
        )
        try await saveDiaryEntryOnBackend(sinistroRef: sinistroRef, entry: entry)
        print("[BackendAPIClient] ✅ saveDiarioEntry: \(entryId) per \(sinistroRef)")
    }

    // -------------------------------------------------------------------------
    // EMAIL EVENTS
    // -------------------------------------------------------------------------

    /// Salva un evento email.
    /// Salva un evento email sul backend Supabase.
    public func saveEmailEvent(_ event: HubEmailEvent) async throws {
        let body = BackendEmailEventBody(
            event_id: event.eventId.uuidString,
            email_id: event.emailId,
            event_type: event.eventType.rawValue,
            direction: event.direction.rawValue,
            sinistro_id: event.sinistroId,
            timestamp: iso.string(from: event.timestamp)
        )
        try await requestVoid("POST", path: "/api/v1/email-events", body: body)
        print("[BackendAPIClient] ✅ saveEmailEvent: \(event.eventId)")
    }

    /// Salva un'email processata.
    /// Salva un marker di email processata sul backend Supabase.
    public func saveProcessedEmail(
        messageId: String,
        userEmail: String,
        sinistroRef: String?,
        category: String
    ) async throws {
        let body = BackendProcessedEmailBody(
            message_id: messageId,
            user_email: userEmail.lowercased(),
            sinistro_ref: sinistroRef,
            category: category,
            processed_at: iso.string(from: Date())
        )
        try await requestVoid("POST", path: "/api/v1/processed-emails", body: body)
        print("[BackendAPIClient] ✅ saveProcessedEmail: \(messageId)")
    }

    // -------------------------------------------------------------------------
    // SYNC PLACEHOLDER
    // -------------------------------------------------------------------------

    /// Placeholder per compatibilità. Il backend gestisce la sincronizzazione
    /// tramite saveSinistro / updateSinistro, quindi questa chiamata è no-op.
    public func syncSinistro(riferimento: String) async throws {
        print("[BackendAPIClient] ⚠️ syncSinistro placeholder per: \(riferimento)")
        // No-op: il backend è il source of truth, non serve un passaggio extra di sync
    }
}

// MARK: - Error Types

public enum BackendAPIError: Error, LocalizedError {
    case notConfigured
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "BackendAPIClient non configurato. Imposta PERX_HUB_EMAIL e PERX_HUB_PASSWORD"
        case .invalidURL(let path):
            return "URL non valido: \(path)"
        case .invalidResponse:
            return "Risposta HTTP non valida"
        case .httpError(let code, let body):
            return "Errore HTTP \(code): \(body.prefix(200))"
        case .decodingError(let msg):
            return "Errore decodifica risposta: \(msg)"
        }
    }
}
