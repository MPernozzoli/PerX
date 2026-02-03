import Vapor
import PerXCore

// MARK: - Vapor Content conformance

// Estendi i DTO di PerXCore per essere usati con Vapor

extension VaultFileDTO: @retroactive Content {}
extension SinistroFolderDTO: @retroactive Content {}
extension JobDTO: @retroactive Content {}
extension JobCompleteRequest: @retroactive Content {}
extension JobFailRequest: @retroactive Content {}
extension FileUploadRequest: @retroactive Content {}
extension HealthResponse: @retroactive Content {}
extension LegacyChangesDTO: @retroactive Content {}
extension LegacyScanResult: @retroactive Content {}
extension LegacyFileInfo: @retroactive Content {}
extension AttachmentDTO: @retroactive Content {}
extension ScheduledEmailDTO: @retroactive Content {}
extension HubStatsResponse: @retroactive Content {}
extension HubStatsResponse.JobStats: @retroactive Content {}
extension HubStatsResponse.EmailStats: @retroactive Content {}
extension HubStatsResponse.AttachmentStats: @retroactive Content {}
extension TaskDTO: @retroactive Content {}
extension EmailDTO: @retroactive Content {}
extension PerXCore.EmailDetailDTO: @retroactive Content {}
extension EmailProcessedResponse: @retroactive Content {}
extension SinistroDTO: @retroactive Content {}
extension StateChangeResponse: @retroactive Content {}
