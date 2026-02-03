import SwiftUI

/// Badge per mostrare lo stato di un messaggio programmato
struct ScheduledStatusBadge: View {
    let status: ScheduledStatus
    
    enum ScheduledStatus {
        case pending(scheduledFor: Date)
        case sent(sentAt: Date)
        case failed(error: String)
        
        var color: Color {
            switch self {
            case .pending: return .orange
            case .sent: return .green
            case .failed: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .pending: return "clock"
            case .sent: return "checkmark.circle.fill"
            case .failed: return "exclamationmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            
            Text(statusText)
                .font(.caption2)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.15))
        .cornerRadius(10)
    }
    
    private var statusText: String {
        switch status {
        case .pending(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM HH:mm"
            return "Programmata per \(formatter.string(from: date))"
        case .sent(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM HH:mm"
            return "Inviata il \(formatter.string(from: date))"
        case .failed(let error):
            return "Fallita: \(error.prefix(20))..."
        }
    }
}

/// Modifier per aggiungere bordo tratteggiato ai messaggi programmati
struct ScheduledBorderModifier: ViewModifier {
    let isScheduled: Bool
    let status: ScheduledStatusBadge.ScheduledStatus?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isScheduled, case .pending = status {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .foregroundColor(.orange.opacity(0.5))
                    }
                }
            )
    }
}

extension View {
    func scheduledBorder(isScheduled: Bool, status: ScheduledStatusBadge.ScheduledStatus?) -> some View {
        modifier(ScheduledBorderModifier(isScheduled: isScheduled, status: status))
    }
}

/// Row per mostrare email programmata nella lista
struct ScheduledEmailRow: View {
    let email: ScheduledEmailService.ScheduledEmail
    let onCancel: (() -> Void)?
    
    @StateObject private var eventService = HubEventService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Destinatari
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.to.joined(separator: ", "))
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(email.subject)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Badge stato
                statusBadge
                
                // Pulsante cancella (solo se pending)
                if email.isScheduled, let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Annulla invio programmato")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .scheduledBorder(isScheduled: email.isScheduled, status: currentStatus)
        .cornerRadius(8)
    }
    
    private var currentStatus: ScheduledStatusBadge.ScheduledStatus? {
        if eventService.isEmailSent(scheduledId: email.id) {
            return .sent(sentAt: Date())
        } else if eventService.isEmailFailed(scheduledId: email.id),
                  let error = eventService.scheduledEmailsFailed[email.id] {
            return .failed(error: error)
        } else if email.isSent, let sentAt = email.sentAt {
            return .sent(sentAt: sentAt)
        } else if email.isFailed, let error = email.errorMessage {
            return .failed(error: error)
        } else if email.isScheduled {
            return .pending(scheduledFor: email.scheduledAt)
        }
        return nil
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let status = currentStatus {
            ScheduledStatusBadge(status: status)
        }
    }
}

/// Row per mostrare messaggio WhatsApp programmato
struct ScheduledWhatsAppRow: View {
    let message: ScheduledWhatsAppService.ScheduledWhatsApp
    let onCancel: (() -> Void)?
    
    @StateObject private var eventService = HubEventService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(message.phoneNumber)")
                        .font(.headline)
                    
                    Text(message.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Badge stato
                statusBadge
                
                // Pulsante cancella
                if message.isScheduled, let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .scheduledBorder(isScheduled: message.isScheduled, status: currentStatus)
        .cornerRadius(8)
    }
    
    private var currentStatus: ScheduledStatusBadge.ScheduledStatus? {
        if eventService.isWhatsAppSent(scheduledId: message.id) {
            return .sent(sentAt: Date())
        } else if eventService.isWhatsAppFailed(scheduledId: message.id),
                  let error = eventService.scheduledWhatsAppFailed[message.id] {
            return .failed(error: error)
        } else if message.isSent, let sentAt = message.sentAt {
            return .sent(sentAt: sentAt)
        } else if message.isFailed, let error = message.errorMessage {
            return .failed(error: error)
        } else if message.isScheduled {
            return .pending(scheduledFor: message.scheduledAt)
        }
        return nil
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if let status = currentStatus {
            ScheduledStatusBadge(status: status)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ScheduledStatusBadge(status: .pending(scheduledFor: Date().addingTimeInterval(3600)))
        ScheduledStatusBadge(status: .sent(sentAt: Date()))
        ScheduledStatusBadge(status: .failed(error: "Connection timeout"))
    }
    .padding()
}
