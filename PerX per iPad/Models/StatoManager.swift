//
//  StatoManager.swift
//  PerX per iPad
//
//  Gestione stati sinistro - copia esatta del Mac
//

import SwiftUI

// MARK: - State Group

enum StateGroup: String, CaseIterable, Identifiable {
    case daScaricare = "Da scaricare"
    case inAttesa = "In attesa"
    case periziaDaEseguire = "Perizia da eseguire"
    case videoperizia = "Videoperizia"
    case inGestione = "In gestione"
    case esito = "Esito"
    case atto = "Atto"
    case controllo = "Controllo"
    case sopralluogo = "Sopralluogo"
    case chiusura = "Chiusura"
    case sistema = "Sistema"
    
    var id: String { rawValue }
    
    var shortLabel: String { rawValue }
    
    var icon: String {
        switch self {
        case .daScaricare: return "tray.and.arrow.down"
        case .inAttesa: return "hourglass.circle"
        case .periziaDaEseguire: return "doc.text.magnifyingglass"
        case .videoperizia: return "video.circle"
        case .inGestione: return "gearshape"
        case .esito: return "megaphone"
        case .atto: return "envelope.badge"
        case .controllo: return "checklist"
        case .sopralluogo: return "mappin.and.ellipse"
        case .chiusura: return "lock.circle"
        case .sistema: return "exclamationmark.triangle"
        }
    }
    
    var color: Color {
        switch self {
        case .daScaricare: return .orange
        case .inAttesa: return .yellow
        case .periziaDaEseguire: return .cyan
        case .videoperizia: return .orange.opacity(0.8)
        case .inGestione: return .blue
        case .esito: return .mint
        case .atto: return .purple
        case .controllo: return .mint.opacity(0.7)
        case .sopralluogo: return .pink
        case .chiusura: return .green
        case .sistema: return .red
        }
    }
    
    var members: [StatoSinistro] {
        StatoSinistro.allCases.filter { $0.stateGroup == self }
    }
    
    var hasVariants: Bool { members.count > 1 }
}

// MARK: - State Variant

enum StateVariant: String, CaseIterable {
    case tradizionale = "tradizionale"
    case documentale = "documentale"
    case videoperizia = "videoperizia"
    case noResidui = "no residui"
    case daAssicurato = "da assicurato"
    case daAgenzia = "da agenzia"
    
    var suffix: String {
        self == .tradizionale ? "" : " (\(rawValue))"
    }
    
    var isBase: Bool { self == .tradizionale }
}

// MARK: - Stato Sinistro

enum StatoSinistro: String, CaseIterable, Identifiable {
    // Stati di ingresso
    case daScaricare = "SV001"
    case inAttesaDocumentale = "SV002"
    case periziaDaEseguire = "SV003"
    case videoperiziaDaFissare = "SV004"
    case periziaDaEseguireNoResidui = "SV005"
    
    // Stati di avanzamento
    case periziaDaEseguireDocumentale = "SV010"
    case inGestioneDocumentale = "SV011"
    case inGestione = "SV012"
    case inGestioneVideoperizia = "SV013"
    case videoperiziaFissata = "SV014"
    case attoDaInviare = "SV020"
    case esitoDaComunicare = "SV021"
    case inAttesaDaAssicurato = "SV022"
    case inAttesaDaAgenzia = "SV023"
    case esitoComunicato = "SV030"
    case attoInviato = "SV031"
    case attoRicevutoSottoscritto = "SV032"
    case accettataVerbalmente = "SV033"
    case inControllo = "SV040"
    case controllata = "SV041"
    case richiestaAutorizzazione = "SV042"
    case supervisioneNonConcordata = "SV043"
    case sopralluogoFissato = "SV050"
    case sopralluogoRestituito = "SV051"
    
    // Stati di chiusura
    case chiusa = "SV090"
    case richiestaRevisione = "SV091"
    
    // Stati sistema
    case revocata = "SI001"
    case annullata = "SI002"
    
    var id: String { rawValue }
    
    var isSystemState: Bool {
        rawValue.starts(with: "SI")
    }
    
    var isVisible: Bool {
        rawValue.starts(with: "SV")
    }
    
    var descrizione: String {
        switch self {
        case .daScaricare: return "Da scaricare"
        case .inAttesaDocumentale: return "In attesa (documentale)"
        case .periziaDaEseguire: return "Perizia da eseguire"
        case .videoperiziaDaFissare: return "Videoperizia da fissare"
        case .periziaDaEseguireNoResidui: return "Perizia da eseguire (no residui)"
        case .periziaDaEseguireDocumentale: return "Perizia da eseguire (documentale)"
        case .inGestioneDocumentale: return "In gestione (documentale)"
        case .inGestione: return "In gestione"
        case .inGestioneVideoperizia: return "In gestione (videoperizia)"
        case .videoperiziaFissata: return "Videoperizia fissata"
        case .attoDaInviare: return "Atto da inviare"
        case .esitoDaComunicare: return "Esito da comunicare"
        case .inAttesaDaAssicurato: return "In attesa (da assicurato)"
        case .inAttesaDaAgenzia: return "In attesa (da agenzia)"
        case .esitoComunicato: return "Esito comunicato"
        case .attoInviato: return "Atto inviato"
        case .attoRicevutoSottoscritto: return "Atto ricevuto sottoscritto"
        case .accettataVerbalmente: return "Accettata verbalmente"
        case .inControllo: return "In controllo"
        case .controllata: return "Controllata"
        case .richiestaAutorizzazione: return "Richiesta autorizzazione"
        case .supervisioneNonConcordata: return "Supervisione non concordata"
        case .sopralluogoFissato: return "Sopralluogo fissato"
        case .sopralluogoRestituito: return "Sopralluogo restituito"
        case .chiusa: return "Chiusa"
        case .richiestaRevisione: return "Richiesta revisione"
        case .revocata: return "Revocata"
        case .annullata: return "Annullata"
        }
    }
    
    var icon: String {
        switch self {
        case .daScaricare: return "tray.and.arrow.down"
        case .inAttesaDocumentale: return "hourglass.circle"
        case .periziaDaEseguire: return "doc.text.magnifyingglass"
        case .videoperiziaDaFissare: return "video.badge.plus"
        case .periziaDaEseguireNoResidui: return "doc.text"
        case .periziaDaEseguireDocumentale: return "doc.text.fill"
        case .inGestioneDocumentale: return "gearshape.2"
        case .inGestione: return "gearshape"
        case .inGestioneVideoperizia: return "gearshape.2.fill"
        case .videoperiziaFissata: return "video.circle.fill"
        case .attoDaInviare: return "envelope.badge"
        case .esitoDaComunicare: return "megaphone"
        case .inAttesaDaAssicurato: return "person.crop.circle.badge.clock"
        case .inAttesaDaAgenzia: return "building.2.crop.circle"
        case .esitoComunicato: return "paperplane.circle"
        case .attoInviato: return "paperplane.circle.fill"
        case .attoRicevutoSottoscritto: return "checkmark.seal"
        case .accettataVerbalmente: return "bubble.left.and.exclamationmark.bubble.right"
        case .inControllo: return "checklist"
        case .controllata: return "checkmark.circle"
        case .richiestaAutorizzazione: return "person.badge.clock"
        case .supervisioneNonConcordata: return "exclamationmark.triangle"
        case .sopralluogoFissato: return "mappin.and.ellipse"
        case .sopralluogoRestituito: return "mappin.circle.fill"
        case .chiusa: return "lock.circle"
        case .richiestaRevisione: return "arrow.counterclockwise.circle"
        case .revocata: return "xmark.circle"
        case .annullata: return "trash.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .daScaricare: return .orange
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia: return .yellow
        case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui: return .cyan
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia: return .blue
        case .videoperiziaDaFissare, .videoperiziaFissata: return .orange.opacity(0.8)
        case .sopralluogoFissato, .sopralluogoRestituito: return .pink
        case .attoDaInviare, .attoInviato, .attoRicevutoSottoscritto, .accettataVerbalmente: return .purple
        case .esitoDaComunicare, .esitoComunicato: return .mint
        case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata: return .mint.opacity(0.7)
        case .chiusa: return .green
        case .richiestaRevisione: return .red.opacity(0.8)
        case .revocata: return .red
        case .annullata: return .gray
        }
    }
    
    var stateGroup: StateGroup {
        switch self {
        case .daScaricare:
            return .daScaricare
        case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            return .inAttesa
        case .periziaDaEseguire, .periziaDaEseguireDocumentale, .periziaDaEseguireNoResidui:
            return .periziaDaEseguire
        case .videoperiziaDaFissare, .videoperiziaFissata:
            return .videoperizia
        case .inGestione, .inGestioneDocumentale, .inGestioneVideoperizia:
            return .inGestione
        case .attoDaInviare, .attoInviato, .attoRicevutoSottoscritto, .accettataVerbalmente:
            return .atto
        case .esitoDaComunicare, .esitoComunicato:
            return .esito
        case .inControllo, .controllata, .richiestaAutorizzazione, .supervisioneNonConcordata:
            return .controllo
        case .sopralluogoFissato, .sopralluogoRestituito:
            return .sopralluogo
        case .chiusa, .richiestaRevisione:
            return .chiusura
        case .revocata, .annullata:
            return .sistema
        }
    }
    
    var variant: StateVariant {
        switch self {
        case .inAttesaDocumentale, .periziaDaEseguireDocumentale, .inGestioneDocumentale:
            return .documentale
        case .inGestioneVideoperizia:
            return .videoperizia
        case .periziaDaEseguireNoResidui:
            return .noResidui
        case .inAttesaDaAssicurato:
            return .daAssicurato
        case .inAttesaDaAgenzia:
            return .daAgenzia
        default:
            return .tradizionale
        }
    }
    
    var validTransitions: [StatoSinistro] {
        switch self {
        case .daScaricare:
            return [.inAttesaDocumentale, .periziaDaEseguire, .videoperiziaDaFissare, .periziaDaEseguireNoResidui]
        case .inAttesaDocumentale:
            return [.periziaDaEseguireDocumentale, .periziaDaEseguire]
        case .periziaDaEseguire:
            return [.inGestione, .attoDaInviare, .esitoDaComunicare]
        case .videoperiziaDaFissare:
            return [.videoperiziaFissata, .inGestioneVideoperizia]
        case .periziaDaEseguireNoResidui:
            return [.inGestione, .esitoDaComunicare, .attoDaInviare]
        case .periziaDaEseguireDocumentale:
            return [.inGestioneDocumentale, .inGestione, .esitoDaComunicare]
        case .inGestioneDocumentale:
            return [.esitoDaComunicare, .attoDaInviare, .richiestaRevisione]
        case .inGestione:
            return [.attoDaInviare, .esitoDaComunicare, .richiestaRevisione]
        case .inGestioneVideoperizia:
            return [.videoperiziaFissata, .attoDaInviare, .esitoDaComunicare, .richiestaRevisione]
        case .videoperiziaFissata:
            return [.inGestioneVideoperizia, .attoDaInviare, .esitoDaComunicare]
        case .attoDaInviare:
            return [.attoInviato]
        case .esitoDaComunicare:
            return [.esitoComunicato]
        case .inAttesaDaAssicurato, .inAttesaDaAgenzia:
            return [.inGestione, .inGestioneDocumentale, .periziaDaEseguireDocumentale, .esitoDaComunicare]
        case .esitoComunicato:
            return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .attoInviato:
            return [.attoRicevutoSottoscritto, .accettataVerbalmente, .chiusa, .inGestione, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .attoRicevutoSottoscritto:
            return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .accettataVerbalmente:
            return [.chiusa, .richiestaAutorizzazione, .supervisioneNonConcordata]
        case .inControllo:
            return [.controllata]
        case .controllata:
            return [.inGestione, .periziaDaEseguire, .chiusa, .richiestaRevisione]
        case .richiestaAutorizzazione:
            return [.chiusa, .controllata, .inGestione]
        case .supervisioneNonConcordata:
            return [.chiusa, .controllata, .inGestione]
        case .sopralluogoFissato:
            return [.sopralluogoRestituito, .inGestione]
        case .sopralluogoRestituito:
            return [.inGestione, .periziaDaEseguire, .attoDaInviare, .esitoDaComunicare]
        case .chiusa:
            return [.richiestaRevisione]
        case .richiestaRevisione:
            return [.inGestione, .chiusa]
        case .revocata:
            return [.daScaricare]
        case .annullata:
            return []
        }
    }
    
    static func from(descrizione: String) -> StatoSinistro? {
        return allCases.first { $0.descrizione.lowercased() == descrizione.lowercased() }
    }
    
    static func colorFor(descrizione: String) -> Color {
        return from(descrizione: descrizione)?.color ?? .gray
    }
    
    static func iconFor(descrizione: String) -> String {
        return from(descrizione: descrizione)?.icon ?? "questionmark.circle"
    }
}

// MARK: - Priorità

enum PriorityLevel: String, CaseIterable {
    case bassa = "Bassa"
    case media = "Media"
    case alta = "Alta"
    case moltoAlta = "Molto Alta"
    case critica = "Critica"
    case auto = "Auto"
    
    var color: Color {
        switch self {
        case .bassa: return .green
        case .media: return .yellow
        case .alta: return .orange
        case .moltoAlta: return .purple
        case .critica: return .red
        case .auto: return .gray
        }
    }
    
    var value: Double? {
        switch self {
        case .bassa: return 10
        case .media: return 30
        case .alta: return 50
        case .moltoAlta: return 70
        case .critica: return 100
        case .auto: return nil
        }
    }
    
    static func from(value: Double?) -> PriorityLevel {
        guard let v = value else { return .auto }
        switch v {
        case 0..<20: return .bassa
        case 20..<40: return .media
        case 40..<60: return .alta
        case 60..<80: return .moltoAlta
        default: return .critica
        }
    }
}

// MARK: - Complessità

enum GradoComplessita: String, CaseIterable {
    case bassa = "Bassa"
    case media = "Media"
    case alta = "Alta"
    case moltaAlta = "Molto Alta"
    case unknown = "-"
    
    var color: Color {
        switch self {
        case .bassa: return .green
        case .media: return .yellow
        case .alta: return .orange
        case .moltaAlta: return .red
        case .unknown: return .gray
        }
    }
    
    static func from(text: String?) -> GradoComplessita {
        guard let t = text?.lowercased() else { return .unknown }
        switch t {
        case "bassa": return .bassa
        case "media": return .media
        case "alta": return .alta
        case "molto alta", "moltaalta": return .moltaAlta
        default: return .unknown
        }
    }
}
