import SwiftUI

/// Prompt per la programmazione intelligente di messaggi/email
/// Mostrato quando si tenta di inviare fuori dall'orario lavorativo
struct SmartSchedulePromptView: View {
    let reason: SmartScheduleService.ScheduleReason
    @Binding var suggestedDate: Date
    let contextId: String? // sinistroRef o conversationId
    let messageType: String // "email" o "messaggio"
    
    let onSendNow: () -> Void
    let onSchedule: (Date) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferences = SmartSchedulePreferences.shared
    @State private var showCustomDatePicker = false
    @State private var savePreference = false
    
    private let scheduleService = SmartScheduleService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Opzioni
            ScrollView {
                VStack(spacing: 12) {
                    // Opzione 1: Invia in seguito (default)
                    sendLaterOption
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Opzione 2: Ignora per questa volta
                    ignoreOnceOption
                    
                    // Opzione 3: Ignora per questo sinistro/conversazione
                    if contextId != nil {
                        ignoreContextOption
                    }
                    
                    // Opzione 4: Ignora per oggi
                    ignoreTodayOption
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Opzione 5: Annulla
                    cancelOption
                }
                .padding(.vertical, 16)
            }
            
            Divider()
            
            // Footer con opzione salva preferenza
            footerView
        }
        .frame(width: 420, height: 500)
        .sheet(isPresented: $showCustomDatePicker) {
            CustomScheduleDatePicker(
                selectedDate: $suggestedDate,
                onConfirm: {
                    showCustomDatePicker = false
                    performSchedule()
                },
                onCancel: {
                    showCustomDatePicker = false
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                
                Text("Invio \(reason.shortDescription)")
                    .font(.headline)
                
                Text("Stai inviando \(articleFor(messageType)) \(messageType) \(reason.description).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            
            // Pulsante chiudi
            Button {
                dismiss()
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Options
    
    private var sendLaterOption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                performSchedule()
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invia in seguito")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text(formatScheduleDate(suggestedDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Consigliato")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            
            // Personalizza
            Button {
                showCustomDatePicker = true
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                    Text("Personalizza data e ora...")
                        .font(.caption)
                    Spacer()
                }
                .foregroundColor(.blue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
    }
    
    private var ignoreOnceOption: some View {
        Button {
            scheduleService.ignoreForThisTime()
            dismiss()
            onSendNow()
        } label: {
            HStack {
                Image(systemName: "forward")
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignora per questa volta")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Solo quest\(articleFor(messageType, article: "o")) \(messageType). Ricomparirà al prossimo invio.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
    }
    
    private var ignoreContextOption: some View {
        Button {
            if let contextId = contextId {
                scheduleService.ignoreForContext(contextId)
            }
            dismiss()
            onSendNow()
        } label: {
            HStack {
                Image(systemName: "folder.badge.minus")
                    .foregroundColor(.purple)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignora per questo sinistro")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Non verrà più chiesto per questa pratica/conversazione.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
    }
    
    private var ignoreTodayOption: some View {
        Button {
            scheduleService.ignoreForToday()
            dismiss()
            onSendNow()
        } label: {
            HStack {
                Image(systemName: "moon.zzz")
                    .foregroundColor(.indigo)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignora per oggi")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Fino a mezzanotte non verranno più mostrati avvisi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
    }
    
    private var cancelOption: some View {
        Button {
            dismiss()
            onCancel()
        } label: {
            HStack {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
                    .frame(width: 24)
                
                Text("Annulla invio")
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        VStack(spacing: 12) {
            // Toggle per usare orario personale
            Toggle(isOn: Binding(
                get: { preferences.usePersonalSchedule },
                set: { preferences.usePersonalSchedule = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usa il mio orario di lavoro")
                        .font(.subheadline)
                    Text("Programma in base agli orari definiti nelle impostazioni")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            
            Divider()
            
            // Toggle per ricordare scelta
            Toggle(isOn: $savePreference) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ricorda la mia scelta")
                        .font(.subheadline)
                    if preferences.usePersonalSchedule {
                        Text("L'invio verrà automaticamente programmato secondo il tuo orario")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("L'invio verrà automaticamente programmato alle \(preferences.defaultScheduleTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: savePreference) { _, newValue in
                if newValue {
                    scheduleService.enableAutoSchedule()
                } else {
                    scheduleService.disableAutoSchedule()
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func performSchedule() {
        dismiss()
        onSchedule(suggestedDate)
    }
    
    private func formatScheduleDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMMM 'alle ore' HH:mm"
        return formatter.string(from: date).capitalized
    }
    
    private func articleFor(_ word: String, article: String = "a") -> String {
        // Articolo per "email" vs "messaggio"
        if word.lowercased() == "email" {
            return article == "o" ? "a" : "un'"
        }
        return article == "o" ? "o" : "un"
    }
}

// MARK: - Custom Date Picker

struct CustomScheduleDatePicker: View {
    @Binding var selectedDate: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var timeString: String = "08:00"
    @StateObject private var preferences = SmartSchedulePreferences.shared
    
    private let scheduleService = SmartScheduleService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Personalizza programmazione")
                .font(.headline)
            
            // Preset rapidi
            VStack(alignment: .leading, spacing: 8) {
                Text("Opzioni rapide")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(quickPresets, id: \.label) { preset in
                        Button(action: {
                            selectedDate = preset.date
                            updateTimeString()
                        }) {
                            VStack(spacing: 4) {
                                Text(preset.label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(formatShortDate(preset.date))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider()
            
            // Date picker
            DatePicker(
                "Data",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            
            // Time picker
            HStack {
                Text("Ora:")
                TextField("HH:mm", text: $timeString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: timeString) { _, newValue in
                        applyTimeString(newValue)
                    }
                
                Spacer()
                
                // Mostra avviso se non è giorno lavorativo
                if !scheduleService.isWorkingDay(selectedDate) {
                    Label("Non lavorativo", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Salva come default
            Toggle("Usa sempre questo orario", isOn: Binding(
                get: { preferences.autoScheduleEnabled },
                set: { newValue in
                    if newValue {
                        preferences.defaultScheduleTime = timeString
                        preferences.autoScheduleEnabled = true
                    } else {
                        preferences.autoScheduleEnabled = false
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            
            Spacer()
            
            HStack {
                Button("Annulla") { onCancel() }
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Conferma") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 380, height: 550)
        .onAppear {
            updateTimeString()
        }
    }
    
    private var quickPresets: [(label: String, date: Date)] {
        let now = Date()
        var presets: [(String, Date)] = []
        
        // Prossimo slot lavorativo
        let nextWorking = scheduleService.calculateNextWorkingTime(from: now)
        presets.append(("Prossimo orario", nextWorking))
        
        // Domani alle 08:00
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrow8 = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) {
            presets.append(("Domani 08:00", tomorrow8))
        }
        
        // Domani alle 14:00
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrow14 = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) {
            presets.append(("Domani 14:00", tomorrow14))
        }
        
        // Lunedì prossimo
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilMonday = weekday == 1 ? 1 : (9 - weekday) % 7
        if daysUntilMonday > 0,
           let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: now),
           let monday8 = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextMonday) {
            presets.append(("Lunedì 08:00", monday8))
        }
        
        return presets
    }
    
    private func updateTimeString() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeString = formatter.string(from: selectedDate)
    }
    
    private func applyTimeString(_ time: String) {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else {
            return
        }
        
        let calendar = Calendar.current
        if let newDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEE d/M HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Scheduled Message Overlay

/// Overlay da mostrare quando un messaggio è programmato
struct ScheduledMessageOverlay: View {
    let scheduledFor: Date
    let onSendNow: () -> Void
    let onEditSchedule: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Invio programmato")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(formatDate(scheduledFor))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Invia ora") {
                onSendNow()
            }
            .buttonStyle(.bordered)
            
            Button(action: onEditSchedule) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            
            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .foregroundColor(.orange.opacity(0.5))
        )
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMMM 'alle' HH:mm"
        return formatter.string(from: date).capitalized
    }
}

// Preview disponibile quando SmartScheduleService è compilato
// #Preview {
//     SmartSchedulePromptView(
//         reason: .afterHours,
//         suggestedDate: .constant(Date().addingTimeInterval(43200)),
//         contextId: "2500001",
//         messageType: "email",
//         onSendNow: {},
//         onSchedule: { _ in },
//         onCancel: {}
//     )
// }
