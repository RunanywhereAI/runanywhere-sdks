// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Storage-related public types shared between the sample UI and the
// SDK. `StoredModel` describes a single on-disk model artifact;
// `StorageInfo` extensions add main-branch field names.

import Foundation

/// Compact descriptor for a model that exists on disk under the SDK's
/// managed models directory.
public struct StoredModel: Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Main-branch sample expects an optional framework so it can guard
    /// with `guard let framework = model.framework`. Kept optional so
    /// placeholder / built-in entries that lack a framework still surface.
    public var framework: InferenceFramework?
    public var category: ModelCategory
    public var sizeBytes: Int64
    /// On-disk location as a URL — sample UIs access `.path` for display
    /// and pass the value to `FileManager` methods expecting URLs.
    public var path: URL
    public var createdDate: Date

    /// Main-branch alias for `sizeBytes`.
    public var size: Int64 { sizeBytes }

    /// File format inferred from the path extension. Sample UIs render
    /// this as a short badge ("gguf", "bin", etc.).
    public var format: ModelFileFormat {
        ModelFileFormat(path: path.path)
    }

    /// Optional descriptive text surfaced by storage UI.
    public var description: String? { nil }

    /// SHA-256 checksum of the model artifact, when known.
    public var checksum: String? { nil }

    public init(info: ModelInfo, sizeBytes: Int64, path: String,
                createdDate: Date = Date()) {
        self.id = info.id
        self.name = info.name
        self.framework = info.framework
        self.category = info.category
        self.sizeBytes = sizeBytes
        self.path = URL(fileURLWithPath: path)
        self.createdDate = createdDate
    }
}

/// Aggregate app-storage footprint used by sample UIs.
public struct AppStorageInfo: Sendable {
    public var totalSize: Int64
    public var modelsSize: Int64
    public var cacheSize: Int64
    public init(totalSize: Int64, modelsSize: Int64, cacheSize: Int64) {
        self.totalSize = totalSize
        self.modelsSize = modelsSize
        self.cacheSize = cacheSize
    }
}

public extension StorageInfo {
    /// Total storage consumed by the SDK on disk (models + cache).
    var appStorage: AppStorageInfo {
        AppStorageInfo(totalSize: modelsBytes + cacheBytes,
                        modelsSize: modelsBytes,
                        cacheSize: cacheBytes)
    }

    /// Device-wide total/free bytes tuple. `.totalSize` and `.freeSpace`
    /// aliases match the main-branch sample spelling.
    var deviceStorage: DeviceStorage {
        DeviceStorage(totalSize: totalBytes, freeSpace: freeBytes)
    }

    /// Models currently resident on disk. Accessed via a MainActor hop
    /// on the underlying ModelCatalog.
    @MainActor
    var storedModels: [StoredModel] { ModelCatalog.storedModels }

    /// Same as `modelsBytes`; exposed under main's spelling.
    var totalModelsSize: Int64 { modelsBytes }
}

/// Typed pair of device-storage fields used by `StorageInfo.deviceStorage`.
public struct DeviceStorage: Sendable {
    public var totalSize: Int64
    public var freeSpace: Int64
    public init(totalSize: Int64, freeSpace: Int64) {
        self.totalSize = totalSize; self.freeSpace = freeSpace
    }
}

/// Model artifact format inferred from a file extension — matches the
/// main-branch sample's storage UI badge.
public struct ModelFileFormat: Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        self.rawValue = ext.isEmpty ? "unknown" : ext
    }
}
