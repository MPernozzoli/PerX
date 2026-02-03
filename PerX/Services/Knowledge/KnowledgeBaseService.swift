import Foundation
import SQLite3

/// Protocollo di accesso read-only alla base di conoscenza vettoriale
protocol KnowledgeBaseProtocol {
    func loadKnowledgeIfNeeded() throws
    func search(
        queryEmbedding: [Float],
        domains: [KnowledgeDomain],
        maxResults: Int
    ) -> [KnowledgeChunk]
}

/// Implementazione locale della KB vettoriale basata su SQLite
final class KnowledgeBaseService: KnowledgeBaseProtocol {
    static let shared = KnowledgeBaseService()
    
    /// Provider di embedding (default: OpenAI)
    var embeddingProvider: EmbeddingProvider = OpenAIEmbeddingProvider.shared
    
    private let kbFileName = "kb.sqlite"
    private var chunks: [KnowledgeChunk] = []
    private var isLoaded = false
    private let loadQueue = DispatchQueue(label: "it.perx.knowledge.load")
    
    private init() {}
    
    // MARK: - Public API
    
    func loadKnowledgeIfNeeded() throws {
        if isLoaded { return }
        try loadQueue.sync {
            if isLoaded { return }
            print("[KB] ⏳ Caricamento kb.sqlite...")
            try self.loadFromDatabase()
            isLoaded = true
            print("[KB] ✅ Caricati \(self.chunks.count) chunk dalla KB")
        }
    }
    
    func search(
        queryEmbedding: [Float],
        domains: [KnowledgeDomain],
        maxResults: Int = 6
    ) -> [KnowledgeChunk] {
        guard !queryEmbedding.isEmpty, !chunks.isEmpty else { return [] }
        
        let domainSet = Set(domains.map { $0.rawValue })
        let allowAll = domainSet.isEmpty || domainSet.contains(KnowledgeDomain.generico.rawValue)
        let filteredChunks: [KnowledgeChunk]
        if allowAll {
            filteredChunks = chunks
        } else {
            filteredChunks = chunks.filter { domainSet.contains($0.documentID) }
        }
        
        let scored = filteredChunks.map { chunk in
            (chunk, cosineSimilarity(queryEmbedding, chunk.embedding))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxResults)
        .compactMap { $0.1 > 0 ? $0.0 : nil }
        
        return Array(scored)
    }
    
    // MARK: - Private
    
    private func loadFromDatabase() throws {
        guard let dbPath = resolveDatabasePath() else {
            throw NSError(domain: "KnowledgeBaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "kb.sqlite non trovato"])
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: "KnowledgeBaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Impossibile aprire il database"])
        }
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT id, document_id, section, chunk_index, text, embedding
        FROM kb_chunks
        ORDER BY document_id, chunk_index
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "KnowledgeBaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Impossibile preparare la query KB"])
        }
        defer { sqlite3_finalize(statement) }
        
        var loadedChunks: [KnowledgeChunk] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            
            guard let docIdCStr = sqlite3_column_text(statement, 1) else { continue }
            let documentID = String(cString: docIdCStr)
            
            let section: String?
            if let sectionCStr = sqlite3_column_text(statement, 2) {
                section = String(cString: sectionCStr)
            } else {
                section = nil
            }
            
            let chunkIndex = Int(sqlite3_column_int(statement, 3))
            
            guard let textCStr = sqlite3_column_text(statement, 4) else { continue }
            let text = String(cString: textCStr)
            
            let embeddingBlob = sqlite3_column_blob(statement, 5)
            let embeddingSize = sqlite3_column_bytes(statement, 5)
            let embedding = Self.parseEmbedding(blob: embeddingBlob, length: Int(embeddingSize))
            
            let chunk = KnowledgeChunk(
                id: id,
                documentID: documentID,
                section: section,
                chunkIndex: chunkIndex,
                text: text,
                embedding: embedding
            )
            loadedChunks.append(chunk)
        }
        
        self.chunks = loadedChunks
    }
    
    private func resolveDatabasePath() -> String? {
        // 1) Application Support/PerX/kb.sqlite
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let candidate = support.appendingPathComponent("PerX").appendingPathComponent(kbFileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        
        // 2) Bundle resource
        if let bundlePath = Bundle.main.path(forResource: "kb", ofType: "sqlite") {
            return bundlePath
        }
        
        // 3) Working directory fallback
        let cwdPath = FileManager.default.currentDirectoryPath + "/" + kbFileName
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }
        
        return nil
    }
    
    private static func parseEmbedding(blob: UnsafeRawPointer?, length: Int) -> [Float] {
        guard let blob = blob, length > 0 else { return [] }
        let count = length / MemoryLayout<Float>.size
        var result = [Float](repeating: 0, count: count)
        _ = result.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                memcpy(baseAddress, blob, length)
            }
        }
        return result
    }
}

