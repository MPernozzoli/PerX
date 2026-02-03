import SwiftUI

// MARK: - String Extension for Default Values
extension String? {
    func defaultValue(_ fieldName: String) -> String {
        self?.isEmpty == false ? self! : "\(fieldName) mancante"
    }
}

// MARK: - DefaultableText Component
/// Componente riutilizzabile per campi di testo con valore di default
struct DefaultableText: View {
    let value: String?
    let fieldName: String
    
    var body: some View {
        Text(value.defaultValue(fieldName))
            .italic(value?.isEmpty != false)
            .foregroundColor(value?.isEmpty == false ? .primary : .secondary.opacity(0.7))
    }
}
