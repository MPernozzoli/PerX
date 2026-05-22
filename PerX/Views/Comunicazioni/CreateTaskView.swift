import SwiftUI
import CoreData

struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let email: Email?
    let whatsAppChat: WhatsAppChat?
    let whatsAppMessage: WhatsAppMessage?
    
    @StateObject private var taskManager = TaskManager.shared
    @State private var taskTitle: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedSinistroID: String? = nil
    @State private var deadline: Date? = nil
    @State private var priority: Double = 0.5
    @State private var suggestedSinistri: [Sinistro] = []
    @State private var showingSinistroPicker = false
    @State private var isTimeSensitive = false
    @State private var fixedDateTime: Date? = nil
    @State private var estimatedMinutes: Double = 30
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    
    private var sourceText: String {
        if let email = email {
            return "\(email.subject)\n\n\(email.body ?? "")"
        } else if let message = whatsAppMessage {
            return message.body
        } else if let chat = whatsAppChat {
            return chat.name ?? "Chat WhatsApp"
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Crea Task")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
            }
            
            Divider()
            
            Form {
                // Titolo task
                Section("Titolo") {
                    TextField("Titolo task", text: $taskTitle)
                }
                
                // Descrizione
                Section("Descrizione") {
                    TextEditor(text: $taskDescription)
                        .frame(height: 100)
                }
                
                // Sinistro associato
                Section("Sinistro") {
                    if let selectedID = selectedSinistroID,
                       let selectedSinistro = suggestedSinistri.first(where: { $0.riferimento == selectedID }) {
                        HStack {
                            Text(selectedSinistro.riferimento ?? "N/A")
                            Spacer()
                            Button("Rimuovi") {
                                selectedSinistroID = nil
                            }
                            .foregroundColor(.red)
                            
                            Button("Cambia") {
                                showingSinistroPicker = true
                            }
                        }
                    } else {
                        HStack {
                            Text("Nessun sinistro associato")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Seleziona") {
                                showingSinistroPicker = true
                            }
                        }
                    }
                }
                
                // Priorità
                Section("Priorità") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bassa")
                            Spacer()
                            Text("Alta")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Slider(value: $priority, in: 0.0...1.0, step: 0.1)
                        
                        Text("Priorità: \(Int(priority * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Durata stimata
                Section("Durata stimata") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("5 min")
                            Spacer()
                            Text("2 ore")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Slider(value: $estimatedMinutes, in: 5...120, step: 5)
                        
                        Text("\(Int(estimatedMinutes)) minuti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Time Sensitive e Scadenza
                Section("Opzioni avanzate") {
                    Toggle("Time-sensitive", isOn: $isTimeSensitive)
                        .help("Attiva se la task ha un orario fisso (es. videoperizia, riunione)")
                    
                    if isTimeSensitive {
                        Toggle("Orario fisso", isOn: Binding(
                            get: { fixedDateTime != nil },
                            set: { 
                                if $0 { 
                                    fixedDateTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) 
                                } else { 
                                    fixedDateTime = nil 
                                } 
                            }
                        ))
                        
                        if fixedDateTime != nil {
                            DatePicker("Data/ora fissa", selection: Binding(
                                get: { fixedDateTime ?? Date() },
                                set: { fixedDateTime = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                    
                    // Scadenza (rende automaticamente time-sensitive)
                    Toggle("Imposta scadenza", isOn: Binding(
                        get: { deadline != nil },
                        set: { 
                            if $0 { 
                                deadline = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                                isTimeSensitive = true // La scadenza rende la task time-sensitive
                            } else { 
                                deadline = nil 
                            } 
                        }
                    ))
                    .help("Impostare una scadenza rende automaticamente la task time-sensitive")
                    
                    if deadline != nil {
                        DatePicker("Data scadenza", selection: Binding(
                            get: { deadline ?? Date() },
                            set: { deadline = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                // Contatti
                Section("Contatti") {
                    TextField("Indirizzo email", text: $contactEmail)
                        .textContentType(.emailAddress)
                        .help("Email da usare per il tasto 'Scrivi' se la task richiede inviare una mail")
                    
                    TextField("Numero di telefono", text: $contactPhone)
                        .textContentType(.telephoneNumber)
                        .help("Telefono da usare per il tasto 'Chiama' se la task richiede effettuare una chiamata")
                }
            }
            .formStyle(.grouped)
            
            // Preview del contenuto sorgente
            if !sourceText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contenuto sorgente")
                        .font(.headline)
                    
                    ScrollView {
                        Text(sourceText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            
            // Pulsanti azione
            HStack {
                Spacer()
                
                Button("Crea Task") {
                    createTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskTitle.isEmpty)
            }
        }
        .padding()
        .frame(width: 600, height: 850)
        .onAppear {
            setupInitialValues()
            loadSuggestedSinistri()
        }
        .sheet(isPresented: $showingSinistroPicker) {
            SinistroPickerView(
                selectedSinistroID: $selectedSinistroID,
                suggestedSinistri: suggestedSinistri
            )
        }
    }
    
    private func setupInitialValues() {
        if let email = email {
            taskTitle = "Rispondere a: \(email.subject)"
            taskDescription = email.body.map { String($0.prefix(500)) } ?? ""
        } else if let message = whatsAppMessage {
            taskTitle = "Rispondere a WhatsApp"
            taskDescription = String(message.body.prefix(500))
        } else if let chat = whatsAppChat {
            taskTitle = "Gestire chat: \(chat.name ?? "WhatsApp")"
            taskDescription = ""
        }
        
        // Calcola priorità base se c'è un sinistro suggerito
        if let firstSinistro = suggestedSinistri.first {
            selectedSinistroID = firstSinistro.riferimento
            priority = taskManager.calculateBasePriority(for: firstSinistro)
        }
    }
    
    private func loadSuggestedSinistri() {
        if let email = email {
            // Cerca sinistri associati all'email
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "SUBQUERY(diarioArray, $entry, $entry.emailMessageId == %@).@count > 0", email.id)
            
            if let sinistri = try? viewContext.fetch(request) {
                suggestedSinistri = sinistri
            }
        } else if let chat = whatsAppChat {
            // Cerca sinistri associati alla chat WhatsApp
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "SUBQUERY(diarioArray, $entry, $entry.whatsAppChatId == %@).@count > 0", chat.id)
            
            if let sinistri = try? viewContext.fetch(request) {
                suggestedSinistri = sinistri
            }
        }
    }
    
    private func createTask() {
        var metadata: [String: AnyCodable] = [:]

        // Aggiungi metadata sorgente solo se presenti
        if let emailId = email?.id, !emailId.isEmpty {
            metadata["sourceEmailId"] = AnyCodable(emailId)
            metadata["originalEmailId"] = AnyCodable(emailId)
            metadata["sourceType"] = AnyCodable("email")
        } else if let chatId = whatsAppChat?.id, !chatId.isEmpty {
            metadata["sourceWhatsAppChatId"] = AnyCodable(chatId)
            metadata["whatsAppChatId"] = AnyCodable(chatId)
            metadata["sourceType"] = AnyCodable("whatsapp")
        }

        if let messageId = whatsAppMessage?.id, !messageId.isEmpty {
            metadata["sourceWhatsAppMessageId"] = AnyCodable(messageId)
        }

        // Aggiungi contatti se presenti
        if !contactEmail.isEmpty {
            metadata["contactEmail"] = AnyCodable(contactEmail)
        }
        if !contactPhone.isEmpty {
            metadata["contactPhone"] = AnyCodable(contactPhone)
        }

        // Se c'è una scadenza, la task è automaticamente time-sensitive
        let finalIsTimeSensitive = isTimeSensitive || deadline != nil

        let task = DailyTask(
            title: taskTitle,
            description: taskDescription.isEmpty ? sourceText : taskDescription,
            type: .manual,
            sinistroID: selectedSinistroID,
            priority: priority,
            deadline: deadline,
            estimatedDuration: estimatedMinutes * 60,
            metadata: metadata,
            isTimeSensitive: finalIsTimeSensitive,
            fixedDateTime: fixedDateTime
        )

        // Salva localmente per risposta UI immediata
        taskManager.addTask(task)

        // Sincronizza con il server (immediato se online, accodato se offline)
        Task {
            await TaskSyncQueue.shared.enqueueCreate(task)
        }

        dismiss()
    }
}

struct SinistroPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedSinistroID: String?
    let suggestedSinistri: [Sinistro]
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.riferimento, ascending: true)],
        animation: .default
    ) private var allSinistri: FetchedResults<Sinistro>
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seleziona Sinistro")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Lista sinistri
            List {
                // Sinistri suggeriti
                if !suggestedSinistri.isEmpty {
                    Section("Suggeriti") {
                        ForEach(suggestedSinistri, id: \.riferimento) { sinistro in
                            Button {
                                selectedSinistroID = sinistro.riferimento
                                dismiss()
                            } label: {
                                HStack {
                                    Text(sinistro.riferimentoVisualizzato)
                                    Spacer()
                                    if selectedSinistroID == sinistro.riferimento {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Opzione nessun sinistro
                Section("Nessun sinistro") {
                    Button {
                        selectedSinistroID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Nessun sinistro associato")
                                .foregroundColor(.secondary)
                            Spacer()
                            if selectedSinistroID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                // Tutti i sinistri
                Section("Tutti i sinistri") {
                    ForEach(allSinistri, id: \.riferimento) { sinistro in
                        Button {
                            selectedSinistroID = sinistro.riferimento
                            dismiss()
                        } label: {
                            HStack {
                                Text(sinistro.riferimentoVisualizzato)
                                Spacer()
                                if selectedSinistroID == sinistro.riferimento {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct EditTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let task: DailyTask
    
    @StateObject private var taskManager = TaskManager.shared
    @State private var taskTitle: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedSinistroID: String? = nil
    @State private var deadline: Date? = nil
    @State private var priority: Double = 0.5
    @State private var suggestedSinistri: [Sinistro] = []
    @State private var showingSinistroPicker = false
    @State private var isTimeSensitive = false
    @State private var fixedDateTime: Date? = nil
    @State private var estimatedMinutes: Double = 30
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Modifica Task")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
            }
            
            Divider()
            
            Form {
                // Titolo task
                Section("Titolo") {
                    TextField("Titolo task", text: $taskTitle)
                }
                
                // Descrizione
                Section("Descrizione") {
                    TextEditor(text: $taskDescription)
                        .frame(height: 100)
                }
                
                // Sinistro associato
                Section("Sinistro") {
                    if let selectedID = selectedSinistroID,
                       let selectedSinistro = suggestedSinistri.first(where: { $0.riferimento == selectedID }) {
                        HStack {
                            Text(selectedSinistro.riferimentoVisualizzato)
                            Spacer()
                            Button("Rimuovi") {
                                selectedSinistroID = nil
                            }
                            .foregroundColor(.red)
                            
                            Button("Cambia") {
                                showingSinistroPicker = true
                            }
                        }
                    } else {
                        HStack {
                            Text("Nessun sinistro associato")
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Seleziona") {
                                showingSinistroPicker = true
                            }
                        }
                    }
                }
                
                // Priorità
                Section("Priorità") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bassa")
                            Spacer()
                            Text("Alta")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Slider(value: $priority, in: 0.0...1.0, step: 0.1)
                        
                        Text("Priorità: \(Int(priority * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Durata stimata
                Section("Durata stimata") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("5 min")
                            Spacer()
                            Text("2 ore")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Slider(value: $estimatedMinutes, in: 5...120, step: 5)
                        
                        Text("\(Int(estimatedMinutes)) minuti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Time Sensitive e Scadenza
                Section("Opzioni avanzate") {
                    Toggle("Time-sensitive", isOn: $isTimeSensitive)
                        .help("Attiva se la task ha un orario fisso (es. videoperizia, riunione)")
                    
                    if isTimeSensitive {
                        Toggle("Orario fisso", isOn: Binding(
                            get: { fixedDateTime != nil },
                            set: { 
                                if $0 { 
                                    fixedDateTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) 
                                } else { 
                                    fixedDateTime = nil 
                                } 
                            }
                        ))
                        
                        if fixedDateTime != nil {
                            DatePicker("Data/ora fissa", selection: Binding(
                                get: { fixedDateTime ?? Date() },
                                set: { fixedDateTime = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                    
                    // Scadenza (rende automaticamente time-sensitive)
                    Toggle("Imposta scadenza", isOn: Binding(
                        get: { deadline != nil },
                        set: { 
                            if $0 { 
                                deadline = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                                isTimeSensitive = true // La scadenza rende la task time-sensitive
                            } else { 
                                deadline = nil 
                            } 
                        }
                    ))
                    .help("Impostare una scadenza rende automaticamente la task time-sensitive")
                    
                    if deadline != nil {
                        DatePicker("Data scadenza", selection: Binding(
                            get: { deadline ?? Date() },
                            set: { deadline = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                // Contatti
                Section("Contatti") {
                    TextField("Indirizzo email", text: $contactEmail)
                        .textContentType(.emailAddress)
                        .help("Email da usare per il tasto 'Scrivi' se la task richiede inviare una mail")
                    
                    TextField("Numero di telefono", text: $contactPhone)
                        .textContentType(.telephoneNumber)
                        .help("Telefono da usare per il tasto 'Chiama' se la task richiede effettuare una chiamata")
                }
            }
            .formStyle(.grouped)
            
            // Pulsanti azione
            HStack {
                Button("Elimina") {
                    let taskId = task.id
                    taskManager.deleteTask(taskID: taskId)
                    Task { await TaskSyncQueue.shared.enqueueDelete(localId: taskId) }
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Salva") {
                    updateTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskTitle.isEmpty)
            }
        }
        .padding()
        .frame(width: 600, height: 850)
        .onAppear {
            setupInitialValues()
            loadSuggestedSinistri()
        }
        .sheet(isPresented: $showingSinistroPicker) {
            SinistroPickerView(
                selectedSinistroID: $selectedSinistroID,
                suggestedSinistri: suggestedSinistri
            )
        }
    }
    
    private func setupInitialValues() {
        taskTitle = task.title
        taskDescription = task.description
        selectedSinistroID = task.sinistroID
        deadline = task.deadline
        priority = task.priority
        isTimeSensitive = task.isTimeSensitive
        fixedDateTime = task.fixedDateTime
        estimatedMinutes = task.estimatedDuration / 60
        
        // Carica contatti dai metadata
        if let email = task.metadata["contactEmail"]?.value as? String {
            contactEmail = email
        }
        if let phone = task.metadata["contactPhone"]?.value as? String {
            contactPhone = phone
        }
        
        // Carica sinistro se presente
        if let sinistroID = task.sinistroID {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
            if let sinistro = try? viewContext.fetch(request).first {
                suggestedSinistri = [sinistro]
            }
        }
    }
    
    private func loadSuggestedSinistri() {
        // Mantiene il sinistro già associato se presente
        if let sinistroID = task.sinistroID, suggestedSinistri.isEmpty {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
            if let sinistro = try? viewContext.fetch(request).first {
                suggestedSinistri = [sinistro]
            }
        }
    }
    
    private func updateTask() {
        guard let index = taskManager.tasks.firstIndex(where: { $0.id == task.id }) else {
            dismiss()
            return
        }

        var updatedTask = taskManager.tasks[index]
        updatedTask.title = taskTitle
        updatedTask.description = taskDescription
        updatedTask.sinistroID = selectedSinistroID
        updatedTask.deadline = deadline
        updatedTask.priority = priority
        updatedTask.isTimeSensitive = fixedDateTime != nil || deadline != nil || isTimeSensitive
        updatedTask.fixedDateTime = fixedDateTime
        updatedTask.estimatedDuration = estimatedMinutes * 60

        // Aggiorna metadata contatti
        if !contactEmail.isEmpty {
            updatedTask.metadata["contactEmail"] = AnyCodable(contactEmail)
        } else {
            updatedTask.metadata.removeValue(forKey: "contactEmail")
        }
        if !contactPhone.isEmpty {
            updatedTask.metadata["contactPhone"] = AnyCodable(contactPhone)
        } else {
            updatedTask.metadata.removeValue(forKey: "contactPhone")
        }

        taskManager.tasks[index] = updatedTask
        taskManager.saveTasks()
        taskManager.updateCounter += 1

        // Sincronizza aggiornamento col server (immediato se online, accodato se offline)
        let localId = updatedTask.id
        Task {
            await TaskSyncQueue.shared.enqueueUpdate(
                localId: localId,
                title: updatedTask.title,
                description: updatedTask.description.isEmpty ? nil : updatedTask.description,
                priority: updatedTask.priority,
                dueDate: updatedTask.deadline,
                status: updatedTask.status
            )
        }

        ScheduleManager.shared.reorganizeAllTasksBasedOnSchedule(userInitiated: true)
        dismiss()
    }
}

