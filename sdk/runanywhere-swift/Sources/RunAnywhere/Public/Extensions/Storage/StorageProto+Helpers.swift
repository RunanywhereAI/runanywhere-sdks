//
//  StorageProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Storage proto types.
//

import Foundation

// MARK: - RADeviceStorageInfo

extension RADeviceStorageInfo {
    public init(totalBytes: Int64, freeBytes: Int64, usedBytes: Int64) {
        self.init()
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.usedPercent = totalBytes > 0
            ? Float(Double(usedBytes) / Double(totalBytes) * 100.0)
            : 0.0
    }

    public var totalSpace: Int64 {
        get { totalBytes }
        set { totalBytes = newValue }
    }

    public var freeSpace: Int64 {
        get { freeBytes }
        set { freeBytes = newValue }
    }

    public var usedSpace: Int64 {
        get { usedBytes }
        set { usedBytes = newValue }
    }

    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }
}

// MARK: - RAAppStorageInfo

extension RAAppStorageInfo {
    public init(documentsBytes: Int64, cacheBytes: Int64, appSupportBytes: Int64, totalBytes: Int64) {
        self.init()
        self.documentsBytes = documentsBytes
        self.cacheBytes = cacheBytes
        self.appSupportBytes = appSupportBytes
        self.totalBytes = totalBytes
    }

    public var documentsSize: Int64 {
        get { documentsBytes }
        set { documentsBytes = newValue }
    }

    public var cacheSize: Int64 {
        get { cacheBytes }
        set { cacheBytes = newValue }
    }

    public var appSupportSize: Int64 {
        get { appSupportBytes }
        set { appSupportBytes = newValue }
    }

    public var totalSize: Int64 {
        get { totalBytes }
        set { totalBytes = newValue }
    }
}

// MARK: - RAStorageInfo

extension RAStorageInfo {
    public static let empty: RAStorageInfo = {
        var s = RAStorageInfo()
        s.app = RAAppStorageInfo()
        s.device = RADeviceStorageInfo()
        s.models = []
        s.totalModels = 0
        s.totalModelsBytes = 0
        return s
    }()

    public var totalModelsSizeBytes: Int64 {
        models.reduce(0) { $0 + $1.sizeOnDiskBytes }
    }

    public var appStorage: RAAppStorageInfo {
        get { app }
        set { app = newValue }
    }

    public var deviceStorage: RADeviceStorageInfo {
        get { device }
        set { device = newValue }
    }

    public var totalModelsSize: Int64 {
        totalModelsBytes > 0 ? totalModelsBytes : totalModelsSizeBytes
    }

    public var modelCount: Int { models.count }

    public var storedModels: [RAStoredModel] {
        models.map { metrics in
            var model = RAStoredModel()
            model.modelID = metrics.modelID
            model.name = metrics.modelID
            model.sizeBytes = metrics.sizeOnDiskBytes
            return model
        }
    }
}

// MARK: - RAModelStorageMetrics

extension RAModelStorageMetrics {
    public init(modelID: String, sizeOnDiskBytes: Int64, lastUsedMs: Int64? = nil) {
        self.init()
        self.modelID = modelID
        self.sizeOnDiskBytes = sizeOnDiskBytes
        if let lastUsedMs { self.lastUsedMs = lastUsedMs }
    }

    public var modelId: String {
        get { modelID }
        set { modelID = newValue }
    }

    public var sizeOnDisk: Int64 {
        get { sizeOnDiskBytes }
        set { sizeOnDiskBytes = newValue }
    }

    public var lastUsed: Date? {
        guard hasLastUsedMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUsedMs) / 1000.0)
    }
}

// MARK: - RAStoredModel

extension RAStoredModel: Identifiable {
    public var id: String { modelID }

    public var size: Int64 {
        get { sizeBytes }
        set { sizeBytes = newValue }
    }

    public var path: URL { URL(fileURLWithPath: localPath.isEmpty ? "/unknown" : localPath) }

    public var createdDate: Date {
        guard hasDownloadedAtMs else { return Date(timeIntervalSince1970: 0) }
        return Date(timeIntervalSince1970: TimeInterval(downloadedAtMs) / 1000.0)
    }

    public var checksum: String? { nil }
    public var format: ModelFormat { .unknown }
    public var framework: InferenceFramework? { nil }
    public var modelDescription: String? { nil }
}

// MARK: - RAStorageAvailability

extension RAStorageAvailability {
    public var hasWarning: Bool { hasWarningMessage }

    public var requiredSpace: Int64 {
        get { requiredBytes }
        set { requiredBytes = newValue }
    }

    public var availableSpace: Int64 {
        get { availableBytes }
        set { availableBytes = newValue }
    }

    public static func make(
        isAvailable: Bool,
        requiredBytes: Int64,
        availableBytes: Int64,
        recommendation: String? = nil
    ) -> RAStorageAvailability {
        var s = RAStorageAvailability()
        s.isAvailable = isAvailable
        s.requiredBytes = requiredBytes
        s.availableBytes = availableBytes
        if let rec = recommendation { s.recommendation = rec }
        return s
    }
}
