import SwiftUI
import Combine

@MainActor
final class EmailListViewModel: ObservableObject {
    @Published var emails: [EmailDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp: EmailListDTO = try await APIClient.shared.get("/api/v1/emails")
            self.emails = resp.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct EmailListView: View {
    @StateObject private var vm = EmailListViewModel()

    var body: some View {
        List {
            ForEach(vm.emails) { email in
                NavigationLink {
                    EmailDetailView(email: email)
                } label: {
                    EmailRow(email: email)
                }
            }
            if vm.emails.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "Nessuna email",
                    systemImage: "envelope",
                    description: Text("La tua casella è vuota.")
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading && vm.emails.isEmpty { ProgressView() }
        }
        .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: { Text(vm.errorMessage ?? "") })
    }
}

private struct EmailRow: View {
    let email: EmailDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderName).font(.headline).lineLimit(1)
                Spacer()
                Text(email.received_at, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(email.subject ?? "(nessun oggetto)")
                .font(.subheadline)
                .lineLimit(1)
            if let preview = email.body_text?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var senderName: String {
        let addr = email.from_address
        if let lt = addr.firstIndex(of: "<"), addr.startIndex < lt {
            return addr[..<lt].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return addr
    }
}

struct EmailDetailView: View {
    let email: EmailDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(email.subject ?? "(nessun oggetto)")
                    .font(.title3.bold())
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text(email.from_address).font(.subheadline)
                }
                .foregroundStyle(.secondary)
                Text(email.received_at, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Text(email.body_text ?? "")
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
    }
}
