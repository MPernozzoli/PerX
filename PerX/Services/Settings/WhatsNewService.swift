import Foundation
import SwiftUI

struct AppUpdate: Codable, Identifiable {
    let id: String
    let version: String
    let date: Date
    let features: [Feature]
    let knownProblems: [KnownProblem]?
    let whatsNext: [WhatsNext]?
    
    struct Feature: Codable, Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let color: String
        
        var colorValue: Color {
            switch color {
            case "purple": return .purple
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "pink": return .pink
            case "indigo": return .indigo
            case "red": return .red
            case "yellow": return .yellow
            case "teal": return .teal
            case "cyan": return .cyan
            default: return .blue
            }
        }
    }
    
    struct KnownProblem: Codable, Identifiable {
        let id = UUID()
        let icon: String
        let description: String
    }
    
    struct WhatsNext: Codable, Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }
}

@MainActor
class WhatsNewService: ObservableObject {
    static let shared = WhatsNewService()
    
    @Published private(set) var hasUnseenUpdates = false
    @Published private(set) var latestUpdate: AppUpdate?
    
    private let userDefaults = UserDefaults.standard
    private let seenUpdatesKey = "seenUpdates"
    
    // Lista di tutti gli aggiornamenti
    private let updates: [AppUpdate] = [
        AppUpdate(
            id: "2026.01.23",
            version: "2.0",
            date: Date(),
            features: [
                AppUpdate.Feature(
                    icon: "moon.stars.fill",
                    title: "Welcome bLack",
                    description: "Supporto completo alla dark mode per lavorare anche di notte senza stancarsi gli occhi",
                    color: "indigo"
                ),
                AppUpdate.Feature(
                    icon: "folder.fill.badge.plus",
                    title: "Cartelle Integrate",
                    description: "Le cartelle dei sinistri sono ora completamente integrate nell'app, non più bisogno di aprirle esternamente",
                    color: "blue"
                ),
                AppUpdate.Feature(
                    icon: "checklist",
                    title: "Task Avanzati",
                    description: "Nuova gestione dei task con priorità, date di scadenza e organizzazione migliorata",
                    color: "green"
                ),
                AppUpdate.Feature(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Messaggi Ripensati",
                    description: "Interfaccia completamente rinnovata per email e messaggi, più moderna e intuitiva",
                    color: "purple"
                ),
                AppUpdate.Feature(
                    icon: "chart.bar.fill",
                    title: "Conteggi Corretti",
                    description: "I counter del consuntivo ora mostrano i dati precisi, finalmente affidabili al 100%",
                    color: "orange"
                ),
                AppUpdate.Feature(
                    icon: "arrow.up.arrow.down",
                    title: "Ordinamento Sinistri",
                    description: "I sinistri nella vista principale ora possono essere ordinati come preferisci",
                    color: "pink"
                ),
                AppUpdate.Feature(
                    icon: "exclamationmark.triangle.fill",
                    title: "Priorità Intelligente",
                    description: "Sistema automatico che calcola l'urgenza dei sinistri in base a vecchiaia, complessità, obiettivi e solleciti per organizzare meglio il lavoro",
                    color: "red"
                )
            ],
            knownProblems: [
                AppUpdate.KnownProblem(
                    icon: "envelope.badge.fill",
                    description: "Errori nel download delle mail"
                ),
                AppUpdate.KnownProblem(
                    icon: "brain.head.profile",
                    description: "La funzione di autotag IA delle foto non risponde"
                ),
                AppUpdate.KnownProblem(
                    icon: "list.number",
                    description: "I conteggi della perizia sono corretti ma non compaiono nel riepilogo sinistro"
                ),
                AppUpdate.KnownProblem(
                    icon: "doc.text.fill",
                    description: "Gli atti non sono generati correttamente"
                )
            ],
            whatsNext: [
                AppUpdate.WhatsNext(
                    icon: "envelope.arrow.triangle.branch",
                    title: "Mail 3.0",
                    description: "Rifacimento completo del sistema mail con sincronizzazione istantanea"
                ),
                AppUpdate.WhatsNext(
                    icon: "message.fill",
                    title: "WhatsApp Business",
                    description: "Integrazione completa di WhatsApp per comunicare direttamente dall'app"
                ),
                AppUpdate.WhatsNext(
                    icon: "building.2.fill",
                    title: "Unipol Inside",
                    description: "Supporto completo per tutti i processi Unipol"
                ),
                AppUpdate.WhatsNext(
                    icon: "person.2.fill",
                    title: "Rubrica Agenzie",
                    description: "Gestione centralizzata di tutte le agenzie e contatti"
                ),
                AppUpdate.WhatsNext(
                    icon: "calendar.badge.clock",
                    title: "Mail Scheduler",
                    description: "Programmazione intelligente dell'invio delle mail"
                ),
                AppUpdate.WhatsNext(
                    icon: "bolt.fill",
                    title: "One-Click Magic",
                    description: "Automazioni per inviare mail e WhatsApp con un solo click"
                )
            ]
        )
    ]
    
    private init() {
        checkForUpdates()
    }
    
    func checkForUpdates() {
        guard let latest = updates.first else { return }
        latestUpdate = latest
        
        let seenIds = getSeenUpdateIds()
        hasUnseenUpdates = !seenIds.contains(latest.id)
    }
    
    func markUpdateAsSeen(_ updateId: String) {
        var seenIds = getSeenUpdateIds()
        if !seenIds.contains(updateId) {
            seenIds.append(updateId)
            if let data = try? JSONEncoder().encode(seenIds) {
                userDefaults.set(data, forKey: seenUpdatesKey)
            }
            checkForUpdates()
        }
    }
    
    private func getSeenUpdateIds() -> [String] {
        guard let data = userDefaults.data(forKey: seenUpdatesKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
    
    func resetSeenUpdates() {
        userDefaults.removeObject(forKey: seenUpdatesKey)
        checkForUpdates()
    }
}
