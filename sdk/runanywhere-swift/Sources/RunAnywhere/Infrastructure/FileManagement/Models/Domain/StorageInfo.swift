import Foundation

/// Simple storage metrics for a single model
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

/// Backward-compatible StoredModel type
/// Provides a simple view of a stored model with computed properties
public struct StoredModel: Sendable, Identifiable {
    /// Underlying model info
    public let modelInfo: ModelInfo

    /// Size on disk
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

/// Model storage summary (total size of all models)
public struct ModelStorageSummary: Sendable {
    /// Total size of all models
    public let totalSize: Int64

    /// Number of models
    public let modelCount: Int

    public init(totalSize: Int64, modelCount: Int) {
        self.totalSize = totalSize
        self.modelCount = modelCount
    }
}

/// Storage information - simple metrics
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

    /// Model storage summary (backward compatible)
    public var modelStorage: ModelStorageSummary {
        ModelStorageSummary(totalSize: totalModelsSize, modelCount: modelCount)
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
