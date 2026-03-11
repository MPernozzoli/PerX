import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Sezione Polizza e Attori (Contraente, Assicurato, Danneggiato)
struct PolizzaAttoriSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var isEditing = false
    
    // Cache per verifica numeri WhatsApp
    @ObservedObject private var waNumberCache = WhatsAppNumberCacheService.shared
    
    // Snapshot per annullare modifiche
    @State private var snapshotNumeroPolizza: String = ""
    @State private var snapshotTipoPolizza: String = ""
    @State private var snapshotCodiceFiscale: String = ""
    @State private var snapshotPartitaIVA: String = ""
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header con pulsante modifica
                HStack {
                    Text("Polizza e Attori")
                        .font(.headline)
                    Spacer()
                    
                    if isEditing {
                        HStack(spacing: 8) {
                            Button("Annulla") {
                                restoreSnapshot()
                                isEditing = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            
                            Button("Salva") {
                                saveChanges()
                                isEditing = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    } else {
                        Button {
                            takeSnapshot()
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Modifica")
                    }
                }
                
                HStack(alignment: .top, spacing: 24) {
                    // Colonna sinistra: Attori
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attori")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            attoreRow(
                                title: "Contraente/Assicurato",
                                nome: sinistro.nomeContraente ?? sinistro.nomeAssicurato,
                                indirizzo: sinistro.indirizzoContraente ?? sinistro.indirizzoAssicurato,
                                telefoni: sinistro.telefoniAssicuratoArray.isEmpty ? (sinistro.telefonoContraente ?? sinistro.telefonoAssicurato).map { [$0] } ?? [] : sinistro.telefoniAssicuratoArray,
                                email: sinistro.emailAssicuratoArray.isEmpty ? (sinistro.emailContraente ?? sinistro.emailAssicurato).map { [$0] } ?? [] : sinistro.emailAssicuratoArray
                            )
                            
                            Divider()
                            
                            attoreRow(
                                title: "Danneggiato",
                                nome: sinistro.nomeDanneggiato,
                                indirizzo: sinistro.indirizzoDanneggiato,
                                telefoni: sinistro.telefonoDanneggiato.map { [$0] } ?? [],
                                email: sinistro.emailDanneggiato.map { [$0] } ?? []
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                        .frame(maxHeight: .infinity)
                    
                    // Colonna destra: Polizza
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Polizza")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            polizzaField(
                                label: "Numero polizza",
                                value: sinistro.numeroPolizza,
                                fieldName: "Numero polizza"
                            )
                            
                            Divider()
                            
                            polizzaField(
                                label: "Tipo polizza",
                                value: sinistro.tipoPolizza,
                                fieldName: "Tipo polizza"
                            )
                            
                            // Nuovi campi CF e P.IVA (visibili solo in edit o se valorizzati)
                            if isEditing || (sinistro.codiceFiscaleAssicurato?.isEmpty == false) || (sinistro.partitaIVAAssicurato?.isEmpty == false) {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Codice Fiscale")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if isEditing {
                                        TextField("Codice Fiscale", text: Binding(
                                            get: { sinistro.codiceFiscaleAssicurato ?? "" },
                                            set: { sinistro.codiceFiscaleAssicurato = $0.isEmpty ? nil : $0.uppercased() }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 200)
                                    } else {
                                        DefaultableText(value: sinistro.codiceFiscaleAssicurato, fieldName: "CF")
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Partita IVA")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if isEditing {
                                        TextField("Partita IVA", text: Binding(
                                            get: { sinistro.partitaIVAAssicurato ?? "" },
                                            set: { sinistro.partitaIVAAssicurato = $0.isEmpty ? nil : $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 200)
                                    } else {
                                        DefaultableText(value: sinistro.partitaIVAAssicurato, fieldName: "P.IVA")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
    
    // MARK: - Attore Row
    
    private func attoreRow(title: String, nome: String?, indirizzo: String?, telefoni: [String], email: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let nome = nome, !nome.isEmpty {
                Text(nome)
                    .font(.body)
            } else {
                Text("\(title) mancante")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            if let indirizzo = indirizzo, !indirizzo.isEmpty {
                Text("📍 \(indirizzo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !telefoni.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(telefoni, id: \.self) { telefono in
                        clickablePhoneNumber(telefono)
                    }
                }
            }
            
            if !email.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(email, id: \.self) { emailAddr in
                        clickableEmail(emailAddr)
                    }
                }
            }
        }
    }
    
    // MARK: - Polizza Field
    
    private func polizzaField(label: String, value: String?, fieldName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            DefaultableText(value: value, fieldName: fieldName)
        }
    }
    
    // MARK: - Clickable Elements
    
    private func clickablePhoneNumber(_ telefono: String) -> some View {
        let waStatus = waNumberCache.status(for: telefono)
        let isWaAvailable = waStatus == .registered || waStatus == .unknown || waStatus == .error
        let isChecking = waStatus == .checking
        
        return HStack(spacing: 8) {
            Text("📞 \(telefono)")
                .font(.caption)
                .foregroundColor(.primary)
            
            // Tasto Chiama
            Button {
                openWebexCall(phoneNumber: telefono)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .help("Chiama")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // Tasto WhatsApp
            if isChecking {
                ProgressView()
                    .controlSize(.mini)
                    .help("Verifica WhatsApp in corso...")
            } else {
                Button {
                    openWhatsAppChat(phoneNumber: telefono)
                } label: {
                    Image(systemName: "message.fill")
                        .font(.caption)
                        .foregroundColor(isWaAvailable ? .green : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!isWaAvailable)
                .help(waStatus == .notRegistered ? "Numero non su WhatsApp" : "Scrivi su WhatsApp")
                .onHover { hovering in
                    if hovering && isWaAvailable { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .contextMenu {
            Button {
                openWebexCall(phoneNumber: telefono)
            } label: {
                Label("Chiama", systemImage: "phone.fill")
            }
            
            if isWaAvailable {
                Button {
                    openWhatsAppChat(phoneNumber: telefono)
                } label: {
                    Label("Scrivi su WhatsApp", systemImage: "message.fill")
                }
            } else if waStatus == .notRegistered {
                Text("Numero non su WhatsApp")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Button {
                copyToClipboard(telefono)
            } label: {
                Label("Copia", systemImage: "doc.on.doc")
            }
        }
    }
    
    private func clickableEmail(_ email: String) -> some View {
        Text("✉️ \(email)")
            .font(.caption)
            .foregroundColor(.blue)
            .underline()
            .onTapGesture {
                openEmailComposer(to: email)
            }
            .contextMenu {
                Button {
                    openEmailComposer(to: email)
                } label: {
                    Label("Scrivi email", systemImage: "envelope")
                }
                
                Button {
                    openMailApp(to: email)
                } label: {
                    Label("Scrivi con app Mail", systemImage: "mail")
                }
                
                Divider()
                
                Button {
                    copyToClipboard(email)
                } label: {
                    Label("Copia", systemImage: "doc.on.doc")
                }
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    // MARK: - Actions
    
    private func openWebexCall(phoneNumber: String) {
        let cleanNumber = phoneNumber.replacingOccurrences(of: "[^+0-9]", with: "", options: .regularExpression)
        guard let url = URL(string: "webex://call?number=\(cleanNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanNumber)") else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func openWhatsAppChat(phoneNumber: String) {
        // Pulisci il numero di telefono
        let cleanNumber = phoneNumber.replacingOccurrences(of: "[^+0-9]", with: "", options: .regularExpression)
        
        // Prepara il messaggio pre-compilato
        let riferimento = sinistro.riferimento ?? "N/A"
        let compagnia = sinistro.nomeCompagnia ?? "la Compagnia"
        let dataSinistro: String = {
            if let data = sinistro.dataSinistro {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                formatter.locale = Locale(identifier: "it_IT")
                return formatter.string(from: data)
            }
            return "data non specificata"
        }()
        
        let messaggioPrecompilato = """
Riferimento: \(riferimento)

Buongiorno sono il perito incaricato da \(compagnia) per il suo sinistro da Fenomeno Elettrico del \(dataSinistro)

"""
        
        // Apri finestra WhatsApp con il numero e messaggio pre-compilato
        let chatView = WhatsAppNewChatView(
            phoneNumber: cleanNumber,
            prefilledMessage: messaggioPrecompilato,
            sinistroRiferimento: riferimento,
            sinistro: sinistro
        )
        
        // Costruisci titolo: WhatsApp - [riferimento] - [nome assicurato] - [tipo interlocutore]
        let nomeAssicurato = sinistro.nomeAssicurato ?? ""
        let windowTitle: String
        if !nomeAssicurato.isEmpty {
            windowTitle = "WhatsApp - \(riferimento) - \(nomeAssicurato) - Assicurato"
        } else {
            windowTitle = "WhatsApp - \(riferimento) - Assicurato"
        }
        
        let windowId = "whatsapp-chat-\(cleanNumber)"
        WindowManager.shared.openWindow(
            identifier: windowId,
            content: chatView,
            configuration: WindowConfiguration(
                identifier: windowId,
                title: windowTitle,
                minSize: CGSize(width: 450, height: 550),
                defaultSize: CGSize(width: 500, height: 700)
            )
        )
    }
    
    /// Recupera l'email dell'agenzia da rubrica (priorità) o dal sinistro
    private var emailAgenziaPerCC: String? {
        // Prima cerca in rubrica
        if let codice = sinistro.codiceAgenzia, !codice.isEmpty {
            if let agenzia = CloudKitRubricaSyncService.shared.agenzie.first(where: { $0.matches(codice: codice) }) {
                if let email = agenzia.emailPrincipale, !email.isEmpty {
                    return email
                }
            }
        }
        // Fallback: email dal sinistro
        if let email = sinistro.emailAgenzia, !email.isEmpty {
            return email
        }
        return nil
    }
    
    private func openEmailComposer(to email: String) {
        let numeroSinistro = sinistro.numeroSinistroCompagnia ?? "N/A"
        let nome = sinistro.nomeContraente ?? sinistro.nomeAssicurato ?? "Assicurato"
        let riferimento = sinistro.riferimento ?? ""
        let oggetto = "Sinistro n.\(numeroSinistro) - Assicurato: \(nome) - ns. rif. \(riferimento)"
        
        // Se il destinatario è l'assicurato, aggiunge l'agenzia in CC
        let ccAgenzia = emailAgenziaPerCC
        // Evita di mettere in CC se l'email è la stessa del destinatario
        let cc = (ccAgenzia != nil && ccAgenzia!.lowercased() != email.lowercased()) ? ccAgenzia : nil
        
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .new(to: email, subject: oggetto, cc: cc))
    }
    
    private func openMailApp(to email: String) {
        let numeroSinistro = sinistro.numeroSinistroCompagnia ?? "N/A"
        let nome = sinistro.nomeContraente ?? sinistro.nomeAssicurato ?? "Assicurato"
        let riferimento = sinistro.riferimento ?? ""
        let oggetto = "Sinistro n.\(numeroSinistro) - Assicurato: \(nome) - ns. rif. \(riferimento)"
        let signature = EmailSignatureService.shared.getActiveSignature()
        let corpo = signature.isEmpty ? "" : "\n\n\(signature)"
        
        // Se il destinatario è l'assicurato, aggiunge l'agenzia in CC
        let ccAgenzia = emailAgenziaPerCC
        let ccParam = (ccAgenzia != nil && ccAgenzia!.lowercased() != email.lowercased()) ? ccAgenzia : nil
        
        var mailtoComponents = URLComponents(string: "mailto:\(email)")
        var queryItems = [
            URLQueryItem(name: "subject", value: oggetto),
            URLQueryItem(name: "body", value: corpo)
        ]
        if let cc = ccParam {
            queryItems.append(URLQueryItem(name: "cc", value: cc))
        }
        mailtoComponents?.queryItems = queryItems
        
        guard let mailtoURL = mailtoComponents?.url else { return }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.open(
            [mailtoURL],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Mail.app"),
            configuration: configuration
        ) { _, error in
            if error != nil {
                NSWorkspace.shared.open(mailtoURL)
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Snapshot Management
    
    private func takeSnapshot() {
        snapshotNumeroPolizza = sinistro.numeroPolizza ?? ""
        snapshotTipoPolizza = sinistro.tipoPolizza ?? ""
        snapshotCodiceFiscale = sinistro.codiceFiscaleAssicurato ?? ""
        snapshotPartitaIVA = sinistro.partitaIVAAssicurato ?? ""
    }
    
    private func restoreSnapshot() {
        sinistro.numeroPolizza = snapshotNumeroPolizza.isEmpty ? nil : snapshotNumeroPolizza
        sinistro.tipoPolizza = snapshotTipoPolizza.isEmpty ? nil : snapshotTipoPolizza
        sinistro.codiceFiscaleAssicurato = snapshotCodiceFiscale.isEmpty ? nil : snapshotCodiceFiscale
        sinistro.partitaIVAAssicurato = snapshotPartitaIVA.isEmpty ? nil : snapshotPartitaIVA
    }
    
    private func saveChanges() {
        sinistro.markAsLocallyModified()
        try? viewContext.save()
    }
}
