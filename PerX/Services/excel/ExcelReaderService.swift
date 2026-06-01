import Foundation

class ExcelReaderService {
    static let shared = ExcelReaderService()
    
    // MARK: - Entry Point
    
    func readExcelFile(at url: URL) async throws -> [String: Any] {
        // In sandbox (TestFlight/App Store), usa il lettore nativo
        if NativeExcelReader.isRunningInSandbox {
            print("[ExcelReaderService] 📦 Modalità sandbox rilevata, uso lettore nativo")
            let rawData = try NativeExcelReader.shared.readClaimExcelFile(at: url)
            return convertToSwiftFormat(rawData)
        }
        
        // In sviluppo, prova prima Python per retrocompatibilità
        // Se fallisce, usa il lettore nativo come fallback
        do {
            return try await readExcelFileWithPython(at: url)
        } catch {
            print("[ExcelReaderService] ⚠️ Python fallito: \(error.localizedDescription)")
            print("[ExcelReaderService] 🔄 Fallback a lettore nativo...")
            let rawData = try NativeExcelReader.shared.readClaimExcelFile(at: url)
            return convertToSwiftFormat(rawData)
        }
    }
    
    /// Converte i dati raw dal lettore nativo al formato Swift usato dal resto dell'app
    private func convertToSwiftFormat(_ result: [String: Any]) -> [String: Any] {
        var convertedResult: [String: Any] = [:]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        dateFormatter.locale = Locale(identifier: "it_IT")
        
        // Gestione stringhe base
        if let gruppo = result["gruppo"] as? String, !gruppo.isEmpty {
            convertedResult["gruppo"] = gruppo
        }
        
        if let nomeCompagnia = result["nome_compagnia"] as? String, !nomeCompagnia.isEmpty {
            convertedResult["nomeCompagnia"] = nomeCompagnia
        }
        
        if let area = result["area"] as? String, !area.isEmpty {
            convertedResult["area"] = area
        }
        
        // Gestione agenzia: usa direttamente codice_agenzia e nome_agenzia se già separati
        // Il lettore nativo (NativeExcelReader) già li separa e normalizza, quindi NON riparsare
        let codiceAgenziaRaw = result["codice_agenzia"] as? String ?? ""
        let nomeAgenziaRaw = result["nome_agenzia"] as? String ?? ""
        
        if !codiceAgenziaRaw.isEmpty {
            // Codice già presente: usa direttamente (uppercase)
            convertedResult["codiceAgenzia"] = codiceAgenziaRaw.uppercased()
        }
        
        if !nomeAgenziaRaw.isEmpty {
            // Nome già presente: usa direttamente (Title Case)
            convertedResult["agenzia"] = titleCase(nomeAgenziaRaw)
        }
        
        if let numeroSinistro = result["numero_sinistro_compagnia"] as? String, !numeroSinistro.isEmpty {
            // Numero sinistro sempre in UPPERCASE
            convertedResult["numeroSinistroCompagnia"] = numeroSinistro.uppercased()
        }
        
        if let indirizzo = result["indirizzo"] as? String, !indirizzo.isEmpty {
            convertedResult["indirizzoAssicurato"] = indirizzo
            convertedResult["indirizzoContraente"] = indirizzo
        }
        
        if let numeroPolizza = result["numero_polizza"] as? String, !numeroPolizza.isEmpty {
            convertedResult["numeroPolizza"] = numeroPolizza
        }
        
        if let tipoPolizza = result["tipo_polizza"] as? String, !tipoPolizza.isEmpty {
            convertedResult["tipoPolizza"] = tipoPolizza
        }
        
        if let nomeContraente = result["nome_contraente"] as? String, !nomeContraente.isEmpty {
            convertedResult["nomeContraente"] = nomeContraente
            convertedResult["nomeAssicurato"] = nomeContraente
        }
        
        if let telefonoAssicurato = result["telefono_assicurato"] as? String, !telefonoAssicurato.isEmpty {
            convertedResult["telefonoAssicurato"] = telefonoAssicurato
            convertedResult["telefonoContraente"] = telefonoAssicurato
        }
        
        if let telefoniAssicurato = result["telefoni_assicurato"] as? [String], !telefoniAssicurato.isEmpty {
            convertedResult["telefoniAssicuratoArray"] = telefoniAssicurato
        }
        
        if let emailAssicurato = result["email_assicurato"] as? String, !emailAssicurato.isEmpty {
            convertedResult["emailAssicurato"] = emailAssicurato
            convertedResult["emailContraente"] = emailAssicurato
        }
        
        if let emailAssicuratoArray = result["email_assicurato_array"] as? [String], !emailAssicuratoArray.isEmpty {
            convertedResult["emailAssicuratoArray"] = emailAssicuratoArray
        }
        
        if let nomeDanneggiato = result["nome_danneggiato"] as? String, !nomeDanneggiato.isEmpty {
            convertedResult["nomeDanneggiato"] = nomeDanneggiato
        }
        
        if let definizione = result["definizione"] as? String, !definizione.isEmpty {
            convertedResult["definizione"] = definizione
            convertedResult["liquidazione"] = liquidazioneFromDefinizione(definizione)
        }
        
        // Gestione date
        if let dataSinistroStr = result["data_sinistro"] as? String, !dataSinistroStr.isEmpty {
            if let dataSinistro = dateFormatter.date(from: dataSinistroStr) {
                convertedResult["dataSinistro"] = dataSinistro
            }
        }
        
        if let dataDenunciaStr = result["data_denuncia"] as? String, !dataDenunciaStr.isEmpty {
            if let dataDenuncia = dateFormatter.date(from: dataDenunciaStr) {
                convertedResult["dataDenuncia"] = dataDenuncia
            }
        }
        
        if let dataIncaricoStr = result["data_incarico"] as? String, !dataIncaricoStr.isEmpty {
            if let dataIncarico = dateFormatter.date(from: dataIncaricoStr) {
                convertedResult["dataIncarico"] = dataIncarico
            }
        }
        
        if let dataSopralluogoStr = result["data_sopralluogo"] as? String, !dataSopralluogoStr.isEmpty {
            if let dataSopralluogo = dateFormatter.date(from: dataSopralluogoStr) {
                convertedResult["dataSopralluogo"] = dataSopralluogo
            }
        }
        
        // Gestione importi
        if let importoRichiesto = result["importo_richiesto"] {
            if let strValue = importoRichiesto as? String, !strValue.isEmpty {
                convertedResult["richiesta"] = NSDecimalNumber(string: strValue.replacingOccurrences(of: ",", with: "."))
            } else if let numValue = importoRichiesto as? NSNumber {
                convertedResult["richiesta"] = NSDecimalNumber(decimal: numValue.decimalValue)
            }
        }
        
        if let stimaDanno = result["stima_danno"] {
            if let strValue = stimaDanno as? String, !strValue.isEmpty {
                convertedResult["stimaDanno"] = NSDecimalNumber(string: strValue.replacingOccurrences(of: ",", with: "."))
            } else if let numValue = stimaDanno as? NSNumber {
                convertedResult["stimaDanno"] = NSDecimalNumber(decimal: numValue.decimalValue)
            }
        }
        
        // Massimals
        if let massimals = result["massimals"] as? [Double] {
            convertedResult["massimals"] = massimals
        }
        
        return convertedResult
    }
    
    // MARK: - Python Implementation (per sviluppo)
    
    private func readExcelFileWithPython(at url: URL) async throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "ExcelReaderError",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "File Excel non trovato"]
            )
        }
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("\(UUID().uuidString)-read-excel.py")
        try pythonScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let processResult = try await PerXLocalAgent.shared.runPythonScript(
            scriptPath: scriptURL.path,
            arguments: [url.path],
            environment: [:],
            standardInput: nil,
            timeout: 30
        )
        guard processResult.exitCode == 0,
              let jsonData = processResult.output.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(
                domain: "ExcelReaderError",
                code: Int(processResult.exitCode),
                userInfo: [NSLocalizedDescriptionKey: processResult.combinedOutput]
            )
        }
        if let error = result["error"] as? String {
            throw NSError(
                domain: "ExcelReaderError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        return convertToSwiftFormat(result)
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
    
    /// Deriva liquidazione (1/0) dalla definizione: 1 se indennizzabile con liquidazione, 0 altrimenti.
    private func liquidazioneFromDefinizione(_ definizione: String) -> Int {
        let def = definizione.uppercased()
        let noLiq = [
            "CONCORDATO CON ATTO DI ACCERTAMENTO CON RISERVA",
            "NON CONCORDATO (VED. NOTE)",
            "NON CONCORDATO (NO FENOMENO ELETTRICO)",
            "NON CONCORDATO (NO RESIDUI)",
            "NON CONCORDATO (SOTTO FRANCHIGIA)",
            "NON CONCORDATO (GARANZIE NON OPERANTI)",
            "NON CONCORDATO (UBICAZIONE DEL SINISTRO NON ASSICURATA)"
        ]
        for p in noLiq { if def.contains(p) { return 0 } }
        if def.contains("DANNO INDENNIZZABILE") { return 1 }
        if def.starts(with: "CONCORDATO") { return 1 }
        return 0
    }
    
    private let pythonScript = #"""
    #!/usr/bin/env python3
    import sys
    import json
    import zipfile
    import xml.etree.ElementTree as ET
    
    def get_shared_strings(zip_ref):
        try:
            shared_strings_xml = ET.fromstring(zip_ref.read('xl/sharedStrings.xml'))
            return [s.find('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t').text 
                   for s in shared_strings_xml.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}si')]
        except:
            return []
    
    def get_cell_value(sheet_xml, cell_ref, shared_strings):
        try:
            for cell in sheet_xml.findall('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c[@r="' + cell_ref + '"]'):
                cell_type = cell.get('t')
                value_element = cell.find('.//{http://schemas.openxmlformats.org/spreadsheetml/2006/main}v')
                
                if value_element is None:
                    return ""
                    
                value = value_element.text
                
                if cell_type == 's':  # Shared string
                    return shared_strings[int(value)]
                elif cell_type == 'str':  # String
                    return value
                elif cell_type == 'b':  # Boolean
                    return 'true' if value == '1' else 'false'
                else:  # Number or other
                    return value
                    
            return ""
        except Exception as e:
            print(f"Error reading cell {cell_ref}: {str(e)}", file=sys.stderr)
            return ""
    
    try:
        excel_path = sys.argv[1]
        
        with zipfile.ZipFile(excel_path, 'r') as zip_ref:
            # Carica le stringhe condivise
            shared_strings = get_shared_strings(zip_ref)
            
            # Leggi il contenuto del foglio di lavoro
            sheet_xml = ET.fromstring(zip_ref.read('xl/worksheets/sheet1.xml'))
            
            # Estrai i valori delle celle
            # Leggi agenzia (sarà parsata in Swift in base alla compagnia)
            agenzia_full = get_cell_value(sheet_xml, "P8", shared_strings) or ""
            # Per retrocompatibilità, manteniamo anche la logica base
            codice_agenzia = agenzia_full[:3] if len(agenzia_full) >= 3 else ""
            nome_agenzia = agenzia_full[3:].strip() if len(agenzia_full) > 3 else agenzia_full
            
            # Leggi data sopralluogo (può essere vuota o contenere testo)
            data_sopralluogo_raw = get_cell_value(sheet_xml, "S13", shared_strings) or ""
            data_sopralluogo = None
            if data_sopralluogo_raw and data_sopralluogo_raw.strip():
                # Prova a parsare come data, se fallisce è testo e quindi None
                try:
                    # Prova formati comuni di data
                    from datetime import datetime
                    for fmt in ["%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d"]:
                        try:
                            data_sopralluogo = datetime.strptime(data_sopralluogo_raw.strip(), fmt).strftime("%d/%m/%Y")
                            break
                        except:
                            continue
                except:
                    pass
            
            # Normalizza nome contraente/assicurato (solo iniziali maiuscole)
            nome_contraente_raw = get_cell_value(sheet_xml, "D20", shared_strings) or ""
            nome_contraente = " ".join([word.capitalize() for word in nome_contraente_raw.split()]) if nome_contraente_raw else ""
            
            # Estrai telefoni ed email da L20
            import re
            contatti_raw = get_cell_value(sheet_xml, "L20", shared_strings) or ""
            
            # Estrai tutti i numeri di telefono (sequenze di 6-15 cifre, possibilmente con spazi/trattini)
            telefoni = []
            # Pattern per numeri: sequenze di 6-15 cifre, possibilmente con spazi, trattini, punti
            phone_pattern = r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,9}\b'
            phone_matches = re.findall(phone_pattern, contatti_raw)
            # Pulisci i numeri (rimuovi spazi, trattini, punti) e filtra quelli con almeno 6 cifre
            for match in phone_matches:
                cleaned = re.sub(r'[-.\s()]', '', match)
                if len(cleaned) >= 6 and len(cleaned) <= 15:
                    telefoni.append(cleaned)
            
            # Estrai tutte le email (pattern standard email)
            email_pattern = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
            email_matches = re.findall(email_pattern, contatti_raw)
            
            # Mantieni il primo telefono e la prima email per retrocompatibilità
            telefono_assicurato = telefoni[0] if telefoni else ""
            email_assicurato = email_matches[0] if email_matches else ""
            
            data = {
                "gruppo": get_cell_value(sheet_xml, "H5", shared_strings),
                "nome_compagnia": get_cell_value(sheet_xml, "P5", shared_strings),
                "area": get_cell_value(sheet_xml, "H8", shared_strings),
                "codice_agenzia": codice_agenzia,
                "nome_agenzia": nome_agenzia,
                "numero_sinistro_compagnia": get_cell_value(sheet_xml, "E10", shared_strings),
                "data_sinistro": get_cell_value(sheet_xml, "H13", shared_strings),
                "data_denuncia": get_cell_value(sheet_xml, "K13", shared_strings),
                "data_incarico": get_cell_value(sheet_xml, "P13", shared_strings),
                "data_sopralluogo": data_sopralluogo,
                "indirizzo": get_cell_value(sheet_xml, "E14", shared_strings),
                "numero_polizza": get_cell_value(sheet_xml, "E16", shared_strings),
                "tipo_polizza": get_cell_value(sheet_xml, "P16", shared_strings),
                "nome_contraente": nome_contraente,
                "telefono_assicurato": telefono_assicurato,
                "telefoni_assicurato": telefoni,
                "email_assicurato": email_assicurato,
                "email_assicurato_array": email_matches,
                "nome_danneggiato": get_cell_value(sheet_xml, "A24", shared_strings),
                "importo_richiesto": get_cell_value(sheet_xml, "I24", shared_strings) or "0",
                "definizione": get_cell_value(sheet_xml, "M24", shared_strings),
                "stima_danno": get_cell_value(sheet_xml, "S24", shared_strings) or "0",
                "iban": get_cell_value(sheet_xml, "D133", shared_strings),
                "massimals": [
                    float(get_cell_value(sheet_xml, "C34", shared_strings) or "0"),
                    float(get_cell_value(sheet_xml, "C35", shared_strings) or "0"),
                    float(get_cell_value(sheet_xml, "C36", shared_strings) or "0")
                ]
            }
            
            print(json.dumps(data))
            
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    """#
}
