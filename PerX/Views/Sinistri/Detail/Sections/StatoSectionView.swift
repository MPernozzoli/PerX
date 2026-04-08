import SwiftUI

/// Sezione Stato con selezione via menu e transizioni animate
struct StatoSectionView: View {
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var statoManager = StatoManager.shared
    
    // Hub integration
    private let claimAdapter = ClaimAdapter.shared
    private let hubMode = HubModeService.shared
    
    @State private var selectedNewStato: StatoManager.StatoInfo?
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Stato")
                        .font(.headline)
                    Spacer()
                    
                    // Container per i box degli stati
                    HStack(spacing: 8) {
                        // Box dello stato corrente
                        if let currentStato = statoManager.allAvailableStates.first(where: { $0.descrizione == sinistro.stato }) {
                            HStack(spacing: 6) {
                                Image(systemName: currentStato.icon)
                                    .font(.system(size: 16))
                                Text(currentStato.descrizione)
                                    .font(.system(.body, design: .rounded))
                            }
                            .foregroundColor(currentStato.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(currentStato.color.opacity(0.1))
                            )
                            .offset(x: selectedNewStato != nil ? -60 : 0)
                        }
                        
                        // Freccia e nuovo stato
                        if let newStato = selectedNewStato {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .offset(x: -30)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: newStato.icon)
                                        .font(.system(size: 16))
                                    Text(newStato.descrizione)
                                        .font(.system(.body, design: .rounded))
                                }
                                .foregroundColor(newStato.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(newStato.color.opacity(0.1))
                                )
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        
                        // Menu per selezionare il nuovo stato
                        Menu {
                            ForEach(getValidTransitionStates(), id: \.id) { stato in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedNewStato = stato
                                    }
                                } label: {
                                    Label {
                                        Text(stato.descrizione)
                                    } icon: {
                                        if selectedNewStato?.id == stato.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Menu("Altri") {
                                ForEach(getAllStatesOrdered(), id: \.id) { stato in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedNewStato = stato
                                        }
                                    } label: {
                                        Label {
                                            Text(stato.descrizione)
                                        } icon: {
                                            if selectedNewStato?.id == stato.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            .help("Mostra tutti gli stati disponibili")
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.borderless)
                        
                        // Pulsante di conferma
                        if let newStato = selectedNewStato {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    let currentStato = getCurrentStatoEnum()
                                    let isValidTransition = currentStato?.validTransitions.contains(where: { $0.id == newStato.id }) ?? false
                                    let isForced = !isValidTransition
                                    updateStato(newStato.id, force: isForced)
                                    selectedNewStato = nil
                                }
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(newStato.color)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .help("Conferma cambio stato")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedNewStato)
                }
                
                if sinistro.stato == StatoManager.StatoSinistro.revocata.descrizione {
                    statoRevocatoView
                }
            }
            .padding(12)
        }
        .backgroundStyle(.regularMaterial)
    }
    
    // MARK: - Stato Revocato View
    
    private var statoRevocatoView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text("Sinistro Revocato")
                .foregroundColor(.red)
            if let dataRevoca = sinistro.dataRevoca {
                Text("il \(formatDate(dataRevoca))")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatLong(date)
    }
    
    private func getCurrentStatoEnum() -> StatoManager.StatoSinistro? {
        guard let statoDescrizione = sinistro.stato,
              let statoId = statoManager.getStatoId(fromDescrizione: statoDescrizione),
              let statoEnum = StatoManager.StatoSinistro(rawValue: statoId) else {
            return nil
        }
        return statoEnum
    }
    
    private func getValidTransitionStates() -> [StatoManager.StatoInfo] {
        guard let currentStato = getCurrentStatoEnum() else {
            return statoManager.allAvailableStates.filter { stato in
                if let systemState = StatoManager.StatoSinistro(rawValue: stato.id) {
                    return systemState.isVisible && !systemState.isSystem
                }
                return stato.isActive && !stato.isSystem
            }
        }
        
        let validTransitions = currentStato.validTransitions
        let validStates = validTransitions.compactMap { transitionEnum -> StatoManager.StatoInfo? in
            statoManager.allAvailableStates.first { $0.id == transitionEnum.id }
        }.filter { statoManager.canCurrentUserAccess(stateInfo: $0) }
        
        let customStates = statoManager.allAvailableStates.filter { stato in
            !stato.isSystem &&
            stato.isActive &&
            statoManager.canCurrentUserAccess(stateInfo: stato) &&
            !validStates.contains(where: { $0.id == stato.id })
        }
        
        return validStates + customStates
    }
    
    private func getAllStatesOrdered() -> [StatoManager.StatoInfo] {
        let allStates = statoManager.allAvailableStates.filter { stato in
            if let systemState = StatoManager.StatoSinistro(rawValue: stato.id) {
                return systemState.isVisible && !systemState.isSystem && statoManager.canCurrentUserAccess(stateInfo: stato)
            }
            return stato.isActive && !stato.isSystem && statoManager.canCurrentUserAccess(stateInfo: stato)
        }
        
        return allStates.sorted { stato1, stato2 in
            let enum1 = StatoManager.StatoSinistro(rawValue: stato1.id)
            let enum2 = StatoManager.StatoSinistro(rawValue: stato2.id)
            
            if let e1 = enum1, let e2 = enum2 {
                let cat1 = e1.category
                let cat2 = e2.category
                
                if cat1 != cat2 {
                    let order: [StatoCategory] = [.ingresso, .avanzamento, .chiusura]
                    if let idx1 = order.firstIndex(of: cat1), let idx2 = order.firstIndex(of: cat2) {
                        return idx1 < idx2
                    }
                }
                return e1.distanceFromClosure < e2.distanceFromClosure
            }
            
            if enum1 == nil && enum2 != nil { return false }
            if enum1 != nil && enum2 == nil { return true }
            
            return stato1.descrizione < stato2.descrizione
        }
    }
    
    private func updateStato(_ statoId: String, force: Bool = false) {
        guard let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.id == statoId }),
              let riferimento = sinistro.riferimento else { return }
        
        Task { @MainActor in
            do {
                // HUB MODE: usa ClaimAdapter se attivo
                if hubMode.shouldUseHub(for: .claim) {
                    try await claimAdapter.changeState(
                        riferimento: riferimento,
                        newState: stato,
                        reason: nil,
                        changedBy: CurrentUserService.shared.currentUsernameOrDefault("unknown")
                    )
                    // Aggiorna anche localmente per riflettere immediatamente
                    sinistro.stato = stato.descrizione
                    try viewContext.save()
                } else {
                    try await StatoManager.shared.changeState(
                        for: sinistro,
                        to: stato,
                        context: viewContext,
                        userEmail: CurrentUserService.shared.currentUsername ?? appState.googleAuthService.userEmail,
                        skipValidation: force
                    )
                }
                print("[StatoSectionView] Stato aggiornato a \(stato.descrizione)")
            } catch {
                print("[StatoSectionView] Errore aggiornamento stato: \(error.localizedDescription)")
            }
        }
    }
}
