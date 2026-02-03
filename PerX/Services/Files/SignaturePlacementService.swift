import Foundation
import AppKit
import CoreGraphics

/// Gestisce il posizionamento e salvataggio delle firme mobili sui file
@MainActor
final class SignaturePlacementService: ObservableObject {
    static let shared = SignaturePlacementService()
    
    private let defaults = UserDefaults.standard
    private let signaturesKey = "SignaturePlacements"
    private let versioningService = FileVersioningService.shared
    
    struct SignaturePlacement: Codable {
        let filePath: String
        let signatureType: String // "individual" o "studio"
        let position: CGPoint
        let size: CGSize
        let pageIndex: Int? // Per PDF, nil per immagini
        let signatureImageData: Data? // PNG data della firma per la stampa
        
        enum CodingKeys: String, CodingKey {
            case filePath, signatureType, pageIndex, signatureImageData
            case positionX, positionY, sizeWidth, sizeHeight
        }
        
        init(filePath: String, signatureType: String, position: CGPoint, size: CGSize, pageIndex: Int?, signatureImageData: Data? = nil) {
            self.filePath = filePath
            self.signatureType = signatureType
            self.position = position
            self.size = size
            self.pageIndex = pageIndex
            self.signatureImageData = signatureImageData
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filePath = try container.decode(String.self, forKey: .filePath)
            signatureType = try container.decode(String.self, forKey: .signatureType)
            pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
            
            let positionX = try container.decode(CGFloat.self, forKey: .positionX)
            let positionY = try container.decode(CGFloat.self, forKey: .positionY)
            position = CGPoint(x: positionX, y: positionY)
            
            let sizeWidth = try container.decode(CGFloat.self, forKey: .sizeWidth)
            let sizeHeight = try container.decode(CGFloat.self, forKey: .sizeHeight)
            size = CGSize(width: sizeWidth, height: sizeHeight)
            
            // Decodifica signatureImageData se presente
            if container.contains(.signatureImageData) {
                self.signatureImageData = try? container.decodeIfPresent(Data.self, forKey: .signatureImageData)
            } else {
                self.signatureImageData = nil
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(signatureType, forKey: .signatureType)
            try container.encodeIfPresent(pageIndex, forKey: .pageIndex)
            try container.encode(position.x, forKey: .positionX)
            try container.encode(position.y, forKey: .positionY)
            try container.encode(size.width, forKey: .sizeWidth)
            try container.encode(size.height, forKey: .sizeHeight)
            try container.encodeIfPresent(signatureImageData, forKey: .signatureImageData)
        }
    }
    
    private var placements: [String: SignaturePlacement] = [:]
    
    private init() {
        loadPlacements()
        // Carica anche dal versioning per sincronizzazione
        loadPlacementsFromVersioning()
    }
    
    private func loadPlacementsFromVersioning() {
        // Questo metodo può essere chiamato quando necessario per sincronizzare
        // Per ora, i placement vengono caricati on-demand quando si apre un file
    }
    
    // MARK: - Salvataggio/Caricamento
    
    private func loadPlacements() {
        guard let data = defaults.data(forKey: signaturesKey),
              let decoded = try? JSONDecoder().decode([String: SignaturePlacement].self, from: data) else {
            placements = [:]
            return
        }
        placements = decoded
    }
    
    private func savePlacements() {
        guard let data = try? JSONEncoder().encode(placements) else {
            return
        }
        defaults.set(data, forKey: signaturesKey)
    }
    
    // MARK: - API Pubblica
    
    func getPlacement(for filePath: String) -> SignaturePlacement? {
        // Prima cerca nei placement locali
        if let placement = placements[filePath] {
            return placement
        }
        
        // Se non trovato, prova a caricare dal versioning
        if let sinistroPath = getSinistroPath(for: filePath),
           let placement = loadPlacementFromVersioning(for: filePath, sinistroPath: sinistroPath) {
            // Salva localmente per prossime volte
            placements[filePath] = placement
            return placement
        }
        
        return nil
    }
    
    func setPlacement(_ placement: SignaturePlacement) {
        placements[placement.filePath] = placement
        savePlacements()
        
        // Salva anche nel versioning per la sincronizzazione
        if let sinistroPath = getSinistroPath(for: placement.filePath) {
            savePlacementToVersioning(placement, sinistroPath: sinistroPath)
        }
    }
    
    private func getSinistroPath(for filePath: String) -> String? {
        let pathComponents = (filePath as NSString).pathComponents
        for i in stride(from: pathComponents.count - 1, through: 0, by: -1) {
            let partialPath = pathComponents[0...i].joined(separator: "/")
            let component = pathComponents[i]
            if component.count == 7 && component.allSatisfy({ $0.isNumber }) {
                return partialPath
            }
        }
        return nil
    }
    
    private func savePlacementToVersioning(_ placement: SignaturePlacement, sinistroPath: String) {
        let versionsDir = versioningService.getVersionsDirectory(for: sinistroPath)
        let fileName = (placement.filePath as NSString).lastPathComponent
        let placementFileName = "\(fileName).signature.json"
        let placementPath = (versionsDir as NSString).appendingPathComponent(placementFileName)
        
        guard let data = try? JSONEncoder().encode(placement) else {
            return
        }
        
        do {
            try data.write(to: URL(fileURLWithPath: placementPath), options: .atomic)
        } catch {
            print("[SignaturePlacementService] ❌ Errore salvataggio placement in versioning: \(error)")
        }
    }
    
    func loadPlacementFromVersioning(for filePath: String, sinistroPath: String) -> SignaturePlacement? {
        let versionsDir = versioningService.getVersionsDirectory(for: sinistroPath)
        let fileName = (filePath as NSString).lastPathComponent
        let placementFileName = "\(fileName).signature.json"
        let placementPath = (versionsDir as NSString).appendingPathComponent(placementFileName)
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: placementPath)),
              let placement = try? JSONDecoder().decode(SignaturePlacement.self, from: data) else {
            return nil
        }
        
        return placement
    }
    
    func removePlacement(for filePath: String) {
        placements.removeValue(forKey: filePath)
        savePlacements()
    }
    
    func hasPlacement(for filePath: String) -> Bool {
        return placements[filePath] != nil
    }
}
