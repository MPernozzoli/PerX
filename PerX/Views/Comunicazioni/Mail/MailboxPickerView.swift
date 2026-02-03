import SwiftUI

struct MailboxPickerView: View {
    @Binding var selection: String
    let mailboxes: [DisplayableMailbox]
    var onSettingsTap: (() -> Void)?
    
    // Namespace for the animation
    @Namespace private var animation
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(mailboxes) { mailbox in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = mailbox.id
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mailbox.iconName)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 16, height: 16)
                            
                            // Mostra il nome solo per la casella selezionata con animazione fluida
                            if selection == mailbox.id {
                                Text(mailbox.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.9)),
                                        removal: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.9))
                                    ))
                            }
                            
                            // Mostra il badge se ci sono email non lette e se l'opzione è attiva
                            if mailbox.showUnreadCount && mailbox.unreadCount > 0 {
                                Text("\(mailbox.unreadCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, selection == mailbox.id ? 10 : 6)
                        .background {
                            if selection == mailbox.id {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .matchedGeometryEffect(id: "selected", in: animation)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selection == mailbox.id ? .accentColor : .secondary)
                }
                
                // Pulsante impostazioni - sempre visibile alla fine (solo icona)
                if let onSettingsTap = onSettingsTap {
                    Button(action: onSettingsTap) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16, height: 16)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Impostazioni caselle")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selection: String = "INBOX"
        
        // Dati di esempio per l'anteprima
        let sampleMailboxes = [
            DisplayableMailbox(id: "PRINCIPALE", name: "Principale", iconName: "house.fill", isVisible: true, unreadCount: 0, showUnreadCount: true),
            DisplayableMailbox(id: "INBOX", name: "In Arrivo", iconName: "tray.fill", isVisible: true, unreadCount: 5, showUnreadCount: true),
            DisplayableMailbox(id: "SENT", name: "Inviata", iconName: "paperplane.fill", isVisible: true, unreadCount: 0, showUnreadCount: true),
            DisplayableMailbox(id: "CUSTOM_1", name: "Lavoro", iconName: "folder.fill", isVisible: true, unreadCount: 12, showUnreadCount: false)
        ]
        
        var body: some View {
            MailboxPickerView(
                selection: $selection,
                mailboxes: sampleMailboxes
            )
            .padding()
        }
    }
    return PreviewWrapper()
} 