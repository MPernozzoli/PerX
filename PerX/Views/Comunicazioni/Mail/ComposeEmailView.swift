import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

enum ComposeEmailMode {
    case reply(Email)
    case replyAll(Email)
    case forward(Email)
    case new(to: String? = nil, subject: String? = nil, cc: String? = nil)
}

struct ComposeEmailView: View {
    let mode: ComposeEmailMode
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var windowManager: ComposeEmailWindowManager
    
    @State private var to: [Contact] = []
    @State private var cc: [Contact] = []
    @State private var bcc: [Contact] = []
    @State private var subject: String = ""
    @State private var emailBody: NSAttributedString = NSAttributedString(string: "")
    @State private var htmlBody: String = ""
    @State private var isHTML: Bool = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingAIAssistant = false
    
    @State private var toText: String = ""
    @State private var ccText: String = ""
    @State private var bccText: String = ""
    @StateObject private var attachmentManager = EmailAttachmentManager()
    
    // Scheduling
    @State private var isScheduled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600) // Default: tra 1 ora
    @State private var showSchedulePicker = false
    
    // Smart Scheduling
    @State private var showSmartSchedulePrompt = false
    @State private var smartScheduleReason: SmartScheduleService.ScheduleReason = .afterHours
    @State private var smartScheduleSuggestedDate = Date()
    @StateObject private var smartScheduleService = SmartScheduleService.shared
    
    private let gmailService = GmailService.shared
    private let signatureService = EmailSignatureService.shared
    private let aiService = AppleIntelligenceService.shared
    private let authService = GoogleAuthService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar superiore (stile Mail)
            composeToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Header con destinatari (stile Mail)
            VStack(alignment: .leading, spacing: 0) {
                // From (solo se necessario)
                HStack(alignment: .top, spacing: 8) {
                    Text("Da:")
                        .frame(width: 60, alignment: .leading)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    Text("Massimo Pernozzoli - massimo.pernozzoli@actsrl.it")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Divider()
                
                // To
                HStack(alignment: .top, spacing: 8) {
                    Text("A:")
                        .frame(width: 60, alignment: .leading)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    TextField("Destinatari", text: $toText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: toText) { _, newValue in
                            to = parseContacts(from: newValue)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                if !ccText.isEmpty || !cc.isEmpty {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Text("Cc:")
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        
                        TextField("Copia conoscenza", text: $ccText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onChange(of: ccText) { _, newValue in
                                cc = parseContacts(from: newValue)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                
                if showingBCC {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Text("Ccn:")
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        
                        TextField("Copia conoscenza nascosta", text: $bccText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onChange(of: bccText) { _, newValue in
                                bcc = parseContacts(from: newValue)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                
                Divider()
                
                // Subject
                HStack(alignment: .top, spacing: 8) {
                    Text("Oggetto:")
                        .frame(width: 60, alignment: .leading)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    TextField("Oggetto", text: $subject)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(.textBackgroundColor))
            
            Divider()
            
            // Formatting toolbar
            formattingToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Body editor con rich text
            VStack(spacing: 0) {
                RichTextEditor(attributedText: $emailBody, htmlString: $htmlBody, isHTML: isHTML)
                    .frame(minHeight: 300)
                
                // Attachment drop zone
                AttachmentDropZone(attachmentManager: attachmentManager)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") {
                    windowManager.closeComposeEmail()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                HStack(spacing: 8) {
                    // Menu per scheduling
                    Menu {
                        Button(action: { 
                            isScheduled = false
                            sendEmailNow() // Bypass smart schedule
                        }) {
                            Label("Invia subito", systemImage: "paperplane.fill")
                        }
                        
                        Divider()
                        
                        Button(action: { showSchedulePicker = true }) {
                            Label("Programma invio...", systemImage: "clock")
                        }
                        
                        if isScheduled {
                            Divider()
                            Text("Programmata: \(scheduledDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    
                    // Pulsante principale - usa smart schedule
                    Button(action: {
                        if isScheduled {
                            scheduleEmail()
                        } else {
                            attemptSendEmail() // Valuta smart schedule
                        }
                    }) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: isScheduled ? "clock" : "paperplane")
                                Text(isScheduled ? "Programma" : "Invia")
                            }
                        }
                    }
                    .disabled(isSending || to.isEmpty || subject.isEmpty)
                }
            }
            
            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    windowManager.updateAlwaysOnTop(!windowManager.isAlwaysOnTop)
                }) {
                    Image(systemName: windowManager.isAlwaysOnTop ? "pin.fill" : "pin")
                }
                .help(windowManager.isAlwaysOnTop ? "Disattiva Sempre in Primo Piano" : "Attiva Sempre in Primo Piano")
                
                Button(action: { showingBCC.toggle() }) {
                    Image(systemName: showingBCC ? "eye.slash" : "eye")
                }
                .help("Mostra/Nascondi Ccn")
            }
        }
        .alert("Errore", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Errore sconosciuto")
        }
        .sheet(isPresented: $showingAIAssistant) {
            AIAssistantView(
                subject: subject,
                emailBodyText: emailBody.string,
                onApply: { suggestedText in
                    emailBody = NSAttributedString(string: suggestedText)
                }
            )
        }
        .sheet(isPresented: $showSchedulePicker) {
            SchedulePickerView(
                scheduledDate: $scheduledDate,
                isScheduled: $isScheduled,
                onConfirm: {
                    showSchedulePicker = false
                }
            )
        }
        .sheet(isPresented: $showSmartSchedulePrompt) {
            SmartSchedulePromptView(
                reason: smartScheduleReason,
                suggestedDate: $smartScheduleSuggestedDate,
                contextId: extractSinistroRefFromContext(),
                messageType: "email",
                onSendNow: {
                    sendEmailNow()
                },
                onSchedule: { date in
                    scheduledDate = date
                    scheduleEmail()
                },
                onCancel: {
                    // Non fare nulla - l'utente ha annullato
                }
            )
        }
        .onAppear {
            setupForMode()
        }
        .onDisappear {
            // Cancella eventuali task in corso quando la view viene rimossa
            isSending = false
        }
    }
    
    @State private var showingBCC = false
    
    // MARK: - Toolbars
    
    private var composeToolbar: some View {
        HStack(spacing: 12) {
            // Apple Intelligence
            Button(action: {
                showingAIAssistant = true
            }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
            }
            .help("Apple Intelligence - Migliora il testo")
            
            Divider()
                .frame(height: 16)
            
            // Attachments
            Button(action: {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                if panel.runModal() == .OK {
                    for url in panel.urls {
                        attachmentManager.addAttachment(url)
                    }
                }
            }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 14))
            }
            .help("Allega file")
            
            Spacer()
            
            // Format toggle
            Menu {
                Button(action: { isHTML = true }) {
                    Label("HTML", systemImage: isHTML ? "checkmark" : "")
                }
                Button(action: { isHTML = false }) {
                    Label("Testo semplice", systemImage: !isHTML ? "checkmark" : "")
                }
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 14))
            }
            .help("Formato")
        }
    }
    
    private var formattingToolbar: some View {
        HStack(spacing: 8) {
            // Font
            Menu {
                Button("Helvetica") { }
                Button("Arial") { }
                Button("Times") { }
            } label: {
                Text("Helvetica")
                    .font(.system(size: 11))
            }
            .frame(width: 100)
            
            Menu {
                Button("Regolare") { }
                Button("Bold") { }
                Button("Italic") { }
            } label: {
                Text("Regolare")
                    .font(.system(size: 11))
            }
            .frame(width: 80)
            
            Menu {
                ForEach([10, 12, 14, 16, 18, 24], id: \.self) { size in
                    Button("\(size)") { }
                }
            } label: {
                Text("12")
                    .font(.system(size: 11))
            }
            .frame(width: 50)
            
            Divider()
                .frame(height: 16)
            
            // Text formatting
            Button(action: {}) {
                Image(systemName: "bold")
                    .font(.system(size: 12))
            }
            .help("Grassetto")
            
            Button(action: {}) {
                Image(systemName: "italic")
                    .font(.system(size: 12))
            }
            .help("Corsivo")
            
            Button(action: {}) {
                Image(systemName: "underline")
                    .font(.system(size: 12))
            }
            .help("Sottolineato")
            
            Divider()
                .frame(height: 16)
            
            // Alignment
            Button(action: {}) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12))
            }
            .help("Allinea a sinistra")
            
            Button(action: {}) {
                Image(systemName: "text.aligncenter")
                    .font(.system(size: 12))
            }
            .help("Allinea al centro")
            
            Button(action: {}) {
                Image(systemName: "text.alignright")
                    .font(.system(size: 12))
            }
            .help("Allinea a destra")
            
            Spacer()
        }
    }
    
    // MARK: - Setup
    
    private func setupForMode() {
        switch mode {
        case .reply(let email):
            to = [email.sender]
            toText = formatContacts([email.sender])
            subject = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
            
            if let originalBody = email.body {
                let (mainBody, _) = extractQuote(from: originalBody)
                let signature = signatureService.getActiveSignature()
                let quotedBody = """
                
                
                -----Messaggio originale-----
                Da: \(email.sender.displayName)
                Data: \(formatDate(email.date))
                Oggetto: \(email.subject)
                
                \(mainBody.strippingHTML())
                """
                if !signature.isEmpty {
                    let sigText = signature.strippingHTML()
                    let fullBody = sigText + "\n\n" + quotedBody
                    emailBody = NSAttributedString(string: fullBody)
                } else {
                    emailBody = NSAttributedString(string: quotedBody)
                }
                htmlBody = ""
                isHTML = false
            } else {
                let signature = signatureService.getActiveSignature()
                if !signature.isEmpty {
                    emailBody = NSAttributedString(string: signature.strippingHTML())
                } else {
                    emailBody = NSAttributedString(string: "")
                }
                htmlBody = ""
                isHTML = false
            }
            
        case .replyAll(let email):
            var recipients: [Contact] = [email.sender]
            recipients.append(contentsOf: email.recipients)
            if let cc = email.cc {
                recipients.append(contentsOf: cc)
            }
            
            // Rimuovi il proprio indirizzo email dalla lista
            let currentUserEmail = authService.userEmail?.lowercased()
            if let userEmail = currentUserEmail {
                recipients = recipients.filter { contact in
                    contact.email.lowercased() != userEmail
                }
            }
            
            let uniqueRecipients = Array(Set(recipients))
            to = uniqueRecipients
            toText = formatContacts(uniqueRecipients)
            subject = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
            
            if let originalBody = email.body {
                let (mainBody, _) = extractQuote(from: originalBody)
                let signature = signatureService.getActiveSignature()
                let quotedBody = """
                
                
                -----Messaggio originale-----
                Da: \(email.sender.displayName)
                Data: \(formatDate(email.date))
                Oggetto: \(email.subject)
                
                \(mainBody.strippingHTML())
                """
                if !signature.isEmpty {
                    let sigText = signature.strippingHTML()
                    let fullBody = sigText + "\n\n" + quotedBody
                    emailBody = NSAttributedString(string: fullBody)
                } else {
                    emailBody = NSAttributedString(string: quotedBody)
                }
                htmlBody = ""
                isHTML = false
            } else {
                let signature = signatureService.getActiveSignature()
                if !signature.isEmpty {
                    emailBody = NSAttributedString(string: signature.strippingHTML())
                } else {
                    emailBody = NSAttributedString(string: "")
                }
                htmlBody = ""
                isHTML = false
            }
            
        case .forward(let email):
            to = []
            toText = ""
            subject = email.subject.hasPrefix("Fwd:") ? email.subject : "Fwd: \(email.subject)"
            
            if let originalBody = email.body {
                let (mainBody, _) = extractQuote(from: originalBody)
                let forwardedBody = """
                
                
                -----Messaggio inoltrato-----
                Da: \(email.sender.displayName)
                Data: \(formatDate(email.date))
                Oggetto: \(email.subject)
                
                \(mainBody.strippingHTML())
                """
                emailBody = NSAttributedString(string: forwardedBody)
            }
            
        case .new(let toAddress, let subjectText, let ccAddress):
            if let toAddress = toAddress, !toAddress.isEmpty {
                to = parseContacts(from: toAddress)
                toText = toAddress
            } else {
                to = []
                toText = ""
            }
            if let ccAddress = ccAddress, !ccAddress.isEmpty {
                cc = parseContacts(from: ccAddress)
                ccText = ccAddress
            }
            subject = subjectText ?? ""
            let signature = signatureService.getActiveSignature()
            if !signature.isEmpty {
                // Prova a caricare come HTML, altrimenti come testo semplice
                if let htmlData = signature.data(using: .utf8),
                   let attributed = try? NSAttributedString(
                       data: htmlData,
                       options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                       documentAttributes: nil
                   ) {
                    emailBody = attributed
                    htmlBody = signature
                    isHTML = signature.contains("<")
                } else {
                    emailBody = NSAttributedString(string: signature.strippingHTML())
                    htmlBody = ""
                    isHTML = false
                }
            } else {
                emailBody = NSAttributedString(string: "")
                htmlBody = ""
            }
        }
    }
    
    // MARK: - Send Email
    
    /// Valuta se mostrare prompt smart schedule o inviare direttamente
    private func attemptSendEmail() {
        guard !to.isEmpty, !subject.isEmpty else { return }
        
        // Estrai sinistroRef se presente (dal subject o dalla mode)
        let sinistroRef = extractSinistroRefFromContext()
        
        // Valuta smart scheduling
        let evaluation = smartScheduleService.evaluateSend(
            for: .email,
            sinistroRef: sinistroRef,
            conversationId: nil
        )
        
        switch evaluation {
        case .sendNow:
            // Orario lavorativo o preferenze ignorano - invia subito
            sendEmailNow()
            
        case .shouldPrompt(let suggestedTime, let reason):
            // Mostra prompt
            smartScheduleSuggestedDate = suggestedTime
            smartScheduleReason = reason
            showSmartSchedulePrompt = true
            
        case .autoSchedule(let scheduledFor):
            // Auto-schedule secondo preferenze salvate
            scheduledDate = scheduledFor
            scheduleEmail()
        }
    }
    
    private func extractSinistroRefFromContext() -> String? {
        // Cerca riferimento nel subject
        let pattern = #"\b([0-9]{7})\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)),
           let range = Range(match.range(at: 1), in: subject) {
            return String(subject[range])
        }
        return nil
    }
    
    private func sendEmailNow() {
        guard !to.isEmpty, !subject.isEmpty else { return }
        
        // Cattura i valori necessari prima di iniziare il Task per evitare problemi di memoria
        let recipients = to
        let ccRecipients = cc
        let bccRecipients = bcc
        let emailSubject = subject
        let currentIsHTML = isHTML
        let currentEmailBody = emailBody
        let currentHtmlBody = htmlBody
        let currentAttachments = attachmentManager.attachments
        
        isSending = true
        errorMessage = nil
        
        Task {
            // Verifica che la finestra sia ancora aperta
            let isWindowVisible = await MainActor.run {
                windowManager.isWindowVisible()
            }
            guard isWindowVisible else {
                await MainActor.run {
                    isSending = false
                }
                return
            }
            
            do {
                var replyToThreadId: String? = nil
                var inReplyTo: String? = nil
                var references: String? = nil
                
                // Cattura il mode per evitare problemi di accesso
                let currentMode = mode
                
                // Ottieni riferimenti thread per risposte (usa ancora GmailService per lettura)
                if case .reply(let email) = currentMode {
                    if let threadId = try? await gmailService.getThreadId(for: email.id) {
                        replyToThreadId = threadId
                    }
                    if let originalDetail = try? await gmailService.fetchEmailDetails(messageId: email.id) {
                        if let messageIdHeader = originalDetail.payload.headers.first(where: { $0.name.lowercased() == "message-id" }) {
                            inReplyTo = messageIdHeader.value
                            references = messageIdHeader.value
                        }
                    }
                } else if case .replyAll(let email) = currentMode {
                    if let threadId = try? await gmailService.getThreadId(for: email.id) {
                        replyToThreadId = threadId
                    }
                    if let originalDetail = try? await gmailService.fetchEmailDetails(messageId: email.id) {
                        if let messageIdHeader = originalDetail.payload.headers.first(where: { $0.name.lowercased() == "message-id" }) {
                            inReplyTo = messageIdHeader.value
                            references = messageIdHeader.value
                        }
                    }
                }
                
                // Aggiungi la firma se non è già presente
                let signature = signatureService.getActiveSignature()
                var bodyToSend: String
                
                if currentIsHTML {
                    // Se è HTML, usa htmlBody se disponibile, altrimenti converti da NSAttributedString
                    if !currentHtmlBody.isEmpty {
                        bodyToSend = currentHtmlBody
                    } else {
                        bodyToSend = currentEmailBody.toHTML()
                    }
                    
                    // Aggiungi firma HTML se non presente
                    if !signature.isEmpty && !bodyToSend.contains(signature) && !bodyToSend.contains(signature.strippingHTML()) {
                        let sigHTML = signature.contains("<") ? signature : "<br><br>\(signature.replacingOccurrences(of: "\n", with: "<br>"))"
                        bodyToSend += sigHTML
                    }
                } else {
                    // Testo semplice
                    bodyToSend = currentEmailBody.string
                    
                    // Aggiungi firma testo se non presente
                    if !signature.isEmpty && !bodyToSend.contains(signature) && !bodyToSend.contains(signature.strippingHTML()) {
                        let sigText = signature.strippingHTML()
                        bodyToSend += "\n\n" + sigText
                    }
                }
                
                // Verifica che il body non sia vuoto
                guard !bodyToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(domain: "ComposeEmail", code: -1, userInfo: [NSLocalizedDescriptionKey: "Il corpo dell'email non può essere vuoto"])
                }
                
                // Prepara gli allegati come base64 per l'HUB
                var attachmentsData: [[String: String]]? = nil
                if !currentAttachments.isEmpty {
                    attachmentsData = currentAttachments.compactMap { attachment -> [String: String]? in
                        guard let data = try? Data(contentsOf: attachment.url) else { return nil }
                        
                        // Determina MIME type dall'estensione
                        let mimeType: String
                        if let utType = UTType(filenameExtension: attachment.url.pathExtension),
                           let preferredMIME = utType.preferredMIMEType {
                            mimeType = preferredMIME
                        } else {
                            mimeType = "application/octet-stream"
                        }
                        
                        return [
                            "filename": attachment.filename,
                            "data": data.base64EncodedString(),
                            "mime_type": mimeType
                        ]
                    }
                }
                
                // Ottieni accountId (email utente)
                let accountId = authService.userEmail ?? ""
                
                // Invia via HUB -> Mail Worker
                let response = try await ScheduledEmailService.shared.sendEmail(
                    accountId: accountId,
                    to: recipients.map { $0.email },
                    cc: ccRecipients.isEmpty ? nil : ccRecipients.map { $0.email },
                    bcc: bccRecipients.isEmpty ? nil : bccRecipients.map { $0.email },
                    subject: emailSubject,
                    body: bodyToSend,
                    isHtml: currentIsHTML,
                    replyToThreadId: replyToThreadId,
                    inReplyTo: inReplyTo,
                    references: references,
                    attachments: attachmentsData
                )
                
                // Verifica che la finestra sia ancora aperta prima di aggiornare l'UI
                let isWindowStillVisible = await MainActor.run {
                    windowManager.isWindowVisible()
                }
                guard isWindowStillVisible else {
                    await MainActor.run {
                        isSending = false
                    }
                    return
                }
                
                if response.success {
                    let messageId = response.messageId ?? "unknown"
                    
                    await MainActor.run {
                        isSending = false
                        print("[ComposeEmailView] ✅ Email inviata via HUB con ID: \(messageId)")
                        
                        // Notifica TaskManager se è una risposta
                        if case .reply(let email) = mode {
                            TaskManager.shared.checkEmailReplyCompletion(
                                emailId: messageId,
                                replyToEmailId: email.id
                            )
                        } else if case .replyAll(let email) = mode {
                            TaskManager.shared.checkEmailReplyCompletion(
                                emailId: messageId,
                                replyToEmailId: email.id
                            )
                        }
                        
                        // Verifica se è una mail "atto da firmare" e aggiorna lo stato
                        let lowerSubject = emailSubject.lowercased()
                        if lowerSubject.contains("atto da firmare") || lowerSubject.contains("invio atto") {
                            let cleanBody = currentIsHTML ? bodyToSend.strippingHTML() : bodyToSend
                            handleAttoDaFirmareSent(subject: emailSubject, body: cleanBody)
                        }
                        
                        windowManager.closeComposeEmail()
                    }
                } else {
                    throw NSError(domain: "ComposeEmail", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Errore sconosciuto"])
                }
            } catch {
                // Verifica che la finestra sia ancora aperta prima di mostrare l'errore
                let isWindowStillVisible = await MainActor.run {
                    windowManager.isWindowVisible()
                }
                guard isWindowStillVisible else {
                    await MainActor.run {
                        isSending = false
                    }
                    return
                }
                
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    print("[ComposeEmailView] ❌ Errore invio email: \(error)")
                }
            }
        }
    }
    
    // MARK: - Schedule Email
    
    private func scheduleEmail() {
        guard !to.isEmpty, !subject.isEmpty else { return }
        guard scheduledDate > Date() else {
            errorMessage = "La data di invio programmato deve essere nel futuro"
            showingError = true
            return
        }
        
        isSending = true
        errorMessage = nil
        
        let recipients = to
        let ccRecipients = cc
        let emailSubject = subject
        let currentEmailBody = emailBody
        let currentHtmlBody = htmlBody
        let currentIsHTML = isHTML
        let scheduleFor = scheduledDate
        
        Task {
            do {
                // Prepara il body
                let signature = signatureService.getActiveSignature()
                var bodyToSend: String
                
                if currentIsHTML {
                    bodyToSend = !currentHtmlBody.isEmpty ? currentHtmlBody : currentEmailBody.toHTML()
                    if !signature.isEmpty && !bodyToSend.contains(signature) {
                        let sigHTML = signature.contains("<") ? signature : "<br><br>\(signature.replacingOccurrences(of: "\n", with: "<br>"))"
                        bodyToSend += sigHTML
                    }
                } else {
                    bodyToSend = currentEmailBody.string
                    if !signature.isEmpty && !bodyToSend.contains(signature) {
                        bodyToSend += "\n\n" + signature.strippingHTML()
                    }
                }
                
                // Chiama API Hub per schedulare
                let accountId = authService.userEmail ?? ""
                
                let scheduled = try await ScheduledEmailService.shared.scheduleEmail(
                    accountId: accountId,
                    to: recipients.map { $0.email },
                    cc: ccRecipients.isEmpty ? nil : ccRecipients.map { $0.email },
                    subject: emailSubject,
                    body: bodyToSend,
                    scheduledFor: scheduleFor,
                    sinistroRef: nil
                )
                
                await MainActor.run {
                    isSending = false
                    print("[ComposeEmailView] ✅ Email programmata con ID: \(scheduled.id) per \(scheduleFor)")
                    windowManager.closeComposeEmail()
                }
                
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    print("[ComposeEmailView] ❌ Errore programmazione email: \(error)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func handleAttoDaFirmareSent(subject: String, body: String) {
        // Estrae il riferimento dal subject o dal body
        let riferimento = extractRiferimento(from: subject, body: body)
        
        guard let riferimento = riferimento else {
            print("[ComposeEmailView] ⚠️ Riferimento non trovato per mail 'atto da firmare'")
            return
        }
        
        // Trova il sinistro
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        request.fetchLimit = 1
        
        guard let sinistro = try? viewContext.fetch(request).first else {
            print("[ComposeEmailView] ⚠️ Sinistro non trovato per riferimento: \(riferimento)")
            return
        }
        
        // Aggiorna lo stato con validazione
        Task {
            do {
                try await StatoManager.shared.changeState(
                    for: sinistro,
                    to: .attoInviato,
                    context: viewContext
                )
                print("[ComposeEmailView] ✅ Stato aggiornato a 'Atto inviato' per sinistro \(riferimento)")
            } catch {
                print("[ComposeEmailView] ⚠️ Impossibile aggiornare stato: \(error.localizedDescription)")
            }
        }
    }
    
    private func extractRiferimento(from subject: String, body: String) -> String? {
        let pattern = #"\b([0-9]{7})\b"# // 7 cifre consecutive
        
        // Cerca prima nel subject
        if let riferimento = findPattern(pattern, in: subject) {
            if isValidRiferimento(riferimento) {
                return riferimento
            }
        }
        
        // Se non trovato, cerca nel body
        if let riferimento = findPattern(pattern, in: body) {
            if isValidRiferimento(riferimento) {
                return riferimento
            }
        }
        
        return nil
    }
    
    private func findPattern(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: text.utf16.count)
        if let match = regex.firstMatch(in: text, range: range) {
            let matchRange = match.range(at: 1)
            if matchRange.location != NSNotFound {
                return (text as NSString).substring(with: matchRange)
            }
        }
        
        return nil
    }
    
    private func isValidRiferimento(_ riferimento: String) -> Bool {
        guard riferimento.count == 7, riferimento.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        // Estrae l'anno (prime 2 cifre)
        let annoString = String(riferimento.prefix(2))
        guard let anno = Int(annoString) else { return false }
        
        // Verifica che l'anno sia ragionevole (es. dal 2020 al 2030)
        return anno >= 20 && anno <= 30
    }
    
    private func parseContacts(from text: String) -> [Contact] {
        let components = text.split(separator: ",")
        return components.compactMap { component in
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            
            if let range = trimmed.range(of: "<") {
                let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let emailRange = trimmed.range(of: ">", range: range.upperBound..<trimmed.endIndex)
                if let emailRange = emailRange {
                    let email = String(trimmed[range.upperBound..<emailRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return Contact(name: name.isEmpty ? nil : name, email: email)
                }
            }
            
            if trimmed.contains("@") {
                return Contact(name: nil, email: trimmed)
            }
            
            return nil
        }
    }
    
    private func formatContacts(_ contacts: [Contact]) -> String {
        return contacts.map { contact in
            if let name = contact.name, !name.isEmpty {
                return "\(name) <\(contact.email)>"
            }
            return contact.email
        }.joined(separator: ", ")
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatMediumWithTime(date)
    }
    
    private func extractQuote(from body: String) -> (main: String, quote: String) {
        let quotePatterns = [
            ("-----Messaggio originale-----", false),
            ("<div class=\"gmail_quote\">", true),
            ("<blockquote", true),
            ("From:", false),
            ("Da:", false)
        ]
        
        var mainBody = body
        var quote = ""
        
        for (pattern, isHTML) in quotePatterns {
            if let range = body.range(of: pattern, options: .caseInsensitive) {
                let mainPart = String(body[..<range.lowerBound])
                let quotePart = String(body[range.lowerBound...])
                
                if !mainPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    mainBody = mainPart.trimmingCharacters(in: .whitespacesAndNewlines)
                    quote = quotePart
                    break
                }
            }
        }
        
        return (mainBody, quote)
    }
}

// MARK: - AI Assistant View

struct AIAssistantView: View {
    let subject: String
    let emailBodyText: String
    let onApply: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var suggestedText: String = ""
    @State private var isGenerating = false
    
    private let aiService = AppleIntelligenceService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Apple Intelligence")
                .font(.headline)
            
            if isGenerating {
                ProgressView()
                Text("Generazione in corso...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                TextEditor(text: $suggestedText)
                    .frame(height: 300)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Applica") {
                    onApply(suggestedText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(suggestedText.isEmpty)
            }
        }
        .padding()
        .frame(width: 600, height: 450)
        .onAppear {
            generateSuggestion()
        }
    }
    
    private func generateSuggestion() {
        isGenerating = true
        Task {
            if let suggestion = await aiService.improveEmailText(subject: subject, body: emailBodyText) {
                await MainActor.run {
                    suggestedText = suggestion
                    isGenerating = false
                }
            } else {
                await MainActor.run {
                    suggestedText = emailBodyText
                    isGenerating = false
                }
            }
        }
    }
}
