//
//  iPadCATProgrammazioneView.swift
//  PerX per iPad
//
//  Programmazione disponibilità CAT: giorni, fasce da 2h e carichi cross-tenant.
//

import SwiftUI

struct iPadCATProgrammazioneView: View {
    @EnvironmentObject private var session: SessionCoordinator
    @StateObject private var store = CATPlanningStore.shared
    @State private var selectedDate = Date()
    @State private var showingEditor = false

    private var selectedMonthDays: [CATAvailabilityDay] {
        store.availability(for: selectedDate)
    }

    private var selectedMonthIdentifier: String {
        let components = Calendar.current.dateComponents([.year, .month], from: selectedDate)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var selectedDay: CATAvailabilityDay? {
        store.availabilityDay(for: selectedDate)
    }

    var body: some View {
        HStack(spacing: 0) {
            calendarColumn
                .frame(width: 390)

            Divider()

            detailColumn
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Programmazione CAT")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Modifica disponibilità", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let selectedDay {
                CATAvailabilityEditorSheet(day: selectedDay) { updatedDay in
                    Task {
                        await store.updateAvailability(updatedDay, for: selectedDate)
                    }
                }
            }
        }
        .task {
            store.configure(for: session.currentUserEmail)
            await store.ensureAvailability(for: selectedDate)
        }
        .task(id: selectedMonthIdentifier) {
            await store.ensureAvailability(for: selectedDate)
        }
    }

    @ViewBuilder
    private var calendarColumn: some View {
        VStack(spacing: 0) {
            monthHeader

            Divider()

            summaryHeader

            CATAvailabilityCalendarGrid(selectedDate: $selectedDate, days: selectedMonthDays)
                .padding()

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Legenda")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 14) {
                    LegendItem(color: .blue.opacity(0.2), label: "Disponibile")
                    LegendItem(color: .gray.opacity(0.2), label: "Non disponibile")
                    LegendItem(color: .green.opacity(0.2), label: "Route confermata")
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var monthHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }

            Spacer()

            VStack(spacing: 4) {
                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Text("\(availableDaysCount) giorni disponibili")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                tag("Solo presenza", color: .orange)
                tag("Slot 2h", color: .blue)
                tag("Margine 50%", color: .teal)
            }

            Text("Le fasce impostate qui guidano il planner mattutino. Nessun percorso può essere proposto fuori dalle finestre disponibili del CAT.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let syncError = store.syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedDay {
            ScrollView {
                VStack(spacing: 20) {
                    selectedDayHeader(selectedDay)
                    availabilityCard(selectedDay)
                    commitmentsCard(selectedDay)
                    plannerHintsCard(selectedDay)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Nessun giorno selezionato",
                systemImage: "calendar",
                description: Text("Seleziona un giorno dal calendario per impostare la disponibilità.")
            )
        }
    }

    private func selectedDayHeader(_ day: CATAvailabilityDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(day.date, format: .dateTime.day().month())
                        .font(.largeTitle.bold())
                    Text(day.isAvailable ? "Disponibilità modificabile per sopralluoghi in presenza." : "Giornata chiusa per nuovi sopralluoghi.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if day.hasConfirmedRoute {
                    tag("Route confermata", color: .green)
                } else if day.isAvailable {
                    tag("Disponibile", color: .blue)
                } else {
                    tag("Non disponibile", color: .gray)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func availabilityCard(_ day: CATAvailabilityDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Fasce disponibilità", systemImage: "clock.badge")
                    .font(.headline)
                Spacer()
                Button("Modifica") {
                    showingEditor = true
                }
                .font(.caption.bold())
            }

            if day.isAvailable, !day.windows.isEmpty {
                ForEach(day.windows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.label)
                            .font(.headline)
                        Text("Margine pianificatore: \(window.expandedLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(14)
                }
            } else {
                ContentUnavailableView(
                    "Nessuna fascia attiva",
                    systemImage: "nosign",
                    description: Text("Il CAT non risulta disponibile per questo giorno.")
                )
            }

            if !day.note.isEmpty {
                Text(day.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func commitmentsCard(_ day: CATAvailabilityDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Impegni multi-tenant", systemImage: "rectangle.3.group.bubble.left")
                .font(.headline)

            if day.externalCommitments.isEmpty {
                Text("Nessun impegno esterno registrato per questo giorno.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(day.externalCommitments) { commitment in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commitment.label)
                                .font(.headline)
                            Text(commitment.tenantName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        tag(commitment.window.label, color: .indigo)
                    }
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(14)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private func plannerHintsCard(_ day: CATAvailabilityDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Lettura planner", systemImage: "wand.and.stars")
                .font(.headline)

            hintRow("Finestre utilizzabili", value: day.windows.isEmpty ? "0" : "\(day.windows.count)")
            hintRow("Margine applicato", value: "\(Int(store.schedulingRules.availabilityTolerancePercent * 100))% per slot")
            hintRow("Fuori zona consentito", value: "entro \(Int(store.schedulingRules.maxOutsideZoneKilometers)) km")
            hintRow("Review tecnica", value: "\(store.schedulingRules.routeReviewWindowMinutes) minuti")

            Divider()

            Text("I sopralluoghi fissati manualmente restano inderogabili. Le eventuali conferme già assegnate bloccano il giorno senza riscrivere le tue finestre.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private var availableDaysCount: Int {
        selectedMonthDays.filter(\.isAvailable).count
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func hintRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }
}

private struct CATAvailabilityCalendarGrid: View {
    @Binding var selectedDate: Date
    let days: [CATAvailabilityDay]

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["L", "M", "M", "G", "V", "S", "D"]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date,
                       let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                        CATAvailabilityCell(
                            date: date,
                            day: day,
                            isSelected: Calendar.current.isDate(selectedDate, inSameDayAs: date)
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                    } else {
                        Color.clear
                            .frame(height: 52)
                    }
                }
            }
        }
    }

    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let adjustedFirstWeekday = (firstWeekday + 5) % 7
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<29

        var result: [Date?] = Array(repeating: nil, count: adjustedFirstWeekday)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                result.append(date)
            }
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }
}

private struct CATAvailabilityCell: View {
    let date: Date
    let day: CATAvailabilityDay
    let isSelected: Bool

    private var backgroundColor: Color {
        if isSelected { return .accentColor }
        if day.hasConfirmedRoute { return .green.opacity(0.2) }
        if day.isAvailable { return .blue.opacity(0.16) }
        return .gray.opacity(0.14)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)

            if Calendar.current.isDateInToday(date) && !isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }

            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.bold())
                    .foregroundColor(isSelected ? .white : .primary)

                if day.isAvailable {
                    Text("\(day.windows.count) slot")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
            }
        }
        .frame(height: 52)
    }
}

private struct CATAvailabilityEditorSheet: View {
    let day: CATAvailabilityDay
    let onSave: (CATAvailabilityDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAvailable = true
    @State private var note = ""
    @State private var editableWindows: [EditableWindow] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Disponibile per sopralluoghi", isOn: $isAvailable)
                }

                if isAvailable {
                    Section("Fasce disponibilità") {
                        ForEach($editableWindows) { $window in
                            HStack {
                                DatePicker(
                                    "Inizio",
                                    selection: $window.start,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                Text("-")

                                DatePicker(
                                    "Fine",
                                    selection: $window.end,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                        }
                        .onDelete { offsets in
                            editableWindows.remove(atOffsets: offsets)
                        }

                        Button {
                            editableWindows.append(
                                EditableWindow(
                                    start: date(hour: 9, minute: 0),
                                    end: date(hour: 11, minute: 0)
                                )
                            )
                        } label: {
                            Label("Aggiungi slot", systemImage: "plus")
                        }
                    }
                }

                Section("Nota") {
                    TextField("Es. indisponibile dopo le 16, solo area primaria...", text: $note, axis: .vertical)
                }

                if day.hasConfirmedRoute {
                    Section {
                        Label("Il giorno ha già una route confermata: le disponibilità restano informative, ma la conferma non viene sovrascritta.", systemImage: "info.circle")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Disponibilità")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let updated = CATAvailabilityDay(
                            date: day.date,
                            isAvailable: isAvailable,
                            windows: isAvailable ? editableWindows.map(\.window) : [],
                            note: note,
                            externalCommitments: day.externalCommitments,
                            hasConfirmedRoute: day.hasConfirmedRoute
                        )
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                isAvailable = day.isAvailable
                note = day.note
                editableWindows = day.windows.map {
                    EditableWindow(
                        start: date(hour: $0.startHour, minute: $0.startMinute),
                        end: date(hour: $0.endHour, minute: $0.endMinute)
                    )
                }
                if editableWindows.isEmpty {
                    editableWindows = [
                        EditableWindow(start: date(hour: 9, minute: 0), end: date(hour: 11, minute: 0))
                    ]
                }
            }
        }
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day.date
        ) ?? day.date
    }
}

private struct EditableWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date

    var window: CATTimeWindow {
        let calendar = Calendar.current
        return CATTimeWindow(
            startHour: calendar.component(.hour, from: start),
            startMinute: calendar.component(.minute, from: start),
            endHour: calendar.component(.hour, from: end),
            endMinute: calendar.component(.minute, from: end)
        )
    }
}
