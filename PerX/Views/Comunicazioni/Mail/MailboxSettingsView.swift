import SwiftUI

struct MailboxSettingsView: View {
    @ObservedObject var viewModel: MailViewModel
    
    var body: some View {
        Form {
            Section(header: Text("Personalizzazione Caselle").font(.title3).padding(.bottom, 8)) {
                List {
                    // La casella "Principale" non è personalizzabile in questa versione
                    ForEach(viewModel.displayableMailboxes.filter { $0.id != "PRINCIPALE" }) { mailbox in
                        MailboxSettingsRow(
                            mailbox: mailbox,
                            onUpdate: { isVisible, iconName, showUnreadCount in
                                viewModel.updateCustomization(
                                    for: mailbox.id,
                                    isVisible: isVisible,
                                    iconName: iconName,
                                    showUnreadCount: showUnreadCount
                                )
                            }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }
}

struct MailboxSettingsRow: View {
    @State var mailbox: DisplayableMailbox
    let onUpdate: (Bool, String, Bool) -> Void
    
    // Lista di icone predefinite per il picker, ora arricchita e ordinata
    private let availableIcons = [
        "alarm.fill",
        "archivebox.fill",
        "arrow.right.doc.on.clipboard",
        "briefcase.fill",
        "building.2.fill",
        "checkmark.seal.fill",
        "doc.fill",
        "doc.on.doc.fill",
        "doc.text.fill",
        "exclamationmark.bubble.fill",
        "flag.fill",
        "folder.fill",
        "gavel.fill",
        "paperclip",
        "paperplane.fill",
        "person.2.fill",
        "person.badge.plus.fill",
        "star.fill",
        "tag.fill",
        "trash.fill",
        "tray.fill"
    ].sorted()
    
    init(mailbox: DisplayableMailbox, onUpdate: @escaping (Bool, String, Bool) -> Void) {
        self._mailbox = State(initialValue: mailbox)
        self.onUpdate = onUpdate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mailbox.name)
                .font(.headline)
            
            VStack(spacing: 12) {
                Toggle("Mostra in elenco", isOn: $mailbox.isVisible)
                    .onChange(of: mailbox.isVisible) { oldValue, newValue in
                        // Se si nasconde la casella, si spegne e disabilita anche il contatore
                        if !newValue {
                            mailbox.showUnreadCount = false
                        }
                        updateChanges()
                    }
                
                Toggle("Mostra contatore", isOn: $mailbox.showUnreadCount)
                    .disabled(!mailbox.isVisible) // Disabilita se la casella è nascosta
                    .onChange(of: mailbox.showUnreadCount) { _, _ in updateChanges() }

                Picker(selection: $mailbox.iconName) {
                    ForEach(availableIcons, id: \.self) { icon in
                        HStack {
                            Image(systemName: icon)
                            Text(icon.replacingOccurrences(of: ".fill", with: "").capitalized)
                        }
                        .tag(icon)
                    }
                } label: {
                    HStack {
                        Text("Icona:")
                        Image(systemName: mailbox.iconName)
                            .foregroundColor(.accentColor)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: mailbox.iconName) { _, _ in updateChanges() }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func updateChanges() {
        onUpdate(mailbox.isVisible, mailbox.iconName, mailbox.showUnreadCount)
    }
}

#if DEBUG
struct MailboxSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        // Usa il singleton per l'anteprima
        let previewViewModel = MailViewModel.shared
        let sampleMailboxes = [
            DisplayableMailbox(id: "PRINCIPALE", name: "Principale", iconName: "house.fill", isVisible: true, unreadCount: 0, showUnreadCount: true),
            DisplayableMailbox(id: "INBOX", name: "In Arrivo", iconName: "tray.fill", isVisible: true, unreadCount: 5, showUnreadCount: true),
            DisplayableMailbox(id: "SENT", name: "Inviata", iconName: "paperplane.fill", isVisible: false, unreadCount: 0, showUnreadCount: true),
            DisplayableMailbox(id: "CUSTOM_1", name: "Lavoro", iconName: "folder.fill", isVisible: true, unreadCount: 12, showUnreadCount: false)
        ]
        
        // Inizializza il viewModel con dati di esempio
        // (Nota: questo richiede di rendere le proprietà del viewModel pubbliche o interne per l'anteprima)
        // Per semplicità, lo lasciamo così, l'anteprima potrebbe non essere perfetta ma la logica è visibile.
        // In un progetto reale, useremmo un protocollo o un mock.
        previewViewModel.displayableMailboxes = sampleMailboxes
        
        return MailboxSettingsView(viewModel: previewViewModel)
    }
}
#endif 