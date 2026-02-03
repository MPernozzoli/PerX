import SwiftUI
import AppKit

struct DailyTaskRow: View {
    let task: DailyTask
    let dayKind: DayKind
    let onComplete: () -> Void
    let onIgnore: () -> Void
    
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var appState = AppState.shared
    @ObservedObject private var workScheduleManager = WorkScheduleManager.shared
    @State private var sinistro: Sinistro?
    @State private var insuredName: String = ""
    @State private var sinistroState: String = ""
    @State private var isHovered = false
    @State private var availableWidth: CGFloat = 0
    @State private var statoColor: Color = .blue
    @State private var statoIcon: String = "gearshape"
    @State private var folderMissing: Bool = false
    @State private var showingEditTask = false
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        Group {
            switch dayKind {
            case .today:
                todayRow
            case .future:
                futureRow
            case .past:
                pastRow
            }
        }
        .onAppear(perform: loadSinistro)
        .sheet(isPresented: $showingEditTask) {
            EditTaskView(task: task)
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    // MARK: - Today (dettaglio)
    private var todayRow: some View {
        ViewThatFits {
            // Layout normale (spazio sufficiente)
            normalLayout
            
            // Layout compatto (spazio limitato)
            compactLayout
        }
    }
    
    private var normalLayout: some View {
        let timeString = task.scheduledTime.map { timeFormatter.string(from: $0) } ?? ""
        
        return HStack(spacing: 10) {
            // Orario
            if let scheduledTime = task.scheduledTime {
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .leading)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Prima riga: [nome task]
                HStack(spacing: 6) {
                    // Tasto modifica per task manuali
                    if task.type == .manual {
                        Button(action: {
                            showingEditTask = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Modifica task")
                    }
                    
                    // Indicatore time-sensitive
                    if task.isTimeSensitive {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(task.isOverdue ? .red : .orange)
                    }
                    
                    HStack(spacing: 4) {
                        Text(task.displayTitle)
                            .font(.headline)
                            .foregroundColor(task.isOverdue ? .red : (task.isTimeSensitive ? .orange : .primary))
                            .lineLimit(1)
                        
                        if let rif = task.sinistroID {
                            Text("- \(riferimentoVisualizzato(for: rif))")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Dettaglio "da scaricare" se manca la cartella
                    if folderMissing && sinistroState != "Da scaricare" {
                        Text("da scaricare")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    if task.isExpired {
                        Text("SCADUTO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    } else if task.isDeadlineImminent {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                // Seconda riga: [nome assicurato]
                if !insuredName.isEmpty {
                    Text(insuredName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !task.description.isEmpty {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Terza riga: [tasti contestuali e del task] [apri sinistro]
                actionButtons
            }
            
            Spacer()
        }
        .padding(.vertical, isHovered ? 12 : 8)
        .padding(.horizontal, 10)
        .background(
            ZStack {
                // Colore di sfondo dello stato dentro la box
                todayBackgroundWithState
                
                // Icona dello stato come sfondo per task future dentro la box
                if taskTimeStatus == .future {
                    Image(systemName: statoIcon)
                        .font(.system(size: 60))
                        .foregroundColor(statoColor.opacity(0.15))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
        )
        .cornerRadius(10)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? Color.black.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
    
    private var compactLayout: some View {
        let timeString = task.scheduledTime.map { timeFormatter.string(from: $0) } ?? ""
        
        return HStack(spacing: 10) {
            // Orario
            if let scheduledTime = task.scheduledTime {
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .leading)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Prima riga: [nome task] - [nome assicurato]
                HStack(spacing: 6) {
                    // Indicatore time-sensitive
                    if task.isTimeSensitive {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(task.isOverdue ? .red : .orange)
                    }
                    
                    HStack(spacing: 4) {
                        Text(task.displayTitle)
                            .font(.headline)
                            .foregroundColor(task.isOverdue ? .red : (task.isTimeSensitive ? .orange : .primary))
                            .lineLimit(1)
                        
                        if let rif = task.sinistroID {
                            Text("- \(riferimentoVisualizzato(for: rif))")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if !insuredName.isEmpty {
                        Text(insuredName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Dettaglio "da scaricare" se manca la cartella
                    if folderMissing && sinistroState != "Da scaricare" {
                        Text("da scaricare")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    if task.isExpired {
                        Text("SCADUTO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    } else if task.isDeadlineImminent {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                // Seconda riga: [tasti contestuali e del task] [apri sinistro]
                actionButtons
            }
            
            Spacer()
        }
        .padding(.vertical, isHovered ? 12 : 8)
        .padding(.horizontal, 10)
        .background(
            ZStack {
                // Colore di sfondo dello stato dentro la box
                todayBackgroundWithState
                
                // Icona dello stato come sfondo per task future dentro la box
                if taskTimeStatus == .future {
                    Image(systemName: statoIcon)
                        .font(.system(size: 60))
                        .foregroundColor(statoColor.opacity(0.15))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
        )
        .cornerRadius(10)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? Color.black.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Mostra pulsanti solo all'hover o se la task non è pending
            if isHovered || task.status != .pending {
                // Pulsante "Chiama" se c'è un numero di telefono nel campo phoneNumber
                if let phoneNumber = task.phoneNumber, !phoneNumber.isEmpty {
                    Button(action: {
                        openWebexCall(phoneNumber: phoneNumber)
                    }) {
                        Label("Chiama", systemImage: "phone.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Chiama \(phoneNumber) su Webex")
                    .transition(.scale.combined(with: .opacity))
                } else if let phoneNumber = getPhoneNumberForCall(from: task) {
                    // Fallback: usa la logica esistente se non c'è phoneNumber nel campo
                    Button(action: {
                        openWebexCall(phoneNumber: phoneNumber)
                    }) {
                        Label("Chiama", systemImage: "phone.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Chiama \(phoneNumber) su Webex")
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Pulsante "Rispondi" se c'è un replyToEmailId
                if let replyToEmailId = task.replyToEmailId, !replyToEmailId.isEmpty {
                    Button(action: {
                        openReplyEmail(emailId: replyToEmailId)
                    }) {
                        Label("Rispondi", systemImage: "arrowshape.turn.up.left.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Rispondi all'email")
                    .transition(.scale.combined(with: .opacity))
                }
                // Pulsante "Scrivi" se c'è un email ma non replyToEmailId
                else if let email = task.email, !email.isEmpty {
                    Button(action: {
                        openComposeEmail(to: email, sinistro: sinistro)
                    }) {
                        Label("Scrivi", systemImage: "envelope.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Scrivi email a \(email)")
                    .transition(.scale.combined(with: .opacity))
                }
                
                if let sinistro = sinistro {
                    Button("Apri sinistro") {
                        appState.openSinistro(sinistro)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
                }
                
                if task.status == .pending {
                    Button("Completata", action: onComplete)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                    
                    // Nascondi "Sposta" per eventi time-sensitive
                    if !task.isTimeSensitive {
                        Menu {
                            // Più tardi (decide automaticamente nel range 30m-2h)
                            if canRescheduleLater(task: task) {
                                Button("Più tardi") {
                                    ScheduleManager.shared.rescheduleTaskLater(taskID: task.id)
                                }
                            }
                            
                            // Nel pomeriggio
                            if canRescheduleToAfternoon(task: task) {
                                Button("Nel pomeriggio") {
                                    ScheduleManager.shared.rescheduleTaskToAfternoon(taskID: task.id)
                                }
                            }
                            
                            // Domattina
                            if canRescheduleToNextMorning(task: task) {
                                Button("Domattina") {
                                    ScheduleManager.shared.rescheduleTaskToNextMorning(taskID: task.id)
                                }
                            }
                            
                            // Domani (o nome del giorno se non è domani)
                            Button(nextWorkingDayLabel(for: task)) {
                                ScheduleManager.shared.rescheduleTaskToNextWorkingDay(taskID: task.id)
                            }
                        } label: {
                            Label("Sposta", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                    }
                } else if task.status == .completed {
                    Label("Completata", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if task.status == .inProgress {
                    Label("In corso", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                // Spazio vuoto per mantenere l'altezza quando i pulsanti sono nascosti
                Color.clear
                    .frame(height: 0)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
    }
    
    /// Determina se il task richiede una chiamata basandosi sul titolo e descrizione
    private func requiresCall(_ task: DailyTask) -> Bool {
        let titleLower = task.title.lowercased()
        let descriptionLower = task.description.lowercased()
        
        // Pattern per rilevare richieste di chiamata
        let callPatterns = ["chiamare", "chiamata", "chiama", "telefonare", "telefonata", "contattare telefonicamente"]
        
        // Controlla nel titolo
        for pattern in callPatterns {
            if titleLower.contains(pattern) || titleLower == pattern {
                return true
            }
        }
        
        // Controlla nella descrizione
        for pattern in callPatterns {
            if descriptionLower.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Ottiene il numero di telefono appropriato per la chiamata
    private func getPhoneNumberForCall(from task: DailyTask) -> String? {
        // 1. Se ci sono numeri espliciti nei metadata, usali
        if let phoneNumbersValue = task.metadata["phoneNumbers"]?.value as? [String],
           let firstPhone = phoneNumbersValue.first {
            return firstPhone
        }
        
        // 2. Se il task richiede una chiamata, cerca il numero appropriato dal sinistro
        guard requiresCall(task) else { return nil }
        
        guard let sinistro = sinistro else { return nil }
        
        let titleLower = task.title.lowercased()
        let descriptionLower = task.description.lowercased()
        let combinedText = "\(titleLower) \(descriptionLower)"
        
        // Se contiene "chiamare agenzia" o "chiamare agenzia", usa telefonoAgenzia
        if combinedText.contains("agenzia") && combinedText.contains("chiam") {
            // Per ora non implementato - la rubrica agenzie non è ancora disponibile
            // TODO: Quando sarà implementata, controllare la rubrica agenzie
            if let telefonoAgenzia = sinistro.telefonoAgenzia, !telefonoAgenzia.isEmpty {
                return normalizePhoneNumber(telefonoAgenzia)
            }
            return nil
        }
        
        // Se contiene "chiamare assicurato" o solo "chiamare", usa telefonoAssicurato
        if combinedText.contains("assicurato") && combinedText.contains("chiam") {
            if let telefonoAssicurato = sinistro.telefonoAssicurato, !telefonoAssicurato.isEmpty {
                return normalizePhoneNumber(telefonoAssicurato)
            }
            // Fallback su telefonoContraente se disponibile
            if let telefonoContraente = sinistro.telefonoContraente, !telefonoContraente.isEmpty {
                return normalizePhoneNumber(telefonoContraente)
            }
            return nil
        }
        
        // Default: se contiene solo "chiamare" o pattern simili, assume assicurato
        if combinedText.contains("chiamare") || combinedText.contains("chiamata") || combinedText.contains("telefonare") {
            if let telefonoAssicurato = sinistro.telefonoAssicurato, !telefonoAssicurato.isEmpty {
                return normalizePhoneNumber(telefonoAssicurato)
            }
            if let telefonoContraente = sinistro.telefonoContraente, !telefonoContraente.isEmpty {
                return normalizePhoneNumber(telefonoContraente)
            }
        }
        
        return nil
    }
    
    /// Normalizza un numero di telefono aggiungendo +39 se necessario
    private func normalizePhoneNumber(_ number: String) -> String {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        if cleaned.hasPrefix("+39") {
            return cleaned
        } else if cleaned.hasPrefix("0039") {
            return "+39" + String(cleaned.dropFirst(4))
        } else if cleaned.hasPrefix("39") && cleaned.count >= 11 {
            return "+" + cleaned
        } else if cleaned.hasPrefix("0") && cleaned.count >= 9 {
            // Numero locale, aggiungi +39
            return "+39" + cleaned
        } else if cleaned.count >= 9 && !cleaned.hasPrefix("+") && !cleaned.hasPrefix("0") {
            // Numero senza prefisso, aggiungi +39
            return "+39" + cleaned
        }
        
        return cleaned
    }
    
    private func openWebexCall(phoneNumber: String) {
        // Webex usa URL scheme per chiamate: webex://call?number=+39xxxxx
        // Rimuovi eventuali caratteri non numerici tranne +
        let cleanNumber = phoneNumber.replacingOccurrences(
            of: "[^+0-9]",
            with: "",
            options: .regularExpression
        )
        
        guard let url = URL(string: "webex://call?number=\(cleanNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanNumber)") else {
            print("[DailyTaskRow] ❌ Impossibile creare URL Webex per: \(phoneNumber)")
            return
        }
        
        // Prova ad aprire Webex
        NSWorkspace.shared.open(url)
        print("[DailyTaskRow] 📞 Apertura Webex per chiamata: \(cleanNumber)")
    }
    
    private func openReplyEmail(emailId: String) {
        // Carica l'email dal repository o dalla cache
        if let email = EmailRepository.shared.getEmail(byId: emailId) {
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
        } else if let email = EmailCacheService.shared.loadFullEmail(forId: emailId) {
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
        } else {
            print("[DailyTaskRow] ❌ Email con ID \(emailId) non trovata, scaricamento...")
            // Prova a scaricare l'email usando MailViewModel (converte automaticamente)
            Task {
                let mailViewModel = MailViewModel.shared
                await mailViewModel.fetchFullEmail(for: emailId)
                
                // Aspetta che l'email sia scaricata e salvata
                var attempts = 0
                while attempts < 10 {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    
                    // Prova dalla memoria prima
                    if let email = EmailCacheService.shared.loadFullEmailFromMemory(forId: emailId) {
                        await MainActor.run {
                            ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
                        }
                        return
                    }
                    
                    // Poi prova dalla cache completa
                    if let email = await EmailCacheService.shared.loadFullEmailAsync(forId: emailId) {
                        await MainActor.run {
                            ComposeEmailWindowManager.shared.openComposeEmail(mode: .reply(email))
                        }
                        return
                    }
                    
                    attempts += 1
                }
                
                print("[DailyTaskRow] ⏰ Timeout nel caricamento email \(emailId)")
            }
        }
    }
    
    private func openComposeEmail(to email: String, sinistro: Sinistro?) {
        guard let sinistro = sinistro else {
            // Se non c'è sinistro, apri con solo l'email
            ComposeEmailWindowManager.shared.openComposeEmail(mode: .new(to: email, subject: nil))
            return
        }
        
        let numeroSinistro = sinistro.numeroSinistroCompagnia ?? "N/A"
        let nomeAssicurato = sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "Assicurato"
        let riferimento = sinistro.riferimento ?? ""
        
        let oggetto = "Sinistro n.\(numeroSinistro) - Assicurato: \(nomeAssicurato) - ns. rif. \(riferimento)"
        
        ComposeEmailWindowManager.shared.openComposeEmail(mode: .new(to: email, subject: oggetto))
    }
    
    // MARK: - Future (compatto)
    private var futureRow: some View {
        HStack(spacing: 8) {
            if let scheduledTime = task.scheduledTime {
                Text(timeFormatter.string(from: scheduledTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }
            Text(task.title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Past (status color)
    private var pastRow: some View {
        HStack(spacing: 8) {
            if let scheduledTime = task.scheduledTime {
                Text(timeFormatter.string(from: scheduledTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }
            Text(task.title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            statusIcon(for: task.status)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(pastBackground(for: task.status))
        .cornerRadius(8)
    }
    
    private func statusIcon(for status: TaskStatus) -> some View {
        switch status {
        case .completed:
            return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .inProgress:
            return Image(systemName: "clock.fill").foregroundColor(.orange)
        default:
            return Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
        }
    }
    
    private func pastBackground(for status: TaskStatus) -> Color {
        switch status {
        case .completed:
            return Color.green.opacity(0.12)
        case .inProgress:
            return Color.yellow.opacity(0.12)
        default:
            return Color.red.opacity(0.12)
        }
    }
    
    private var taskTimeStatus: TaskTimeStatus {
        guard let scheduledTime = task.scheduledTime,
              let scheduledDate = task.scheduledDate else {
            return .unknown
        }
        let now = Date()
        let calendar = Calendar.current
        
        // Se la task è completata, non considerare lo stato temporale
        if task.status == .completed {
            return .completed
        }
        
        // Verifica che la data della task sia oggi
        let today = calendar.startOfDay(for: now)
        let taskDay = calendar.startOfDay(for: scheduledDate)
        
        // Se la task è di un giorno diverso da oggi, è futura o passata in base alla data
        if taskDay != today {
            if taskDay < today {
                return .past
            } else {
                return .future
            }
        }
        
        // Se è oggi, confronta l'orario
        // Estrai solo l'orario da scheduledTime (ignora la data)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
        
        // Combina la data corretta (scheduledDate) con l'orario estratto
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second ?? 0
        
        guard let taskDateTime = calendar.date(from: dateComponents) else {
            return .unknown
        }
        
        let taskEnd = taskDateTime.addingTimeInterval(task.estimatedDuration)
        
        // Verifica se l'orario è passato (considerando anche la durata)
        if now > taskEnd {
            return .past
        }
        
        // Verifica se l'orario è "in corso" (tra inizio e fine)
        if now >= taskDateTime && now <= taskEnd {
            return .inProgress
        }
        
        // Altrimenti è futura
        return .future
    }
    
    private var todayBackgroundWithState: Color {
        // Colore di base in base allo stato temporale
        switch taskTimeStatus {
        case .future:
            // Task future: colore dello stato con opacità
            return statoColor.opacity(0.18)
        case .inProgress:
            // Task in corso: arancione
            return Color.orange.opacity(0.2)
        case .past:
            // Task passate: rosso
            return Color.red.opacity(0.15)
        case .completed:
            // Task completate: verde chiaro
            return Color.green.opacity(0.12)
        case .unknown:
            return Color(NSColor.controlBackgroundColor)
        }
    }
    
    enum TaskTimeStatus {
        case future
        case inProgress
        case past
        case completed
        case unknown
    }
    
    private func loadSinistro() {
        guard let rif = task.sinistroID else { return }
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", rif)
        if let found = try? context.fetch(request).first {
            sinistro = found
            insuredName = found.nomeAssicuratoCompleto ?? found.nomeAssicurato ?? ""
            sinistroState = found.stato ?? ""
            
            // Verifica se manca la cartella
            folderMissing = FileService.shared.getSinistroPath(riferimento: rif) == nil
            
            // Carica colore e icona dello stato
            if let statoRaw = found.stato,
               let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoRaw || $0.rawValue == statoRaw }) {
                statoColor = stato.color
                statoIcon = stato.icon
            } else {
                statoColor = .blue
                statoIcon = "gearshape"
            }
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    /// Restituisce il riferimento visualizzato (con sigla compagnia se abilitato)
    private func riferimentoVisualizzato(for sinistroID: String) -> String {
        let showSigla = UserDefaults.standard.bool(forKey: "includiCodiceCompagniaRiferimento")
        guard showSigla else { return sinistroID }
        
        // Cerca il sinistro nel contesto
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", sinistroID)
        request.fetchLimit = 1
        
        if let sinistro = try? viewContext.fetch(request).first {
            return sinistro.riferimentoVisualizzato
        }
        
        return sinistroID
    }
    
    /// Verifica se la task può essere spostata più tardi nella stessa giornata
    private func canRescheduleLater(task: DailyTask) -> Bool {
        guard let scheduledTime = task.scheduledTime,
              let scheduledDate = task.scheduledDate else { return false }
        
        let calendar = Calendar.current
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: scheduledDate).sorted { $0.start < $1.start }
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: scheduledDate, time: hours.start),
             end: combineDateTime(targetDate: scheduledDate, time: hours.end))
        }
        
        let taskDuration = task.estimatedDuration
        
        // Verifica se c'è spazio per spostare di 2 ore
        let maxLaterTime = scheduledTime.addingTimeInterval(2 * 3600)
        let maxTaskEnd = maxLaterTime.addingTimeInterval(taskDuration)
        
        // Verifica che sia ancora nella stessa giornata lavorativa
        for slot in workingHours {
            if maxTaskEnd <= slot.end && maxLaterTime >= slot.start && maxLaterTime < slot.end {
                return true
            }
        }
        
        return false
    }
    
    /// Verifica se la task può essere spostata al pomeriggio
    private func canRescheduleToAfternoon(task: DailyTask) -> Bool {
        guard let scheduledTime = task.scheduledTime,
              let scheduledDate = task.scheduledDate else { return false }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: scheduledTime)
        
        // Deve essere al mattino (prima delle 14)
        guard hour < 14 else { return false }
        
        let rawWorkingHours = workScheduleManager.getWorkingHours(for: scheduledDate).sorted { $0.start < $1.start }
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
            (start: combineDateTime(targetDate: scheduledDate, time: hours.start),
             end: combineDateTime(targetDate: scheduledDate, time: hours.end))
        }
        
        let taskDuration = task.estimatedDuration
        let now = Date()
        
        // Trova slot pomeridiano disponibile
        for slot in workingHours {
            let slotHour = calendar.component(.hour, from: slot.start)
            if slotHour >= 14 {
                // Verifica che non sia già passato
                if slot.end <= now { continue }
                
                let taskEnd = slot.start.addingTimeInterval(taskDuration)
                if taskEnd <= slot.end {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Verifica se la task può essere spostata al mattino del giorno dopo
    private func canRescheduleToNextMorning(task: DailyTask) -> Bool {
        guard let scheduledDate = task.scheduledDate else { return false }
        
        let calendar = Calendar.current
        var nextDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        let taskDuration = task.estimatedDuration
        
        // Helper per combinare data e ora
        func combineDateTime(targetDate: Date, time: Date) -> Date {
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = timeComponents.second ?? 0
            return calendar.date(from: dateComponents) ?? targetDate
        }
        
        // Cerca nei prossimi 7 giorni
        for _ in 0..<7 {
            if workScheduleManager.isWorkingDay(nextDate) {
                let rawWorkingHours = workScheduleManager.getWorkingHours(for: nextDate).sorted { $0.start < $1.start }
                let workingHours = rawWorkingHours.map { hours -> (start: Date, end: Date) in
                    (start: combineDateTime(targetDate: nextDate, time: hours.start),
                     end: combineDateTime(targetDate: nextDate, time: hours.end))
                }
                
                // Trova slot mattutino (prima delle 14)
                for slot in workingHours {
                    let slotHour = calendar.component(.hour, from: slot.start)
                    if slotHour < 14 {
                        let taskEnd = slot.start.addingTimeInterval(taskDuration)
                        if taskEnd <= slot.end {
                            return true
                        }
                    }
                }
            }
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }
        
        return false
    }
    
    /// Restituisce l'etichetta per il prossimo giorno lavorativo
    private func nextWorkingDayLabel(for task: DailyTask) -> String {
        let calendar = Calendar.current
        let today = Date()
        var nextDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        
        // Trova prossimo giorno lavorativo
        for _ in 0..<14 {
            if workScheduleManager.isWorkingDay(nextDate) {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
                
                // Se è domani, mostra "Domani"
                if calendar.isDate(nextDate, inSameDayAs: tomorrow) {
                    return "Domani"
                } else {
                    // Altrimenti mostra il nome del giorno
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "it_IT")
                    formatter.dateFormat = "EEEE"
                    let dayName = formatter.string(from: nextDate).capitalized
                    return dayName
                }
            }
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }
        
        return "Domani"
    }
}

