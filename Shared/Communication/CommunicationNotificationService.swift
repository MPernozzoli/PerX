import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

final class CommunicationNotificationService {
    static let shared = CommunicationNotificationService()

    static let categoryIdentifier = "COMMUNICATION_INCOMING_CALL"
    static let answerActionIdentifier = "COMMUNICATION_ANSWER"
    static let answerAndOpenClaimActionIdentifier = "COMMUNICATION_ANSWER_AND_OPEN_CLAIM"
    static let openClaimOnlyActionIdentifier = "COMMUNICATION_OPEN_CLAIM_ONLY"
    static let voicemailActionIdentifier = "COMMUNICATION_SEND_TO_VOICEMAIL_AI_TRIAGE"

    private init() {}

    func registerNotificationCategories() {
        #if canImport(UserNotifications)
        let answer = UNNotificationAction(
            identifier: Self.answerActionIdentifier,
            title: "Rispondi",
            options: [.foreground]
        )
        let answerAndOpenClaim = UNNotificationAction(
            identifier: Self.answerAndOpenClaimActionIdentifier,
            title: "Rispondi e apri sinistro",
            options: [.foreground]
        )
        let openClaimOnly = UNNotificationAction(
            identifier: Self.openClaimOnlyActionIdentifier,
            title: "Apri solo sinistro",
            options: [.foreground]
        )
        let voicemail = UNNotificationAction(
            identifier: Self.voicemailActionIdentifier,
            title: "Manda alla segreteria",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [answerAndOpenClaim, answer, openClaimOnly, voicemail],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        #endif
    }

    func sendIncomingCallNotification(
        sessionId: String,
        callId: String?,
        callerName: String,
        phoneNumber: String?,
        claimContext: CommunicationClaimContext?
    ) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Chiamata in arrivo - \(callerName)"
        if let claimContext {
            let insured = claimContext.insuredName ?? "Assicurato non indicato"
            content.body = "Sinistro \(claimContext.displayReference)\n\(insured)"
        } else if let phoneNumber, !phoneNumber.isEmpty {
            content.body = phoneNumber
        } else {
            content.body = "Comunicazione PerX"
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "communication-\(sessionId)"
        content.userInfo = [
            "type": "communication_incoming_call",
            "sessionId": sessionId,
            "callId": callId ?? "",
            "callerName": callerName,
            "phoneNumber": phoneNumber ?? "",
            "claimId": claimContext?.claimId ?? "",
            "claimReference": claimContext?.displayReference ?? "",
            "claimStatus": claimContext?.claimStatus ?? "",
            "insuredName": claimContext?.insuredName ?? ""
        ]
        let request = UNNotificationRequest(
            identifier: "communication-\(sessionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    func actionType(for notificationActionIdentifier: String) -> CommunicationNotificationActionType? {
        switch notificationActionIdentifier {
        case Self.answerActionIdentifier:
            return .answer
        case Self.answerAndOpenClaimActionIdentifier:
            return .answerAndOpenClaim
        case Self.openClaimOnlyActionIdentifier:
            return .openClaimOnly
        case Self.voicemailActionIdentifier:
            return .sendToVoicemailAITriage
        default:
            return nil
        }
    }
}
