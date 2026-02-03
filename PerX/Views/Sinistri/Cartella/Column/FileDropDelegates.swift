import SwiftUI
import UniformTypeIdentifiers
import Foundation

// MARK: - Enhanced Drop Delegate

struct EnhancedFileDropDelegate: DropDelegate {
    let item: FileService.FileItem
    @Binding var draggedItem: FileService.FileItem?
    @Binding var draggedItems: [FileService.FileItem]
    let fileService: FileService
    @Binding var dropTarget: FileService.FileItem?
    let currentPath: String
    let refreshTrigger: UUID
    let onDrop: (Bool) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        // Gestisce drag interno (singolo o multiplo)
        if !draggedItems.isEmpty {
            // Se la destinazione è la stessa cartella di origine, annulla l'operazione
            let sourcePath = draggedItems.first?.url.deletingLastPathComponent().path
            if sourcePath == item.url.path || (sourcePath == currentPath && !item.isDirectory) {
                dropTarget = nil
                return false
            }
            
            // Non permettere drop su se stessi
            if draggedItems.contains(where: { $0.url == item.url }) {
                dropTarget = nil
                return false
            }
            
            // Non permettere drop su sottocartelle degli elementi trascinati
            for dragged in draggedItems {
                if item.url.path.hasPrefix(dragged.url.path + "/") {
                    dropTarget = nil
                    return false
                }
            }
            
            if item.isDirectory {
                var allSuccess = true
                
                // Sposta tutti gli elementi
                for dragged in draggedItems {
                    let success = fileService.moveItem(dragged, to: item.url.path)
                    if !success {
                        allSuccess = false
                    }
                }
                
                dropTarget = nil
                onDrop(allSuccess)
                return allSuccess
            }
        } else if let dragged = draggedItem {
            // Fallback per drag singolo
            if dragged.url == item.url {
                dropTarget = nil
                return false
            }
            
            if item.url.path.hasPrefix(dragged.url.path + "/") {
                dropTarget = nil
                return false
            }
            
            if item.isDirectory {
                let success = fileService.moveItem(dragged, to: item.url.path)
                dropTarget = nil
                
                if success {
                    onDrop(true)
                } else {
                    onDrop(false)
                }
                return success
            }
        }
        
        // Gestisce file esterni (Finder / altre app) → copia sempre dentro la destinazione
        let providers = info.itemProviders(for: [.fileURL])
        let targetPath = item.isDirectory ? item.url.path : currentPath
        
        ExternalFileDropHelpers.importFromProviders(providers, to: targetPath) { success in
            onDrop(success)
        }
        
        dropTarget = nil
        return !providers.isEmpty
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        // Valida drag interno (multiplo)
        if !draggedItems.isEmpty {
            // Non permettere drop su elementi selezionati
            if draggedItems.contains(where: { $0.url == item.url }) {
                return false
            }
            
            // Non permettere drop su sottocartelle
            for dragged in draggedItems {
                if item.url.path.hasPrefix(dragged.url.path + "/") {
                    return false
                }
            }
            
            return item.isDirectory
        }
        
        // Valida drag singolo
        if let dragged = draggedItem {
            let isValid = item.isDirectory &&
                         dragged.url != item.url &&
                         !item.url.path.hasPrefix(dragged.url.path + "/")
            return isValid
        }
        
        // Valida file esterni - accetta sempre su cartelle
        if item.isDirectory {
            return true
        }
        
        return false
    }
    
    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) {
            dropTarget = item
        }
    }
    
    func dropExited(info: DropInfo) {
        dropTarget = nil
    }
}

// MARK: - Legacy Drop Delegate (kept for compatibility)

struct FileDropDelegate: DropDelegate {
    let item: FileService.FileItem
    @Binding var draggedItem: FileService.FileItem?
    let fileService: FileService
    @Binding var dropTarget: FileService.FileItem?
    let onDrop: (Bool) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedItem else { return false }
        
        if dragged.url == item.url {
            dropTarget = nil
            return false
        }
        
        if item.url.path.hasPrefix(dragged.url.path + "/") {
            dropTarget = nil
            return false
        }
        
        if item.isDirectory {
            let success = fileService.moveItem(dragged, to: item.url.path)
            dropTarget = nil
            onDrop(success)
            return success
        }
        
        dropTarget = nil
        return false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedItem else { return false }
        
        let isValid = item.isDirectory && 
                     dragged.url != item.url && 
                     !dragged.isDirectory &&
                     !item.url.path.hasPrefix(dragged.url.path + "/")
        return isValid
    }
    
    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) {
            dropTarget = item
        }
    }
    
    func dropExited(info: DropInfo) {
        dropTarget = nil
    }
}
