//
//  HubOutboxService.swift
//  PerX per iPad
//
//  Servizio per invio email e WhatsApp tramite Hub.
//  Sostituisce CloudKitOutboxService con comunicazione diretta all'Hub.
//

import Foundation
import Combine

/// Servizio per gestire invio email e WhatsApp tramite Hub centralizzato
@MainActor
class HubOutboxService: ObservableObject {
    static let shared = HubOutboxService()
    
    @Published var pendingRequests: [OutboxRequest] = []
    @Published var isSending = false
    @Published var lastError: String?
    
    private let hubClient = HubAPIClient.shared
    
    private init() {}
    
    // MARK: - Email
    
    /// Invia email tramite Hub
    func sendEmail(
        to: [String],
        cc: [String]? = nil,
        bcc: [String]? = nil,
        subject: String,
        body: String,
        isHtml: Bool = true,
        sinistroRiferimento: String? = nil,
        attachments: [(filename: String, mimeType: String, data: Data)]? = nil,
        replyToMessageId: String? = nil
    ) async throws -> String {
        isSending = true
        lastError = nil
        defer { isSending = false }
        
        // Crea richiesta locale per tracking
        let requestId = UUID().uuidString
        let request = OutboxRequest(
            id: requestId,
            type: .email,
            status: .sending,
            createdAt: Date(),
            details: "A: \(to.joined(separator: ", "))"
        )
        pendingRequests.append(request)
        
        do {
            // Converti allegati in base64
            let attachmentRequests = attachments?.map { attachment in
                EmailAttachmentRequest(
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data.base64EncodedString()
                )
            }
            
            // Invia tramite Hub
            let emailRequest = SendEmailRequest(
                to: to,
                cc: cc,
                bcc: bcc,
                subject: subject,
                body: body,
                isHtml: isHtml,
                sinistroRiferimento: sinistroRiferimento,
                attachments: attachmentRequests,
                replyToMessageId: replyToMessageId
            )
            
            let response = try await hubClient.sendEmail(emailRequest)
            
            // Aggiorna stato richiesta
            if let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) {
                pendingRequests[idx].status = .sent
                pendingRequests[idx].resultId = response.messageId
            }
            
            // Rimuovi dalla lista dopo un po'
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    pendingRequests.removeAll { $0.id == requestId }
                }
            }
            
            return response.messageId
            
        } catch {
            // Aggiorna stato errore
            if let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) {
                pendingRequests[idx].status = .failed
                pendingRequests[idx].errorMessage = error.localizedDescription
            }
            
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Schedula email per invio futuro
    func scheduleEmail(
        to: [String],
        subject: String,
        body: String,
        scheduledFor: Date,
        sinistroRiferimento: String? = nil
    ) async throws -> String {
        let request = ScheduleEmailRequest(
            to: to,
            subject: subject,
            body: body,
            scheduledFor: scheduledFor,
            sinistroRiferimento: sinistroRiferimento
        )
        
        let response = try await hubClient.scheduleEmail(request)
        return response.scheduleId
    }
    
    // MARK: - WhatsApp
    
    /// Invia messaggio WhatsApp tramite Hub
    func sendWhatsApp(
        phoneNumber: String? = nil,
        chatId: String? = nil,
        message: String,
        mediaData: Data? = nil,
        mediaType: String? = nil,
        mediaFilename: String? = nil,
        sinistroRiferimento: String? = nil
    ) async throws -> String {
        guard phoneNumber != nil || chatId != nil else {
            throw HubAPIError.badRequest
        }
        
        isSending = true
        lastError = nil
        defer { isSending = false }
        
        // Crea richiesta locale per tracking
        let requestId = UUID().uuidString
        let request = OutboxRequest(
            id: requestId,
            type: .whatsapp,
            status: .sending,
            createdAt: Date(),
            details: "A: \(phoneNumber ?? chatId ?? "")"
        )
        pendingRequests.append(request)
        
        do {
            let waRequest = SendWhatsAppRequest(
                phoneNumber: phoneNumber,
                chatId: chatId,
                message: message,
                mediaData: mediaData?.base64EncodedString(),
                mediaType: mediaType,
                mediaFilename: mediaFilename,
                sinistroRiferimento: sinistroRiferimento
            )
            
            let response = try await hubClient.sendWhatsApp(waRequest)
            
            // Aggiorna stato richiesta
            if let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) {
                pendingRequests[idx].status = .sent
                pendingRequests[idx].resultId = response.messageId
            }
            
            // Rimuovi dalla lista dopo un po'
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    pendingRequests.removeAll { $0.id == requestId }
                }
            }
            
            return response.messageId
            
        } catch {
            // Aggiorna stato errore
            if let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) {
                pendingRequests[idx].status = .failed
                pendingRequests[idx].errorMessage = error.localizedDescription
            }
            
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Schedula messaggio WhatsApp
    func scheduleWhatsApp(
        phoneNumber: String,
        message: String,
        scheduledFor: Date,
        sinistroRiferimento: String? = nil
    ) async throws -> String {
        let request = ScheduleWhatsAppRequest(
            phoneNumber: phoneNumber,
            message: message,
            scheduledFor: scheduledFor,
            sinistroRiferimento: sinistroRiferimento
        )
        
        let response = try await hubClient.scheduleWhatsApp(request)
        return response.scheduleId
    }
    
    // MARK: - Retry
    
    /// Riprova invio richiesta fallita
    func retry(_ request: OutboxRequest) async {
        // TODO: Implementare retry logic
    }
    
    /// Rimuovi richiesta dalla lista
    func dismiss(_ request: OutboxRequest) {
        pendingRequests.removeAll { $0.id == request.id }
    }
}

// MARK: - Models

struct OutboxRequest: Identifiable {
    let id: String
    let type: OutboxType
    var status: OutboxStatus
    let createdAt: Date
    let details: String
    var resultId: String?
    var errorMessage: String?
    
    enum OutboxType {
        case email
        case whatsapp
        
        var icon: String {
            switch self {
            case .email: return "envelope.fill"
            case .whatsapp: return "message.fill"
            }
        }
        
        var label: String {
            switch self {
            case .email: return "Email"
            case .whatsapp: return "WhatsApp"
            }
        }
    }
    
    enum OutboxStatus {
        case sending
        case sent
        case failed
        
        var label: String {
            switch self {
            case .sending: return "Invio in corso..."
            case .sent: return "Inviato"
            case .failed: return "Errore"
            }
        }
    }
}
