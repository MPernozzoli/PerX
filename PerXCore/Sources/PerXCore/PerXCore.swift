// PerXCore - Shared models and utilities for PerX Hub and Client
// This package contains no UI dependencies

@_exported import Foundation

// Re-export all public types
// Models
public typealias _VaultFile = VaultFile
public typealias _VaultFileSource = VaultFileSource
public typealias _SinistroFolderStatus = SinistroFolderStatus
public typealias _SinistroFolder = SinistroFolder
public typealias _Job = Job
public typealias _JobType = JobType
public typealias _JobStatus = JobStatus
public typealias _JobPayload = JobPayload
public typealias _FileManifestEntry = FileManifestEntry
public typealias _LegacyChanges = LegacyChanges

// DTOs
public typealias _VaultFileDTO = VaultFileDTO
public typealias _JobDTO = JobDTO
public typealias _HealthResponse = HealthResponse

/// Version of PerXCore
public let PerXCoreVersion = "1.0.0"
