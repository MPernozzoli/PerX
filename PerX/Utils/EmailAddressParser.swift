import Foundation

class EmailAddressParser {
    
    static func parse(addressString: String) -> Contact {
        let trimmedString = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let components = trimmedString.components(separatedBy: CharacterSet(charactersIn: "<>"))
        
        if components.count >= 2 {
            let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
            let email = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Contact(name: name.isEmpty ? nil : name, email: email)
        } else {
            return Contact(name: nil, email: trimmedString)
        }
    }
    
    static func parse(addressesString: String) -> [Contact] {
        let individualAddresses = addressesString.components(separatedBy: ",")
        return individualAddresses.map { parse(addressString: $0) }
    }
} 