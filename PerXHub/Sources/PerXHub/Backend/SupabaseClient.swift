import Foundation

// ============================================================================
// MARK: - SupabaseClient
//
// Thin REST client per scrivere direttamente su Supabase dalla Hub.
// Pensato per la sync `wa_messages`: l'Hub possiede il bridge OpenWA e
// replica ogni messaggio (in/out, ack) su Supabase; l'app iOS legge tramite
// Realtime/REST.
//
// Config: HubConfiguration.supabaseURL + supabaseServiceRoleKey
//   (vedi Configuration/RuntimeSecrets.swift).
// ============================================================================

public actor SupabaseClient {
    public static let shared = SupabaseClient()

    private let session = URLSession.shared
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    public enum SupabaseError: Error, CustomStringConvertible {
        case notConfigured
        case http(status: Int, body: String)
        case encoding(Error)

        public var description: String {
            switch self {
            case .notConfigured: return "Supabase non configurato (URL o service_role_key mancanti)"
            case .http(let s, let b): return "Supabase HTTP \(s): \(b.prefix(200))"
            case .encoding(let e): return "Supabase encoding error: \(e)"
            }
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        prefer: String? = nil,
        query: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        guard let base = HubConfiguration.supabaseURL,
              let key = HubConfiguration.supabaseServiceRoleKey,
              !base.isEmpty, !key.isEmpty else {
            throw SupabaseError.notConfigured
        }
        var components = URLComponents(string: "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(path)")
        if let query = query { components?.queryItems = query }
        guard let url = components?.url else {
            throw SupabaseError.http(status: 0, body: "Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let prefer = prefer {
            req.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.http(status: 0, body: "No HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(status: http.statusCode, body: body)
        }
        return (data, http)
    }

    // MARK: - Generic upsert/insert

    /// UPSERT su una tabella usando una unique key (PostgREST `on_conflict`).
    public func upsert<T: Encodable>(
        table: String,
        rows: [T],
        onConflict: String? = nil
    ) async throws {
        var query: [URLQueryItem] = []
        if let onConflict = onConflict {
            query.append(URLQueryItem(name: "on_conflict", value: onConflict))
        }
        var req = try makeRequest(
            path: "/rest/v1/\(table)",
            method: "POST",
            prefer: "resolution=merge-duplicates,return=minimal",
            query: query.isEmpty ? nil : query
        )
        do {
            req.httpBody = try encoder.encode(rows)
        } catch {
            throw SupabaseError.encoding(error)
        }
        _ = try await send(req)
    }

    /// SELECT con filtri eq/in/order/limit. Ritorna i row decodificati come `T`.
    public func select<T: Decodable>(
        _ type: T.Type,
        table: String,
        filters: [String: String] = [:],
        order: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        var query: [URLQueryItem] = [URLQueryItem(name: "select", value: "*")]
        for (k, v) in filters {
            query.append(URLQueryItem(name: k, value: v))
        }
        if let order = order {
            query.append(URLQueryItem(name: "order", value: order))
        }
        if let limit = limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let req = try makeRequest(path: "/rest/v1/\(table)", method: "GET", query: query)
        let (data, _) = try await send(req)
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            throw SupabaseError.encoding(error)
        }
    }

    /// UPDATE con filtro eq.
    public func update<T: Encodable>(
        table: String,
        filters: [String: String],
        patch: T
    ) async throws {
        let query = filters.map { URLQueryItem(name: $0.key, value: "eq.\($0.value)") }
        var req = try makeRequest(
            path: "/rest/v1/\(table)",
            method: "PATCH",
            prefer: "return=minimal",
            query: query
        )
        do {
            req.httpBody = try encoder.encode(patch)
        } catch {
            throw SupabaseError.encoding(error)
        }
        _ = try await send(req)
    }
}

// MARK: - wa_messages helpers

public extension SupabaseClient {

    struct WAMessageRow: Encodable {
        public let id: String
        public let tenantSlug: String
        public let accountId: String
        public let chatId: String
        public let waMessageId: String?
        public let direction: String          // "in" | "out"
        public let fromNumber: String?
        public let toNumber: String?
        public let body: String?
        public let messageType: String        // "chat", "image", ...
        public let hasMedia: Bool
        public let mediaMimetype: String?
        public let mediaFilename: String?
        public let mediaBase64: String?
        public let timestamp: Date
        public let status: String             // received | pending | sent | delivered | read | failed
        public let ackStatus: Int?
        public let sinistroRef: String?
        public let isGroup: Bool
        public let author: String?
    }

    struct WAMessageAckPatch: Encodable {
        public let status: String
        public let ackStatus: Int
        public let ackAt: Date
    }

    struct WAOutboundResultPatch: Encodable {
        public let status: String             // "sent" | "failed"
        public let waMessageId: String?
        public let error: String?
    }

    /// Upserta un messaggio (in/out) sulla tabella `wa_messages`.
    func insertWAMessage(_ row: WAMessageRow) async throws {
        try await upsert(table: "wa_messages", rows: [row], onConflict: "id")
    }

    /// Aggiorna lo stato ACK per un dato wa_message_id.
    func updateWAMessageAck(
        accountId: String,
        waMessageId: String,
        ack: Int,
        at: Date
    ) async throws {
        let statusName: String
        switch ack {
        case 1: statusName = "sent"
        case 2: statusName = "delivered"
        case 3, 4: statusName = "read"
        case -1: statusName = "failed"
        default: statusName = "pending"
        }
        try await update(
            table: "wa_messages",
            filters: [
                "account_id": accountId,
                "wa_message_id": waMessageId,
            ],
            patch: WAMessageAckPatch(status: statusName, ackStatus: ack, ackAt: at)
        )
    }

    /// Aggiorna lo stato di un messaggio outbound dopo invio dal bridge.
    func updateWAOutboundResult(
        id: String,
        success: Bool,
        waMessageId: String?,
        error: String?
    ) async throws {
        try await update(
            table: "wa_messages",
            filters: ["id": id],
            patch: WAOutboundResultPatch(
                status: success ? "sent" : "failed",
                waMessageId: waMessageId,
                error: error
            )
        )
    }
}
