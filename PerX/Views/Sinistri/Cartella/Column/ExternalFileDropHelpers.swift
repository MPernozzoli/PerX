import Foundation
import UniformTypeIdentifiers

enum ExternalFileDropHelpers {
    static func uniqueDestinationURL(in directory: URL, desiredName: String) -> URL {
        let fm = FileManager.default
        let baseName = (desiredName as NSString).deletingPathExtension
        let ext = (desiredName as NSString).pathExtension
        
        var candidate = directory.appendingPathComponent(desiredName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        
        // Finder-like: "nome 2.ext"
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(baseName) \(i)" : "\(baseName) \(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
    
    static func importFromProviders(
        _ providers: [NSItemProvider],
        to targetDirectoryPath: String,
        onResult: @escaping (Bool) -> Void
    ) {
        guard !providers.isEmpty else {
            onResult(false)
            return
        }
        
        let targetDirectoryURL = URL(fileURLWithPath: targetDirectoryPath)
        let fm = FileManager.default
        var successCount = 0
        var processedCount = 0
        let totalCount = providers.count
        
        for provider in providers {
            // Usa loadItem per ottenere direttamente l'URL, evitando file temporanei con solo URI come testo
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard error == nil else {
                        if let error { print("Errore loadItem fileURL: \(error)") }
                        processedCount += 1
                        if processedCount == totalCount {
                            DispatchQueue.main.async {
                                onResult(successCount > 0)
                            }
                        }
                        return
                    }
                    
                    // Gestisci diversi tipi di item
                    var sourceURL: URL?
                    
                    if let url = item as? URL {
                        sourceURL = url
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        sourceURL = url
                    } else if let string = item as? String,
                               let url = URL(string: string) {
                        sourceURL = url
                    }
                    
                    guard let sourceURL = sourceURL else {
                        print("Errore: impossibile estrarre URL da provider")
                        processedCount += 1
                        if processedCount == totalCount {
                            DispatchQueue.main.async {
                                onResult(successCount > 0)
                            }
                        }
                        return
                    }
                    
                    // Verifica che il file sorgente esista
                    guard fm.fileExists(atPath: sourceURL.path) else {
                        print("Errore: file sorgente non esiste: \(sourceURL.path)")
                        processedCount += 1
                        if processedCount == totalCount {
                            DispatchQueue.main.async {
                                onResult(successCount > 0)
                            }
                        }
                        return
                    }
                    
                    // Ottieni il nome del file
                    var fileName = sourceURL.lastPathComponent
                    if let suggestedName = provider.suggestedName, !suggestedName.isEmpty {
                        fileName = suggestedName
                    }
                    
                    // Gestisci directory: copia ricorsivamente
                    var isDirectory: ObjCBool = false
                    let exists = fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                    
                    guard exists else {
                        processedCount += 1
                        if processedCount == totalCount {
                            DispatchQueue.main.async {
                                onResult(successCount > 0)
                            }
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        let accessed = sourceURL.startAccessingSecurityScopedResource()
                        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
                        
                        do {
                            let destinationURL = uniqueDestinationURL(in: targetDirectoryURL, desiredName: fileName)
                            
                            if isDirectory.boolValue {
                                // Per directory: copia ricorsivamente
                                try fm.copyItem(at: sourceURL, to: destinationURL)
                            } else {
                                // Per file: copia normale
                                try fm.copyItem(at: sourceURL, to: destinationURL)
                            }
                            
                            successCount += 1
                        } catch {
                            print("Errore copia file drop esterno: \(error)")
                        }
                        
                        processedCount += 1
                        if processedCount == totalCount {
                            onResult(successCount > 0)
                        }
                    }
                }
                continue
            }
            
            // Fallback: item "public.file-url"
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let sourceURL = URL(dataRepresentation: data, relativeTo: nil) else {
                    if let error { print("Errore loadItem public.file-url: \(error)") }
                    processedCount += 1
                    if processedCount == totalCount {
                        DispatchQueue.main.async {
                            onResult(successCount > 0)
                        }
                    }
                    return
                }
                
                // Verifica che il file sorgente esista
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                    print("Errore: file sorgente non esiste: \(sourceURL.path)")
                    processedCount += 1
                    if processedCount == totalCount {
                        DispatchQueue.main.async {
                            onResult(successCount > 0)
                        }
                    }
                    return
                }
                
                var fileName = sourceURL.lastPathComponent
                if let suggestedName = provider.suggestedName, !suggestedName.isEmpty {
                    fileName = suggestedName
                }
                
                let destinationURL = uniqueDestinationURL(in: targetDirectoryURL, desiredName: fileName)
                
                DispatchQueue.main.async {
                    let accessed = sourceURL.startAccessingSecurityScopedResource()
                    defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
                    
                    do {
                        // copyItem gestisce automaticamente sia file che directory
                        try fm.copyItem(at: sourceURL, to: destinationURL)
                        successCount += 1
                    } catch {
                        print("Errore copia file drop esterno (fallback): \(error)")
                    }
                    
                    processedCount += 1
                    if processedCount == totalCount {
                        onResult(successCount > 0)
                    }
                }
            }
        }
    }
}

