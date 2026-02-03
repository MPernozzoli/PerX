import Foundation
import CloudKit

// MARK: - CKDatabase Async Extensions

/// Estensioni centralizzate per operazioni CloudKit async.
/// Sostituiscono i wrapper duplicati in tutti i servizi CloudKit.
extension CKDatabase {
    
    /// Salva un record in modo asincrono.
    /// - Parameter record: Il record da salvare
    /// - Returns: Il record salvato
    func saveRecordAsync(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            self.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
            }
        }
    }
    
    /// Recupera un record per ID.
    /// - Parameter recordID: L'ID del record da recuperare
    /// - Returns: Il record recuperato
    /// - Throws: Errore se il record non esiste o in caso di errore di rete
    func fetchRecordAsync(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            self.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let record else {
                    continuation.resume(throwing: CKError(.unknownItem))
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }
    
    /// Recupera un record per ID, restituendo nil se non esiste.
    /// - Parameter recordID: L'ID del record da recuperare
    /// - Returns: Il record recuperato o nil se non esiste
    func fetchRecordIfExists(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            self.fetch(withRecordID: recordID) { record, error in
                if let error {
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }
    
    /// Esegue una query e restituisce i record trovati.
    /// - Parameter query: La query da eseguire
    /// - Returns: Array di record trovati
    func performQueryAsync(_ query: CKQuery) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            self.perform(query, inZoneWith: nil) { records, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: records ?? [])
            }
        }
    }
    
    /// Elimina un record per ID.
    /// - Parameter recordID: L'ID del record da eliminare
    func deleteRecordAsync(_ recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.delete(withRecordID: recordID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }
    
    /// Elimina un record per ID e restituisce l'ID eliminato.
    /// - Parameter recordID: L'ID del record da eliminare
    /// - Returns: L'ID del record eliminato
    func deleteRecordReturningIDAsync(_ recordID: CKRecord.ID) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            self.delete(withRecordID: recordID) { deletedID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: deletedID ?? recordID)
            }
        }
    }
}

// MARK: - CKContainer Async Extensions

extension CKContainer {
    
    /// Recupera lo stato dell'account iCloud in modo asincrono.
    func accountStatusAsync() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Recupera l'ID del record utente corrente.
    func fetchUserRecordIDAsync() async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: recordID ?? CKRecord.ID(recordName: "unknown"))
            }
        }
    }
}
