import SwiftUI

// MARK: - Rename Popover

struct RenamePopover: View {
    let item: FileService.FileItem
    let sinistro: Sinistro
    let onComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(item: FileService.FileItem, sinistro: Sinistro, onComplete: @escaping (String) -> Void) {
        self.item = item
        self.sinistro = sinistro
        self.onComplete = onComplete
        _newName = State(initialValue: item.url.lastPathComponent)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rinomina \(item.isDirectory ? "Cartella" : "File")")
                .font(.headline)
            
            TextField("Nuovo nome", text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !newName.isEmpty && newName != item.url.lastPathComponent {
                        onComplete(newName)
                        dismiss()
                    }
                }
            
            HStack {
                Button {
                    newName = sinistro.riferimento ?? ""
                } label: {
                    Label("Incolla Riferimento", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Rinomina") {
                    onComplete(newName)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(newName.isEmpty || newName == item.url.lastPathComponent)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Rename Item View

struct RenameItemView: View {
    let item: FileService.FileItem
    let sinistro: Sinistro
    let onComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(item: FileService.FileItem, sinistro: Sinistro, onComplete: @escaping (String) -> Void) {
        self.item = item
        self.sinistro = sinistro
        self.onComplete = onComplete
        _newName = State(initialValue: item.url.lastPathComponent)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rinomina \(item.isDirectory ? "Cartella" : "File")")
                .font(.headline)
            
            TextField("Nuovo nome", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .focused($isTextFieldFocused)
            
            HStack {
                Button {
                    newName = sinistro.riferimento ?? ""
                } label: {
                    Label("Incolla Riferimento", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)
                
                Spacer()
                
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Rinomina") {
                    onComplete(newName)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(newName.isEmpty || newName == item.url.lastPathComponent)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - New Folder View

struct NewFolderView: View {
    let currentPath: String
    let onComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folderName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Nuova Cartella")
                .font(.headline)
            
            TextField("Nome cartella", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                
                Button("Crea") {
                    onComplete(folderName)
                    dismiss()
                }
                .disabled(folderName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Draggable Divider

struct DraggableDivider: View {
    @Binding var width: CGFloat
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let delta = value.translation.width
                                width = max(200, min(400, width + delta - dragOffset))
                                dragOffset = delta
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragOffset = 0
                            }
                    )
            )
            .opacity(isDragging ? 1 : 0.5)
    }
}
