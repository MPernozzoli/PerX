import AppKit

class ExcelService {
    static let shared = ExcelService()
    
    func openExcelFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    // TODO: In futuro implementare qui le funzioni per:
    // - Lettura dati Excel
    // - Parsing delle informazioni
    // - Estrazione automatica dei dati
    // - Generazione report
    // Quando rimetteremo CoreXLSX o un'altra libreria per gestire i file Excel
} 
