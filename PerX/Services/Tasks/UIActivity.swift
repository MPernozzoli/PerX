import Combine
import Foundation

/// Segnale per la UI: un calcolo è in corso, ma non sul thread che disegna.
@MainActor
final class UIActivity: ObservableObject {
    static let shared = UIActivity()

    @Published private(set) var label: String?
    private var depth = 0

    private init() {}

    var isBusy: Bool { label != nil }

    func begin(_ label: String) {
        depth += 1
        self.label = label
    }

    func end() {
        depth = max(0, depth - 1)
        if depth == 0 {
            label = nil
        }
    }
}
