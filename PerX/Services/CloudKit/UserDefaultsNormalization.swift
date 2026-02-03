import Foundation

// MARK: - UserDefaults Normalization

/// Utility per normalizzare/denormalizzare valori UserDefaults per la serializzazione JSON.
/// Gestisce tipi non-JSON-nativi come Data e Date.
enum UserDefaultsNormalization {
    
    /// Normalizza un valore per la serializzazione JSON.
    /// Converte Data e Date in dizionari con metadati di tipo.
    /// - Parameter value: Il valore da normalizzare
    /// - Returns: Il valore normalizzato (JSON-compatibile)
    static func normalize(_ value: Any) -> Any {
        if let data = value as? Data {
            return ["__type": "data", "base64": data.base64EncodedString()]
        }
        if let date = value as? Date {
            return ["__type": "date", "ts": date.timeIntervalSince1970]
        }
        if let array = value as? [Any] {
            return array.map { normalize($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalize($0) }
        }
        // PropertyList types: String/Bool/Number
        return value
    }
    
    /// Denormalizza un valore JSON in un valore UserDefaults.
    /// Riconverte i dizionari con metadati di tipo in Data e Date.
    /// - Parameter value: Il valore da denormalizzare
    /// - Returns: Il valore denormalizzato o nil se non valido
    static func denormalize(_ value: Any) -> Any? {
        if let dict = value as? [String: Any],
           let type = dict["__type"] as? String {
            switch type {
            case "data":
                if let b64 = dict["base64"] as? String, let data = Data(base64Encoded: b64) { return data }
                return nil
            case "date":
                if let ts = dict["ts"] as? Double { return Date(timeIntervalSince1970: ts) }
                return nil
            default:
                return nil
            }
        }
        if let array = value as? [Any] {
            return array.compactMap { denormalize($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.compactMapValues { denormalize($0) }
        }
        return value
    }
    
    /// Codifica un dizionario snapshot in JSON string.
    /// - Parameter snapshot: Il dizionario da codificare
    /// - Returns: La stringa JSON
    static func encodeSnapshotJSON(_ snapshot: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// Decodifica una stringa JSON in un dizionario.
    /// - Parameter json: La stringa JSON da decodificare
    /// - Returns: Il dizionario decodificato o nil se non valido
    static func decodeSnapshotJSON(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }
}
