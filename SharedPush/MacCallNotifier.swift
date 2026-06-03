#if os(macOS)
import Foundation
import UserNotifications
import AppKit

/// macOS replacement for CallKit. Shows a system notification with custom
/// actions "Rispondi", "Apri sinistro", "Rifiuta". Reusable for incoming
/// calls coming from the unified communications layer (LiveKit) AND for
/// external phone calls routed through the telecom provider.
@MainActor
public final class MacCallNotifier: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = MacCallNotifier()

    public var onAnswer: ((String) async -> Void)?
    public var onAnswerAndOpenClaim: ((String, String?) async -> Void)?
    public var onOpenClaimOnly: ((String, String?) async -> Void)?
    public var onDecline: ((String) async -> Void)?

    private static let incomingCallCategoryWithClaim = "perx_incoming_call_with_claim"
    private static let incomingCallCategoryPlain = "perx_incoming_call_plain"

    /// Storage for the claim_id associated to a pending notification, keyed by
    /// session_id. Userinfo on the notification carries it too — kept here for
    /// faster dispatch.
    private var pendingClaim: [String: String] = [:]

    private override init() { super.init() }

    public func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let answer = UNNotificationAction(
            identifier: "perx.answer",
            title: "Rispondi",
            options: [.foreground]
        )
        let answerAndOpen = UNNotificationAction(
            identifier: "perx.answer_open_claim",
            title: "Rispondi e apri sinistro",
            options: [.foreground]
        )
        let openOnly = UNNotificationAction(
            identifier: "perx.open_claim",
            title: "Apri sinistro",
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: "perx.decline",
            title: "Rifiuta",
            options: [.destructive]
        )

        let withClaim = UNNotificationCategory(
            identifier: Self.incomingCallCategoryWithClaim,
            actions: [answer, answerAndOpen, openOnly, decline],
            intentIdentifiers: [],
            options: []
        )
        let plain = UNNotificationCategory(
            identifier: Self.incomingCallCategoryPlain,
            actions: [answer, decline],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([withClaim, plain])

        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    public func presentIncomingCall(_ payload: IncomingCallPayload) {
        if let claim = payload.claimId, !claim.isEmpty {
            pendingClaim[payload.sessionId] = claim
        }

        let content = UNMutableNotificationContent()
        content.title = "Chiamata in arrivo"
        content.subtitle = payload.callerName
        if !payload.callerHandle.isEmpty {
            content.body = payload.callerHandle
        }
        if let claim = payload.claimId {
            content.body += content.body.isEmpty ? "Sinistro: \(claim)" : "\nSinistro: \(claim)"
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = (payload.claimId?.isEmpty ?? true)
            ? Self.incomingCallCategoryPlain
            : Self.incomingCallCategoryWithClaim
        content.userInfo = [
            "session_id": payload.sessionId,
            "claim_id": payload.claimId as Any,
            "has_video": payload.hasVideo,
        ]

        let request = UNNotificationRequest(
            identifier: "perx.incoming_call.\(payload.sessionId)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Mac incoming-call notification failed: \(error)")
            }
        }
    }

    public func dismiss(sessionId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["perx.incoming_call.\(sessionId)"]
        )
        pendingClaim.removeValue(forKey: sessionId)
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let sessionId = (info["session_id"] as? String) ?? ""
        let claimId = info["claim_id"] as? String

        Task { @MainActor in
            switch response.actionIdentifier {
            case "perx.answer":
                await onAnswer?(sessionId)
            case "perx.answer_open_claim":
                await onAnswerAndOpenClaim?(sessionId, claimId)
            case "perx.open_claim":
                await onOpenClaimOnly?(sessionId, claimId)
            case "perx.decline":
                await onDecline?(sessionId)
            case UNNotificationDefaultActionIdentifier:
                await onAnswer?(sessionId)
            default:
                break
            }
            dismiss(sessionId: sessionId)
            completionHandler()
        }
    }
}
#endif
