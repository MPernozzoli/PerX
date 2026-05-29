import Foundation

struct BignamiSummary: Decodable, Equatable {
    let matched: Bool
    let companyName: String?
    let companyCode: String?
    let policyName: String?
    let policyCode: String?
    let policyType: String?
    let editionLabel: String?
    let editionCode: String?
    let year: Int?
    let guarantee: String?
    let overviewText: String?
    let definitions: [String]
    let commonExclusions: [String]
    let commonInterpretations: [String]
    let commonNotes: [String]
    let sections: [BignamiSectionSummary]
    let coverageItems: [BignamiCoverageItemSummary]
    let commonLimits: [BignamiCommonLimitSummary]
    let webPath: String?
    let matchScore: Double?

    enum CodingKeys: String, CodingKey {
        case matched
        case companyName = "company_name"
        case companyCode = "company_code"
        case policyName = "policy_name"
        case policyCode = "policy_code"
        case policyType = "policy_type"
        case editionLabel = "edition_label"
        case editionCode = "edition_code"
        case year
        case guarantee
        case overviewText = "overview_text"
        case definitions
        case commonExclusions = "common_exclusions"
        case commonInterpretations = "common_interpretations"
        case commonNotes = "common_notes"
        case sections
        case coverageItems = "coverage_items"
        case commonLimits = "common_limits"
        case webPath = "web_path"
        case matchScore = "match_score"
    }
}

struct BignamiSectionSummary: Decodable, Equatable, Identifiable {
    var id: String { [party, title, pageReference, articleNumber].compactMap { $0 }.joined(separator: "-") }
    let party: String?
    let title: String?
    let definition: String?
    let valueType: String?
    let primoRischioValue: String?
    let derogaPercentage: Double?
    let determinazione: [String]
    let exclusions: [String]
    let notes: [String]
    let pageReference: String?
    let articleNumber: String?

    enum CodingKeys: String, CodingKey {
        case party
        case title
        case definition
        case valueType = "value_type"
        case primoRischioValue = "primo_rischio_value"
        case derogaPercentage = "deroga_percentage"
        case determinazione
        case exclusions
        case notes
        case pageReference = "page_reference"
        case articleNumber = "article_number"
    }
}

struct BignamiCoverageItemSummary: Decodable, Equatable, Identifiable {
    var id: String { [guaranteeName, guaranteeGroup, maximumValue, deductibleValue].compactMap { $0 }.joined(separator: "-") }
    let guaranteeName: String
    let guaranteeGroup: String?
    let description: String?
    let valueType: String?
    let maximumValue: String?
    let deductibleValue: String?
    let guaranteeExclusions: [String]
    let commonExclusions: [String]
    let pageReference: String?
    let articleNumber: String?

    enum CodingKeys: String, CodingKey {
        case guaranteeName = "guarantee_name"
        case guaranteeGroup = "guarantee_group"
        case description
        case valueType = "value_type"
        case maximumValue = "maximum_value"
        case deductibleValue = "deductible_value"
        case guaranteeExclusions = "guarantee_exclusions"
        case commonExclusions = "common_exclusions"
        case pageReference = "page_reference"
        case articleNumber = "article_number"
    }
}

struct BignamiCommonLimitSummary: Decodable, Equatable, Identifiable {
    var id: String { [label, scope, value].compactMap { $0 }.joined(separator: "-") }
    let label: String
    let scope: String?
    let value: String?
    let onFrontespizio: Bool
    let pageReference: String?
    let articleNumber: String?

    enum CodingKeys: String, CodingKey {
        case label
        case scope
        case value
        case onFrontespizio = "on_frontespizio"
        case pageReference = "page_reference"
        case articleNumber = "article_number"
    }
}

@MainActor
final class BignamiService {
    static let shared = BignamiService()

    private let client = HubAPIAdapterClient.shared

    private init() {}

    func fetchSummary(for sinistro: Sinistro) async throws -> BignamiSummary {
        var components = URLComponents()
        components.path = "/api/v1/bignami/summary"
        components.queryItems = [
            queryItem("company", sinistro.nomeCompagnia),
            queryItem("policy_type", sinistro.tipoPolizza),
            queryItem("policy_number", sinistro.numeroPolizza),
            queryItem("guarantee", sinistro.garanzia ?? sinistro.fulminazione),
        ].compactMap { $0 }

        let path = components.string ?? "/api/v1/bignami/summary"
        return try await client.cloudGet(path)
    }

    private func queryItem(_ name: String, _ value: String?) -> URLQueryItem? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URLQueryItem(name: name, value: value)
    }
}
