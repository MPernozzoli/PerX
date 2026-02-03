import SwiftUI

// MARK: - Tipo di dettaglio KPI

enum KPIDetailType {
    case sinistroChiuso
    case attoInviato
    case assegnazione
    
    var title: String {
        switch self {
        case .sinistroChiuso: return "Sinistri Chiusi"
        case .attoInviato: return "Atti Inviati"
        case .assegnazione: return "Nuove Assegnazioni"
        }
    }
    
    var icon: String {
        switch self {
        case .sinistroChiuso: return StatoManager.StatoSinistro.chiusa.icon
        case .attoInviato: return StatoManager.StatoSinistro.attoInviato.icon
        case .assegnazione: return "envelope.badge.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .sinistroChiuso: return StatoManager.StatoSinistro.chiusa.color
        case .attoInviato: return StatoManager.StatoSinistro.attoInviato.color
        case .assegnazione: return .blue
        }
    }
    
    var dateLabel: String {
        switch self {
        case .sinistroChiuso: return "Data Chiusura"
        case .attoInviato: return "Data Invio"
        case .assegnazione: return "Data Assegnazione"
        }
    }
}

// MARK: - KPI Sinistri Detail View (Generica)

struct KPISinistriDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let sinistri: [Sinistro]
    let type: KPIDetailType
    let monthYearString: String
    let onOpenSinistro: (Sinistro) -> Void
    
    @State private var copiedReference: String?
    @State private var showCopyNotification = false
    
    /// Filtra i sinistri escludendo quelli eliminati
    private var activeSinistri: [Sinistro] {
        sinistri.filter { !$0.isDeleted && $0.stato?.lowercased() != "eliminato" }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerView
            
            // Tabella
            tableView
            
            // Notifica copia
            copyNotificationView
        }
        .frame(minWidth: 800, minHeight: 400)
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                Text("\(type.title) - \(monthYearString)")
                    .font(.headline)
                
                Text("(\(activeSinistri.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Chiudi") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }
    
    @ViewBuilder
    private var tableView: some View {
        switch type {
        case .sinistroChiuso:
            closedClaimsTable
        case .attoInviato:
            sentReportsTable
        case .assegnazione:
            assignedClaimsTable
        }
    }
    
    private var closedClaimsTable: some View {
        Table(activeSinistri) {
            TableColumn("Riferimento") { sinistro in
                riferimentoCell(sinistro)
            }
            
            TableColumn("Assicurato") { sinistro in
                Text(sinistro.nomeAssicurato ?? "")
            }
            
            TableColumn("Compagnia") { sinistro in
                Text(sinistro.agenzia ?? "")
            }
            
            TableColumn("Richiesta") { sinistro in
                if let richiesta = sinistro.richiesta?.doubleValue {
                    Text(CurrencyFormatter.shared.formatWithSymbol(richiesta))
                } else {
                    Text("-")
                }
            }
            
            TableColumn("Liquidato") { sinistro in
                if let liquidato = sinistro.liquidato?.doubleValue {
                    Text(CurrencyFormatter.shared.formatWithSymbol(liquidato))
                } else {
                    Text("-")
                }
            }
            
            TableColumn("Data Chiusura") { sinistro in
                if let data = sinistro.dataChiusura {
                    Text(formatDate(data))
                } else {
                    Text("-")
                }
            }
        }
    }
    
    private var sentReportsTable: some View {
        let tableData: [Sinistro] = activeSinistri
        return Table(tableData) {
            TableColumn("Riferimento") { (item: Sinistro) in
                riferimentoCell(item)
            }
            
            TableColumn("Assicurato") { (item: Sinistro) in
                Text(item.nomeAssicurato ?? "")
            }
            
            TableColumn("Compagnia") { (item: Sinistro) in
                Text(item.agenzia ?? "")
            }
            
            TableColumn("Stato") { (item: Sinistro) in
                HStack(spacing: 4) {
                    Circle()
                        .fill(getStatoColor(item.stato))
                        .frame(width: 8, height: 8)
                    Text(item.stato ?? "-")
                        .font(.caption)
                }
            }
            
            TableColumn("Liquidato") { (item: Sinistro) in
                if let liquidato = item.liquidato?.doubleValue {
                    Text(CurrencyFormatter.shared.formatWithSymbol(liquidato))
                } else {
                    Text("-")
                }
            }
            
            TableColumn("Data Invio Atto") { (item: Sinistro) in
                if let data = item.dataInvioAtto {
                    Text(formatDate(data))
                } else {
                    Text("-")
                }
            }
        }
    }
    
    private var assignedClaimsTable: some View {
        let tableData: [Sinistro] = activeSinistri
        return Table(tableData) {
            TableColumn("Riferimento") { (item: Sinistro) in
                riferimentoCell(item)
            }
            
            TableColumn("Assicurato") { (item: Sinistro) in
                Text(item.nomeAssicurato ?? "")
            }
            
            TableColumn("Compagnia") { (item: Sinistro) in
                Text(item.nomeCompagnia ?? "")
            }
            
            TableColumn("Agenzia") { (item: Sinistro) in
                Text(item.agenzia ?? "-")
            }
            
            TableColumn("Stato") { (item: Sinistro) in
                HStack(spacing: 4) {
                    Circle()
                        .fill(getStatoColor(item.stato))
                        .frame(width: 8, height: 8)
                    Text(item.stato ?? "-")
                        .font(.caption)
                }
            }
            
            TableColumn("Data Assegnazione") { (item: Sinistro) in
                if let data = item.dataAssegnazione {
                    Text(formatDate(data))
                } else if let data = item.dataIncarico {
                    Text(formatDate(data))
                } else {
                    Text("-")
                }
            }
        }
    }
    
    private func riferimentoCell(_ sinistro: Sinistro) -> some View {
        Text(sinistro.riferimentoVisualizzato)
            .foregroundColor(.blue)
            .onTapGesture {
                dismiss()
                onOpenSinistro(sinistro)
            }
            .contextMenu {
                Button(action: {
                    copyToClipboard(sinistro.riferimento ?? "")
                }) {
                    Text("Copia Riferimento")
                    Image(systemName: "doc.on.doc")
                }
                
                Button(action: {
                    onOpenSinistro(sinistro)
                }) {
                    Text("Apri Sinistro")
                    Image(systemName: "arrow.up.right.square")
                }
            }
    }
    
    @ViewBuilder
    private var copyNotificationView: some View {
        if let copiedRef = copiedReference {
            HStack {
                Image(systemName: "doc.on.doc")
                Text("Riferimento \(copiedRef) copiato")
            }
            .foregroundColor(.secondary)
            .font(.caption)
            .opacity(showCopyNotification ? 1 : 0)
            .animation(.easeInOut, value: showCopyNotification)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedReference = text
        showCopyNotification = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyNotification = false
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatMedium(date)
    }
    
    private func getStatoColor(_ stato: String?) -> Color {
        guard let stato = stato,
              let statoId = StatoManager.shared.getStatoId(fromDescrizione: stato),
              let statoEnum = StatoManager.StatoSinistro(rawValue: statoId) else {
            return .secondary
        }
        return statoEnum.color
    }
}

// MARK: - ClosedClaimsDetailView (Retrocompatibilità)

struct ClosedClaimsDetailView: View {
    let sinistri: [Sinistro]
    let monthYearString: String
    let onOpenSinistro: (Sinistro) -> Void
    
    var body: some View {
        KPISinistriDetailView(
            sinistri: sinistri,
            type: .sinistroChiuso,
            monthYearString: monthYearString,
            onOpenSinistro: onOpenSinistro
        )
    }
} 