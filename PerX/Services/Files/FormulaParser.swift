import Foundation
import SwiftUI

class FormulaParser: ObservableObject {
    static let shared = FormulaParser()
    
    private init() {}
    
    // Valuta una formula excel-like (es. "=A1+B2" o "=100*1.22")
    func evaluateFormula(
        _ formula: String,
        context: [String: NSDecimalNumber] = [:]
    ) -> NSDecimalNumber? {
        guard formula.hasPrefix("=") else {
            return nil
        }
        
        let expression = String(formula.dropFirst()).trimmingCharacters(in: .whitespaces)
        
        // Sostituisci riferimenti a celle (es. A1, B2) con valori dal contesto
        var processedExpression = expression
        for (key, value) in context {
            processedExpression = processedExpression.replacingOccurrences(of: key, with: value.stringValue)
        }
        
        // Rimuovi spazi
        processedExpression = processedExpression.replacingOccurrences(of: " ", with: "")
        
        // Esegui calcolo semplice (supporta +, -, *, /)
        return evaluateSimpleExpression(processedExpression)
    }
    
    private func evaluateSimpleExpression(_ expression: String) -> NSDecimalNumber? {
        // Cerca operatori in ordine di precedenza
        if let index = expression.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let operatorChar = expression[index]
            let left = String(expression[..<index])
            let right = String(expression[expression.index(after: index)...])
            
            guard let leftValue = evaluateSimpleExpression(left),
                  let rightValue = evaluateSimpleExpression(right) else {
                return nil
            }
            
            if operatorChar == "+" {
                return leftValue.adding(rightValue)
            } else {
                return leftValue.subtracting(rightValue)
            }
        }
        
        if let index = expression.lastIndex(where: { $0 == "*" || $0 == "/" }) {
            let operatorChar = expression[index]
            let left = String(expression[..<index])
            let right = String(expression[expression.index(after: index)...])
            
            guard let leftValue = evaluateSimpleExpression(left),
                  let rightValue = evaluateSimpleExpression(right) else {
                return nil
            }
            
            if operatorChar == "*" {
                return leftValue.multiplying(by: rightValue)
            } else {
                if rightValue.compare(NSDecimalNumber.zero) == .orderedSame {
                    return nil // Divisione per zero
                }
                return leftValue.dividing(by: rightValue)
            }
        }
        
        // Se non ci sono operatori, prova a convertire in numero
        let cleaned = expression.replacingOccurrences(of: ",", with: ".")
        if let value = Decimal(string: cleaned) {
            return NSDecimalNumber(decimal: value)
        }
        
        return nil
    }
    
    // Estrae riferimenti a celle da una formula (es. "A1", "B2")
    func extractCellReferences(_ formula: String) -> [String] {
        guard formula.hasPrefix("=") else {
            return []
        }
        
        let pattern = "([A-Z]+\\d+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(formula.startIndex..<formula.endIndex, in: formula)
        
        var references: [String] = []
        regex?.enumerateMatches(in: formula, options: [], range: range) { match, _, _ in
            if let match = match,
               let referenceRange = Range(match.range, in: formula) {
                references.append(String(formula[referenceRange]))
            }
        }
        
        return references
    }
}

