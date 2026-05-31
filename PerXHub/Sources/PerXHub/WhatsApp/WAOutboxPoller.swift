import Foundation

// ============================================================================
// MARK: - WAOutboxPoller
//
// Polla Supabase `wa_messages` per righe con `status='pending'` inserite
// dall'app iOS / portale, le invia via WA Bridge OpenWA locale, e aggiorna
// la riga con l'esito (status='sent' + wa_message_id, oppure status='failed'
// + error). Il messaggio confermato verrà poi rimbalzato dal bridge sul
// route `/internal/whatsapp/message` con `isOutgoing=true`, generando una
// nuova riga `received/sent` per la chat — questo è ok, le righe `pending`
// sono solo intent dell'utente.
// ============================================================================

public actor WAOutboxPoller {
    public static let shared = WAOutboxPoller()

    private var task: Task<Void, Never>?
    private var pollInterval: UInt64 = 5_000_000_000  // 5s in ns
    private var inflight = Set<String>()              // id già in invio
    private let session = URLSession.shared
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {}

    public func start() {
        guard task == nil else { return }
        guard HubConfiguration.supabaseURL != nil,
              HubConfiguration.supabaseServiceRoleKey != nil else {
            print("[WAOutboxPoller] Supabase non configurato, poller non avviato")
            return
        }
        print("[WAOutboxPoller] avvio (interval \(pollInterval / 1_000_000_000)s)")
        task = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 5_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Tick

    private struct OutboxRow: Decodable {
        let id: String
        let tenantSlug: String
        let accountId: String
        let chatId: String
        let toNumber: String?
        let body: String?
        let mediaMimetype: String?
        let mediaFilename: String?
        let mediaBase64: String?

        enum CodingKeys: String, CodingKey {
            case id
            case tenantSlug = "tenant_slug"
            case accountId = "account_id"
            case chatId = "chat_id"
            case toNumber = "to_number"
            case body
            case mediaMimetype = "media_mimetype"
            case mediaFilename = "media_filename"
            case mediaBase64 = "media_base64"
        }
    }

    private func tick() async {
        let rows: [OutboxRow]
        do {
            rows = try await SupabaseClient.shared.select(
                OutboxRow.self,
                table: "wa_messages",
                filters: ["status": "eq.pending", "direction": "eq.out"],
                order: "created_at.asc",
                limit: 20
            )
        } catch {
            print("[WAOutboxPoller] poll fallito: \(error)")
            return
        }
        guard !rows.isEmpty else { return }

        for row in rows {
            if inflight.contains(row.id) { continue }
            inflight.insert(row.id)
            await sendOne(row)
            inflight.remove(row.id)
        }
    }

    private func sendOne(_ row: OutboxRow) async {
        let to = row.toNumber ?? row.chatId
        guard !to.isEmpty else {
            await markFailed(row.id, error: "missing to_number/chat_id")
            return
        }

        struct Media: Encodable {
            let mimetype: String
            let data: String
            let filename: String?
        }
        struct SendBody: Encodable {
            let to: String
            let body: String
            let media: Media?
        }
        struct SendResponse: Decodable {
            let success: Bool?
            let messageId: String?
            let error: String?
        }

        let media: Media? = {
            guard let mt = row.mediaMimetype, let payload = row.mediaBase64 else { return nil }
            return Media(mimetype: mt, data: payload, filename: row.mediaFilename)
        }()
        let payload = SendBody(to: to, body: row.body ?? "", media: media)

        let bridgeURL = HubConfiguration.waBridgeURL
        guard let url = URL(string: "\(bridgeURL)/clients/\(row.accountId)/send") else {
            await markFailed(row.id, error: "invalid bridge URL")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        do {
            req.httpBody = try encoder.encode(payload)
        } catch {
            await markFailed(row.id, error: "encoding error: \(error)")
            return
        }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                await markFailed(row.id, error: "bridge HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
                return
            }
            let resp = try? JSONDecoder().decode(SendResponse.self, from: data)
            if let resp = resp, resp.success == true {
                await markSent(row.id, waMessageId: resp.messageId)
            } else if let err = resp?.error {
                await markFailed(row.id, error: err)
            } else {
                await markSent(row.id, waMessageId: resp?.messageId)
            }
        } catch {
            await markFailed(row.id, error: "bridge unreachable: \(error)")
        }
    }

    private func markSent(_ id: String, waMessageId: String?) async {
        do {
            try await SupabaseClient.shared.updateWAOutboundResult(
                id: id,
                success: true,
                waMessageId: waMessageId,
                error: nil
            )
            print("[WAOutboxPoller] ✅ sent \(id) -> \(waMessageId ?? "?")")
        } catch {
            print("[WAOutboxPoller] failed to mark sent \(id): \(error)")
        }
    }

    private func markFailed(_ id: String, error: String) async {
        do {
            try await SupabaseClient.shared.updateWAOutboundResult(
                id: id,
                success: false,
                waMessageId: nil,
                error: error
            )
            print("[WAOutboxPoller] ❌ failed \(id): \(error)")
        } catch {
            print("[WAOutboxPoller] failed to mark failed \(id): \(error)")
        }
    }
}
