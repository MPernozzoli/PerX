import SwiftUI
import CoreData

@MainActor
struct DetachedSinistriWindowView: View {
    let windowId: String
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var appState = AppState.shared
    @State private var draggedTab: TabInfo?
    @State private var draggedTabSourceWindowId: String?
    @State private var isDragging: Bool = false
    @State private var showDetachIndicator: Bool = false
    @State private var dragLocation: CGPoint = .zero

    // Make windowState non-optional to reduce optional complexity in the body
    private var windowState: DetachedWindowState {
        if let state = appState.detachedWindows[windowId] {
            return state
        } else {
            // Fallback to an empty state to avoid optional noise
            return DetachedWindowState(id: windowId, tabs: [], selectedTabId: nil, isAlwaysOnTop: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(windowState.tabs, id: \.id) { tab in
                                let isDragged = draggedTab?.id == tab.id
                                
                                TabButton(
                                    title: tab.sinistro.riferimentoVisualizzato,
                                    isSelected: windowState.selectedTabId == tab.id,
                                    canClose: true,
                                    onSelect: {
                                        if var state = appState.detachedWindows[windowId] {
                                            state.selectedTabId = tab.id
                                            appState.detachedWindows[windowId] = state
                                        }
                                    },
                                    onClose: {
                                        appState.closeTab(id: tab.id, windowId: windowId)
                                        // Se non ci sono più tab, chiudi la finestra
                                        if let state = appState.detachedWindows[windowId], state.tabs.isEmpty {
                                            appState.closeDetachedWindow(windowId: windowId)
                                        }
                                    }
                                )
                                .opacity(isDragged ? 0.5 : 1.0)
                                .scaleEffect(isDragged ? 0.95 : 1.0)
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(tab.sinistro.riferimento ?? "", forType: .string)
                                    } label: {
                                        Label("Copia Riferimento", systemImage: "doc.on.doc")
                                    }
                                }
                                .onDrag {
                                    draggedTab = tab
                                    draggedTabSourceWindowId = windowId
                                    isDragging = true
                                    return NSItemProvider(object: (tab.sinistro.riferimento ?? "") as NSString)
                                }
                                .onDrop(of: [.text], delegate: TabDropDelegate(
                                    tab: tab,
                                    windowId: windowId,
                                    appState: appState,
                                    draggedTab: $draggedTab,
                                    draggedTabSourceWindowId: $draggedTabSourceWindowId,
                                    isDragging: $isDragging,
                                    showDetachIndicator: $showDetachIndicator,
                                    dragLocation: $dragLocation,
                                    onDetach: {
                                        if let draggedTab = draggedTab {
                                            appState.detachTab(draggedTab, fromWindowId: windowId)
                                        }
                                    }
                                ))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    
                    // Always on top button - ancorato in fondo a destra
                    Button {
                        if var state = appState.detachedWindows[windowId] {
                            state.isAlwaysOnTop.toggle()
                            appState.detachedWindows[windowId] = state
                            WindowManager.shared.updateAlwaysOnTop(identifier: windowId, value: state.isAlwaysOnTop)
                        }
                    } label: {
                        Image(systemName: windowState.isAlwaysOnTop ? "pin.fill" : "pin")
                            .foregroundColor(windowState.isAlwaysOnTop ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 40)
                    .help(windowState.isAlwaysOnTop ? "Disattiva sempre in primo piano" : "Attiva sempre in primo piano")
                }
                .frame(height: 40)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(NSColor.windowBackgroundColor),
                            Color(NSColor.windowBackgroundColor).opacity(0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Indicatore per detach (stile Chrome)
                if showDetachIndicator && isDragging {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "rectangle.split.2x1")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                Text("Rilascia per aprire\nin nuova finestra")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .shadow(radius: 8)
                            )
                            .padding(.trailing, 20)
                            .padding(.bottom, 60)
                            Spacer()
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showDetachIndicator)
                }
            }

            Divider()

            // Contenuto
            if let selectedTabId = windowState.selectedTabId,
               let tab = windowState.tabs.first(where: { $0.id == selectedTabId }) {
                Group {
                    let isObjectValid: Bool = {
                        guard !tab.sinistro.isDeleted else { return false }
                        guard tab.sinistro.managedObjectContext != nil else { return false }
                        
                        // Verifica se l'oggetto esiste ancora nel contesto in modo sicuro
                        do {
                            _ = try viewContext.existingObject(with: tab.sinistro.objectID)
                            return true
                        } catch {
                            return false
                        }
                    }()
                    
                    if isObjectValid {
                        SinistroDetailView(sinistro: tab.sinistro)
                            .environment(\.managedObjectContext, viewContext)
                            .environmentObject(appState)
                            .id(selectedTabId)
                            .onAppear {
                                viewContext.refresh(tab.sinistro, mergeChanges: true)
                            }
                    } else {
                        Text("Sinistro non più disponibile")
                            .foregroundColor(.secondary)
                            .onAppear {
                                appState.closeTab(id: tab.id, windowId: windowId)
                            }
                    }
                }
            } else {
                Text("Nessuna tab selezionata")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct TabDropDelegate: DropDelegate {
    let tab: TabInfo
    let windowId: String
    let appState: AppState
    @Binding var draggedTab: TabInfo?
    @Binding var draggedTabSourceWindowId: String?
    @Binding var isDragging: Bool
    @Binding var showDetachIndicator: Bool
    @Binding var dragLocation: CGPoint
    let onDetach: () -> Void
    
    // Soglia per il magnete (in pixel)
    private let magnetThreshold: CGFloat = 30
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedTab = draggedTab else { return false }
        
        // Reset stati
        isDragging = false
        showDetachIndicator = false
        
        // Verifica se il drop è dentro la tab bar (con margine per il magnete)
        let isInTabBar = info.location.x >= -magnetThreshold && 
                        info.location.y >= -magnetThreshold &&
                        info.location.y <= 60
        
        if isInTabBar {
            let sourceWindowId = draggedTabSourceWindowId
            
            // Se la tab proviene dalla stessa finestra, spostala normalmente
            if sourceWindowId == windowId {
                if let windowState = appState.detachedWindows[windowId],
                   let sourceIndex = windowState.tabs.firstIndex(where: { $0.id == draggedTab.id }),
                   let destinationIndex = windowState.tabs.firstIndex(where: { $0.id == tab.id }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTab(from: sourceIndex, to: destinationIndex, windowId: windowId)
                    }
                }
            } else {
                // Tab da un'altra finestra: spostala tra finestre
                if let windowState = appState.detachedWindows[windowId],
                   let destinationIndex = windowState.tabs.firstIndex(where: { $0.id == tab.id }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTabBetweenWindows(
                            tab: draggedTab,
                            fromWindowId: sourceWindowId,
                            toWindowId: windowId,
                            atIndex: destinationIndex
                        )
                    }
                } else {
                    // Aggiungi alla fine se non troviamo la tab di destinazione
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.moveTabBetweenWindows(
                            tab: draggedTab,
                            fromWindowId: sourceWindowId,
                            toWindowId: windowId,
                            atIndex: nil
                        )
                    }
                }
            }
        } else {
            // Drop fuori dalla tab bar, detach
            onDetach()
        }
        
        self.draggedTab = nil
        self.draggedTabSourceWindowId = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedTab = draggedTab else { return }
        
        // Applica effetto magnete se siamo vicini alla tab bar
        let isNearTabBar = info.location.y >= -magnetThreshold && info.location.y <= 60
        let sourceWindowId = draggedTabSourceWindowId
        
        if isNearTabBar {
            // Se proviene dalla stessa finestra
            if sourceWindowId == windowId {
                if let windowState = appState.detachedWindows[windowId],
                   let sourceIndex = windowState.tabs.firstIndex(where: { $0.id == draggedTab.id }),
                   let destinationIndex = windowState.tabs.firstIndex(where: { $0.id == tab.id }),
                   sourceIndex != destinationIndex {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.moveTab(from: sourceIndex, to: destinationIndex, windowId: windowId)
                    }
                }
            } else {
                // Tab da un'altra finestra: mostra preview dello spostamento
                if let windowState = appState.detachedWindows[windowId],
                   let destinationIndex = windowState.tabs.firstIndex(where: { $0.id == tab.id }) {
                    // Preview: mostra dove verrà inserita (opzionale, per ora solo logica)
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dragLocation = info.location
        
        // Mostra indicatore detach se il mouse si allontana dalla tab bar
        let isFarFromTabBar = info.location.y < -50 || info.location.y > 100
        showDetachIndicator = isFarFromTabBar
        
        // Proposta di drop con effetto magnete
        let isInTabBar = info.location.x >= -magnetThreshold && 
                        info.location.y >= -magnetThreshold &&
                        info.location.y <= 60
        
        return DropProposal(operation: isInTabBar ? .move : .copy)
    }
    
    func dropExited(info: DropInfo) {
        // Mantieni l'indicatore se siamo ancora in drag
        if isDragging {
            let isFarFromTabBar = info.location.y < -50 || info.location.y > 100
            showDetachIndicator = isFarFromTabBar
        }
    }
}
