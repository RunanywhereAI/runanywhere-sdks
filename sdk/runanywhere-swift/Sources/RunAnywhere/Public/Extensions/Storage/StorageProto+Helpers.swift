//
//  StorageProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Storage proto types.
//

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

    // Aliases `totalSpace` / `freeSpace` / `usedSpace` removed — shadowed
    // the canonical proto field names (`totalBytes`/`freeBytes`/`usedBytes`)
    // without semantic value. Per swift.md SWIFT-DUP-STORAGE-ALIASES.

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

    // `documentsSize` / `cacheSize` / `appSupportSize` / `totalSize` aliases
    // removed. Per swift.md SWIFT-DUP-STORAGE-ALIASES — canonical proto
    // field names (`documentsBytes`/`cacheBytes`/`appSupportBytes`/
    // `totalBytes`) are what app code should use.
}

// MARK: - RAStorageInfo

extension RAStorageInfo {
    public static let empty: RAStorageInfo = {
        var info = RAStorageInfo()
        info.app = RAAppStorageInfo()
        info.device = RADeviceStorageInfo()
        info.models = []
        info.totalModels = 0
        info.totalModelsBytes = 0
        return info
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

}

// MARK: - RAModelStorageMetrics

extension RAModelStorageMetrics {
    public init(modelID: String, sizeOnDiskBytes: Int64, lastUsedMs: Int64? = nil) {
        self.init()
        self.modelID = modelID
        self.sizeOnDiskBytes = sizeOnDiskBytes
        if let lastUsedMs { self.lastUsedMs = lastUsedMs }
    }

    // `modelId` / `sizeOnDisk` / `lastUsed` aliases removed — pure renames of
    // canonical proto field names (`modelID`/`sizeOnDiskBytes`/`lastUsedMs`)
    // with no consumer usage. Per swift.md SWIFT-DUP-STORAGE-ALIASES.
}

// MARK: - RAStorageAvailability

extension RAStorageAvailability {
    // `hasWarning` / `requiredSpace` / `availableSpace` aliases removed — pure
    // renames of canonical proto field names (`hasWarningMessage`/
    // `requiredBytes`/`availableBytes`). Per swift.md SWIFT-DUP-STORAGE-ALIASES.

    public static func make(
        isAvailable: Bool,
        requiredBytes: Int64,
        availableBytes: Int64,
        recommendation: String? = nil
    ) -> RAStorageAvailability {
        var availability = RAStorageAvailability()
        availability.isAvailable = isAvailable
        availability.requiredBytes = requiredBytes
        availability.availableBytes = availableBytes
        if let rec = recommendation { availability.recommendation = rec }
        return availability
    }
}
