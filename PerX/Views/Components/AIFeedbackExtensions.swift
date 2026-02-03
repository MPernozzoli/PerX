import SwiftUI

/// Estensioni per facilitare l'uso del feedback nelle view
extension View {
    /// Aggiunge un componente di feedback per un risultato AI
    func aiFeedback(
        result: AIResult,
        task: AITask?,
        userContext: [String: Any]? = nil
    ) -> some View {
        Group {
            if let task = task {
                VStack(alignment: .leading, spacing: 8) {
                    self
                    AIFeedbackInlineView(
                        result: result,
                        task: task,
                        userContext: userContext
                    )
                }
            } else {
                self
            }
        }
    }
}

/// Helper per ottenere il task da un risultato AI
struct AIFeedbackHelper {
    @MainActor
    static func getTask(for result: AIResult) -> AITask? {
        return AIManager.shared.getTask(for: result)
    }
    
    @MainActor
    static func getTask(forTaskID taskID: UUID) -> AITask? {
        return AIManager.shared.getTaskByID(taskID)
    }
}

