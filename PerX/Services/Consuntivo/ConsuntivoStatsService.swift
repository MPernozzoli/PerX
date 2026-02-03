import Foundation
import CoreData

/// Service per il calcolo delle statistiche del consuntivo
@MainActor
class ConsuntivoStatsService {
    static let shared = ConsuntivoStatsService()
    
    private init() {}
    
    // MARK: - Monthly Stats
    
    func getMonthlyClosedClaims(for month: Date, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: month)
        let endOfMonth = calendar.endOfMonth(for: month)
        
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, StatoManager.StatoSinistro.chiusa.descrizione]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getMonthlySentReports(for month: Date, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: month)
        let endOfMonth = calendar.endOfMonth(for: month)
        
        var predicateFormat = "dataInvioAtto >= %@ AND dataInvioAtto <= %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getMonthlyReturnedReports(for month: Date, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: month)
        let endOfMonth = calendar.endOfMonth(for: month)
        let statoAtto = StatoManager.StatoSinistro.attoRicevutoSottoscritto.descrizione
        
        var predicateFormat = "(dataRitornoAtto >= %@ AND dataRitornoAtto <= %@) OR (stato == %@ AND dataInvioAtto >= %@ AND dataInvioAtto <= %@)"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, statoAtto, startOfMonth as NSDate, endOfMonth as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat = "(\(predicateFormat)) AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getMonthlyAssignedClaims(for month: Date, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: month)
        var endOfMonthComponents = calendar.dateComponents([.year, .month], from: month)
        endOfMonthComponents.day = calendar.range(of: .day, in: .month, for: month)?.count ?? 31
        endOfMonthComponents.hour = 23
        endOfMonthComponents.minute = 59
        endOfMonthComponents.second = 59
        let endOfMonth = calendar.date(from: endOfMonthComponents) ?? calendar.endOfMonth(for: month)
        
        var predicateFormat = "dataAssegnazione != nil AND dataAssegnazione >= %@ AND dataAssegnazione <= %@"
        var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        let allAssigned = (try? context.fetch(request)) ?? []
        
        // Raggruppa per riferimento e prendi solo il primo record per ogni sinistro
        // Questo garantisce che ogni sinistro sia contato una sola volta anche se assegnato più volte
        var seenReferences = Set<String>()
        var uniqueAssigned: [Sinistro] = []
        
        for sinistro in allAssigned {
            guard let riferimento = sinistro.riferimento,
                  let dataAssegnazione = sinistro.dataAssegnazione,
                  calendar.isDate(dataAssegnazione, equalTo: month, toGranularity: .month) else {
                continue
            }
            if !seenReferences.contains(riferimento) {
                seenReferences.insert(riferimento)
                uniqueAssigned.append(sinistro)
            }
        }
        
        return uniqueAssigned
    }
    
    func getMonthlyRevokedClaims(for month: Date, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfMonth(for: month)
        let endOfMonth = calendar.endOfMonth(for: month)
        let statoRevocata = StatoManager.StatoSinistro.revocata.descrizione
        
        var predicateFormat = "stato == %@ AND dataRevoca >= %@ AND dataRevoca <= %@"
        var predicateArgs: [Any] = [statoRevocata, startOfMonth as NSDate, endOfMonth as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        let allRevoked = (try? context.fetch(request)) ?? []
        
        // Raggruppa per riferimento e prendi solo il primo record per ogni sinistro
        // Questo garantisce che ogni sinistro sia contato una sola volta anche se revocato più volte
        var seenReferences = Set<String>()
        var uniqueRevoked: [Sinistro] = []
        
        for sinistro in allRevoked {
            guard let riferimento = sinistro.riferimento else { continue }
            if !seenReferences.contains(riferimento) {
                seenReferences.insert(riferimento)
                uniqueRevoked.append(sinistro)
            }
        }
        
        return uniqueRevoked
    }
    
    // MARK: - Yearly Stats
    
    func getYearlyClosedClaims(for year: Int, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) ?? Date()
        
        var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
        var predicateArgs: [Any] = [startOfYear as NSDate, endOfYear as NSDate, StatoManager.StatoSinistro.chiusa.descrizione]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getYearlySentReports(for year: Int, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) ?? Date()
        
        var predicateFormat = "dataInvioAtto >= %@ AND dataInvioAtto <= %@"
        var predicateArgs: [Any] = [startOfYear as NSDate, endOfYear as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        return (try? context.fetch(request)) ?? []
    }
    
    func getYearlyAssignedClaims(for year: Int, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) ?? Date()
        
        var predicateFormat = "dataAssegnazione >= %@ AND dataAssegnazione <= %@"
        var predicateArgs: [Any] = [startOfYear as NSDate, endOfYear as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        let allAssigned = (try? context.fetch(request)) ?? []
        
        // Raggruppa per riferimento e prendi solo il primo record per ogni sinistro
        // Questo garantisce che ogni sinistro sia contato una sola volta anche se assegnato più volte
        var seenReferences = Set<String>()
        var uniqueAssigned: [Sinistro] = []
        
        for sinistro in allAssigned {
            guard let riferimento = sinistro.riferimento else { continue }
            if !seenReferences.contains(riferimento) {
                seenReferences.insert(riferimento)
                uniqueAssigned.append(sinistro)
            }
        }
        
        return uniqueAssigned
    }
    
    func getYearlyRevokedClaims(for year: Int, in context: NSManagedObjectContext, userEmail: String? = nil) -> [Sinistro] {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)) ?? Date()
        let statoRevocata = StatoManager.StatoSinistro.revocata.descrizione
        
        var predicateFormat = "stato == %@ AND dataRevoca >= %@ AND dataRevoca <= %@"
        var predicateArgs: [Any] = [statoRevocata, startOfYear as NSDate, endOfYear as NSDate]
        
        if let userEmail = userEmail?.lowercased(), !userEmail.isEmpty {
            predicateFormat += " AND assignedToUserEmail ==[c] %@"
            predicateArgs.append(userEmail)
        }
        
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
        
        let allRevoked = (try? context.fetch(request)) ?? []
        
        // Raggruppa per riferimento e prendi solo il primo record per ogni sinistro
        // Questo garantisce che ogni sinistro sia contato una sola volta anche se revocato più volte
        var seenReferences = Set<String>()
        var uniqueRevoked: [Sinistro] = []
        
        for sinistro in allRevoked {
            guard let riferimento = sinistro.riferimento else { continue }
            if !seenReferences.contains(riferimento) {
                seenReferences.insert(riferimento)
                uniqueRevoked.append(sinistro)
            }
        }
        
        return uniqueRevoked
    }
    
    // MARK: - Aggregated Stats
    
    func getLiquidationStats(for claims: [Sinistro], groupByCompany: Bool = true) -> [LiquidationStats] {
        // Raggruppa i sinistri per compagnia o gruppo (case-insensitive per evitare duplicati)
        let groupedClaims: [String: [Sinistro]]
        if groupByCompany {
            groupedClaims = Dictionary(grouping: claims) {
                ($0.nomeCompagnia ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces)
            }
        } else {
            groupedClaims = Dictionary(grouping: claims) {
                ($0.gruppo ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces)
            }
        }
        
        return groupedClaims.map { normalizedKey, claims in
            // Prendi il nome originale formattato dal primo sinistro del gruppo
            let company = groupByCompany 
                ? (claims.first?.nomeCompagnia?.capitalized ?? "N/D")
                : (claims.first?.gruppo?.capitalized ?? "N/D")
            let totalClaimsCount = claims.count
            
            // Determina i range in base alla compagnia/gruppo
            let rangeLiquidato: (min: Double, max: Double)
            let rangePL: (min: Double, max: Double)
            
            if groupByCompany {
                // Raggruppato per compagnia
                let compagnia = Compagnia.detect(
                    gruppo: claims.first?.gruppo,
                    compagnia: claims.first?.nomeCompagnia
                )
                rangeLiquidato = compagnia.rangeLiquidatoMedio
                rangePL = compagnia.rangePL
            } else {
                // Raggruppato per gruppo
                let gruppo = GruppoAssicurativo.from(nomeGruppo: claims.first?.gruppo)
                rangeLiquidato = gruppo.rangeLiquidatoMedio
                rangePL = gruppo.rangePL
            }
            
            // Sinistri in PL
            let inPLClaims = claims.filter { $0.isInPL }
            
            // Sinistri con liquidazione (escludendo negativi, quindi almeno 1€)
            // Per Generali, escludiamo anche i "concordato (non liquidabile dallo studio)" (special client)
            let allWithLiquidation = claims.filter { sinistro in
                guard let importo = sinistro.importoLiquidatoEffettivo?.doubleValue else { return false }
                // Escludi special client per Generali (concordato non liquidabile)
                if !groupByCompany {
                    let gruppo = GruppoAssicurativo.from(nomeGruppo: sinistro.gruppo)
                    if gruppo == .generali {
                        if let def = sinistro.definizione?.uppercased(),
                           def.contains("CONCORDATO") && def.contains("NON LIQUIDABILE DALLO STUDIO PERITALE") {
                            return false
                        }
                    }
                } else {
                    let compagnia = Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
                    if compagnia == .cattolica || compagnia == .generaliItalia {
                        if let def = sinistro.definizione?.uppercased(),
                           def.contains("CONCORDATO") && def.contains("NON LIQUIDABILE DALLO STUDIO PERITALE") {
                            return false
                        }
                    }
                }
                return importo >= rangeLiquidato.min
            }
            
            // MEDIE "IN PL" - Solo sinistri in PL con range PL
            let inPLRange = inPLClaims.filter { sinistro in
                guard let importo = sinistro.importoLiquidatoEffettivo?.doubleValue else { return false }
                return importo >= rangePL.min && importo <= rangePL.max
            }
            
            // MEDIE "TUTTI" - Tutti i sinistri con liquidazione (esclusi negativi) con range liquidato
            let allRange = allWithLiquidation.filter { sinistro in
                guard let importo = sinistro.importoLiquidatoEffettivo?.doubleValue else { return false }
                return importo >= rangeLiquidato.min && importo <= rangeLiquidato.max
            }
            
            // Calcola le medie
            let avgInPL = inPLRange.isEmpty ? 0 : inPLRange.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(inPLRange.count)
            let avgAll = allRange.isEmpty ? 0 : allRange.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(allRange.count)
            
            // Per le negative contiamo SOLO i sinistri senza liquidazione (haLiquidazione = false)
            let negative = claims.filter { $0.isNegativa }
            let negativePerc = claims.count > 0 ? (Double(negative.count) / Double(claims.count)) * 100 : 0
            
            // Calcola tempo medio gestione (giorni tra dataAssegnazione e dataChiusura)
            // SOLO sinistri con dataAssegnazione, skippiamo quelli senza
            let sinistriConTempoGestione = claims.compactMap { sinistro -> Double? in
                guard let dataAssegnazione = sinistro.dataAssegnazione,
                      let dataChiusura = sinistro.dataChiusura else {
                    return nil
                }
                let giorni = Calendar.current.dateComponents([.day], from: dataAssegnazione, to: dataChiusura).day ?? 0
                return Double(giorni)
            }
            let avgGestioneDays = sinistriConTempoGestione.isEmpty ? 0 : sinistriConTempoGestione.reduce(0, +) / Double(sinistriConTempoGestione.count)
            
            // Trova sinistri chiusi senza dataAssegnazione
            let sinistriSenzaDataAssegnazione = claims.compactMap { sinistro -> String? in
                // Solo sinistri chiusi (hanno dataChiusura) ma senza dataAssegnazione
                guard sinistro.dataChiusura != nil,
                      sinistro.dataAssegnazione == nil,
                      let riferimento = sinistro.riferimento else {
                    return nil
                }
                return riferimento
            }
            
            // Trova sinistri in PL senza importo liquidazione (per calcolo medie)
            // Controlla se c'è un valore in stimaDanno, liquidato, dannoAccertato O nella perizia
            // Non basta controllare importoLiquidatoEffettivo perché restituisce nil se haLiquidazione è false
            let sinistriSenzaLiquidazione = inPLClaims.compactMap { sinistro -> String? in
                // Verifica se c'è un valore in uno dei campi possibili del sinistro
                let hasValueInSinistro = (sinistro.stimaDanno?.doubleValue ?? 0) > 0 ||
                                         (sinistro.liquidato?.doubleValue ?? 0) > 0 ||
                                         (sinistro.dannoAccertato?.doubleValue ?? 0) > 0
                
                // Verifica se c'è un valore nella perizia (importo calcolato dalla perizia interna)
                let hasValueInPerizia = (sinistro.perizia?.stimaDannoIndennizzabile?.doubleValue ?? 0) > 0
                
                // Se non c'è valore né nel sinistro né nella perizia, segnala come mancante
                guard !hasValueInSinistro && !hasValueInPerizia,
                      let riferimento = sinistro.riferimento else {
                    return nil
                }
                return riferimento
            }
            
            // Trova sinistri chiusi senza definizione
            // Importante: la definizione è necessaria per calcolare isConcordata e quindi la % concordate
            let sinistriSenzaDefinizione = claims.compactMap { sinistro -> String? in
                // Solo sinistri chiusi (hanno dataChiusura) ma senza definizione
                // Se un sinistro è chiuso e potrebbe essere concordato, deve avere la definizione
                guard sinistro.dataChiusura != nil,
                      (sinistro.definizione == nil || sinistro.definizione?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true),
                      let riferimento = sinistro.riferimento else {
                    return nil
                }
                return riferimento
            }
            
            // Calcola % concordate: [n concordate]/[chiusure totali]
            let concordate = claims.filter { $0.isConcordata }
            let concordatePerc = claims.count > 0 ? (Double(concordate.count) / Double(claims.count)) * 100 : 0
            
            return LiquidationStats(
                company: company,
                averageUnder5k: avgInPL,  // Manteniamo per retrocompatibilità (usa range PL)
                averageUnder10k: avgInPL, // Manteniamo per retrocompatibilità (usa range PL)
                averageUnder5kInPL: avgInPL,
                averageUnder10kInPL: avgInPL,
                averageUnder5kAll: avgAll,
                averageUnder10kAll: avgAll,
                negativePercentage: negativePerc,
                concordatePercentage: concordatePerc,
                averageGestioneDays: avgGestioneDays,
                totalClaims: totalClaimsCount,
                sinistriSenzaDataAssegnazione: sinistriSenzaDataAssegnazione,
                sinistriSenzaLiquidazione: sinistriSenzaLiquidazione,
                sinistriSenzaDefinizione: sinistriSenzaDefinizione
            )
        }.sorted { $0.company < $1.company }
    }
    
    func getMonthlyBreakdown(for year: Int, closedClaims: [Sinistro], sentReports: [Sinistro]) -> [MonthlyBreakdownData] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "it_IT")
        
        return (1...12).map { month in
            let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            
            let closures = closedClaims.filter { sinistro in
                guard let date = sinistro.dataChiusura else { return false }
                return calendar.component(.month, from: date) == month
            }.count
            
            let reports = sentReports.filter { sinistro in
                guard let date = sinistro.dataInvioAtto else { return false }
                return calendar.component(.month, from: date) == month
            }.count
            
            return MonthlyBreakdownData(
                month: month,
                monthName: formatter.string(from: startOfMonth).capitalized,
                closures: closures,
                reports: reports
            )
        }
    }
    
    func getCompanyBreakdown(for claims: [Sinistro]) -> [CompanyBreakdownData] {
        // Normalizza i nomi delle compagnie (case-insensitive) per evitare duplicati
        let grouped = Dictionary(grouping: claims) {
            ($0.nomeCompagnia ?? "N/D").lowercased().trimmingCharacters(in: .whitespaces)
        }
        
        return grouped.map { normalizedCompany, claims in
            // Prendi il nome originale formattato dal primo sinistro del gruppo
            let company = claims.first?.nomeCompagnia?.capitalized ?? "N/D"
            let inPLClaims = claims.filter { $0.isInPL }
            let liquidatoValues = inPLClaims.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }
            let avgLiquidato = liquidatoValues.isEmpty ? 0 : liquidatoValues.reduce(0, +) / Double(liquidatoValues.count)
            let negativeCount = claims.filter { $0.isNegativa }.count
            let negativePerc = claims.isEmpty ? 0 : (Double(negativeCount) / Double(claims.count)) * 100
            
            return CompanyBreakdownData(
                company: company,
                totalClaims: claims.count,
                inPLClaims: inPLClaims.count,
                averageLiquidation: avgLiquidato,
                negativePercentage: negativePerc
            )
        }.sorted { $0.totalClaims > $1.totalClaims }
    }
    
    func calculateAverageLiquidation(for claims: [Sinistro]) -> Double {
        let inPLClaims = claims.filter { $0.isInPL }
        let values = inPLClaims.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    func calculateNegativePercentage(for claims: [Sinistro]) -> Double {
        let negatives = claims.filter { $0.isNegativa }.count
        return claims.isEmpty ? 0 : (Double(negatives) / Double(claims.count)) * 100
    }
    
    func calculateDailyAverage(claims: [Sinistro], workingHours: Double) -> Double {
        let workingDays = workingHours / 8.0 // Assumiamo 8 ore al giorno
        return workingDays > 0 ? Double(claims.count) / workingDays : 0
    }
    
    // MARK: - Giorni gestione (singola fonte per Consuntivo, FilteredSinistri, ecc.)
    
    /// Giorni tra dataAssegnazione e dataChiusura. `nil` se manca una delle due.
    /// Usato da ConsuntivoView, FilteredSinistriWindow, FilteredSinistriViewModel per consistenza.
    func giorniGestione(for sinistro: Sinistro) -> Int? {
        guard let dataAssegnazione = sinistro.dataAssegnazione,
              let dataChiusura = sinistro.dataChiusura else {
            return nil
        }
        let day = Calendar.current.dateComponents([.day], from: dataAssegnazione, to: dataChiusura).day
        return day
    }
    
    // MARK: - Liquidation history
    
    /// Ultimi 12 mesi di statistiche liquidazione (avg under 5k/10k, % negative) per grafici/storico.
    func getLiquidationHistory(
        upToMonth: Date,
        context: NSManagedObjectContext,
        userEmail: String? = nil
    ) -> [MonthlyLiquidationStats] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        let statoChiusa = StatoManager.StatoSinistro.chiusa.descrizione
        
        return (0...11).compactMap { monthOffset in
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: upToMonth) else { return nil }
            let startOfMonth = calendar.startOfMonth(for: date)
            let endOfMonth = calendar.endOfMonth(for: date)
            
            var predicateFormat = "dataChiusura >= %@ AND dataChiusura <= %@ AND stato == %@"
            var predicateArgs: [Any] = [startOfMonth as NSDate, endOfMonth as NSDate, statoChiusa]
            if let email = userEmail?.lowercased(), !email.isEmpty {
                predicateFormat += " AND assignedToUserEmail ==[c] %@"
                predicateArgs.append(email)
            }
            
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: predicateFormat, argumentArray: predicateArgs)
            guard let claims = try? context.fetch(request) else { return nil }
            
            let inPLClaims = claims.filter { $0.isInPL }
            let under5k = inPLClaims.filter { s in
                guard let v = s.importoLiquidatoEffettivo?.doubleValue else { return false }
                return v >= 1 && v <= 5000
            }
            let under10k = inPLClaims.filter { s in
                guard let v = s.importoLiquidatoEffettivo?.doubleValue else { return false }
                return v >= 1 && v <= 10000
            }
            let negative = claims.filter { $0.isNegativa }
            let avg5k = under5k.isEmpty ? 0 : under5k.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(under5k.count)
            let avg10k = under10k.isEmpty ? 0 : under10k.compactMap { $0.importoLiquidatoEffettivo?.doubleValue }.reduce(0, +) / Double(under10k.count)
            let negPerc = claims.isEmpty ? 0 : (Double(negative.count) / Double(claims.count)) * 100
            
            return MonthlyLiquidationStats(
                date: date,
                monthName: formatter.string(from: date).capitalized,
                averageUnder5k: avg5k,
                averageUnder10k: avg10k,
                negativePercentage: negPerc,
                totalClaims: claims.count
            )
        }
    }
}

