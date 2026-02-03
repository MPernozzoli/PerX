import SwiftUI
import AppKit

// MARK: - Esempio di integrazione in ConsuntivoView

/*
 
 Questo file mostra come integrare FilteredSinistriWindow in ConsuntivoView.
 
 PASSAGGI:
 1. Sostituire le tabelle statiche con pulsanti che aprono FilteredSinistriWindow
 2. Mantenere il conteggio visibile ma rendere la lista apribile su richiesta
 3. Aggiungere export rapido per ogni sezione
 
*/

// MARK: - Helper per aprire finestre

extension View {
    func openFilteredSinistriWindow(config: FilterConfig) {
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
}

/*
 
 AGGIORNAMENTO: Nuove Colonne Disponibili
 
 La FilteredSinistriWindow ora supporta colonne dinamiche e avanzate:
 
 Colonne Base:
 - riferimento, assicurato, compagnia, dataIncarico, stato, indirizzo
 
 Colonne Avanzate:
 - concordato: Sì/No con icona
 - liquidazione: Importo € formattato
 - giorniGestione: Giorni tra assegnazione e chiusura (solo per chiusi)
 - solleciti: N° solleciti con icona colorata
 - beni: N° beni del sinistro
 - complessita: Stelle da 1 a 3
 
 Preset Automatici:
 - ColumnType.suggestedForClosed: Per sinistri chiusi
 - ColumnType.suggestedForOpen: Per sinistri aperti
 - ColumnType.suggestedForAll: Per tutti i sinistri
 
*/

// MARK: - Esempio 1: Sinistri Chiusi del Mese

struct ConsuntivoClosedSinistriCard: View {
    let year: Int
    let month: Int
    let count: Int
    let userEmail: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sinistri Chiusi")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("\(count) pratiche")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green.opacity(0.8))
            }
            
            HStack(spacing: 8) {
                Button {
                    let config = FilterConfig.closedSinistriForMonth(
                        year: year,
                        month: month,
                        userEmail: userEmail
                    )
                    openFilteredSinistriWindow(config: config)
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Visualizza Lista")
                    }
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button {
                    exportClosedSinistri()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .help("Esporta")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func exportClosedSinistri() {
        let config = FilterConfig.closedSinistriForMonth(
            year: year,
            month: month,
            userEmail: userEmail
        )
        
        // Apri direttamente la sheet di export
        let windowView = FilteredSinistriWindow(config: config)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        
        // ... implementa export diretto
    }
}

// MARK: - Esempio 2: Dettaglio Fattura

struct InvoiceDetailButton: View {
    let invoice: Invoice // Sostituire con il modello effettivo
    
    var body: some View {
        Button {
            let config = FilterConfig.forInvoice(
                invoiceNumber: invoice.number,
                sinistri: invoice.sinistri,
                date: invoice.date
            )
            openFilteredSinistriWindow(config: config)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fattura #\(invoice.number)")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("\(invoice.sinistri.count) sinistri")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

// MARK: - Esempio 3: Sezione Riepilogo con Card Cliccabili

struct ConsuntivoSummarySection: View {
    let year: Int
    let month: Int
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Riepilogo \(monthName) \(year)")
                .font(.system(size: 18, weight: .bold))
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                // Card sinistri chiusi
                SummaryCard(
                    title: "Chiusi",
                    count: 15,
                    icon: "checkmark.circle.fill",
                    color: .green
                ) {
                    let config = FilterConfig.closedSinistriForMonth(
                        year: year,
                        month: month
                    )
                    openFilteredSinistriWindow(config: config)
                }
                
                // Card sinistri aperti
                SummaryCard(
                    title: "Aperti",
                    count: 42,
                    icon: "folder.fill",
                    color: .blue
                ) {
                    let config = FilterConfig(
                        title: "Sinistri Aperti",
                        subtitle: "\(monthName) \(year)",
                        iconName: "folder.fill",
                        iconColor: .blue,
                        states: nil,
                        userEmail: nil,
                        dateFilter: nil,
                        customFilter: { sinistro in
                            let stato = sinistro.stato ?? ""
                            return !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                        },
                        columnsToShow: [.riferimento, .assicurato, .dataIncarico, .stato]
                    )
                    openFilteredSinistriWindow(config: config)
                }
                
                // Card urgenti
                SummaryCard(
                    title: "Urgenti",
                    count: 8,
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                ) {
                    let config = FilterConfig(
                        title: "Sinistri Urgenti",
                        subtitle: "Con scadenze imminenti",
                        iconName: "exclamationmark.triangle.fill",
                        iconColor: .red,
                        states: nil,
                        userEmail: nil,
                        dateFilter: nil,
                        customFilter: { sinistro in
                            // TODO: Implementare con task system quando disponibile
                            let stato = sinistro.stato ?? ""
                            let notClosed = !["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                            return notClosed && sinistro.isRecente
                        },
                        columnsToShow: [.riferimento, .assicurato, .dataIncarico, .stato]
                    )
                    openFilteredSinistriWindow(config: config)
                }
                
                // Card fatturate
                SummaryCard(
                    title: "Fatturate",
                    count: 12,
                    icon: "doc.text.fill",
                    color: .purple
                ) {
                    let config = FilterConfig(
                        title: "Pratiche Fatturate",
                        subtitle: "\(monthName) \(year)",
                        iconName: "doc.text.fill",
                        iconColor: .purple,
                        states: nil,
                        userEmail: nil,
                        dateFilter: nil,
                        customFilter: { sinistro in
                            // TODO: Implementare logica per sinistri fatturati
                            // Es: controllare se esiste fattura associata nel sistema
                            // Per ora: sinistri chiusi come esempio
                            let stato = sinistro.stato ?? ""
                            return ["Chiuso", "Chiuso - Rifiutato", "Chiuso - Senza seguito"].contains(stato)
                        },
                        columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico, .liquidazione]
                    )
                    openFilteredSinistriWindow(config: config)
                }
            }
        }
    }
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.monthSymbols[month - 1].capitalized
    }
}

// MARK: - Summary Card Component

struct SummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("\(count)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(color)
                    }
                    
                    Spacer()
                    
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(color.opacity(0.7))
                }
                
                HStack {
                    Text("Visualizza")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                }
                .foregroundColor(color)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(isHovered ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(color.opacity(isHovered ? 0.3 : 0.2), lineWidth: 1.5)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Mock Types (da sostituire con modelli reali)

struct Invoice {
    let number: String
    let date: Date
    let sinistri: [String]
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        ConsuntivoClosedSinistriCard(
            year: 2026,
            month: 1,
            count: 15,
            userEmail: nil
        )
        
        ConsuntivoSummarySection(
            year: 2026,
            month: 1
        )
    }
    .padding()
    .frame(width: 600)
}
