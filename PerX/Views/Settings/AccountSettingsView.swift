import SwiftUI
import AppKit

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var profileService = UserProfileService.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Sezione Profilo
                ProfileSectionView()
                
                // Sezione Email
                EmailSettingsSectionView()
            }
            .padding()
        }
        .task {
            await profileService.refreshCurrentProfile()
        }
    }
}

// MARK: - Profile Section

private struct ProfileSectionView: View {
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var appState = AppState.shared
    
    @State private var isEditingProfile = false
    @State private var showAvatarPicker = false
    
    var body: some View {
        GroupBox {
            VStack(spacing: 20) {
                // Header con avatar e info base
                HStack(spacing: 16) {
                    // Avatar
                    AvatarView(profile: profileService.currentProfile, size: 80)
                        .onTapGesture { showAvatarPicker = true }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, .blue)
                                .offset(x: 4, y: 4)
                        }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if let profile = profileService.currentProfile {
                            Text(profile.displayName)
                                .font(.title2.bold())
                            
                            Text(profile.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Badge ruoli
                            if !profile.roles.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(profile.roles) { role in
                                        RoleBadge(role: role)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        } else {
                            Text("Nessun profilo")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Stato connessione
                    VStack(alignment: .trailing, spacing: 8) {
                        if appState.googleAuthService.isAuthenticated {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Connesso")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Disconnetti") {
                                appState.googleAuthService.signOut()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                        } else {
                            Button {
                                appState.googleAuthService.signIn()
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.key")
                                    Text("Accedi")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                Divider()
                
                // Form dati profilo
                if let profile = profileService.currentProfile {
                    ProfileFormView(profile: profile)
                }
            }
            .padding()
        } label: {
            Label("Profilo Utente", systemImage: "person.crop.circle")
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerView()
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}

// MARK: - Profile Form

private struct ProfileFormView: View {
    let profile: UserProfile
    @StateObject private var profileService = UserProfileService.shared
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var birthDate: Date = Date()
    @State private var hasBirthDate = false
    @State private var birthdayVisibility: BirthdayVisibility = .everyone
    @State private var notifyBirthday = true
    @State private var contractType: ContractType? = nil
    @State private var selectedRoles: Set<UserRole> = []
    @State private var enableBadges = false
    @State private var sendReadReceipts = true
    
    @State private var hasChanges = false
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Nome e Cognome
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Nome", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cognome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Cognome", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // Username (non modificabile)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("Username", text: .constant(profile.username))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
                    .frame(maxWidth: .infinity)
            }
            
            Divider()
            
            // Data di nascita
            HStack(spacing: 16) {
                Toggle("Data di nascita", isOn: $hasBirthDate)
                    .toggleStyle(.checkbox)
                
                if hasBirthDate {
                    DatePicker("", selection: $birthDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                    
                    Picker("Visibilità", selection: $birthdayVisibility) {
                        ForEach(BirthdayVisibility.allCases) { visibility in
                            Text(visibility.displayName).tag(visibility)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                
                Spacer()
            }
            
            if hasBirthDate {
                Toggle("Notifica il mio compleanno ai colleghi", isOn: $notifyBirthday)
                    .toggleStyle(.checkbox)
            }
            
            Divider()
            
            // Tipo contratto
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tipo Contratto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $contractType) {
                        Text("Non specificato").tag(nil as ContractType?)
                        ForEach(ContractType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type as ContractType?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                Spacer()
            }
            
            // Ruoli
            VStack(alignment: .leading, spacing: 8) {
                Text("Ruoli")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 8)
                ], spacing: 8) {
                    ForEach(profile.availableRoles) { role in
                        RoleToggle(role: role, isSelected: selectedRoles.contains(role)) {
                            if selectedRoles.contains(role) {
                                selectedRoles.remove(role)
                            } else {
                                selectedRoles.insert(role)
                            }
                            hasChanges = true
                        }
                    }
                }
            }
            
            Divider()
            
            // Preferenze
            VStack(alignment: .leading, spacing: 12) {
                Text("Preferenze")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Partecipa alla raccolta badge", isOn: $enableBadges)
                    .toggleStyle(.checkbox)
                    .help("TODO: Implementazione in arrivo")
                
                Toggle("Invia notifiche di lettura messaggi", isOn: $sendReadReceipts)
                    .toggleStyle(.checkbox)
            }
            
            // Pulsante salva
            if hasChanges {
                HStack {
                    Spacer()
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Salva Modifiche")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
                .padding(.top, 8)
            }
        }
        .onAppear { loadFromProfile() }
        .onChange(of: firstName) { _, _ in hasChanges = true }
        .onChange(of: lastName) { _, _ in hasChanges = true }
        .onChange(of: birthDate) { _, _ in hasChanges = true }
        .onChange(of: hasBirthDate) { _, _ in hasChanges = true }
        .onChange(of: birthdayVisibility) { _, _ in hasChanges = true }
        .onChange(of: notifyBirthday) { _, _ in hasChanges = true }
        .onChange(of: contractType) { _, _ in hasChanges = true }
        .onChange(of: enableBadges) { _, _ in hasChanges = true }
        .onChange(of: sendReadReceipts) { _, _ in hasChanges = true }
    }
    
    private func loadFromProfile() {
        firstName = profile.firstName
        lastName = profile.lastName
        if let date = profile.birthDate {
            birthDate = date
            hasBirthDate = true
        }
        birthdayVisibility = profile.birthdayVisibility
        notifyBirthday = profile.notifyBirthday
        contractType = profile.contractType
        selectedRoles = Set(profile.roles)
        enableBadges = profile.enableBadges
        sendReadReceipts = profile.sendReadReceipts
        hasChanges = false
    }
    
    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await profileService.updateProfile { profile in
                profile.firstName = firstName
                profile.lastName = lastName
                profile.birthDate = hasBirthDate ? birthDate : nil
                profile.birthdayVisibility = birthdayVisibility
                profile.notifyBirthday = notifyBirthday
                profile.contractType = contractType
                profile.roles = Array(selectedRoles)
                profile.enableBadges = enableBadges
                profile.sendReadReceipts = sendReadReceipts
            }
            hasChanges = false
        } catch {
            print("[ProfileForm] ❌ Errore salvataggio: \(error)")
        }
    }
}

// AvatarView è ora in Views/Components/AvatarView.swift

// MARK: - Avatar Picker

private struct AvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileService = UserProfileService.shared
    
    @State private var selectedTab = 0
    @State private var selectedColor = GeneratedAvatar.availableColors[0]
    @State private var selectedIcon = GeneratedAvatar.availableIcons[0]
    @State private var selectedImage: NSImage?
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Scegli Avatar")
                    .font(.headline)
                Spacer()
                Button("Annulla") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Preview
            HStack {
                Spacer()
                previewAvatar
                    .frame(width: 120, height: 120)
                Spacer()
            }
            .padding(.vertical, 20)
            
            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Genera Avatar").tag(0)
                Text("Carica Foto").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Divider()
                .padding(.top)
            
            // Content
            ScrollView {
                switch selectedTab {
                case 0:
                    generatedAvatarPicker
                case 1:
                    photoPicker
                default:
                    EmptyView()
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button {
                    Task { await saveAvatar() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Salva")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var previewAvatar: some View {
        if selectedTab == 1, let image = selectedImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(hex: selectedColor))
                .overlay {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                }
        }
    }
    
    private var generatedAvatarPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Colori
            VStack(alignment: .leading, spacing: 8) {
                Text("Colore di sfondo")
                    .font(.subheadline.bold())
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 8), spacing: 8) {
                    ForEach(GeneratedAvatar.availableColors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if color == selectedColor {
                                    Circle()
                                        .stroke(.white, lineWidth: 3)
                                }
                            }
                            .shadow(color: color == selectedColor ? .black.opacity(0.3) : .clear, radius: 4)
                            .onTapGesture { selectedColor = color }
                    }
                }
            }
            
            Divider()
            
            // Icone
            VStack(alignment: .leading, spacing: 8) {
                Text("Icona")
                    .font(.subheadline.bold())
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 8), spacing: 8) {
                    ForEach(GeneratedAvatar.availableIcons, id: \.self) { icon in
                        Circle()
                            .fill(selectedIcon == icon ? Color.accentColor : Color.gray.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: icon)
                                    .foregroundColor(selectedIcon == icon ? .white : .primary)
                            }
                            .onTapGesture { selectedIcon = icon }
                    }
                }
            }
        }
        .padding()
    }
    
    private var photoPicker: some View {
        VStack(spacing: 16) {
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                
                Button("Rimuovi") {
                    selectedImage = nil
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("Trascina un'immagine o clicca per selezionare")
                    .foregroundColor(.secondary)
            }
            
            Button("Seleziona Immagine...") {
                selectImage()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding()
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleImageDrop(providers)
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url,
           let image = NSImage(contentsOf: url) {
            selectedImage = image
        }
    }
    
    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSImage.self) { image, _ in
            if let image = image as? NSImage {
                DispatchQueue.main.async {
                    self.selectedImage = image
                }
            }
        }
        return true
    }
    
    private func saveAvatar() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            if selectedTab == 1, let image = selectedImage {
                try await profileService.setAvatarPhoto(image)
            } else {
                try await profileService.setGeneratedAvatar(
                    backgroundColor: selectedColor,
                    icon: selectedIcon
                )
            }
            dismiss()
        } catch {
            print("[AvatarPicker] ❌ Errore: \(error)")
        }
    }
}

// MARK: - Role Badge

private struct RoleBadge: View {
    let role: UserRole
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: role.icon)
                .font(.caption2)
            Text(role.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(roleColor.opacity(0.15))
        .foregroundColor(roleColor)
        .cornerRadius(12)
    }
    
    private var roleColor: Color {
        switch role {
        case .admin: return .red
        case .director: return .purple
        case .teamLeader: return .blue
        case .expert: return .green
        case .secretary: return .orange
        }
    }
}

// MARK: - Role Toggle

private struct RoleToggle: View {
    let role: UserRole
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: role.icon)
                Text(role.displayName)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Email Settings Section

private struct EmailSettingsSectionView: View {
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                // Firma Email
                InlineSignatureEditor()
                
                Divider()
                
                // Notifiche di lettura
                ReadReceiptSettingsView()
                
                Divider()
                
                // Auto-marcatura
                AutoReadSettingsView()
            }
            .padding()
        } label: {
            Label("Impostazioni Email", systemImage: "envelope")
        }
    }
}

// MARK: - Read Receipt Settings

private struct ReadReceiptSettingsView: View {
    @State private var isEnabled = ReadReceiptSettings.shared.isEnabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Notifiche di lettura email", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    ReadReceiptSettings.shared.isEnabled = newValue
                }
            
            if isEnabled {
                Text("Ricevi notifiche quando le email inviate vengono lette dal destinatario.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Auto Read Settings

private struct AutoReadSettingsView: View {
    @State private var isEnabled = EmailAutoReadSettings.shared.isEnabled
    @State private var showAllCategories = false
    
    private let mainCategories: [EmailCategory] = [
        .assignment,
        .revocation,
        .revisionRequested,
        .actReceived,
        .documentationReceived,
        .reminderReceived,
        .clarificationRequest
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Marca come letta quando processata", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    EmailAutoReadSettings.shared.isEnabled = newValue
                }
            
            if isEnabled {
                Text("Le email processate con successo verranno automaticamente marcate come lette:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 4) {
                    ForEach(mainCategories, id: \.self) { category in
                        Toggle(category.displayName, isOn: Binding(
                            get: { EmailAutoReadSettings.shared.isCategoryEnabled(category) },
                            set: { newValue in EmailAutoReadSettings.shared.setCategory(category, enabled: newValue) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                
                DisclosureGroup("Altre categorie", isExpanded: $showAllCategories) {
                    let otherCategories = EmailCategory.allCases.filter { !mainCategories.contains($0) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 4) {
                        ForEach(otherCategories, id: \.self) { category in
                            Toggle(category.displayName, isOn: Binding(
                                get: { EmailAutoReadSettings.shared.isCategoryEnabled(category) },
                                set: { newValue in EmailAutoReadSettings.shared.setCategory(category, enabled: newValue) }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Inline Signature Editor

struct InlineSignatureEditor: View {
    @State private var isExpanded: Bool = false
    @State private var signature: NSAttributedString = NSAttributedString(string: "")
    @State private var htmlSignature: String = ""
    @State private var isHTML: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    
    private let signatureService = EmailSignatureService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Firma Email")
                        .font(.subheadline.bold())
                    Text("Aggiunta automaticamente alle email.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        isExpanded.toggle()
                        if isExpanded { loadSignature() }
                    }
                } label: {
                    Text(isExpanded ? "Nascondi" : "Modifica")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if !isExpanded {
                if EmailSignatureService.shared.hasSignature() {
                    HTMLPreviewView(htmlString: EmailSignatureService.shared.getSignature())
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                } else {
                    Text("Nessuna firma impostata")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(8)
                }
            }
            
            if isExpanded {
                VStack(spacing: 0) {
                    // Toolbar
                    HStack(spacing: 8) {
                        Text("Editor Firma")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Toggle("HTML", isOn: $isHTML)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    
                    RichTextEditor(attributedText: $signature, htmlString: $htmlSignature, isHTML: isHTML)
                        .frame(minHeight: 150)
                        .onChange(of: signature) { _, _ in hasUnsavedChanges = true }
                        .onChange(of: htmlSignature) { _, _ in hasUnsavedChanges = true }
                    
                    HStack {
                        Button("Ripristina Default") {
                            let defaultSig = signatureService.getDefaultSignature()
                            signature = NSAttributedString(string: defaultSig)
                            hasUnsavedChanges = true
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Annulla") {
                            withAnimation {
                                isExpanded = false
                                hasUnsavedChanges = false
                                loadSignature()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Salva") {
                            saveSignature()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!hasUnsavedChanges)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    private func saveSignature() {
        let sigToSave: String
        if isHTML {
            if !htmlSignature.isEmpty {
                sigToSave = htmlSignature
            } else {
                sigToSave = signature.toHTML()
            }
        } else {
            sigToSave = signature.string
        }
        
        if !sigToSave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            signatureService.saveSignature(sigToSave)
            hasUnsavedChanges = false
            withAnimation { isExpanded = false }
        }
    }
    
    private func loadSignature() {
        let savedSig = signatureService.getSignature()
        if !savedSig.isEmpty {
            if let htmlData = savedSig.data(using: .utf8),
               let attributed = try? NSAttributedString(
                   data: htmlData,
                   options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                signature = attributed
                htmlSignature = savedSig
                isHTML = true
            } else {
                signature = NSAttributedString(string: savedSig)
                htmlSignature = savedSig
                isHTML = false
            }
        } else {
            let defaultSig = signatureService.getDefaultSignature()
            if !defaultSig.isEmpty {
                if let htmlData = defaultSig.data(using: .utf8),
                   let attributed = try? NSAttributedString(
                       data: htmlData,
                       options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                       documentAttributes: nil
                   ) {
                    signature = attributed
                    htmlSignature = defaultSig
                    isHTML = true
                } else {
                    signature = NSAttributedString(string: defaultSig)
                    htmlSignature = defaultSig
                    isHTML = false
                }
            }
        }
        hasUnsavedChanges = false
    }
}

// MARK: - HTML Preview View

struct HTMLPreviewView: NSViewRepresentable {
    let htmlString: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .controlBackgroundColor
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if !htmlString.isEmpty {
            if let htmlData = htmlString.data(using: .utf8),
               let attributed = try? NSAttributedString(
                   data: htmlData,
                   options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil
               ) {
                textView.textStorage?.setAttributedString(attributed)
            } else {
                textView.string = htmlString.strippingHTML()
            }
        } else {
            textView.string = ""
        }
    }
}

// Color extension per hex è ora in Views/Components/AvatarView.swift
