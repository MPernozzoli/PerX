import Foundation

/// Rappresenta un chunk di knowledge vettoriale letto da kb.sqlite
struct KnowledgeChunk: Identifiable, Hashable, Codable {
    let id: Int64
    let documentID: String
    let section: String?
    let chunkIndex: Int
    let text: String
    let embedding: [Float]
}

/// Domini/categorie dei documenti di knowledge
enum KnowledgeDomain: String, CaseIterable, Codable {
    case fenomenoElettrico = "FE_Basics"
    case letturaMotori = "Lettura_Motori_Compressori"
    case letturaSchede = "Lettura_Schede_Elettroniche"
    case seriali = "Seriali_Marche_Comuni"
    case stimaDanni = "Procedure_Stima_Danni"
    case generico = "Generico"
}

