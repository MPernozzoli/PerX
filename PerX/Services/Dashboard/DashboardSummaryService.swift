import Foundation
import CoreData

/// Dati di riepilogo per la dashboard (sinistri in gestione, assegnazioni, task per oggi).
@MainActor
final class DashboardSummaryService: ObservableObject {
    static let shared = DashboardSummaryService()
    
    private let lastDashboardOpenKey = "dashboardLastOpenDate"
    private let workSchedule = WorkScheduleManager.shared
    private let calendar = Calendar.current
    
    /// Data oltre cui contare le assegnazioni (ultimo accesso dashboard o inizio giornata).
    var lastOpenDate: Date? {
        get {
            UserDefaults.standard.object(forKey: lastDashboardOpenKey) as? Date
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d, forKey: lastDashboardOpenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastDashboardOpenKey)
            }
        }
    }
    
    /// Chiamare quando la dashboard viene chiusa / si cambia schermata, per aggiornare "dall'ultimo accesso".
    func markDashboardClosed() {
        lastOpenDate = Date()
    }
    
    /// Data di riferimento per contare le assegnazioni: lastOpenDate se valida, altrimenti inizio giornata.
    func referenceDateForAssignments() -> Date {
        if let last = lastOpenDate, calendar.isDate(last, inSameDayAs: Date()) {
            return last
        }
        return calendar.startOfDay(for: Date())
    }
    
    /// Sinistri attualmente in gestione per l'utente corrente (non chiusi, assegnati a me).
    func sinistriInGestione(context: NSManagedObjectContext, userEmail: String?) -> Int {
        guard let email = userEmail?.lowercased(), !email.isEmpty else { return 0 }
        let chiusa = StatoManager.StatoSinistro.chiusa.descrizione
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(
            format: "(assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@) AND (stato != %@ OR stato == nil)",
            email, email, chiusa
        )
        request.includesSubentities = false
        return (try? context.count(for: request)) ?? 0
    }
    
    /// Numero di sinistri assegnati all'utente corrente con dataAssegnazione >= referenceDateForAssignments().
    func assegnazioniDallUltimoAccesso(context: NSManagedObjectContext, userEmail: String?) -> Int {
        guard let email = userEmail?.lowercased(), !email.isEmpty else { return 0 }
        let ref = referenceDateForAssignments()
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(
            format: "(assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@) AND dataAssegnazione >= %@",
            email, email, ref as NSDate
        )
        request.includesSubentities = false
        return (try? context.count(for: request)) ?? 0
    }
    
    /// Task programmate per oggi (prioritarie, da ScheduleManager).
    func taskPerOggi() -> [ScheduledTask] {
        ScheduleManager.shared.distributeTasksInSchedule(for: Date())
    }
    
    /// Oggi è un giorno lavorativo?
    var isWorkingDay: Bool {
        workSchedule.isWorkingDay(Date())
    }
    
    /// Siamo oltre l'orario lavorativo di oggi? (true se non è lavorativo o se ora attuale > fine ultimo slot).
    var isPastWorkingHours: Bool {
        guard workSchedule.isWorkingDay(Date()) else { return true }
        let hours = workSchedule.getWorkingHours(for: Date())
        guard let lastSlot = hours.last else { return false }
        let now = Date()
        let comp = calendar.dateComponents([.hour, .minute], from: lastSlot.end)
        let endToday = calendar.date(bySettingHour: comp.hour ?? 18, minute: comp.minute ?? 0, second: 0, of: calendar.startOfDay(for: now)) ?? now
        return now > endToday
    }
    
    /// Contesto per il messaggio "carino": fine settimana / festivo / dopo orario.
    enum DashboardContext {
        case normal
        case nonWorkingDay
        case pastWorkingHours
    }
    
    var dashboardContext: DashboardContext {
        if !isWorkingDay { return .nonWorkingDay }
        if isPastWorkingHours { return .pastWorkingHours }
        return .normal
    }
}
