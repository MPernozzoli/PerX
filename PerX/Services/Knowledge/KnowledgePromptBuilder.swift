import Foundation

/// Contesto di prompt con knowledge allegata
struct PromptContext {
    let systemInstructions: String
    let userMessage: String
    let knowledgeChunks: [KnowledgeChunk]
}

/// Costruisce il prompt standard PerX con Knowledge Bounded Prompting
func buildPerXPrompt(from task: AITask) -> String {
    let baseSystem = """
    Sei un assistente per periti assicurativi ramo property, specializzato in fenomeno elettrico.
    Devi attenerti rigorosamente alla documentazione tecnica fornita.
    Se una informazione non è presente nei documenti, devi dichiararlo esplicitamente.
    Evita di inventare normative, tabelle o procedure non presenti nella documentazione.
    Rispondi in modo tecnico, sintetico e coerente con il linguaggio peritale.
    """
    
    let knowledgeSection: String
    if !task.knowledgeChunks.isEmpty {
        let docsText = task.knowledgeChunks
            .sorted {
                if $0.documentID == $1.documentID {
                    return $0.chunkIndex < $1.chunkIndex
                }
                return $0.documentID < $1.documentID
            }
            .map { chunk in
                """
                [Documento: \(chunk.documentID), Sezione: \(chunk.section ?? "-"), Index: \(chunk.chunkIndex)]
                \(chunk.text)
                """
            }
            .joined(separator: "\n---\n")
        
        knowledgeSection = """
        
        === DOCUMENTAZIONE TECNICA DISPONIBILE ===
        \(docsText)
        """
    } else {
        knowledgeSection = """
        
        === DOCUMENTAZIONE TECNICA DISPONIBILE ===
        Nessun estratto di documentazione è stato fornito. Se necessario, indica esplicitamente che non puoi pronunciarti in assenza di documentazione tecnica.
        """
    }
    
    let userSection: String
    if let inputText = task.parameters["inputText"]?.value as? String {
        userSection = """
        
        === CONTESTO/DOMANDA ===
        \(inputText)
        """
    } else if let prompt = task.parameters["prompt"]?.value as? String {
        userSection = """
        
        === CONTESTO/DOMANDA ===
        \(prompt)
        """
    } else {
        userSection = """
        
        === CONTESTO/DOMANDA ===
        Nessun testo esplicito fornito.
        """
    }
    
    return baseSystem + knowledgeSection + userSection
}

