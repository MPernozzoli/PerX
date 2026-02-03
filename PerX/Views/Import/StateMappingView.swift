import SwiftUI

struct StateMappingView: View {
    let uniqueStates: Set<String>
    @Binding var stateMappings: [ImportService.StateMapping]
    let onNext: () -> Void
    
    @StateObject private var statoManager = StatoManager.shared
    @State private var localMappings: [String: String] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Associa gli stati del file agli stati di PerX")
                .font(.title3)
            
            Text("Gli stati nel file importato sono diversi da quelli usati in PerX. Associa ogni stato esterno a uno stato interno.")
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(uniqueStates), id: \.self) { sourceState in
                        StateMappingRowView(
                            sourceState: sourceState,
                            selectedState: Binding(
                                get: { localMappings[sourceState] ?? "" },
                                set: { localMappings[sourceState] = $0 }
                            ),
                            suggestedState: getSuggestedState(for: sourceState)
                        )
                    }
                }
                .padding()
            }
            
            HStack {
                Spacer()
                Button("Avanti") {
                    saveMappingsAndProceed()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(40)
        .onAppear {
            initializeMappings()
        }
    }
    
    private func initializeMappings() {
        for state in uniqueStates {
            // Prima prova con il sistema di memoria (con matching fuzzy)
            if let savedState = ImportService.shared.findSavedStateMapping(for: state) {
                localMappings[state] = savedState
            } else {
                // Logica euristica
                let suggested = getSuggestedState(for: state)
                localMappings[state] = suggested ?? ""
            }
        }
    }
    
    private func getSuggestedState(for sourceState: String) -> String? {
        // Prima prova con il sistema di memoria (con matching fuzzy)
        if let savedState = ImportService.shared.findSavedStateMapping(for: sourceState) {
            return savedState
        }
        
        // Logica euristica
        let normalizedState = sourceState.lowercased()
        return statoManager.availableStates.first {
            $0.descrizione.lowercased() == normalizedState
        }?.descrizione
    }
    
    private func saveMappingsAndProceed() {
        stateMappings = localMappings.compactMap { source, target in
            guard !target.isEmpty else { return nil }
            
            // Salva il mapping nella memoria
            ImportService.shared.saveStateMapping(sourceState: source, targetState: target)
            
            return ImportService.StateMapping(
                sourceState: source,
                targetState: target
            )
        }
        
        onNext()
    }
} 