import SwiftUI
import Combine

@MainActor
final class CommunicationsViewModel: ObservableObject {
    @Published var incoming: [IncomingCallDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp: IncomingCallListDTO = try await APIClient.shared.get("/api/v1/communications/incoming")
            self.incoming = resp.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct CommunicationsView: View {
    @StateObject private var vm = CommunicationsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CallListView()
                    } label: {
                        Label("Chiamate", systemImage: "phone.fill")
                    }
                    NavigationLink {
                        EmailListView()
                    } label: {
                        Label("Email", systemImage: "envelope.fill")
                    }
                    NavigationLink {
                        ChatListView()
                    } label: {
                        Label("Messaggi", systemImage: "message.fill")
                    }
                }

                if !vm.incoming.isEmpty {
                    Section("Chiamate in arrivo") {
                        ForEach(vm.incoming) { call in
                            IncomingCallSummaryRow(call: call)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Comunicazioni")
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
            .onReceive(NotificationCenter.default.publisher(for: .perxRealtimeIncomingCall)) { _ in
                Task { await vm.load() }
            }
        }
    }
}

private struct IncomingCallSummaryRow: View {
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
