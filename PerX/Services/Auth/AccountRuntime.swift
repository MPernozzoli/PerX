import Foundation

/// Avvia e ferma i servizi in base a ciò che l'account può usare.
@MainActor
enum AccountRuntime {
    static func applyCurrentProfile() {
        let settings = TenantMailSettingsService.shared.settings
        guard settings.tenantSlug != "nuovo-studio" else { return }
        let access = settings.studioAccess
        let signedIn = GoogleAuthService.shared.isAuthenticated

        if signedIn && access.posta {
            MailViewModel.shared.startMonitoring()
        } else {
            MailViewModel.shared.stopMonitoring()
        }

        if signedIn && access.whatsapp && BuildFeatures.localWhatsAppServerEnabled {
            WhatsAppService.shared.start()
            WhatsAppNotificationService.shared.startPolling()
        } else {
            WhatsAppNotificationService.shared.stopPolling()
            WhatsAppService.shared.stop()
        }

        if signedIn {
            RegiaWorker.shared.start()
        } else {
            RegiaWorker.shared.stop()
        }

        if signedIn && !access.singleOperator {
            PassiveTriggerService.shared.startMonitoring()
        } else {
            PassiveTriggerService.shared.stopMonitoring()
        }
    }

    static func stopAll() {
        MailViewModel.shared.stopMonitoring()
        RegiaWorker.shared.stop()
        WhatsAppNotificationService.shared.stopPolling()
        WhatsAppService.shared.stop()
        PassiveTriggerService.shared.stopMonitoring()
    }
}
