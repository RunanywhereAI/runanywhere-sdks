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

    public var modelCount: Int { models.count }
}

// MARK: - RAModelStorageMetrics

extension RAModelStorageMetrics {
    public var lastUsed: Date? {
        guard hasLastUsedMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUsedMs) / 1000.0)
    }
}

// MARK: - RAStorageAvailability

extension RAStorageAvailability {
    public var hasWarning: Bool { hasWarningMessage }

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
