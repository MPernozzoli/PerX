import Foundation

/// Servizio per generare messaggi template predefiniti per WhatsApp
@MainActor
class WhatsAppMessageTemplateService {
    static let shared = WhatsAppMessageTemplateService()
    
    private init() {}
    
    /// Template disponibili
    enum TemplateType: String, CaseIterable, Identifiable {
        case richiestaFotografiche = "Richiesta foto"
        case invioAttoConPerizia = "Invio atto (con perizia)"
        case invioAttoSenzaPerizia = "Invio atto (senza perizia)"
        case fissaVideoperizia = "Fissa videoperizia"
        case sollecitoDocs = "Sollecito documentazione"
        case confermaRicezione = "Conferma ricezione"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .richiestaFotografiche:
                return "Richiedi foto bene e componenti"
            case .invioAttoConPerizia:
                return "Invia atto con importi valorizzati"
            case .invioAttoSenzaPerizia:
                return "Invia atto da compilare"
            case .fissaVideoperizia:
                return "Fissa appuntamento videoperizia"
            case .sollecitoDocs:
                return "Sollecita invio documentazione"
            case .confermaRicezione:
                return "Conferma ricezione documenti"
            }
        }
        
        var iconName: String {
            switch self {
            case .richiestaFotografiche: return "camera.fill"
            case .invioAttoConPerizia: return "doc.text.fill"
            case .invioAttoSenzaPerizia: return "doc.fill"
            case .fissaVideoperizia: return "video.fill"
            case .sollecitoDocs: return "exclamationmark.bubble.fill"
            case .confermaRicezione: return "checkmark.message.fill"
            }
        }
        
        var requiredTag: String? {
            switch self {
            case .invioAttoConPerizia, .invioAttoSenzaPerizia:
                return "atto_da_firmare"
            default:
                return nil
            }
        }
    }
    
    /// Genera un messaggio template sostituendo i placeholder
    func generateMessage(
        template: TemplateType,
        sinistro: Sinistro?,
        userName: String? = nil
    ) -> String {
        let riferimento = sinistro?.riferimento ?? "[riferimento]"
        let dataSinistroStr = formatDataSinistro(sinistro?.dataSinistro ?? sinistro?.dataIncarico)
        let nomeCompagnia = sinistro?.nomeCompagnia ?? "[compagnia]"
        let nomeUtente = userName ?? extractUserName() ?? "Perito"
        
        // Valori economici da Sinistro
        let dannoAccertato = formatValutaOptional(sinistro?.dannoAccertato)
        
        // Valori da Garanzia (tramite Perizia) - calcola delimitazioni e indennizzo
        let (delimitazioniInfo, indennizzoCalcolato) = getDelimitazioniEIndennizzo(sinistro)
        
        switch template {
        case .richiestaFotografiche:
            return """
Riferimento: \(riferimento)

Buongiorno, sono il perito incaricato del sinistro da fenomeno elettrico del \(dataSinistroStr), al fine di avanzare la pratica Le chiedo di mandarmi delle foto del bene danneggiato e delle componenti danneggiate (se accessibili in sicurezza) e dell'esterno dell'abitazione. Le evidenzio che non sarà possibile in nessun caso procedere con l'indennizzo in assenza delle suddette foto. Abbiamo anche necessità di avere copia dettagliata dei giustificativi per il ripristino del lamentato danno.

La ringrazio della collaborazione,
\(nomeUtente)
"""
            
        case .invioAttoConPerizia:
            var messaggio = """
Riferimento: \(riferimento)

Buongiorno, sono il perito incaricato per il sinistro da fenomeno elettrico del \(dataSinistroStr). Sulla base delle risultanze al momento disponibili, la nostra quantificazione del danno ammonta ad € \(dannoAccertato)
"""
            
            if !delimitazioniInfo.isEmpty {
                messaggio += " che, al netto delle delimitazioni di Polizza (\(delimitazioniInfo)),"
            }
            
            messaggio += """
 determina un indennizzo pari ad € \(indennizzoCalcolato) IVA esclusa.

Può accelerare il processo di liquidazione rispondendo a questo messaggio "accetto l'importo" e fornendo contestualmente l'IBAN su cui accreditare l'importo, procedendo successivamente con la firma dell'atto, anche presso la Sua agenzia di riferimento.

La ringrazio della collaborazione,
\(nomeUtente)
"""
            return messaggio
            
        case .invioAttoSenzaPerizia:
            return """
Riferimento: \(riferimento)

Buongiorno, sono il perito incaricato per il sinistro da fenomeno elettrico del \(dataSinistroStr). Le allego l'atto da restituire *compilato* e firmato.

Può accelerare il processo di liquidazione rispondendo a questo messaggio "accetto l'importo" e fornendo contestualmente l'IBAN su cui accreditare l'importo, procedendo successivamente con la firma dell'atto, anche presso la Sua agenzia di riferimento.

La ringrazio della collaborazione,
\(nomeUtente)
"""
            
        case .fissaVideoperizia:
            return """
Riferimento: \(riferimento)

Buongiorno, sono il perito incaricato da \(nomeCompagnia) per il sinistro da fenomeno elettrico del \(dataSinistroStr). Per poter procedere con la perizia vorrei fissare una videochiamata con lei dove mi può mostrare i residui. Possiamo farla nei prossimi giorni, nell'orario che le viene più comodo tra le 10:00 e le 19:00. Le servirà uno smartphone con connessione cellulare (sconsigliamo di usare la rete WiFi). Di solito dura meno di 15 minuti.

La ringrazio anticipatamente della collaborazione,
\(nomeUtente)
"""
            
        case .sollecitoDocs:
            return """
Riferimento: \(riferimento)

Buongiorno, le scrivo in relazione alla mia precedente richiesta di documentazione per il sinistro del \(dataSinistroStr). Per poter procedere con la pratica è necessario ricevere quanto richiesto.

La prego di voler provvedere al più presto.

Cordiali saluti,
\(nomeUtente)
"""
            
        case .confermaRicezione:
            return """
Riferimento: \(riferimento)

Buongiorno, confermo la ricezione della documentazione inviata. Procederò con l'analisi e le farò sapere gli sviluppi.

Cordiali saluti,
\(nomeUtente)
"""
        }
    }
    
    // MARK: - Helpers
    
    private func formatDataSinistro(_ date: Date?) -> String {
        guard let date = date else { return "[data sinistro]" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: date)
    }
    
    private func formatValutaOptional(_ value: NSDecimalNumber?) -> String {
        guard let value = value, value.doubleValue > 0 else {
            return "[importo]"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: value) ?? "[importo]"
    }
    
    private func formatValuta(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
    
    /// Estrae delimitazioni (franchigia/scoperto) dalla Garanzia Fenomeni Elettrici e calcola l'indennizzo
    private func getDelimitazioniEIndennizzo(_ sinistro: Sinistro?) -> (delimitazioni: String, indennizzo: String) {
        guard let sinistro = sinistro,
              let perizia = sinistro.perizia else {
            return ("", "[indennizzo]")
        }
        
        // Cerca la garanzia Fenomeni Elettrici
        let garanziaFE = perizia.garanzieArray.first { garanzia in
            garanzia.tipoGaranzia.lowercased().contains("fenomen") ||
            garanzia.tipoGaranzia.lowercased().contains("elettric")
        }
        
        var parts: [String] = []
        var dannoLordo = sinistro.dannoAccertato?.doubleValue ?? 0
        var indennizzoCalcolato = dannoLordo
        
        if let garanzia = garanziaFE {
            // Franchigia
            if let franchigia = garanzia.franchigiaMinimo, franchigia.doubleValue > 0 {
                parts.append("franchigia di € \(formatValuta(franchigia.doubleValue))")
                indennizzoCalcolato = max(0, indennizzoCalcolato - franchigia.doubleValue)
            }
            
            // Scoperto
            if let scoperto = garanzia.scopertoPercentuale, scoperto.doubleValue > 0 {
                parts.append("scoperto del \(scoperto.doubleValue)% relativamente alla Garanzia Fenomeni elettrici")
                let deduzionePercentuale = dannoLordo * (scoperto.doubleValue / 100.0)
                
                // Applica minimo/massimo scoperto se presenti
                var deduzioneFinal = deduzionePercentuale
                if let min = garanzia.scopertoMinimo, deduzionePercentuale < min.doubleValue {
                    deduzioneFinal = min.doubleValue
                }
                if let max = garanzia.scopertoMassimo, deduzionePercentuale > max.doubleValue {
                    deduzioneFinal = max.doubleValue
                }
                
                indennizzoCalcolato = Swift.max(0, indennizzoCalcolato - deduzioneFinal)
            }
        }
        
        // Se il sinistro ha già un valore liquidato, usalo
        if let liquidato = sinistro.liquidato, liquidato.doubleValue > 0 {
            return (parts.joined(separator: " / "), formatValuta(liquidato.doubleValue))
        }
        
        // Se abbiamo calcolato un indennizzo
        if indennizzoCalcolato > 0 {
            return (parts.joined(separator: " / "), formatValuta(indennizzoCalcolato))
        }
        
        return (parts.joined(separator: " / "), "[indennizzo]")
    }
    
    /// Estrae il nome utente dall'email o dalle impostazioni
    private func extractUserName() -> String? {
        // Prova a ottenere dall'email Google
        if let email = AppState.shared.googleAuthService.userEmail,
           let userName = email.components(separatedBy: "@").first {
            return userName.capitalized
        }
        
        // Fallback: prova dalle impostazioni
        return UserDefaults.standard.string(forKey: "userName")
    }
}

