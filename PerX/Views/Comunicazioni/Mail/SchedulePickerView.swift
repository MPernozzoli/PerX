import SwiftUI

/// View per selezionare data e ora di invio programmato
struct SchedulePickerView: View {
    @Binding var scheduledDate: Date
    @Binding var isScheduled: Bool
    let onConfirm: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Preset di date comuni
    private let presets: [(String, Date)] = {
        let calendar = Calendar.current
        let now = Date()
        
        var presets: [(String, Date)] = []
        
        // Tra 1 ora
        if let oneHour = calendar.date(byAdding: .hour, value: 1, to: now) {
            presets.append(("Tra 1 ora", oneHour))
        }
        
        // Domani mattina alle 9
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrowMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            presets.append(("Domani alle 9:00", tomorrowMorning))
        }
        
        // Lunedì prossimo alle 9
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilMonday = weekday == 1 ? 1 : (9 - weekday) % 7
        if daysUntilMonday > 0,
           let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: now),
           let mondayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMonday) {
            presets.append(("Lunedì alle 9:00", mondayMorning))
        }
        
        return presets
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Programma invio")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Preset rapidi
            VStack(alignment: .leading, spacing: 8) {
                Text("Opzioni rapide")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(presets, id: \.0) { preset in
                    Button(action: {
                        scheduledDate = preset.1
                        isScheduled = true
                        onConfirm()
                    }) {
                        HStack {
                            Image(systemName: "clock")
                            Text(preset.0)
                            Spacer()
                            Text(formatDate(preset.1))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Selezione personalizzata
            VStack(alignment: .leading, spacing: 12) {
                Text("Oppure scegli data e ora")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                DatePicker(
                    "Invia il",
                    selection: $scheduledDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
            }
            
            Spacer()
            
            // Pulsanti
            HStack {
                Button("Annulla") {
                    isScheduled = false
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Conferma") {
                    isScheduled = true
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(scheduledDate <= Date())
            }
        }
        .padding()
        .frame(width: 350, height: 500)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
}

#Preview {
    SchedulePickerView(
        scheduledDate: .constant(Date().addingTimeInterval(3600)),
        isScheduled: .constant(false),
        onConfirm: {}
    )
}
