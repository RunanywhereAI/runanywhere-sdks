// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Model catalog — `RunAnywhere.registerModel(...)`, `availableModels`,
// `getCurrentModelId`, `loadModel`, etc. Backed by a process-wide
// in-memory registry. The C++ ModelRegistry singleton is the source of
// truth for runtime lookups; this Swift layer mirrors entries for the
// frontend so iOS sample apps can browse the catalog before any download.

import Foundation
import CRACommonsCore

// MARK: - Inference framework taxonomy

public enum InferenceFramework: String, Sendable, Codable, CaseIterable {
    case llamaCpp     = "llamacpp"
    case onnx         = "onnx"
    case whisperKit   = "whisperkit"
    case metalRT      = "metalrt"
    case genie        = "genie"
    case foundationModels = "foundation_models"
    case coreML       = "coreml"
    case mlx          = "mlx"
    case sherpa       = "sherpa"
    case unknown      = "unknown"
}

public enum ModelCategory: String, Sendable, Codable, CaseIterable {
    case llm
    case stt
    case tts
    case vad
    case embedding
    case vlm
    case diffusion
    case rerank
    case wakeword
    case unknown
}

public enum ModelArtifactType: Sendable, Codable {
    case singleFile
    case archive(format: String)   // "zip" | "tar.gz" | ...
    case multiFile

    private enum CodingKeys: String, CodingKey { case kind, format }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "archive":
            self = .archive(format: try c.decode(String.self, forKey: .format))
        case "multiFile": self = .multiFile
        default: self = .singleFile
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .singleFile:           try c.encode("singleFile", forKey: .kind)
        case .multiFile:            try c.encode("multiFile",  forKey: .kind)
        case .archive(let format):
            try c.encode("archive", forKey: .kind)
            try c.encode(format,    forKey: .format)
        }
    }
}

public struct ModelFileDescriptor: Sendable, Codable {
    public var url: URL
    public var relativePath: String
    public var sha256: String?
    public var sizeBytes: Int64?

    public init(url: URL, relativePath: String, sha256: String? = nil,
                sizeBytes: Int64? = nil) {
        self.url = url; self.relativePath = relativePath
        self.sha256 = sha256; self.sizeBytes = sizeBytes
    }
}

// MARK: - ModelInfo (the public catalog entry)

public struct ModelInfo: Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var url: URL?
    public var framework: InferenceFramework
    public var category: ModelCategory
    public var artifactType: ModelArtifactType
    public var memoryRequirement: Int64?
    public var supportsThinking: Bool
    public var modality: String?
    public var localPath: String?
    public var files: [ModelFileDescriptor]?

    public init(id: String, name: String, url: URL? = nil,
                framework: InferenceFramework = .llamaCpp,
                category: ModelCategory = .llm,
                artifactType: ModelArtifactType = .singleFile,
                memoryRequirement: Int64? = nil,
                supportsThinking: Bool = false,
                modality: String? = nil,
                localPath: String? = nil,
                files: [ModelFileDescriptor]? = nil) {
        self.id = id; self.name = name; self.url = url
        self.framework = framework; self.category = category
        self.artifactType = artifactType
        self.memoryRequirement = memoryRequirement
        self.supportsThinking = supportsThinking
        self.modality = modality
        self.localPath = localPath
        self.files = files
    }
}

// MARK: - LoRA adapter catalog

public struct LoRAAdapterConfig: Sendable {
    public var id: String
    public var name: String
    public var localPath: String
    public var baseModelId: String
    public var scale: Float

    public init(id: String, name: String, localPath: String,
                baseModelId: String, scale: Float = 1.0) {
        self.id = id; self.name = name; self.localPath = localPath
        self.baseModelId = baseModelId; self.scale = scale
    }
}

public struct LoraAdapterCatalogEntry: Sendable {
    public var id: String
    public var name: String
    public var url: URL
    public var baseModelId: String
    public var sha256: String?
    public var sizeBytes: Int64?

    public init(id: String, name: String, url: URL,
                baseModelId: String, sha256: String? = nil, sizeBytes: Int64? = nil) {
        self.id = id; self.name = name; self.url = url
        self.baseModelId = baseModelId; self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }
}

public struct LoRAAdapterInfo: Sendable {
    public var config: LoRAAdapterConfig
    public var loaded: Bool
    public init(config: LoRAAdapterConfig, loaded: Bool) {
        self.config = config; self.loaded = loaded
    }
}

public struct LoraCompatibilityResult: Sendable {
    public var compatible: Bool
    public var reason: String?
    public init(compatible: Bool, reason: String? = nil) {
        self.compatible = compatible; self.reason = reason
    }
}

public enum DownloadState: Sendable {
    case notStarted
    case downloading(progress: Double)
    case completed(localPath: String)
    case failed(message: String)
    case cancelled
}

// MARK: - Storage info

public struct StorageInfo: Sendable {
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var modelsBytes: Int64
    public var cacheBytes: Int64

    public init(totalBytes: Int64 = 0, freeBytes: Int64 = 0,
                modelsBytes: Int64 = 0, cacheBytes: Int64 = 0) {
        self.totalBytes = totalBytes; self.freeBytes = freeBytes
        self.modelsBytes = modelsBytes; self.cacheBytes = cacheBytes
    }
}

// MARK: - In-memory model registry (Swift side)

@MainActor
internal enum ModelCatalog {
    private static var entries: [String: ModelInfo] = [:]
    private static var loraEntries: [String: LoraAdapterCatalogEntry] = [:]
    private static var loadedLoraAdapters: [String: LoRAAdapterConfig] = [:]
    private static var pendingFlush: [() -> Void] = []

    static func register(_ info: ModelInfo) { entries[info.id] = info }
    static func registerLora(_ entry: LoraAdapterCatalogEntry) { loraEntries[entry.id] = entry }
    static func remove(_ id: String) { entries.removeValue(forKey: id) }

    static var allModels: [ModelInfo] { Array(entries.values) }
    static func model(id: String) -> ModelInfo? { entries[id] }

    static var allLoraEntries: [LoraAdapterCatalogEntry] { Array(loraEntries.values) }

    static var allRegisteredLoraAdapters: [LoRAAdapterConfig] {
        Array(loadedLoraAdapters.values)
    }

    static func setLoraLoaded(_ cfg: LoRAAdapterConfig) { loadedLoraAdapters[cfg.id] = cfg }
    static func setLoraUnloaded(_ id: String) { loadedLoraAdapters.removeValue(forKey: id) }
    static func clearLoraAdapters() { loadedLoraAdapters.removeAll() }

    static func adaptersForModel(_ modelId: String) -> [LoRAAdapterConfig] {
        loadedLoraAdapters.values.filter { $0.baseModelId == modelId }
    }

    static func enqueueFlush(_ work: @escaping () -> Void) { pendingFlush.append(work) }
    static func runPendingFlushes() {
        let work = pendingFlush; pendingFlush.removeAll()
        for w in work { w() }
    }
}

// MARK: - RunAnywhere.* extensions for the catalog

@MainActor
public extension RunAnywhere {

    // --- Registration -----------------------------------------------------

    static func registerModel(id: String, name: String, url: URL,
                               framework: InferenceFramework,
                               category: ModelCategory = .llm,
                               artifactType: ModelArtifactType = .singleFile,
                               memoryRequirement: Int64? = nil,
                               supportsThinking: Bool = false,
                               modality: String? = nil) {
        let info = ModelInfo(id: id, name: name, url: url,
                              framework: framework, category: category,
                              artifactType: artifactType,
                              memoryRequirement: memoryRequirement,
                              supportsThinking: supportsThinking,
                              modality: modality)
        ModelCatalog.register(info)
    }

    static func registerMultiFileModel(id: String, name: String,
                                        files: [ModelFileDescriptor],
                                        framework: InferenceFramework,
                                        category: ModelCategory = .llm,
                                        memoryRequirement: Int64? = nil) {
        let info = ModelInfo(id: id, name: name, url: nil,
                              framework: framework, category: category,
                              artifactType: .multiFile,
                              memoryRequirement: memoryRequirement,
                              files: files)
        ModelCatalog.register(info)
    }

    static func registerLoraAdapter(_ entry: LoraAdapterCatalogEntry) {
        ModelCatalog.registerLora(entry)
    }

    static func flushPendingRegistrations() async {
        await MainActor.run { ModelCatalog.runPendingFlushes() }
    }

    /// Scans `models_dir` on disk and returns the count of previously-downloaded
    /// model files matched against registered entries.
    static func discoverDownloadedModels() async -> Int {
        var found = 0
        for info in ModelCatalog.allModels {
            // Compute conventional path: models_dir/{framework}/{id}/<filename>
            var path: UnsafeMutablePointer<CChar>?
            let rc = info.framework.rawValue.withCString { fw -> Int32 in
                info.id.withCString { mid -> Int32 in
                    ra_file_model_path(fw, mid, &path)
                }
            }
            guard rc == RA_OK, let raw = path else { continue }
            let dir = String(cString: raw)
            ra_file_string_free(path)
            if FileManager.default.fileExists(atPath: dir) { found += 1 }
        }
        return found
    }

    // --- Catalog queries --------------------------------------------------

    static var availableModels: [ModelInfo] { ModelCatalog.allModels }

    static func availableModels(for framework: InferenceFramework) -> [ModelInfo] {
        ModelCatalog.allModels.filter { $0.framework == framework }
    }

    static func availableModels(for category: ModelCategory) -> [ModelInfo] {
        ModelCatalog.allModels.filter { $0.category == category }
    }

    static func getModelsForFramework(_ framework: InferenceFramework) -> [ModelInfo] {
        availableModels(for: framework)
    }

    static func getModelsForCategory(_ category: ModelCategory) -> [ModelInfo] {
        availableModels(for: category)
    }

    static func getRegisteredFrameworks() -> [InferenceFramework] {
        Array(Set(ModelCatalog.allModels.map { $0.framework }))
    }

    static func model(by id: String) -> ModelInfo? { ModelCatalog.model(id: id) }

    // --- Storage / cleanup ------------------------------------------------

    static func getStorageInfo() -> StorageInfo {
        var info = ra_storage_disk_space_t()
        var path: UnsafeMutablePointer<CChar>?
        _ = ra_file_models_dir(&path)
        defer { if let p = path { ra_file_string_free(p) } }
        if let raw = path {
            _ = String(cString: raw).withCString { ra_storage_disk_space_for($0, &info) }
        }
        let modelsBytes = path.map { ra_file_directory_size_bytes($0) } ?? 0
        var cachePath: UnsafeMutablePointer<CChar>?
        _ = ra_file_cache_dir(&cachePath)
        defer { if let p = cachePath { ra_file_string_free(p) } }
        let cacheBytes = cachePath.map { ra_file_directory_size_bytes($0) } ?? 0
        return StorageInfo(totalBytes: info.capacity_bytes,
                            freeBytes: info.available_bytes,
                            modelsBytes: modelsBytes,
                            cacheBytes: cacheBytes)
    }

    static func clearCache() -> Int64 { ra_file_clear_cache() }
    static func cleanTempFiles() -> Int64 { ra_file_clear_tmp() }

    static func deleteStoredModel(_ modelId: String,
                                    framework: InferenceFramework) -> Bool {
        var path: UnsafeMutablePointer<CChar>?
        let rc = framework.rawValue.withCString { fw in
            modelId.withCString { mid in
                ra_file_model_path(fw, mid, &path)
            }
        }
        defer { if let p = path { ra_file_string_free(p) } }
        guard rc == RA_OK, let raw = path else { return false }
        return ra_file_remove_path(String(cString: raw)) == RA_OK
    }

    static func getDownloadedModelsWithInfo() -> [ModelInfo] {
        ModelCatalog.allModels.filter { info in
            var path: UnsafeMutablePointer<CChar>?
            defer { if let p = path { ra_file_string_free(p) } }
            let rc = info.framework.rawValue.withCString { fw in
                info.id.withCString { mid in
                    ra_file_model_path(fw, mid, &path)
                }
            }
            guard rc == RA_OK, let raw = path else { return false }
            return FileManager.default.fileExists(atPath: String(cString: raw))
        }
    }

    // --- Loading helpers --------------------------------------------------

    /// Resolves a registered modelId to its on-disk path and loads it as the
    /// current LLM session. Use this from sample apps that don't track paths
    /// themselves.
    static func loadModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument("model not registered: \(modelId)")
        }
        var path: UnsafeMutablePointer<CChar>?
        defer { if let p = path { ra_file_string_free(p) } }
        let rc = info.framework.rawValue.withCString { fw in
            modelId.withCString { mid in ra_file_model_path(fw, mid, &path) }
        }
        guard rc == RA_OK, let raw = path else {
            throw RunAnywhereError.invalidArgument("could not resolve model path")
        }
        let resolved = info.localPath ?? String(cString: raw)
        try loadModel(modelId, modelPath: resolved, format: info.framework.modelFormat)
    }
}

internal extension InferenceFramework {
    var modelFormat: ModelFormat {
        switch self {
        case .llamaCpp:         return .gguf
        case .onnx, .sherpa:    return .onnx
        case .whisperKit:       return .whisperKit
        case .coreML:           return .coreML
        case .mlx:              return .mlxSafetensors
        default:                return .unknown
        }
    }
}
