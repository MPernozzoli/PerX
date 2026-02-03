import SwiftUI
import CoreData

/// Popover per visualizzare task correlate a una comunicazione (email/WhatsApp) e crearne di nuove
struct TaskPopoverView: View {
    let email: Email?
    let whatsAppChat: WhatsAppChat?
    let whatsAppMessage: WhatsAppMessage?
    let sinistro: Sinistro?
    
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateTask = false
    
    /// Task correlate alla comunicazione corrente
    private var relatedTasks: [DailyTask] {
        taskManager.tasks.filter { task in
            // Filtra per email ID
            if let emailId = email?.id,
               let taskEmailId = task.metadata["originalEmailId"]?.value as? String,
               taskEmailId == emailId {
                return true
            }
            
            // Filtra per WhatsApp chat ID
            if let chatId = whatsAppChat?.id,
               let taskChatId = task.metadata["whatsAppChatId"]?.value as? String,
               taskChatId == chatId {
                return true
            }
            
            // Filtra per sinistro ID se presente
            if let sinistroRef = sinistro?.riferimento,
               task.sinistroID == sinistroRef {
                // Solo task AI-generated o manuali correlate a comunicazioni
                if task.type == .aiGenerated || task.metadata["sourceEmailId"]?.value != nil || task.metadata["sourceWhatsAppChatId"]?.value != nil {
                    return true
                }
            }
            
            return false
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Task pendenti
    private var pendingTasks: [DailyTask] {
        relatedTasks.filter { $0.status == .pending && !$0.isIgnored }
    }
    
    /// Task completate
    private var completedTasks: [DailyTask] {
        relatedTasks.filter { $0.status == .completed }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.accentColor)
                Text("Task Correlate")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingCreateTask = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Nuova")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            if relatedTasks.isEmpty {
                // Nessuna task trovata
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("Nessuna task correlata")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Crea una nuova task per questa comunicazione")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Task pendenti
                        if !pendingTasks.isEmpty {
                            Text("Pendenti")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                            
                            ForEach(pendingTasks) { task in
                                TaskPopoverRow(task: task, onComplete: {
                                    taskManager.markTaskCompleted(taskID: task.id)
                                })
                            }
                        }
                        
                        // Task completate (collassate)
                        if !completedTasks.isEmpty {
                            DisclosureGroup {
                                ForEach(completedTasks) { task in
                                    TaskPopoverRow(task: task, onComplete: nil)
                                }
                            } label: {
                                Text("Completate (\(completedTasks.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            // Info sinistro se presente
            if let sinistro = sinistro {
                Divider()
                
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Sinistro: \(sinistro.riferimentoVisualizzato)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 350)
        .sheet(isPresented: $showingCreateTask) {
            CreateTaskView(
                email: email,
                whatsAppChat: whatsAppChat,
                whatsAppMessage: whatsAppMessage
            )
            .environment(\.managedObjectContext, viewContext)
        }
    }
}

/// Riga singola di task nel popover
struct TaskPopoverRow: View {
    let task: DailyTask
    let onComplete: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox per completamento (solo per task pending)
            if task.status == .pending {
                Button(action: { onComplete?() }) {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .strikethrough(task.status == .completed)
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    // Priorità
                    priorityBadge
                    
                    // Scadenza
                    if let deadline = task.deadline {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(deadline.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                        }
                        .foregroundColor(task.hasExpired ? .red : .secondary)
                    }
                    
                    // Time-sensitive
                    if task.isTimeSensitive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private var priorityBadge: some View {
        let (color, text): (Color, String) = {
            switch task.priority {
            case 0.8...1.0: return (.red, "Alta")
            case 0.5..<0.8: return (.orange, "Media")
            default: return (.secondary, "Bassa")
            }
        }()
        
        return Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

#Preview {
    TaskPopoverView(
        email: nil,
        whatsAppChat: nil,
        whatsAppMessage: nil,
        sinistro: nil
    )
}

