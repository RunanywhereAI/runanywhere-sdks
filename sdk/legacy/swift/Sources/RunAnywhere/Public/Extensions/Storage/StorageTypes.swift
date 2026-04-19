//
//  StorageTypes.swift
//  RunAnywhere SDK
//
//  Consolidated storage-related types for public API.
//  Includes: storage info, configuration, availability, and model storage metrics.
//

import Foundation

// MARK: - Device Storage

/// Device storage information
public struct DeviceStorageInfo: Sendable {
    /// Total device storage space in bytes
    public let totalSpace: Int64

    /// Free space available in bytes
    public let freeSpace: Int64

    /// Used space in bytes
    public let usedSpace: Int64

    /// Percentage of storage used (0-100)
    public var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    public init(totalSpace: Int64, freeSpace: Int64, usedSpace: Int64) {
        self.totalSpace = totalSpace
        self.freeSpace = freeSpace
        self.usedSpace = usedSpace
    }
}

// MARK: - App Storage

/// App storage breakdown by directory type
public struct AppStorageInfo: Sendable {
    /// Documents directory size in bytes
    public let documentsSize: Int64

    /// Cache directory size in bytes
    public let cacheSize: Int64

    /// Application Support directory size in bytes
    public let appSupportSize: Int64

    /// Total app storage in bytes
    public let totalSize: Int64

    public init(documentsSize: Int64, cacheSize: Int64, appSupportSize: Int64, totalSize: Int64) {
        self.documentsSize = documentsSize
        self.cacheSize = cacheSize
        self.appSupportSize = appSupportSize
        self.totalSize = totalSize
    }
}

// MARK: - Model Storage Metrics

/// Storage metrics for a single model
/// All model metadata (id, name, framework, artifactType, etc.) is in ModelInfo
/// This struct adds the on-disk storage size
public struct ModelStorageMetrics: Sendable {
    /// The model info (contains id, framework, localPath, artifactType, etc.)
    public let model: ModelInfo

    /// Actual size on disk in bytes (may differ from downloadSize after extraction)
    public let sizeOnDisk: Int64

    public init(model: ModelInfo, sizeOnDisk: Int64) {
        self.model = model
        self.sizeOnDisk = sizeOnDisk
    }
}

// MARK: - Stored Model (Backward Compatible)

/// Backward-compatible stored model view
/// Provides a simple view of a stored model with computed properties
public struct StoredModel: Sendable, Identifiable {
    /// Underlying model info
    public let modelInfo: ModelInfo

    /// Size on disk in bytes
    public let size: Int64

    /// Model ID
    public var id: String { modelInfo.id }

    /// Model name
    public var name: String { modelInfo.name }

    /// Model format
    public var format: ModelFormat { modelInfo.format }

    /// Inference framework
    public var framework: InferenceFramework? { modelInfo.framework }

    /// Model description
    public var description: String? { modelInfo.description }

    /// Path to the model on disk
    public var path: URL { modelInfo.localPath ?? URL(fileURLWithPath: "/unknown") }

    /// Checksum (from download info if available)
    public var checksum: String? { nil }

    /// Created date (use current date as fallback)
    public var createdDate: Date { Date() }

    public init(modelInfo: ModelInfo, size: Int64) {
        self.modelInfo = modelInfo
        self.size = size
    }

    /// Create from ModelStorageMetrics
    public init(from metrics: ModelStorageMetrics) {
        self.modelInfo = metrics.model
        self.size = metrics.sizeOnDisk
    }
}

// MARK: - Storage Info (Aggregate)

/// Complete storage information including device, app, and model storage
public struct StorageInfo: Sendable {
    /// App storage usage
    public let appStorage: AppStorageInfo

    /// Device storage capacity
    public let deviceStorage: DeviceStorageInfo

    /// Storage metrics for each downloaded model
    public let models: [ModelStorageMetrics]

    /// Total size of all models
    public var totalModelsSize: Int64 {
        models.reduce(0) { $0 + $1.sizeOnDisk }
    }

    /// Number of stored models
    public var modelCount: Int {
        models.count
    }

    /// Stored models array (backward compatible)
    public var storedModels: [StoredModel] {
        models.map { StoredModel(from: $0) }
    }

    /// Empty storage info
    public static let empty = StorageInfo(
        appStorage: AppStorageInfo(documentsSize: 0, cacheSize: 0, appSupportSize: 0, totalSize: 0),
        deviceStorage: DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0),
        models: []
    )

    public init(
        appStorage: AppStorageInfo,
        deviceStorage: DeviceStorageInfo,
        models: [ModelStorageMetrics]
    ) {
        self.appStorage = appStorage
        self.deviceStorage = deviceStorage
        self.models = models
    }
}

// MARK: - Storage Availability

/// Storage availability check result
public struct StorageAvailability: Sendable {
    /// Whether storage is available for the requested operation
    public let isAvailable: Bool

    /// Required space in bytes
    public let requiredSpace: Int64

    /// Available space in bytes
    public let availableSpace: Int64

    /// Whether there's a warning (e.g., low space)
    public let hasWarning: Bool

    /// Recommendation message if any
    public let recommendation: String?

    public init(
        isAvailable: Bool,
        requiredSpace: Int64,
        availableSpace: Int64,
        hasWarning: Bool,
        recommendation: String?
    ) {
        self.isAvailable = isAvailable
        self.requiredSpace = requiredSpace
        self.availableSpace = availableSpace
        self.hasWarning = hasWarning
        self.recommendation = recommendation
    }
}
