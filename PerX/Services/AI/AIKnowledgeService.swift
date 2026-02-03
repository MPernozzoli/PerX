import Foundation
import CoreData

/// Gestisce documenti conoscenza per i prompt dei modelli locali
class AIKnowledgeService {
    static let shared = AIKnowledgeService()
    private let context: NSManagedObjectContext
    
    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    /// Recupera i testi attivi per una categoria, ordinati
    func getContext(for category: String) -> String {
        let request: NSFetchRequest<AIKnowledgeDocument> = AIKnowledgeDocument.fetchRequest()
        request.predicate = NSPredicate(format: "categoria == %@ AND attivo == YES", category)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AIKnowledgeDocument.ordine, ascending: true)]
        
        do {
            let docs = try context.fetch(request)
            return docs.map { $0.contenuto }.joined(separator: "\n\n")
        } catch {
            print("[AIKnowledgeService] Errore fetch knowledge: \(error)")
            return ""
        }
    }
    
    /// Recupera tutte le categorie attive
    func getAvailableCategories() -> [String] {
        let request: NSFetchRequest<AIKnowledgeDocument> = AIKnowledgeDocument.fetchRequest()
        request.propertiesToFetch = []
        if let docs = try? context.fetch(request) {
            let categories = docs.map { $0.categoria }
            return Array(Set(categories)).sorted()
        }
        return []
    }
}

