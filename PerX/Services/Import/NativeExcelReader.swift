import Foundation
import Compression

/// Lettore Excel nativo in Swift - SOLO API Foundation, nessuna dipendenza esterna
class NativeExcelReader {
    static let shared = NativeExcelReader()
    private init() {}
    
    static var isRunningInSandbox: Bool {
        return false
    }
    
    func readExcelFile(at url: URL) throws -> ImportService.ImportData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.invalidData("File Excel non trovato: \(url.lastPathComponent)")
        }
        let (sharedStrings, sheets) = try extractXLSX(from: url)
        guard let sheetXML = sheets.values.first else {
            throw ImportError.invalidData("Nessun foglio trovato")
        }
        let rows = parseWorksheet(xml: sheetXML, sharedStrings: sharedStrings)
        guard !rows.isEmpty else { return ImportService.ImportData(headers: [], rows: [], fileName: url.lastPathComponent) }
        return ImportService.ImportData(headers: rows[0], rows: Array(rows.dropFirst()), fileName: url.lastPathComponent)
    }
    
    func readClaimExcelFile(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "NativeExcelReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "File non trovato"])
        }
        let (sharedStrings, sheets) = try extractXLSX(from: url)
        guard let sheetXML = sheets["xl/worksheets/sheet1.xml"] ?? sheets.values.first else {
            throw NSError(domain: "NativeExcelReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nessun foglio"])
        }
        let cells = parseCells(from: sheetXML, sharedStrings: sharedStrings)
        func r(_ ref: String) -> String { cells[ref] ?? "" }
        
        // Parsing agenzia: formato [CODICE 3 char alfanumerici][NOME senza separatore]
        let agenziaFull = r("P8")
        let codAg: String
        let nomeAg: String
        if agenziaFull.count >= 3 {
            // I primi 3 caratteri sono il codice (uppercase)
            codAg = String(agenziaFull.prefix(3)).uppercased()
            // Il resto è il nome (Title Case)
            let nomeRaw = String(agenziaFull.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            nomeAg = titleCase(nomeRaw)
        } else {
            codAg = ""
            nomeAg = titleCase(agenziaFull)
        }
        
        // Nome contraente in Title Case
        let nomeContr = titleCase(r("D20"))
        
        // Estrazione contatti
        let (tel, em) = extractContacts(from: r("L20"))
        
        // Parsing data sopralluogo (S13) - come nello script Python
        let dataSopralluogoRaw = r("S13")
        let dataSopralluogo = parseDateString(dataSopralluogoRaw)
        
        var result: [String: Any] = [
            "gruppo": r("H5"),
            "nome_compagnia": r("P5"),
            "area": r("H8"),
            "codice_agenzia": codAg,
            "nome_agenzia": nomeAg,
            "numero_sinistro_compagnia": r("E10").uppercased(), // Sempre uppercase
            "data_sinistro": r("H13"),
            "data_denuncia": r("K13"),
            "data_incarico": r("P13"),
            "indirizzo": r("E14"),
            "numero_polizza": r("E16"),
            "tipo_polizza": r("P16"),
            "nome_contraente": nomeContr,
            "telefono_assicurato": tel.first ?? "",
            "telefoni_assicurato": tel,
            "email_assicurato": em.first ?? "",
            "email_assicurato_array": em,
            "nome_danneggiato": r("A24"),
            "importo_richiesto": r("I24").isEmpty ? "0" : r("I24"),
            "definizione": r("M24"),
            "stima_danno": r("S24").isEmpty ? "0" : r("S24"),
            "iban": r("D133"),
            "massimals": [
                Double(r("C34").replacingOccurrences(of: ",", with: ".")) ?? 0,
                Double(r("C35").replacingOccurrences(of: ",", with: ".")) ?? 0,
                Double(r("C36").replacingOccurrences(of: ",", with: ".")) ?? 0
            ]
        ]
        
        // Aggiungi data_sopralluogo solo se parsata correttamente
        if let dataSop = dataSopralluogo {
            result["data_sopralluogo"] = dataSop
        }
        
        return result
    }
    
    /// Converte una stringa in Title Case (iniziali maiuscole)
    private func titleCase(_ string: String) -> String {
        guard !string.isEmpty else { return string }
        return string.components(separatedBy: " ")
            .map { word in
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
    
    /// Prova a parsare una stringa come data nei formati comuni
    private func parseDateString(_ dateString: String) -> String? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Formati da provare (come nello script Python)
        let dateFormats = ["dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                // Restituisci nel formato standard dd/MM/yyyy
                formatter.dateFormat = "dd/MM/yyyy"
                return formatter.string(from: date)
            }
        }
        
        // Se non è una data valida, restituisci nil (potrebbe essere testo)
        return nil
    }
    
    private func extractXLSX(from url: URL) throws -> (sharedStrings: [String], sheets: [String: String]) {
        try readZIPDirectly(from: url)
    }
    
    private func readZIPDirectly(from url: URL) throws -> ([String], [String: String]) {
        guard let archive = MiniZIP(url: url) else { throw ImportError.invalidData("ZIP non leggibile") }
        var ss = ""; var sheets: [String: String] = [:]
        if let d = archive.read("xl/sharedStrings.xml"), let x = String(data: d, encoding: .utf8) { ss = x }
        for e in archive.entries where e.hasPrefix("xl/worksheets/") && e.hasSuffix(".xml") {
            if let d = archive.read(e), let x = String(data: d, encoding: .utf8) { sheets[e] = x }
        }
        return (parseSharedStrings(from: ss), sheets)
    }
    
    private func parseSharedStrings(from xml: String) -> [String] {
        guard !xml.isEmpty, let data = xml.data(using: .utf8) else { return [] }
        let p = SSParser(); let xp = XMLParser(data: data); xp.delegate = p; xp.parse(); return p.strings
    }
    
    private func parseWorksheet(xml: String, sharedStrings: [String]) -> [[String]] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let p = WSParser(ss: sharedStrings); let xp = XMLParser(data: data); xp.delegate = p; xp.parse(); return p.rows
    }
    
    private func parseCells(from xml: String, sharedStrings: [String]) -> [String: String] {
        guard let data = xml.data(using: .utf8) else { return [:] }
        let p = CParser(ss: sharedStrings); let xp = XMLParser(data: data); xp.delegate = p; xp.parse(); return p.cells
    }
    
    private func extractContacts(from text: String) -> ([String], [String]) {
        var tel: [String] = []; var em: [String] = []
        if let rx = try? NSRegularExpression(pattern: #"\+?\d[\d\s\-().]{5,14}\d"#) {
            for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) {
                    let n = String(text[r]).replacingOccurrences(of: #"[\s\-().]"#, with: "", options: .regularExpression)
                    if n.count >= 6 && n.count <= 15 { tel.append(n) }
                }
            }
        }
        if let rx = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: .caseInsensitive) {
            for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) { em.append(String(text[r]).lowercased()) }
            }
        }
        return (tel, em)
    }
}

// MARK: - XML Parsers
private class SSParser: NSObject, XMLParserDelegate {
    var strings: [String] = []; private var cur = ""; private var inT = false
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String] = [:]) {
        if e == "t" || e.hasSuffix(":t") { inT = true; cur = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inT { cur += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "t" || e.hasSuffix(":t") { inT = false }
        if e == "si" || e.hasSuffix(":si") { strings.append(cur); cur = "" }
    }
}

private class WSParser: NSObject, XMLParserDelegate {
    let ss: [String]; var rows: [[String]] = []; private var row: [Int: String] = [:]; private var ref = ""; private var typ = ""; private var val = ""; private var inV = false; private var maxC = 0
    init(ss: [String]) { self.ss = ss }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String:String] = [:]) {
        if e == "row" || e.hasSuffix(":row") { row = [:] }
        else if e == "c" || e.hasSuffix(":c") { ref = a["r"] ?? ""; typ = a["t"] ?? ""; val = "" }
        else if e == "v" || e.hasSuffix(":v") { inV = true; val = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inV { val += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "v" || e.hasSuffix(":v") { inV = false }
        else if e == "c" || e.hasSuffix(":c") {
            let c = colIdx(ref); maxC = max(maxC, c)
            var v = val; if typ == "s", let i = Int(val), i < ss.count { v = ss[i] }
            row[c] = v
        }
        else if e == "row" || e.hasSuffix(":row") {
            var arr = [String](repeating: "", count: maxC + 1)
            for (c, v) in row { if c < arr.count { arr[c] = v } }
            rows.append(arr)
        }
    }
    private func colIdx(_ r: String) -> Int {
        var i = 0; for c in r { if c >= "A" && c <= "Z" { i = i * 26 + Int(c.asciiValue! - 64) } else { break } }; return i - 1
    }
}

private class CParser: NSObject, XMLParserDelegate {
    let ss: [String]; var cells: [String: String] = [:]; private var ref = ""; private var typ = ""; private var val = ""; private var inV = false
    init(ss: [String]) { self.ss = ss }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String:String] = [:]) {
        if e == "c" || e.hasSuffix(":c") { ref = a["r"] ?? ""; typ = a["t"] ?? ""; val = "" }
        else if e == "v" || e.hasSuffix(":v") { inV = true; val = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inV { val += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "v" || e.hasSuffix(":v") { inV = false }
        else if e == "c" || e.hasSuffix(":c") {
            var v = val; if typ == "s", let i = Int(val), i < ss.count { v = ss[i] }
            if !ref.isEmpty { cells[ref] = v }
        }
    }
}

// MARK: - Minimal ZIP Reader
private class MiniZIP {
    private let fh: FileHandle; private(set) var entries: [String] = []; private var cd: [String: (off: UInt32, cSize: UInt32, uSize: UInt32, method: UInt16)] = [:]
    init?(url: URL) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        fh = h
        do {
            let sz = try fh.seekToEnd(); try fh.seek(toOffset: 0)
            let searchSz: UInt64 = min(sz, 65557); let searchStart = sz > searchSz ? sz - searchSz : 0
            try fh.seek(toOffset: searchStart)
            guard let data = try fh.read(upToCount: Int(sz - searchStart)) else { return nil }
            var eocdOff: Int?
            for i in stride(from: data.count - 22, through: 0, by: -1) {
                if data[i] == 0x50 && data[i+1] == 0x4b && data[i+2] == 0x05 && data[i+3] == 0x06 { eocdOff = i; break }
            }
            guard let off = eocdOff else { return nil }
            let cdOff = u32(data, off + 16); let cdSz = u32(data, off + 12)
            try fh.seek(toOffset: UInt64(cdOff))
            guard let cdData = try fh.read(upToCount: Int(cdSz)) else { return nil }
            var pos = 0
            while pos < cdData.count - 46 {
                guard cdData[pos] == 0x50 && cdData[pos+1] == 0x4b && cdData[pos+2] == 0x01 && cdData[pos+3] == 0x02 else { break }
                let method = UInt16(cdData[pos+10]) | (UInt16(cdData[pos+11]) << 8)
                let cSz = u32(cdData, pos+20); let uSz = u32(cdData, pos+24)
                let fnLen = Int(UInt16(cdData[pos+28]) | (UInt16(cdData[pos+29]) << 8))
                let exLen = Int(UInt16(cdData[pos+30]) | (UInt16(cdData[pos+31]) << 8))
                let cmLen = Int(UInt16(cdData[pos+32]) | (UInt16(cdData[pos+33]) << 8))
                let lhOff = u32(cdData, pos+42)
                let fnStart = pos + 46; let fnEnd = fnStart + fnLen
                if fnEnd <= cdData.count, let fn = String(data: Data(cdData[fnStart..<fnEnd]), encoding: .utf8) {
                    entries.append(fn); cd[fn] = (lhOff, cSz, uSz, method)
                }
                pos = fnEnd + exLen + cmLen
            }
        } catch { return nil }
    }
    deinit { try? fh.close() }
    func read(_ path: String) -> Data? {
        guard let e = cd[path] else { return nil }
        do {
            try fh.seek(toOffset: UInt64(e.off))
            guard let hd = try fh.read(upToCount: 30), hd[0] == 0x50 && hd[1] == 0x4b && hd[2] == 0x03 && hd[3] == 0x04 else { return nil }
            let fnLen = Int(UInt16(hd[26]) | (UInt16(hd[27]) << 8)); let exLen = Int(UInt16(hd[28]) | (UInt16(hd[29]) << 8))
            try fh.seek(toOffset: UInt64(e.off) + 30 + UInt64(fnLen) + UInt64(exLen))
            guard let cData = try fh.read(upToCount: Int(e.cSize)) else { return nil }
            if e.method == 0 { return cData }
            if e.method == 8 { return decompress(cData, Int(e.uSize)) }
            return nil
        } catch { return nil }
    }
    private func u32(_ d: Data, _ o: Int) -> UInt32 { UInt32(d[o]) | (UInt32(d[o+1])<<8) | (UInt32(d[o+2])<<16) | (UInt32(d[o+3])<<24) }
    private func decompress(_ data: Data, _ uSize: Int) -> Data? {
        var out = Data(count: uSize)
        let r = out.withUnsafeMutableBytes { db in data.withUnsafeBytes { sb in
            compression_decode_buffer(db.bindMemory(to: UInt8.self).baseAddress!, uSize,
                                      sb.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }}
        if r > 0 { out.count = r; return out }; return nil
    }
}
