//
//  RubricaModels.swift
//  PerX per iPad
//
//  Modelli per la rubrica agenzie/liquidatori sincronizzata via CloudKit
//  NOTA: Gruppi e Compagnie sono enum fissi, non editabili dalla rubrica
//

import Foundation
import SwiftUI
import CloudKit

// MARK: - Gruppi Assicurativi (fissi, non editabili)

enum GruppoAssicurativo: String, CaseIterable, Codable {
    case zurich = "Zurich Group"
    case generali = "Generali"
    case unipolSai = "UnipolSai"
    case unknown = "Altro"
    
    /// ID stringa per referenza in rubrica
    var rubricaId: String { rawValue }
    
    var compagnie: [Compagnia] {
        switch self {
        case .zurich:
            return [.zurichItalia]
        case .generali:
            return [.cattolica, .generaliItalia]
        case .unipolSai:
            return [.unipolItalia]
        case .unknown:
            return []
        }
    }
    
    var color: Color {
        switch self {
        case .zurich: return Color(red: 0.0, green: 0.47, blue: 0.78)
        case .generali: return Color(red: 0.77, green: 0.12, blue: 0.23)
        case .unipolSai: return Color(red: 0.0, green: 0.44, blue: 0.25)
        case .unknown: return .gray
        }
    }
    
    var uiIconSystemName: String {
        switch self {
        case .zurich: return "building.2.fill"
        case .generali: return "building.columns.fill"
        case .unipolSai: return "shield.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Compagnie (fisse, non editabili)

enum Compagnia: String, CaseIterable, Codable {
    case zurichItalia = "Zurich Italia"
    case cattolica = "Cattolica"
    case generaliItalia = "Generali Italia"
    case unipolItalia = "Unipol Italia"
    case unknown = "Altro"
    
    /// ID stringa per referenza in rubrica
    var rubricaId: String { rawValue }
    
    var gruppo: GruppoAssicurativo {
        switch self {
        case .zurichItalia: return .zurich
        case .cattolica, .generaliItalia: return .generali
        case .unipolItalia: return .unipolSai
        case .unknown: return .unknown
        }
    }
    
    var color: Color {
        switch self {
        case .zurichItalia: return Color(red: 0.0, green: 0.47, blue: 0.78)
        case .cattolica: return Color(red: 0.85, green: 0.55, blue: 0.0)
        case .generaliItalia: return Color(red: 0.77, green: 0.12, blue: 0.23)
        case .unipolItalia: return Color(red: 0.0, green: 0.44, blue: 0.25)
        case .unknown: return .gray
        }
    }
    
    var sigla: String {
        switch self {
        case .zurichItalia: return "ZUR"
        case .cattolica: return "CAT"
        case .generaliItalia: return "GEN"
        case .unipolItalia: return "UNI"
        case .unknown: return "XXX"
        }
    }
}

// MARK: - Agenzia

struct RubricaAgenzia: Identifiable, Codable, Hashable {
    var id: String
    var compagniaId: String
    var agenziaParentId: String? // ID agenzia madre (nil = agenzia principale)
    var codice: String
    var nome: String
    var suffissoNome: String?
    var indirizzo: String?
    var citta: String?
    var provincia: String?
    var cap: String?
    var telefoni: [String]
    var email: [String]
    var fax: String?
    var orariApertura: OrariApertura?
    var note: String?
    var idAreaLegacy: Int?
    var descrAreaLegacy: String?
    var lastModified: Date
    
    var isFiliale: Bool {
        agenziaParentId != nil && !agenziaParentId!.isEmpty
    }
    
    init(
        id: String = UUID().uuidString,
        compagniaId: String,
        agenziaParentId: String? = nil,
        codice: String,
        nome: String,
        suffissoNome: String? = nil,
        indirizzo: String? = nil,
        citta: String? = nil,
        provincia: String? = nil,
        cap: String? = nil,
        telefoni: [String] = [],
        email: [String] = [],
        fax: String? = nil,
        orariApertura: OrariApertura? = nil,
        note: String? = nil,
        idAreaLegacy: Int? = nil,
        descrAreaLegacy: String? = nil
    ) {
        self.id = id
        self.compagniaId = compagniaId
        self.agenziaParentId = agenziaParentId
        self.codice = codice
        self.nome = nome
        self.suffissoNome = suffissoNome
        self.indirizzo = indirizzo
        self.citta = citta
        self.provincia = provincia
        self.cap = cap
        self.telefoni = telefoni
        self.email = email
        self.fax = fax
        self.orariApertura = orariApertura
        self.note = note
        self.idAreaLegacy = idAreaLegacy
        self.descrAreaLegacy = descrAreaLegacy
        self.lastModified = Date()
    }
    
    var nomeCompleto: String {
        var result = ""
        if !codice.isEmpty {
            result = "\(codice) - "
        }
        result += nome
        if let suffisso = suffissoNome, !suffisso.isEmpty {
            result += " (\(suffisso))"
        }
        return result
    }
    
    var nomeConTipoSede: String {
        if isFiliale {
            return "📍 \(nomeCompleto)"
        }
        return nomeCompleto
    }
    
    var indirizzoCompleto: String {
        var parts: [String] = []
        if let indirizzo = indirizzo, !indirizzo.isEmpty {
            parts.append(indirizzo)
        }
        if let cap = cap, !cap.isEmpty {
            parts.append(cap)
        }
        if let citta = citta, !citta.isEmpty {
            parts.append(citta)
        }
        if let provincia = provincia, !provincia.isEmpty {
            parts.append("(\(provincia))")
        }
        return parts.joined(separator: " ")
    }
    
    var telefonoPrincipale: String? {
        telefoni.first
    }
    
    var emailPrincipale: String? {
        email.first
    }
    
    // MARK: - CloudKit
    
    static let recordType = "RubricaAgenzia"
    
    enum CKKeys: String {
        case id, compagniaId, agenziaParentId, codice, nome, suffissoNome
        case indirizzo, citta, provincia, cap
        case telefoni, email, fax, orariApertura, note
        case idAreaLegacy, descrAreaLegacy, lastModified
    }
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.compagniaId = record[CKKeys.compagniaId.rawValue] as? String ?? ""
        self.agenziaParentId = record[CKKeys.agenziaParentId.rawValue] as? String
        self.codice = record[CKKeys.codice.rawValue] as? String ?? ""
        self.nome = record[CKKeys.nome.rawValue] as? String ?? ""
        self.suffissoNome = record[CKKeys.suffissoNome.rawValue] as? String
        self.indirizzo = record[CKKeys.indirizzo.rawValue] as? String
        self.citta = record[CKKeys.citta.rawValue] as? String
        self.provincia = record[CKKeys.provincia.rawValue] as? String
        self.cap = record[CKKeys.cap.rawValue] as? String
        self.telefoni = record[CKKeys.telefoni.rawValue] as? [String] ?? []
        self.email = record[CKKeys.email.rawValue] as? [String] ?? []
        self.fax = record[CKKeys.fax.rawValue] as? String
        if let orariData = record[CKKeys.orariApertura.rawValue] as? Data {
            self.orariApertura = try? JSONDecoder().decode(OrariApertura.self, from: orariData)
        } else {
            self.orariApertura = nil
        }
        self.note = record[CKKeys.note.rawValue] as? String
        self.idAreaLegacy = record[CKKeys.idAreaLegacy.rawValue] as? Int
        self.descrAreaLegacy = record[CKKeys.descrAreaLegacy.rawValue] as? String
        self.lastModified = record[CKKeys.lastModified.rawValue] as? Date ?? Date()
    }
    
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[CKKeys.compagniaId.rawValue] = compagniaId
        record[CKKeys.agenziaParentId.rawValue] = agenziaParentId
        record[CKKeys.codice.rawValue] = codice
        record[CKKeys.nome.rawValue] = nome
        record[CKKeys.suffissoNome.rawValue] = suffissoNome
        record[CKKeys.indirizzo.rawValue] = indirizzo
        record[CKKeys.citta.rawValue] = citta
        record[CKKeys.provincia.rawValue] = provincia
        record[CKKeys.cap.rawValue] = cap
        record[CKKeys.telefoni.rawValue] = telefoni
        record[CKKeys.email.rawValue] = email
        record[CKKeys.fax.rawValue] = fax
        if let orari = orariApertura, let data = try? JSONEncoder().encode(orari) {
            record[CKKeys.orariApertura.rawValue] = data
        }
        record[CKKeys.note.rawValue] = note
        record[CKKeys.idAreaLegacy.rawValue] = idAreaLegacy
        record[CKKeys.descrAreaLegacy.rawValue] = descrAreaLegacy
        record[CKKeys.lastModified.rawValue] = lastModified
        return record
    }
}

// MARK: - Agente

struct RubricaAgente: Identifiable, Codable, Hashable {
    var id: String
    var agenziaId: String
    var nome: String
    var cognome: String
    var ruolo: String?
    var telefoni: [String]
    var email: [String]
    var note: String?
    var lastModified: Date
    
    init(
        id: String = UUID().uuidString,
        agenziaId: String,
        nome: String,
        cognome: String,
        ruolo: String? = nil,
        telefoni: [String] = [],
        email: [String] = [],
        note: String? = nil
    ) {
        self.id = id
        self.agenziaId = agenziaId
        self.nome = nome
        self.cognome = cognome
        self.ruolo = ruolo
        self.telefoni = telefoni
        self.email = email
        self.note = note
        self.lastModified = Date()
    }
    
    var nomeCompleto: String {
        "\(nome) \(cognome)"
    }
    
    static let recordType = "RubricaAgente"
    
    enum CKKeys: String {
        case id, agenziaId, nome, cognome, ruolo, telefoni, email, note, lastModified
    }
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.agenziaId = record[CKKeys.agenziaId.rawValue] as? String ?? ""
        self.nome = record[CKKeys.nome.rawValue] as? String ?? ""
        self.cognome = record[CKKeys.cognome.rawValue] as? String ?? ""
        self.ruolo = record[CKKeys.ruolo.rawValue] as? String
        self.telefoni = record[CKKeys.telefoni.rawValue] as? [String] ?? []
        self.email = record[CKKeys.email.rawValue] as? [String] ?? []
        self.note = record[CKKeys.note.rawValue] as? String
        self.lastModified = record[CKKeys.lastModified.rawValue] as? Date ?? Date()
    }
    
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[CKKeys.agenziaId.rawValue] = agenziaId
        record[CKKeys.nome.rawValue] = nome
        record[CKKeys.cognome.rawValue] = cognome
        record[CKKeys.ruolo.rawValue] = ruolo
        record[CKKeys.telefoni.rawValue] = telefoni
        record[CKKeys.email.rawValue] = email
        record[CKKeys.note.rawValue] = note
        record[CKKeys.lastModified.rawValue] = lastModified
        return record
    }
}

// MARK: - Liquidatore

struct RubricaLiquidatore: Identifiable, Codable, Hashable {
    var id: String
    var gruppoId: String?
    var compagniaId: String?
    var nome: String
    var cognome: String
    var telefoni: [String]
    var email: [String]
    var area: String?
    var note: String?
    var lastModified: Date
    
    init(
        id: String = UUID().uuidString,
        gruppoId: String? = nil,
        compagniaId: String? = nil,
        nome: String,
        cognome: String,
        telefoni: [String] = [],
        email: [String] = [],
        area: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.gruppoId = gruppoId
        self.compagniaId = compagniaId
        self.nome = nome
        self.cognome = cognome
        self.telefoni = telefoni
        self.email = email
        self.area = area
        self.note = note
        self.lastModified = Date()
    }
    
    var nomeCompleto: String {
        "\(nome) \(cognome)"
    }
    
    static let recordType = "RubricaLiquidatore"
    
    enum CKKeys: String {
        case id, gruppoId, compagniaId, nome, cognome, telefoni, email, area, note, lastModified
    }
    
    init(from record: CKRecord) {
        self.id = record.recordID.recordName
        self.gruppoId = record[CKKeys.gruppoId.rawValue] as? String
        self.compagniaId = record[CKKeys.compagniaId.rawValue] as? String
        self.nome = record[CKKeys.nome.rawValue] as? String ?? ""
        self.cognome = record[CKKeys.cognome.rawValue] as? String ?? ""
        self.telefoni = record[CKKeys.telefoni.rawValue] as? [String] ?? []
        self.email = record[CKKeys.email.rawValue] as? [String] ?? []
        self.area = record[CKKeys.area.rawValue] as? String
        self.note = record[CKKeys.note.rawValue] as? String
        self.lastModified = record[CKKeys.lastModified.rawValue] as? Date ?? Date()
    }
    
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[CKKeys.gruppoId.rawValue] = gruppoId
        record[CKKeys.compagniaId.rawValue] = compagniaId
        record[CKKeys.nome.rawValue] = nome
        record[CKKeys.cognome.rawValue] = cognome
        record[CKKeys.telefoni.rawValue] = telefoni
        record[CKKeys.email.rawValue] = email
        record[CKKeys.area.rawValue] = area
        record[CKKeys.note.rawValue] = note
        record[CKKeys.lastModified.rawValue] = lastModified
        return record
    }
}

// MARK: - Orari Apertura

enum StatoApertura: String {
    case aperta = "aperta"
    case chiudePresto = "chiude_presto"
    case chiusa = "chiusa"
    
    var color: Color {
        switch self {
        case .aperta: return .green
        case .chiudePresto: return .yellow
        case .chiusa: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .aperta: return "circle.fill"
        case .chiudePresto: return "clock.badge.exclamationmark.fill"
        case .chiusa: return "circle.fill"
        }
    }
}

struct FasciaOraria: Codable, Hashable, Identifiable {
    var id: UUID
    var aperturaOre: Int
    var aperturaMinuti: Int
    var chiusuraOre: Int
    var chiusuraMinuti: Int
    
    init(id: UUID = UUID(), aperturaOre: Int, aperturaMinuti: Int, chiusuraOre: Int, chiusuraMinuti: Int) {
        self.id = id
        self.aperturaOre = aperturaOre
        self.aperturaMinuti = aperturaMinuti
        self.chiusuraOre = chiusuraOre
        self.chiusuraMinuti = chiusuraMinuti
    }
    
    var aperturaString: String {
        String(format: "%02d:%02d", aperturaOre, aperturaMinuti)
    }
    
    var chiusuraString: String {
        String(format: "%02d:%02d", chiusuraOre, chiusuraMinuti)
    }
    
    var descrizione: String {
        "\(aperturaString)-\(chiusuraString)"
    }
    
    var aperturaInMinuti: Int {
        aperturaOre * 60 + aperturaMinuti
    }
    
    var chiusuraInMinuti: Int {
        chiusuraOre * 60 + chiusuraMinuti
    }
    
    func contiene(ore: Int, minuti: Int) -> Bool {
        let minutiTotali = ore * 60 + minuti
        return minutiTotali >= aperturaInMinuti && minutiTotali < chiusuraInMinuti
    }
    
    func minutiAllaChiusura(ore: Int, minuti: Int) -> Int? {
        guard contiene(ore: ore, minuti: minuti) else { return nil }
        let minutiTotali = ore * 60 + minuti
        return chiusuraInMinuti - minutiTotali
    }
}

struct OrarioGiorno: Codable, Hashable {
    var aperto: Bool
    var fasce: [FasciaOraria]
    
    init(aperto: Bool = true, fasce: [FasciaOraria] = []) {
        self.aperto = aperto
        self.fasce = fasce
    }
    
    static var defaultLavorativo: OrarioGiorno {
        OrarioGiorno(aperto: true, fasce: [
            FasciaOraria(aperturaOre: 9, aperturaMinuti: 0, chiusuraOre: 13, chiusuraMinuti: 0),
            FasciaOraria(aperturaOre: 14, aperturaMinuti: 0, chiusuraOre: 18, chiusuraMinuti: 0)
        ])
    }
    
    static var chiuso: OrarioGiorno {
        OrarioGiorno(aperto: false, fasce: [])
    }
    
    var descrizione: String {
        if !aperto { return "Chiuso" }
        if fasce.isEmpty { return "Orari non specificati" }
        return fasce.map { $0.descrizione }.joined(separator: " / ")
    }
    
    func isAperto(ore: Int, minuti: Int) -> Bool {
        guard aperto else { return false }
        return fasce.contains { $0.contiene(ore: ore, minuti: minuti) }
    }
    
    func minutiAllaChiusura(ore: Int, minuti: Int) -> Int? {
        guard aperto else { return nil }
        for fascia in fasce {
            if let minuti = fascia.minutiAllaChiusura(ore: ore, minuti: minuti) {
                return minuti
            }
        }
        return nil
    }
}

struct OrariApertura: Codable, Hashable {
    var lunedi: OrarioGiorno
    var martedi: OrarioGiorno
    var mercoledi: OrarioGiorno
    var giovedi: OrarioGiorno
    var venerdi: OrarioGiorno
    var sabato: OrarioGiorno
    var domenica: OrarioGiorno
    
    init(
        lunedi: OrarioGiorno = .defaultLavorativo,
        martedi: OrarioGiorno = .defaultLavorativo,
        mercoledi: OrarioGiorno = .defaultLavorativo,
        giovedi: OrarioGiorno = .defaultLavorativo,
        venerdi: OrarioGiorno = .defaultLavorativo,
        sabato: OrarioGiorno = .chiuso,
        domenica: OrarioGiorno = .chiuso
    ) {
        self.lunedi = lunedi
        self.martedi = martedi
        self.mercoledi = mercoledi
        self.giovedi = giovedi
        self.venerdi = venerdi
        self.sabato = sabato
        self.domenica = domenica
    }
    
    static var defaultOrari: OrariApertura {
        OrariApertura()
    }
    
    func orarioPer(weekday: Int) -> OrarioGiorno {
        switch weekday {
        case 1: return domenica
        case 2: return lunedi
        case 3: return martedi
        case 4: return mercoledi
        case 5: return giovedi
        case 6: return venerdi
        case 7: return sabato
        default: return .chiuso
        }
    }
    
    func orarioOggi() -> OrarioGiorno {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return orarioPer(weekday: weekday)
    }
    
    func statoAperturaAttuale() -> StatoApertura {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let ore = calendar.component(.hour, from: now)
        let minuti = calendar.component(.minute, from: now)
        
        let orario = orarioPer(weekday: weekday)
        
        guard orario.aperto else { return .chiusa }
        guard orario.isAperto(ore: ore, minuti: minuti) else { return .chiusa }
        
        if let minutiRimanenti = orario.minutiAllaChiusura(ore: ore, minuti: minuti),
           minutiRimanenti <= 30 {
            return .chiudePresto
        }
        
        return .aperta
    }
    
    var isApertaOra: Bool {
        statoAperturaAttuale() != .chiusa
    }
}
