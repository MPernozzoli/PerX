import Foundation
import CoreData

/// Servizio per sincronizzare i dati del bene con tag foto e PerxiaBene
@MainActor
class BeneSyncService: ObservableObject {
    static let shared = BeneSyncService()
    
    private let fileTagManager = FileTagManager.shared
    
    private init() {}
    
    // MARK: - Verifica collegamento con foto/Perxia
    
    /// Verifica se il bene ha foto associate tramite i tag
    func hasFotoAssociate(bene: Bene, sinistroPath: String?) -> Bool {
        guard let path = sinistroPath else { return false }
        
        let fileTags = fileTagManager.fileTags
        
        for (filePath, tags) in fileTags {
            guard filePath.hasPrefix(path) else { continue }
            
            for tag in tags {
                if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                    if let beneRif = fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id),
                       beneRif.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Verifica se il bene ha un PerxiaBene corrispondente
    func getPerxiaBeneCorrispondente(bene: Bene, sinistro: Sinistro?) -> PerxiaBene? {
        guard let sinistro = sinistro else { return nil }
        
        return sinistro.beniPerxia.first { perxiaBene in
            perxiaBene.tipologia.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame
        }
    }
    
    // MARK: - Sincronizzazione Nome
    
    /// Aggiorna il nome del bene nei tag foto e PerxiaBene
    func sincronizzaNome(bene: Bene, vecchioNome: String, nuovoNome: String, sinistroPath: String?, viewContext: NSManagedObjectContext) {
        guard !vecchioNome.isEmpty, !nuovoNome.isEmpty, vecchioNome != nuovoNome else { return }
        guard let path = sinistroPath else { return }
        
        // Aggiorna tag foto
        let fileTags = fileTagManager.fileTags
        
        for (filePath, tags) in fileTags {
            guard filePath.hasPrefix(path) else { continue }
            
            for tag in tags {
                if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                    if let beneRif = fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id),
                       beneRif.localizedCaseInsensitiveCompare(vecchioNome) == .orderedSame {
                        fileTagManager.setBeneRiferimento(nuovoNome, forFile: filePath, tagId: tag.id)
                    }
                }
            }
        }
        
        // Aggiorna PerxiaBene
        if let sinistro = bene.partita?.perizia?.sinistro ?? bene.periziaBozza?.sinistro {
            for pb in sinistro.beniPerxia {
                if pb.tipologia.localizedCaseInsensitiveCompare(vecchioNome) == .orderedSame {
                    pb.tipologia = nuovoNome
                    break
                }
            }
        }
        
        try? viewContext.save()
    }
    
    // MARK: - Sincronizzazione Modello/Anno con reset certezza
    
    /// Aggiorna il modello nel PerxiaBene e resetta la certezza
    func sincronizzaModello(bene: Bene, nuovoModello: String?, viewContext: NSManagedObjectContext) {
        guard let sinistro = bene.partita?.perizia?.sinistro ?? bene.periziaBozza?.sinistro else { return }
        
        for perxiaBene in sinistro.beniPerxia {
            if perxiaBene.tipologia.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame {
                perxiaBene.modello = nuovoModello
                perxiaBene.certezzaModello = 0.0
                break
            }
        }
        
        try? viewContext.save()
    }
    
    /// Aggiorna l'anno nel PerxiaBene e resetta la certezza
    func sincronizzaAnno(bene: Bene, nuovoAnno: String?, viewContext: NSManagedObjectContext) {
        guard let sinistro = bene.partita?.perizia?.sinistro ?? bene.periziaBozza?.sinistro else { return }
        
        for perxiaBene in sinistro.beniPerxia {
            if perxiaBene.tipologia.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame {
                perxiaBene.anno = nuovoAnno
                perxiaBene.certezzaAnno = 0.0
                break
            }
        }
        
        try? viewContext.save()
    }
    
    // MARK: - Ottieni lista foto associate
    
    func getFotoAssociate(bene: Bene, sinistroPath: String?) -> [String] {
        guard let path = sinistroPath else { return [] }
        
        var fotoAssociate: [String] = []
        let fileTags = fileTagManager.fileTags
        
        for (filePath, tags) in fileTags {
            guard filePath.hasPrefix(path) else { continue }
            
            for tag in tags {
                if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                    if let beneRif = fileTagManager.getBeneRiferimento(forFile: filePath, tagId: tag.id),
                       beneRif.localizedCaseInsensitiveCompare(bene.nome) == .orderedSame {
                        fotoAssociate.append(filePath)
                        break
                    }
                }
            }
        }
        
        return fotoAssociate
    }
}
