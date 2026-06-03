import SwiftUI
import Combine

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var schedules: [WorkScheduleDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp: WorkScheduleListDTO = try await APIClient.shared.get("/api/v1/work-schedules")
            self.schedules = resp.items.sorted {
                if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
                return $0.start_time < $1.start_time
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func create(_ payload: WorkScheduleCreateDTO) async -> Bool {
        do {
            let _: WorkScheduleDTO = try await APIClient.shared.post("/api/v1/work-schedules", body: payload)
            await load()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

struct ScheduleView: View {
    @StateObject private var vm = ScheduleViewModel()
    @State private var showAdd = false

    private static let weekdayNames = [
        "Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<7, id: \.self) { day in
                    let dayItems = vm.schedules.filter { $0.weekday == day }
                    Section(Self.weekdayNames[day]) {
                        if dayItems.isEmpty {
                            Text("Nessun turno")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(dayItems) { item in
                                ScheduleRow(item: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Programmazione")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                ScheduleAddView { payload in
                    await vm.create(payload)
                }
            }
            .refreshable { await vm.load() }
            .overlay {
                if vm.isLoading && vm.schedules.isEmpty { ProgressView() }
            }
            .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
            .task { await vm.load() }
        }
    }
}

private struct ScheduleRow: View {
    let item: WorkScheduleDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatTime(item.start_time)) – \(formatTime(item.end_time))")
                    .font(.headline.monospacedDigit())
                HStack(spacing: 6) {
                    Text(item.slot_type.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    if let loc = item.location, !loc.isEmpty {
                        Text(loc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func formatTime(_ raw: String) -> String {
        // "HH:mm:ss" → "HH:mm"
        String(raw.prefix(5))
    }
}

private struct ScheduleAddView: View {
    let onSubmit: (WorkScheduleCreateDTO) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var weekday: Int = 0
    @State private var start: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var end: Date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
    @State private var location: String = ""
    @State private var slotType: String = "work"
    @State private var isSubmitting = false

    private let weekdays = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
    private let slotTypes = ["work", "break", "off"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Giorno") {
                    Picker("Giorno", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { Text(weekdays[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Orario") {
                    DatePicker("Inizio", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Fine", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section("Dettagli") {
                    Picker("Tipo", selection: $slotType) {
                        ForEach(slotTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Sede (opzionale)", text: $location)
                }
            }
            .navigationTitle("Nuovo turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await submit() } }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        let payload = WorkScheduleCreateDTO(
            weekday: weekday,
            start_time: timeString(start),
            end_time: timeString(end),
            location: location.isEmpty ? nil : location,
            slot_type: slotType,
            effective_from: nil,
            effective_to: nil
        )
        if await onSubmit(payload) {
            dismiss()
        }
        isSubmitting = false
    }

    private func timeString(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", comps.hour ?? 0, comps.minute ?? 0)
    }
}
