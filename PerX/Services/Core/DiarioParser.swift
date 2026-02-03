import Foundation

/// Parser per le note utente nel diario
/// Estrae tag speciali (@task, @azione, @[riferimento]) e genera eventi
@MainActor
class DiarioParser: ObservableObject {
    static let shared = DiarioParser()
    
    private let eventBus = UnifiedEventBus.shared
    
    // MARK: - Regex Patterns
    
    /// Pattern per @task: cattura tutto fino al primo punto o a capo
    /// Esempio: "@task chiamare agente entro le 16" → corpo = "chiamare agente entro le 16"
    private let taskPattern = try! NSRegularExpression(
        pattern: #"@task\s+([^.\n]+)"#,
        options: [.caseInsensitive]
    )
    
    /// Pattern per @azione: cattura il nome dell'azione
    /// Esempio: "@azione sollecito" → corpo = "sollecito"
    private let actionPattern = try! NSRegularExpression(
        pattern: #"@azione\s+([^.\n\s]+)"#,
        options: [.caseInsensitive]
    )
    
    /// Pattern per @[riferimento]: cattura il contenuto tra parentesi quadre
    /// Esempio: "@[2024/123456]" → corpo = "2024/123456"
    /// Esempio: "@[fattura.pdf]" → corpo = "fattura.pdf"
    private let referencePattern = try! NSRegularExpression(
        pattern: #"@\[([^\]]+)\]"#,
        options: []
    )
    
    // MARK: - Time Patterns
    
    /// Pattern per deadline naturali ("entro le...")
    private let deadlinePatterns: [(pattern: String, handler: (Date, NSTextCheckingResult, String) -> Date?)] = [
        // "entro le HH" o "entro le HH:MM"
        (#"entro\s+le\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let range1 = Range(match.range(at: 1), in: text)!
            let hour = Int(text[range1]) ?? 0
            var minute = 0
            if match.numberOfRanges > 2, let range2 = Range(match.range(at: 2), in: text) {
                minute = Int(text[range2]) ?? 0
            }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today)
        }),
        
        // "domani" o "domani mattina/pomeriggio"
        (#"domani(?:\s+(mattina|pomeriggio))?"#, { today, match, text in
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return nil }
            if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                let period = String(text[range]).lowercased()
                let hour = period == "mattina" ? 9 : 14
                return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow)
            }
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }),
        
        // "entro [giorno settimana] alle HH" - es. "entro martedì alle 16"
        (#"entro\s+(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let hourRange = Range(match.range(at: 2), in: text)!
            
            let dayName = String(text[dayRange]).lowercased()
                .replacingOccurrences(of: "ì", with: "i")
            
            let weekdayMap = [
                "lunedi": 2, "martedi": 3, "mercoledi": 4,
                "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1
            ]
            
            guard let targetWeekday = weekdayMap[dayName] else { return nil }
            let currentWeekday = Calendar.current.component(.weekday, from: today)
            
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            
            guard let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: today) else { return nil }
            
            let hour = Int(text[hourRange]) ?? 0
            var minute = 0
            if match.numberOfRanges > 3, let minuteRange = Range(match.range(at: 3), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: targetDate)
        }),
        
        // "entro [giorno settimana]" - es. "entro martedì" (solo giorno, default 18:00)
        (#"entro\s+(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)(?:\s+(mattina|pomeriggio))?"#, { today, match, text in
            let range = Range(match.range(at: 1), in: text)!
            let dayName = String(text[range]).lowercased()
                .replacingOccurrences(of: "ì", with: "i")
            
            let weekdayMap = [
                "lunedi": 2, "martedi": 3, "mercoledi": 4,
                "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1
            ]
            
            guard let targetWeekday = weekdayMap[dayName] else { return nil }
            let currentWeekday = Calendar.current.component(.weekday, from: today)
            
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            
            guard let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: today) else { return nil }
            
            var hour = 18  // Default fine giornata per deadline
            if match.numberOfRanges > 2, let periodRange = Range(match.range(at: 2), in: text) {
                let period = String(text[periodRange]).lowercased()
                hour = period == "pomeriggio" ? 18 : 12
            }
            
            return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: targetDate)
        }),
        
        // "tra X giorni"
        (#"tra\s+(\d+)\s+giorni?"#, { today, match, text in
            let range = Range(match.range(at: 1), in: text)!
            guard let days = Int(text[range]) else { return nil }
            return Calendar.current.date(byAdding: .day, value: days, to: today)
        }),
        
        // "entro il DD/MM alle HH" o "entro il DD/MM/YYYY alle HH" (data + orario)
        // Es: "entro il 12/07 alle 16" o "entro il 12/07/2024 alle 16:30"
        (#"entro\s+il\s+(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let monthRange = Range(match.range(at: 2), in: text)!
            let hourRange = Range(match.range(at: 4), in: text)!
            
            guard let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]),
                  let hour = Int(text[hourRange]) else { return nil }
            
            var year = Calendar.current.component(.year, from: today)
            if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: text) {
                if let y = Int(text[yearRange]) {
                    year = y < 100 ? 2000 + y : y
                }
            }
            
            var minute = 0
            if match.numberOfRanges > 5, let minuteRange = Range(match.range(at: 5), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            
            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            components.hour = hour
            components.minute = minute
            
            if let targetDate = Calendar.current.date(from: components) {
                // Se la data è già passata quest'anno, usa l'anno prossimo
                if targetDate < today && year == Calendar.current.component(.year, from: today) {
                    components.year = year + 1
                    return Calendar.current.date(from: components)
                }
                return targetDate
            }
            
            return nil
        }),
        
        // "entro il DD/MM" o "entro il DD/MM/YYYY" (solo data, default 18:00)
        (#"entro\s+il\s+(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let monthRange = Range(match.range(at: 2), in: text)!
            
            guard let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]) else { return nil }
            
            var year = Calendar.current.component(.year, from: today)
            if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: text) {
                if let y = Int(text[yearRange]) {
                    year = y < 100 ? 2000 + y : y
                }
            }
            
            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            components.hour = 18
            components.minute = 0
            
            if let targetDate = Calendar.current.date(from: components) {
                // Se la data è già passata quest'anno, usa l'anno prossimo
                if targetDate < today && year == Calendar.current.component(.year, from: today) {
                    components.year = year + 1
                    return Calendar.current.date(from: components)
                }
                return targetDate
            }
            
            return nil
        }),
        
        // "il DD/MM" o "il DD/MM/YYYY" (formato italiano, senza "entro")
        // Es: "chiamare il 12/07" o "chiamare il 12/07/2024"
        (#"\bil\s+(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let monthRange = Range(match.range(at: 2), in: text)!
            
            guard let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]) else { return nil }
            
            var year = Calendar.current.component(.year, from: today)
            if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: text) {
                if let y = Int(text[yearRange]) {
                    year = y < 100 ? 2000 + y : y
                }
            }
            
            // Se la data è nel passato (stesso anno), assume anno prossimo
            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            components.hour = 18
            components.minute = 0
            
            if let targetDate = Calendar.current.date(from: components) {
                // Se la data è già passata quest'anno, usa l'anno prossimo
                if targetDate < today && year == Calendar.current.component(.year, from: today) {
                    components.year = year + 1
                    return Calendar.current.date(from: components)
                }
                return targetDate
            }
            
            return nil
        })
    ]
    
    /// Pattern per orari programmati ("alle...")
    private let scheduledTimePatterns: [(pattern: String, handler: (Date, NSTextCheckingResult, String) -> Date?)] = [
        // "alle HH" o "alle HH:MM"
        (#"alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let range1 = Range(match.range(at: 1), in: text)!
            let hour = Int(text[range1]) ?? 0
            var minute = 0
            if match.numberOfRanges > 2, let range2 = Range(match.range(at: 2), in: text) {
                minute = Int(text[range2]) ?? 0
            }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today)
        }),
        
        // "domani alle HH" o "domani alle HH:MM"
        (#"domani\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return nil }
            let range1 = Range(match.range(at: 1), in: text)!
            let hour = Int(text[range1]) ?? 0
            var minute = 0
            if match.numberOfRanges > 2, let range2 = Range(match.range(at: 2), in: text) {
                minute = Int(text[range2]) ?? 0
            }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
        }),
        
        // "lunedì alle HH", etc.
        (#"(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let hourRange = Range(match.range(at: 2), in: text)!
            
            let dayName = String(text[dayRange]).lowercased().replacingOccurrences(of: "ì", with: "i")
            let weekdayMap = [
                "lunedi": 2, "martedi": 3, "mercoledi": 4,
                "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1
            ]
            
            guard let targetWeekday = weekdayMap[dayName] else { return nil }
            let currentWeekday = Calendar.current.component(.weekday, from: today)
            
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            
            guard let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: today) else { return nil }
            
            let hour = Int(text[hourRange]) ?? 0
            var minute = 0
            if match.numberOfRanges > 3, let minuteRange = Range(match.range(at: 3), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: targetDate)
        }),
        
        // "il [giorno settimana]" - es. "chiamare il lunedì"
        (#"\bil\s+(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)(?:\s+(mattina|pomeriggio))?"#, { today, match, text in
            let range = Range(match.range(at: 1), in: text)!
            let dayName = String(text[range]).lowercased()
                .replacingOccurrences(of: "ì", with: "i")
            
            let weekdayMap = [
                "lunedi": 2, "martedi": 3, "mercoledi": 4,
                "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1
            ]
            
            guard let targetWeekday = weekdayMap[dayName] else { return nil }
            let currentWeekday = Calendar.current.component(.weekday, from: today)
            
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            
            guard let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: today) else { return nil }
            
            var hour = 9
            if match.numberOfRanges > 2, let periodRange = Range(match.range(at: 2), in: text) {
                let period = String(text[periodRange]).lowercased()
                hour = period == "pomeriggio" ? 14 : 9
            }
            
            return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: targetDate)
        }),
        
        // "il [giorno settimana] alle HH" - es. "chiamare il lunedì alle 14"
        (#"\bil\s+(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let hourRange = Range(match.range(at: 2), in: text)!
            
            let dayName = String(text[dayRange]).lowercased().replacingOccurrences(of: "ì", with: "i")
            let weekdayMap = [
                "lunedi": 2, "martedi": 3, "mercoledi": 4,
                "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1
            ]
            
            guard let targetWeekday = weekdayMap[dayName] else { return nil }
            let currentWeekday = Calendar.current.component(.weekday, from: today)
            
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            
            guard let targetDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: today) else { return nil }
            
            let hour = Int(text[hourRange]) ?? 0
            var minute = 0
            if match.numberOfRanges > 3, let minuteRange = Range(match.range(at: 3), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: targetDate)
        }),
        
        // "il DD/MM alle HH" o "il DD/MM/YYYY alle HH" (formato italiano con orario)
        // Es: "chiamare il 12/07 alle 14" o "chiamare il 12/07/2024 alle 14:30"
        (#"\bil\s+(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s+alle\s+(\d{1,2})(?::(\d{2}))?"#, { today, match, text in
            let dayRange = Range(match.range(at: 1), in: text)!
            let monthRange = Range(match.range(at: 2), in: text)!
            let hourRange = Range(match.range(at: 4), in: text)!
            
            guard let day = Int(text[dayRange]),
                  let month = Int(text[monthRange]),
                  let hour = Int(text[hourRange]) else { return nil }
            
            var year = Calendar.current.component(.year, from: today)
            if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: text) {
                if let y = Int(text[yearRange]) {
                    year = y < 100 ? 2000 + y : y
                }
            }
            
            var minute = 0
            if match.numberOfRanges > 5, let minuteRange = Range(match.range(at: 5), in: text) {
                minute = Int(text[minuteRange]) ?? 0
            }
            
            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            components.hour = hour
            components.minute = minute
            
            if let targetDate = Calendar.current.date(from: components) {
                // Se la data è già passata quest'anno, usa l'anno prossimo
                if targetDate < today && year == Calendar.current.component(.year, from: today) {
                    components.year = year + 1
                    return Calendar.current.date(from: components)
                }
                return targetDate
            }
            
            return nil
        })
    ]
    
    private init() {
        print("[DiarioParser] ✅ Inizializzato")
    }
    
    // MARK: - Parsing
    
    /// Risultato del parsing di una nota
    struct ParseResult {
        let originalText: String
        let cleanText: String
        let tags: [ParsedTag]
        let highlightRanges: [HighlightRange]
        
        var hasTags: Bool { !tags.isEmpty }
        var hasTaskTag: Bool { tags.contains { $0.type == .task } }
        var hasActionTag: Bool { tags.contains { $0.type == .action } }
        var hasReferenceTag: Bool { tags.contains { $0.type == .reference } }
    }
    
    /// Range da evidenziare nell'UI
    struct HighlightRange {
        let range: NSRange
        let type: ParsedTag.TagType
        let isBody: Bool  // true se è il corpo del tag, false se è solo il tag stesso
    }
    
    /// Parsa una nota utente ed estrae i tag
    func parse(_ text: String) -> ParseResult {
        var tags: [ParsedTag] = []
        var highlightRanges: [HighlightRange] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        // Estrai @task
        let taskMatches = taskPattern.matches(in: text, options: [], range: fullRange)
        for match in taskMatches {
            guard match.numberOfRanges >= 2 else { continue }
            
            let fullMatchRange = match.range(at: 0)
            let bodyRange = match.range(at: 1)
            let body = nsText.substring(with: bodyRange).trimmingCharacters(in: .whitespaces)
            
            // Estrai deadline o scheduledTime dal corpo
            let timeResult = extractTime(from: body)
            
            // Calcola range Swift per il tag
            if let swiftRange = Range(bodyRange, in: text) {
                let tag = ParsedTag(
                    type: .task,
                    body: body,
                    deadline: timeResult.deadline,
                    scheduledTime: timeResult.scheduledTime,
                    timeType: timeResult.timeType,
                    range: swiftRange
                )
                tags.append(tag)
            }
            
            // Aggiungi range per highlight
            highlightRanges.append(HighlightRange(range: fullMatchRange, type: .task, isBody: false))
            highlightRanges.append(HighlightRange(range: bodyRange, type: .task, isBody: true))
        }
        
        // Estrai @azione
        let actionMatches = actionPattern.matches(in: text, options: [], range: fullRange)
        for match in actionMatches {
            guard match.numberOfRanges >= 2 else { continue }
            
            let fullMatchRange = match.range(at: 0)
            let bodyRange = match.range(at: 1)
            let body = nsText.substring(with: bodyRange).trimmingCharacters(in: .whitespaces)
            
            if let swiftRange = Range(bodyRange, in: text) {
                let tag = ParsedTag(type: .action, body: body, range: swiftRange)
                tags.append(tag)
            }
            
            highlightRanges.append(HighlightRange(range: fullMatchRange, type: .action, isBody: false))
            highlightRanges.append(HighlightRange(range: bodyRange, type: .action, isBody: true))
        }
        
        // Estrai @[riferimento]
        let refMatches = referencePattern.matches(in: text, options: [], range: fullRange)
        for match in refMatches {
            guard match.numberOfRanges >= 2 else { continue }
            
            let fullMatchRange = match.range(at: 0)
            let bodyRange = match.range(at: 1)
            let body = nsText.substring(with: bodyRange).trimmingCharacters(in: .whitespaces)
            
            if let swiftRange = Range(bodyRange, in: text) {
                let tag = ParsedTag(type: .reference, body: body, range: swiftRange)
                tags.append(tag)
            }
            
            highlightRanges.append(HighlightRange(range: fullMatchRange, type: .reference, isBody: false))
            highlightRanges.append(HighlightRange(range: bodyRange, type: .reference, isBody: true))
        }
        
        // Genera testo pulito (senza i tag)
        let cleanText = generateCleanText(text, tags: tags)
        
        return ParseResult(
            originalText: text,
            cleanText: cleanText,
            tags: tags,
            highlightRanges: highlightRanges.sorted { $0.range.location < $1.range.location }
        )
    }
    
    /// Risultato dell'estrazione tempo
    struct TimeExtractionResult {
        let deadline: Date?
        let scheduledTime: Date?
        let timeType: ParsedTag.TimeType?
    }
    
    /// Estrae deadline o scheduledTime dal testo, distinguendo tra "entro" (deadline) e "alle" (scheduledTime)
    func extractTime(from text: String, referenceDate: Date = Date()) -> TimeExtractionResult {
        let lowercased = text.lowercased()
        
        // Prima prova i pattern di scheduledTime ("alle...")
        for (patternString, handler) in scheduledTimePatterns {
            guard let regex = try? NSRegularExpression(pattern: patternString, options: [.caseInsensitive]) else { continue }
            
            let range = NSRange(location: 0, length: lowercased.utf16.count)
            if let match = regex.firstMatch(in: lowercased, options: [], range: range) {
                if let scheduled = handler(referenceDate, match, lowercased) {
                    return TimeExtractionResult(
                        deadline: nil,
                        scheduledTime: scheduled,
                        timeType: .scheduledTime
                    )
                }
            }
        }
        
        // Poi prova i pattern di deadline ("entro...")
        for (patternString, handler) in deadlinePatterns {
            guard let regex = try? NSRegularExpression(pattern: patternString, options: [.caseInsensitive]) else { continue }
            
            let range = NSRange(location: 0, length: lowercased.utf16.count)
            if let match = regex.firstMatch(in: lowercased, options: [], range: range) {
                if let deadline = handler(referenceDate, match, lowercased) {
                    return TimeExtractionResult(
                        deadline: deadline,
                        scheduledTime: nil,
                        timeType: .deadline
                    )
                }
            }
        }
        
        return TimeExtractionResult(deadline: nil, scheduledTime: nil, timeType: nil)
    }
    
    /// Estrae una deadline dal testo (metodo legacy per retrocompatibilità)
    func extractDeadline(from text: String, referenceDate: Date = Date()) -> Date? {
        return extractTime(from: text, referenceDate: referenceDate).deadline
    }
    
    /// Estrae numeri di telefono dal testo (formato italiano)
    /// Supporta: +39, 0039, 39, numeri locali con/senza prefisso
    func extractPhoneNumbers(from text: String) -> [String] {
        var phoneNumbers: [String] = []
        
        // Pattern per numeri italiani: +39, 0039, o numeri locali (9-10 cifre)
        let patterns = [
            #"\+39\s*\d{8,10}"#,           // +39 123456789
            #"0039\s*\d{8,10}"#,           // 0039 123456789
            #"\b0\d{1,2}[\s.-]?\d{6,7}\b"#, // Numeri locali (02 1234567, 06-12345678)
            #"\b\d{9,10}\b"#                // Numeri senza prefisso (10 cifre)
        ]
        
        for patternString in patterns {
            guard let regex = try? NSRegularExpression(pattern: patternString, options: []) else { continue }
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)
            
            for match in matches {
                if let swiftRange = Range(match.range(at: 0), in: text) {
                    let phoneNumber = String(text[swiftRange])
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ".", with: "")
                    
                    // Normalizza: aggiungi +39 se manca
                    let normalized = normalizePhoneNumber(phoneNumber)
                    if !phoneNumbers.contains(normalized) {
                        phoneNumbers.append(normalized)
                    }
                }
            }
        }
        
        return phoneNumbers
    }
    
    /// Normalizza un numero di telefono aggiungendo +39 se necessario
    private func normalizePhoneNumber(_ number: String) -> String {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        
        if cleaned.hasPrefix("+39") {
            return cleaned
        } else if cleaned.hasPrefix("0039") {
            return "+39" + String(cleaned.dropFirst(4))
        } else if cleaned.hasPrefix("39") && cleaned.count >= 11 {
            return "+" + cleaned
        } else if cleaned.hasPrefix("0") && cleaned.count >= 9 {
            // Numero locale, aggiungi +39
            return "+39" + cleaned
        } else if cleaned.count >= 9 && !cleaned.hasPrefix("+") && !cleaned.hasPrefix("0") {
            // Numero senza prefisso, aggiungi +39
            return "+39" + cleaned
        }
        
        return cleaned
    }
    
    /// Pulisce il titolo della task rimuovendo riferimenti temporali
    /// Rimuove: "oggi", "domani", "alle 15", "entro le 16", "martedì", date, etc.
    func cleanTaskTitle(from text: String) -> String {
        var cleaned = text
        
        // Pattern per rimuovere riferimenti temporali
        let timePatterns = [
            #"(?i)\b(oggi|domani|ieri)\b"#,
            #"(?i)\b(alle|entro le?)\s+\d{1,2}(?::\d{2})?\b"#,
            #"(?i)\b(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)\b"#,
            #"(?i)\b(mattina|pomeriggio|sera)\b"#,
            #"(?i)\b(entro\s+)?il\s+\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            #"(?i)\b(entro\s+)?il\s+(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica)\b"#
        ]
        
        for patternString in timePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: patternString,
                with: "",
                options: .regularExpression
            )
        }
        
        // Rimuovi spazi multipli e trim
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    /// Genera testo pulito rimuovendo i tag
    private func generateCleanText(_ text: String, tags: [ParsedTag]) -> String {
        var cleanText = text
        
        // Rimuovi @task [corpo]
        cleanText = taskPattern.stringByReplacingMatches(
            in: cleanText,
            options: [],
            range: NSRange(location: 0, length: cleanText.utf16.count),
            withTemplate: ""
        )
        
        // Rimuovi @azione [nome]
        cleanText = actionPattern.stringByReplacingMatches(
            in: cleanText,
            options: [],
            range: NSRange(location: 0, length: cleanText.utf16.count),
            withTemplate: ""
        )
        
        // Rimuovi @[riferimento]
        cleanText = referencePattern.stringByReplacingMatches(
            in: cleanText,
            options: [],
            range: NSRange(location: 0, length: cleanText.utf16.count),
            withTemplate: ""
        )
        
        // Pulisci spazi multipli
        cleanText = cleanText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanText
    }
    
    // MARK: - Event Generation
    
    /// Processa una nota utente e pubblica l'evento sul bus
    func processUserNote(
        _ text: String,
        sinistroId: String?,
        diarioEntryId: UUID? = nil
    ) -> ParseResult {
        let result = parse(text)
        
        // Pubblica evento solo se ci sono tag
        if result.hasTags {
            let event = UserNoteClaimEvent(
                noteText: text,
                sinistroId: sinistroId,
                parsedTags: result.tags,
                diarioEntryId: diarioEntryId
            )
            
            eventBus.publishUserNote(event)
            print("[DiarioParser] 📤 Evento pubblicato con \(result.tags.count) tag")
        }
        
        return result
    }
    
    // MARK: - Live Highlight
    
    /// Genera attributi per l'evidenziazione live durante la digitazione
    func getHighlightAttributes(for text: String) -> [(range: NSRange, type: ParsedTag.TagType, isBody: Bool)] {
        let result = parse(text)
        return result.highlightRanges.map { ($0.range, $0.type, $0.isBody) }
    }
    
    /// Verifica se il testo contiene tag in corso di digitazione
    func hasPartialTag(in text: String) -> (hasPartial: Bool, type: String?) {
        // Controlla se c'è un @ non seguito da un tag completo
        if text.contains("@task ") { return (true, "task") }
        if text.contains("@azione ") { return (true, "azione") }
        if text.contains("@[") && !text.contains("]") { return (true, "reference") }
        if text.hasSuffix("@") { return (true, nil) }
        
        return (false, nil)
    }
    
    /// Suggerimenti per l'autocompletamento
    func getSuggestions(for text: String) -> [String] {
        if text.hasSuffix("@") {
            return ["@task ", "@azione ", "@["]
        }
        
        if text.contains("@task ") && !text.contains(".") {
            // Suggerisci deadline comuni
            return ["domani", "entro le 16", "lunedì", "tra 2 giorni"]
        }
        
        if text.contains("@azione ") {
            // Suggerisci azioni comuni (future)
            return ["sollecito", "chiusura", "verifica"]
        }
        
        return []
    }
}

// MARK: - Preview Helper

extension DiarioParser {
    /// Esempio di parsing per testing
    static func example() {
        let parser = DiarioParser.shared
        
        let testCases = [
            "Chiamato cliente, tutto ok",
            "@task chiamare agente domani mattina",
            "@task verificare polizza entro le 16. Poi chiudere pratica.",
            "@azione sollecito - urgente",
            "Riferimento a @[2024/123456] per confronto",
            "Ho visto il file @[fattura.pdf] e va bene",
            "@task inviare esito entro il 15/01 @[perizia.pdf]"
        ]
        
        for test in testCases {
            let result = parser.parse(test)
            print("---")
            print("Input: \(test)")
            print("Tags: \(result.tags.count)")
            for tag in result.tags {
                print("  - \(tag.type): '\(tag.body)' deadline: \(tag.deadline?.description ?? "none")")
            }
            print("Clean: \(result.cleanText)")
        }
    }
}


