import SwiftUI
import Combine

@MainActor
final class CallListViewModel: ObservableObject {
    @Published var incoming: [IncomingCallDTO] = []
    @Published var history: [CallHistoryDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let inc: IncomingCallListDTO = APIClient.shared.get("/api/v1/communications/incoming")
            async let hist: CallHistoryListDTO = APIClient.shared.get("/api/v1/communications/sessions?limit=50")
            self.incoming = try await inc.items
            self.history = try await hist.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func dial(phone: String, displayName: String?) async -> String? {
        let req = CommunicationStartRequestDTO(
            destination: .init(
                destination_type: "external_phone",
                transport: "telecom_provider",
                target_id: nil,
                raw_value: phone,
                display_name: displayName
            ),
            context: .init(claim_id: nil)
        )
        do {
            let resp: CommunicationStartResponseDTO = try await APIClient.shared.post(
                "/api/v1/communications/start",
                body: req
            )
            return resp.session_id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}

struct CallListView: View {
    @StateObject private var vm = CallListViewModel()
    @State private var showDial = false

    var body: some View {
        List {
            if !vm.incoming.isEmpty {
                Section("In arrivo") {
                    ForEach(vm.incoming) { call in
                        IncomingCallRow(call: call)
                    }
                }
            }
            if !vm.history.isEmpty {
                Section("Recenti") {
                    ForEach(vm.history) { call in
                        HistoryCallRow(call: call)
                    }
                }
            } else if vm.incoming.isEmpty && !vm.isLoading {
                Section {
                    ContentUnavailableView(
                        "Nessuna chiamata",
                        systemImage: "phone.down",
                        description: Text("Componi un numero per iniziare una chiamata.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chiamate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDial = true } label: { Image(systemName: "phone.fill.arrow.up.right") }
            }
        }
        .sheet(isPresented: $showDial) {
            DialerSheet { phone, name in
                await vm.dial(phone: phone, displayName: name) != nil
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .perxRealtimeIncomingCall)) { _ in
            Task { await vm.load() }
        }
        .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: { Text(vm.errorMessage ?? "") })
    }
}

private struct IncomingCallRow: View {
    let call: IncomingCallDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.arrow.down.left.fill")
                .foregroundStyle(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.display_name ?? "Sconosciuto").font(.headline)
                Text("\(call.transport.capitalized) · \(call.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(call.created_at, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryCallRow: View {
    let call: CallHistoryDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.display_name ?? otherParty ?? "Sconosciuto")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(call.transport.capitalized) · \(call.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(call.created_at, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(call.created_at, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var otherParty: String? {
        call.direction == "inbound" ? call.from_value : call.to_value
    }

    private var icon: String {
        switch (call.direction ?? "", call.state) {
        case ("inbound", let s) where s == "missed" || s == "rejected": return "phone.arrow.down.left"
        case ("inbound", _): return "phone.arrow.down.left.fill"
        case ("outbound", _): return "phone.arrow.up.right.fill"
        default: return "phone"
        }
    }

    private var color: Color {
        switch call.state {
        case "ended", "completed": return .secondary
        case "missed", "rejected", "failed": return .red
        case "ringing", "active": return .green
        default: return .blue
        }
    }
}

private struct DialerSheet: View {
    let onCall: (String, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var phone: String = ""
    @State private var name: String = ""
    @State private var isCalling = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatario") {
                    TextField("Numero di telefono", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Nome (opzionale)", text: $name)
                }
            }
            .navigationTitle("Nuova chiamata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiama") {
                        Task {
                            isCalling = true
                            let ok = await onCall(
                                phone.trimmingCharacters(in: .whitespaces),
                                name.isEmpty ? nil : name
                            )
                            isCalling = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty || isCalling)
                }
            }
        }
    }
}
