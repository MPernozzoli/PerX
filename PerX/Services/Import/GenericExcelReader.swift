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
        // Trova il percorso diretto a Python (evita /usr/bin/env che usa xcrun)
        let pythonPaths = [
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
            "\(NSHomeDirectory())/.local/bin/python3"
        ]
        
        var pythonPath: String?
        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                pythonPath = path
                print("[GenericExcelReader] ✅ Python trovato: \(path)")
                break
            }
        }
        
        // Se non trovato, prova con 'which' (ma non usare /usr/bin/env)
        if pythonPath == nil {
            let whichProcess = Process()
            whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            whichProcess.arguments = ["-c", "command -v python3"]
            
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            whichProcess.standardError = Pipe()
            
            do {
                try whichProcess.run()
                whichProcess.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty,
                   FileManager.default.fileExists(atPath: output) {
                    pythonPath = output
                    print("[GenericExcelReader] ✅ Python trovato tramite PATH: \(output)")
                }
            } catch {
                print("[GenericExcelReader] ⚠️ Errore ricerca Python: \(error)")
            }
        }
        
        guard let python = pythonPath else {
            throw ImportError.invalidData("Python 3 non trovato. Verifica che sia installato.")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("generic_read_excel.py")
        try pythonScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        // Crea uno script wrapper che disabilita xcrun
        let wrapperScript = """
        #!/bin/bash
        # Wrapper per disabilitare xcrun
        export DEVELOPER_DIR=""
        export XCODE_DEVELOPER_DIR_PATH=""
        unset DEVELOPER_DIR
        unset XCODE_DEVELOPER_DIR_PATH
        exec "\(python)" "\(scriptURL.path)" "\(url.path)"
        """
        
        let wrapperURL = tempDir.appendingPathComponent("python_wrapper.sh")
        try wrapperScript.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [wrapperURL.path]
        
        // Crea un ambiente minimo senza variabili che potrebbero far usare xcrun
        var env: [String: String] = [:]
        
        // Aggiungi solo le variabili essenziali
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PYTHONIOENCODING"] = "utf-8"
        env["LANG"] = "en_US.UTF-8"
        env["HOME"] = NSHomeDirectory()
        
        // Disabilita xcrun esplicitamente
        env["DEVELOPER_DIR"] = ""
        env["XCODE_DEVELOPER_DIR_PATH"] = ""
        
        // Aggiungi PYTHONPATH solo se esiste
        let pythonSitePackagesPaths = [
            "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/site-packages",
            "/opt/homebrew/lib/python3.11/site-packages",
            "/usr/local/lib/python3.11/site-packages"
        ]
        let existingPythonPaths = pythonSitePackagesPaths.filter { FileManager.default.fileExists(atPath: $0) }
        if !existingPythonPaths.isEmpty {
            env["PYTHONPATH"] = existingPythonPaths.joined(separator: ":")
        }
        
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        var outputData = Data()
        var errorData = Data()
        let outputQueue = DispatchQueue(label: "excel-reader-output-queue")

        // Async read handlers
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            outputQueue.async {
                outputData.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8) {
                print(str, terminator: "")
            }
            outputQueue.async {
                errorData.append(data)
            }
        }

        print("[GenericExcelReader] 📄 File Excel: \(url.lastPathComponent)")
        print("[GenericExcelReader] 📄 Path completo: \(url.path)")
        print("[GenericExcelReader] 🐍 Script Python: \(scriptURL.path)")
        print("[GenericExcelReader] 🐍 Python executable: \(python)")
        print("[GenericExcelReader] 🔧 Comando: \(python) \(scriptURL.path) \(url.path)")
        
        do {
            try process.run()
            print("[GenericExcelReader] ✅ Processo Python avviato con successo. PID: \(process.processIdentifier)")
        } catch {
            print("[GenericExcelReader] ❌ Errore avvio processo Python: \(error.localizedDescription)")
            
            // Se l'errore indica Python mancante, avvia installazione
            if error.localizedDescription.contains("python3") || error.localizedDescription.contains("Python") || error.localizedDescription.contains("command not found") {
                Task {
                    await DependencyManager.shared.handleServiceError(error, for: .python)
                }
            }
            
            throw ImportError.invalidData("Impossibile avviare lo script Python: \(error.localizedDescription)")
        }

        // Timeout di sicurezza
        let task = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 secondi
            if process.isRunning {
                print("[ExcelReader] TIMEOUT: Il processo sta impiegando troppo tempo, terminazione forzata.")
                process.terminate()
            }
        }
        
        process.waitUntilExit()
        task.cancel() // Annulla il task di timeout
        
        // Assicura che i readability handler vengano rimossi
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        print("[ExcelReader] Processo Python terminato con codice di uscita: \(process.terminationStatus)")

        let finalErrorOutput = await outputQueue.sync { String(data: errorData, encoding: .utf8) }
        if let error = finalErrorOutput, !error.isEmpty {
            print("[ExcelReader] Output finale di errore (stderr) dallo script:\n--- \(error) ---")
        }

        if process.terminationStatus != 0 {
            // Estrai messaggio di errore più dettagliato
            var errorMessage = "Lo script Python è fallito (codice \(process.terminationStatus))"
            
            // Prova a leggere l'errore dall'output JSON se disponibile
            let finalOutputData = await outputQueue.sync { outputData }
            if let output = String(data: finalOutputData, encoding: .utf8),
               let jsonData = output.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let jsonError = jsonObject["error"] as? String {
                errorMessage = jsonError
            } else if let stderrOutput = finalErrorOutput, !stderrOutput.isEmpty {
                // Usa stderr se disponibile
                let lines = stderrOutput.components(separatedBy: .newlines)
                    .filter { $0.contains("[PY_ERROR]") || $0.contains("Error") || $0.contains("Exception") }
                if let lastError = lines.last {
                    errorMessage = "Errore Python: \(lastError.replacingOccurrences(of: "[PY_ERROR] ", with: ""))"
                } else {
                    errorMessage = "Errore Python: \(stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            }
            
            // Se l'errore indica Python mancante, avvia installazione
            if errorMessage.contains("python3") || errorMessage.contains("Python") || errorMessage.contains("command not found") || errorMessage.contains("No such file") {
                Task {
                    await DependencyManager.shared.handleServiceError(
                        NSError(domain: "ExcelReaderError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage]),
                        for: .python
                    )
                }
            }
            
            throw ImportError.invalidData(errorMessage)
        }
        
        let finalOutputData = await outputQueue.sync { outputData }
        guard let output = String(data: finalOutputData, encoding: .utf8),
              let jsonData = output.data(using: .utf8) else {
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
            print("[ExcelReader] ERRORE: Fallita la decodifica dell'output JSON. Output grezzo: \(output)")
            throw ImportError.invalidData("Errore interno durante l'analisi dei dati del file Excel: \(error.localizedDescription)")
        }
    }

    private struct ExcelReadResult: Codable {
        let headers: [String]
        let rows: [[String]]
    }
} 