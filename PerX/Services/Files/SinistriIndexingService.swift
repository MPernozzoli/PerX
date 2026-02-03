import Foundation
import CoreData
import Combine

class SinistriIndexingService: ObservableObject {
    static let shared = SinistriIndexingService()
    
    @Published var isIndexing = false
    @Published var indexingProgress: Double = 0.0
    @Published var indexingCurrent: Int = 0
    @Published var indexingTotal: Int = 0
    
    private var indexingTask: Task<Void, Never>?
    
    private init() {}
    
    func startIndexing(context: NSManagedObjectContext) {
        guard !isIndexing else { return }
        
        // Cancella eventuale task precedente
        indexingTask?.cancel()
        
        isIndexing = true
        indexingProgress = 0.0
        indexingCurrent = 0
        indexingTotal = 0
        
        indexingTask = Task {
            await performIndexing(context: context)
        }
    }
    
    func stopIndexing() {
        indexingTask?.cancel()
        Task { @MainActor in
            isIndexing = false
        }
    }
    
    private func performIndexing(context: NSManagedObjectContext) async {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "stato != %@ AND stato != %@ AND stato != %@", "Chiuso", "Revocato", "Revocata")
        
        do {
            let sinistri = try context.fetch(request)
            
            await MainActor.run {
                indexingTotal = sinistri.count
            }
            
            if indexingTotal == 0 {
                await MainActor.run {
                    isIndexing = false
                }
                return
            }
            
            let batchSize = 2
            var processed = 0
            
            for i in stride(from: 0, to: sinistri.count, by: batchSize) {
                // Controlla se il task è stato cancellato
                if Task.isCancelled {
                    await MainActor.run {
                        isIndexing = false
                    }
                    return
                }
                
                let endIndex = min(i + batchSize, sinistri.count)
                let batch = Array(sinistri[i..<endIndex])
                
                await withTaskGroup(of: Void.self) { group in
                    for sinistro in batch {
                        group.addTask {
                            await self.processSinistro(sinistro, context: context)
                        }
                    }
                }
                
                processed += batch.count
                
                await MainActor.run {
                    indexingCurrent = processed
                    indexingProgress = Double(processed) / Double(indexingTotal)
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            await MainActor.run {
                isIndexing = false
                indexingProgress = 1.0
            }
        } catch {
            print("[Indicizzazione] ❌ Errore nel recupero sinistri: \(error)")
            await MainActor.run {
                isIndexing = false
            }
        }
    }
    
    private func processSinistro(_ sinistro: Sinistro, context: NSManagedObjectContext) async {
        guard let riferimento = sinistro.riferimento else {
            print("[Indicizzazione] ⚠️ Sinistro senza riferimento")
            return
        }
        
        do {
            let excelURL = try await ExcelFinderService.shared.findElaboratoPeritale(forSinistro: sinistro)
            await AutoCheckService.shared.readAndUpdateExcel(excelURL: excelURL, sinistro: sinistro)
        } catch let error as ExcelFinderService.ExcelFinderError {
            switch error {
            case .noExcelFileFound:
                // Verifica se la cartella esiste
                let fileService = FileService.shared
                if fileService.getSinistroPath(riferimento: riferimento) == nil {
                    print("[Indicizzazione] ⚠️ Sinistro \(riferimento): Cartella sinistro non trovata")
                } else {
                    print("[Indicizzazione] ⚠️ Sinistro \(riferimento): File Excel 'Elaborato_Peritale_*.xlsm' non trovato nella cartella")
                }
            case .multipleFilesNeedUserSelection:
                print("[Indicizzazione] ⚠️ Sinistro \(riferimento): Trovati più file Excel, serve selezione manuale")
            case .invalidFileName:
                print("[Indicizzazione] ⚠️ Sinistro \(riferimento): Nome file Excel non valido")
            case .permissionDenied:
                print("[Indicizzazione] ⚠️ Sinistro \(riferimento): Permessi negati per accedere al file Excel")
            }
        } catch {
            print("[Indicizzazione] ⚠️ Sinistro \(riferimento): Errore generico - \(error.localizedDescription)")
        }
    }
}
