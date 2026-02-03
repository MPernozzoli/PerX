import Foundation
import CoreData

extension Sinistro {
    
    /// Suggerisce e applica automaticamente informazioni al sinistro basandosi su un testo
    func applyAISuggestions(from text: String) async {
        let suggestion = await AppleIntelligenceService.shared.suggestSinistroInfo(from: text)
        
        await MainActor.run {
            // Applica solo se i campi sono vuoti (non sovrascrive dati esistenti)
            if riferimento == nil || riferimento?.isEmpty == true {
                riferimento = suggestion.riferimento
            }
            
            if nomeAssicurato == nil || nomeAssicurato?.isEmpty == true {
                nomeAssicurato = suggestion.nomeAssicurato
                nomeContraente = suggestion.nomeAssicurato
                nomeDanneggiato = suggestion.nomeAssicurato
            }
            
            if telefonoAssicurato == nil || telefonoAssicurato?.isEmpty == true {
                telefonoAssicurato = suggestion.telefono
                telefonoContraente = suggestion.telefono
                telefonoDanneggiato = suggestion.telefono
            }
            
            if emailAssicurato == nil || emailAssicurato?.isEmpty == true {
                emailAssicurato = suggestion.email
                emailContraente = suggestion.email
                emailDanneggiato = suggestion.email
            }
            
            if indirizzoAssicurato == nil || indirizzoAssicurato?.isEmpty == true {
                indirizzoAssicurato = suggestion.indirizzo
                indirizzoContraente = suggestion.indirizzo
                indirizzoDanneggiato = suggestion.indirizzo
            }
            
            if richiesta == nil {
                if let richiestaValue = suggestion.richiesta {
                    richiesta = richiestaValue as NSDecimalNumber
                }
            }
            
            if dataSinistro == nil {
                dataSinistro = suggestion.dataSinistro
            }
            
            if stato == nil || stato?.isEmpty == true {
                stato = suggestion.suggestedStatus
            }
            
            if fulminazione == nil || fulminazione?.isEmpty == true {
                fulminazione = suggestion.tipoDanno
            }
        }
    }
    
    /// Ottiene suggerimenti senza applicarli automaticamente
    func getAISuggestions(from text: String) async -> SinistroSuggestion {
        return await AppleIntelligenceService.shared.suggestSinistroInfo(from: text)
    }
    
    /// Categorizza automaticamente il sinistro basandosi sui dati esistenti
    func autoCategorize() async {
        var textToAnalyze = ""
        
        if let riferimento = riferimento {
            textToAnalyze += "\(riferimento) "
        }
        if let nome = nomeAssicurato {
            textToAnalyze += "\(nome) "
        }
        if let stato = stato {
            textToAnalyze += "\(stato) "
        }
        if let fulminazione = fulminazione {
            textToAnalyze += "\(fulminazione) "
        }
        
        let category = await AppleIntelligenceService.shared.categorizeText(textToAnalyze)
        
        await MainActor.run {
            // Puoi aggiungere un campo categoria se necessario
            // Per ora usiamo fulminazione per il tipo danno
            if fulminazione == nil || fulminazione?.isEmpty == true {
                fulminazione = category
            }
        }
    }
    
    /// Suggerisce lo stato più appropriato basandosi sui dati del sinistro
    func suggestStatus() async -> String? {
        var textToAnalyze = ""
        
        if let riferimento = riferimento {
            textToAnalyze += "\(riferimento) "
        }
        if let stato = stato {
            textToAnalyze += "\(stato) "
        }
        if let dataSinistro = dataSinistro {
            textToAnalyze += "Data sinistro: \(dataSinistro) "
        }
        if let dataSopralluogo = dataSopralluogo {
            textToAnalyze += "Sopralluogo: \(dataSopralluogo) "
        }
        
        let suggestion = await AppleIntelligenceService.shared.suggestSinistroInfo(from: textToAnalyze)
        return suggestion.suggestedStatus
    }
}

