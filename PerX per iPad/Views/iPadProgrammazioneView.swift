//
//  iPadProgrammazioneView.swift
//  PerX per iPad
//
//  Vista programmazione lavoro con calendario e task.
//

import SwiftUI

struct iPadProgrammazioneView: View {
    @EnvironmentObject var session: SessionCoordinator
    @State private var selectedDate = Date()
    @State private var tasks: [ProgrammazioneTask] = []
    @State private var showingAddTask = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Calendar
            calendarSection
                .frame(width: 350)
            
            Divider()
            
            // Right: Tasks for selected day
            taskListSection
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Programmazione")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(selectedDate: selectedDate) { task in
                tasks.append(task)
            }
        }
    }
    
    // MARK: - Calendar
    
    @ViewBuilder
    private var calendarSection: some View {
        VStack(spacing: 0) {
            // Month header
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                }
                
                Spacer()
                
                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(.headline)
                
                Spacer()
                
                Button {
                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding()
            
            Divider()
            
            // Calendar grid
            CalendarGridView(selectedDate: $selectedDate, tasksPerDay: tasksPerDay)
                .padding()
            
            Spacer()
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                Text("Legenda")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    LegendItem(color: .blue, label: "Task")
                    LegendItem(color: .orange, label: "Scadenza")
                    LegendItem(color: .green, label: "Completate")
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Task List
    
    @ViewBuilder
    private var taskListSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate, format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(selectedDate, format: .dateTime.day().month())
                        .font(.title.bold())
                }
                
                Spacer()
                
                if Calendar.current.isDateInToday(selectedDate) {
                    Text("Oggi")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            
            Divider()
            
            // Tasks
            if tasksForSelectedDay.isEmpty {
                ContentUnavailableView(
                    "Nessuna attività",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Non ci sono attività programmate per questo giorno")
                )
            } else {
                List {
                    ForEach(tasksForSelectedDay) { task in
                        ProgrammazioneTaskRow(task: task)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var tasksForSelectedDay: [ProgrammazioneTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            calendar.isDate(task.date, inSameDayAs: selectedDate)
        }
    }
    
    private var tasksPerDay: [Date: Int] {
        var result: [Date: Int] = [:]
        let calendar = Calendar.current
        
        for task in tasks {
            let day = calendar.startOfDay(for: task.date)
            result[day, default: 0] += 1
        }
        
        return result
    }
}

// MARK: - Models

struct ProgrammazioneTask: Identifiable {
    let id: String
    let title: String
    let description: String
    let date: Date
    let sinistroRif: String?
    var isCompleted: Bool
    let type: TaskType
    
    enum TaskType {
        case task, deadline, appointment
        
        var color: Color {
            switch self {
            case .task: return .blue
            case .deadline: return .orange
            case .appointment: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .task: return "checkmark.circle"
            case .deadline: return "exclamationmark.circle"
            case .appointment: return "calendar"
            }
        }
    }
}

// MARK: - Subviews

struct CalendarGridView: View {
    @Binding var selectedDate: Date
    let tasksPerDay: [Date: Int]
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["L", "M", "M", "G", "V", "S", "D"]
    
    var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }
            
            // Days grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            taskCount: tasksPerDay[Calendar.current.startOfDay(for: date)] ?? 0
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }
    
    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let adjustedFirstWeekday = (firstWeekday + 5) % 7 // Adjust for Monday start
        
        let range = calendar.range(of: .day, in: .month, for: monthStart)!
        
        var days: [Date?] = Array(repeating: nil, count: adjustedFirstWeekday)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        
        // Pad to complete weeks
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let taskCount: Int
    
    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
            } else if isToday {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                if taskCount > 0 {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(height: 44)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ProgrammazioneTaskRow: View {
    let task: ProgrammazioneTask
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.type.icon)
                .foregroundColor(task.isCompleted ? .green : task.type.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted)
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if let rif = task.sinistroRif {
                        Label(rif, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Label(task.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct AddTaskSheet: View {
    let selectedDate: Date
    let onAdd: (ProgrammazioneTask) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var time = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Titolo", text: $title)
                    TextField("Descrizione", text: $description)
                }
                
                Section("Data e ora") {
                    DatePicker("Ora", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Nuova attività")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.hour, .minute], from: time)
                        let taskDate = calendar.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0, second: 0, of: selectedDate) ?? selectedDate
                        
                        let task = ProgrammazioneTask(
                            id: UUID().uuidString,
                            title: title,
                            description: description,
                            date: taskDate,
                            sinistroRif: nil,
                            isCompleted: false,
                            type: .task
                        )
                        
                        onAdd(task)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
