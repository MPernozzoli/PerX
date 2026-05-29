//
//  RubricaModels.swift
//  PerX
//
//  Modelli per la rubrica agenzie/liquidatori sincronizzata via backend
//  NOTA: Gruppi e Compagnie sono presi da CompagniaService.swift (GruppoAssicurativo, Compagnia)
//        Non sono editabili in questa rubrica.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Gruppi e Compagnie: usare direttamente gli enum da CompagniaService
// GruppoAssicurativo e Compagnia sono definiti in CompagniaService.swift
// Non vengono creati/eliminati dalla rubrica, sono fissi.

/// Helper per ottenere l'id stringa di un gruppo (usato come chiave)
extension GruppoAssicurativo {
    /// ID stringa per referenza in rubrica
    var rubricaId: String { rawValue }
    
    /// Colore SwiftUI per UI
    var color: Color {
        Color(red: uiColor.red, green: uiColor.green, blue: uiColor.blue)
    }
}

/// Helper per ottenere l'id stringa di una compagnia (usato come chiave)
extension Compagnia {
    /// ID stringa per referenza in rubrica
    var rubricaId: String { rawValue }
    
    /// Colore SwiftUI per UI (usa override da impostazioni se presenti)
    var color: Color {
        CompagniaSettingsService.shared.effectiveUiColor(self)
    }
}

// MARK: - Agenzia

struct RubricaAgenzia: Identifiable, Codable, Hashable {
    var id: String // UUID
    var compagniaId: String
    var agenziaParentId: String? // ID agenzia madre (nil = agenzia principale)
    var codice: String // Codice principale (es. "5239")
    var codiciAlternativi: [String] // Codici legacy/altri per retrocompatibilità (monitoraggio vecchi codici)
    var nome: String // Nome agenzia (es. "Milano Argentina")
    var suffissoNome: String? // Suffisso opzionale (es. "Sede Centrale", "Filiale Nord")
    var indirizzo: String?
    var citta: String?
    var provincia: String?
    var cap: String?
    var telefoni: [String] // Array di numeri telefono
    var email: [String] // Array di email
    var fax: String?
    var orariApertura: OrariApertura?
    var note: String?
    var idAreaLegacy: Int? // Per compatibilità con dati importati
    var descrAreaLegacy: String? // Per compatibilità con dati importati
    var lastModified: Date
    
    // MARK: - Flag per funzioni / comportamenti (mappabili in dettaglio sinistro)
    var problematica: Bool
    var puntigliosa: Bool
    var critica: Bool
    var comunicareSempreEsitiInAgenzia: Bool
    var attiSempreInAgenzia: Bool
    var chiamarePrimaDiInviareAtti: Bool
    var prioritaria: Bool
    
    /// true se è una filiale (ha un'agenzia madre)
    var isFiliale: Bool {
        agenziaParentId != nil && !agenziaParentId!.isEmpty
    }
    
    /// Tutti i codici (principale + alternativi) normalizzati uppercase, senza duplicati né vuoti
    var tuttiICodici: [String] {
        let main = codice.trimmingCharacters(in: .whitespaces).uppercased()
        let alt = codiciAlternativi
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        if !main.isEmpty { seen.insert(main) }
        return [main].filter { !$0.isEmpty } + alt.filter { seen.insert($0).inserted }
    }
    
    /// true se il codice passato (anche alternativo) corrisponde a questa agenzia
    func matches(codice query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return false }
        return tuttiICodici.contains(q)
    }
    
    init(
        id: String = UUID().uuidString,
        compagniaId: String,
        agenziaParentId: String? = nil,
        codice: String,
        codiciAlternativi: [String] = [],
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
        descrAreaLegacy: String? = nil,
        problematica: Bool = false,
        puntigliosa: Bool = false,
        critica: Bool = false,
        comunicareSempreEsitiInAgenzia: Bool = false,
        attiSempreInAgenzia: Bool = false,
        chiamarePrimaDiInviareAtti: Bool = false,
        prioritaria: Bool = false
    ) {
        self.id = id
        self.compagniaId = compagniaId
        self.agenziaParentId = agenziaParentId
        self.codice = codice
        self.codiciAlternativi = codiciAlternativi
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
        self.problematica = problematica
        self.puntigliosa = puntigliosa
        self.critica = critica
        self.comunicareSempreEsitiInAgenzia = comunicareSempreEsitiInAgenzia
        self.attiSempreInAgenzia = attiSempreInAgenzia
        self.chiamarePrimaDiInviareAtti = chiamarePrimaDiInviareAtti
        self.prioritaria = prioritaria
    }
    
    /// Nome completo formattato
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
    
    /// Nome con indicazione filiale
    var nomeConTipoSede: String {
        if isFiliale {
            return "📍 \(nomeCompleto)"
        }
        return nomeCompleto
    }
    
    /// Indirizzo completo formattato (evita duplicazione se indirizzo contiene già CAP/città/provincia).
    var indirizzoCompleto: String {
        let base = (indirizzo ?? "").trimmingCharacters(in: .whitespaces)
        let capVal = (cap ?? "").trimmingCharacters(in: .whitespaces)
        let cittaVal = (citta ?? "").trimmingCharacters(in: .whitespaces)
        let provVal = (provincia ?? "").trimmingCharacters(in: .whitespaces)
        
        // Suffisso atteso "CAP Città (PROV)" o varianti
        let suffixParts: [String] = [capVal, cittaVal, provVal.isEmpty ? "" : "(\(provVal))"].filter { !$0.isEmpty }
        let suffix = suffixParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        
        // Se indirizzo è vuoto, usa solo cap + città + prov
        if base.isEmpty {
            return suffix
        }
        // Se il suffisso è vuoto, restituisci solo l'indirizzo
        if suffix.isEmpty {
            return base
        }
        // Evita duplicazione: se base finisce già con cap, o con "città (PROV)", non riappendere
        let baseLower = base.lowercased()
        let suffixLower = suffix.lowercased()
        if baseLower.hasSuffix(suffixLower) {
            return base
        }
        // Controllo alternativo: base contiene già il CAP (5 cifre) e la provincia (TO), (PD) ecc.
        if !capVal.isEmpty, base.contains(capVal) {
            if provVal.isEmpty || base.range(of: "\\(\(provVal)\\)", options: .regularExpression) != nil {
                return base
            }
        }
        return "\(base) \(suffix)".trimmingCharacters(in: .whitespaces)
    }
    
    /// Telefono principale
    var telefonoPrincipale: String? {
        telefoni.first
    }
    
    /// Email principale
    var emailPrincipale: String? {
        email.first
    }
    
    /// Testo formattato per copia
    var testoPerCopia: String {
        var lines: [String] = []
        lines.append(nomeCompleto)
        if !indirizzoCompleto.isEmpty {
            lines.append(indirizzoCompleto)
        }
        if let tel = telefonoPrincipale {
            lines.append("Tel: \(tel)")
        }
        if let email = emailPrincipale {
            lines.append("Email: \(email)")
        }
        if let fax = fax, !fax.isEmpty {
            lines.append("Fax: \(fax)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Codable (default per flag mancanti in cache legacy)

extension RubricaAgenzia {
    enum CodableKeys: String, CodingKey {
        case id, compagniaId, agenziaParentId, codice, codiciAlternativi, nome, suffissoNome, indirizzo, citta, provincia, cap
        case telefoni, email, fax, orariApertura, note, idAreaLegacy, descrAreaLegacy, lastModified
        case problematica, puntigliosa, critica, comunicareSempreEsitiInAgenzia, attiSempreInAgenzia, chiamarePrimaDiInviareAtti, prioritaria
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKeys.self)
        id = try c.decode(String.self, forKey: .id)
        compagniaId = try c.decode(String.self, forKey: .compagniaId)
        agenziaParentId = try c.decodeIfPresent(String.self, forKey: .agenziaParentId)
        codice = try c.decode(String.self, forKey: .codice)
        codiciAlternativi = try c.decodeIfPresent([String].self, forKey: .codiciAlternativi) ?? []
        nome = try c.decode(String.self, forKey: .nome)
        suffissoNome = try c.decodeIfPresent(String.self, forKey: .suffissoNome)
        indirizzo = try c.decodeIfPresent(String.self, forKey: .indirizzo)
        citta = try c.decodeIfPresent(String.self, forKey: .citta)
        provincia = try c.decodeIfPresent(String.self, forKey: .provincia)
        cap = try c.decodeIfPresent(String.self, forKey: .cap)
        telefoni = try c.decodeIfPresent([String].self, forKey: .telefoni) ?? []
        email = try c.decodeIfPresent([String].self, forKey: .email) ?? []
        fax = try c.decodeIfPresent(String.self, forKey: .fax)
        orariApertura = try c.decodeIfPresent(OrariApertura.self, forKey: .orariApertura)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        idAreaLegacy = try c.decodeIfPresent(Int.self, forKey: .idAreaLegacy)
        descrAreaLegacy = try c.decodeIfPresent(String.self, forKey: .descrAreaLegacy)
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        problematica = try c.decodeIfPresent(Bool.self, forKey: .problematica) ?? false
        puntigliosa = try c.decodeIfPresent(Bool.self, forKey: .puntigliosa) ?? false
        critica = try c.decodeIfPresent(Bool.self, forKey: .critica) ?? false
        comunicareSempreEsitiInAgenzia = try c.decodeIfPresent(Bool.self, forKey: .comunicareSempreEsitiInAgenzia) ?? false
        attiSempreInAgenzia = try c.decodeIfPresent(Bool.self, forKey: .attiSempreInAgenzia) ?? false
        chiamarePrimaDiInviareAtti = try c.decodeIfPresent(Bool.self, forKey: .chiamarePrimaDiInviareAtti) ?? false
        prioritaria = try c.decodeIfPresent(Bool.self, forKey: .prioritaria) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(compagniaId, forKey: .compagniaId)
        try c.encodeIfPresent(agenziaParentId, forKey: .agenziaParentId)
        try c.encode(codice, forKey: .codice)
        try c.encode(codiciAlternativi, forKey: .codiciAlternativi)
        try c.encode(nome, forKey: .nome)
        try c.encodeIfPresent(suffissoNome, forKey: .suffissoNome)
        try c.encodeIfPresent(indirizzo, forKey: .indirizzo)
        try c.encodeIfPresent(citta, forKey: .citta)
        try c.encodeIfPresent(provincia, forKey: .provincia)
        try c.encodeIfPresent(cap, forKey: .cap)
        try c.encode(telefoni, forKey: .telefoni)
        try c.encode(email, forKey: .email)
        try c.encodeIfPresent(fax, forKey: .fax)
        try c.encodeIfPresent(orariApertura, forKey: .orariApertura)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(idAreaLegacy, forKey: .idAreaLegacy)
        try c.encodeIfPresent(descrAreaLegacy, forKey: .descrAreaLegacy)
        try c.encode(lastModified, forKey: .lastModified)
        try c.encode(problematica, forKey: .problematica)
        try c.encode(puntigliosa, forKey: .puntigliosa)
        try c.encode(critica, forKey: .critica)
        try c.encode(comunicareSempreEsitiInAgenzia, forKey: .comunicareSempreEsitiInAgenzia)
        try c.encode(attiSempreInAgenzia, forKey: .attiSempreInAgenzia)
        try c.encode(chiamarePrimaDiInviareAtti, forKey: .chiamarePrimaDiInviareAtti)
        try c.encode(prioritaria, forKey: .prioritaria)
    }
}

// MARK: - Flag agenzia (label per UI)

enum RubricaAgenziaFlag: String, CaseIterable, Identifiable {
    case problematica = "Problematica"
    case puntigliosa = "Puntigliosa"
    case critica = "Critica"
    case comunicareSempreEsitiInAgenzia = "Comunicare sempre esiti in agenzia"
    case attiSempreInAgenzia = "Atti sempre in agenzia"
    case chiamarePrimaDiInviareAtti = "Chiamare prima di inviare atti"
    case prioritaria = "Prioritaria"
    
    var id: String { rawValue }
    
    func isOn(in agenzia: RubricaAgenzia) -> Bool {
        switch self {
        case .problematica: return agenzia.problematica
        case .puntigliosa: return agenzia.puntigliosa
        case .critica: return agenzia.critica
        case .comunicareSempreEsitiInAgenzia: return agenzia.comunicareSempreEsitiInAgenzia
        case .attiSempreInAgenzia: return agenzia.attiSempreInAgenzia
        case .chiamarePrimaDiInviareAtti: return agenzia.chiamarePrimaDiInviareAtti
        case .prioritaria: return agenzia.prioritaria
        }
    }
    
    var icon: String {
        switch self {
        case .problematica: return "exclamationmark.triangle.fill"
        case .puntigliosa: return "eye.fill"
        case .critica: return "exclamationmark.octagon.fill"
        case .comunicareSempreEsitiInAgenzia: return "megaphone.fill"
        case .attiSempreInAgenzia: return "doc.text.fill"
        case .chiamarePrimaDiInviareAtti: return "phone.badge.checkmark"
        case .prioritaria: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .problematica: return .orange
        case .puntigliosa: return .purple
        case .critica: return .red
        case .comunicareSempreEsitiInAgenzia: return .blue
        case .attiSempreInAgenzia: return .teal
        case .chiamarePrimaDiInviareAtti: return .green
        case .prioritaria: return .yellow
        }
    }
}

// MARK: - Agente (persona fisica in agenzia)

struct RubricaAgente: Identifiable, Codable, Hashable {
    var id: String
    var agenziaId: String
    var nome: String
    var cognome: String
    var ruolo: String? // es. "Titolare", "Collaboratore"
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
    
    var iniziali: String {
        let n = nome.first.map { String($0).uppercased() } ?? ""
        let c = cognome.first.map { String($0).uppercased() } ?? ""
        return n + c
    }
}

// MARK: - Liquidatore (futuro, sotto Gruppo)

struct RubricaLiquidatore: Identifiable, Codable, Hashable {
    var id: String
    var gruppoId: String? // Può essere associato a un gruppo
    var compagniaId: String? // O a una compagnia specifica
    var nome: String
    var cognome: String
    var telefoni: [String]
    var email: [String]
    var area: String? // Area geografica di competenza
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
    
}

// MARK: - Orari di Apertura (stile WorkSchedule)

/// Stato apertura agenzia
enum StatoApertura: String {
    case aperta = "aperta"
    case chiudePresto = "chiude_presto" // Chiude tra meno di 30 min
    case chiusa = "chiusa"
    
    var color: String {
        switch self {
        case .aperta: return "green"
        case .chiudePresto: return "yellow"
        case .chiusa: return "red"
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

/// Singola fascia oraria (es. 09:00-13:00)
struct FasciaOraria: Codable, Hashable, Identifiable {
    var id: UUID
    var aperturaOre: Int      // 0-23
    var aperturaMinuti: Int   // 0-59
    var chiusuraOre: Int      // 0-23
    var chiusuraMinuti: Int   // 0-59
    
    init(id: UUID = UUID(), aperturaOre: Int, aperturaMinuti: Int, chiusuraOre: Int, chiusuraMinuti: Int) {
        self.id = id
        self.aperturaOre = aperturaOre
        self.aperturaMinuti = aperturaMinuti
        self.chiusuraOre = chiusuraOre
        self.chiusuraMinuti = chiusuraMinuti
    }
    
    /// Inizializza da stringhe "HH:mm"
    init?(apertura: String, chiusura: String) {
        let apParts = apertura.split(separator: ":")
        let chParts = chiusura.split(separator: ":")
        guard apParts.count == 2, chParts.count == 2,
              let apOre = Int(apParts[0]), let apMin = Int(apParts[1]),
              let chOre = Int(chParts[0]), let chMin = Int(chParts[1]) else {
            return nil
        }
        self.id = UUID()
        self.aperturaOre = apOre
        self.aperturaMinuti = apMin
        self.chiusuraOre = chOre
        self.chiusuraMinuti = chMin
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
    
    /// Minuti dall'inizio della giornata per apertura
    var aperturaInMinuti: Int {
        aperturaOre * 60 + aperturaMinuti
    }
    
    /// Minuti dall'inizio della giornata per chiusura
    var chiusuraInMinuti: Int {
        chiusuraOre * 60 + chiusuraMinuti
    }
    
    /// Verifica se un orario è compreso in questa fascia
    func contiene(ore: Int, minuti: Int) -> Bool {
        let minutiTotali = ore * 60 + minuti
        return minutiTotali >= aperturaInMinuti && minutiTotali < chiusuraInMinuti
    }
    
    /// Minuti rimanenti alla chiusura (nil se fuori orario)
    func minutiAllaChiusura(ore: Int, minuti: Int) -> Int? {
        guard contiene(ore: ore, minuti: minuti) else { return nil }
        let minutiTotali = ore * 60 + minuti
        return chiusuraInMinuti - minutiTotali
    }
}

/// Orari di un giorno (più fasce orarie)
struct OrarioGiorno: Codable, Hashable {
    var aperto: Bool
    var fasce: [FasciaOraria]
    
    init(aperto: Bool = true, fasce: [FasciaOraria] = []) {
        self.aperto = aperto
        self.fasce = fasce
    }
    
    /// Default: 09:00-13:00 / 14:00-18:00
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
    
    /// Verifica se è aperto in un dato orario
    func isAperto(ore: Int, minuti: Int) -> Bool {
        guard aperto else { return false }
        return fasce.contains { $0.contiene(ore: ore, minuti: minuti) }
    }
    
    /// Minuti alla prossima chiusura (nil se chiuso)
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

/// Orari settimanali completi
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
    
    /// Orari default (Lun-Ven 09-13/14-18, Sab-Dom chiuso)
    static var defaultOrari: OrariApertura {
        OrariApertura()
    }
    
    /// Ottiene orario per giorno della settimana (1=Dom, 2=Lun, ..., 7=Sab)
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
    
    /// Ottiene orario per oggi
    func orarioOggi() -> OrarioGiorno {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return orarioPer(weekday: weekday)
    }
    
    /// Verifica stato apertura attuale
    func statoAperturaAttuale() -> StatoApertura {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let ore = calendar.component(.hour, from: now)
        let minuti = calendar.component(.minute, from: now)
        
        let orario = orarioPer(weekday: weekday)
        
        guard orario.aperto else { return .chiusa }
        guard orario.isAperto(ore: ore, minuti: minuti) else { return .chiusa }
        
        // Controlla se chiude entro 30 minuti
        if let minutiRimanenti = orario.minutiAllaChiusura(ore: ore, minuti: minuti),
           minutiRimanenti <= 30 {
            return .chiudePresto
        }
        
        return .aperta
    }
    
    /// Verifica se è aperto ora
    var isApertaOra: Bool {
        statoAperturaAttuale() != .chiusa
    }
    
    /// Descrizione compatta degli orari
    var descrizioneCompatta: String {
        let giorni: [(String, OrarioGiorno)] = [
            ("Lun", lunedi),
            ("Mar", martedi),
            ("Mer", mercoledi),
            ("Gio", giovedi),
            ("Ven", venerdi),
            ("Sab", sabato),
            ("Dom", domenica)
        ]
        
        // Raggruppa giorni con stessi orari
        var result: [String] = []
        var i = 0
        
        while i < giorni.count {
            let (nome, orario) = giorni[i]
            
            // Trova giorni consecutivi con stessi orari
            var j = i + 1
            while j < giorni.count && giorni[j].1 == orario {
                j += 1
            }
            
            let rangeEnd = j - 1
            
            if !orario.aperto {
                // Salta giorni chiusi per compattezza
                i = j
                continue
            }
            
            if rangeEnd > i {
                // Range di giorni
                result.append("\(nome)-\(giorni[rangeEnd].0): \(orario.descrizione)")
            } else {
                // Singolo giorno
                result.append("\(nome): \(orario.descrizione)")
            }
            
            i = j
        }
        
        return result.isEmpty ? "Chiuso" : result.joined(separator: " | ")
    }
    
    /// Descrizione breve per oggi
    var descrizioneOggi: String {
        let orario = orarioOggi()
        if !orario.aperto { return "Oggi chiuso" }
        return "Oggi: \(orario.descrizione)"
    }
    
    /// Calcola quando sarà la prossima apertura (se attualmente chiuso)
    func prossimaApertura() -> String? {
        let stato = statoAperturaAttuale()
        guard stato == .chiusa else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let oraAttuale = calendar.component(.hour, from: now)
        let minutiAttuali = calendar.component(.minute, from: now)
        var weekday = calendar.component(.weekday, from: now)
        
        // Controlla oggi se ci sono altre fasce
        let orarioOggi = orarioPer(weekday: weekday)
        if orarioOggi.aperto {
            for fascia in orarioOggi.fasce {
                let ore = fascia.aperturaOre
                let min = fascia.aperturaMinuti
                if ore > oraAttuale || (ore == oraAttuale && min > minutiAttuali) {
                    return "Apre alle \(fascia.aperturaString)"
                }
            }
        }
        
        // Cerca nei prossimi 7 giorni
        for offset in 1...7 {
            weekday = ((weekday - 1 + offset) % 7) + 1
            let orario = orarioPer(weekday: weekday)
            if orario.aperto, let primaFascia = orario.fasce.first {
                let nomeGiorno = nomeGiornoSettimana(weekday)
                if offset == 1 {
                    return "Apre domani alle \(primaFascia.aperturaString)"
                } else {
                    return "Apre \(nomeGiorno) alle \(primaFascia.aperturaString)"
                }
            }
        }
        
        return nil
    }
    
    private func nomeGiornoSettimana(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "domenica"
        case 2: return "lunedì"
        case 3: return "martedì"
        case 4: return "mercoledì"
        case 5: return "giovedì"
        case 6: return "venerdì"
        case 7: return "sabato"
        default: return ""
        }
    }
}
