import Foundation
import SwiftUI

class OnboardingService: ObservableObject {
    static let shared = OnboardingService()
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Published var shouldShowOnboarding = false
    
    private init() {
        // Controlla se mostrare l'onboarding al prossimo ciclo
        DispatchQueue.main.async { [weak self] in
            self?.checkOnboarding()
        }
    }
    
    func checkOnboarding() {
        if !hasCompletedOnboarding {
            shouldShowOnboarding = true
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        shouldShowOnboarding = false
    }
    
    func showOnboarding() {
        shouldShowOnboarding = true
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        shouldShowOnboarding = true
    }
}

// MARK: - Onboarding Steps

struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let features: [String]
    let image: String?
    
    init(title: String, description: String, icon: String, features: [String], image: String? = nil) {
        self.title = title
        self.description = description
        self.icon = icon
        self.features = features
        self.image = image
    }
}

extension OnboardingStep {
    static let allSteps: [OnboardingStep] = [
        OnboardingStep(
            title: "Benvenuto in PerX",
            description: "Il sistema di gestione sinistri più completo per periti assicurativi",
            icon: "doc.text.magnifyingglass",
            features: [
                "Gestione completa sinistri",
                "Sincronizzazione email automatica",
                "Calcolo consuntivi e compensi",
                "Programmazione attività"
            ]
        ),
        
        OnboardingStep(
            title: "Dashboard",
            description: "La tua panoramica completa su tutti i sinistri attivi",
            icon: "gauge",
            features: [
                "Statistiche in tempo reale",
                "Promemoria scadenze",
                "Andamento fatturato",
                "Attività recenti"
            ]
        ),
        
        OnboardingStep(
            title: "Sinistri",
            description: "Gestione completa del ciclo di vita dei sinistri",
            icon: "folder",
            features: [
                "Creazione e modifica sinistri",
                "Gestione documentale",
                "Stati personalizzabili",
                "Tag e ricerca avanzata",
                "Visualizzazione file multimediali"
            ]
        ),
        
        OnboardingStep(
            title: "Comunicazioni",
            description: "Sincronizzazione automatica email e WhatsApp",
            icon: "envelope",
            features: [
                "Sincronizzazione Gmail automatica",
                "Associazione email a sinistri",
                "Gestione allegati",
                "Ricerca intelligente",
                "Integrazione WhatsApp"
            ]
        ),
        
        OnboardingStep(
            title: "Consuntivo",
            description: "Calcolo automatico compensi e fatturato",
            icon: "chart.bar",
            features: [
                "Calcolo compensi automatico",
                "Statistiche per compagnia",
                "Export Excel",
                "Grafici andamento",
                "Previsioni fatturato"
            ]
        ),
        
        OnboardingStep(
            title: "Programmazione",
            description: "Gestione calendari e attività",
            icon: "calendar.badge.clock",
            features: [
                "Calendario attività",
                "Scadenze e reminder",
                "Pianificazione sopralluoghi",
                "Vista giornaliera/settimanale"
            ]
        ),
        
        OnboardingStep(
            title: "Impostazioni",
            description: "Personalizza PerX secondo le tue esigenze",
            icon: "gear",
            features: [
                "Configurazione cartelle",
                "Stati personalizzati",
                "Parametri compensi",
                "Integrazione servizi",
                "Sincronizzazione cloud"
            ]
        ),
        
        OnboardingStep(
            title: "Pronti a Iniziare!",
            description: "Completa la configurazione iniziale e inizia a usare PerX",
            icon: "checkmark.circle.fill",
            features: [
                "Configura le cartelle sinistri",
                "Collega Gmail per email",
                "Imposta parametri compensi",
                "Crea il primo sinistro"
            ]
        )
    ]
}
