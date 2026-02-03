import SwiftUI
import CoreData

struct CustomThreadSelectionView: View {
    let email: Email
    let onSelectThread: (UUID, String) -> Void
    let onCreateThread: (String) -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var customThreads: [(id: UUID, name: String)] = []
    @State private var showingCreateThread = false
    @State private var newThreadName = ""
    
    private let threadCustomizationService = ThreadCustomizationService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if customThreads.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Nessun thread personalizzato")
                            .font(.headline)
                        
                        Text("Crea un nuovo thread personalizzato per organizzare le tue email")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(customThreads, id: \.id) { thread in
                            Button(action: {
                                onSelectThread(thread.id, thread.name)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.accentColor)
                                    
                                    Text(thread.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
                
                // Tasto per creare nuovo thread
                Button(action: {
                    showingCreateThread = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Crea nuovo thread")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Thread personalizzati")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCreateThread) {
                CreateCustomThreadView(
                    threadName: $newThreadName,
                    onCreate: {
                        guard !newThreadName.isEmpty else { return }
                        onCreateThread(newThreadName)
                        newThreadName = ""
                        dismiss()
                    },
                    onCancel: {
                        newThreadName = ""
                        showingCreateThread = false
                    }
                )
            }
            .onAppear {
                loadCustomThreads()
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func loadCustomThreads() {
        let request = NSFetchRequest<SinistroEmailThread>(entityName: "SinistroEmailThread")
        request.predicate = NSPredicate(format: "sinistro == nil")
        
        if let threads = try? viewContext.fetch(request) {
            customThreads = threads.compactMap { thread in
                let threadId = thread.wrappedId
                if let name = threadCustomizationService.getCustomThreadName(threadId: threadId) {
                    return (id: threadId, name: name)
                }
                return nil
            }
        }
    }
}

struct CreateCustomThreadView: View {
    @Binding var threadName: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Crea thread personalizzato")
                    .font(.headline)
                    .padding(.top)
                
                TextField("Nome thread (es. Amministrazione, Notizie interne...)", text: $threadName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button("Annulla", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Crea", action: onCreate)
                        .buttonStyle(.borderedProminent)
                        .disabled(threadName.isEmpty)
                }
                .padding(.horizontal)
            }
            .frame(width: 400, height: 200)
            .onAppear {
                isFocused = true
            }
        }
    }
}

