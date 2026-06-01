import Foundation

/// Fornitore di embedding astratto (da implementare con modello reale)
protocol EmbeddingProvider {
    func embed(text: String) async throws -> [Float]
}

/// Implementazione stub in attesa del modello embedding reale
final class StubEmbeddingProvider: EmbeddingProvider {
    func embed(text: String) async throws -> [Float] {
        // TODO: sostituire con embedding reale (MLX/altro)
        return []
    }
}
