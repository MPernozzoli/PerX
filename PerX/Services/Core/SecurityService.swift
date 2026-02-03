import Foundation
import AppKit

class SecurityService {
    static let shared = SecurityService()
    private let logService = LogService()
    
    func accessDirectory(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            logService.addLog(.error, message: "Directory non trovata: \(path)")
            return false
        }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isReadableKey, .isWritableKey])
            guard let isReadable = resourceValues.isReadable else {
                logService.addLog(.error, message: "Impossibile determinare i permessi di lettura")
                return false
            }
            
            if !isReadable {
                logService.addLog(.error, message: "Directory non leggibile: \(path)")
                return false
            }
            return true
        } catch {
            logService.addLog(.error, message: "Errore nell'accesso alla directory: \(error.localizedDescription)")
            return false
        }
    }
} 

