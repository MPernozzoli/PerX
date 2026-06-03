import SwiftUI
import Combine

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var threads: [ChatThreadDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp: ChatThreadListDTO = try await APIClient.shared.get("/api/v1/internal-chat/threads")
            self.threads = resp.items.sorted { $0.created_at > $1.created_at }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct ChatListView: View {
    @StateObject private var vm = ChatListViewModel()

    var body: some View {
        List {
            ForEach(vm.threads) { thread in
                NavigationLink {
                    ChatThreadView(thread: thread)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thread.title).font(.headline)
                        HStack {
                            Text(thread.thread_type.capitalized)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                            if let claim = thread.claim_id {
                                Text(claim).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(thread.created_at, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if vm.threads.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "Nessun thread",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Nessuna conversazione aperta.")
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Messaggi")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading && vm.threads.isEmpty { ProgressView() }
        }
        .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: { Text(vm.errorMessage ?? "") })
    }
}

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [ChatMessageDTO] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?

    private let threadId: String

    init(threadId: String) { self.threadId = threadId }

    func load() async {
        do {
            let resp: ChatMessageListDTO = try await APIClient.shared.get(
                "/api/v1/internal-chat/threads/\(threadId)/messages"
            )
            self.messages = resp.items.sorted { $0.created_at < $1.created_at }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        do {
            let payload = ChatMessageCreateDTO(body_text: text, message_type: "text")
            let msg: ChatMessageDTO = try await APIClient.shared.post(
                "/api/v1/internal-chat/threads/\(threadId)/messages",
                body: payload
            )
            messages.append(msg)
            draft = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}

struct ChatThreadView: View {
    let thread: ChatThreadDTO
    @StateObject private var vm: ChatThreadViewModel

    init(thread: ChatThreadDTO) {
        self.thread = thread
        _vm = StateObject(wrappedValue: ChatThreadViewModel(threadId: thread.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg, isOwn: msg.sender_user_id == nil ? false : msg.sender_user_id == currentUserKey)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Scrivi un messaggio", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .perxRealtimeChatMessage)) { note in
            guard let tid = note.userInfo?["thread_id"] as? String, tid == thread.id else { return }
            Task { await vm.load() }
        }
        .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: { Text(vm.errorMessage ?? "") })
    }

    private var currentUserKey: String? {
        APIClient.shared.userEmail
    }
}

private struct MessageBubble: View {
    let message: ChatMessageDTO
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.body_text ?? "")
                    .padding(10)
                    .background(isOwn ? Color.accentColor.opacity(0.9) : Color(.secondarySystemBackground))
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(message.created_at, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isOwn { Spacer(minLength: 40) }
        }
    }
}

extension Notification.Name {
    static let perxRealtimeChatMessage = Notification.Name("perxRealtimeChatMessage")
}
