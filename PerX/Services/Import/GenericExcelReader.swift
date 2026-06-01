import Foundation

class GenericExcelReader {
    static let shared = GenericExcelReader()
    
    // MARK: - Entry Point
    
    func readExcelFile(at url: URL) async throws -> ImportService.ImportData {
        // In sandbox (TestFlight/App Store), usa il lettore nativo
        if NativeExcelReader.isRunningInSandbox {
            print("[GenericExcelReader] 📦 Modalità sandbox rilevata, uso lettore nativo")
            return try NativeExcelReader.shared.readExcelFile(at: url)
        }
        
        // In sviluppo, prova prima Python per retrocompatibilità
        // Se fallisce, usa il lettore nativo come fallback
        do {
            return try await readExcelFileWithPython(at: url)
        } catch {
            print("[GenericExcelReader] ⚠️ Python fallito: \(error.localizedDescription)")
            print("[GenericExcelReader] 🔄 Fallback a lettore nativo...")
            return try NativeExcelReader.shared.readExcelFile(at: url)
        }
    }
    
    // MARK: - Python Implementation (per sviluppo)
    
    private func readExcelFileWithPython(at url: URL) async throws -> ImportService.ImportData {
        // Verifica che il file esista
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.invalidData("File Excel non trovato: \(url.lastPathComponent)")
        }
        
        // Verifica che Python sia installato prima di procedere
        let pythonInstalled = await DependencyManager.shared.isDependencyInstalled(.python)
        if !pythonInstalled {
            throw ImportError.invalidData("Python non disponibile, uso lettore nativo")
        }
        
        return try await runPythonScript(for: url)
    }
    
    private let pythonScript = #"""
    #!/usr/bin/env python3
    import sys
    import json
    import zipfile
    import xml.etree.ElementTree as ET
    import re

    # --- Enhanced Logging ---
    def log_error(message):
        print(f"[PY_ERROR] {message}", file=sys.stderr)

    def log_info(message):
        print(f"[PY_INFO] {message}", file=sys.stderr)

    # Namespace for spreadsheet XML
    NS = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

    def get_col_index(cell_name):
        """'A' -> 0, 'B' -> 1, ... 'Z' -> 25, 'AA' -> 26"""
        index = 0
        for char in cell_name:
            if 'A' <= char <= 'Z':
                index = index * 26 + (ord(char) - ord('A') + 1)
        return index - 1

    def get_cell_value(cell_node, shared_strings):
        """Extracts the value from a <c> cell node."""
        value_node = cell_node.find('ns:v', NS)
        if value_node is None:
            return ""
        
        value = value_node.text
        cell_type = cell_node.get('t')

        if cell_type == 's':  # Shared String
            try:
                return shared_strings[int(value)]
            except (ValueError, IndexError):
                return "" # Invalid index
        # Note: Other types like 'b' (boolean), 'n' (number) are handled by just returning their text value
        return value or ""

    def read_excel_to_json(file_path):
        try:
            log_info(f"Starting to process file: {file_path}")
            shared_strings = []
            with zipfile.ZipFile(file_path, 'r') as z:
                log_info("Zip file opened. Reading shared strings...")
                if 'xl/sharedStrings.xml' in z.namelist():
                    with z.open('xl/sharedStrings.xml') as f:
                        tree = ET.parse(f)
                        root = tree.getroot()
                        for si in root.findall('ns:si', NS):
                            # Handle both simple text and rich text
                            text_parts = []
                            for t in si.findall('.//ns:t', NS):
                                if t.text:
                                    text_parts.append(t.text)
                            shared_strings.append("".join(text_parts))
                log_info(f"Found {len(shared_strings)} shared strings.")

                log_info("Locating first worksheet...")
                sheet_path = None
                with z.open('xl/workbook.xml') as f:
                    workbook_tree = ET.parse(f)
                    first_sheet_node = workbook_tree.find('.//ns:sheet', NS)
                    if first_sheet_node is not None:
                        rId = first_sheet_node.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
                        log_info(f"Found first sheet node with r:id='{rId}'. Looking up in rels file...")
                        with z.open('xl/_rels/workbook.xml.rels') as rels_f:
                            rels_tree = ET.parse(rels_f)
                            # Use * to find element with any tag
                            rel_node = rels_tree.find(f".//*[@Id='{rId}']")
                            if rel_node is not None:
                                sheet_path = 'xl/' + rel_node.get('Target')
                    
                if not sheet_path:
                    raise Exception("Could not dynamically find the first worksheet path.")
                
                log_info(f"Worksheet path identified: '{sheet_path}'. Reading sheet data...")

                with z.open(sheet_path) as f:
                    sheet_tree = ET.parse(f)
                    sheet_data = sheet_tree.find('ns:sheetData', NS)
                    
                    all_rows_sparse = []
                    global_max_col = -1
                    
                    if sheet_data is not None:
                        log_info("Processing rows...")
                        for i, row_node in enumerate(sheet_data.findall('ns:row', NS)):
                            row_sparse = {}
                            for cell_node in row_node.findall('ns:c', NS):
                                cell_ref = cell_node.get('r')
                                if cell_ref:
                                    col_name_match = re.match(r"([A-Z]+)", cell_ref)
                                    if col_name_match:
                                        col_name = col_name_match.group(1)
                                        col_idx = get_col_index(col_name)
                                        global_max_col = max(global_max_col, col_idx)
                                        row_sparse[col_idx] = get_cell_value(cell_node, shared_strings)
                            all_rows_sparse.append(row_sparse)
                        log_info(f"Finished parsing {len(all_rows_sparse)} rows.")
                    
                    log_info("Converting sparse data to dense table...")
                    rows_data = []
                    for row_sparse in all_rows_sparse:
                        row_list = [""] * (global_max_col + 1)
                        for col_idx, value in row_sparse.items():
                            if col_idx < len(row_list):
                                row_list[col_idx] = value
                        rows_data.append(row_list)
                        
                if not rows_data:
                    print(json.dumps({"headers": [], "rows": []}))
                    return
                        
                headers = rows_data[0]
                rows = rows_data[1:]
                
                log_info("Data processed successfully. Printing JSON output.")
                print(json.dumps({"headers": headers, "rows": rows}))

        except Exception as e:
            log_error(f"Python script failed: {str(e)}")
            # Also print to stdout for swift to catch it as an error in the JSON payload
            print(json.dumps({"error": f"Python script failed: {str(e)}"}))
            sys.exit(1)

    if __name__ == "__main__":
        if len(sys.argv) > 1:
            read_excel_to_json(sys.argv[1])

    """#
    
    private func runPythonScript(for url: URL) async throws -> ImportService.ImportData {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("\(UUID().uuidString)-generic-read-excel.py")
        try pythonScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let result = try await PerXLocalAgent.shared.runPythonScript(
            scriptPath: scriptURL.path,
            arguments: [url.path],
            environment: [:],
            standardInput: nil,
            timeout: 30
        )
        guard result.exitCode == 0 else {
            throw ImportError.invalidData(result.combinedOutput)
        }
        guard let jsonData = result.output.data(using: .utf8) else {
            throw ImportError.invalidData("Nessun dato o dato non valido ricevuto dallo script Python.")
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let error = jsonObject["error"] as? String {
            throw ImportError.invalidData("Errore dallo script Python: \(error)")
        }
        
        do {
            let result = try JSONDecoder().decode(ExcelReadResult.self, from: jsonData)
            return ImportService.ImportData(headers: result.headers, rows: result.rows, fileName: url.lastPathComponent)
        } catch {
            throw ImportError.invalidData("Errore interno durante l'analisi dei dati del file Excel: \(error.localizedDescription)")
        }
    }

    private struct ExcelReadResult: Codable {
        let headers: [String]
        let rows: [[String]]
    }
}
