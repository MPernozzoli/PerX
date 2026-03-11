import Foundation
import CoreData

/// Struttura per breakdown dettagliato della priorità
struct PriorityBreakdown {
    let etaComponent: Double           // Tempo trascorso (0-1.0)
    let obiettvoComponent: Double      // Boost obiettivo mensile (0-0.4)
    let accelerazioneComponent: Double // Boost accelerazione (0-0.2)
    let complessitaComponent: Double   // Priorità complessità temporale (0-0.3)
    let sollecitiRicevutiComponent: Double  // Boost solleciti ricevuti (0-1.0+)
    let sollecitiRicevutiCount: Int         // Numero solleciti ricevuti
    let tipoMittenteSollecitoMax: TipoMittenteSollecito // Tipo mittente più grave
    let sollecitiInviatiDebuff: Double      // Debuff solleciti inviati (-0.5 to 0)
    let sollecitiInviatiCount: Int          // Numero solleciti inviati
    let backlogComponent: Double       // Boost anni precedenti (0-0.8)
    let statoComponent: Double         // Impatto stato (-0.5 to +0.5)
    let agenziaPrioritariaComponent: Double // Boost agenzia prioritaria in rubrica (0 o 0.3)
    let totalCalculated: Double        // Totale calcolato
    let isManual: Bool                 // Se priorità è manuale
    let manualValue: Double?           // Valore manuale (se presente)
    
    /// True quando almeno un indicatore è 1.0 ma il risultato è compensato (es. media per altri fattori, o molto alta ma atto inviato)
    var isCompensated: Bool {
        guard !isManual else { return false }
        let total = min(1.0, totalCalculated)
        let hasMaxIndicator = etaComponent >= 0.99 || sollecitiRicevutiComponent >= 0.99
        guard hasMaxIndicator else { return false }
        let strongNegative = sollecitiInviatiDebuff < -0.2 || statoComponent < -0.2
        // Compensato verso il basso: indicatore a 1.0 ma risultato medio/basso
        let compensatedDown = total < 0.60
        // Compensato verso l'alto: risultato molto alto ma forti riduttori
        let compensatedUp = total >= 0.85 && strongNegative
        return compensatedDown || compensatedUp
    }
    
    var finalPriority: Double {
        if isManual, let manual = manualValue {
            return manual
        }
        return min(1.0, totalCalculated)
    }
    
    /// Descrizione formattata per tooltip
    var formattedDescription: String {
        var lines: [String] = []
        
        lines.append("Età sinistro: \(formatValue(etaComponent))")
        if obiettvoComponent > 0 {
            lines.append("Per obiettivo: \(formatValue(obiettvoComponent))")
        }
        if accelerazioneComponent > 0 {
            lines.append("Accelerazione: \(formatValue(accelerazioneComponent))")
        }
        if complessitaComponent > 0 {
            lines.append("Complessità: \(formatValue(complessitaComponent))")
        }
        if sollecitiRicevutiComponent > 0 {
            let mittente = tipoMittenteSollecitoMax != .unknown ? " (\(tipoMittenteSollecitoMax.descrizione))" : ""
            lines.append("Solleciti ricevuti (\(sollecitiRicevutiCount)x)\(mittente): \(formatValue(sollecitiRicevutiComponent))")
        }
        if sollecitiInviatiDebuff < 0 {
            lines.append("Solleciti inviati (\(sollecitiInviatiCount)x): \(formatValue(sollecitiInviatiDebuff))")
        }
        if backlogComponent > 0 {
            lines.append("Backlog: \(formatValue(backlogComponent))")
        }
        if statoComponent != 0 {
            let sign = statoComponent > 0 ? "+" : ""
            lines.append("Stato: \(sign)\(formatValue(statoComponent))")
        }
        if agenziaPrioritariaComponent > 0 {
            lines.append("Agenzia prioritaria: \(formatValue(agenziaPrioritariaComponent))")
        }
        
        lines.append("─────────────")
        lines.append("Totale: \(formatValue(totalCalculated))")
        
        if isManual, let manual = manualValue {
            lines.append("")
            lines.append("⚠️ Override manuale: \(formatValue(manual))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatValue(_ value: Double) -> String {
        return String(format: "%.2f", value)
    }
}

/// Calcola priorità dinamica basata su tempo, obiettivi e metriche
@MainActor
class PriorityCalculator {
    static let shared = PriorityCalculator()
    
    private let workScheduleManager = WorkScheduleManager.shared
    
    private init() {}
    
    /// Calcola priorità dinamica per un sinistro
    /// UNICA LOGICA usata in tutta l'app (task system, ordinamento sinistri, dashboard)
    /// Crescita esponenziale: lenta nei primi giorni, rapida verso deadline
    func calculateDynamicPriority(
        for sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) -> Double {
        // Se c'è override manuale, usa quello
        if let manualPriority = sinistro.value(forKey: "prioritaManuale") as? Double {
            return min(1.0, max(0.0, manualPriority))
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Calcola giorni passati per logica "grace period"
        let referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico
        let daysPassed = referenceDate.flatMap { calendar.dateComponents([.day], from: $0, to: now).day } ?? 0
        let receivedReminderCount = countReceivedReminders(in: sinistro)
        
        // 1. PRIORITÀ BASE da TEMPO TRASCORSO (0.0 - 1.0)
        let timePriority = calculateTimePriority(for: sinistro, now: now, calendar: calendar)
        
        // 2. BOOST da OBIETTIVO MENSILE (0.0 - 0.4) ponderato su efficienza (complessità/beni)
        var goalBoost = calculateGoalBoost(for: sinistro, monthlyGoal: monthlyGoal, currentClosures: currentClosures)
        
        // 3. BOOST da ACCELERAZIONE (0.0 - 0.2)
        var accelerationBoost: Double = needsAcceleration ? 0.2 : 0.0
        
        // 4. PRIORITÀ TEMPORALE da COMPLESSITÀ (Alta inizio mese, bassa fine mese)
        let complexityPriority = calculateComplexityPriority(for: sinistro, now: now, calendar: calendar)
        
        // 5. BOOST da SOLLECITI RICEVUTI (0.0 - 1.0+ con moltiplicatore)
        let receivedReminderBoost = calculateReceivedReminderBoost(sinistro: sinistro)
        
        // 6. DEBUFF da SOLLECITI INVIATI (-0.5 - 0.0, sfuma nel tempo)
        let sentReminderDebuff = calculateSentReminderDebuff(sinistro: sinistro, now: now, calendar: calendar)
        
        // 7. BOOST da ANNO DI COMPETENZA (0.0 - 0.8)
        let backlogBoost = calculateBacklogBoost(for: sinistro)
        
        // 8. IMPATTO STATO (Incrementi per stati azionabili, decrementi per stati in attesa)
        let stateImpact = calculateStateImpact(for: sinistro, now: now, calendar: calendar)
        
        // 9. BOOST AGENZIA PRIORITARIA (0.3 se in rubrica l'agenzia ha flag prioritaria)
        let agenziaPrioritariaBoost = calculateAgenziaPrioritariaBoost(for: sinistro)
        
        // GRACE PERIOD: Se nei primi 7 giorni e senza solleciti ricevuti, 
        // disattiviamo i boost di pressione (obiettivo e accelerazione)
        if daysPassed < 7 && receivedReminderCount == 0 {
            goalBoost = 0.0
            accelerationBoost = 0.0
        }
        
        // Somma totale (incluso debuff solleciti inviati e boost agenzia prioritaria)
        var totalPriority = timePriority + goalBoost + accelerationBoost + complexityPriority + receivedReminderBoost + sentReminderDebuff + backlogBoost + stateImpact + agenziaPrioritariaBoost
        
        // Cap a "Bassa" (< 0.25) se siamo nel grace period e non ci sono solleciti ricevuti
        // NOTA: il backlogBoost, complexityPriority e stateImpact possono forzare l'uscita dal grace period 
        if daysPassed < 7 && receivedReminderCount == 0 && backlogBoost == 0 && complexityPriority < 0.2 && stateImpact <= 0 {
            totalPriority = min(0.24, totalPriority)
        }
        
        // Se 3+ solleciti ricevuti: priorità assoluta (1.0)
        if receivedReminderCount >= 3 {
            return 1.0 // Priorità assoluta
        }
        
        return min(1.0, totalPriority)
    }
    
    /// Verifica se un sinistro ha urgenze reali (solleciti ricevuti)
    func isCriticallyUrgent(for sinistro: Sinistro) -> Bool {
        return countReceivedReminders(in: sinistro) > 0
    }
    
    /// Calcola la priorità raw (prima della normalizzazione a 1.0) per ordinamento secondario
    func calculateRawPriority(
        for sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) -> Double {
        // Se c'è override manuale, usa quello (già normalizzato)
        if let manualPriority = sinistro.value(forKey: "prioritaManuale") as? Double {
            return manualPriority
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        let referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico
        let daysPassed = referenceDate.flatMap { calendar.dateComponents([.day], from: $0, to: now).day } ?? 0
        let receivedReminderCount = countReceivedReminders(in: sinistro)
        
        let timePriority = calculateTimePriority(for: sinistro, now: now, calendar: calendar)
        var goalBoost = calculateGoalBoost(for: sinistro, monthlyGoal: monthlyGoal, currentClosures: currentClosures)
        var accelerationBoost: Double = needsAcceleration ? 0.2 : 0.0
        let complexityPriority = calculateComplexityPriority(for: sinistro, now: now, calendar: calendar)
        let receivedReminderBoost = calculateReceivedReminderBoost(sinistro: sinistro)
        let sentReminderDebuff = calculateSentReminderDebuff(sinistro: sinistro, now: now, calendar: calendar)
        let backlogBoost = calculateBacklogBoost(for: sinistro)
        let stateImpact = calculateStateImpact(for: sinistro, now: now, calendar: calendar)
        let agenziaPrioritariaBoost = calculateAgenziaPrioritariaBoost(for: sinistro)
        
        // Grace period
        if daysPassed < 7 && receivedReminderCount == 0 {
            goalBoost = 0.0
            accelerationBoost = 0.0
        }
        
        var totalPriority = timePriority + goalBoost + accelerationBoost + complexityPriority + receivedReminderBoost + sentReminderDebuff + backlogBoost + stateImpact + agenziaPrioritariaBoost
        
        // Cap grace period
        if daysPassed < 7 && receivedReminderCount == 0 && backlogBoost == 0 && complexityPriority < 0.2 && stateImpact <= 0 {
            totalPriority = min(0.24, totalPriority)
        }
        
        // Se 3+ solleciti ricevuti: priorità assoluta (1.0)
        if receivedReminderCount >= 3 {
            return 1.0
        }
        
        // Restituisce il valore RAW (senza cap a 1.0)
        return totalPriority
    }
    
    /// Conta i solleciti inviati per un sinistro (usa campo consolidato sul modello)
    func countSentReminders(for sinistro: Sinistro) -> Int {
        return Int(sinistro.sollecitiInviatiCount)
    }
    
    /// Data dell'ultimo sollecito inviato (per logica task) - usa campo consolidato sul modello
    func lastSentReminderDate(for sinistro: Sinistro) -> Date? {
        return sinistro.dataUltimoSollecitoInviato
    }
    
    /// Conta i solleciti ricevuti per un sinistro (usa campo consolidato sul modello)
    func countReceivedReminders(for sinistro: Sinistro) -> Int {
        return Int(sinistro.sollecitiRicevutiCount)
    }
    
    /// Calcola breakdown dettagliato con valori di default (per UI)
    func calculatePriorityBreakdown(for sinistro: Sinistro) -> PriorityBreakdown {
        let monthlyGoal = workScheduleManager.getMonthlyTarget(for: Date())
        // Per il breakdown UI, usiamo valori conservativi
        return calculatePriorityBreakdown(
            for: sinistro,
            monthlyGoal: monthlyGoal,
            currentClosures: 0,
            needsAcceleration: false
        )
    }
    
    /// Calcola breakdown dettagliato della priorità per tooltip
    func calculatePriorityBreakdown(
        for sinistro: Sinistro,
        monthlyGoal: Int,
        currentClosures: Int,
        needsAcceleration: Bool
    ) -> PriorityBreakdown {
        let calendar = Calendar.current
        let now = Date()
        
        // Calcola giorni passati per logica "grace period"
        let referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico
        let daysPassed = referenceDate.flatMap { calendar.dateComponents([.day], from: $0, to: now).day } ?? 0
        let receivedReminderCount = countReceivedReminders(in: sinistro)
        
        // 1. PRIORITÀ BASE da TEMPO TRASCORSO
        let timePriority = calculateTimePriority(for: sinistro, now: now, calendar: calendar)
        
        // 2. BOOST da OBIETTIVO MENSILE
        var goalBoost = calculateGoalBoost(for: sinistro, monthlyGoal: monthlyGoal, currentClosures: currentClosures)
        
        // 3. BOOST da ACCELERAZIONE
        var accelerationBoost: Double = needsAcceleration ? 0.2 : 0.0
        
        // 4. PRIORITÀ TEMPORALE da COMPLESSITÀ
        let complexityPriority = calculateComplexityPriority(for: sinistro, now: now, calendar: calendar)
        
        // 5. BOOST da SOLLECITI RICEVUTI
        let receivedReminderBoost = calculateReceivedReminderBoost(sinistro: sinistro)
        
        // 6. DEBUFF da SOLLECITI INVIATI
        let sentReminderDebuff = calculateSentReminderDebuff(sinistro: sinistro, now: now, calendar: calendar)
        
        // 7. BOOST da ANNO DI COMPETENZA
        let backlogBoost = calculateBacklogBoost(for: sinistro)
        
        // 8. IMPATTO STATO
        let stateImpact = calculateStateImpact(for: sinistro, now: now, calendar: calendar)
        
        // 9. BOOST AGENZIA PRIORITARIA
        let agenziaPrioritariaBoost = calculateAgenziaPrioritariaBoost(for: sinistro)
        
        // GRACE PERIOD
        if daysPassed < 7 && receivedReminderCount == 0 {
            goalBoost = 0.0
            accelerationBoost = 0.0
        }
        
        // Somma totale (incluso debuff solleciti inviati e boost agenzia prioritaria)
        var totalPriority = timePriority + goalBoost + accelerationBoost + complexityPriority + receivedReminderBoost + sentReminderDebuff + backlogBoost + stateImpact + agenziaPrioritariaBoost
        
        // Cap grace period
        if daysPassed < 7 && receivedReminderCount == 0 && backlogBoost == 0 && complexityPriority < 0.2 && stateImpact <= 0 {
            totalPriority = min(0.24, totalPriority)
        }
        
        // Se 3+ solleciti ricevuti: priorità assoluta
        if receivedReminderCount >= 3 {
            totalPriority = 1.0
        }
        
        // Controlla se c'è override manuale
        let manualValue = sinistro.value(forKey: "prioritaManuale") as? Double
        let isManual = manualValue != nil
        
        return PriorityBreakdown(
            etaComponent: timePriority,
            obiettvoComponent: goalBoost,
            accelerazioneComponent: accelerationBoost,
            complessitaComponent: complexityPriority,
            sollecitiRicevutiComponent: receivedReminderBoost,
            sollecitiRicevutiCount: receivedReminderCount,
            tipoMittenteSollecitoMax: sinistro.tipoMittenteSollecitoMaxEnum,
            sollecitiInviatiDebuff: sentReminderDebuff,
            sollecitiInviatiCount: Int(sinistro.sollecitiInviatiCount),
            backlogComponent: backlogBoost,
            statoComponent: stateImpact,
            agenziaPrioritariaComponent: agenziaPrioritariaBoost,
            totalCalculated: min(1.0, totalPriority),
            isManual: isManual,
            manualValue: manualValue
        )
    }
    
    // MARK: - Priority Components
    
    /// Calcola priorità basata su tempo trascorso (ESPONENZIALE)
    /// Target: 20 giorni da assegnazione, 30 giorni da incarico
    private func calculateTimePriority(for sinistro: Sinistro, now: Date, calendar: Calendar) -> Double {
        let referenceDate: Date?
        let targetDays: Int
        
        // Priorità 1: dataAssegnazione (target 20 giorni)
        if let assegnazione = sinistro.dataAssegnazione {
            referenceDate = assegnazione
            targetDays = 20
        }
        // Priorità 2: dataIncarico (target 30 giorni)
        else if let incarico = sinistro.dataIncarico {
            referenceDate = incarico
            targetDays = 30
        }
        else {
            return 0.1 // Baseline minima
        }
        
        guard let refDate = referenceDate else { return 0.1 }
        
        let daysPassed = calendar.dateComponents([.day], from: refDate, to: now).day ?? 0
        
        // Formula esponenziale: P = (days / target)^2
        // Giorno 1: (1/20)^2 = 0.0025
        // Giorno 5: (5/20)^2 = 0.0625
        // Giorno 10: (10/20)^2 = 0.25
        // Giorno 15: (15/20)^2 = 0.5625
        // Giorno 18: (18/20)^2 = 0.81
        // Giorno 20: (20/20)^2 = 1.0
        // Giorno 22: (22/20)^2 = 1.21 → cap a 1.0
        
        let ratio = Double(daysPassed) / Double(targetDays)
        let exponentialPriority = pow(ratio, 2.0)
        
        return min(1.0, max(0.05, exponentialPriority)) // Min 0.05, max 1.0
    }
    
    /// Calcola boost da obiettivo mensile (NORMALIZZATO)
    /// Considera quanto siamo indietro rispetto alla media giornaliera necessaria
    /// Pesa il contributo in base alla "comodità" del sinistro (semplice/pochi beni = utile per volume)
    private func calculateGoalBoost(for sinistro: Sinistro, monthlyGoal: Int, currentClosures: Int) -> Double {
        guard monthlyGoal > 0 else { return 0.0 }
        
        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now)!
        let totalDaysInMonth = range.count
        let dayOfMonth = calendar.component(.day, from: now)
        let daysRemaining = max(1, totalDaysInMonth - dayOfMonth + 1)
        
        // Target giornaliero teorico all'inizio del mese
        let theoreticalDailyRate = Double(monthlyGoal) / Double(totalDaysInMonth)
        
        // Quanti ne mancano per l'obiettivo
        let remainingToGoal = max(0, monthlyGoal - currentClosures)
        
        // Media giornaliera necessaria da oggi a fine mese
        let requiredDailyRate = Double(remainingToGoal) / Double(daysRemaining)
        
        // Se la media necessaria è superiore alla teorica, siamo indietro
        let pressureRatio = requiredDailyRate / theoreticalDailyRate
        
        // Boost base da pressione (0.0 - 0.4)
        var baseBoost = 0.0
        if pressureRatio > 1.1 { baseBoost = 0.1 }
        if pressureRatio > 1.3 { baseBoost = 0.2 }
        if pressureRatio > 1.5 { baseBoost = 0.3 }
        if pressureRatio > 2.0 { baseBoost = 0.4 }
        
        // MOLTIPLICATORE EFFICIENZA (Relevance for Goal)
        // Un sinistro semplice e con pochi beni è "oro" per l'obiettivo numerico
        let efficiencyMultiplier = calculateEfficiencyMultiplier(for: sinistro)
        
        return baseBoost * efficiencyMultiplier
    }
    
    /// Moltiplicatore basato su quanto il sinistro è utile per fare volume velocemente
    private func calculateEfficiencyMultiplier(for sinistro: Sinistro) -> Double {
        // 1. Fattore Complessità (Inversamente proporzionale)
        let complexityScore = extractComplexityScore(from: sinistro)
        let complexityFactor: Double
        if complexityScore <= 3 { complexityFactor = 1.2 }       // Molto utile
        else if complexityScore <= 6 { complexityFactor = 1.0 }  // Normale
        else { complexityFactor = 0.5 }                         // Poco utile per volume
        
        // 2. Fattore Beni (Inversamente proporzionale)
        let goodsCount = sinistro.beniPerxia.count
        let goodsFactor: Double
        if goodsCount == 0 { goodsFactor = 1.0 }               // Default
        else if goodsCount <= 2 { goodsFactor = 1.3 }          // Ottimo (veloce)
        else if goodsCount <= 5 { goodsFactor = 1.0 }          // Standard
        else { goodsFactor = 0.6 }                             // Lento
        
        return complexityFactor * goodsFactor
    }
    
    /// Calcola priorità basata su complessità con logica temporale
    /// Inizio mese: complessi hanno priorità (bisogna iniziarli)
    /// Fine mese: complessi perdono priorità (meglio chiudere i semplici)
    private func calculateComplexityPriority(for sinistro: Sinistro, now: Date, calendar: Calendar) -> Double {
        let complexityScore = extractComplexityScore(from: sinistro)
        let range = calendar.range(of: .day, in: .month, for: now)!
        let dayOfMonth = calendar.component(.day, from: now)
        let progressInMonth = Double(dayOfMonth) / Double(range.count) // 0.0 -> 1.0
        
        // Punteggio normalizzato 0.0 - 1.0
        let normalizedComplexity = Double(complexityScore) / 10.0
        
        if progressInMonth < 0.3 {
            // Inizio mese (primi 10gg): complessità aumenta priorità
            return normalizedComplexity * 0.3
        } else if progressInMonth > 0.8 {
            // Fine mese: complessità DIMINUISCE priorità relativa (focus su semplici)
            // (1.0 - normalizedComplexity) dà priorità ai semplici
            return (1.0 - normalizedComplexity) * 0.2
        } else {
            // Metà mese: boost neutro/lineare
            return normalizedComplexity * 0.15
        }
    }
    
    /// Estrae il punteggio di complessità (1-10)
    /// Se non presente, mappa i livelli testuali o usa default 5
    private func extractComplexityScore(from sinistro: Sinistro) -> Int {
        guard let complexity = sinistro.complessita else { return 5 }
        
        // Cerca pattern tipo "(8/10)" o solo "8" nel testo
        let pattern = #"(?:(\d+)/10)|(?:score:\s*(\d+))|(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: complexity, range: NSRange(complexity.startIndex..., in: complexity)) {
            
            for i in 1...3 {
                if let range = Range(match.range(at: i), in: complexity),
                   let score = Int(complexity[range]) {
                    return max(1, min(10, score))
                }
            }
        }
        
        // Fallback su livelli testuali
        let lower = complexity.lowercased()
        if lower.contains("semplice") || lower.contains("bassa") { return 3 }
        if lower.contains("complessa") || lower.contains("alta") { return 8 }
        if lower.contains("media") || lower.contains("intermedia") { return 5 }
        
        return 5
    }
    
    /// Calcola boost per sinistri di anni precedenti (Backlog)
    /// Se l'anno di competenza (primi due numeri del riferimento) è < anno corrente
    private func calculateBacklogBoost(for sinistro: Sinistro) -> Double {
        guard let riferimento = sinistro.riferimento, riferimento.count >= 2 else { return 0.0 }
        
        // Estrai l'anno dai primi due caratteri (es. "25" -> 2025)
        let yearPrefix = riferimento.prefix(2)
        guard let shortYear = Int(yearPrefix) else { return 0.0 }
        let competenceYear = 2000 + shortYear
        
        let currentYear = Calendar.current.component(.year, from: Date())
        
        if competenceYear < currentYear {
            let diff = currentYear - competenceYear
            // +0.4 per ogni anno di ritardo, max 0.8
            return min(0.8, Double(diff) * 0.4)
        }
        
        return 0.0
    }
    
    // MARK: - State Impact (Boost & Penalties)
    
    /// Calcola l'impatto dello stato sulla priorità (decrementi per attese esterne, incrementi per azioni interne)
    private func calculateStateImpact(for sinistro: Sinistro, now: Date, calendar: Calendar) -> Double {
        guard let statoDesc = sinistro.stato,
              let stato = StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == statoDesc }) else {
            return 0.0
        }
        
        // 1. STATI IMPEDENTI (Attesa terzi) -> DECREMENTO
        // Il decremento è massimo all'inizio e sfuma col tempo
        let impedingStates: Set<StatoManager.StatoSinistro> = [
            .attoInviato, .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia,
            .richiestaAutorizzazione, .supervisioneNonConcordata, .inControllo, .videoperiziaDaFissare
        ]
        
        if impedingStates.contains(stato) {
            let referenceDate: Date
            let minWaitDays: Int
            
            switch stato {
            case .attoInviato:
                referenceDate = sinistro.dataInvioAtto ?? sinistro.dataAssegnazione ?? sinistro.dataIncarico ?? now
                minWaitDays = 4 // Almeno 4 giorni lavorativi di "calma"
            case .inAttesaDocumentale, .inAttesaDaAssicurato, .inAttesaDaAgenzia:
                referenceDate = sinistro.dataAssegnazione ?? sinistro.dataIncarico ?? now
                minWaitDays = 5
            case .richiestaAutorizzazione, .supervisioneNonConcordata, .inControllo:
                referenceDate = sinistro.dataAssegnazione ?? now // Fallback finché non c'è dataInControllo
                minWaitDays = 7
            default:
                referenceDate = now
                minWaitDays = 3
            }
            
            let daysSince = calendar.dateComponents([.day], from: referenceDate, to: now).day ?? 0
            
            if daysSince < minWaitDays {
                // Decremento massimo nei primi giorni (-0.5)
                // Sfuma linearmente: a minWaitDays il decremento è 0
                let penalty = -0.5 * (Double(minWaitDays - daysSince) / Double(minWaitDays))
                return penalty
            }
            return 0.0 // Dopo i giorni minimi, la penalità sparisce
        }
        
        // 2. STATI AZIONABILI (Dipendono da noi) -> INCREMENTO
        // Proporzionale alla vicinanza alla chiusura
        let actionableStates: [StatoManager.StatoSinistro: Double] = [
            .attoRicevutoSottoscritto: 0.5,  // Massimo boost: pronto per chiusura
            .accettataVerbalmente: 0.45,
            .attoDaInviare: 0.35,
            .esitoDaComunicare: 0.3,
            .inGestione: 0.25,
            .inGestioneDocumentale: 0.2,
            .periziaDaEseguire: 0.15,
            .daScaricare: 0.1
        ]
        
        if let boost = actionableStates[stato] {
            return boost
        }
        
        return 0.0
    }
    
    // MARK: - Reminder Boost (Solleciti Ricevuti)
    
    /// Calcola boost da solleciti RICEVUTI
    /// Usa campi consolidati sul modello: count + tipo mittente massimo
    private func calculateReceivedReminderBoost(sinistro: Sinistro) -> Double {
        let count = Int(sinistro.sollecitiRicevutiCount)
        guard count > 0 else { return 0.0 }
        
        // Usa il boost priorità dal tipo mittente massimo consolidato sul modello
        let baseBoost = sinistro.boostPrioritaSolleciti
        
        // Applica MOLTIPLICATORE in base al numero di solleciti
        let multiplier: Double
        if count >= 3 {
            multiplier = 999.0 // Priorità assoluta (gestita sopra)
        } else if count == 2 {
            multiplier = 2.0 // Doppia priorità
        } else {
            multiplier = 1.0 // Priorità normale
        }
        
        return baseBoost * multiplier
    }
    
    // MARK: - Reminder Debuff (Solleciti Inviati)
    
    /// Calcola DEBUFF da solleciti INVIATI
    /// Il debuff è massimo appena inviato (-0.5) e sfuma gradualmente in 4 giorni lavorativi
    /// Usa campo consolidato dataUltimoSollecitoInviato dal modello
    private func calculateSentReminderDebuff(sinistro: Sinistro, now: Date, calendar: Calendar) -> Double {
        guard let lastSentDate = sinistro.dataUltimoSollecitoInviato else { return 0.0 }
        
        // Calcola giorni lavorativi dall'ultimo sollecito inviato
        let workingDaysSinceSent = workScheduleManager.countWorkingDays(from: lastSentDate, to: now)
        
        // Periodo di "calma" dopo un sollecito: 4 giorni lavorativi
        let calmPeriodDays = 4
        
        if workingDaysSinceSent < calmPeriodDays {
            // Debuff massimo (-0.5) che sfuma linearmente
            // Giorno 0: -0.5
            // Giorno 1: -0.375
            // Giorno 2: -0.25
            // Giorno 3: -0.125
            // Giorno 4: 0
            let remainingCalmDays = calmPeriodDays - workingDaysSinceSent
            let debuff = -0.5 * (Double(remainingCalmDays) / Double(calmPeriodDays))
            return debuff
        }
        
        return 0.0
    }
    
    /// Conta i solleciti RICEVUTI dal sinistro (usa campo consolidato sul modello)
    private func countReceivedReminders(in sinistro: Sinistro) -> Int {
        return Int(sinistro.sollecitiRicevutiCount)
    }
    
    /// Boost +0.3 se l'agenzia del sinistro è in rubrica con flag prioritaria
    private func calculateAgenziaPrioritariaBoost(for sinistro: Sinistro) -> Double {
        let rubrica = CloudKitRubricaSyncService.shared
        guard let agenzia = rubrica.findAgenziaByMatch(codice: sinistro.codiceAgenzia, nome: sinistro.agenzia)
            ?? (sinistro.codiceAgenzia.flatMap { rubrica.findAgenziaByCodice($0) }) else {
            return 0.0
        }
        return agenzia.prioritaria ? 0.3 : 0.0
    }
}
