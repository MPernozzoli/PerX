import SwiftUI
import CoreData
import Combine

/// ViewModel per FilteredSinistriWindow - gestisce filtraggio, ordinamento e calcoli
@MainActor
final class FilteredSinistriViewModel: ObservableObject {
    
    // MARK: - Published State
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var sortColumn: FilteredSortColumn = .dataIncarico
    @Published var sortAscending: Bool = false
    
    // MARK: - Debounce
    private var searchDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    init() {
        setupDebounce()
    }
    
    private func setupDebounce() {
        $searchText
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.debouncedSearchText = newValue
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Filtering
    func filterSinistri(_ sinistri: [Sinistro], searchText: String) -> [Sinistro] {
        guard !searchText.isEmpty else { return sinistri }
        
        let query = searchText.lowercased()
        return sinistri.filter { sinistro in
            (sinistro.riferimento ?? "").lowercased().contains(query) ||
            (sinistro.nomeAssicurato ?? "").lowercased().contains(query) ||
            (sinistro.nomeCompagnia ?? "").lowercased().contains(query) ||
            (sinistro.indirizzoAssicurato ?? "").lowercased().contains(query)
        }
    }
    
    // MARK: - Sorting
    func sortSinistri(_ sinistri: [Sinistro]) -> [Sinistro] {
        return sinistri.sorted { lhs, rhs in
            let comparison: Bool
            
            switch sortColumn {
            case .riferimento:
                comparison = (lhs.riferimento ?? "") < (rhs.riferimento ?? "")
            case .assicurato:
                comparison = (lhs.nomeAssicurato ?? "").localizedCaseInsensitiveCompare(rhs.nomeAssicurato ?? "") == .orderedAscending
            case .dataIncarico:
                let lhsDate = lhs.dataIncarico ?? .distantPast
                let rhsDate = rhs.dataIncarico ?? .distantPast
                comparison = lhsDate < rhsDate
            case .stato:
                comparison = (lhs.stato ?? "").localizedCaseInsensitiveCompare(rhs.stato ?? "") == .orderedAscending
            case .compagnia:
                comparison = (lhs.nomeCompagnia ?? "").localizedCaseInsensitiveCompare(rhs.nomeCompagnia ?? "") == .orderedAscending
            case .liquidazione:
                comparison = (lhs.importoLiquidatoEffettivo?.doubleValue ?? 0) < (rhs.importoLiquidatoEffettivo?.doubleValue ?? 0)
            case .giorniGestione:
                let lhsDays = calcolaGiorniGestione(for: lhs)
                let rhsDays = calcolaGiorniGestione(for: rhs)
                comparison = (lhsDays ?? 0) < (rhsDays ?? 0)
            }
            
            return sortAscending ? comparison : !comparison
        }
    }
    
    // MARK: - Helpers (usa ConsuntivoStatsService per consistenza con ConsuntivoView)
    func calcolaGiorniGestione(for sinistro: Sinistro) -> Int? {
        ConsuntivoStatsService.shared.giorniGestione(for: sinistro)
    }
    
    func statoColor(for sinistro: Sinistro) -> Color {
        guard let statoString = sinistro.stato,
              let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoString }) else {
            return Color(NSColor.controlBackgroundColor)
        }
        return stato.color
    }
}

// MARK: - Filtered Sort Column
enum FilteredSortColumn: String, CaseIterable {
    case riferimento = "Riferimento"
    case assicurato = "Assicurato"
    case dataIncarico = "Data Incarico"
    case stato = "Stato"
    case compagnia = "Compagnia"
    case liquidazione = "Liquidazione"
    case giorniGestione = "Giorni Gestione"
}
