import SwiftUI

// MARK: - State

/// Singleton that drives the in-app incoming-call banner.
/// Set when an SSE `incoming_call` event arrives while the app is in the foreground.
@MainActor
final class IncomingCallBannerState: ObservableObject {
    static let shared = IncomingCallBannerState()

    @Published private(set) var pendingCall: IncomingCallPayload?
    private var autoDismissTask: Task<Void, Never>?

    private init() {}

    /// Show the banner. Auto-dismisses after 30 s if not acted on.
    func show(_ payload: IncomingCallPayload) {
        pendingCall = payload
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.pendingCall = nil }
        }
    }

    func dismiss() {
        autoDismissTask?.cancel()
        pendingCall = nil
    }
}

// MARK: - Banner View

/// Full-width banner that slides in from the top when an incoming call arrives
/// while the app is in the foreground. NOT a modal — never blocks the current view.
struct IncomingCallBanner: View {
    @ObservedObject private var state = IncomingCallBannerState.shared
    @ObservedObject private var session = CallSessionShared.shared

    var body: some View {
        if let call = state.pendingCall, session.activeSessionId == nil {
            banner(for: call)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func banner(for call: IncomingCallPayload) -> some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "phone.arrow.down.left.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            // Caller info
            VStack(alignment: .leading, spacing: 2) {
                Text("Chiamata in arrivo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(call.callerName.isEmpty ? "Sconosciuto" : call.callerName)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Reject
            Button {
                Task {
                    state.dismiss()
                    // Tell backend the call was rejected
                    struct Body: Encodable { let action_type: String }
                    struct Resp: Decodable { let session_id: String? }
                    _ = try? await APIClient.shared.post(
                        "/api/v1/communications/sessions/\(call.sessionId)/actions",
                        body: Body(action_type: "end")
                    ) as Resp
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rifiuta")

            // Answer
            Button {
                Task {
                    state.dismiss()
                    await CallSessionShared.shared.connect(toSessionId: call.sessionId)
                }
            } label: {
                Image(systemName: "phone.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.green, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rispondi")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
