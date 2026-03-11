import Foundation
import Vapor
import PerXCore

// MARK: - JFish Sync Service
// Servizio per sincronizzare dati tra JFish (gestionale studio) e PerX (gestionale interno)
// Direzione: JFish → PerX (unidirezionale)

/// Actor per gestire la sincronizzazione JFish-PerX in modo thread-safe
actor JFishSyncService {
    static let shared = JFishSyncService()
    
    private init() {}
    
    // MARK: - Confronto Dati
    
    /// Confronta i dati JFish con quelli PerX e restituisce le differenze
    /// - Parameters:
    ///   - jfishData: Dati estratti da JFish
    ///   - perxData: Dati esistenti in PerX (nil se sinistro non trovato)
    /// - Returns: Lista delle differenze rilevate
    func compare(jfishData: JFishSinistroDTO, perxData: SinistroDTO?) -> JFishCompareResult {
        var differences: [JFishFieldDiff] = []
        let sinistroExists = perxData != nil
        
        // Se il sinistro non esiste in PerX, tutto è "nuovo"
        guard let perx = perxData else {
            return JFishCompareResult(
                riferimento: jfishData.riferimento,
                sinistroExists: false,
                differences: [],
                allFieldsMissing: true,
                message: "Sinistro non trovato in PerX"
            )
        }
        
        // Confronta campi disponibili in SinistroDTO
        
        // Stato - confronta usando statoId per precisione
        if let jfishStato = jfishData.stato {
            let perxStatoId = perx.statoId
            let perxStatoDesc = perx.stato
            
            // Cerca lo stato PerX corrispondente all'alias JFish
            if let mappedStatoId = getPerXStatoId(jfishStato) {
                // Confronta gli ID stato
                if mappedStatoId != perxStatoId {
                    let mappedDesc = StatoSinistro(rawValue: mappedStatoId)?.descrizione ?? jfishStato
                    differences.append(JFishFieldDiff(
                        field: "stato",
                        jfishValue: jfishStato,
                        perxValue: perxStatoDesc,
                        mappedValue: mappedDesc,
                        fieldType: .stato
                    ))
                }
            } else {
                // Alias non trovato, confronta descrizioni
                let mappedStato = mapJFishStatoToPerX(jfishStato)
                if mappedStato != perxStatoDesc {
                    differences.append(JFishFieldDiff(
                        field: "stato",
                        jfishValue: jfishStato,
                        perxValue: perxStatoDesc,
                        mappedValue: mappedStato + " (alias non trovato)",
                        fieldType: .stato
                    ))
                }
            }
        }
        
        // Data Chiusura
        compareDateField(jfishData.dataChiusura, perxDate: perx.dataChiusura, fieldName: "dataChiusura", into: &differences)
        
        // Data Evento (sinistro)
        compareDateField(jfishData.dataSinistro, perxDate: perx.dataEvento, fieldName: "dataEvento", into: &differences)
        
        // Agenzia (campo aggregato in SinistroDTO)
        if let amministratore = jfishData.amministratore, let nome = amministratore.nome, !nome.isEmpty {
            let perxAgenzia = perx.agenzia ?? ""
            if nome != perxAgenzia {
                differences.append(JFishFieldDiff(field: "agenzia", jfishValue: nome, perxValue: perxAgenzia, fieldType: .text))
            }
        }
        
        // Assicurato (campo aggregato in SinistroDTO)
        if let assicurato = jfishData.assicurato, let nome = assicurato.nome, !nome.isEmpty {
            let perxAssicurato = perx.assicurato ?? ""
            if nome != perxAssicurato {
                differences.append(JFishFieldDiff(field: "assicurato", jfishValue: nome, perxValue: perxAssicurato, fieldType: .text))
            }
        }
        
        // Polizza (campo aggregato in SinistroDTO)
        if let polizza = jfishData.polizza, let numero = polizza.numero, !numero.isEmpty {
            let perxPolizza = perx.polizza ?? ""
            if numero != perxPolizza {
                differences.append(JFishFieldDiff(field: "polizza", jfishValue: numero, perxValue: perxPolizza, fieldType: .text))
            }
        }
        
        // Definizione
        if let esito = jfishData.esitoPerizia, !esito.isEmpty {
            let perxDefinizione = perx.definizione ?? ""
            if esito != perxDefinizione {
                differences.append(JFishFieldDiff(field: "definizione", jfishValue: esito, perxValue: perxDefinizione, fieldType: .text))
            }
        }
        
        // Data Assegnazione (incarico)
        compareDateField(jfishData.dataIncarico, perxDate: perx.dataAssegnazione, fieldName: "dataAssegnazione", into: &differences)
        
        // Importo Liquidato
        if let jfishImporto = jfishData.importoLiquidato {
            let perxImporto = perx.importoLiquidato ?? 0
            if abs(jfishImporto - perxImporto) > 0.01 {
                differences.append(JFishFieldDiff(
                    field: "importoLiquidato",
                    jfishValue: String(format: "%.2f", jfishImporto),
                    perxValue: String(format: "%.2f", perxImporto),
                    fieldType: .importo
                ))
            }
        }
        
        // Complessità
        if let jfishComplessita = jfishData.complessita, !jfishComplessita.isEmpty {
            let perxComplessita = perx.complessita ?? ""
            if jfishComplessita != perxComplessita {
                differences.append(JFishFieldDiff(field: "complessita", jfishValue: jfishComplessita, perxValue: perxComplessita, fieldType: .text))
            }
        }
        
        return JFishCompareResult(
            riferimento: jfishData.riferimento,
            sinistroExists: sinistroExists,
            differences: differences,
            allFieldsMissing: false,
            message: differences.isEmpty ? "Dati sincronizzati" : "\(differences.count) differenze trovate"
        )
    }
    
    // MARK: - Aggiornamento Sinistro
    
    /// Aggiorna i campi del sinistro PerX con i valori da JFish
    /// - Parameters:
    ///   - riferimento: Riferimento del sinistro
    ///   - updates: Campi da aggiornare con i nuovi valori
    /// - Returns: Risultato dell'aggiornamento
    func updateFromJFish(riferimento: String, updates: JFishUpdateRequest) async throws -> JFishUpdateResult {
        // Verifica se il sinistro esiste
        let existingSinistro = try await CloudKitWebService.shared.fetchSinistro(riferimento: riferimento)
        let isNewSinistro = existingSinistro == nil
        
        var updatedFields: [String] = []
        var skippedFields: [String] = []
        
        // Campi supportati da SinistroUpdateRequest
        var stato: String? = nil
        var dataApertura: Date? = nil
        var dataAssegnazione: Date? = nil
        var dataChiusura: Date? = nil
        var dataSopralluogo: Date? = nil
        var dataInvioAtto: Date? = nil
        var dataComunicazioneEsito: Date? = nil
        var richiesta: Double? = nil
        var liquidato: Double? = nil
        var dannoAccertato: Double? = nil
        var riserva: Double? = nil
        var assicurato: String? = nil
        var polizza: String? = nil
        var agenzia: String? = nil
        var complessita: String? = nil
        var definizione: String? = nil
        var tipoServizio: String? = nil
        
        for update in updates.fields {
            // Mappa i campi JFish ai campi SinistroUpdateRequest
            switch update.field {
            case "stato":
                stato = mapJFishStatoToPerX(update.value)
                updatedFields.append(update.field)
            case "dataApertura", "dataEvento", "dataSinistro":
                dataApertura = parseDateString(update.value)
                updatedFields.append(update.field)
            case "dataAssegnazione", "dataIncarico":
                dataAssegnazione = parseDateString(update.value)
                updatedFields.append(update.field)
            case "dataChiusura":
                dataChiusura = parseDateString(update.value)
                updatedFields.append(update.field)
            case "dataSopralluogo":
                dataSopralluogo = parseDateString(update.value)
                updatedFields.append(update.field)
            case "dataInvioAtto":
                dataInvioAtto = parseDateString(update.value)
                updatedFields.append(update.field)
            case "dataComunicazioneEsito":
                dataComunicazioneEsito = parseDateString(update.value)
                updatedFields.append(update.field)
            case "richiesta", "richiestaDenuncia":
                richiesta = parseImporto(update.value)
                updatedFields.append(update.field)
            case "liquidato", "importoLiquidato":
                liquidato = parseImporto(update.value)
                updatedFields.append(update.field)
            case "dannoAccertato":
                dannoAccertato = parseImporto(update.value)
                updatedFields.append(update.field)
            case "riserva", "riservaDenuncia":
                riserva = parseImporto(update.value)
                updatedFields.append(update.field)
            case "assicurato", "nomeAssicurato":
                assicurato = update.value
                updatedFields.append(update.field)
            case "polizza", "numeroPolizza":
                polizza = update.value
                updatedFields.append(update.field)
            case "agenzia":
                agenzia = update.value
                updatedFields.append(update.field)
            case "complessita":
                complessita = update.value
                updatedFields.append(update.field)
            case "definizione", "esitoPerizia":
                definizione = update.value
                updatedFields.append(update.field)
            case "tipoServizio":
                tipoServizio = update.value
                updatedFields.append(update.field)
            default:
                // Campo non supportato da SinistroUpdateRequest
                skippedFields.append(update.field)
            }
        }
        
        // Logica riserva: se sinistro chiuso → riserva diventa liquidato
        // Determina lo stato finale (quello nuovo se presente, altrimenti quello esistente)
        let statoFinale = stato ?? existingSinistro?.stato ?? ""
        let isChiuso = statoFinale.lowercased().contains("chius")
        
        if let riservaValue = riserva {
            if isChiuso {
                // Sinistro chiuso: riserva → liquidato
                liquidato = riservaValue
                riserva = nil
                print("[JFishSync] Sinistro chiuso: riserva \(riservaValue) → liquidato")
            } else {
                // Sinistro aperto: riserva rimane riserva
                print("[JFishSync] Sinistro aperto: riserva \(riservaValue) rimane in riserva")
            }
        }
        
        // Salva su CloudKit
        if isNewSinistro {
            // Crea nuovo sinistro con i dati forniti
            let newSinistro = SinistroDTO(
                id: UUID().uuidString,
                riferimento: riferimento,
                stato: stato ?? "Nuovo",
                statoId: getPerXStatoId(stato ?? "Nuovo") ?? "0",
                assicurato: assicurato,
                polizza: polizza,
                agenzia: agenzia,
                dataAssegnazione: dataAssegnazione,
                dataChiusura: dataChiusura,
                ownerEmail: nil
            )
            try await CloudKitWebService.shared.saveSinistro(newSinistro, modifiedBy: "jfish-sync")
            updatedFields.append("(sinistro creato)")
            print("[JFishSync] Sinistro \(riferimento) creato su PerX")
        } else if !updatedFields.isEmpty {
            // Aggiorna sinistro esistente
            let updateRequest = SinistroUpdateRequest(
                stato: stato,
                dataApertura: dataApertura,
                dataAssegnazione: dataAssegnazione,
                dataChiusura: dataChiusura,
                dataSopralluogo: dataSopralluogo,
                dataInvioAtto: dataInvioAtto,
                dataComunicazioneEsito: dataComunicazioneEsito,
                richiesta: richiesta,
                liquidato: liquidato,
                dannoAccertato: dannoAccertato,
                riserva: riserva,
                assicurato: assicurato,
                polizza: polizza,
                agenzia: agenzia,
                complessita: complessita,
                definizione: definizione,
                tipoServizio: tipoServizio
            )
            try await CloudKitWebService.shared.updateSinistro(riferimento: riferimento, data: updateRequest)
        }
        
        let hasSkipped = !skippedFields.isEmpty
        let actionVerb = isNewSinistro ? "Creato sinistro con" : "Aggiornati"
        return JFishUpdateResult(
            success: true,
            riferimento: riferimento,
            updatedFields: updatedFields,
            failedFields: skippedFields.map { "\($0): non supportato" },
            message: hasSkipped
                ? "\(actionVerb) \(updatedFields.count) campi, \(skippedFields.count) non supportati"
                : "\(actionVerb) \(updatedFields.count) campi"
        )
    }
    
    // MARK: - Helpers
    
    private func compareDateField(_ jfishDateStr: String?, perxDate: Date?, fieldName: String, into differences: inout [JFishFieldDiff]) {
        guard let jfishStr = jfishDateStr, !jfishStr.isEmpty else { return }
        
        let perxDateStr = perxDate.map { formatDate($0) } ?? ""
        
        if jfishStr != perxDateStr {
            differences.append(JFishFieldDiff(
                field: fieldName,
                jfishValue: jfishStr,
                perxValue: perxDateStr,
                fieldType: .date
            ))
        }
    }
    
    private func parseDateString(_ dateStr: String) -> Date? {
        // Formato italiano: dd/MM/yyyy
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.date(from: dateStr)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
    
    /// Parsa un importo in formato italiano (es: "11.474,00" → 11474.0)
    private func parseImporto(_ value: String) -> Double? {
        // Rimuovi spazi e simbolo €
        var cleaned = value.trimmingCharacters(in: .whitespaces)
        cleaned = cleaned.replacingOccurrences(of: "€", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        
        // Formato italiano: 11.474,00 → rimuovi . e sostituisci , con .
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        
        return Double(cleaned)
    }
    
    /// Mappa lo stato JFish allo stato PerX usando gli alias definiti in StatoSinistro
    /// - Parameter jfishStato: Nome stato come appare su JFish
    /// - Returns: Descrizione stato PerX (es: "In gestione") se trovato, altrimenti lo stato originale
    private func mapJFishStatoToPerX(_ jfishStato: String) -> String {
        // Prova a trovare per descrizione esatta
        if let stato = StatoSinistro.fromDescrizione(jfishStato) {
            return stato.descrizione
        }
        
        // Se non trova corrispondenza, restituisce lo stato originale
        return jfishStato
    }
    
    /// Ottiene l'ID stato PerX (es: "SV012") dall'alias JFish
    /// - Parameter jfishStato: Nome stato come appare su JFish
    /// - Returns: ID stato PerX se trovato, nil altrimenti
    private func getPerXStatoId(_ jfishStato: String) -> String? {
        // Prova a trovare per descrizione esatta
        if let stato = StatoSinistro.fromDescrizione(jfishStato) {
            return stato.rawValue
        }
        
        return nil
    }
    
}

// MARK: - Errors

enum JFishSyncError: Error, LocalizedError {
    case sinistroNotFound(String)
    case unknownField(String)
    case invalidValue(String, String)
    
    var errorDescription: String? {
        switch self {
        case .sinistroNotFound(let ref):
            return "Sinistro \(ref) non trovato in PerX"
        case .unknownField(let field):
            return "Campo sconosciuto: \(field)"
        case .invalidValue(let field, let value):
            return "Valore non valido per \(field): \(value)"
        }
    }
}

// MARK: - DTOs

/// Dati sinistro estratti da JFish
struct JFishSinistroDTO: Content {
    let idInternoJFish: String?
    let riferimento: String
    let numeroSinistro: String?
    let stato: String?
    let dataSinistro: String?
    let dataDenuncia: String?
    let dataIncarico: String?
    let dataSopralluogo: String?
    let dataInvioAtto: String?
    let dataChiusura: String?
    let dataPagamentoPremio: String?
    
    let assicurato: JFishAttoreDTO?
    let contraente: JFishAttoreDTO?
    let danneggiato: JFishAttoreDTO?
    let amministratore: JFishAttoreDTO?
    let liquidatore: JFishAttoreDTO?
    
    let polizza: JFishPolizzaDTO?
    let ubicazione: JFishUbicazioneDTO?
    
    let richiestaDenuncia: Double?
    let riservaDenuncia: Double?
    let importoLiquidato: Double?
    let dannoAccertato: Double?
    let esitoPerizia: String?
    let tipoServizio: String?
    let complessita: String?
    
    let flags: JFishFlagsDTO?
}

struct JFishAttoreDTO: Content {
    let nome: String?
    let telefono: String?
    let email: String?
    let codiceFiscale: String?
}

struct JFishPolizzaDTO: Content {
    let gruppo: String?
    let compagnia: String?
    let garanzia: String?
    let numero: String?
}

struct JFishUbicazioneDTO: Content {
    let indirizzo: String?
    let citta: String?
    let cap: String?
    let provincia: String?
}

struct JFishFlagsDTO: Content {
    let riapertura: Bool?
    let triage: Bool?
    let prontaDefinizione: Bool?
    let noResidui: Bool?
    let danniIndiretti: Bool?
}

/// Risultato del confronto JFish vs PerX
struct JFishCompareResult: Content {
    let riferimento: String
    let sinistroExists: Bool
    let differences: [JFishFieldDiff]
    let allFieldsMissing: Bool
    let message: String
}

/// Singola differenza tra un campo JFish e PerX
struct JFishFieldDiff: Content {
    let field: String
    let jfishValue: String
    let perxValue: String
    let mappedValue: String?
    let fieldType: FieldType
    
    enum FieldType: String, Content {
        case text
        case date
        case importo
        case stato
        case boolean
    }
    
    init(field: String, jfishValue: String, perxValue: String, mappedValue: String? = nil, fieldType: FieldType) {
        self.field = field
        self.jfishValue = jfishValue
        self.perxValue = perxValue
        self.mappedValue = mappedValue
        self.fieldType = fieldType
    }
}

/// Richiesta di aggiornamento campi
struct JFishUpdateRequest: Content {
    let fields: [JFishFieldUpdate]
}

struct JFishFieldUpdate: Content {
    let field: String
    let value: String
}

/// Risultato dell'aggiornamento
struct JFishUpdateResult: Content {
    let success: Bool
    let riferimento: String
    let updatedFields: [String]
    let failedFields: [String]
    let message: String
}

// MARK: - Diario Sync

/// Entry del diario da JFish
struct JFishDiarioEntry: Content {
    let data: String
    let tipo: String?
    let nota: String?
    let id: String?
}

/// Risultato sync diario
struct JFishDiarioSyncResult: Content {
    let success: Bool
    let riferimento: String
    let addedEntries: Int
    let skippedEntries: Int
    let message: String
}
