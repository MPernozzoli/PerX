import Foundation

/// Client per l'orchestratore "Invia atto" lato backend.
/// POST /claims/{id}/atto/upload-and-send  (multipart: file PDF + channels + wa_account_id?)
enum AttoSendChannel: String, CaseIterable, Identifiable {
    case push
    case email
    case whatsapp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: return "Notifica push (portale)"
        case .email: return "Email con PDF"
        case .whatsapp: return "WhatsApp"
        }
    }
}

struct AttoSendResponse: Decodable {
    let status: String
    let claim_id: String
    let document_id: String
    let channels: [String]
    let delivery: AttoSendDelivery
    let act_flow: [String: AnyDecodable]?
}

struct AttoSendDelivery: Decodable {
    let push: [AttoSendDeliveryItem]
    let email: [AttoSendDeliveryItem]
    let whatsapp: [AttoSendDeliveryItem]
}

struct AttoSendDeliveryItem: Decodable {
    let success: Bool?
    let error: String?
    let message_id: String?
}

/// Helper per accettare valori JSON arbitrari dal backend (act_flow).
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v; return }
        if let v = try? container.decode(Int.self) { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([AnyDecodable].self) { value = v.map(\.value); return }
        if let v = try? container.decode([String: AnyDecodable].self) {
            value = v.mapValues(\.value)
            return
        }
        value = NSNull()
    }
}

actor AttoSendService {
    static let shared = AttoSendService()

    private let client = BackendAPIClient.shared

    func sendAtto(
        claimId: String,
        pdfData: Data,
        fileName: String,
        channels: Set<AttoSendChannel>,
        whatsAppAccountId: String?
    ) async throws -> AttoSendResponse {
        var fields: [String: String] = [
            "channels": channels.map(\.rawValue).sorted().joined(separator: ",")
        ]
        if let id = whatsAppAccountId, !id.isEmpty {
            fields["wa_account_id"] = id
        }

        return try await client.uploadMultipart(
            "/claims/\(claimId)/atto/upload-and-send",
            method: "POST",
            fileData: pdfData,
            fileName: fileName,
            mimeType: "application/pdf",
            fields: fields
        )
    }
}
