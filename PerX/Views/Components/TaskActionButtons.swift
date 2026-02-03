import SwiftUI

/// Tasti contestuali per una task basati sul tipo di azione
/// Mostra tasti specifici per l'azione richiesta (chiama, rispondi, scrivi, etc.)
struct TaskActionButtons: View {
    let task: DailyTask
    let onComplete: () -> Void
    let onOpenSinistro: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Tasti contestuali basati su actionType
            if let actionType = task.actionType {
                switch actionType {
                case .call:
                    CallActionButton(phoneNumber: task.phoneNumber ?? "")
                    
                case .reply:
                    ReplyActionButton(emailId: task.replyToEmailId ?? "")
                    
                case .email, .send:
                    EmailActionButton(address: task.email ?? "")
                    
                case .remind:
                    RemindActionButton(task: task)
                    
                case .request:
                    RequestActionButton(task: task)
                    
                case .attend:
                    AttendActionButton(task: task)
                    
                case .review, .verify:
                    ReviewActionButton(task: task)
                    
                case .close:
                    CloseActionButton(task: task)
                }
            }
            
            // Tasti sempre presenti
            if task.sinistroID != nil {
                Button {
                    onOpenSinistro()
                } label: {
                    Label("Apri sinistro", systemImage: "folder.fill")
                }
                .buttonStyle(.bordered)
            }
            
            Button {
                onComplete()
            } label: {
                Label("Segna completata", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Action Buttons

struct CallActionButton: View {
    let phoneNumber: String
    
    var body: some View {
        Button {
            // Apri app telefono con numero
            if let url = URL(string: "tel://\(phoneNumber)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Chiama", systemImage: "phone.fill")
        }
        .buttonStyle(.bordered)
        .disabled(phoneNumber.isEmpty)
    }
}

struct ReplyActionButton: View {
    let emailId: String
    
    var body: some View {
        Button {
            // Apri ComposeEmailView in modalità risposta
            // TODO: Implementare navigazione a ComposeEmailView
            print("[TaskActionButtons] 📧 Rispondi a email: \(emailId)")
        } label: {
            Label("Rispondi", systemImage: "arrowshape.turn.up.left.fill")
        }
        .buttonStyle(.bordered)
        .disabled(emailId.isEmpty)
    }
}

struct EmailActionButton: View {
    let address: String
    
    var body: some View {
        Button {
            // Apri ComposeEmailView con destinatario pre-compilato
            // TODO: Implementare navigazione a ComposeEmailView
            print("[TaskActionButtons] 📧 Scrivi email a: \(address)")
        } label: {
            Label("Scrivi", systemImage: "envelope.fill")
        }
        .buttonStyle(.bordered)
        .disabled(address.isEmpty)
    }
}

struct RemindActionButton: View {
    let task: DailyTask
    
    var body: some View {
        Button {
            // Apri template sollecito
            print("[TaskActionButtons] 🔔 Sollecita: \(task.title)")
        } label: {
            Label("Sollecita", systemImage: "bell.fill")
        }
        .buttonStyle(.bordered)
    }
}

struct RequestActionButton: View {
    let task: DailyTask
    
    var body: some View {
        Button {
            // Apri template richiesta
            print("[TaskActionButtons] 📥 Richiedi: \(task.title)")
        } label: {
            Label("Richiedi", systemImage: "arrow.down.doc.fill")
        }
        .buttonStyle(.bordered)
    }
}

struct AttendActionButton: View {
    let task: DailyTask
    
    var body: some View {
        Button {
            // Segna partecipazione
            print("[TaskActionButtons] 🎥 Partecipa: \(task.title)")
        } label: {
            Label("Partecipa", systemImage: "video.fill")
        }
        .buttonStyle(.bordered)
    }
}

struct ReviewActionButton: View {
    let task: DailyTask
    
    var body: some View {
        Button {
            // Apri view di controllo
            print("[TaskActionButtons] 🔍 Controlla: \(task.title)")
        } label: {
            Label("Controlla", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
    }
}

struct CloseActionButton: View {
    let task: DailyTask
    
    var body: some View {
        Button {
            // Apri workflow chiusura
            print("[TaskActionButtons] 🔒 Chiudi sinistro: \(task.sinistroID ?? "")")
        } label: {
            Label("Chiudi", systemImage: "lock.fill")
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        TaskActionButtons(
            task: DailyTask(
                title: "Chiamare assicurato",
                description: "Test task",
                type: .sinistroActivity,
                sinistroID: "RIF123",
                phoneNumber: "+39 123 456 7890",
                actionType: .call
            ),
            onComplete: {
                print("Task completata")
            },
            onOpenSinistro: {
                print("Apri sinistro")
            }
        )
        
        TaskActionButtons(
            task: DailyTask(
                title: "Rispondere a email",
                description: "Test task",
                type: .sinistroActivity,
                sinistroID: "RIF456",
                replyToEmailId: "email123",
                actionType: .reply
            ),
            onComplete: {
                print("Task completata")
            },
            onOpenSinistro: {
                print("Apri sinistro")
            }
        )
    }
    .padding()
}
