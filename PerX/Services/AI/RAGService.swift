import Foundation

/// Servizio RAG per informazioni peritali
class RAGService {
    static let shared = RAGService()
    
    private var knowledgeBase: [RAGDocument] = []
    private var index: [String: [Int]] = [:] // keyword -> document indices
    
    private init() {
        loadKnowledgeBase()
        buildIndex()
    }
    
    // MARK: - Public API
    
    /// Cerca informazioni rilevanti per una query
    func search(query: String, maxResults: Int = 5) -> [RAGDocument] {
        let keywords = extractKeywords(from: query)
        var documentScores: [Int: Int] = [:]
        
        // Score basato su keyword matching
        for keyword in keywords {
            if let docIndices = index[keyword.lowercased()] {
                for docIndex in docIndices {
                    documentScores[docIndex] = (documentScores[docIndex] ?? 0) + 1
                }
            }
        }
        
        // Ordina per score
        let sortedIndices = documentScores.sorted { $0.value > $1.value }
            .prefix(maxResults)
            .map { $0.key }
        
        return sortedIndices.compactMap { index in
            guard index < knowledgeBase.count else { return nil }
            return knowledgeBase[index]
        }
    }
    
    /// Costruisce il contesto per un prompt basato su una query
    func buildContext(for query: String, personality: AIPersonality? = nil) -> String {
        let documents = search(query: query, maxResults: 3)
        
        guard !documents.isEmpty else {
            return ""
        }
        
        var context = "Informazioni rilevanti dal knowledge base peritale:\n\n"
        
        for (index, doc) in documents.enumerated() {
            context += "\(index + 1). \(doc.title)\n"
            context += "\(doc.content)\n\n"
        }
        
        // Aggiungi contesto specifico per personalità se necessario
        if let personality = personality {
            context += getPersonalityContext(personality: personality)
        }
        
        return context
    }
    
    /// Aggiunge un documento al knowledge base
    func addDocument(_ document: RAGDocument) {
        knowledgeBase.append(document)
        updateIndex(for: document, at: knowledgeBase.count - 1)
    }
    
    /// Rimuove un documento dal knowledge base
    func removeDocument(at index: Int) {
        guard index < knowledgeBase.count else { return }
        knowledgeBase.remove(at: index)
        rebuildIndex()
    }
    
    // MARK: - Private Implementation
    
    private func loadKnowledgeBase() {
        // Carica documenti base peritali
        let baseDocuments = [
            RAGDocument(
                title: "Procedura Liquidazione Sinistri",
                content: "La liquidazione di un sinistro prevede: 1) Verifica documentazione, 2) Valutazione danni, 3) Calcolo importo liquidabile, 4) Redazione perizia, 5) Invio alla compagnia. Importante verificare sempre la completezza della documentazione prima di procedere.",
                category: "procedure",
                tags: ["liquidazione", "procedura", "perizia"]
            ),
            RAGDocument(
                title: "Tipi di Danno - Fulminazione",
                content: "La fulminazione può causare: danni elettrici ad apparecchiature, surriscaldamento di componenti, interruzione di servizi, danni a impianti. Verificare sempre la presenza di certificazioni CE e la conformità degli impianti. Documentare con foto dettagliate i punti di impatto.",
                category: "danni",
                tags: ["fulminazione", "danno elettrico", "impianti"]
            ),
            RAGDocument(
                title: "Normativa Assicurativa Base",
                content: "Le polizze coprono danni diretti e indiretti. I danni diretti sono quelli immediatamente causati dall'evento. I danni indiretti includono mancato guadagno, spese accessorie. Verificare sempre i massimali e le franchigie applicabili.",
                category: "normativa",
                tags: ["normativa", "polizza", "copertura", "massimali"]
            ),
            RAGDocument(
                title: "Comunicazione con Assicurato",
                content: "La comunicazione con l'assicurato deve essere chiara, professionale e tempestiva. Fornire sempre informazioni precise su stato del sinistro, documentazione necessaria, tempistiche. Mantenere un tono empatico ma professionale.",
                category: "comunicazione",
                tags: ["comunicazione", "assicurato", "relazioni"]
            ),
            RAGDocument(
                title: "Documentazione Richiesta Standard",
                content: "Documentazione standard per sinistro: denuncia sinistro, polizza assicurativa, fatture/ricevute beni danneggiati, foto dei danni, preventivi di riparazione/sostituzione, certificazioni tecniche se applicabili. Verificare sempre la completezza prima di procedere.",
                category: "documentazione",
                tags: ["documentazione", "documenti", "richiesta"]
            )
        ]
        
        knowledgeBase = baseDocuments
    }
    
    private func buildIndex() {
        index.removeAll()
        
        for (docIndex, document) in knowledgeBase.enumerated() {
            updateIndex(for: document, at: docIndex)
        }
    }
    
    private func updateIndex(for document: RAGDocument, at docIndex: Int) {
        var allKeywords = extractKeywords(from: document.title + " " + document.content)
        allKeywords.append(contentsOf: document.tags)
        
        for keyword in allKeywords {
            let lowercased = keyword.lowercased()
            if self.index[lowercased] == nil {
                self.index[lowercased] = []
            }
            if !self.index[lowercased]!.contains(docIndex) {
                self.index[lowercased]!.append(docIndex)
            }
        }
    }
    
    private func rebuildIndex() {
        buildIndex()
    }
    
    private func extractKeywords(from text: String) -> [String] {
        // Estrae parole significative (almeno 3 caratteri, non stop words)
        let stopWords = Set(["il", "la", "lo", "gli", "le", "di", "a", "da", "in", "con", "su", "per", "tra", "fra", "e", "o", "ma", "se", "che", "un", "una", "uno", "dei", "delle", "degli", "del", "della", "dello", "al", "alla", "allo", "ai", "alle", "agli", "dal", "dalla", "dallo", "dai", "dalle", "dagli", "nel", "nella", "nello", "nei", "nelle", "negli", "sul", "sulla", "sullo", "sui", "sulle", "sugli"])
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        
        return Array(Set(words)) // Rimuove duplicati
    }
    
    private func getPersonalityContext(personality: AIPersonality) -> String {
        switch personality {
        case .elettra:
            return "\nContesto personalità: Elettra è l'assistente front desk, specializzata in comunicazione con clienti, gestione email, pianificazione attività. Usa un tono professionale ma amichevole, è orientata all'efficienza e alla chiarezza.\n"
        case .sparky:
            return "\nContesto personalità: Sparky è l'assistente tecnico, specializzato in analisi tecniche, valutazioni danni, perizie dettagliate. Usa un linguaggio più tecnico e preciso, si concentra sui dettagli tecnici e sulle specifiche.\n"
        }
    }
}

/// Documento nel knowledge base RAG
struct RAGDocument: Identifiable, Codable {
    let id: UUID
    let title: String
    let content: String
    let category: String
    let tags: [String]
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        category: String,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
    }
}

