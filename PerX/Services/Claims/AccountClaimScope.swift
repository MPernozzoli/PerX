import CoreData
import Foundation

extension Notification.Name {
    static let accountClaimScopeChanged = Notification.Name("accountClaimScopeChanged")
}

/// Ogni accesso vede solo i sinistri del proprio utente e del proprio tenant.
@MainActor
enum AccountClaimScope {
    private static let tenantKey = "perx.activeTenantId"

    static func remember(tenantId: String) {
        let normalized = tenantId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: tenantKey)
        } else {
            UserDefaults.standard.set(normalized, forKey: tenantKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tenantKey)
    }

    static var activeTenantId: String {
        UserDefaults.standard.string(forKey: tenantKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func predicate(for email: String?) -> NSPredicate {
        let current = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !current.isEmpty else { return NSPredicate(value: false) }
        let tenantId = activeTenantId
        if tenantId.isEmpty {
            return NSPredicate(
                format: "ownerEmail ==[c] %@ OR assignedToUserEmail ==[c] %@",
                current,
                current
            )
        }
        return NSPredicate(
            format: "(ownerEmail ==[c] %@ OR assignedToUserEmail ==[c] %@) AND (tenantId == %@ OR tenantId == nil)",
            current,
            current,
            tenantId
        )
    }

    static func includes(_ sinistro: Sinistro, email: String?) -> Bool {
        let predicate = predicate(for: email)
        return predicate.evaluate(with: sinistro)
    }
}

@MainActor
final class AccountClaimSync {
    static let shared = AccountClaimSync()
    private var task: Task<Void, Never>?

    func refresh(email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        task?.cancel()
        task = Task { await self.run(email: normalized) }
    }

    private func run(email: String) async {
        AccountVault.activate(email: email)
        _ = await TenantSettingsAPIService.shared.loadTenantSettings()
        let tenantId = AccountClaimScope.activeTenantId
        guard !tenantId.isEmpty else {
            NotificationCenter.default.post(name: .accountClaimScopeChanged, object: nil)
            return
        }
        stampLegacyClaims(ownerEmail: email, tenantId: tenantId)
        NotificationCenter.default.post(name: .accountClaimScopeChanged, object: nil)
        await mirrorClaims(ownerEmail: email, tenantId: tenantId)
        await mirrorDiary(ownerEmail: email)
        AccountRuntime.applyCurrentProfile()
        NotificationCenter.default.post(name: .accountClaimScopeChanged, object: nil)
    }

    private func stampLegacyClaims(ownerEmail: String, tenantId: String) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(
            format: "(ownerEmail ==[c] %@ OR assignedToUserEmail ==[c] %@) AND tenantId == nil",
            ownerEmail,
            ownerEmail
        )
        let rows = (try? context.fetch(request)) ?? []
        for sinistro in rows {
            sinistro.tenantId = tenantId
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    private func mirrorClaims(ownerEmail: String, tenantId: String) async {
        let context = PersistenceController.shared.container.viewContext
        var page = 1
        var imported = 0
        while !Task.isCancelled {
            let response: TenantClaimPage
            do {
                response = try await BackendAPIClient.shared.get(
                    "claims",
                    queryItems: [
                        URLQueryItem(name: "page", value: String(page)),
                        URLQueryItem(name: "page_size", value: "200"),
                    ]
                )
            } catch {
                return
            }
            for item in response.items {
                guard let riferimento = item.externalRef?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !riferimento.isEmpty else { continue }
                upsert(item, riferimento: riferimento, ownerEmail: ownerEmail, tenantId: tenantId, in: context)
                imported += 1
            }
            if response.items.count < 200 || page * 200 >= response.total {
                break
            }
            page += 1
        }
        if context.hasChanges {
            try? context.save()
        }
        _ = imported
    }

    private func upsert(
        _ item: TenantClaimRow,
        riferimento: String,
        ownerEmail: String,
        tenantId: String,
        in context: NSManagedObjectContext
    ) {
        let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        let existing = (try? context.fetch(request)) ?? []
        let owned = existing.first {
            ($0.ownerEmail ?? "").lowercased() == ownerEmail
                || ($0.assignedToUserEmail ?? "").lowercased() == ownerEmail
        }
        if owned == nil && !existing.isEmpty {
            return
        }
        let sinistro = owned ?? Sinistro(context: context)
        sinistro.riferimento = riferimento
        sinistro.ownerEmail = ownerEmail
        sinistro.assignedToUserEmail = ownerEmail
        sinistro.tenantId = tenantId
        sinistro.nomeAssicurato = item.nomeAssicurato
        sinistro.numeroSinistroCompagnia = item.numeroSinistro
        sinistro.nomeCompagnia = item.compagnia
        sinistro.agenzia = item.agenzia
        sinistro.numeroPolizza = item.numeroPolizza
        sinistro.stato = BackendStatoMapping.statoSinistro(forCloudSlug: item.stato)?.descrizione ?? item.stato
        if let data = item.dataSinistro {
            sinistro.dataSinistro = data
        }
        if let richiesta = item.richiesta {
            sinistro.richiesta = NSDecimalNumber(value: richiesta)
        }
        if let liquidato = item.liquidato {
            sinistro.liquidato = NSDecimalNumber(value: liquidato)
        }
        if let accertato = item.dannoAccertato {
            sinistro.dannoAccertato = NSDecimalNumber(value: accertato)
            sinistro.stimaDanno = NSDecimalNumber(value: accertato)
        } else if let liquidato = item.liquidato {
            sinistro.stimaDanno = NSDecimalNumber(value: liquidato)
        }
    }

    private func mirrorDiary(ownerEmail: String) async {
        let context = PersistenceController.shared.container.viewContext
        var page = 1
        var grouped: [String: [ImportedDiaryLine]] = [:]
        while !Task.isCancelled {
            let response: ImportedDiaryPage
            do {
                response = try await BackendAPIClient.shared.get(
                    "claims/imported-diary",
                    queryItems: [
                        URLQueryItem(name: "page", value: String(page)),
                        URLQueryItem(name: "page_size", value: "400"),
                    ]
                )
            } catch {
                return
            }
            for line in response.items {
                grouped[line.externalRef, default: []].append(line)
            }
            if page * 400 >= response.total {
                break
            }
            page += 1
        }
        for (riferimento, lines) in grouped {
            let request = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            request.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            request.fetchLimit = 1
            guard let sinistro = (try? context.fetch(request))?.first else { continue }
            let owner = (sinistro.ownerEmail ?? "").lowercased()
            let assignee = (sinistro.assignedToUserEmail ?? "").lowercased()
            if owner != ownerEmail && assignee != ownerEmail {
                continue
            }
            var kept = sinistro.diarioArray.filter { $0.createdByEmail != "import-chiari" }
            kept.append(contentsOf: lines.compactMap { Self.diaryEntry(from: $0) })
            kept.sort { $0.timestamp > $1.timestamp }
            sinistro.diarioArray = kept
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    private static func diaryEntry(from line: ImportedDiaryLine) -> DiarioEntry? {
        guard let id = UUID(uuidString: line.id), !line.text.isEmpty else { return nil }
        let tipo: DiarioEntry.TipoEntry
        switch line.eventType {
        case "nota":
            tipo = .notaUtente
        case "stato":
            tipo = .cambioStato
        case "stima":
            tipo = .aggiornamento
        default:
            tipo = .sistema
        }
        return DiarioEntry(
            id: id,
            timestamp: line.eventTime,
            tipo: tipo,
            titolo: line.eventType,
            riassunto: String(line.text.prefix(180)),
            contenutoCompleto: line.text,
            createdByEmail: "import-chiari"
        )
    }
}

private struct TenantClaimPage: Decodable {
    let items: [TenantClaimRow]
    let total: Int
}

private struct TenantClaimRow: Decodable {
    let externalRef: String?
    let numeroSinistro: String?
    let compagnia: String?
    let stato: String
    let agenzia: String?
    let nomeAssicurato: String?
    let numeroPolizza: String?
    let dataSinistro: Date?
    let richiesta: Double?
    let liquidato: Double?
    let dannoAccertato: Double?

    enum CodingKeys: String, CodingKey {
        case externalRef = "external_ref"
        case numeroSinistro = "numero_sinistro"
        case compagnia
        case stato = "stato_corrente"
        case agenzia
        case nomeAssicurato = "nome_assicurato"
        case numeroPolizza = "numero_polizza"
        case dataSinistro = "data_sinistro"
        case richiesta
        case liquidato
        case dannoAccertato = "danno_accertato"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalRef = try container.decodeIfPresent(String.self, forKey: .externalRef)
        numeroSinistro = try container.decodeIfPresent(String.self, forKey: .numeroSinistro)
        compagnia = try container.decodeIfPresent(String.self, forKey: .compagnia)
        stato = try container.decodeIfPresent(String.self, forKey: .stato) ?? ""
        agenzia = try container.decodeIfPresent(String.self, forKey: .agenzia)
        nomeAssicurato = try container.decodeIfPresent(String.self, forKey: .nomeAssicurato)
        numeroPolizza = try container.decodeIfPresent(String.self, forKey: .numeroPolizza)
        richiesta = Self.amount(container, .richiesta)
        liquidato = Self.amount(container, .liquidato)
        dannoAccertato = Self.amount(container, .dannoAccertato)
        if let raw = try? container.decodeIfPresent(String.self, forKey: .dataSinistro) {
            dataSinistro = Self.parseDate(raw)
        } else {
            dataSinistro = nil
        }
    }

    private static func amount(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(raw)
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw)
    }
}

private struct ImportedDiaryPage: Decodable {
    let items: [ImportedDiaryLine]
    let total: Int
}

private struct ImportedDiaryLine: Decodable {
    let id: String
    let externalRef: String
    let eventTime: Date
    let eventType: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case externalRef = "external_ref"
        case eventTime = "event_time"
        case eventType = "event_type"
        case text
    }
}
