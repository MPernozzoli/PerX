import Foundation
import SwiftUI
import Combine

/// Servizio per la programmazione intelligente di email e messaggi
/// Suggerisce di programmare l'invio quando siamo fuori dagli orari lavorativi
@MainActor
class SmartScheduleService: ObservableObject {
    static let shared = SmartScheduleService()
    
    // MARK: - Published State
    
    @Published var showingPrompt = false
    @Published var pendingAction: PendingAction?
    
    // MARK: - Preferences
    
    private let preferences = SmartSchedulePreferences.shared
    private let calendarService = ItalianCalendarService.shared
    private let workScheduleManager = WorkScheduleManager.shared
    private let calendar = Calendar(identifier: .gregorian)
    
    // MARK: - Configuration
    
    /// Orario inizio giornata lavorativa di default (08:00)
    private let defaultWorkdayStartHour = 8
    private let defaultWorkdayStartMinute = 0
    
    /// Orario fine giornata lavorativa di default (19:30)
    private let defaultWorkdayEndHour = 19
    private let defaultWorkdayEndMinute = 30
    
    private init() {}
    
    // MARK: - Public API
    
    /// Risultato della valutazione se serve scheduling
    enum ScheduleEvaluation {
        case sendNow                    // Invia subito (orario lavorativo)
        case shouldPrompt(suggestedTime: Date, reason: ScheduleReason)  // Mostra prompt
        case autoSchedule(scheduledFor: Date)  // Auto-schedule (preferenza salvata)
    }
    
    /// Motivo per cui si suggerisce lo scheduling
    enum ScheduleReason {
        case afterHours     // Dopo le 19:30
        case beforeHours    // Prima delle 08:00
        case sunday         // Domenica
        case holiday        // Festivo
        
        var description: String {
            switch self {
            case .afterHours: return "dopo l'orario lavorativo (19:30)"
            case .beforeHours: return "prima dell'orario lavorativo (08:00)"
            case .sunday: return "di domenica"
            case .holiday: return "in un giorno festivo"
            }
        }
        
        var shortDescription: String {
            switch self {
            case .afterHours: return "Fuori orario"
            case .beforeHours: return "Fuori orario"
            case .sunday: return "Domenica"
            case .holiday: return "Festivo"
            }
        }
    }
    
    /// Azione in attesa (email o WhatsApp)
    struct PendingAction {
        let type: ActionType
        let context: ActionContext
        let suggestedTime: Date
        let reason: ScheduleReason
        let onSendNow: () -> Void
        let onSchedule: (Date) -> Void
        let onCancel: () -> Void
        
        enum ActionType {
            case email
            case whatsapp
        }
        
        struct ActionContext {
            let sinistroRef: String?
            let conversationId: String?  // Per WhatsApp
        }
    }
    
    /// Valuta se l'invio richiede scheduling
    func evaluateSend(
        for type: PendingAction.ActionType,
        sinistroRef: String?,
        conversationId: String?
    ) -> ScheduleEvaluation {
        let now = Date()
        
        // Check: ignora per oggi
        if preferences.isIgnoredForToday() {
            return .sendNow
        }
        
        // Check: ignora per sinistro/conversazione
        let contextId = sinistroRef ?? conversationId
        if let contextId = contextId, preferences.isIgnoredForContext(contextId) {
            return .sendNow
        }
        
        // Check: orario lavorativo?
        guard let reason = getScheduleReason(for: now) else {
            return .sendNow
        }
        
        // Calcola prossimo orario lavorativo
        let suggestedTime = calculateNextWorkingTime(from: now)
        
        // Check: ha una preferenza salvata per auto-schedule?
        if preferences.autoScheduleEnabled {
            return .autoSchedule(scheduledFor: suggestedTime)
        }
        
        return .shouldPrompt(suggestedTime: suggestedTime, reason: reason)
    }
    
    /// Calcola il prossimo orario lavorativo
    func calculateNextWorkingTime(from date: Date) -> Date {
        // Se usa orario personale, delega a WorkScheduleManager
        if preferences.usePersonalSchedule {
            return calculateNextWorkingTimeFromPersonalSchedule(from: date)
        }
        
        // Altrimenti usa le regole di default
        return calculateNextWorkingTimeDefault(from: date)
    }
    
    /// Calcola prossimo orario usando le regole di default (08:00-19:30, no domeniche/festivi)
    private func calculateNextWorkingTimeDefault(from date: Date) -> Date {
        var targetDate = date
        
        let hour = calendar.component(.hour, from: targetDate)
        let minute = calendar.component(.minute, from: targetDate)
        
        if hour > defaultWorkdayEndHour || (hour == defaultWorkdayEndHour && minute >= defaultWorkdayEndMinute) {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!
            targetDate = calendar.date(bySettingHour: defaultWorkdayStartHour, minute: defaultWorkdayStartMinute, second: 0, of: targetDate)!
        } else if hour < defaultWorkdayStartHour {
            targetDate = calendar.date(bySettingHour: defaultWorkdayStartHour, minute: defaultWorkdayStartMinute, second: 0, of: targetDate)!
        }
        
        // Trova il prossimo giorno lavorativo (no domenica, no festivi)
        while !isWorkingDayDefault(targetDate) {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!
            targetDate = calendar.date(bySettingHour: defaultWorkdayStartHour, minute: defaultWorkdayStartMinute, second: 0, of: targetDate)!
        }
        
        return targetDate
    }
    
    /// Calcola prossimo orario usando WorkScheduleManager personale
    private func calculateNextWorkingTimeFromPersonalSchedule(from date: Date) -> Date {
        var targetDate = date
        var maxIterations = 365 // Protezione contro loop infinito
        
        while maxIterations > 0 {
            maxIterations -= 1
            
            // Verifica se oggi è lavorativo secondo WorkScheduleManager
            if workScheduleManager.isWorkingDay(targetDate) {
                let workingHours = workScheduleManager.getWorkingHours(for: targetDate)
                
                if !workingHours.isEmpty {
                    // Cerca la prima fascia oraria disponibile
                    let currentHour = calendar.component(.hour, from: targetDate)
                    let currentMinute = calendar.component(.minute, from: targetDate)
                    
                    for slot in workingHours.sorted(by: { 
                        calendar.component(.hour, from: $0.start) < calendar.component(.hour, from: $1.start)
                    }) {
                        let startHour = calendar.component(.hour, from: slot.start)
                        let startMinute = calendar.component(.minute, from: slot.start)
                        let endHour = calendar.component(.hour, from: slot.end)
                        let endMinute = calendar.component(.minute, from: slot.end)
                        
                        // Se siamo prima dell'inizio di questo slot
                        if currentHour < startHour || (currentHour == startHour && currentMinute < startMinute) {
                            // Imposta all'inizio di questo slot
                            return calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: targetDate)!
                        }
                        
                        // Se siamo dentro questo slot
                        if (currentHour > startHour || (currentHour == startHour && currentMinute >= startMinute)) &&
                           (currentHour < endHour || (currentHour == endHour && currentMinute < endMinute)) {
                            // Siamo già in orario lavorativo - ritorna l'ora corrente
                            return targetDate
                        }
                    }
                }
            }
            
            // Nessun slot disponibile oggi, vai al giorno successivo
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate)!
            targetDate = calendar.startOfDay(for: targetDate)
        }
        
        // Fallback: primo giorno successivo alle 08:00
        return calculateNextWorkingTimeDefault(from: date)
    }
    
    /// Verifica se una data è un giorno lavorativo
    func isWorkingDay(_ date: Date) -> Bool {
        if preferences.usePersonalSchedule {
            return workScheduleManager.isWorkingDay(date)
        }
        return isWorkingDayDefault(date)
    }
    
    /// Verifica giorno lavorativo con regole di default (no domenica, no festivi)
    /// NOTA: I sabati SONO considerati lavorativi
    private func isWorkingDayDefault(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        
        // 1 = domenica - NON lavorativo
        if weekday == 1 {
            return false
        }
        
        // Festivo - NON lavorativo
        if calendarService.isHoliday(date) {
            return false
        }
        
        return true
    }
    
    /// Verifica se siamo in orario lavorativo
    func isWorkingTime(_ date: Date) -> Bool {
        if preferences.usePersonalSchedule {
            return isWorkingTimeFromPersonalSchedule(date)
        }
        return isWorkingTimeDefault(date)
    }
    
    /// Verifica orario lavorativo con regole di default (08:00 - 19:30)
    private func isWorkingTimeDefault(_ date: Date) -> Bool {
        guard isWorkingDayDefault(date) else {
            return false
        }
        
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        if hour < defaultWorkdayStartHour {
            return false
        }
        
        if hour > defaultWorkdayEndHour {
            return false
        }
        
        if hour == defaultWorkdayEndHour && minute >= defaultWorkdayEndMinute {
            return false
        }
        
        return true
    }
    
    /// Verifica orario lavorativo usando WorkScheduleManager
    private func isWorkingTimeFromPersonalSchedule(_ date: Date) -> Bool {
        guard workScheduleManager.isWorkingDay(date) else {
            return false
        }
        
        let workingHours = workScheduleManager.getWorkingHours(for: date)
        guard !workingHours.isEmpty else {
            return false
        }
        
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        
        for slot in workingHours {
            let startHour = calendar.component(.hour, from: slot.start)
            let startMinute = calendar.component(.minute, from: slot.start)
            let endHour = calendar.component(.hour, from: slot.end)
            let endMinute = calendar.component(.minute, from: slot.end)
            
            // Verifica se siamo dentro questo slot
            let afterStart = currentHour > startHour || (currentHour == startHour && currentMinute >= startMinute)
            let beforeEnd = currentHour < endHour || (currentHour == endHour && currentMinute < endMinute)
            
            if afterStart && beforeEnd {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func getScheduleReason(for date: Date) -> ScheduleReason? {
        // Se usa orario personale, verifica con WorkScheduleManager
        if preferences.usePersonalSchedule {
            return getScheduleReasonFromPersonalSchedule(for: date)
        }
        
        // Regole di default
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        
        // Domenica
        if weekday == 1 {
            return .sunday
        }
        
        // Festivo
        if calendarService.isHoliday(date) {
            return .holiday
        }
        
        // Prima delle 08:00
        if hour < defaultWorkdayStartHour {
            return .beforeHours
        }
        
        // Dopo le 19:30
        if hour > defaultWorkdayEndHour || (hour == defaultWorkdayEndHour && minute >= defaultWorkdayEndMinute) {
            return .afterHours
        }
        
        return nil
    }
    
    /// Determina motivo scheduling usando WorkScheduleManager
    private func getScheduleReasonFromPersonalSchedule(for date: Date) -> ScheduleReason? {
        // Se non è un giorno lavorativo secondo l'utente
        if !workScheduleManager.isWorkingDay(date) {
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 {
                return .sunday
            }
            // Potrebbe essere un festivo o un giorno non lavorativo personalizzato
            return .holiday
        }
        
        // È un giorno lavorativo, ma siamo fuori dagli orari?
        let workingHours = workScheduleManager.getWorkingHours(for: date)
        guard !workingHours.isEmpty else {
            // Giorno senza orari definiti
            return .holiday
        }
        
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        
        // Ordina gli slot per orario di inizio
        let sortedSlots = workingHours.sorted {
            calendar.component(.hour, from: $0.start) < calendar.component(.hour, from: $1.start)
        }
        
        guard let firstSlot = sortedSlots.first, let lastSlot = sortedSlots.last else {
            return .holiday
        }
        
        let firstStartHour = calendar.component(.hour, from: firstSlot.start)
        let lastEndHour = calendar.component(.hour, from: lastSlot.end)
        let lastEndMinute = calendar.component(.minute, from: lastSlot.end)
        
        // Prima del primo slot
        if currentHour < firstStartHour {
            return .beforeHours
        }
        
        // Dopo l'ultimo slot
        if currentHour > lastEndHour || (currentHour == lastEndHour && currentMinute >= lastEndMinute) {
            return .afterHours
        }
        
        // Verifica se siamo in una "pausa" tra gli slot
        for slot in sortedSlots {
            let startHour = calendar.component(.hour, from: slot.start)
            let startMinute = calendar.component(.minute, from: slot.start)
            let endHour = calendar.component(.hour, from: slot.end)
            let endMinute = calendar.component(.minute, from: slot.end)
            
            let afterStart = currentHour > startHour || (currentHour == startHour && currentMinute >= startMinute)
            let beforeEnd = currentHour < endHour || (currentHour == endHour && currentMinute < endMinute)
            
            if afterStart && beforeEnd {
                // Siamo in orario lavorativo
                return nil
            }
        }
        
        // Siamo in una pausa tra slot (es. pausa pranzo)
        return .afterHours
    }
    
    // MARK: - Preference Actions
    
    func ignoreForThisTime() {
        // Non fa nulla - l'utente può inviare ora
    }
    
    func ignoreForContext(_ contextId: String) {
        preferences.addIgnoredContext(contextId)
    }
    
    func ignoreForToday() {
        preferences.setIgnoreUntilMidnight()
    }
    
    func enableAutoSchedule() {
        preferences.autoScheduleEnabled = true
    }
    
    func disableAutoSchedule() {
        preferences.autoScheduleEnabled = false
    }
    
    func resetPreferences() {
        preferences.reset()
    }
}

// MARK: - Preferences Manager

class SmartSchedulePreferences: ObservableObject {
    static let shared = SmartSchedulePreferences()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let autoScheduleKey = "smartSchedule.autoScheduleEnabled"
    private let ignoreUntilKey = "smartSchedule.ignoreUntil"
    private let ignoredContextsKey = "smartSchedule.ignoredContexts"
    private let defaultScheduleTimeKey = "smartSchedule.defaultTime" // "08:00" format
    private let usePersonalScheduleKey = "smartSchedule.usePersonalSchedule"
    
    @Published var autoScheduleEnabled: Bool {
        didSet {
            defaults.set(autoScheduleEnabled, forKey: autoScheduleKey)
        }
    }
    
    @Published var defaultScheduleTime: String {
        didSet {
            defaults.set(defaultScheduleTime, forKey: defaultScheduleTimeKey)
        }
    }
    
    /// Se true, usa WorkScheduleManager personale invece delle regole di default
    @Published var usePersonalSchedule: Bool {
        didSet {
            defaults.set(usePersonalSchedule, forKey: usePersonalScheduleKey)
        }
    }
    
    private var ignoreUntil: Date? {
        get { defaults.object(forKey: ignoreUntilKey) as? Date }
        set { defaults.set(newValue, forKey: ignoreUntilKey) }
    }
    
    private var ignoredContexts: Set<String> {
        get {
            let array = defaults.stringArray(forKey: ignoredContextsKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: ignoredContextsKey)
        }
    }
    
    private init() {
        self.autoScheduleEnabled = defaults.bool(forKey: autoScheduleKey)
        self.defaultScheduleTime = defaults.string(forKey: defaultScheduleTimeKey) ?? "08:00"
        self.usePersonalSchedule = defaults.bool(forKey: usePersonalScheduleKey)
    }
    
    // MARK: - Public API
    
    func isIgnoredForToday() -> Bool {
        guard let ignoreUntil = ignoreUntil else { return false }
        return Date() < ignoreUntil
    }
    
    func setIgnoreUntilMidnight() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let midnight = calendar.startOfDay(for: tomorrow)
        ignoreUntil = midnight
    }
    
    func isIgnoredForContext(_ contextId: String) -> Bool {
        ignoredContexts.contains(contextId)
    }
    
    func addIgnoredContext(_ contextId: String) {
        var contexts = ignoredContexts
        contexts.insert(contextId)
        ignoredContexts = contexts
    }
    
    func removeIgnoredContext(_ contextId: String) {
        var contexts = ignoredContexts
        contexts.remove(contextId)
        ignoredContexts = contexts
    }
    
    @MainActor
    func getDefaultScheduleDate(from baseDate: Date) -> Date {
        let components = defaultScheduleTime.split(separator: ":")
        let hour = Int(components.first ?? "8") ?? 8
        let minute = Int(components.last ?? "0") ?? 0
        
        let calendar = Calendar.current
        var target = SmartScheduleService.shared.calculateNextWorkingTime(from: baseDate)
        
        // Applica l'orario personalizzato
        target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: target)!
        
        return target
    }
    
    func reset() {
        autoScheduleEnabled = false
        ignoreUntil = nil
        ignoredContexts = []
        defaultScheduleTime = "08:00"
        usePersonalSchedule = false
    }
}
