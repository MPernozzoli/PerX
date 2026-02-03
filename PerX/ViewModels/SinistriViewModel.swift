import SwiftUI
import CoreData
import Combine

/// ViewModel per SinistriView - gestisce tutta la logica di filtraggio, ordinamento e calcoli
@MainActor
final class SinistriViewModel: ObservableObject {
    
    // MARK: - Singleton Services
    private let appState = AppState.shared
    private let taskManager = TaskManager.shared
    private let diarioUnreadService = DiarioUnreadService.shared
    private let notificationManager = SinistroNotificationManager.shared
    
    // MARK: - Published State
    @Published var selectedStates: Set<String> = []
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var searchInFilteredOnly = true
    @Published var searchIsExpanded = false
    
    @Published var selectedCompanies: Set<String> = []
    @Published var selectedAgenzie: Set<String> = []
    @Published var selectedTipoPolizze: Set<String> = []
    
    @Published var selectedSinistri: Set<NSManagedObjectID> = []
    @Published var lastSelectedSinistroID: NSManagedObjectID?
    
    // MARK: - Drag & Drop State
    @Published var draggedTab: TabInfo?
    @Published var draggedTabSourceWindowId: String?
    @Published var dragOffset: CGFloat = 0
    @Published var isDragging = false
    @Published var showDetachIndicator = false
    @Published var dragLocation: CGPoint = .zero
    
    // MARK: - Persistent Settings (sync with UserDefaults)
    @AppStorage("sinistriSortColumn") private var sortColumnRaw: String = SortColumn.riferimento.rawValue
    @AppStorage("sinistriSortAscending") var sortAscending: Bool = true
    @AppStorage("recentOnlyFilter") var recentOnly: Bool = true
    @AppStorage("showUltimiOnlyFilter") var showUltimiOnly: Bool = false
    @AppStorage("filterAssigneeEnabled") var filterAssigneeEnabled: Bool = true
    @AppStorage("filterAssigneeEmail") var filterAssigneeEmail: String = ""
    @AppStorage("includiCodiceCompagniaRiferimento") var mostraSiglaCompagnia: Bool = true
    
    // MARK: - Cache
    private var cachedMonthlyClosures: Int?
    private var cachedNeedsAcceleration: Bool?
    private var taskCountCache: [String: Int] = [:]
    private var priorityCache: [NSManagedObjectID: Double] = [:]
    private var activeTasksCache: [String: [DailyTask]] = [:]
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValiditySeconds: TimeInterval = 5.0
    
    // MARK: - Debounce
    private var searchDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed
    var sortColumn: SortColumn {
        get { SortColumn(rawValue: sortColumnRaw) ?? .riferimento }
        set { sortColumnRaw = newValue.rawValue }
    }
    
    // MARK: - Init
    init() {
        setupDebounce()
        setupMigration()
    }
    
    private func setupDebounce() {
        $searchText
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.debouncedSearchText = newValue
            }
            .store(in: &cancellables)
        
        $searchText
            .sink { [weak self] newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self?.searchInFilteredOnly = true
                    self?.debouncedSearchText = ""
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMigration() {
        // Migrazione vecchia chiave
        if UserDefaults.standard.object(forKey: "filterAssigneeEnabled") == nil,
           UserDefaults.standard.object(forKey: "filterByCurrentUser") != nil {
            filterAssigneeEnabled = UserDefaults.standard.bool(forKey: "filterByCurrentUser")
        }
        
        if filterAssigneeEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filterAssigneeEmail = CurrentUserService.shared.currentUsername ?? GoogleAuthService.shared.userEmail ?? ""
        }
    }
    
    // MARK: - Cache Invalidation
    func invalidateCache() {
        cachedMonthlyClosures = nil
        cachedNeedsAcceleration = nil
        taskCountCache.removeAll()
        priorityCache.removeAll()
        activeTasksCache.removeAll()
        lastCacheUpdate = .distantPast
    }
    
    // MARK: - Filtering Logic
    func filterSinistri(_ sinistri: FetchedResults<Sinistro>) -> [Sinistro] {
        guard !sinistri.isEmpty || debouncedSearchText.isEmpty else {
            return []
        }
        
        let allSinistri = Array(sinistri)
        let isAdvancedSearch = !searchInFilteredOnly
        let hasSearchText = !debouncedSearchText.isEmpty
        let hasSelectedStates = !selectedStates.isEmpty
        
        // Step 0: Filtro assegnatario (utente)
        var filtered = applyAssigneeFilter(to: allSinistri, isAdvancedSearch: isAdvancedSearch)
        
        // Step 0.5: Filtro recenti (anno corrente e anno-1)
        if recentOnly && !isAdvancedSearch {
            filtered = filtered.filter { $0.isRecente }
        }
        
        // Step 0.6: Filtro ultimi (24 ore)
        if showUltimiOnly && !isAdvancedSearch {
            let recentInteractions = SinistroInteractionTracker.shared.getRecentInteractions(hoursAgo: 24)
            filtered = filtered.filter { recentInteractions.contains($0.id) }
        }
        
        // Step 1: Filtro stati default (chiusa, revocata, annullata)
        if !isAdvancedSearch {
            filtered = applyDefaultStateFilter(to: filtered)
        }
        
        // Step 2: Ricerca avanzata (ricerca globale)
        if hasSearchText && isAdvancedSearch {
            filtered = applySearchFilter(to: filtered, query: debouncedSearchText.lowercased())
        }
        
        // Step 3: Filtro compagnia
        if !selectedCompanies.isEmpty && !isAdvancedSearch {
            filtered = applyCompanyFilter(to: filtered)
        }
        
        // Step 4: Filtro agenzia
        if !selectedAgenzie.isEmpty && !isAdvancedSearch {
            let agenzieNormalized = Set(selectedAgenzie.map { $0.lowercased() })
            filtered = filtered.filter { sinistro in
                guard let agenzia = sinistro.agenzia?.lowercased() else { return false }
                return agenzieNormalized.contains(agenzia)
            }
        }
        
        // Step 5: Filtro tipo polizza
        if !selectedTipoPolizze.isEmpty && !isAdvancedSearch {
            let polizzeNormalized = Set(selectedTipoPolizze.map { $0.lowercased() })
            filtered = filtered.filter { sinistro in
                guard let tipoPolizza = sinistro.tipoPolizza?.lowercased() else { return false }
                return polizzeNormalized.contains(tipoPolizza)
            }
        }
        
        // Step 6: Filtro stato selezionato
        if hasSelectedStates && !isAdvancedSearch {
            filtered = filtered.filter { sinistro in
                guard let stato = sinistro.stato else { return false }
                return selectedStates.contains(stato)
            }
        }
        
        // Step 7: Ricerca nei filtrati
        if hasSearchText && !isAdvancedSearch {
            filtered = applySearchFilter(to: filtered, query: debouncedSearchText.lowercased())
        }
        
        // Step 8: Ordinamento
        return applySorting(to: filtered, sinistri: sinistri)
    }
    
    // MARK: - Filter Helpers
    
    private func applyAssigneeFilter(to sinistri: [Sinistro], isAdvancedSearch: Bool) -> [Sinistro] {
        if isAdvancedSearch { return sinistri }
        guard filterAssigneeEnabled else { return sinistri }
        
        let target: String? = {
            let stored = filterAssigneeEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !stored.isEmpty { return stored }
            return CurrentUserService.shared.currentUsername ?? GoogleAuthService.shared.userEmail?.lowercased()
        }()
        
        guard let target, !target.isEmpty else { return sinistri }
        
        let targetEmail = CurrentUserService.shared.currentEmail?.lowercased()
        return sinistri.filter { sinistro in
            let assigned = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
            if assigned == target { return true }
            if let targetEmail, targetEmail != target, assigned == targetEmail { return true }
            return false
        }
    }
    
    private func applyDefaultStateFilter(to sinistri: [Sinistro]) -> [Sinistro] {
        let statiDaNascondere: Set<String> = [
            StatoManager.StatoSinistro.chiusa.descrizione,
            StatoManager.StatoSinistro.revocata.descrizione,
            StatoManager.StatoSinistro.annullata.descrizione
        ]
        let statiSelezionati = Set(selectedStates)
        
        return sinistri.filter { sinistro in
            guard let stato = sinistro.stato else { return true }
            if statiDaNascondere.contains(stato) {
                return statiSelezionati.contains(stato)
            }
            return true
        }
    }
    
    private func applyCompanyFilter(to sinistri: [Sinistro]) -> [Sinistro] {
        return sinistri.filter { sinistro in
            let detected = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
            return selectedCompanies.contains(detected.rawValue)
        }
    }
    
    private func applySearchFilter(to sinistri: [Sinistro], query: String) -> [Sinistro] {
        return sinistri.filter { sinistro in
            let riferimentoMatch = sinistro.riferimento?.lowercased().contains(query) ?? false
            let nomeMatch = sinistro.nomeAssicurato?.lowercased().contains(query) ?? false
            
            // Match numero sinistro con varianti (per Unipol: completo, senza trattini, ultime 7 cifre)
            let numeroMatch = matchNumeroSinistro(query: query, sinistro: sinistro)
            
            return riferimentoMatch || nomeMatch || numeroMatch
        }
    }
    
    /// Verifica se la query matcha il numero sinistro considerando le varianti per compagnia
    /// Per Unipol: 1-8101-2026-0040019 → matcha anche "0040019", "18101-20260040019", ecc.
    private func matchNumeroSinistro(query: String, sinistro: Sinistro) -> Bool {
        guard let numeroCompleto = sinistro.numeroSinistroCompagnia, !numeroCompleto.isEmpty else {
            return false
        }
        
        let queryNormalized = query.lowercased()
        
        // Match diretto (standard)
        if numeroCompleto.lowercased().contains(queryNormalized) {
            return true
        }
        
        // Per ricerche più sofisticate, usa le varianti del CompagniaService
        let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
        let varianti = CompagniaService.shared.segmentaNumeroSinistro(
            numeroCompleto: numeroCompleto,
            compagnia: compagnia
        )
        
        // La query potrebbe essere una delle varianti (es. ultime 7 cifre)
        for variante in varianti {
            if variante.lowercased().contains(queryNormalized) ||
               queryNormalized.contains(variante.lowercased()) {
                return true
            }
        }
        
        // Match inverso: la query senza separatori potrebbe matchare il numero
        let queryNoSeparators = query.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "")
        let numeroNoSeparators = numeroCompleto.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        if numeroNoSeparators.lowercased().contains(queryNoSeparators.lowercased()) ||
           queryNoSeparators.lowercased().contains(numeroNoSeparators.lowercased()) {
            return true
        }
        
        return false
    }
    
    // MARK: - Sorting
    
    private func applySorting(to sinistri: [Sinistro], sinistri allSinistri: FetchedResults<Sinistro>) -> [Sinistro] {
        let monthlyGoal = cachedMonthlyGoal
        let currentClosures = getMonthlyClosures(sinistri: allSinistri)
        let needsAcceleration = getNeedsAcceleration(sinistri: allSinistri)
        let taskCounts = getTaskCounts()
        
        return sinistri.sorted { lhs, rhs in
            let comparison: Bool
            
            switch sortColumn {
            case .riferimento:
                comparison = (lhs.riferimento ?? "") < (rhs.riferimento ?? "")
                
            case .prioritaDinamica:
                // 1. Prima: critici (con solleciti ricevuti) sempre in alto
                let lhsIsCritical = PriorityCalculator.shared.isCriticallyUrgent(for: lhs)
                let rhsIsCritical = PriorityCalculator.shared.isCriticallyUrgent(for: rhs)
                
                if lhsIsCritical != rhsIsCritical {
                    // Critici sempre in alto (quando sortAscending è false, cioè decrescente)
                    comparison = !lhsIsCritical && rhsIsCritical
                } else {
                    // 2. Secondo: priorità normalizzata
                    let lhsPriority = getPriority(for: lhs, monthlyGoal: monthlyGoal, currentClosures: currentClosures, needsAcceleration: needsAcceleration)
                    let rhsPriority = getPriority(for: rhs, monthlyGoal: monthlyGoal, currentClosures: currentClosures, needsAcceleration: needsAcceleration)
                    
                    if abs(lhsPriority - rhsPriority) < 0.001 {
                        // 3. Terzo: se priorità normalizzata uguale, usa raw priority per distinguere
                        let lhsRaw = PriorityCalculator.shared.calculateRawPriority(
                            for: lhs,
                            monthlyGoal: monthlyGoal,
                            currentClosures: currentClosures,
                            needsAcceleration: needsAcceleration
                        )
                        let rhsRaw = PriorityCalculator.shared.calculateRawPriority(
                            for: rhs,
                            monthlyGoal: monthlyGoal,
                            currentClosures: currentClosures,
                            needsAcceleration: needsAcceleration
                        )
                        comparison = lhsRaw < rhsRaw
                    } else {
                        comparison = lhsPriority < rhsPriority
                    }
                }
                
            case .stato:
                comparison = (lhs.stato ?? "").localizedCaseInsensitiveCompare(rhs.stato ?? "") == .orderedAscending
                
            case .assicurato:
                comparison = (lhs.nomeAssicurato ?? "").localizedCaseInsensitiveCompare(rhs.nomeAssicurato ?? "") == .orderedAscending
                
            case .compagnia:
                comparison = (lhs.nomeCompagnia ?? "").localizedCaseInsensitiveCompare(rhs.nomeCompagnia ?? "") == .orderedAscending
                
            case .complessita:
                comparison = lhs.gradoComplessita.rawValue < rhs.gradoComplessita.rawValue
                
            case .liquidato:
                comparison = (lhs.liquidato?.doubleValue ?? 0) < (rhs.liquidato?.doubleValue ?? 0)
                
            case .task:
                let lhsTask = taskCounts[lhs.riferimento ?? ""] ?? 0
                let rhsTask = taskCounts[rhs.riferimento ?? ""] ?? 0
                comparison = lhsTask < rhsTask
            }
            
            return sortAscending ? comparison : !comparison
        }
    }
    
    // MARK: - Statistics Cache
    
    private var cachedMonthlyGoal: Int {
        WorkScheduleManager.shared.getMonthlyTarget(for: Date())
    }
    
    func getMonthlyClosures(sinistri: FetchedResults<Sinistro>) -> Int {
        let now = Date()
        if let cached = cachedMonthlyClosures, now.timeIntervalSince(lastCacheUpdate) < cacheValiditySeconds {
            return cached
        }
        
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return 0
        }
        
        let closedStates = ["chiusa", "concordata verbalmente", "atto ricevuto"]
        let count = sinistri.filter { sinistro in
            guard let stato = sinistro.stato?.lowercased(), closedStates.contains(stato) else { return false }
            if let dataChiusura = sinistro.dataChiusura,
               dataChiusura >= monthStart && dataChiusura <= monthEnd {
                return true
            }
            return false
        }.count
        
        cachedMonthlyClosures = count
        lastCacheUpdate = now
        return count
    }
    
    func getNeedsAcceleration(sinistri: FetchedResults<Sinistro>) -> Bool {
        let now = Date()
        if let cached = cachedNeedsAcceleration, now.timeIntervalSince(lastCacheUpdate) < cacheValiditySeconds {
            return cached
        }
        
        let calendar = Calendar.current
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else {
            return false
        }
        
        let closedStates = ["chiusa", "concordata verbalmente", "atto ricevuto"]
        let recentlyClosed = sinistri.filter { sinistro in
            guard let stato = sinistro.stato?.lowercased(), closedStates.contains(stato),
                  let dataChiusura = sinistro.dataChiusura,
                  dataChiusura >= threeMonthsAgo else { return false }
            return true
        }
        
        guard !recentlyClosed.isEmpty else {
            cachedNeedsAcceleration = false
            return false
        }
        
        var totalDays = 0
        var count = 0
        
        for sinistro in recentlyClosed {
            let referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico
            guard let startDate = referenceDate, let endDate = sinistro.dataChiusura else { continue }
            let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            totalDays += days
            count += 1
        }
        
        guard count > 0 else {
            cachedNeedsAcceleration = false
            return false
        }
        
        let result = Double(totalDays) / Double(count) > 20.0
        cachedNeedsAcceleration = result
        lastCacheUpdate = now
        return result
    }
    
    func getTaskCounts() -> [String: Int] {
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < cacheValiditySeconds && !taskCountCache.isEmpty {
            return taskCountCache
        }
        
        var counts: [String: Int] = [:]
        for task in taskManager.tasks where (task.status == .pending || task.status == .inProgress) {
            if let sinistroID = task.sinistroID {
                counts[sinistroID, default: 0] += 1
            }
        }
        
        taskCountCache = counts
        return counts
    }
    
    func getActiveTasks() -> [String: [DailyTask]] {
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < cacheValiditySeconds && !activeTasksCache.isEmpty {
            return activeTasksCache
        }
        
        var result: [String: [DailyTask]] = [:]
        for task in taskManager.tasks where (task.status == .pending || task.status == .inProgress) {
            if let sinistroID = task.sinistroID {
                result[sinistroID, default: []].append(task)
            }
        }
        
        activeTasksCache = result
        return result
    }
    
    func getPriority(for sinistro: Sinistro, monthlyGoal: Int, currentClosures: Int, needsAcceleration: Bool) -> Double {
        let objectID = sinistro.objectID
        
        if let cached = priorityCache[objectID] {
            return cached
        }
        
        let priority = PriorityCalculator.shared.calculateDynamicPriority(
            for: sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: currentClosures,
            needsAcceleration: needsAcceleration
        )
        
        priorityCache[objectID] = priority
        return priority
    }
    
    func activeTaskCount(for sinistro: Sinistro) -> Int {
        guard let riferimento = sinistro.riferimento else { return 0 }
        return getTaskCounts()[riferimento] ?? 0
    }
    
    func calculatePriority(for sinistro: Sinistro, sinistri: FetchedResults<Sinistro>) -> Double {
        getPriority(
            for: sinistro,
            monthlyGoal: cachedMonthlyGoal,
            currentClosures: getMonthlyClosures(sinistri: sinistri),
            needsAcceleration: getNeedsAcceleration(sinistri: sinistri)
        )
    }
    
    // MARK: - Suggested Sinistri
    
    func computeSuggestedSinistri(sinistri: FetchedResults<Sinistro>) -> [SuggestedSinistroItem] {
        let now = Date()
        let calendar = Calendar.current
        let thirtyMinutesFromNow = now.addingTimeInterval(30 * 60)
        
        let openTabRiferimenti = Set(appState.openTabs.compactMap { $0.sinistro.riferimento })
        let currentUserEmail = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        
        var sinistriWithTasks: [String: (sinistro: Sinistro, taskDate: Date)] = [:]
        var sinistriWithUnread: [String: (sinistro: Sinistro, unreadCount: Int)] = [:]
        
        // Dizionario sinistri
        var sinistriDict: [String: Sinistro] = [:]
        sinistriDict.reserveCapacity(sinistri.count)
        for sinistro in sinistri {
            if let riferimento = sinistro.riferimento {
                sinistriDict[riferimento] = sinistro
            }
        }
        
        // Task nell'intervallo
        let pendingTasks = taskManager.tasks.filter { $0.status == .pending && !$0.isIgnored && $0.sinistroID != nil }
        
        for task in pendingTasks {
            guard let sinistroID = task.sinistroID, !openTabRiferimenti.contains(sinistroID) else { continue }
            
            var taskDateTime: Date?
            
            if let scheduledDate = task.scheduledDate, let scheduledTime = task.scheduledTime {
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                dateComponents.second = timeComponents.second ?? 0
                taskDateTime = calendar.date(from: dateComponents)
            } else if let fixedDateTime = task.fixedDateTime {
                taskDateTime = fixedDateTime
            } else if let scheduledDate = task.scheduledDate {
                let today = calendar.startOfDay(for: now)
                let taskDay = calendar.startOfDay(for: scheduledDate)
                if taskDay == today {
                    taskDateTime = now
                }
            }
            
            guard let taskDate = taskDateTime else { continue }
            
            let taskEnd = taskDate.addingTimeInterval(task.estimatedDuration)
            let isInTimeRange = (taskDate >= now && taskDate <= thirtyMinutesFromNow) ||
                                (taskDate < now && taskEnd >= now && taskEnd <= thirtyMinutesFromNow)
            
            if isInTimeRange, let sinistro = sinistriDict[sinistroID] {
                let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
                guard assignedEmail == currentUserEmail else { continue }
                
                if let existing = sinistriWithTasks[sinistroID] {
                    if taskDate < existing.taskDate {
                        sinistriWithTasks[sinistroID] = (sinistro: sinistro, taskDate: taskDate)
                    }
                } else {
                    sinistriWithTasks[sinistroID] = (sinistro: sinistro, taskDate: taskDate)
                }
            }
        }
        
        // Notifiche
        let riferimentiConNotifiche = notificationManager.getAllRiferimentiWithNotifications()
        
        for rif in riferimentiConNotifiche {
            guard !openTabRiferimenti.contains(rif), let sinistro = sinistriDict[rif] else { continue }
            
            let assignedEmail = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
            guard assignedEmail == currentUserEmail else { continue }
            
            let totalUnread = notificationManager.getTotalCount(riferimento: rif)
            if totalUnread > 0 {
                sinistriWithUnread[rif] = (sinistro: sinistro, unreadCount: totalUnread)
            }
        }
        
        // Merge risultati
        var result: [SuggestedSinistroItem] = []
        result.reserveCapacity(sinistriWithUnread.count + sinistriWithTasks.count)
        var addedRiferimenti = Set<String>()
        
        let sortedUnread = sinistriWithUnread.values.sorted { $0.unreadCount > $1.unreadCount }
        for item in sortedUnread {
            if let rif = item.sinistro.riferimento {
                let taskDate = sinistriWithTasks[rif]?.taskDate
                result.append(SuggestedSinistroItem(sinistro: item.sinistro, unreadCount: item.unreadCount, taskDate: taskDate))
                addedRiferimenti.insert(rif)
            }
        }
        
        let sortedTasks = sinistriWithTasks.values.sorted { $0.taskDate < $1.taskDate }
        for item in sortedTasks {
            if let rif = item.sinistro.riferimento, !addedRiferimenti.contains(rif) {
                result.append(SuggestedSinistroItem(sinistro: item.sinistro, unreadCount: 0, taskDate: item.taskDate))
                addedRiferimenti.insert(rif)
            }
        }
        
        return result
    }
    
    // MARK: - Selection Logic
    
    func toggleSelection(_ sinistro: Sinistro) {
        if selectedSinistri.contains(sinistro.objectID) {
            selectedSinistri.remove(sinistro.objectID)
        } else {
            selectedSinistri.insert(sinistro.objectID)
        }
    }
    
    func selectRange(to sinistro: Sinistro, in list: [Sinistro]) {
        let anchorID = lastSelectedSinistroID ?? list.first?.objectID
        
        guard let anchorID,
              let anchorIndex = list.firstIndex(where: { $0.objectID == anchorID }),
              let targetIndex = list.firstIndex(where: { $0.objectID == sinistro.objectID }) else {
            selectedSinistri.insert(sinistro.objectID)
            lastSelectedSinistroID = sinistro.objectID
            return
        }
        
        let startIndex = min(anchorIndex, targetIndex)
        let endIndex = max(anchorIndex, targetIndex)
        
        for index in startIndex...endIndex {
            selectedSinistri.insert(list[index].objectID)
        }
        
        lastSelectedSinistroID = sinistro.objectID
    }
    
    func clearSelection() {
        selectedSinistri.removeAll()
        lastSelectedSinistroID = nil
    }
    
    func selectedSinistriObjects(from list: [Sinistro]) -> [Sinistro] {
        list.filter { selectedSinistri.contains($0.objectID) }
    }
    
    // MARK: - Actions
    
    func changePriority(for sinistro: Sinistro, to level: ManualPriorityLevel, context: NSManagedObjectContext) {
        if let value = level.value {
            sinistro.setValue(value, forKey: "prioritaManuale")
        } else {
            sinistro.setValue(nil, forKey: "prioritaManuale")
        }
        
        try? context.save()
        invalidatePriorityCache(for: sinistro.objectID)
    }
    
    /// Invalida la cache priorità per forzare ricalcolo (es. dopo override manuale)
    func invalidatePriorityCache(for objectID: NSManagedObjectID) {
        priorityCache.removeValue(forKey: objectID)
    }
    
    func changeState(for sinistro: Sinistro, to newState: StatoManager.StatoSinistro, context: NSManagedObjectContext) async {
        do {
            try await StatoManager.shared.changeState(
                for: sinistro,
                to: newState,
                context: context,
                userEmail: GoogleAuthService.shared.userEmail,
                skipValidation: true
            )
        } catch {
            print("[SinistriViewModel] ❌ Errore cambio stato: \(error)")
        }
    }
    
    func deleteSinistro(_ sinistro: Sinistro, context: NSManagedObjectContext) {
        if let tab = appState.openTabs.first(where: { $0.sinistro.objectID == sinistro.objectID }) {
            appState.closeTab(id: tab.id)
        }
        
        if let rif = sinistro.riferimento, !rif.isEmpty {
            DeletedSinistriTracker.shared.markAsDeleted(riferimento: rif)
        }
        
        let rifToDelete = sinistro.riferimento
        context.delete(sinistro)
        
        do {
            try context.save()
            if let rif = rifToDelete, !rif.isEmpty {
                Task {
                    await CloudKitSinistroSyncService.shared.deleteSinistro(riferimento: rif)
                }
            }
        } catch {
            print("[SinistriViewModel] ❌ Errore eliminazione: \(error)")
        }
    }
    
    func markSinistroAsRead(_ sinistro: Sinistro) {
        guard let rif = sinistro.riferimento else { return }
        
        if let email = GoogleAuthService.shared.userEmail?.lowercased() {
            diarioUnreadService.markSeen(sinistroRiferimento: rif, currentUserEmail: email)
        }
        
        for section in SinistroNotificationManager.Section.allCases {
            notificationManager.clearNotifications(riferimento: rif, section: section)
        }
    }
    
    func markAllSuggestedAsRead(suggested: [SuggestedSinistroItem]) {
        let email = GoogleAuthService.shared.userEmail?.lowercased()
        
        for item in suggested where item.unreadCount > 0 {
            if let rif = item.sinistro.riferimento {
                if let email {
                    diarioUnreadService.markSeen(sinistroRiferimento: rif, currentUserEmail: email)
                }
                for section in SinistroNotificationManager.Section.allCases {
                    notificationManager.clearNotifications(riferimento: rif, section: section)
                }
            }
        }
    }
    
    // MARK: - UI Helpers
    
    func statoColor(for sinistro: Sinistro) -> Color {
        guard let statoString = sinistro.stato,
              let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoString }) else {
            return Color(NSColor.controlBackgroundColor)
        }
        return stato.color
    }
    
    func priorityLabel(for value: Double, sinistro: Sinistro) -> String {
        if value > 0.90 {
            return PriorityCalculator.shared.isCriticallyUrgent(for: sinistro) ? "Critica" : "Molto Alta"
        }
        switch value {
        case ..<0.25: return "Bassa"
        case 0.25..<0.60: return "Media"
        case 0.60..<0.90: return "Alta"
        default: return "Alta"
        }
    }
    
    func priorityColor(for value: Double, sinistro: Sinistro) -> Color {
        if value > 0.90 {
            return PriorityCalculator.shared.isCriticallyUrgent(for: sinistro) ? .red : Color(nsColor: .systemPurple)
        }
        switch value {
        case ..<0.25: return .green
        case 0.25..<0.60: return .yellow
        case 0.60..<0.90: return .orange
        default: return .orange
        }
    }
    
    // MARK: - Stato Popover Logic
    
    /// Ottiene le informazioni sullo stato di un sinistro per il popover
    func getStatoInfo(for sinistro: Sinistro) -> StatoPopoverInfo {
        let statoString = sinistro.stato
        let stato = statoString.flatMap { desc in
            StatoManager.StatoSinistro.allCases.first { $0.descrizione == desc }
        }
        
        let dataStato = getDataUltimoStato(sinistro: sinistro, stato: stato)
        let giorniTotali = dataStato.map { calculateGiorniTotali(from: $0) } ?? 0
        let giorniLavorativi = dataStato.map { ItalianCalendarService.shared.getWorkingDaysSince($0) } ?? 0
        
        return StatoPopoverInfo(
            stato: stato,
            descrizione: statoString ?? "N/D",
            dataStato: dataStato,
            giorniTotali: giorniTotali,
            giorniLavorativi: giorniLavorativi,
            cicliControllo: sinistro.cicliControlloArray,
            statisticheControllo: sinistro.statisticheControllo
        )
    }
    
    /// Ottiene la data corrispondente allo stato corrente
    private func getDataUltimoStato(sinistro: Sinistro, stato: StatoManager.StatoSinistro?) -> Date? {
        guard let stato = stato else { return nil }
        
        switch stato {
        // Stati con date specifiche salvate
        case .attoInviato:
            return sinistro.dataInvioAtto
        case .esitoComunicato:
            return sinistro.dataComunicazioneEsito ?? sinistro.dataInvioAtto
        case .attoRicevutoSottoscritto:
            return sinistro.dataRicezioneAttoSottoscritto ?? sinistro.dataRitornoAtto
        case .accettataVerbalmente:
            return sinistro.dataAccettazioneVerbale
        case .chiusa:
            return sinistro.dataChiusura
        case .revocata:
            return sinistro.dataRevoca
        case .sopralluogoFissato, .sopralluogoRestituito:
            return sinistro.dataSopralluogo
            
        // Stati di gestione usano dataAssegnazione
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia:
            return sinistro.dataAssegnazione ?? sinistro.dataAperturaGestione
            
        // Stati di ingresso usano dataIncarico
        case .daScaricare:
            return sinistro.dataIncarico ?? sinistro.dataCreazione
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            return sinistro.dataAssegnazione ?? sinistro.dataIncarico
        case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui:
            return sinistro.dataAssegnazione ?? sinistro.dataIncarico
        case .videoperiziaDaFissare, .videoperiziaFissata:
            return sinistro.dataAssegnazione ?? sinistro.dataIncarico
            
        // Stati di controllo: cerca nel ciclo aperto o nel diario
        case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata:
            if let cicloAperto = sinistro.cicloControlloAperto {
                return cicloAperto.dataEntrata
            }
            return getDataStatoDaDiario(sinistro: sinistro, statoCorrente: stato.descrizione)
            
        // Altri stati: fallback al diario
        case .attoDaInviare, .esitoDaComunicare, .richiestaRevisione, .annullata:
            return getDataStatoDaDiario(sinistro: sinistro, statoCorrente: stato.descrizione)
        }
    }
    
    /// Cerca nel diario l'entry che corrisponde all'ingresso nello stato corrente
    private func getDataStatoDaDiario(sinistro: Sinistro, statoCorrente: String) -> Date? {
        let entriesOrdinate = sinistro.diarioArray
            .filter { $0.tipo == .cambioStato }
            .sorted { $0.timestamp > $1.timestamp }
        
        // Cerca una corrispondenza esatta con lo stato corrente
        for entry in entriesOrdinate {
            let testo = entry.testo + (entry.riassunto ?? "") + (entry.contenutoCompleto ?? "")
            if testo.contains("a \"\(statoCorrente)\"") || 
               testo.contains("a \u{201C}\(statoCorrente)\u{201D}") ||
               testo.contains("→ \(statoCorrente)") ||
               testo.contains("a \(statoCorrente)") {
                return entry.timestamp
            }
        }
        
        // Fallback: ritorna la data dell'ultimo cambio stato
        return entriesOrdinate.first?.timestamp
    }
    
    private func calculateGiorniTotali(from date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: Date())
        return components.day ?? 0
    }
    
    func categoriaDescrizione(_ categoria: StatoCategory) -> String {
        switch categoria {
        case .ingresso: return "Fase iniziale"
        case .avanzamento: return "In lavorazione"
        case .chiusura: return "Fase finale"
        case .sistema: return "Stato di sistema"
        }
    }
}

// MARK: - Stato Popover Info

struct StatoPopoverInfo {
    let stato: StatoManager.StatoSinistro?
    let descrizione: String
    let dataStato: Date?
    let giorniTotali: Int
    let giorniLavorativi: Int
    let cicliControllo: [CicloControllo]
    let statisticheControllo: (numeroCicli: Int, giorniTotali: Int, giorniLavorativiTotali: Int)
    
    var hasData: Bool { dataStato != nil }
    var hasCicliControllo: Bool { !cicliControllo.isEmpty }
    var statoColor: Color { stato?.color ?? .gray }
}

// MARK: - Supporting Types

enum SortColumn: String, CaseIterable {
    case riferimento = "Riferimento"
    case prioritaDinamica = "Priorità"
    case stato = "Stato"
    case assicurato = "Assicurato"
    case compagnia = "Compagnia"
    case complessita = "Complessità"
    case liquidato = "Liquidato"
    case task = "Task"
}

struct SuggestedSinistroItem {
    let sinistro: Sinistro
    let unreadCount: Int
    let taskDate: Date?
}
