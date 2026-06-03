import SwiftUI
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var tasks: [TaskDTO] = []
    @Published var events: [CalendarEventDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let tasksReq: [TaskDTO] = APIClient.shared.get("/api/v1/tasks?status=pending,in_progress")
            async let eventsReq: CalendarEventListDTO = APIClient.shared.get("/api/v1/calendar-events")
            self.tasks = try await tasksReq.sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            self.events = try await eventsReq.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct CalendarView: View {
    @StateObject private var vm = CalendarViewModel()

    var body: some View {
        NavigationStack {
            List {
                if !vm.events.isEmpty {
                    Section("Eventi") {
                        ForEach(vm.events) { event in
                            EventRow(event: event)
                        }
                    }
                }
                if !vm.tasks.isEmpty {
                    Section("Task") {
                        ForEach(vm.tasks) { task in
                            TaskRow(task: task)
                        }
                    }
                }
                if vm.tasks.isEmpty && vm.events.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "Nessuna attività",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("Non ci sono task o eventi in programma.")
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Calendario")
            .refreshable { await vm.load() }
            .overlay {
                if vm.isLoading && vm.tasks.isEmpty && vm.events.isEmpty {
                    ProgressView()
                }
            }
            .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
            .task { await vm.load() }
            .onReceive(NotificationCenter.default.publisher(for: .perxRealtimeTaskUpdated)) { _ in
                Task { await vm.load() }
            }
        }
    }
}

private struct TaskRow: View {
    let task: TaskDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                priorityIcon
                Text(task.title).font(.headline)
                Spacer()
                if let due = task.dueDate {
                    Text(due, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let desc = task.description, !desc.isEmpty {
                Text(desc).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(task.status.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                if let ref = task.sinistroRef {
                    Text(ref).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var priorityIcon: some View {
        let color: Color = {
            switch task.priority.lowercased() {
            case "urgent": return .red
            case "high": return .orange
            case "low": return .gray
            default: return .blue
            }
        }()
        return Image(systemName: "circle.fill").foregroundStyle(color).font(.caption)
    }
}

private struct EventRow: View {
    let event: CalendarEventDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.headline)
            HStack {
                Image(systemName: "clock")
                Text(event.starts_at, style: .time)
                Text("–")
                Text(event.ends_at, style: .time)
                Spacer()
                Text(event.starts_at, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let location = event.location, !location.isEmpty {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text(location)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

extension Notification.Name {
    static let perxRealtimeTaskUpdated = Notification.Name("perxRealtimeTaskUpdated")
    static let perxRealtimeClaimUpdated = Notification.Name("perxRealtimeClaimUpdated")
    static let perxRealtimeIncomingCall = Notification.Name("perxRealtimeIncomingCall")
}
