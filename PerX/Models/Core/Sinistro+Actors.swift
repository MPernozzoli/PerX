import Foundation
import CoreData

// ============================================================================
// MARK: - Sinistro + Actors (anagrafica unificata cloud)
//
// Helper tipizzati attorno ai campi `*CloudId` e `*SnapshotJSON` aggiunti
// al modello Core Data. Gli snapshot vengono serializzati come JSON string
// e deserializzati on-demand in `CloudActorAddressSnapshot` /
// `CloudActorIbanSnapshot` (vedi ActorDTOs.swift).
// ============================================================================

extension Sinistro {

    // MARK: - Snapshot encoding helpers

    private static let snapshotEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let snapshotDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Address snapshots tipizzati

    var contraenteAddressSnapshot: CloudActorAddressSnapshot? {
        get { Self.decodeAddress(contraenteAddressSnapshotJSON) }
        set { contraenteAddressSnapshotJSON = Self.encodeAddress(newValue) }
    }

    var assicuratoAddressSnapshot: CloudActorAddressSnapshot? {
        get { Self.decodeAddress(assicuratoAddressSnapshotJSON) }
        set { assicuratoAddressSnapshotJSON = Self.encodeAddress(newValue) }
    }

    var danneggiatoAddressSnapshot: CloudActorAddressSnapshot? {
        get { Self.decodeAddress(danneggiatoAddressSnapshotJSON) }
        set { danneggiatoAddressSnapshotJSON = Self.encodeAddress(newValue) }
    }

    var ibanSnapshot: CloudActorIbanSnapshot? {
        get { Self.decodeIban(ibanSnapshotJSON) }
        set { ibanSnapshotJSON = Self.encodeIban(newValue) }
    }

    private static func decodeAddress(_ json: String?) -> CloudActorAddressSnapshot? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? snapshotDecoder.decode(CloudActorAddressSnapshot.self, from: data)
    }

    private static func encodeAddress(_ snap: CloudActorAddressSnapshot?) -> String? {
        guard let snap else { return nil }
        guard let data = try? snapshotEncoder.encode(snap) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeIban(_ json: String?) -> CloudActorIbanSnapshot? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? snapshotDecoder.decode(CloudActorIbanSnapshot.self, from: data)
    }

    private static func encodeIban(_ snap: CloudActorIbanSnapshot?) -> String? {
        guard let snap else { return nil }
        guard let data = try? snapshotEncoder.encode(snap) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Apply from CloudClaimResponse

    /// Aggiorna i riferimenti cloud (id + snapshot) leggendoli dal DTO di
    /// risposta del backend. Da chiamare nel sync layer dopo aver applicato
    /// i campi piatti tradizionali.
    func applyActorCloudRefs(from dto: CloudClaimResponse) {
        contraenteCloudId = dto.contraente_id
        assicuratoCloudId = dto.assicurato_id
        danneggiatoCloudId = dto.danneggiato_id
        agencyCloudId = dto.agency_id
        compagniaCloudId = dto.compagnia_id
        contraenteAddressSnapshot = dto.contraente_address_snapshot
        assicuratoAddressSnapshot = dto.assicurato_address_snapshot
        danneggiatoAddressSnapshot = dto.danneggiato_address_snapshot
        ibanSnapshot = dto.iban_snapshot
    }

    // MARK: - Build payload for outgoing updates

    /// Costruisce gli input per il backend a partire dagli ID cloud salvati
    /// localmente. Utile in update_claim — il backend rileggerà i campi
    /// dell'Actor tramite l'id senza bisogno di rispedire l'intero payload.
    func buildActorInputs() -> (contraente: CloudClaimActorInput?, assicurato: CloudClaimActorInput?, danneggiato: CloudClaimActorInput?) {
        func input(_ id: String?) -> CloudClaimActorInput? {
            guard let id, !id.isEmpty else { return nil }
            return CloudClaimActorInput(actor_id: id, actor_data: nil, address_id: nil, iban_id: nil)
        }
        return (input(contraenteCloudId), input(assicuratoCloudId), input(danneggiatoCloudId))
    }
}
