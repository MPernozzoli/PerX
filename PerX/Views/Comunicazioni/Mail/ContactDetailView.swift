import SwiftUI

struct ContactDetailView: View {
    let contact: Contact
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text(contact.displayName)
                .font(.title)
            
            Text(contact.email)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Placeholder for future actions like "Add to contacts", "Start new email", etc.
            HStack {
                Button("Chiudi") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 300)
    }
}

#Preview {
    ContactDetailView(contact: Contact(name: "Mario Rossi", email: "mario.rossi@example.com"))
} 