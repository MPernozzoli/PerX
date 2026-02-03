import Foundation
import CoreData

@MainActor
class DirectoryService: ObservableObject {
    @Published var isScanning = false
    private let logService: LogService
    private let viewContext: NSManagedObjectContext
    private let fileManager = FileManager.default
    
    init(logService: LogService, viewContext: NSManagedObjectContext) {
        self.logService = logService
        self.viewContext = viewContext
    }
    
    func scanDirectories(mainDirectory: String?, activeDirectory: String?, closedDirectory: String?) {
        guard !isScanning else { 
            logService.addLog(.warning, message: "Scansione già in corso")
            return 
        }
        
        isScanning = true
        logService.addLog(.info, message: "Avvio scansione directory")
        
        if let mainDir = mainDirectory, !mainDir.isEmpty {
            scanDirectorySync(path: mainDir)
        } else if let activeDir = activeDirectory,
                  let closedDir = closedDirectory,
                  !activeDir.isEmpty,
                  !closedDir.isEmpty {
            scanDirectorySync(path: activeDir)
            scanDirectorySync(path: closedDir)
        }
        
        logService.addLog(.info, message: "Scansione completata con successo")
        isScanning = false
    }
    
    private func scanDirectorySync(path: String) {
        guard fileManager.fileExists(atPath: path) else {
            logService.addLog(.error, message: "Directory non trovata: \(path)")
            return
        }
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            logService.addLog(.error, message: "Impossibile accedere alla directory: \(path)")
            return
        }
        
        var processedCount = 0
        while let filePath = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(filePath)
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                if let sinistroRef = extractSinistroReference(from: (filePath as NSString).lastPathComponent) {
                    processSinistroDirectorySync(ref: sinistroRef, path: fullPath)
                    processedCount += 1
                    if processedCount % 10 == 0 {
                        logService.addLog(.info, message: "Processati \(processedCount) sinistri")
                    }
                }
            }
        }
    }
    
    private func extractSinistroReference(from dirName: String) -> String? {
        let pattern = "\\d{7}"
        if let range = dirName.range(of: pattern, options: .regularExpression) {
            let ref = String(dirName[range])
            logService.addLog(.info, message: "Trovato riferimento: \(ref)")
            return ref
        }
        return nil
    }
    
    private func processSinistroDirectorySync(ref: String, path: String) {
        do {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", ref)
            
            let results = try viewContext.fetch(request)
            let sinistro: Sinistro
            
            if let existingSinistro = results.first {
                sinistro = existingSinistro
                logService.addLog(.info, message: "Aggiornamento sinistro esistente: \(ref)")
            } else {
                // Modifica: Non creare mai sinistri nuovi dalla scansione directory
                logService.addLog(.warning, message: "Sinistro \(ref) trovato su disco ma non censito nel DB. Salto.")
                return
            }
            
            checkSinistroFilesSync(sinistro: sinistro, path: path)
            try viewContext.save()
            
        } catch {
            logService.addLog(.error, message: "Errore nel processare il sinistro \(ref): \(error.localizedDescription)")
        }
    }
    
    private func checkSinistroFilesSync(sinistro: Sinistro, path: String) {
        guard UserDefaults.standard.bool(forKey: "enableAutoStateChange") else {
            return
        }
        
        // Rileva file "atto da firmare" nella cartella sinistro
        let attoDaFirmarePatterns = [
            "atto da firmare",
            "atto_da_firmare",
            "atto da inviare",
            "atto_da_inviare"
        ]
        
        var attoDaFirmareFound = false
        var attoDaFirmareDate: Date?
        
        // Cerca file con pattern "atto da firmare"
        if let enumerator = fileManager.enumerator(atPath: path) {
            while let filePath = enumerator.nextObject() as? String {
                let fileName = (filePath as NSString).lastPathComponent.lowercased()
                let fullPath = (path as NSString).appendingPathComponent(filePath)
                
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                
                // Verifica se il file contiene uno dei pattern
                if attoDaFirmarePatterns.contains(where: { fileName.contains($0) }) {
                    if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
                       let creationDate = attributes[.creationDate] as? Date {
                        attoDaFirmareFound = true
                        attoDaFirmareDate = creationDate
                        break
                    }
                }
            }
        }
        
        // Se trovato "atto da firmare", cambia stato a "atto da inviare" o "esito da comunicare"
        if attoDaFirmareFound {
            let currentStateDesc = sinistro.stato ?? ""
            let statoManager = StatoManager.shared
            let currentStateId = statoManager.getStatoId(fromDescrizione: currentStateDesc)
            let currentState = currentStateId.flatMap { StatoManager.StatoSinistro(rawValue: $0) }
            
            // Verifica se è perizia senza atto (es. Zurich concordata senza divisione SI/VSU)
            let isPeriziaSenzaAtto = sinistro.isPeriziaSenzaAtto
            
            let targetState: StatoManager.StatoSinistro = isPeriziaSenzaAtto ? .esitoDaComunicare : .attoDaInviare
            
            // Verifica se la transizione è valida
            if let currentState = currentState,
               currentState.validTransitions.contains(targetState) {
                Task {
                    do {
                        try await statoManager.changeState(
                            for: sinistro,
                            to: targetState,
                            context: viewContext
                        )
                        logService.addLog(.info, message: "Trovato atto da firmare per \(sinistro.riferimento ?? ""), stato aggiornato a \(targetState.descrizione)")
                    } catch {
                        logService.addLog(.warning, message: "Impossibile aggiornare stato per \(sinistro.riferimento ?? ""): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Mantieni logica legacy per "atto da inviare.pdf" (per retrocompatibilità)
        let attoPath = (path as NSString).appendingPathComponent("atto da inviare.pdf")
        if fileManager.fileExists(atPath: attoPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: attoPath),
               let creationDate = attributes[.creationDate] as? Date {
                // Questo è gestito dalla logica sopra, ma manteniamo per retrocompatibilità
                if sinistro.stato != StatoManager.StatoSinistro.attoDaInviare.descrizione &&
                   sinistro.stato != StatoManager.StatoSinistro.esitoDaComunicare.descrizione {
                    logService.addLog(.info, message: "Trovato atto da inviare.pdf per \(sinistro.riferimento ?? "")")
                }
            }
        }
        
        let closingFolder = (path as NSString).appendingPathComponent("da chiudere")
        if fileManager.fileExists(atPath: closingFolder) {
            let possibleFiles = [
                "\(sinistro.riferimento ?? "")_concordata.pdf",
                "\(sinistro.riferimento ?? "")_nonconcordata.pdf",
                "\(sinistro.riferimento ?? "").pdf"
            ]
            
            for fileName in possibleFiles {
                let filePath = (closingFolder as NSString).appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: filePath),
                   let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                   let creationDate = attributes[.creationDate] as? Date {
                    sinistro.stato = "Chiuso"
                    sinistro.dataChiusura = creationDate
                    logService.addLog(.info, message: "Trovato file di chiusura per \(sinistro.riferimento ?? "")")
                    break
                }
            }
        }
    }
    
    func verifySinistroFiles(sinistro: Sinistro) {
        guard let riferimento = sinistro.riferimento else { return }
        
        // Usa la cartella interna (Application Support)
        guard let sinistroDirPath = FileService.shared.getSinistroPath(riferimento: riferimento) else { return }
        
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sinistroDirPath, isDirectory: &isDirectory) && isDirectory.boolValue {
            checkSinistroFilesSync(sinistro: sinistro, path: sinistroDirPath)
            try? viewContext.save()
        }
    }
}

enum DirectoryError: Error {
    case directoryNotFound
    case accessDenied
    case processingError
} 