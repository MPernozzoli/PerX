import SwiftUI
import CoreData

/// Vista principale del contenuto dettaglio sinistro (tab "Dettagli")
struct SinistroDetailContentView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    
    let onOpenCollegato: ((Sinistro?) -> Void)?
    
    @State private var isCompanyExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // SEZIONE 1: Compagnia e Agenzia
                CompanySectionView(
                    sinistro: sinistro,
                    isExpanded: $isCompanyExpanded
                )
                
                // SEZIONE 2: Stato
                StatoSectionView(sinistro: sinistro)
                
                // SEZIONE 3: Polizza e Attori (vecchio flusso, campi piatti)
                PolizzaAttoriSectionView(sinistro: sinistro)

                // SEZIONE 3-bis: Anagrafica unificata (nuovo flusso backend)
                AnagraficaAttoriSectionView(sinistro: sinistro)
                
                // Layout a due colonne per le altre GroupBox
                HStack(alignment: .top, spacing: 16) {
                    // Colonna sinistra
                    VStack(spacing: 16) {
                        VerificheSectionView(sinistro: sinistro)
                        ImportiSectionView(sinistro: sinistro)
                    }
                    
                    // Colonna destra
                    VStack(spacing: 16) {
                        SinistriCollegatiSectionView(sinistro: sinistro)
                        DateSectionView(sinistro: sinistro)
                    }
                }
            }
            .padding(20)
        }
    }
}
