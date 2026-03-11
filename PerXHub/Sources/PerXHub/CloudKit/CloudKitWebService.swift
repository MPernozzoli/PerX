import Foundation
import Crypto
import PerXCore

// ============================================================================
// MARK: - CloudKitWebService
// Accesso a CloudKit via Web Services REST API (Server-to-Server)
// Funziona senza entitlements e senza contesto utente - perfetto per daemon H24
// ============================================================================

public actor CloudKitWebService {
    public static let shared = CloudKitWebService()
    
    // Configurazione
    private let containerIdentifier = "iCloud.it.pernozzoli.PerX"
    private let environment = "production" // o "development"
    private let database = "public" // S2S funziona solo con public database
    
    // Credenziali S2S (da caricare da file o environment)
    private var keyID: String?
    private var privateKey: P256.Signing.PrivateKey?
    private var isConfigured = false
    
    // Base URL per CloudKit Web Services
    private var baseURL: String {
        "https://api.apple-cloudkit.com/database/1/\(containerIdentifier)/\(environment)/\(database)"
    }
    
    // Record types (stessi di CloudKitSinistroSyncService)
    private enum RecordTypes {
        static let sinistroMinimal = "SinistroMinimal"
        static let sinistroFull = "SinistroFull"
        static let diarioEntry = "DiarioEntry"
        static let processedEmail = "ProcessedEmail"
        static let task = "Task"
        static let emailEvent = "EmailEvent"
    }
    
    private init() {
        print("[CloudKitWebService] Inizializzato (non ancora configurato)")
    }
    
    // MARK: - Configuration
    
    /// Configura il servizio con le credenziali S2S
    /// - Parameters:
    ///   - keyID: Key ID dal CloudKit Dashboard
    ///   - privateKeyPEM: Chiave privata in formato PEM
    public func configure(keyID: String, privateKeyPEM: String) throws {
        self.keyID = keyID
        
        // Parse della chiave privata PEM
        let cleanedKey = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let keyData = Data(base64Encoded: cleanedKey) else {
            throw CloudKitWebError.invalidPrivateKey("Impossibile decodificare la chiave base64")
        }
        
        do {
            // Prova prima come chiave SEC1 (EC PRIVATE KEY)
            self.privateKey = try P256.Signing.PrivateKey(derRepresentation: keyData)
        } catch {
            do {
                // Prova come PKCS8 (PRIVATE KEY)
                self.privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
            } catch {
                throw CloudKitWebError.invalidPrivateKey("Formato chiave non supportato: \(error)")
            }
        }
        
        isConfigured = true
        print("[CloudKitWebService] ✅ Configurato con keyID: \(keyID)")
    }
    
    /// Configura da file
    public func configure(keyID: String, privateKeyPath: String) throws {
        let keyPEM = try String(contentsOfFile: privateKeyPath, encoding: .utf8)
        try configure(keyID: keyID, privateKeyPEM: keyPEM)
    }
    
    /// Configura da environment variables
    public func configureFromEnvironment() throws {
        guard let keyID = ProcessInfo.processInfo.environment["CLOUDKIT_KEY_ID"] else {
            throw CloudKitWebError.configurationError("CLOUDKIT_KEY_ID non impostato")
        }
        
        // Prova prima da variabile ambiente, poi da file
        if let keyPEM = ProcessInfo.processInfo.environment["CLOUDKIT_PRIVATE_KEY"] {
            try configure(keyID: keyID, privateKeyPEM: keyPEM)
        } else if let keyPath = ProcessInfo.processInfo.environment["CLOUDKIT_PRIVATE_KEY_PATH"] {
            try configure(keyID: keyID, privateKeyPath: keyPath)
        } else {
            // Path di default
            let defaultPath = "/opt/perx-hub/cloudkit_private_key.pem"
            if FileManager.default.fileExists(atPath: defaultPath) {
                try configure(keyID: keyID, privateKeyPath: defaultPath)
            } else {
                throw CloudKitWebError.configurationError("Chiave privata non trovata. Imposta CLOUDKIT_PRIVATE_KEY o CLOUDKIT_PRIVATE_KEY_PATH")
            }
        }
    }
    
    // MARK: - Authentication
    
    /// Genera gli header di autenticazione S2S
    /// Segue il formato Apple: https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html
    private func authHeaders(for request: URLRequest, body: Data?) throws -> [String: String] {
        guard let keyID = keyID, let privateKey = privateKey else {
            throw CloudKitWebError.notConfigured
        }
        
        // Data ISO8601 senza millisecondi (es: 2016-01-25T22:15:43Z)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let dateString = dateFormatter.string(from: Date())
        
        // Calcola hash SHA-256 del body, poi codifica in base64
        let bodyHash: String
        if let body = body, !body.isEmpty {
            let hash = SHA256.hash(data: body)
            bodyHash = Data(hash).base64EncodedString()
        } else {
            // Body vuoto = hash di stringa vuota
            let hash = SHA256.hash(data: Data())
            bodyHash = Data(hash).base64EncodedString()
        }
        
        // Il subpath deve essere SOLO il path, senza host e senza query string
        // Esempio: /database/1/iCloud.it.pernozzoli.PerX/production/public/records/query
        let subpath = request.url?.path ?? ""
        
        // Costruisci il messaggio da firmare
        // Format da documentazione Apple: [Date]:[Body Hash]:[Web service URL subpath]
        let message = "\(dateString):\(bodyHash):\(subpath)"
        
        // DEBUG: Log del messaggio che stiamo firmando
        print("[CloudKitWebService] DEBUG - Date: \(dateString)")
        print("[CloudKitWebService] DEBUG - Body hash: \(bodyHash)")
        print("[CloudKitWebService] DEBUG - Subpath: \(subpath)")
        print("[CloudKitWebService] DEBUG - Message to sign: \(message)")
        
        // Firma con ECDSA P-256 + SHA-256
        // Swift Crypto signature(for:) calcola internamente SHA256 e poi firma
        let messageData = Data(message.utf8)
        let signature = try privateKey.signature(for: messageData)
        
        // DER è il formato corretto per CloudKit (confermato dalla libreria Python)
        let signatureBase64 = signature.derRepresentation.base64EncodedString()
        print("[CloudKitWebService] DEBUG - Signature (DER): \(signatureBase64)")
        
        return [
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": dateString,
            "X-Apple-CloudKit-Request-SignatureV1": signatureBase64
        ]
    }
    
    // MARK: - HTTP Requests
    
    /// Esegue una richiesta POST a CloudKit
    private func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyData = try JSONEncoder().encode(body)
        request.httpBody = bodyData
        
        // Aggiungi header di autenticazione
        let authHeaders = try authHeaders(for: request, body: bodyData)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKitWebError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            // Prova a parsare l'errore CloudKit
            if let errorResponse = try? JSONDecoder().decode(CloudKitErrorResponse.self, from: data) {
                throw CloudKitWebError.serverError(errorResponse.serverErrorCode, errorResponse.reason)
            }
            throw CloudKitWebError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Sinistri
    
    /// Recupera sinistri per un utente
    public func fetchSinistri(forUser user: String, fallbackEmail: String? = nil) async throws -> [SinistroDTO] {
        guard isConfigured else {
            print("[CloudKitWebService] ⚠️ Non configurato, ritorno array vuoto")
            return []
        }
        
        // Costruisci il filtro
        var filterBy: [[String: Any]] = [
            [
                "fieldName": "assignedToUserEmail",
                "comparator": "EQUALS",
                "fieldValue": ["value": user.lowercased()]
            ]
        ]
        
        // Se c'è fallback email, aggiungi come OR (usando query separate)
        let query: [String: Any] = [
            "recordType": RecordTypes.sinistroMinimal,
            "filterBy": filterBy
        ]
        
        let requestBody: [String: Any] = ["query": query]
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let response: CloudKitQueryResponse = try await postRaw("/records/query", bodyData: bodyData)
        
        return response.records.compactMap { record -> SinistroDTO? in
            guard let riferimento = record.fields["riferimento"]?.stringValue else { return nil }
            
            // Mapping da SinistroMinimal → SinistroDTO
            return SinistroDTO(
                id: record.recordName,
                riferimento: riferimento,
                stato: record.fields["stato"]?.stringValue ?? "Da scaricare",
                statoId: record.fields["substate"]?.stringValue ?? "SV001",
                assicurato: record.fields["nomeAssicurato"]?.stringValue,
                polizza: nil, // Non presente in SinistroMinimal
                agenzia: record.fields["nomeCompagnia"]?.stringValue,
                dataAssegnazione: record.fields["dataAssegnazione"]?.dateValue,
                dataChiusura: nil, // Non presente in SinistroMinimal
                ownerEmail: record.fields["ownerEmail"]?.stringValue,
                lastModified: record.fields["lastModifiedAt"]?.dateValue ?? Date()
            )
        }
    }
    
    /// Recupera un sinistro per riferimento
    public func fetchSinistro(riferimento: String) async throws -> SinistroDTO? {
        guard isConfigured else { return nil }
        
        let query: [String: Any] = [
            "recordType": RecordTypes.sinistroMinimal,
            "filterBy": [
                [
                    "fieldName": "riferimento",
                    "comparator": "EQUALS",
                    "fieldValue": ["value": riferimento]
                ]
            ]
        ]
        
        let requestBody: [String: Any] = ["query": query]
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let response: CloudKitQueryResponse = try await postRaw("/records/query", bodyData: bodyData)
        
        guard let record = response.records.first,
              let rif = record.fields["riferimento"]?.stringValue else { return nil }
        
        return SinistroDTO(
            id: record.recordName,
            riferimento: rif,
            stato: record.fields["stato"]?.stringValue ?? "Da scaricare",
            statoId: record.fields["statoId"]?.stringValue ?? "SV001",
            assicurato: record.fields["assicurato"]?.stringValue,
            polizza: record.fields["polizza"]?.stringValue,
            agenzia: record.fields["agenzia"]?.stringValue,
            dataAssegnazione: record.fields["dataAssegnazione"]?.dateValue,
            dataChiusura: record.fields["dataChiusura"]?.dateValue,
            ownerEmail: record.fields["ownerEmail"]?.stringValue,
            lastModified: record.fields["lastModifiedAt"]?.dateValue ?? Date()
        )
    }
    
    /// Salva/aggiorna un sinistro
    public func saveSinistro(_ dto: SinistroDTO, modifiedBy userEmail: String) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "riferimento": ["value": dto.riferimento],
            "stato": ["value": dto.stato],
            "statoId": ["value": dto.statoId],
            "lastModifiedBy": ["value": userEmail],
            "lastModifiedAt": ["value": Int64(Date().timeIntervalSince1970 * 1000)]
        ]
        
        if let assicurato = dto.assicurato {
            fields["assicurato"] = ["value": assicurato]
        }
        if let polizza = dto.polizza {
            fields["polizza"] = ["value": polizza]
        }
        if let agenzia = dto.agenzia {
            fields["agenzia"] = ["value": agenzia]
        }
        if let da = dto.dataAssegnazione {
            fields["dataAssegnazione"] = ["value": Int64(da.timeIntervalSince1970 * 1000)]
        }
        if let dc = dto.dataChiusura {
            fields["dataChiusura"] = ["value": Int64(dc.timeIntervalSince1970 * 1000)]
        }
        if let ownerEmail = dto.ownerEmail {
            fields["ownerEmail"] = ["value": ownerEmail]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.sinistroMinimal,
            "recordName": dto.riferimento,
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ Sinistro salvato: \(dto.riferimento)")
    }
    
    /// Aggiorna un sinistro esistente
    public func updateSinistro(riferimento: String, data: SinistroUpdateRequest) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "lastModifiedAt": ["value": Int64(Date().timeIntervalSince1970 * 1000)]
        ]
        
        if let stato = data.stato {
            fields["stato"] = ["value": stato]
        }
        if let dataAssegnazione = data.dataAssegnazione {
            fields["dataAssegnazione"] = ["value": Int64(dataAssegnazione.timeIntervalSince1970 * 1000)]
        }
        if let dataChiusura = data.dataChiusura {
            fields["dataChiusura"] = ["value": Int64(dataChiusura.timeIntervalSince1970 * 1000)]
        }
        if let assicurato = data.assicurato {
            fields["assicurato"] = ["value": assicurato]
        }
        if let polizza = data.polizza {
            fields["polizza"] = ["value": polizza]
        }
        if let agenzia = data.agenzia {
            fields["agenzia"] = ["value": agenzia]
        }
        if let complessita = data.complessita {
            fields["complessita"] = ["value": complessita]
        }
        if let definizione = data.definizione {
            fields["definizione"] = ["value": definizione]
        }
        if let liquidato = data.liquidato {
            fields["importoLiquidato"] = ["value": liquidato]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.sinistroMinimal,
            "recordName": riferimento,
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ Sinistro aggiornato: \(riferimento)")
    }
    
    // MARK: - Diario
    
    /// Recupera le entry del diario per un sinistro
    public func fetchDiario(sinistroRef: String) async throws -> [DiarioEntryDTO] {
        guard isConfigured else { return [] }
        
        let query: [String: Any] = [
            "recordType": RecordTypes.diarioEntry,
            "filterBy": [
                [
                    "fieldName": "sinistroRef",
                    "comparator": "EQUALS",
                    "fieldValue": ["value": sinistroRef]
                ]
            ],
            "sortBy": [
                ["fieldName": "timestamp", "ascending": false]
            ]
        ]
        
        let requestBody: [String: Any] = ["query": query]
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let response: CloudKitQueryResponse = try await postRaw("/records/query", bodyData: bodyData)
        
        return response.records.compactMap { record -> DiarioEntryDTO? in
            guard let testo = record.fields["testo"]?.stringValue else { return nil }
            
            return DiarioEntryDTO(
                id: record.fields["entryId"]?.stringValue ?? record.recordName,
                timestamp: record.fields["timestamp"]?.dateValue ?? Date(),
                testo: testo,
                tipo: record.fields["tipo"]?.stringValue,
                titolo: record.fields["titolo"]?.stringValue,
                riassunto: record.fields["riassunto"]?.stringValue,
                contenutoCompleto: record.fields["contenutoCompleto"]?.stringValue,
                createdByEmail: record.fields["createdByEmail"]?.stringValue
            )
        }
    }
    
    /// Aggiunge una entry al diario
    public func addDiarioEntry(sinistroRef: String, entry: DiarioEntryDTO) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "sinistroRef": ["value": sinistroRef],
            "entryId": ["value": entry.id],
            "timestamp": ["value": Int64(entry.timestamp.timeIntervalSince1970 * 1000)],
            "testo": ["value": entry.testo]
        ]
        
        if let tipo = entry.tipo {
            fields["tipo"] = ["value": tipo]
        }
        if let titolo = entry.titolo {
            fields["titolo"] = ["value": titolo]
        }
        if let riassunto = entry.riassunto {
            fields["riassunto"] = ["value": riassunto]
        }
        if let contenutoCompleto = entry.contenutoCompleto {
            fields["contenutoCompleto"] = ["value": contenutoCompleto]
        }
        if let createdBy = entry.createdByEmail {
            fields["createdByEmail"] = ["value": createdBy]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.diarioEntry,
            "recordName": "\(sinistroRef)_\(entry.id)",
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ Entry diario aggiunta: \(entry.id)")
    }
    
    /// Salva entry diario (formato esteso)
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
        try await addDiarioEntry(sinistroRef: sinistroRef, entry: entry)
    }
    
    // MARK: - Tasks
    
    /// Recupera task per un utente
    public func fetchTasks(forUser user: String, fallbackEmail: String? = nil) async throws -> [HubTask] {
        guard isConfigured else { return [] }
        
        let query: [String: Any] = [
            "recordType": RecordTypes.task,
            "filterBy": [
                [
                    "fieldName": "assignedTo",
                    "comparator": "EQUALS",
                    "fieldValue": ["value": user.lowercased()]
                ]
            ]
        ]
        
        let requestBody: [String: Any] = ["query": query]
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        
        let response: CloudKitQueryResponse = try await postRaw("/records/query", bodyData: bodyData)
        
        return response.records.compactMap { record -> HubTask? in
            guard let taskId = record.fields["taskId"]?.stringValue,
                  let title = record.fields["title"]?.stringValue,
                  let typeRaw = record.fields["type"]?.stringValue,
                  let type = TaskType(rawValue: typeRaw),
                  let priorityRaw = record.fields["priority"]?.stringValue,
                  let priority = TaskPriority(rawValue: priorityRaw),
                  let statusRaw = record.fields["status"]?.stringValue,
                  let status = TaskStatus(rawValue: statusRaw),
                  let createdAt = record.fields["createdAt"]?.dateValue
            else { return nil }
            
            return HubTask(
                id: taskId,
                title: title,
                description: record.fields["description"]?.stringValue,
                type: type,
                priority: priority,
                sinistroRef: record.fields["sinistroRef"]?.stringValue,
                dueDate: record.fields["dueDate"]?.dateValue,
                status: status,
                assignedTo: record.fields["assignedTo"]?.stringValue,
                createdBy: record.fields["createdBy"]?.stringValue,
                createdAt: createdAt,
                completedAt: record.fields["completedAt"]?.dateValue,
                syncedToCK: true
            )
        }
    }
    
    /// Salva un task
    public func saveTask(_ task: HubTask) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "taskId": ["value": task.id],
            "title": ["value": task.title],
            "type": ["value": task.type.rawValue],
            "priority": ["value": task.priority.rawValue],
            "status": ["value": task.status.rawValue],
            "createdAt": ["value": Int64(task.createdAt.timeIntervalSince1970 * 1000)]
        ]
        
        if let desc = task.description {
            fields["description"] = ["value": desc]
        }
        if let ref = task.sinistroRef {
            fields["sinistroRef"] = ["value": ref]
        }
        if let due = task.dueDate {
            fields["dueDate"] = ["value": Int64(due.timeIntervalSince1970 * 1000)]
        }
        if let assignedTo = task.assignedTo {
            fields["assignedTo"] = ["value": assignedTo]
        }
        if let createdBy = task.createdBy {
            fields["createdBy"] = ["value": createdBy]
        }
        if let completedAt = task.completedAt {
            fields["completedAt"] = ["value": Int64(completedAt.timeIntervalSince1970 * 1000)]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.task,
            "recordName": task.id,
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ Task salvato: \(task.id)")
    }
    
    // MARK: - Email Events
    
    /// Salva email processata
    public func saveProcessedEmail(
        messageId: String,
        userEmail: String,
        sinistroRef: String?,
        category: String
    ) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "messageId": ["value": messageId],
            "userEmail": ["value": userEmail.lowercased()],
            "processedAt": ["value": Int64(Date().timeIntervalSince1970 * 1000)],
            "category": ["value": category]
        ]
        
        if let ref = sinistroRef {
            fields["sinistroRef"] = ["value": ref]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.processedEmail,
            "recordName": messageId,
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ Email processata salvata: \(messageId)")
    }
    
    /// Salva evento email
    public func saveEmailEvent(_ event: HubEmailEvent) async throws {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        var fields: [String: [String: Any]] = [
            "eventId": ["value": event.eventId.uuidString],
            "emailId": ["value": event.emailId],
            "eventType": ["value": event.eventType.rawValue],
            "timestamp": ["value": Int64(event.timestamp.timeIntervalSince1970 * 1000)],
            "direction": ["value": event.direction.rawValue]
        ]
        
        if let sinistroId = event.sinistroId {
            fields["sinistroId"] = ["value": sinistroId]
        }
        
        let record: [String: Any] = [
            "recordType": RecordTypes.emailEvent,
            "recordName": event.eventId.uuidString,
            "fields": fields
        ]
        
        let requestBody: [String: Any] = [
            "operations": [
                [
                    "operationType": "forceUpdate",
                    "record": record
                ]
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let _: CloudKitModifyResponse = try await postRaw("/records/modify", bodyData: bodyData)
        
        print("[CloudKitWebService] ✅ EmailEvent salvato: \(event.eventId)")
    }
    
    // MARK: - Sync Placeholder
    
    /// Sincronizza un sinistro (placeholder per compatibilità)
    public func syncSinistro(riferimento: String) async throws {
        print("[CloudKitWebService] ⚠️ syncSinistro placeholder chiamato per: \(riferimento)")
    }
    
    // MARK: - Raw HTTP
    
    /// Esegue una richiesta POST raw
    private func postRaw<T: Decodable>(_ path: String, bodyData: Data) async throws -> T {
        guard isConfigured else {
            throw CloudKitWebError.notConfigured
        }
        
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // CloudKit S2S richiede Content-Type: text/plain (non application/json!)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        // Aggiungi header di autenticazione
        let authHeaders = try authHeaders(for: request, body: bodyData)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudKitWebError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No body"
            print("[CloudKitWebService] ❌ HTTP \(httpResponse.statusCode): \(responseString)")
            
            if let errorResponse = try? JSONDecoder().decode(CloudKitErrorResponse.self, from: data) {
                throw CloudKitWebError.serverError(errorResponse.serverErrorCode, errorResponse.reason)
            }
            throw CloudKitWebError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response Types

struct CloudKitQueryResponse: Decodable {
    let records: [CloudKitRecord]
    let continuationMarker: String?
}

struct CloudKitModifyResponse: Decodable {
    let records: [CloudKitRecord]?
}

struct CloudKitRecord: Decodable {
    let recordName: String
    let recordType: String
    let fields: [String: CloudKitFieldValue]
    let recordChangeTag: String?
}

struct CloudKitFieldValue: Decodable {
    let value: AnyCodable?
    let type: String?
    
    var stringValue: String? {
        if let str = value?.value as? String {
            return str
        }
        return nil
    }
    
    var intValue: Int? {
        if let num = value?.value as? Int {
            return num
        }
        if let num = value?.value as? Int64 {
            return Int(num)
        }
        return nil
    }
    
    var dateValue: Date? {
        if let timestamp = value?.value as? Int64 {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        }
        if let timestamp = value?.value as? Int {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        }
        if let timestamp = value?.value as? Double {
            return Date(timeIntervalSince1970: timestamp / 1000.0)
        }
        return nil
    }
}

struct CloudKitErrorResponse: Decodable {
    let uuid: String?
    let serverErrorCode: String
    let reason: String
}

// MARK: - AnyCodable Helper

struct AnyCodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int64.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}

// MARK: - Errors

public enum CloudKitWebError: Error, LocalizedError {
    case notConfigured
    case configurationError(String)
    case invalidPrivateKey(String)
    case invalidResponse
    case httpError(Int)
    case serverError(String, String)
    
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "CloudKitWebService non configurato. Chiama configure() o configureFromEnvironment()"
        case .configurationError(let msg):
            return "Errore configurazione: \(msg)"
        case .invalidPrivateKey(let msg):
            return "Chiave privata non valida: \(msg)"
        case .invalidResponse:
            return "Risposta non valida dal server"
        case .httpError(let code):
            return "Errore HTTP: \(code)"
        case .serverError(let code, let reason):
            return "Errore CloudKit [\(code)]: \(reason)"
        }
    }
}
