//
//  iPadCartellaView.swift
//  PerX per iPad
//
//  File browser touch-friendly per cartella sinistro.
//

import SwiftUI

struct iPadCartellaView: View {
    let sinistro: SinistroMinimal
    
    @EnvironmentObject var session: SessionCoordinator
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var files: [FileItem] = []
    @State private var selectedFile: FileItem?
    @State private var currentPath: [String] = []
    @State private var errorMessage: String?
    
    private var folderService: SinistroFolderCacheService? {
        session.folderCacheService
    }
    
    private var folderInfo: CachedFolderInfo? {
        folderService?.cachedFolders[sinistro.riferimento]
    }
    
    private var isCached: Bool {
        folderService?.isCached(riferimento: sinistro.riferimento) == true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isCached {
                // Folder cached - show file browser
                fileBrowserView
            } else {
                // Folder not cached - show download prompt
                downloadPromptView
            }
        }
    }
    
    // MARK: - Download Prompt
    
    @ViewBuilder
    private var downloadPromptView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
            
            Text("Cartella non scaricata")
                .font(.title2.bold())
            
            Text("Richiedi il download della cartella dal Mac.\nVerrà eliminata automaticamente dopo 3 giorni.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if isDownloading {
                VStack(spacing: 12) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text("Download in corso...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else {
                Button {
                    Task { await downloadFolder() }
                } label: {
                    Label("Scarica Cartella", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - File Browser
    
    @ViewBuilder
    private var fileBrowserView: some View {
        VStack(spacing: 0) {
            // Toolbar con info cartella
            folderToolbar
            
            Divider()
            
            // Breadcrumb
            breadcrumbBar
            
            Divider()
            
            // File list
            if files.isEmpty {
                ContentUnavailableView(
                    "Cartella vuota",
                    systemImage: "folder",
                    description: Text("Nessun file in questa cartella")
                )
            } else {
                List {
                    ForEach(files) { file in
                        Button {
                            selectedFile = file
                        } label: {
                            FileRow(file: file)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedFile?.id == file.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        .onTapGesture(count: 2) {
                            if file.isDirectory {
                                navigateInto(file)
                            } else {
                                openFile(file)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadFiles()
        }
    }
    
    // MARK: - Folder Toolbar
    
    @ViewBuilder
    private var folderToolbar: some View {
        HStack {
            if let info = folderInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cartella scaricata")
                        .font(.subheadline.bold())
                    
                    HStack(spacing: 8) {
                        if info.isExpired {
                            Label("Scaduta", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        } else {
                            Label("Scade tra \(info.daysUntilExpiration)gg", systemImage: "clock")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            
            Spacer()
            
            Toggle("Mantieni", isOn: Binding(
                get: { folderInfo?.keepBeyondExpiration ?? false },
                set: { folderService?.setKeepBeyondExpiration($0, for: sinistro.riferimento) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            
            Text("Mantieni")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(role: .destructive) {
                folderService?.removeFolder(riferimento: sinistro.riferimento)
                files = []
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Breadcrumb
    
    @ViewBuilder
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    currentPath = []
                    loadFiles()
                } label: {
                    Image(systemName: "house.fill")
                        .foregroundColor(.accentColor)
                }
                
                ForEach(Array(currentPath.enumerated()), id: \.offset) { index, pathComponent in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        currentPath = Array(currentPath.prefix(index + 1))
                        loadFiles()
                    } label: {
                        Text(pathComponent)
                            .font(.subheadline)
                            .foregroundColor(index == currentPath.count - 1 ? .primary : .accentColor)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.tertiarySystemGroupedBackground))
    }
    
    // MARK: - Actions
    
    private func downloadFolder() async {
        isDownloading = true
        errorMessage = nil
        
        do {
            _ = try await folderService?.requestFolder(riferimento: sinistro.riferimento)
            loadFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isDownloading = false
    }
    
    private func loadFiles() {
        guard let basePath = folderService?.localPath(for: sinistro.riferimento) else {
            files = []
            return
        }
        
        var fullPath = basePath
        for component in currentPath {
            fullPath = fullPath.appendingPathComponent(component)
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: fullPath,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            files = contents.compactMap { url -> FileItem? in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                
                return FileItem(
                    id: url.lastPathComponent,
                    name: url.lastPathComponent,
                    path: url,
                    isDirectory: resourceValues?.isDirectory ?? false,
                    size: resourceValues?.fileSize ?? 0,
                    modifiedDate: resourceValues?.contentModificationDate ?? Date()
                )
            }.sorted { item1, item2 in
                if item1.isDirectory != item2.isDirectory {
                    return item1.isDirectory
                }
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
        } catch {
            print("Errore caricamento file: \(error)")
            files = []
        }
    }
    
    private func navigateInto(_ file: FileItem) {
        guard file.isDirectory else { return }
        currentPath.append(file.name)
        loadFiles()
    }
    
    private func openFile(_ file: FileItem) {
        // Su iPad non possiamo aprire file esterni, ma possiamo mostrare un Quick Look
        // TODO: Implementare preview file
    }
}

// MARK: - File Item

struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: URL
    let isDirectory: Bool
    let size: Int
    let modifiedDate: Date
}

// MARK: - File Row

struct FileRow: View {
    let file: FileItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if !file.isDirectory {
                        Text(formatSize(file.size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(file.modifiedDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var iconName: String {
        if file.isDirectory {
            return "folder.fill"
        }
        
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "mp4", "mov", "avi": return "video.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z": return "doc.zipper"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        if file.isDirectory {
            return .blue
        }
        
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "gif", "heic": return .green
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        default: return .gray
        }
    }
    
    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
