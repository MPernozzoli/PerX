import Foundation
import PerXCore
import SQLite

/// Manager per gestire allegati email/WhatsApp
/// Gestisce stati, download e spostamento nel Vault
public actor AttachmentManager {
    public static let shared = AttachmentManager()
    
    // Cartella temporanea per allegati in attesa di associazione
    private var tempPath: String { "\(basePath)/temp_attachments" }
    private var basePath: String = "/opt/perx-hub"
    
    private init() {}
    
    // MARK: - Initialization
    
    public func initialize(basePath: String) throws {
        self.basePath = basePath
        
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
        
        print("[AttachmentManager] Initialized at: \(tempPath)")
    }
    
    // MARK: - Create Attachment
    
    /// Registra un nuovo allegato da email/WhatsApp
    public func createAttachment(
        messageId: String,
        sourceType: AttachmentSourceType,
        filename: String,
        size: Int64,
        mimeType: String? = nil,
        sinistroRef: String? = nil
    ) async throws -> HubAttachment {
        let attachment = HubAttachment(
            messageId: messageId,
            filename: filename,
            size: size,
            mimeType: mimeType,
            status: .pending,
            sinistroRef: sinistroRef
        )
        
        try await saveAttachment(attachment)
        
        print("[AttachmentManager] Created attachment: \(attachment.id) (\(filename))")
        return attachment
    }
    
    // MARK: - Download Flow
    
    /// Salva i dati dell'allegato scaricato
    public func saveDownloadedData(_ attachmentId: String, data: Data) async throws -> HubAttachment {
        guard var attachment = try await getAttachment(attachmentId) else {
            throw AttachmentManagerError.attachmentNotFound(attachmentId)
        }
        
        // Salva in temp
        let tempFile = "\(tempPath)/\(attachmentId)_\(attachment.filename)"
        try data.write(to: URL(fileURLWithPath: tempFile))
        
        // Aggiorna stato
        attachment.status = .downloaded
        attachment.processedAt = Date()
        try await saveAttachment(attachment)
        
        // Se ha già sinistro associato, sposta nel vault
        if let sinistroRef = attachment.sinistroRef {
            return try await moveToVault(attachmentId, sinistroRef: sinistroRef)
        }
        
        return attachment
    }
    
    /// Aggiorna stato allegato
    public func updateStatus(_ attachmentId: String, status: AttachmentStatus, errorMessage: String? = nil) async throws -> HubAttachment {
        guard var attachment = try await getAttachment(attachmentId) else {
            throw AttachmentManagerError.attachmentNotFound(attachmentId)
        }
        
        attachment.status = status
        if let error = errorMessage {
            attachment.errorMessage = error
        }
        attachment.processedAt = Date()
        
        try await saveAttachment(attachment)
        return attachment
    }
    
    // MARK: - Association
    
    /// Associa allegato a un sinistro e sposta nel Vault
    public func associateToSinistro(_ attachmentId: String, sinistroRef: String) async throws -> HubAttachment {
        guard var attachment = try await getAttachment(attachmentId) else {
            throw AttachmentManagerError.attachmentNotFound(attachmentId)
        }
        
        attachment.sinistroRef = sinistroRef
        try await saveAttachment(attachment)
        
        // Se già scaricato, sposta nel vault
        if attachment.status == .downloaded {
            return try await moveToVault(attachmentId, sinistroRef: sinistroRef)
        }
        
        return attachment
    }
    
    // MARK: - Vault Move
    
    /// Sposta allegato da temp al Vault
    private func moveToVault(_ attachmentId: String, sinistroRef: String) async throws -> HubAttachment {
        guard var attachment = try await getAttachment(attachmentId) else {
            throw AttachmentManagerError.attachmentNotFound(attachmentId)
        }
        
        // Aggiorna stato
        attachment.status = .processing
        try await saveAttachment(attachment)
        
        // Leggi file da temp
        let tempFile = "\(tempPath)/\(attachmentId)_\(attachment.filename)"
        let fileURL = URL(fileURLWithPath: tempFile)
        
        guard FileManager.default.fileExists(atPath: tempFile) else {
            throw AttachmentManagerError.fileNotFound(tempFile)
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            
            // Crea file nel vault
            let vaultFile = try await VaultManager.shared.uploadFile(
                sinistroRef: sinistroRef,
                folder: "da mail",
                filename: attachment.filename,
                data: data,
                source: .email,
                sourceId: attachment.messageId
            )
            
            // Aggiorna allegato
            attachment.vaultFileId = vaultFile.id
            attachment.status = .saved
            attachment.processedAt = Date()
            try await saveAttachment(attachment)
            
            // Rimuovi file temp
            try? FileManager.default.removeItem(at: fileURL)
            
            print("[AttachmentManager] ✅ Moved to vault: \(attachment.filename) -> \(vaultFile.relativePath)")
            
            return attachment
            
        } catch {
            attachment.status = .error
            attachment.errorMessage = error.localizedDescription
            try await saveAttachment(attachment)
            throw error
        }
    }
    
    // MARK: - Queries
    
    /// Ottieni allegato per ID
    public func getAttachment(_ id: String) async throws -> HubAttachment? {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments.filter(DatabaseSchema.AttachmentsColumns.id == id)
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return attachmentFromRow(row)
    }
    
    /// Ottieni allegati per un messaggio
    public func getAttachments(messageId: String) async throws -> [HubAttachment] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments
            .filter(DatabaseSchema.AttachmentsColumns.messageId == messageId)
        
        return try db.prepare(query).map { attachmentFromRow($0) }
    }
    
    /// Ottieni allegati in attesa per un messaggio
    public func getPendingAttachments(messageId: String) async throws -> [HubAttachment] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments
            .filter(DatabaseSchema.AttachmentsColumns.messageId == messageId)
            .filter(DatabaseSchema.AttachmentsColumns.status == AttachmentStatus.pending.rawValue)
        
        return try db.prepare(query).map { attachmentFromRow($0) }
    }
    
    /// Ottieni allegati in stato pending globalmente (con limite)
    public func getAllPendingAttachments(limit: Int = 50) async throws -> [HubAttachment] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments
            .filter(DatabaseSchema.AttachmentsColumns.status == AttachmentStatus.pending.rawValue)
            .limit(limit)
        
        return try db.prepare(query).map { attachmentFromRow($0) }
    }
    
    /// Ottieni allegati non associati
    public func getUnassociatedAttachments(limit: Int = 50) async throws -> [HubAttachment] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments
            .filter(DatabaseSchema.AttachmentsColumns.sinistroRef == nil)
            .filter(DatabaseSchema.AttachmentsColumns.status == AttachmentStatus.downloaded.rawValue)
            .limit(limit)
        
        return try db.prepare(query).map { attachmentFromRow($0) }
    }
    
    /// Ottieni allegati per sinistro
    public func getAttachmentsForSinistro(_ sinistroRef: String) async throws -> [HubAttachment] {
        let db = try await DatabaseManager.shared.db()
        
        let query = DatabaseSchema.attachments
            .filter(DatabaseSchema.AttachmentsColumns.sinistroRef == sinistroRef)
        
        return try db.prepare(query).map { attachmentFromRow($0) }
    }
    
    // MARK: - Database
    
    private func saveAttachment(_ attachment: HubAttachment) async throws {
        let db = try await DatabaseManager.shared.db()
        
        try db.run(DatabaseSchema.attachments.insert(or: .replace,
            DatabaseSchema.AttachmentsColumns.id <- attachment.id,
            DatabaseSchema.AttachmentsColumns.messageId <- attachment.messageId,
            DatabaseSchema.AttachmentsColumns.sourceType <- "email", // TODO: passare dal modello
            DatabaseSchema.AttachmentsColumns.filename <- attachment.filename,
            DatabaseSchema.AttachmentsColumns.size <- attachment.size,
            DatabaseSchema.AttachmentsColumns.mimeType <- attachment.mimeType,
            DatabaseSchema.AttachmentsColumns.status <- attachment.status.rawValue,
            DatabaseSchema.AttachmentsColumns.vaultFileId <- attachment.vaultFileId,
            DatabaseSchema.AttachmentsColumns.sinistroRef <- attachment.sinistroRef,
            DatabaseSchema.AttachmentsColumns.errorMessage <- attachment.errorMessage,
            DatabaseSchema.AttachmentsColumns.createdAt <- attachment.createdAt.timeIntervalSince1970,
            DatabaseSchema.AttachmentsColumns.processedAt <- attachment.processedAt?.timeIntervalSince1970
        ))
    }
    
    private func attachmentFromRow(_ row: SQLite.Row) -> HubAttachment {
        HubAttachment(
            id: row[DatabaseSchema.AttachmentsColumns.id],
            messageId: row[DatabaseSchema.AttachmentsColumns.messageId],
            filename: row[DatabaseSchema.AttachmentsColumns.filename],
            size: row[DatabaseSchema.AttachmentsColumns.size],
            mimeType: row[DatabaseSchema.AttachmentsColumns.mimeType],
            status: AttachmentStatus(rawValue: row[DatabaseSchema.AttachmentsColumns.status]) ?? .pending,
            vaultFileId: row[DatabaseSchema.AttachmentsColumns.vaultFileId],
            sinistroRef: row[DatabaseSchema.AttachmentsColumns.sinistroRef],
            errorMessage: row[DatabaseSchema.AttachmentsColumns.errorMessage],
            createdAt: Date(timeIntervalSince1970: row[DatabaseSchema.AttachmentsColumns.createdAt]),
            processedAt: row[DatabaseSchema.AttachmentsColumns.processedAt].map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Types

public enum AttachmentSourceType: String, Codable {
    case email
    case whatsapp
}

public enum AttachmentManagerError: Error {
    case attachmentNotFound(String)
    case fileNotFound(String)
    case invalidState(String)
}
