import SwiftUI
import CoreData

/// Tipo di collegamento sinistro
enum TipoCollegamento {
    case collegato  // Manuale (stesso evento/bene)
    case pregresso  // Automatico (stessa polizza o CF/P.IVA)
}

/// Wrapper per sinistro con tipo di collegamento
struct SinistroCollegato: Identifiable {
    let sinistro: Sinistro
    let tipo: TipoCollegamento
    
    var id: String { sinistro.riferimento ?? UUID().uuidString }
}

/// Sezione Sinistri Collegati e Pregressi
struct SinistriCollegatiSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    
    @State private var showAddCollegatoSheet = false
    @State private var sinistriCollegatiManuali: [Sinistro] = []
    @State private var sinistriPregressi: [Sinistro] = []
    
    private var tuttiISinistri: [SinistroCollegato] {
        var result: [SinistroCollegato] = []
        
        // Aggiungi collegati manuali
        for s in sinistriCollegatiManuali {
            result.append(SinistroCollegato(sinistro: s, tipo: .collegato))
        }
        
        // Aggiungi pregressi (escludi quelli già collegati manualmente)
        let collegatiIds = Set(sinistriCollegatiManuali.compactMap { $0.riferimento })
        for s in sinistriPregressi where !collegatiIds.contains(s.riferimento ?? "") {
            result.append(SinistroCollegato(sinistro: s, tipo: .pregresso))
        }
        
        return result
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sinistri Collegati")
                        .font(.headline)
                    Spacer()
                    Button {
                        showAddCollegatoSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Collega sinistro")
                }
                
                if tuttiISinistri.isEmpty {
                    Text("Nessun sinistro collegato o pregresso")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    VStack(spacing: 8) {
                        ForEach(tuttiISinistri) { item in
                            SinistroCollegatoRow(
                                item: item,
                                sinistroAttuale: sinistro,
                                onRemove: item.tipo == .collegato ? {
                                    rimuoviCollegamento(con: item.sinistro)
                                } : nil,
                                onOpen: {
                                    openSinistro(item.sinistro)
                                }
                            )
                        }
                    }
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
        .onAppear {
            caricaSinistriCollegati()
            caricaSinistriPregressi()
        }
        .sheet(isPresented: $showAddCollegatoSheet) {
            CollegaSinistriView(
                sinistroAttuale: sinistro,
                onSelect: { sinistroSelezionato in
                    aggiungiCollegamento(con: sinistroSelezionato)
                    showAddCollegatoSheet = false
                }
            )
            .environmentObject(appState)
        }
    }
    
    // MARK: - Data Loading
    
    private func caricaSinistriCollegati() {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        let collegamenti = sinistro.collegamentiSet
        if !collegamenti.isEmpty {
            request.predicate = NSPredicate(format: "riferimento IN %@", Array(collegamenti))
            sinistriCollegatiManuali = (try? viewContext.fetch(request)) ?? []
        } else {
            sinistriCollegatiManuali = []
        }
    }
    
    private func caricaSinistriPregressi() {
        var predicates: [NSPredicate] = []
        
        // Escludi il sinistro corrente
        predicates.append(NSPredicate(format: "riferimento != %@", sinistro.riferimento ?? ""))
        
        // Escludi quelli già collegati manualmente
        let collegamenti = sinistro.collegamentiSet
        if !collegamenti.isEmpty {
            predicates.append(NSPredicate(format: "NOT (riferimento IN %@)", Array(collegamenti)))
        }
        
        // Match su numero polizza
        var matchPredicates: [NSPredicate] = []
        
        if let numeroPolizza = sinistro.numeroPolizza, !numeroPolizza.isEmpty {
            matchPredicates.append(NSPredicate(format: "numeroPolizza == %@", numeroPolizza))
        }
        
        // Match su codice fiscale (se valorizzato)
        if let cf = sinistro.codiceFiscaleAssicurato, !cf.isEmpty {
            matchPredicates.append(NSPredicate(format: "codiceFiscaleAssicurato == %@", cf))
        }
        
        // Match su partita IVA (se valorizzata)
        if let piva = sinistro.partitaIVAAssicurato, !piva.isEmpty {
            matchPredicates.append(NSPredicate(format: "partitaIVAAssicurato == %@", piva))
        }
        
        // Se non ci sono criteri di match, nessun pregresso
        guard !matchPredicates.isEmpty else {
            sinistriPregressi = []
            return
        }
        
        // Combina con OR i criteri di match
        let matchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: matchPredicates)
        predicates.append(matchPredicate)
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Sinistro.dataSinistro, ascending: false)]
        
        sinistriPregressi = (try? viewContext.fetch(request)) ?? []
    }
    
    // MARK: - Actions
    
    private func aggiungiCollegamento(con sinistroCollegato: Sinistro) {
        viewContext.performAndWait {
            // Aggiorna il sinistro corrente
            var collegamenti1 = sinistro.collegamentiSet
            collegamenti1.insert(sinistroCollegato.riferimento ?? "")
            sinistro.collegamentiSet = collegamenti1
            
            // Aggiorna il sinistro collegato (bidirezionale)
            var collegamenti2 = sinistroCollegato.collegamentiSet
            collegamenti2.insert(sinistro.riferimento ?? "")
            sinistroCollegato.collegamentiSet = collegamenti2
            
            sinistro.markAsLocallyModified()
            sinistroCollegato.markAsLocallyModified()
            try? viewContext.save()
            caricaSinistriCollegati()
        }
    }
    
    private func rimuoviCollegamento(con sinistroCollegato: Sinistro) {
        viewContext.performAndWait {
            // Rimuovi dal sinistro corrente
            var collegamenti1 = sinistro.collegamentiSet
            collegamenti1.remove(sinistroCollegato.riferimento ?? "")
            sinistro.collegamentiSet = collegamenti1
            
            // Rimuovi dal sinistro collegato
            var collegamenti2 = sinistroCollegato.collegamentiSet
            collegamenti2.remove(sinistro.riferimento ?? "")
            sinistroCollegato.collegamentiSet = collegamenti2
            
            sinistro.markAsLocallyModified()
            sinistroCollegato.markAsLocallyModified()
            try? viewContext.save()
            caricaSinistriCollegati()
        }
    }
    
    private func openSinistro(_ sinistro: Sinistro) {
        // Usa il metodo openSinistro di AppState che gestisce correttamente la navigazione
        appState.openSinistro(sinistro)
    }
}

// MARK: - Row View

struct SinistroCollegatoRow: View {
    let item: SinistroCollegato
    let sinistroAttuale: Sinistro
    let onRemove: (() -> Void)?
    let onOpen: () -> Void
    
    private var isClosedClaim: Bool {
        let stato = (item.sinistro.stato ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return stato == "Chiuso" || stato == "Revocato"
    }
    
    private var isPregressoByDate: Bool {
        guard let itemDate = item.sinistro.dataSinistro,
              let attualeDate = sinistroAttuale.dataSinistro else {
            // Fallback: se mancano le date, manteniamo una semantica sensata
            return isClosedClaim
        }
        return itemDate < attualeDate
    }

    private var peritoKey: String? {
        let v = (item.sinistro.assignedToUserEmail ?? item.sinistro.ownerEmail ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return v.isEmpty ? nil : v
    }
    
    private var peritoAttualeKey: String? {
        let v = (sinistroAttuale.assignedToUserEmail ?? sinistroAttuale.ownerEmail ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return v.isEmpty ? nil : v
    }
    
    private var peritoDisplay: String? {
        let name = (item.sinistro.assignedToUserName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        
        let email = (item.sinistro.assignedToUserEmail ?? item.sinistro.ownerEmail ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }
    
    private var shouldShowPerito: Bool {
        guard let peritoKey else { return false }
        guard let peritoAttualeKey else { return true } // non abbiamo il perito attuale, quindi mostriamo
        return peritoKey != peritoAttualeKey
    }
    
    private var badgeText: String? {
        switch item.tipo {
        case .collegato:
            return "Collegato"
        case .pregresso:
            return isPregressoByDate ? "Pregresso" : "Sinistro attuale"
        }
    }
    
    private var badgeColor: Color {
        switch item.tipo {
        case .collegato:
            return .blue
        case .pregresso:
            return isPregressoByDate ? .orange : .green
        }
    }
    
    private var statoInfo: StatoManager.StatoInfo? {
        guard let statoDesc = item.sinistro.stato else { return nil }
        return StatoManager.shared.allAvailableStates.first { $0.descrizione == statoDesc }
    }
    
    private var statoColor: Color {
        statoInfo?.color ?? .gray
    }
    
    private var statoIcon: String {
        statoInfo?.icon ?? "questionmark.circle"
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icona stato con colore
            Image(systemName: statoIcon)
                .font(.system(size: 18))
                .foregroundColor(statoColor)
                .frame(width: 24)
            
            // Info sinistro
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.sinistro.riferimentoVisualizzato)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Badge tipo (Collegato/Pregresso)
                    if let badgeText {
                        Text(badgeText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(badgeColor)
                            )
                    }
                }
                
                HStack(spacing: 8) {
                    if let nome = item.sinistro.nomeAssicurato ?? item.sinistro.nomeContraente {
                        Text(nome)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let data = item.sinistro.dataSinistro {
                        Text(formatDate(data))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if shouldShowPerito, let peritoDisplay {
                    Text("Perito: \(peritoDisplay)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Stato con colore
            if let stato = item.sinistro.stato {
                Text(stato)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statoColor)
            }
            
            // Azioni
            HStack(spacing: 8) {
                Button {
                    onOpen()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Apri")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Apri sinistro")
                
                if let onRemove = onRemove {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Rimuovi collegamento")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statoColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statoColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatShortYY(date)
    }
}
