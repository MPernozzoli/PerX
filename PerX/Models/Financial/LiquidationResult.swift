import Foundation

/// Risultato del calcolo di liquidazione per una garanzia
struct LiquidazioneResult {
    let garanzia: Garanzia
    
    // MARK: - Voci indennizzabili
    
    /// Dettaglio VSU per partita (indennizzabile)
    var vsuPerPartita: [UUID: Double] = [:]
    /// Dettaglio SI per partita (indennizzabile)
    var siPerPartita: [UUID: Double] = [:]
    
    /// Totale VSU (indennizzabile)
    var totaleVSU: Double = 0
    /// Totale SI (indennizzabile)
    var totaleSI: Double = 0
    /// IVA in liquidazione (solo se ripristini ultimati e riconosciIVA)
    var iva: Double = 0
    /// IVA a saldo (se ripristini non ultimati e riconosciIVA)
    var ivaASaldo: Double = 0
    /// Franchigia applicata
    var franchigia: Double = 0
    /// Scoperto applicato
    var scoperto: Double = 0
    /// Massimale della garanzia
    var massimale: Double = 0
    /// Danno indennizzabile finale
    var dannoIndennizzabile: Double = 0
    
    /// Separazione per ripristini non ultimati
    var liquidazioneVSU: Double = 0
    var liquidazioneSI: Double = 0
    
    /// Flag per indicare se l'IVA è stata riconosciuta
    var ivaRiconosciuta: Bool = true
    
    /// Flag per indicare se i ripristini sono ultimati
    var ripristiniUltimati: Bool = true
    
    /// Condizione per mostrare VSU e SI con IVA ripartita (IVA inclusa nei valori)
    /// Condizioni: riconosciIVA + ripristiniUltimati + ivaInclusa (richiesta IVA inclusa)
    var mostraValoriConIvaRipartita: Bool {
        ivaRiconosciuta && ripristiniUltimati && ivaInclusa && iva > 0
    }
    
    /// Flag per indicare se la richiesta/stima è IVA inclusa
    var ivaInclusa: Bool = true
    
    // MARK: - Voci NON indennizzabili (riserva)
    
    /// Dettaglio VSU per partita (non indennizzabile)
    var vsuNonIndennizzabilePerPartita: [UUID: Double] = [:]
    /// Dettaglio SI per partita (non indennizzabile)
    var siNonIndennizzabilePerPartita: [UUID: Double] = [:]
    
    /// Totale VSU (non indennizzabile)
    var totaleVSUNonIndennizzabile: Double = 0
    /// Totale SI (non indennizzabile)
    var totaleSINonIndennizzabile: Double = 0
    /// IVA su voci non indennizzabili
    var ivaNonIndennizzabile: Double = 0
    
    /// Danno non indennizzabile (riserva) - NO franchigia/scoperto se parziale
    var dannoNonIndennizzabile: Double = 0
    
    /// True se TUTTE le voci sono non indennizzabili (in questo caso si applica franchigia/scoperto)
    var tuttoNonIndennizzabile: Bool = false
    
    /// True se ci sono voci non indennizzabili (anche parziale)
    var haVociNonIndennizzabili: Bool {
        dannoNonIndennizzabile > 0
    }
}

/// Riepilogo liquidazione per l'intera perizia
struct RiepilogoLiquidazione {
    var risultatiPerGaranzia: [LiquidazioneResult] = []
    
    var totaleVSU: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.totaleVSU }
    }
    
    var totaleSI: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.totaleSI }
    }
    
    var totaleIVA: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.iva }
    }
    
    var totaleIVAASaldo: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.ivaASaldo }
    }
    
    var totaleFranchigia: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.franchigia }
    }
    
    var totaleScoperto: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.scoperto }
    }
    
    var dannoIndennizzabileTotale: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.dannoIndennizzabile }
    }
    
    var liquidazioneVSUTotale: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.liquidazioneVSU }
    }
    
    var liquidazioneSITotale: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.liquidazioneSI }
    }
    
    // MARK: - Non indennizzabile (riserva)
    
    var totaleVSUNonIndennizzabile: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.totaleVSUNonIndennizzabile }
    }
    
    var totaleSINonIndennizzabile: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.totaleSINonIndennizzabile }
    }
    
    var totaleIVANonIndennizzabile: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.ivaNonIndennizzabile }
    }
    
    var dannoNonIndennizzabileTotale: Double {
        risultatiPerGaranzia.reduce(0) { $0 + $1.dannoNonIndennizzabile }
    }
    
    /// True se almeno una garanzia ha voci non indennizzabili
    var haVociNonIndennizzabili: Bool {
        risultatiPerGaranzia.contains { $0.haVociNonIndennizzabili }
    }
    
    /// True se TUTTO è non indennizzabile (tutte le garanzie hanno tuttoNonIndennizzabile = true)
    var tuttoNonIndennizzabile: Bool {
        !risultatiPerGaranzia.isEmpty && risultatiPerGaranzia.allSatisfy { $0.tuttoNonIndennizzabile }
    }
}
