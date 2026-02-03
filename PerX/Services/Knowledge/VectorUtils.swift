import Foundation

/// Calcola la cosine similarity tra due vettori Float
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard !a.isEmpty, !b.isEmpty, a.count == b.count else { return 0 }
    
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    
    let denom = sqrtf(normA) * sqrtf(normB)
    if denom == 0 { return 0 }
    return dot / denom
}

