import Foundation
import SQLite

/// Schema del database SQLite per l'Hub
public struct DatabaseSchema {
    
    // MARK: - Tables
    
    public static let vaultFiles = Table("vault_files")
    public static let jobs = Table("jobs")
    public static let fileManifest = Table("file_manifest")
    public static let sinistroFolders = Table("sinistro_folders")
    
    // Sinistri table (Hub source of truth)
    public static let sinistri = Table("sinistri")
    
    // Email tables
    public static let emails = Table("emails")
    public static let emailAccounts = Table("email_accounts")
    public static let attachments = Table("attachments")
    public static let scheduledEmails = Table("scheduled_emails")
    public static let scheduledWhatsApp = Table("scheduled_whatsapp")
    public static let archivedEmailRefs = Table("archived_email_refs")
    
    // WhatsApp tables
    public static let whatsappChats = Table("whatsapp_chats")
    public static let whatsappMessages = Table("whatsapp_messages")
    
    // Connected clients (heartbeat tracking)
    public static let connectedClients = Table("connected_clients")
    
    // MARK: - vault_files columns
    
    public struct VaultFilesColumns {
        public static let id = Expression<String>("id")
        public static let sinistroRef = Expression<String>("sinistro_ref")
        public static let relativePath = Expression<String>("relative_path")
        public static let filename = Expression<String>("filename")
        public static let folder = Expression<String>("folder")
        public static let size = Expression<Int64>("size")
        public static let mimeType = Expression<String?>("mime_type")
        public static let checksum = Expression<String?>("checksum")
        public static let source = Expression<String>("source")
        public static let sourceId = Expression<String?>("source_id")
        public static let createdAt = Expression<Double>("created_at")
        public static let modifiedAt = Expression<Double?>("modified_at")
    }
    
    // MARK: - jobs columns
    
    public struct JobsColumns {
        public static let id = Expression<String>("id")
        public static let type = Expression<String>("type")
        public static let status = Expression<String>("status")
        public static let priority = Expression<Int>("priority")
        public static let payload = Expression<String>("payload") // JSON
        public static let createdAt = Expression<Double>("created_at")
        public static let startedAt = Expression<Double?>("started_at")
        public static let completedAt = Expression<Double?>("completed_at")
        public static let errorMessage = Expression<String?>("error_message")
        public static let retryCount = Expression<Int>("retry_count")
    }
    
    // MARK: - file_manifest columns
    
    public struct FileManifestColumns {
        public static let legacyPath = Expression<String>("legacy_path")
        public static let vaultFileId = Expression<String?>("vault_file_id")
        public static let lastKnownChecksum = Expression<String?>("last_known_checksum")
        public static let lastKnownSize = Expression<Int64?>("last_known_size")
        public static let lastKnownModified = Expression<Double?>("last_known_modified")
        public static let lastSyncAt = Expression<Double>("last_sync_at")
        public static let syncDirection = Expression<String>("sync_direction")
    }
    
    // MARK: - sinistro_folders columns
    
    public struct SinistroFoldersColumns {
        public static let sinistroRef = Expression<String>("sinistro_ref")
        public static let status = Expression<String>("status")
        public static let lastSyncAt = Expression<Double?>("last_sync_at")
        public static let fileCount = Expression<Int>("file_count")
        public static let totalSize = Expression<Int64>("total_size")
        public static let errorMessage = Expression<String?>("error_message")
    }
    
    // MARK: - sinistri columns
    
    public struct SinistriColumns {
        // Identificativi
        public static let riferimento = Expression<String>("riferimento")
        public static let numeroSinistro = Expression<String?>("numero_sinistro")
        public static let numeroPolizza = Expression<String?>("numero_polizza")
        public static let tipoPolizza = Expression<String?>("tipo_polizza")
        
        // Stato e date
        public static let stato = Expression<String>("stato")
        public static let substate = Expression<String?>("substate")
        public static let assegnatario = Expression<String?>("assegnatario")
        public static let dataAssegnazione = Expression<Double?>("data_assegnazione")
        public static let dataChiusura = Expression<Double?>("data_chiusura")
        public static let dataAperturaGestione = Expression<Double?>("data_apertura_gestione")
        public static let dataInvioAtto = Expression<Double?>("data_invio_atto")
        public static let dataRevoca = Expression<Double?>("data_revoca")
        public static let dataRitornoAtto = Expression<Double?>("data_ritorno_atto")
        public static let dataComunicazioneEsito = Expression<Double?>("data_comunicazione_esito")
        public static let dataRicezioneAttoSottoscritto = Expression<Double?>("data_ricezione_atto_sottoscritto")
        
        // Compagnia e agenzia
        public static let compagnia = Expression<String?>("compagnia")
        public static let gruppo = Expression<String?>("gruppo")
        public static let area = Expression<String?>("area")
        public static let codiceAgenzia = Expression<String?>("codice_agenzia")
        public static let agenzia = Expression<String?>("agenzia")
        public static let subagenzia = Expression<String?>("subagenzia")
        public static let emailAgenzia = Expression<String?>("email_agenzia")
        public static let telefonoAgenzia = Expression<String?>("telefono_agenzia")
        
        // Contraente
        public static let nomeContraente = Expression<String?>("nome_contraente")
        public static let telefonoContraente = Expression<String?>("telefono_contraente")
        public static let emailContraente = Expression<String?>("email_contraente")
        public static let indirizzoContraente = Expression<String?>("indirizzo_contraente")
        
        // Assicurato
        public static let nomeAssicurato = Expression<String?>("nome_assicurato")
        public static let telefonoAssicurato = Expression<String?>("telefono_assicurato")
        public static let telefoniAssicurato = Expression<String?>("telefoni_assicurato") // JSON array
        public static let emailAssicurato = Expression<String?>("email_assicurato")
        public static let emailAssicuratoArray = Expression<String?>("email_assicurato_array") // JSON array
        public static let indirizzoAssicurato = Expression<String?>("indirizzo_assicurato")
        public static let codiceFiscaleAssicurato = Expression<String?>("codice_fiscale_assicurato")
        public static let partitaIVAAssicurato = Expression<String?>("partita_iva_assicurato")
        
        // Danneggiato
        public static let nomeDanneggiato = Expression<String?>("nome_danneggiato")
        public static let telefonoDanneggiato = Expression<String?>("telefono_danneggiato")
        public static let emailDanneggiato = Expression<String?>("email_danneggiato")
        public static let indirizzoDanneggiato = Expression<String?>("indirizzo_danneggiato")
        
        // Date sinistro
        public static let dataSinistro = Expression<Double?>("data_sinistro")
        public static let dataDenuncia = Expression<Double?>("data_denuncia")
        public static let dataIncarico = Expression<Double?>("data_incarico")
        public static let dataSopralluogo = Expression<Double?>("data_sopralluogo")
        
        // Importi
        public static let richiesta = Expression<Double?>("richiesta")
        public static let liquidato = Expression<Double?>("liquidato")
        public static let dannoAccertato = Expression<Double?>("danno_accertato")
        public static let dannoAccertatoNetto = Expression<Double?>("danno_accertato_netto")
        public static let stimaDanno = Expression<Double?>("stima_danno")
        
        // Esito perizia
        public static let definizione = Expression<String?>("definizione")
        public static let definizioneManuale = Expression<Bool>("definizione_manuale")
        public static let concordata = Expression<Bool>("concordata")
        public static let negativa = Expression<Bool>("negativa")
        public static let fulminazione = Expression<String?>("fulminazione")
        
        // Regolarità amministrativa (da PDF incarico)
        public static let regolaritaAmministrativa = Expression<Bool?>("regolarita_amministrativa")
        public static let dataPagamentoPremio = Expression<Double?>("data_pagamento_premio")
        public static let regolaritaAmministrativaOverride = Expression<Bool>("regolarita_amministrativa_override")
        
        // Flags e stato
        public static let sopralluogo = Expression<Bool>("sopralluogo")
        public static let giustificativi = Expression<Bool>("giustificativi")
        public static let iban = Expression<Bool>("iban")
        public static let sinistroCollegato = Expression<Bool>("sinistro_collegato")
        public static let idSinistroCollegato = Expression<String?>("id_sinistro_collegato")
        public static let oltreDieciBeni = Expression<Bool>("oltre_dieci_beni")
        
        // Legacy (per compatibilità con ExcelReaderService)
        public static let cliente = Expression<String?>("cliente")
        public static let mandante = Expression<String?>("mandante")
        public static let localita = Expression<String?>("localita")
        public static let provincia = Expression<String?>("provincia")
        public static let tipoDanno = Expression<String?>("tipo_danno")
        
        // Metadati file e sync
        public static let legacyPath = Expression<String?>("legacy_path")
        public static let folderStatus = Expression<String?>("folder_status")
        public static let cartella = Expression<String?>("cartella")
        public static let lastModifiedAt = Expression<Double>("last_modified_at")
        public static let createdAt = Expression<Double>("created_at")
        public static let syncedToCK = Expression<Bool>("synced_to_ck")
        public static let cloudKitRecordID = Expression<String?>("cloudkit_record_id")
    }
    
    // MARK: - emails columns
    
    public struct EmailsColumns {
        public static let messageId = Expression<String>("message_id")
        public static let accountId = Expression<String>("account_id")
        public static let subject = Expression<String?>("subject")
        public static let senderEmail = Expression<String>("sender_email")
        public static let senderName = Expression<String?>("sender_name")
        public static let recipients = Expression<String>("recipients") // JSON array
        public static let date = Expression<Double>("date")
        public static let body = Expression<String?>("body")
        public static let category = Expression<String?>("category")
        public static let direction = Expression<String>("direction") // IN/OUT
        public static let senderType = Expression<String?>("sender_type")
        public static let sinistroRef = Expression<String?>("sinistro_ref")
        public static let confidence = Expression<Double?>("confidence")
        public static let matchedPatterns = Expression<String?>("matched_patterns") // JSON
        public static let isRead = Expression<Bool>("is_read")
        public static let threadId = Expression<String?>("thread_id")
        public static let processedAt = Expression<Double>("processed_at")
        public static let syncedToCK = Expression<Bool>("synced_to_ck")
    }
    
    // MARK: - Alias di comodo per accesso diretto (usati in EmailProcessor)
    
    public static let emailMessageId = EmailsColumns.messageId
    public static let emailAccountId = EmailsColumns.accountId
    public static let emailSubject = EmailsColumns.subject
    public static let emailSenderEmail = EmailsColumns.senderEmail
    public static let emailSenderName = EmailsColumns.senderName
    public static let emailDate = EmailsColumns.date
    public static let emailBody = EmailsColumns.body
    public static let emailCategory = EmailsColumns.category
    public static let emailDirection = EmailsColumns.direction
    public static let emailSenderType = EmailsColumns.senderType
    public static let emailSinistroRef = EmailsColumns.sinistroRef
    public static let emailConfidence = EmailsColumns.confidence
    public static let emailMatchedPatterns = EmailsColumns.matchedPatterns
    public static let emailIsRead = EmailsColumns.isRead
    public static let emailProcessedAt = EmailsColumns.processedAt
    public static let emailSyncedToCK = EmailsColumns.syncedToCK
    
    // MARK: - email_accounts columns (per deduplicazione CC)
    
    public struct EmailAccountsColumns {
        public static let messageId = Expression<String>("message_id")
        public static let accountId = Expression<String>("account_id")
        public static let mailbox = Expression<String?>("mailbox")
        public static let isRead = Expression<Bool>("is_read")
    }
    
    // MARK: - attachments columns
    
    public struct AttachmentsColumns {
        public static let id = Expression<String>("id")
        public static let messageId = Expression<String>("message_id")
        public static let sourceType = Expression<String>("source_type") // email/whatsapp
        public static let filename = Expression<String>("filename")
        public static let size = Expression<Int64>("size")
        public static let mimeType = Expression<String?>("mime_type")
        public static let status = Expression<String>("status")
        public static let vaultFileId = Expression<String?>("vault_file_id")
        public static let sinistroRef = Expression<String?>("sinistro_ref")
        public static let errorMessage = Expression<String?>("error_message")
        public static let createdAt = Expression<Double>("created_at")
        public static let processedAt = Expression<Double?>("processed_at")
    }
    
    // MARK: - scheduled_emails columns
    
    public struct ScheduledEmailsColumns {
        public static let id = Expression<String>("id")
        public static let accountId = Expression<String>("account_id")
        public static let toAddresses = Expression<String>("to_addresses") // JSON
        public static let ccAddresses = Expression<String?>("cc_addresses") // JSON
        public static let subject = Expression<String>("subject")
        public static let body = Expression<String>("body")
        public static let attachmentIds = Expression<String?>("attachment_ids") // JSON
        public static let scheduledAt = Expression<Double>("scheduled_at")
        public static let status = Expression<String>("status")
        public static let sentAt = Expression<Double?>("sent_at")
        public static let errorMessage = Expression<String?>("error_message")
        public static let createdBy = Expression<String?>("created_by")
        public static let createdAt = Expression<Double>("created_at")
    }
    
    // MARK: - scheduled_whatsapp columns
    
    public struct ScheduledWhatsAppColumns {
        public static let id = Expression<String>("id")
        public static let accountId = Expression<String>("account_id")
        public static let phoneNumber = Expression<String>("phone_number")
        public static let body = Expression<String>("body")
        public static let mediaData = Expression<String?>("media_data") // Base64 encoded
        public static let mediaType = Expression<String?>("media_type")
        public static let mediaFilename = Expression<String?>("media_filename")
        public static let scheduledAt = Expression<Double>("scheduled_at")
        public static let status = Expression<String>("status") // pending, sent, failed
        public static let sentAt = Expression<Double?>("sent_at")
        public static let sentMessageId = Expression<String?>("sent_message_id")
        public static let errorMessage = Expression<String?>("error_message")
        public static let sinistroRef = Expression<String?>("sinistro_ref")
        public static let createdBy = Expression<String?>("created_by")
        public static let createdAt = Expression<Double>("created_at")
    }
    
    // MARK: - archived_email_refs columns (per sinistri chiusi)
    
    public struct ArchivedEmailRefsColumns {
        public static let sinistroRef = Expression<String>("sinistro_ref")
        public static let messageId = Expression<String>("message_id")
        public static let date = Expression<Double>("date")
        public static let subject = Expression<String?>("subject")
    }
    
    // MARK: - connected_clients columns (heartbeat tracking)
    
    public struct ConnectedClientsColumns {
        public static let userId = Expression<String>("user_id")
        public static let lastSeen = Expression<Double>("last_seen")
        public static let clientInfo = Expression<String?>("client_info") // optional: app version, platform, etc.
    }
    
    // MARK: - whatsapp_chats columns
    
    public struct WhatsAppChatsColumns {
        public static let id = Expression<String>("id")
        public static let accountId = Expression<String>("account_id")
        public static let chatId = Expression<String>("chat_id")           // ID chat WhatsApp (numero@c.us o gruppo)
        public static let name = Expression<String?>("name")                // Nome contatto/gruppo
        public static let phoneNumber = Expression<String?>("phone_number") // Numero telefono (se contatto singolo)
        public static let isGroup = Expression<Bool>("is_group")
        public static let lastMessageBody = Expression<String?>("last_message_body")
        public static let lastMessageAt = Expression<Double?>("last_message_at")
        public static let unreadCount = Expression<Int>("unread_count")
        public static let sinistroRef = Expression<String?>("sinistro_ref") // Associazione sinistro
        public static let createdAt = Expression<Double>("created_at")
        public static let updatedAt = Expression<Double>("updated_at")
    }
    
    // MARK: - whatsapp_messages columns
    
    public struct WhatsAppMessagesColumns {
        public static let id = Expression<String>("id")
        public static let accountId = Expression<String>("account_id")
        public static let chatId = Expression<String>("chat_id")
        public static let waMessageId = Expression<String>("wa_message_id")  // ID messaggio WhatsApp
        public static let fromNumber = Expression<String>("from_number")
        public static let toNumber = Expression<String?>("to_number")
        public static let body = Expression<String?>("body")
        public static let timestamp = Expression<Double>("timestamp")
        public static let direction = Expression<String>("direction")        // 'in' o 'out'
        public static let type = Expression<String>("type")                  // text, image, video, audio, document, sticker
        public static let mediaType = Expression<String?>("media_type")
        public static let mediaFilename = Expression<String?>("media_filename")
        public static let mediaData = Expression<String?>("media_data")      // Base64 per media piccoli
        public static let mediaLocalPath = Expression<String?>("media_local_path") // Path locale se scaricato
        public static let isRead = Expression<Bool>("is_read")
        public static let sinistroRef = Expression<String?>("sinistro_ref")
        public static let createdAt = Expression<Double>("created_at")
        // ACK status: -1=error, 0=pending, 1=sent, 2=delivered, 3=read, 4=played
        public static let ackStatus = Expression<Int?>("ack_status")
        public static let ackTimestamp = Expression<Double?>("ack_timestamp")
    }
    
    // MARK: - Create Tables
    
    public static func createTables(db: Connection) throws {
        // vault_files
        try db.run(vaultFiles.create(ifNotExists: true) { t in
            t.column(VaultFilesColumns.id, primaryKey: true)
            t.column(VaultFilesColumns.sinistroRef)
            t.column(VaultFilesColumns.relativePath)
            t.column(VaultFilesColumns.filename)
            t.column(VaultFilesColumns.folder)
            t.column(VaultFilesColumns.size)
            t.column(VaultFilesColumns.mimeType)
            t.column(VaultFilesColumns.checksum)
            t.column(VaultFilesColumns.source)
            t.column(VaultFilesColumns.sourceId)
            t.column(VaultFilesColumns.createdAt)
            t.column(VaultFilesColumns.modifiedAt)
        })
        
        // Indexes for vault_files
        try db.run(vaultFiles.createIndex(VaultFilesColumns.sinistroRef, ifNotExists: true))
        try db.run(vaultFiles.createIndex(VaultFilesColumns.source, VaultFilesColumns.sourceId, ifNotExists: true))
        
        // jobs
        try db.run(jobs.create(ifNotExists: true) { t in
            t.column(JobsColumns.id, primaryKey: true)
            t.column(JobsColumns.type)
            t.column(JobsColumns.status)
            t.column(JobsColumns.priority)
            t.column(JobsColumns.payload)
            t.column(JobsColumns.createdAt)
            t.column(JobsColumns.startedAt)
            t.column(JobsColumns.completedAt)
            t.column(JobsColumns.errorMessage)
            t.column(JobsColumns.retryCount, defaultValue: 0)
        })
        
        // Index for jobs by status and priority
        try db.run(jobs.createIndex(JobsColumns.status, JobsColumns.priority, JobsColumns.createdAt, ifNotExists: true))
        
        // file_manifest
        try db.run(fileManifest.create(ifNotExists: true) { t in
            t.column(FileManifestColumns.legacyPath, primaryKey: true)
            t.column(FileManifestColumns.vaultFileId)
            t.column(FileManifestColumns.lastKnownChecksum)
            t.column(FileManifestColumns.lastKnownSize)
            t.column(FileManifestColumns.lastKnownModified)
            t.column(FileManifestColumns.lastSyncAt)
            t.column(FileManifestColumns.syncDirection)
        })
        
        // sinistro_folders
        try db.run(sinistroFolders.create(ifNotExists: true) { t in
            t.column(SinistroFoldersColumns.sinistroRef, primaryKey: true)
            t.column(SinistroFoldersColumns.status)
            t.column(SinistroFoldersColumns.lastSyncAt)
            t.column(SinistroFoldersColumns.fileCount, defaultValue: 0)
            t.column(SinistroFoldersColumns.totalSize, defaultValue: 0)
            t.column(SinistroFoldersColumns.errorMessage)
        })
        
        // sinistri
        try db.run(sinistri.create(ifNotExists: true) { t in
            // Identificativi
            t.column(SinistriColumns.riferimento, primaryKey: true)
            t.column(SinistriColumns.numeroSinistro)
            t.column(SinistriColumns.numeroPolizza)
            t.column(SinistriColumns.tipoPolizza)
            
            // Stato e date
            t.column(SinistriColumns.stato)
            t.column(SinistriColumns.substate)
            t.column(SinistriColumns.assegnatario)
            t.column(SinistriColumns.dataAssegnazione)
            t.column(SinistriColumns.dataChiusura)
            t.column(SinistriColumns.dataAperturaGestione)
            t.column(SinistriColumns.dataInvioAtto)
            t.column(SinistriColumns.dataRevoca)
            t.column(SinistriColumns.dataRitornoAtto)
            t.column(SinistriColumns.dataComunicazioneEsito)
            t.column(SinistriColumns.dataRicezioneAttoSottoscritto)
            
            // Compagnia e agenzia
            t.column(SinistriColumns.compagnia)
            t.column(SinistriColumns.gruppo)
            t.column(SinistriColumns.area)
            t.column(SinistriColumns.codiceAgenzia)
            t.column(SinistriColumns.agenzia)
            t.column(SinistriColumns.subagenzia)
            t.column(SinistriColumns.emailAgenzia)
            t.column(SinistriColumns.telefonoAgenzia)
            
            // Contraente
            t.column(SinistriColumns.nomeContraente)
            t.column(SinistriColumns.telefonoContraente)
            t.column(SinistriColumns.emailContraente)
            t.column(SinistriColumns.indirizzoContraente)
            
            // Assicurato
            t.column(SinistriColumns.nomeAssicurato)
            t.column(SinistriColumns.telefonoAssicurato)
            t.column(SinistriColumns.telefoniAssicurato)
            t.column(SinistriColumns.emailAssicurato)
            t.column(SinistriColumns.emailAssicuratoArray)
            t.column(SinistriColumns.indirizzoAssicurato)
            t.column(SinistriColumns.codiceFiscaleAssicurato)
            t.column(SinistriColumns.partitaIVAAssicurato)
            
            // Danneggiato
            t.column(SinistriColumns.nomeDanneggiato)
            t.column(SinistriColumns.telefonoDanneggiato)
            t.column(SinistriColumns.emailDanneggiato)
            t.column(SinistriColumns.indirizzoDanneggiato)
            
            // Date sinistro
            t.column(SinistriColumns.dataSinistro)
            t.column(SinistriColumns.dataDenuncia)
            t.column(SinistriColumns.dataIncarico)
            t.column(SinistriColumns.dataSopralluogo)
            
            // Importi
            t.column(SinistriColumns.richiesta)
            t.column(SinistriColumns.liquidato)
            t.column(SinistriColumns.dannoAccertato)
            t.column(SinistriColumns.dannoAccertatoNetto)
            t.column(SinistriColumns.stimaDanno)
            
            // Esito perizia
            t.column(SinistriColumns.definizione)
            t.column(SinistriColumns.definizioneManuale, defaultValue: false)
            t.column(SinistriColumns.concordata, defaultValue: false)
            t.column(SinistriColumns.negativa, defaultValue: false)
            t.column(SinistriColumns.fulminazione)
            
            // Regolarità amministrativa
            t.column(SinistriColumns.regolaritaAmministrativa)
            t.column(SinistriColumns.dataPagamentoPremio)
            t.column(SinistriColumns.regolaritaAmministrativaOverride, defaultValue: false)
            
            // Flags
            t.column(SinistriColumns.sopralluogo, defaultValue: false)
            t.column(SinistriColumns.giustificativi, defaultValue: false)
            t.column(SinistriColumns.iban, defaultValue: false)
            t.column(SinistriColumns.sinistroCollegato, defaultValue: false)
            t.column(SinistriColumns.idSinistroCollegato)
            t.column(SinistriColumns.oltreDieciBeni, defaultValue: false)
            
            // Legacy compatibility
            t.column(SinistriColumns.cliente)
            t.column(SinistriColumns.mandante)
            t.column(SinistriColumns.localita)
            t.column(SinistriColumns.provincia)
            t.column(SinistriColumns.tipoDanno)
            
            // Metadati file e sync
            t.column(SinistriColumns.legacyPath)
            t.column(SinistriColumns.folderStatus)
            t.column(SinistriColumns.cartella)
            t.column(SinistriColumns.lastModifiedAt)
            t.column(SinistriColumns.createdAt)
            t.column(SinistriColumns.syncedToCK, defaultValue: false)
            t.column(SinistriColumns.cloudKitRecordID)
        })
        
        // Indexes for sinistri
        try db.run(sinistri.createIndex(SinistriColumns.stato, ifNotExists: true))
        try db.run(sinistri.createIndex(SinistriColumns.assegnatario, ifNotExists: true))
        try db.run(sinistri.createIndex(SinistriColumns.syncedToCK, ifNotExists: true))
        
        // emails
        try db.run(emails.create(ifNotExists: true) { t in
            t.column(EmailsColumns.messageId, primaryKey: true)
            t.column(EmailsColumns.accountId)
            t.column(EmailsColumns.subject)
            t.column(EmailsColumns.senderEmail)
            t.column(EmailsColumns.senderName)
            t.column(EmailsColumns.recipients)
            t.column(EmailsColumns.date)
            t.column(EmailsColumns.body)
            t.column(EmailsColumns.category)
            t.column(EmailsColumns.direction)
            t.column(EmailsColumns.senderType)
            t.column(EmailsColumns.sinistroRef)
            t.column(EmailsColumns.confidence)
            t.column(EmailsColumns.matchedPatterns)
            t.column(EmailsColumns.isRead, defaultValue: false)
            t.column(EmailsColumns.threadId)
            t.column(EmailsColumns.processedAt)
            t.column(EmailsColumns.syncedToCK, defaultValue: false)
        })
        
        // Indexes for emails
        try db.run(emails.createIndex(EmailsColumns.sinistroRef, ifNotExists: true))
        try db.run(emails.createIndex(EmailsColumns.date, ifNotExists: true))
        try db.run(emails.createIndex(EmailsColumns.category, ifNotExists: true))
        
        // email_accounts (per deduplicazione CC)
        try db.run(emailAccounts.create(ifNotExists: true) { t in
            t.column(EmailAccountsColumns.messageId)
            t.column(EmailAccountsColumns.accountId)
            t.column(EmailAccountsColumns.mailbox)
            t.column(EmailAccountsColumns.isRead, defaultValue: false)
            t.primaryKey(EmailAccountsColumns.messageId, EmailAccountsColumns.accountId)
        })
        
        // attachments
        try db.run(attachments.create(ifNotExists: true) { t in
            t.column(AttachmentsColumns.id, primaryKey: true)
            t.column(AttachmentsColumns.messageId)
            t.column(AttachmentsColumns.sourceType)
            t.column(AttachmentsColumns.filename)
            t.column(AttachmentsColumns.size)
            t.column(AttachmentsColumns.mimeType)
            t.column(AttachmentsColumns.status)
            t.column(AttachmentsColumns.vaultFileId)
            t.column(AttachmentsColumns.sinistroRef)
            t.column(AttachmentsColumns.errorMessage)
            t.column(AttachmentsColumns.createdAt)
            t.column(AttachmentsColumns.processedAt)
        })
        
        // Index for attachments
        try db.run(attachments.createIndex(AttachmentsColumns.messageId, ifNotExists: true))
        try db.run(attachments.createIndex(AttachmentsColumns.status, ifNotExists: true))
        
        // scheduled_emails
        try db.run(scheduledEmails.create(ifNotExists: true) { t in
            t.column(ScheduledEmailsColumns.id, primaryKey: true)
            t.column(ScheduledEmailsColumns.accountId)
            t.column(ScheduledEmailsColumns.toAddresses)
            t.column(ScheduledEmailsColumns.ccAddresses)
            t.column(ScheduledEmailsColumns.subject)
            t.column(ScheduledEmailsColumns.body)
            t.column(ScheduledEmailsColumns.attachmentIds)
            t.column(ScheduledEmailsColumns.scheduledAt)
            t.column(ScheduledEmailsColumns.status)
            t.column(ScheduledEmailsColumns.sentAt)
            t.column(ScheduledEmailsColumns.errorMessage)
            t.column(ScheduledEmailsColumns.createdBy)
            t.column(ScheduledEmailsColumns.createdAt)
        })
        
        // Index for scheduled_emails
        try db.run(scheduledEmails.createIndex(ScheduledEmailsColumns.status, ScheduledEmailsColumns.scheduledAt, ifNotExists: true))
        
        // scheduled_whatsapp
        try db.run(scheduledWhatsApp.create(ifNotExists: true) { t in
            t.column(ScheduledWhatsAppColumns.id, primaryKey: true)
            t.column(ScheduledWhatsAppColumns.accountId)
            t.column(ScheduledWhatsAppColumns.phoneNumber)
            t.column(ScheduledWhatsAppColumns.body)
            t.column(ScheduledWhatsAppColumns.mediaData)
            t.column(ScheduledWhatsAppColumns.mediaType)
            t.column(ScheduledWhatsAppColumns.mediaFilename)
            t.column(ScheduledWhatsAppColumns.scheduledAt)
            t.column(ScheduledWhatsAppColumns.status)
            t.column(ScheduledWhatsAppColumns.sentAt)
            t.column(ScheduledWhatsAppColumns.sentMessageId)
            t.column(ScheduledWhatsAppColumns.errorMessage)
            t.column(ScheduledWhatsAppColumns.sinistroRef)
            t.column(ScheduledWhatsAppColumns.createdBy)
            t.column(ScheduledWhatsAppColumns.createdAt)
        })
        
        // Index for scheduled_whatsapp
        try db.run(scheduledWhatsApp.createIndex(ScheduledWhatsAppColumns.status, ScheduledWhatsAppColumns.scheduledAt, ifNotExists: true))
        
        // archived_email_refs (per sinistri chiusi)
        try db.run(archivedEmailRefs.create(ifNotExists: true) { t in
            t.column(ArchivedEmailRefsColumns.sinistroRef)
            t.column(ArchivedEmailRefsColumns.messageId)
            t.column(ArchivedEmailRefsColumns.date)
            t.column(ArchivedEmailRefsColumns.subject)
            t.primaryKey(ArchivedEmailRefsColumns.sinistroRef, ArchivedEmailRefsColumns.messageId)
        })
        
        // connected_clients (heartbeat tracking)
        try db.run(connectedClients.create(ifNotExists: true) { t in
            t.column(ConnectedClientsColumns.userId, primaryKey: true)
            t.column(ConnectedClientsColumns.lastSeen)
            t.column(ConnectedClientsColumns.clientInfo)
        })
        
        // whatsapp_chats
        try db.run(whatsappChats.create(ifNotExists: true) { t in
            t.column(WhatsAppChatsColumns.id, primaryKey: true)
            t.column(WhatsAppChatsColumns.accountId)
            t.column(WhatsAppChatsColumns.chatId)
            t.column(WhatsAppChatsColumns.name)
            t.column(WhatsAppChatsColumns.phoneNumber)
            t.column(WhatsAppChatsColumns.isGroup, defaultValue: false)
            t.column(WhatsAppChatsColumns.lastMessageBody)
            t.column(WhatsAppChatsColumns.lastMessageAt)
            t.column(WhatsAppChatsColumns.unreadCount, defaultValue: 0)
            t.column(WhatsAppChatsColumns.sinistroRef)
            t.column(WhatsAppChatsColumns.createdAt)
            t.column(WhatsAppChatsColumns.updatedAt)
            t.unique(WhatsAppChatsColumns.accountId, WhatsAppChatsColumns.chatId)
        })
        
        // Indexes for whatsapp_chats
        try db.run(whatsappChats.createIndex(WhatsAppChatsColumns.accountId, ifNotExists: true))
        try db.run(whatsappChats.createIndex(WhatsAppChatsColumns.sinistroRef, ifNotExists: true))
        
        // whatsapp_messages
        try db.run(whatsappMessages.create(ifNotExists: true) { t in
            t.column(WhatsAppMessagesColumns.id, primaryKey: true)
            t.column(WhatsAppMessagesColumns.accountId)
            t.column(WhatsAppMessagesColumns.chatId)
            t.column(WhatsAppMessagesColumns.waMessageId)
            t.column(WhatsAppMessagesColumns.fromNumber)
            t.column(WhatsAppMessagesColumns.toNumber)
            t.column(WhatsAppMessagesColumns.body)
            t.column(WhatsAppMessagesColumns.timestamp)
            t.column(WhatsAppMessagesColumns.direction)
            t.column(WhatsAppMessagesColumns.type, defaultValue: "text")
            t.column(WhatsAppMessagesColumns.mediaType)
            t.column(WhatsAppMessagesColumns.mediaFilename)
            t.column(WhatsAppMessagesColumns.mediaData)
            t.column(WhatsAppMessagesColumns.mediaLocalPath)
            t.column(WhatsAppMessagesColumns.isRead, defaultValue: false)
            t.column(WhatsAppMessagesColumns.sinistroRef)
            t.column(WhatsAppMessagesColumns.createdAt)
            t.column(WhatsAppMessagesColumns.ackStatus)
            t.column(WhatsAppMessagesColumns.ackTimestamp)
        })
        
        // Indexes for whatsapp_messages
        try db.run(whatsappMessages.createIndex(
            WhatsAppMessagesColumns.accountId,
            WhatsAppMessagesColumns.chatId,
            WhatsAppMessagesColumns.timestamp,
            ifNotExists: true
        ))
        try db.run(whatsappMessages.createIndex(WhatsAppMessagesColumns.sinistroRef, ifNotExists: true))
        try db.run(whatsappMessages.createIndex(WhatsAppMessagesColumns.waMessageId, ifNotExists: true))
    }
    
    // MARK: - Migrations
    
    /// Esegue migrazioni per aggiornare database esistenti
    public static func runMigrations(db: Connection) throws {
        // Migration 1: Add ackStatus and ackTimestamp to whatsapp_messages
        let tableInfo = try db.prepare("PRAGMA table_info(whatsapp_messages)")
        var hasAckStatus = false
        var hasAckTimestamp = false
        
        for row in tableInfo {
            if let name = row[1] as? String {
                if name == "ack_status" { hasAckStatus = true }
                if name == "ack_timestamp" { hasAckTimestamp = true }
            }
        }
        
        if !hasAckStatus {
            try db.run("ALTER TABLE whatsapp_messages ADD COLUMN ack_status INTEGER")
        }
        if !hasAckTimestamp {
            try db.run("ALTER TABLE whatsapp_messages ADD COLUMN ack_timestamp REAL")
        }
    }
}
