import SwiftUI
import CoreData
import AppKit

/// Finestra per visualizzare sinistri filtrati da hashtag o altre sorgenti
struct FilteredSinistriWindow: View {
    let config: FilterConfig
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = FilteredSinistriViewModel()
    
    @State private var isPinned = false
    @State private var showingExportOptions = false
    @State private var visibleColumns: Set<FilterConfig.ColumnType>
    @State private var visibleDynamicColumns: [DynamicColumn]
    @State private var showingColumnPicker = false
    
    @FetchRequest(
        entity: Sinistro.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.dataIncarico, ascending: false)]
    ) private var allSinistri: FetchedResults<Sinistro>
    
    init(config: FilterConfig) {
        self.config = config
        _visibleColumns = State(initialValue: config.columnsToShow)
        _visibleDynamicColumns = State(initialValue: config.dynamicColumns ?? [])
    }
    
    // Colonne dinamiche visibili, con logica per nascondere compagnia se c'è solo una compagnia
    private var effectiveDynamicColumns: [DynamicColumn] {
        guard config.usesDynamicColumns else { return visibleDynamicColumns }
        
        // Se la configurazione è per sinistri chiusi, verifica se mostrare la colonna compagnia
        let hasMultipleCompanies = {
            let companies = Set(filteredSinistri.compactMap { $0.nomeCompagnia }.filter { !$0.isEmpty })
            return companies.count >= 2
        }()
        
        // Se ci sono meno di 2 compagnie, rimuovi la colonna compagnia
        if !hasMultipleCompanies {
            return visibleDynamicColumns.filter { $0.id != "compagnia" }
        }
        
        return visibleDynamicColumns
    }
    
    private var filteredSinistri: [Sinistro] {
        var result = Array(allSinistri)
        
        // Applica filtri da config
        result = applyConfigFilters(to: result)
        
        // Deduplica per riferimento (es. assegnazioni KPI: un sinistro = un riferimento)
        if config.deduplicateByRiferimento {
            var seen = Set<String>()
            result = result.filter { s in
                guard let rif = s.riferimento, !rif.isEmpty else { return false }
                if seen.contains(rif) { return false }
                seen.insert(rif)
                return true
            }
        }
        
        // Applica ricerca tramite ViewModel
        result = viewModel.filterSinistri(result, searchText: viewModel.debouncedSearchText)
        
        // Applica ordinamento tramite ViewModel
        return viewModel.sortSinistri(result)
    }
    
    private var displaySubtitle: String {
        if let userEmail = config.userEmail {
            // Cerca il nome utente dall'email
            let userDirectory = CloudKitUserDirectoryService.shared
            if let user = userDirectory.user(email: userEmail) {
                return "Di \(user.displayName)"
            }
            // Fallback: estrai nome dall'email
            if let namePart = userEmail.components(separatedBy: "@").first {
                let formatted = namePart.replacingOccurrences(of: ".", with: " ").capitalized
                return "Di \(formatted)"
            }
        }
        return config.subtitle
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Search bar
            searchBarView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            
            Divider()
            
            // Tabella sinistri con header fisso
            if filteredSinistri.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    tableHeader
                    Divider()
                    tableList
                }
            }
            
            // Footer con conteggio
            footerView
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(.textBackgroundColor))
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsSheet(
                sinistri: filteredSinistri,
                config: config,
                visibleColumns: visibleColumns,
                dynamicColumns: config.usesDynamicColumns ? effectiveDynamicColumns : nil
            )
        }
    }
    
    // MARK: - Row View
    
    @ViewBuilder
    private func rowView(for sinistro: Sinistro) -> some View {
        if config.usesDynamicColumns {
            DynamicColumnRow(sinistro: sinistro, columns: effectiveDynamicColumns)
        } else {
            SinistroCompactRow(sinistro: sinistro, showColumns: visibleColumns)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icona e titolo
            ZStack {
                Circle()
                    .fill(config.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: config.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(config.iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(displaySubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Azioni
            HStack(spacing: 8) {
                // Columns picker
                Button {
                    showingColumnPicker.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(showingColumnPicker ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "tablecells")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showingColumnPicker ? .accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Gestisci colonne")
                .popover(isPresented: $showingColumnPicker) {
                    ColumnPickerPopover(visibleColumns: $visibleColumns)
                }
                
                // Sort menu
                Menu {
                    ForEach(FilteredSortColumn.allCases, id: \.self) { column in
                        Button {
                            if viewModel.sortColumn == column {
                                viewModel.sortAscending.toggle()
                            } else {
                                viewModel.sortColumn = column
                                viewModel.sortAscending = true
                            }
                        } label: {
                            HStack {
                                Text(column.rawValue)
                                if viewModel.sortColumn == column {
                                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .help("Ordinamento")
                
                // Pin ontop
                Button {
                    isPinned.toggle()
                    toggleWindowPin()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPinned ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isPinned ? .accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Disattiva sempre in primo piano" : "Sempre in primo piano")
                
                // Export
                Button {
                    showingExportOptions = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Esporta")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            TextField("Cerca sinistri...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(viewModel.searchText.isEmpty ? "Nessun sinistro trovato" : "Nessun risultato")
                .font(.system(size: 16, weight: .medium))
            
            if !viewModel.searchText.isEmpty {
                Text("Prova a modificare i termini di ricerca")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("\(filteredSinistri.count) sinistri")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !viewModel.searchText.isEmpty {
                Button("Cancella ricerca") {
                    viewModel.searchText = ""
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Helpers
    
    private func applyConfigFilters(to sinistri: [Sinistro]) -> [Sinistro] {
        var result = sinistri
        
        // Filtro per stato
        if let states = config.states, !states.isEmpty {
            result = result.filter { sinistro in
                states.contains(sinistro.stato ?? "")
            }
        }
        
        // Filtro per utente
        if let userEmail = config.userEmail {
            result = result.filter { sinistro in
                let assigned = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
                return assigned == userEmail.lowercased()
            }
        }
        
        // Filtro per data
        if let dateFilter = config.dateFilter {
            result = result.filter { sinistro in
                guard let dataIncarico = sinistro.dataIncarico else { return false }
                return dateFilter.matches(date: dataIncarico)
            }
        }
        
        // Filtro personalizzato
        if let customFilter = config.customFilter {
            result = result.filter(customFilter)
        }
        
        return result
    }
    
    // MARK: - Table Views
    
    private var tableHeader: some View {
        HStack(spacing: 0) {
            // Prima colonna sempre riferimento
            sortableHeaderColumn(FilteredSortColumn.riferimento, width: 120)
            
            // Seconda colonna sempre nome contraente
            sortableHeaderColumn(FilteredSortColumn.assicurato, width: 180)
            
            // Altre colonne opzionali
            if config.usesDynamicColumns {
                ForEach(effectiveDynamicColumns.dropFirst(2)) { column in
                    headerColumn(column.label, width: column.width)
                }
            } else {
                let optionalColumns = Array(visibleColumns).sorted(by: { $0.rawValue < $1.rawValue })
                    .filter { $0 != .riferimento && $0 != .assicurato }
                
                ForEach(optionalColumns, id: \.self) { column in
                    if column == .stato {
                        sortableHeaderColumn(FilteredSortColumn.stato, width: column.width)
                    } else if column == .compagnia {
                        sortableHeaderColumn(FilteredSortColumn.compagnia, width: column.width)
                    } else if column == .liquidazione {
                        sortableHeaderColumn(FilteredSortColumn.liquidazione, width: column.width)
                    } else if column == .giorniGestione {
                        sortableHeaderColumn(FilteredSortColumn.giorniGestione, width: column.width)
                    } else {
                        headerColumn(column.label, width: column.width)
                    }
                }
            }
            
            // Spacer per evitare che le colonne vengano tagliate
            Spacer(minLength: 0)
                .frame(minWidth: 0)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func headerColumn(_ title: String, width: CGFloat?) -> some View {
        Group {
            if let width = width {
                Text(title)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func sortableHeaderColumn(_ column: FilteredSortColumn, width: CGFloat?) -> some View {
        Button {
            if viewModel.sortColumn == column {
                viewModel.sortAscending.toggle()
            } else {
                viewModel.sortColumn = column
                viewModel.sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.rawValue)
                    .font(.headline)
                
                if viewModel.sortColumn == column {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var tableList: some View {
        List {
            ForEach(filteredSinistri, id: \.objectID) { sinistro in
                FilteredSinistroTableRow(
                    sinistro: sinistro,
                    config: config,
                    visibleColumns: visibleColumns,
                    visibleDynamicColumns: effectiveDynamicColumns,
                    statoColor: viewModel.statoColor(for: sinistro),
                    onTap: {
                        AppState.shared.openSinistro(sinistro, openInNewWindow: true)
                    }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    
    private func toggleWindowPin() {
        if let window = NSApp.windows.first(where: { $0.contentView?.subviews.contains(where: { view in
            String(describing: type(of: view)).contains("FilteredSinistriWindow")
        }) ?? false }) {
            window.level = isPinned ? .floating : .normal
        }
    }
}

// MARK: - Filter Config

// MARK: - Dynamic Column System

/// Tipo di dato per una colonna dinamica
enum DynamicColumnType {
    case text
    case number
    case currency
    case date
    case bool
    case state
    case stars(max: Int)
    case custom((Any?) -> AnyView)
}

/// Definizione di una colonna dinamica
struct DynamicColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let type: DynamicColumnType
    let width: CGFloat?
    private let _valueExtractor: (Sinistro) -> Any?
    
    init(id: String, label: String, type: DynamicColumnType, width: CGFloat? = nil, valueExtractor: @escaping (Sinistro) -> Any?) {
        self.id = id
        self.label = label
        self.type = type
        self.width = width
        self._valueExtractor = valueExtractor
    }
    
    func value(for sinistro: Sinistro) -> Any? {
        _valueExtractor(sinistro)
    }
    
    // Hashable conformance (ignora closure)
    static func == (lhs: DynamicColumn, rhs: DynamicColumn) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Preset Columns
    
    static let riferimento = DynamicColumn(
        id: "riferimento", label: "Riferimento", type: .text, width: 120
    ) { $0.riferimento }
    
    static let assicurato = DynamicColumn(
        id: "assicurato", label: "Assicurato", type: .text, width: nil
    ) { $0.nomeAssicurato }
    
    static let compagnia = DynamicColumn(
        id: "compagnia", label: "Compagnia", type: .text, width: 100
    ) { $0.nomeCompagnia }
    
    static let dataIncarico = DynamicColumn(
        id: "dataIncarico", label: "Data Incarico", type: .date, width: 100
    ) { $0.dataIncarico }
    
    static let dataChiusura = DynamicColumn(
        id: "dataChiusura", label: "Data Chiusura", type: .date, width: 100
    ) { $0.dataChiusura }
    
    static let dataAssegnazione = DynamicColumn(
        id: "dataAssegnazione", label: "Data Assegnazione", type: .date, width: 110
    ) { $0.dataAssegnazione ?? $0.dataIncarico }
    
    static let dataInvioAtto = DynamicColumn(
        id: "dataInvioAtto", label: "Data Invio Atto", type: .date, width: 110
    ) { $0.dataInvioAtto }
    
    static let stato = DynamicColumn(
        id: "stato", label: "Stato", type: .state, width: 120
    ) { $0.stato }
    
    static let indirizzo = DynamicColumn(
        id: "indirizzo", label: "Indirizzo", type: .text, width: nil
    ) { $0.indirizzoAssicurato }
    
    static let concordato = DynamicColumn(
        id: "concordato", label: "Concordato", type: .bool, width: 80
    ) { $0.isConcordata }
    
    static let liquidazione = DynamicColumn(
        id: "liquidazione", label: "Liquidazione", type: .currency, width: 100
    ) { $0.importoLiquidatoEffettivo?.doubleValue }
    
    static let richiesta = DynamicColumn(
        id: "richiesta", label: "Richiesta", type: .currency, width: 100
    ) { $0.richiesta?.doubleValue }
    
    static let giorniGestione = DynamicColumn(
        id: "giorniGestione", label: "Giorni Gestione", type: .number, width: 100
    ) { @MainActor sinistro in
        ConsuntivoStatsService.shared.giorniGestione(for: sinistro)
    }
    
    static let beni = DynamicColumn(
        id: "beni", label: "N° Beni", type: .number, width: 70
    ) { $0.numeroBeni }
    
    static let complessita = DynamicColumn(
        id: "complessita", label: "Complessità", type: .stars(max: 3), width: 90
    ) { sinistro in
        switch sinistro.gradoComplessita {
        case .bassa: return 1
        case .media: return 2
        case .alta, .moltaAlta: return 3
        default: return 0
        }
    }
    
    static let agenzia = DynamicColumn(
        id: "agenzia", label: "Agenzia", type: .text, width: 120
    ) { $0.agenzia }
    
    // Fatturato columns
    static func fatturatoBase(settings: FatturatoSettings) -> DynamicColumn {
        DynamicColumn(
            id: "fatturatoBase", label: "Importo Base", type: .currency, width: 120
        ) { sinistro in
            sinistro.oltreDieciBeni ? settings.importoBaseDieciBeni : settings.importoBase
        }
    }
    
    static func fatturatoBonus(settings: FatturatoSettings) -> DynamicColumn {
        DynamicColumn(
            id: "fatturatoBonus", label: "Bonus", type: .currency, width: 100
        ) { sinistro in
            if sinistro.oltreDieciBeni {
                return max(0, settings.importoBaseDieciBeni - settings.importoBase)
            }
            return 0.0
        }
    }
    
    static func fatturatoTotale(settings: FatturatoSettings) -> DynamicColumn {
        DynamicColumn(
            id: "fatturatoTotale", label: "Totale", type: .currency, width: 120
        ) { sinistro in
            let base = sinistro.oltreDieciBeni ? settings.importoBaseDieciBeni : settings.importoBase
            let bonus = sinistro.oltreDieciBeni ? max(0, settings.importoBaseDieciBeni - settings.importoBase) : 0
            return base + bonus
        }
    }
    
    // MARK: - Preset Column Sets
    
    static var defaultColumns: [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato]
    }
    
    static var closedClaimsColumns: [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .concordato, .liquidazione, .giorniGestione]
    }
    
    static var openClaimsColumns: [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .beni, .complessita]
    }
    
    static var assignedClaimsColumns: [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .agenzia, .stato, .dataAssegnazione]
    }
    
    static var sentReportsColumns: [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .stato, .liquidazione, .dataInvioAtto]
    }
    
    static func fatturatoColumns(settings: FatturatoSettings) -> [DynamicColumn] {
        [.riferimento, .assicurato, .compagnia, .beni, fatturatoBase(settings: settings), fatturatoBonus(settings: settings), fatturatoTotale(settings: settings)]
    }
}

struct FilterConfig {
    let title: String
    let subtitle: String
    let iconName: String
    let iconColor: Color
    let states: Set<String>?
    let userEmail: String?
    let dateFilter: DateFilter?
    let customFilter: ((Sinistro) -> Bool)?
    
    /// Se true, la lista mostrata deduplica per riferimento (uno per sinistro, come i KPI)
    let deduplicateByRiferimento: Bool
    
    // Sistema colonne dinamiche (nuovo)
    let dynamicColumns: [DynamicColumn]?
    
    // Sistema colonne legacy (per retrocompatibilità)
    let columnsToShow: Set<ColumnType>
    
    /// Usa colonne dinamiche se disponibili
    var usesDynamicColumns: Bool {
        dynamicColumns != nil && !dynamicColumns!.isEmpty
    }
    
    init(
        title: String,
        subtitle: String,
        iconName: String,
        iconColor: Color,
        states: Set<String>? = nil,
        userEmail: String? = nil,
        dateFilter: DateFilter? = nil,
        customFilter: ((Sinistro) -> Bool)? = nil,
        deduplicateByRiferimento: Bool = false,
        dynamicColumns: [DynamicColumn]? = nil,
        columnsToShow: Set<ColumnType> = ColumnType.suggestedForAll
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconColor = iconColor
        self.states = states
        self.userEmail = userEmail
        self.dateFilter = dateFilter
        self.customFilter = customFilter
        self.deduplicateByRiferimento = deduplicateByRiferimento
        self.dynamicColumns = dynamicColumns
        self.columnsToShow = columnsToShow
    }
    
    enum DateFilter {
        case thisYear
        case lastYear
        case last30Days
        case custom(from: Date, to: Date)
        
        func matches(date: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .thisYear:
                return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            case .lastYear:
                return calendar.component(.year, from: date) == calendar.component(.year, from: now) - 1
            case .last30Days:
                return date > now.addingTimeInterval(-30 * 24 * 60 * 60)
            case .custom(let from, let to):
                return date >= from && date <= to
            }
        }
    }
    
    enum ColumnType: String, CaseIterable, Identifiable {
        case riferimento
        case assicurato
        case compagnia
        case dataIncarico
        case stato
        case indirizzo
        case concordato
        case liquidazione
        case giorniGestione
        case solleciti
        case beni
        case complessita
        // Colonne Fatturato
        case fatturatoBase
        case fatturatoBonus
        case fatturatoTotale
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .riferimento: return "Riferimento"
            case .assicurato: return "Assicurato"
            case .compagnia: return "Compagnia"
            case .dataIncarico: return "Data Incarico"
            case .stato: return "Stato"
            case .indirizzo: return "Indirizzo"
            case .concordato: return "Concordato"
            case .liquidazione: return "Liquidazione"
            case .giorniGestione: return "Giorni Gestione"
            case .solleciti: return "Solleciti"
            case .beni: return "N° Beni"
            case .complessita: return "Complessità"
            case .fatturatoBase: return "Importo Base"
            case .fatturatoBonus: return "Bonus"
            case .fatturatoTotale: return "Totale Fatturato"
            }
        }
        
        var width: CGFloat? {
            switch self {
            case .riferimento: return 120
            case .assicurato: return nil // flessibile
            case .compagnia: return 100
            case .dataIncarico: return 100
            case .stato: return 120
            case .indirizzo: return nil
            case .concordato: return 80
            case .liquidazione: return 100
            case .giorniGestione: return 100
            case .solleciti: return 70
            case .beni: return 70
            case .complessita: return 90
            case .fatturatoBase: return 120
            case .fatturatoBonus: return 150
            case .fatturatoTotale: return 120
            }
        }
        
        /// Colonne sempre visibili (non disattivabili)
        static var mandatory: Set<ColumnType> {
            [.riferimento, .assicurato]
        }
        
        /// Colonne suggerite per sinistri chiusi
        static var suggestedForClosed: Set<ColumnType> {
            [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .concordato, .liquidazione, .giorniGestione]
        }
        
        /// Colonne suggerite per sinistri aperti
        static var suggestedForOpen: Set<ColumnType> {
            [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .solleciti, .complessita]
        }
        
        /// Colonne suggerite per tutti i sinistri
        static var suggestedForAll: Set<ColumnType> {
            [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .beni, .complessita]
        }
        
        /// Colonne suggerite per dettaglio fatturato
        static var suggestedForFatturato: Set<ColumnType> {
            [.riferimento, .assicurato, .compagnia, .beni, .fatturatoBase, .fatturatoBonus, .fatturatoTotale]
        }
    }
    
    // MARK: - Preset per ConsuntivoView
    
    static func closedSinistriForMonth(year: Int, month: Int, userEmail: String? = nil) -> FilterConfig {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let endDate = calendar.endOfMonth(for: startDate)
        let monthName = DateFormatter().monthSymbols[month - 1].capitalized
        
        // Colonne per sinistri chiusi: riferimento, assicurato, compagnia (condizionale), 
        // data assegnazione, data invio atto, data chiusura, concordata, giorni gestione
        var columns: [DynamicColumn] = [
            .riferimento,
            .assicurato
        ]
        
        // La colonna compagnia verrà aggiunta dinamicamente nella vista se ci sono almeno 2 compagnie diverse
        // Per ora la includiamo sempre, la vista la filtrerà se necessario
        columns.append(.compagnia)
        columns.append(.dataAssegnazione)
        columns.append(.dataInvioAtto)
        columns.append(.dataChiusura)
        columns.append(.concordato)
        columns.append(.giorniGestione)
        
        return FilterConfig(
            title: "Sinistri Chiusi - \(monthName) \(year)",
            subtitle: userEmail != nil ? "Di un utente specifico" : "Tutti dello studio",
            iconName: "checkmark.circle.fill",
            iconColor: .green,
            states: [StatoManager.StatoSinistro.chiusa.descrizione],
            userEmail: userEmail,
            dateFilter: nil,
            customFilter: { sinistro in
                guard let dataChiusura = sinistro.dataChiusura else { return false }
                return dataChiusura >= startDate && dataChiusura <= endDate
            },
            dynamicColumns: columns
        )
    }
    
    static func forInvoice(invoiceNumber: String, sinistri: [String], date: Date) -> FilterConfig {
        return FilterConfig(
            title: "Fattura #\(invoiceNumber)",
            subtitle: "\(sinistri.count) sinistri - \(date.formatted(date: .abbreviated, time: .omitted))",
            iconName: "doc.text.fill",
            iconColor: .blue,
            states: nil,
            userEmail: nil,
            dateFilter: nil,
            customFilter: { sinistro in
                sinistri.contains(sinistro.riferimento ?? "")
            },
            columnsToShow: [.riferimento, .assicurato, .dataIncarico, .compagnia, .stato, .liquidazione]
        )
    }
    
    static func closedInPeriod(from: Date, to: Date, userEmail: String? = nil) -> FilterConfig {
        return FilterConfig(
            title: "Sinistri Chiusi nel Periodo",
            subtitle: "Dal \(from.formatted(date: .abbreviated, time: .omitted)) al \(to.formatted(date: .abbreviated, time: .omitted))",
            iconName: "checkmark.circle.fill",
            iconColor: .green,
            states: ["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"],
            userEmail: userEmail,
            dateFilter: .custom(from: from, to: to),
            customFilter: nil,
            columnsToShow: ColumnType.suggestedForClosed
        )
    }
    
    /// Preset per Atti Inviati nel mese (dataInvioAtto nel mese di riferimento)
    static func sentReportsForMonth(year: Int, month: Int, userEmail: String? = nil) -> FilterConfig {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let endDate = calendar.endOfMonth(for: startDate)
        let monthName = DateFormatter().monthSymbols[month - 1].capitalized
        
        return FilterConfig(
            title: "Atti Inviati - \(monthName) \(year)",
            subtitle: userEmail != nil ? "Di un utente specifico" : "Tutti dello studio",
            iconName: StatoManager.StatoSinistro.attoInviato.icon,
            iconColor: StatoManager.StatoSinistro.attoInviato.color,
            states: nil,
            userEmail: userEmail,
            dateFilter: nil,
            customFilter: { sinistro in
                guard let dataInvio = sinistro.dataInvioAtto else { return false }
                return dataInvio >= startDate && dataInvio <= endDate
            },
            columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .liquidazione]
        )
    }
    
    /// Preset per Assegnazioni nel mese (solo dataAssegnazione nel mese di riferimento, no import/creazione)
    static func assignedClaimsForMonth(year: Int, month: Int, userEmail: String? = nil) -> FilterConfig {
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let endDate = calendar.endOfMonth(for: startDate)
        let monthName = DateFormatter().monthSymbols[month - 1].capitalized
        
        return FilterConfig(
            title: "Nuove Assegnazioni - \(monthName) \(year)",
            subtitle: userEmail != nil ? "Di un utente specifico" : "Tutti dello studio",
            iconName: "envelope.badge.fill",
            iconColor: .blue,
            states: nil,
            userEmail: userEmail,
            dateFilter: nil,
            customFilter: { sinistro in
                guard let dataAssegnazione = sinistro.dataAssegnazione else { return false }
                return dataAssegnazione >= startDate && dataAssegnazione <= endDate
            },
            deduplicateByRiferimento: true,
            columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato, .complessita]
        )
    }
    
    /// Preset con lista sinistri esplicita (per KPI)
    static func forSinistriList(_ sinistri: [Sinistro], title: String, subtitle: String, iconName: String, iconColor: Color, columns: Set<ColumnType>) -> FilterConfig {
        let riferimenti = Set(sinistri.compactMap { $0.riferimento })
        return FilterConfig(
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            iconColor: iconColor,
            states: nil,
            userEmail: nil,
            dateFilter: nil,
            customFilter: { sinistro in
                guard let rif = sinistro.riferimento else { return false }
                // Escludi sinistri eliminati
                if sinistro.stato?.lowercased() == "eliminato" { return false }
                return riferimenti.contains(rif)
            },
            columnsToShow: columns
        )
    }
    
    /// Preset per dettaglio fatturato mensile
    static func fatturatoDetailForMonth(year: Int, month: Int, sinistri: [Sinistro], totaleFatturato: Double, settings: FatturatoSettings = .shared) -> FilterConfig {
        let monthName = DateFormatter().monthSymbols[month - 1].capitalized
        let riferimenti = Set(sinistri.compactMap { $0.riferimento })
        
        return FilterConfig(
            title: "Dettaglio Fatturato - \(monthName) \(year)",
            subtitle: "\(sinistri.count) sinistri • Totale: \(CurrencyFormatter.shared.formatWithSymbol(totaleFatturato))",
            iconName: "eurosign.circle.fill",
            iconColor: .purple,
            states: nil,
            userEmail: nil,
            dateFilter: nil,
            customFilter: { sinistro in
                guard let rif = sinistro.riferimento else { return false }
                if sinistro.stato?.lowercased() == "eliminato" { return false }
                return riferimenti.contains(rif)
            },
            dynamicColumns: DynamicColumn.fatturatoColumns(settings: settings)
        )
    }
    
    /// Crea config con colonne dinamiche custom
    static func withDynamicColumns(
        title: String,
        subtitle: String,
        iconName: String,
        iconColor: Color,
        columns: [DynamicColumn],
        customFilter: ((Sinistro) -> Bool)? = nil
    ) -> FilterConfig {
        FilterConfig(
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            iconColor: iconColor,
            customFilter: customFilter,
            dynamicColumns: columns
        )
    }
    
    // MARK: - From Hashtag
    
    static func from(hashtag: ChatHashtag, senderEmail: String, senderName: String) -> FilterConfig {
        let tag = hashtag.tag
        let filter = hashtag.filter ?? "utente"
        
        // Determina email target
        let targetEmail: String? = {
            switch filter {
            case "utente", "miei":
                return senderEmail
            case "studio", "tutti":
                return nil
            default:
                return senderEmail
            }
        }()
        
        // Configura in base al tag
        switch tag {
        case "chiusure", "chiusi":
            return FilterConfig(
                title: "Sinistri Chiusi",
                subtitle: filter == "utente" ? "Di \(senderName)" : "Tutti dello studio",
                iconName: "checkmark.circle.fill",
                iconColor: .green,
                states: ["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"],
                userEmail: targetEmail,
                dateFilter: nil,
                customFilter: nil,
                columnsToShow: ColumnType.suggestedForClosed
            )
            
        case "aperti":
            return FilterConfig(
                title: "Sinistri Aperti",
                subtitle: filter == "utente" ? "Di \(senderName)" : "Tutti dello studio",
                iconName: "folder.fill",
                iconColor: .blue,
                states: nil, // Tutti tranne chiusi
                userEmail: targetEmail,
                dateFilter: nil,
                customFilter: { sinistro in
                    let stato = sinistro.stato ?? ""
                    return !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                },
                columnsToShow: ColumnType.suggestedForOpen
            )
            
        case "sinistri":
            return FilterConfig(
                title: "Tutti i Sinistri",
                subtitle: filter == "utente" ? "Di \(senderName)" : "Tutti dello studio",
                iconName: "folder.fill.badge.gearshape",
                iconColor: .orange,
                states: nil,
                userEmail: targetEmail,
                dateFilter: nil,
                customFilter: nil,
                columnsToShow: ColumnType.suggestedForAll
            )
            
        case "assegnati":
            return FilterConfig(
                title: "Sinistri Assegnati",
                subtitle: "A \(senderName)",
                iconName: "person.crop.circle.fill.badge.checkmark",
                iconColor: .purple,
                states: nil,
                userEmail: senderEmail,
                dateFilter: nil,
                customFilter: { sinistro in
                    let stato = sinistro.stato ?? ""
                    return !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                },
                columnsToShow: ColumnType.suggestedForOpen
            )
            
        case "urgenti":
            return FilterConfig(
                title: "Sinistri Urgenti",
                subtitle: filter == "utente" ? "Di \(senderName)" : "Tutti dello studio",
                iconName: "exclamationmark.triangle.fill",
                iconColor: .red,
                states: nil,
                userEmail: targetEmail,
                dateFilter: nil,
                customFilter: { sinistro in
                    // TODO: Implementare logica urgenza con task system
                    // Per ora: sinistri aperti recenti
                    let stato = sinistro.stato ?? ""
                    let notClosed = !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                    return notClosed && sinistro.isRecente
                },
                columnsToShow: [.riferimento, .assicurato, .dataIncarico, .stato, .solleciti, .complessita]
            )
            
        case "scadenze":
            return FilterConfig(
                title: "Sinistri con Scadenze",
                subtitle: filter == "utente" ? "Di \(senderName)" : "Tutti dello studio",
                iconName: "calendar.badge.clock",
                iconColor: .orange,
                states: nil,
                userEmail: targetEmail,
                dateFilter: nil,
                customFilter: { sinistro in
                    // TODO: Implementare filtro con task system
                    // Per ora: sinistri aperti degli ultimi 30 giorni
                    let stato = sinistro.stato ?? ""
                    let notClosed = !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                    
                    if let dataIncarico = sinistro.dataIncarico {
                        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                        return notClosed && dataIncarico >= thirtyDaysAgo
                    }
                    return false
                },
                columnsToShow: [.riferimento, .assicurato, .dataIncarico, .stato, .solleciti]
            )
            
        default:
            return FilterConfig(
                title: "Sinistri",
                subtitle: "Tutti",
                iconName: "folder.fill",
                iconColor: .gray,
                states: nil,
                userEmail: nil,
                dateFilter: nil,
                customFilter: nil,
                columnsToShow: ColumnType.suggestedForAll
            )
        }
    }
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable, Identifiable {
    case dataIncaricoDesc = "Data Incarico (recente)"
    case dataIncaricoAsc = "Data Incarico (meno recente)"
    case riferimentoAsc = "Riferimento (A-Z)"
    case riferimentoDesc = "Riferimento (Z-A)"
    case assicuratoAsc = "Assicurato (A-Z)"
    case assicuratoDesc = "Assicurato (Z-A)"
    
    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Dynamic Column Row

struct DynamicColumnRow: View {
    let sinistro: Sinistro
    let columns: [DynamicColumn]
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icona stato
            Circle()
                .fill(stateColor.opacity(0.2))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(stateColor, lineWidth: 2)
                )
            
            // Colonne dinamiche
            ForEach(columns) { column in
                columnView(for: column)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private func columnView(for column: DynamicColumn) -> some View {
        let value = column.value(for: sinistro)
        
        Group {
            switch column.type {
            case .text:
                Text(value as? String ?? "—")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .leading)
                
            case .number:
                if let num = value as? Int {
                    Text("\(num)")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .center)
                } else if let num = value as? Double {
                    Text(String(format: "%.0f", num))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .center)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .center)
                }
                
            case .currency:
                if let amount = value as? Double, amount > 0 {
                    Text(CurrencyFormatter.shared.formatWithSymbol(amount))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .trailing)
                }
                
            case .date:
                if let date = value as? Date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
                
            case .bool:
                let boolValue = value as? Bool ?? false
                HStack(spacing: 4) {
                    Image(systemName: boolValue ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(boolValue ? .green : .secondary)
                    Text(boolValue ? "Sì" : "No")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(width: column.width, alignment: .center)
                
            case .state:
                let stateText = value as? String ?? "—"
                Text(stateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor.opacity(0.12))
                    .cornerRadius(6)
                    .frame(width: column.width, alignment: .leading)
                
            case .stars(let max):
                let starValue = value as? Int ?? 0
                HStack(spacing: 2) {
                    ForEach(0..<max, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(index < starValue ? .orange : .secondary.opacity(0.3))
                    }
                }
                .frame(width: column.width, alignment: .center)
                
            case .custom(let renderer):
                renderer(value)
                    .frame(width: column.width)
            }
        }
    }
    
    private var stateColor: Color {
        let stato = sinistro.stato ?? ""
        if stato.lowercased().contains("chiuso") {
            return .green
        } else if stato.lowercased().contains("sospeso") {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Compact Row (Legacy)

struct SinistroCompactRow: View {
    let sinistro: Sinistro
    let showColumns: Set<FilterConfig.ColumnType>
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icona stato
            Circle()
                .fill(stateColor.opacity(0.2))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(stateColor, lineWidth: 2)
                )
            
            // Colonne dinamiche
            ForEach(Array(showColumns).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { column in
                columnView(for: column)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private func columnView(for column: FilterConfig.ColumnType) -> some View {
        Group {
            switch column {
            case .riferimento:
                Text(sinistro.riferimento ?? "—")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: column.width, alignment: .leading)
                
            case .assicurato:
                Text(sinistro.nomeAssicurato ?? "—")
                    .font(.system(size: 13))
                    .frame(minWidth: 150, alignment: .leading)
                
            case .compagnia:
                Text(sinistro.nomeCompagnia ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: column.width, alignment: .leading)
                
            case .dataIncarico:
                if let data = sinistro.dataIncarico {
                    Text(data.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
                
            case .stato:
                Text(sinistro.stato ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor.opacity(0.12))
                    .cornerRadius(6)
                    .frame(width: column.width, alignment: .leading)
                
            case .indirizzo:
                Text(sinistro.indirizzoAssicurato ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 150, alignment: .leading)
                
            case .concordato:
                HStack(spacing: 4) {
                    Image(systemName: sinistro.isConcordata ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(sinistro.isConcordata ? .green : .secondary)
                    Text(sinistro.isConcordata ? "Sì" : "No")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(width: column.width, alignment: .center)
                
            case .liquidazione:
                if let importo = sinistro.importoLiquidatoEffettivo, importo.doubleValue > 0 {
                    Text(importo.doubleValue, format: .currency(code: "EUR"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: column.width, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .trailing)
                }
                
            case .giorniGestione:
                if let giorni = calcolaGiorniGestione() {
                    HStack(spacing: 4) {
                        Text("\(giorni)")
                            .font(.system(size: 12, weight: .medium))
                        Text("gg")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: column.width, alignment: .center)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .center)
                }
                
            case .solleciti:
                // TODO: Implementare conteggio solleciti reale
                let count = 0 // Placeholder: contare eventi con intent = .reminder
                HStack(spacing: 4) {
                    Image(systemName: count > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 10))
                        .foregroundColor(count > 2 ? .red : (count > 0 ? .orange : .secondary))
                    Text("\(count)")
                        .font(.system(size: 12, weight: count > 0 ? .medium : .regular))
                }
                .frame(width: column.width, alignment: .center)
                
            case .beni:
                let count = sinistro.numeroBeni
                HStack(spacing: 4) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(count)")
                        .font(.system(size: 12))
                }
                .frame(width: column.width, alignment: .center)
                
            case .complessita:
                let grado = sinistro.gradoComplessita
                if grado != .unknown {
                    let stelleValue: Int = {
                        switch grado {
                        case .bassa: return 1
                        case .media: return 2
                        case .alta, .moltaAlta: return 3
                        default: return 0
                        }
                    }()
                    
                    HStack(spacing: 2) {
                        ForEach(Array(1...5), id: \.self) { star in
                            let iconName: String = (star <= stelleValue) ? "star.fill" : "star"
                            Image(systemName: iconName)
                                .font(.system(size: 10))
                                .foregroundColor(star <= stelleValue ? .orange : .secondary.opacity(0.3))
                        }
                    }
                    .frame(width: column.width, alignment: .center)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .center)
                }
                
            case .fatturatoBase:
                let importo = calcolaImportoBaseFatturato()
                Text(CurrencyFormatter.shared.formatWithSymbol(importo))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: column.width, alignment: .trailing)
                
            case .fatturatoBonus:
                let bonusTotal = calcolaBonusFatturato()
                if bonusTotal > 0 {
                    Text("+\(CurrencyFormatter.shared.formatWithSymbol(bonusTotal))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: column.width, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .trailing)
                }
                
            case .fatturatoTotale:
                let totale = calcolaTotaleFatturato()
                Text(CurrencyFormatter.shared.formatWithSymbol(totale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                    .frame(width: column.width, alignment: .trailing)
            }
        }
    }
    
    // MARK: - Fatturato Helpers
    
    private func calcolaImportoBaseFatturato() -> Double {
        let settings = FatturatoSettings.shared
        if sinistro.oltreDieciBeni {
            return settings.importoBaseDieciBeni
        }
        return settings.importoBase
    }
    
    private func calcolaBonusFatturato() -> Double {
        let settings = FatturatoSettings.shared
        var bonus: Double = 0
        
        // Bonus oltre 10 beni
        if sinistro.oltreDieciBeni {
            let incremento = settings.importoBaseDieciBeni - settings.importoBase
            if incremento > 0 {
                bonus += incremento
            }
        }
        
        return bonus
    }
    
    private func calcolaTotaleFatturato() -> Double {
        return calcolaImportoBaseFatturato() + calcolaBonusFatturato()
    }
    
    private func calcolaGiorniGestione() -> Int? {
        ConsuntivoStatsService.shared.giorniGestione(for: sinistro)
    }
    
    private var stateColor: Color {
        let stato = sinistro.stato ?? ""
        if stato.lowercased().contains("chiuso") {
            return .green
        } else if stato.lowercased().contains("sospeso") {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Column Picker Popover

struct ColumnPickerPopover: View {
    @Binding var visibleColumns: Set<FilterConfig.ColumnType>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colonne Visibili")
                .font(.system(size: 14, weight: .semibold))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FilterConfig.ColumnType.allCases) { column in
                        let isMandatory = FilterConfig.ColumnType.mandatory.contains(column)
                        
                        Toggle(isOn: Binding(
                            get: { visibleColumns.contains(column) },
                            set: { isOn in
                                if isOn {
                                    visibleColumns.insert(column)
                                } else if !isMandatory {
                                    visibleColumns.remove(column)
                                }
                            }
                        )) {
                            HStack {
                                Text(column.label)
                                    .font(.system(size: 12))
                                
                                if isMandatory {
                                    Text("(obbligatoria)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(isMandatory)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            HStack {
                Button("Reimposta") {
                    visibleColumns = FilterConfig.ColumnType.suggestedForAll
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
                
                Spacer()
                
                Text("\(visibleColumns.count) colonne")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let sinistri: [Sinistro]
    let config: FilterConfig
    let visibleColumns: Set<FilterConfig.ColumnType>
    let dynamicColumns: [DynamicColumn]?
    @Environment(\.dismiss) private var dismiss
    
    @State private var exportFormat: ExportFormat = .csv
    @State private var includeHeaders = true
    
    private var columnCount: Int {
        dynamicColumns?.count ?? visibleColumns.count
    }
    
    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case excel = "Excel (XLSX)"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Esporta Sinistri")
                .font(.system(size: 18, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                    Text("\(sinistri.count) sinistri")
                        .font(.system(size: 14))
                }
                
                HStack {
                    Image(systemName: "tablecells")
                        .foregroundColor(.accentColor)
                    Text("\(columnCount) colonne")
                        .font(.system(size: 14))
                }
            }
            .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Formato")
                    .font(.system(size: 13, weight: .medium))
                
                Picker("Formato", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Toggle("Includi intestazioni", isOn: $includeHeaders)
                .font(.system(size: 12))
            
            Text("L'export includerà le colonne attualmente visibili nella tabella.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Esporta") {
                    exportData()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
    
    private func exportData() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = exportFormat == .csv ? [.commaSeparatedText] : [.init(filenameExtension: "xlsx")!]
        savePanel.nameFieldStringValue = "\(config.title) - \(Date().formatted(date: .abbreviated, time: .omitted))"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                let data = generateExportData()
                try data.write(to: url, atomically: true, encoding: .utf8)
                
                NSWorkspace.shared.open(url)
            } catch {
                print("❌ Errore esportazione: \(error)")
            }
        }
    }
    
    private func generateExportData() -> String {
        var csv = ""
        
        // Usa colonne dinamiche se disponibili
        if let dynCols = dynamicColumns, !dynCols.isEmpty {
            // Headers
            if includeHeaders {
                let headers = dynCols.map { $0.label }
                csv += headers.joined(separator: ";") + "\n"
            }
            
            // Rows
            for sinistro in sinistri {
                var row: [String] = []
                
                for column in dynCols {
                    let value = exportDynamicValue(for: column, sinistro: sinistro)
                    row.append(value)
                }
                
                csv += row.joined(separator: ";") + "\n"
            }
        } else {
            // Legacy: usa colonne statiche
            // Headers
            if includeHeaders {
                let headers = visibleColumns.sorted { $0.rawValue < $1.rawValue }.map { $0.label }
                csv += headers.joined(separator: ";") + "\n"
            }
            
            // Rows
            for sinistro in sinistri {
                var row: [String] = []
                
                for column in visibleColumns.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let value = exportValue(for: column, sinistro: sinistro)
                    row.append(value)
                }
                
                csv += row.joined(separator: ";") + "\n"
            }
        }
        
        return csv
    }
    
    private func exportDynamicValue(for column: DynamicColumn, sinistro: Sinistro) -> String {
        let value = column.value(for: sinistro)
        
        switch column.type {
        case .text, .state:
            return value as? String ?? ""
        case .number:
            if let num = value as? Int {
                return "\(num)"
            } else if let num = value as? Double {
                return String(format: "%.0f", num)
            }
            return ""
        case .currency:
            if let amount = value as? Double {
                return CurrencyFormatter.shared.format(amount) // Formato italiano: X.XXX,XX
            }
            return ""
        case .date:
            if let date = value as? Date {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return ""
        case .bool:
            return (value as? Bool ?? false) ? "Sì" : "No"
        case .stars:
            return "\(value as? Int ?? 0)"
        case .custom:
            return "\(value ?? "")"
        }
    }
    
    private func exportValue(for column: FilterConfig.ColumnType, sinistro: Sinistro) -> String {
        switch column {
        case .riferimento:
            return sinistro.riferimento ?? ""
        case .assicurato:
            return sinistro.nomeAssicurato ?? ""
        case .compagnia:
            return sinistro.nomeCompagnia ?? ""
        case .dataIncarico:
            if let data = sinistro.dataIncarico {
                return data.formatted(date: .abbreviated, time: .omitted)
            }
            return ""
        case .stato:
            return sinistro.stato ?? ""
        case .indirizzo:
            return sinistro.indirizzoAssicurato ?? ""
        case .concordato:
            return sinistro.isConcordata ? "Sì" : "No"
        case .liquidazione:
            if let importo = sinistro.importoLiquidatoEffettivo, importo.doubleValue > 0 {
                return CurrencyFormatter.shared.format(importo.doubleValue)
            }
            return ""
        case .giorniGestione:
            if let giorni = calcolaGiorniGestione(sinistro: sinistro) {
                return "\(giorni)"
            }
            return ""
        case .solleciti:
            return "0" // TODO: Implementare conteggio solleciti
        case .beni:
            return "\(sinistro.numeroBeni)"
        case .complessita:
            let grado = sinistro.gradoComplessita
            switch grado {
            case .bassa: return "1"
            case .media: return "2"
            case .alta: return "3"
            case .moltaAlta: return "3"
            default: return ""
            }
        case .fatturatoBase:
            let settings = FatturatoSettings.shared
            let importo = sinistro.oltreDieciBeni ? settings.importoBaseDieciBeni : settings.importoBase
            return CurrencyFormatter.shared.format(importo)
        case .fatturatoBonus:
            let settings = FatturatoSettings.shared
            if sinistro.oltreDieciBeni {
                let bonus = settings.importoBaseDieciBeni - settings.importoBase
                return bonus > 0 ? CurrencyFormatter.shared.format(bonus) : ""
            }
            return ""
        case .fatturatoTotale:
            let settings = FatturatoSettings.shared
            let base = sinistro.oltreDieciBeni ? settings.importoBaseDieciBeni : settings.importoBase
            let bonus = sinistro.oltreDieciBeni ? max(0, settings.importoBaseDieciBeni - settings.importoBase) : 0
            return CurrencyFormatter.shared.format(base + bonus)
        }
    }
    
    private func calcolaGiorniGestione(sinistro: Sinistro) -> Int? {
        ConsuntivoStatsService.shared.giorniGestione(for: sinistro)
    }
}

// MARK: - Filtered Sinistro Table Row

struct FilteredSinistroTableRow: View {
    let sinistro: Sinistro
    let config: FilterConfig
    let visibleColumns: Set<FilterConfig.ColumnType>
    let visibleDynamicColumns: [DynamicColumn]
    let statoColor: Color
    let onTap: () -> Void
    
    @StateObject private var viewModel = FilteredSinistriViewModel()
    
    var body: some View {
        HStack(spacing: 0) {
            // Prima colonna sempre riferimento
            Text(sinistro.riferimento ?? "—")
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onTapGesture(perform: onTap)
            
            // Seconda colonna sempre nome contraente
            Text(sinistro.nomeAssicurato ?? "—")
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            // Altre colonne opzionali
            if config.usesDynamicColumns {
                ForEach(visibleDynamicColumns.dropFirst(2)) { column in
                    columnCellView(for: column)
                }
            } else {
                let optionalColumns = Array(visibleColumns).sorted(by: { $0.rawValue < $1.rawValue })
                    .filter { $0 != .riferimento && $0 != .assicurato }
                
                ForEach(optionalColumns, id: \.self) { column in
                    columnCellView(for: column)
                }
            }
            
            // Spacer per evitare che le colonne vengano tagliate
            Spacer(minLength: 0)
                .frame(minWidth: 0)
        }
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(statoColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(statoColor.opacity(0.3), lineWidth: 1)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(sinistro.riferimento ?? "", forType: .string)
            } label: {
                Label("Copia Riferimento", systemImage: "doc.on.doc")
            }
            
            Button {
                onTap()
            } label: {
                Label("Apri in nuova finestra", systemImage: "rectangle.split.2x1")
            }
        }
    }
    
    @ViewBuilder
    private func columnCellView(for column: DynamicColumn) -> some View {
        let value = column.value(for: sinistro)
        
        Group {
            switch column.type {
            case .text:
                Text(value as? String ?? "—")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .leading)
            case .number:
                if let num = value as? Int {
                    Text("\(num)")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .center)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .center)
                }
            case .currency:
                if let amount = value as? Double, amount > 0 {
                    Text(CurrencyFormatter.shared.formatWithSymbol(amount))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .trailing)
                }
            case .date:
                if let date = value as? Date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
            case .bool:
                let boolValue = value as? Bool ?? false
                HStack(spacing: 4) {
                    Image(systemName: boolValue ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(boolValue ? .green : .secondary)
                    Text(boolValue ? "Sì" : "No")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(width: column.width, alignment: .center)
            case .state:
                let stateText = value as? String ?? "—"
                Text(stateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statoColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statoColor.opacity(0.12))
                    .cornerRadius(6)
                    .frame(width: column.width, alignment: .leading)
            case .stars:
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: column.width, alignment: .center)
            case .custom:
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: column.width, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func columnCellView(for column: FilterConfig.ColumnType) -> some View {
        Group {
            switch column {
            case .riferimento, .assicurato:
                EmptyView() // Già mostrati come prime due colonne
            case .compagnia:
                Text(sinistro.nomeCompagnia ?? "—")
                    .lineLimit(1)
                    .frame(width: column.width, alignment: .leading)
            case .dataIncarico:
                if let data = sinistro.dataIncarico {
                    Text(data.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
            case .stato:
                Text(sinistro.stato ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statoColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statoColor.opacity(0.12))
                    .cornerRadius(6)
                    .frame(width: column.width, alignment: .leading)
            case .liquidazione:
                if let importo = sinistro.importoLiquidatoEffettivo, importo.doubleValue > 0 {
                    Text(CurrencyFormatter.shared.formatWithSymbol(importo.doubleValue))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: column.width, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .trailing)
                }
            case .giorniGestione:
                if let giorni = viewModel.calcolaGiorniGestione(for: sinistro) {
                    HStack(spacing: 4) {
                        Text("\(giorni)")
                            .font(.system(size: 12, weight: .medium))
                        Text("gg")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: column.width, alignment: .center)
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: column.width, alignment: .center)
                }
            case .concordato:
                HStack(spacing: 4) {
                    Image(systemName: sinistro.isConcordata ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(sinistro.isConcordata ? .green : .secondary)
                    Text(sinistro.isConcordata ? "Sì" : "No")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(width: column.width, alignment: .center)
            case .indirizzo:
                Text(sinistro.indirizzoAssicurato ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 150, alignment: .leading)
            case .solleciti:
                // TODO: Implementare conteggio solleciti reale
                let count = 0
                HStack(spacing: 4) {
                    Image(systemName: count > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(count)")
                        .font(.system(size: 12))
                }
                .frame(width: column.width, alignment: .center)
            case .beni:
                Text("\(sinistro.numeroBeni)")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: column.width, alignment: .center)
            case .complessita:
                let rating = Int(sinistro.complessita ?? "0") ?? 0
                HStack(spacing: 2) {
                    ForEach(Array(1...5), id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundColor(star <= rating ? .yellow : .gray.opacity(0.3))
                    }
                }
                .frame(width: column.width, alignment: .center)
            case .fatturatoBase, .fatturatoBonus, .fatturatoTotale:
                // Queste sono gestite separatamente in configurazioni fatturato
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: column.width, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Window Helper

/// Helper per aprire FilteredSinistriWindow in una nuova finestra
struct FilteredSinistriWindowHelper {
    /// Apre una finestra con i sinistri filtrati dalla configurazione
    @MainActor
    static func open(config: FilterConfig) {
        let windowView = FilteredSinistriWindow(config: config)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        
        let hostingController = NSHostingController(rootView: windowView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = config.title
        window.setContentSize(NSSize(width: 900, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Apre una finestra con una lista di sinistri esplicita (colonne legacy)
    @MainActor
    static func open(sinistri: [Sinistro], title: String, subtitle: String, iconName: String, iconColor: Color, columns: Set<FilterConfig.ColumnType> = FilterConfig.ColumnType.suggestedForAll) {
        let config = FilterConfig.forSinistriList(
            sinistri,
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            iconColor: iconColor,
            columns: columns
        )
        open(config: config)
    }
    
    /// Apre una finestra con colonne dinamiche
    @MainActor
    static func open(
        sinistri: [Sinistro],
        title: String,
        subtitle: String,
        iconName: String,
        iconColor: Color,
        dynamicColumns: [DynamicColumn]
    ) {
        let riferimenti = Set(sinistri.compactMap { $0.riferimento })
        
        let config = FilterConfig(
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            iconColor: iconColor,
            customFilter: { sinistro in
                guard let rif = sinistro.riferimento else { return false }
                if sinistro.stato?.lowercased() == "eliminato" { return false }
                return riferimenti.contains(rif)
            },
            dynamicColumns: dynamicColumns
        )
        open(config: config)
    }
}

#Preview {
    FilteredSinistriWindow(
        config: FilterConfig(
            title: "Sinistri Chiusi",
            subtitle: "Di Marco Pernozzoli",
            iconName: "checkmark.circle.fill",
            iconColor: .green,
            states: ["Chiuso"],
            userEmail: "m.pernozzoli@actsrl.it",
            dateFilter: nil,
            customFilter: nil,
            columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato]
        )
    )
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

