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
    case whisperKitCoreML = "whisperkit_coreml"
    case metalRT      = "metalrt"
    case genie        = "genie"
    case foundationModels = "foundation_models"
    case coreML       = "coreml"
    case mlx          = "mlx"
    case sherpa       = "sherpa"
    case whisperCpp   = "whispercpp"
    case unknown      = "unknown"

    /// Lowercase alias. The legacy SDK spelled `metalRT` as `metalrt`; the
    /// sample apps use the lowercase form. Provides both.
    public static var metalrt: InferenceFramework { .metalRT }
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

/// Model artifact shape — maps to how the downloader extracts it.
public enum ModelArtifactType: Sendable, Codable {
    case singleFile
    case archive(ArchiveFormat, structure: ArchiveStructure = .flat)
    case multiFile

    /// Legacy string-form overload. Kept for back-compat with earlier v2 SDKs
    /// that accepted `.archive(format: "tar.gz")`.
    public static func archive(format: String) -> ModelArtifactType {
        .archive(ArchiveFormat.from(rawString: format), structure: .flat)
    }

    private enum CodingKeys: String, CodingKey { case kind, format, structure }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "archive":
            let f = try c.decode(ArchiveFormat.self, forKey: .format)
            let s = (try? c.decode(ArchiveStructure.self, forKey: .structure)) ?? .flat
            self = .archive(f, structure: s)
        case "multiFile": self = .multiFile
        default: self = .singleFile
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .singleFile:           try c.encode("singleFile", forKey: .kind)
        case .multiFile:            try c.encode("multiFile",  forKey: .kind)
        case .archive(let f, let s):
            try c.encode("archive", forKey: .kind)
            try c.encode(f,         forKey: .format)
            try c.encode(s,         forKey: .structure)
        }
    }
}

public enum ArchiveFormat: String, Sendable, Codable {
    case zip
    case tar
    case tarGz    = "tar.gz"
    case tarBz2   = "tar.bz2"
    case tarXz    = "tar.xz"

    public static func from(rawString s: String) -> ArchiveFormat {
        switch s.lowercased() {
        case "zip":                 return .zip
        case "tar":                 return .tar
        case "tar.gz", "tgz":       return .tarGz
        case "tar.bz2":             return .tarBz2
        case "tar.xz":              return .tarXz
        default:                    return .zip
        }
    }
}

public enum ArchiveStructure: String, Sendable, Codable {
    /// Archive contents unpacked directly into the model dir.
    case flat
    /// Archive contains exactly one top-level directory; that directory is the model root.
    case nestedDirectory = "nested_directory"
    /// Model's layout is itself directory-based (e.g. CoreML .mlmodelc folder tree).
    case directoryBased  = "directory_based"
}

/// Semantic category of a model — what inference task it serves. Maps onto
/// `ModelCategory` but provides the richer Swift-level naming the legacy SDK
/// exposed (legacy enum was `.speechRecognition`, `.speechSynthesis`, etc.).
public enum Modality: String, Sendable, Codable, CaseIterable {
    case text
    case speechRecognition      = "speech_recognition"
    case speechSynthesis        = "speech_synthesis"
    case voiceActivityDetection = "voice_activity_detection"
    case embedding
    case multimodal
    case imageGeneration        = "image_generation"
    case wakeword

    public var category: ModelCategory {
        switch self {
        case .text:                    return .llm
        case .speechRecognition:       return .stt
        case .speechSynthesis:         return .tts
        case .voiceActivityDetection:  return .vad
        case .embedding:               return .embedding
        case .multimodal:              return .vlm
        case .imageGeneration:         return .diffusion
        case .wakeword:                return .wakeword
        }
    }
}

public struct ModelFileDescriptor: Sendable, Codable {
    public var url: URL
    /// Path relative to the model root where this file should be placed.
    public var relativePath: String
    public var sha256: String?
    public var sizeBytes: Int64?

    public init(url: URL, relativePath: String, sha256: String? = nil,
                sizeBytes: Int64? = nil) {
        self.url = url; self.relativePath = relativePath
        self.sha256 = sha256; self.sizeBytes = sizeBytes
    }

    /// Legacy initializer — the main SDK named the field `filename` (with the
    /// relative path being the filename itself). Kept for source compat.
    public init(url: URL, filename: String, sha256: String? = nil,
                sizeBytes: Int64? = nil) {
        self.init(url: url, relativePath: filename,
                  sha256: sha256, sizeBytes: sizeBytes)
    }

    /// Legacy read accessor: returns the trailing filename portion of the
    /// relative path so existing sample-app code that reads `.filename` works.
    public var filename: String {
        (relativePath as NSString).lastPathComponent
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

    /// Canonical v2 registration — accepts a rich `Modality` enum.
    /// The modality determines the default `category` when none is passed.
    static func registerModel(id: String, name: String, url: URL,
                               framework: InferenceFramework,
                               category: ModelCategory? = nil,
                               artifactType: ModelArtifactType = .singleFile,
                               memoryRequirement: Int64? = nil,
                               supportsThinking: Bool = false,
                               modality: Modality = .text) {
        let info = ModelInfo(
            id: id, name: name, url: url,
            framework: framework,
            category: category ?? modality.category,
            artifactType: artifactType,
            memoryRequirement: memoryRequirement,
            supportsThinking: supportsThinking,
            modality: modality.rawValue)
        ModelCatalog.register(info)
    }

    /// Legacy overload accepting `modality: String?` — kept for sample-app
    /// code that already passes a raw string.
    static func registerModel(id: String, name: String, url: URL,
                               framework: InferenceFramework,
                               category: ModelCategory = .llm,
                               artifactType: ModelArtifactType = .singleFile,
                               memoryRequirement: Int64? = nil,
                               supportsThinking: Bool = false,
                               modality modalityString: String?) {
        let info = ModelInfo(id: id, name: name, url: url,
                              framework: framework, category: category,
                              artifactType: artifactType,
                              memoryRequirement: memoryRequirement,
                              supportsThinking: supportsThinking,
                              modality: modalityString)
        ModelCatalog.register(info)
    }

    static func registerMultiFileModel(id: String, name: String,
                                        files: [ModelFileDescriptor],
                                        framework: InferenceFramework,
                                        category: ModelCategory? = nil,
                                        memoryRequirement: Int64? = nil,
                                        modality: Modality = .text) {
        let info = ModelInfo(
            id: id, name: name, url: nil,
            framework: framework,
            category: category ?? modality.category,
            artifactType: .multiFile,
            memoryRequirement: memoryRequirement,
            modality: modality.rawValue,
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

    /// Async parenthesised overload matching the legacy SDK shape. Lets
    /// sample apps write `try await RunAnywhere.availableModels()` against
    /// code originally written for the main-branch SDK.
    static func availableModels() async -> [ModelInfo] { ModelCatalog.allModels }

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

    /// Legacy name for `getStorageInfo()`.
    static func storageInfo() -> StorageInfo { getStorageInfo() }

    /// Delete a model by id. Looks up the framework from the catalog.
    @discardableResult
    static func deleteModel(_ modelId: String) async -> Bool {
        guard let info = ModelCatalog.model(id: modelId) else { return false }
        return deleteStoredModel(modelId, framework: info.framework)
    }

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

    // --- Framework × category matrix ---------------------------------
    //
    // Thin pass-through wrappers over `ra_model.h`. Useful for sample-app
    // UI that needs to gate buttons on "is this (framework, category)
    // combo supported by any engine?" without hard-coding the matrix.

    /// Returns true if `framework` has an engine slot implementing `category`.
    /// Matches the curated table in `core/abi/ra_model.cpp` shipped with
    /// the XCFramework — consistent across Swift/Kotlin/Dart/TS/Web.
    static func frameworkSupports(_ framework: InferenceFramework,
                                     category: ModelCategory) -> Bool {
        framework.rawValue.withCString { fw in
            category.rawValue.withCString { cat in
                ra_framework_supports(fw, cat) != 0
            }
        }
    }

    /// Detect a model format from a URL or local path (extension-based).
    static func detectModelFormat(from urlOrPath: String) -> ModelFormat {
        let raw = urlOrPath.withCString { ra_model_detect_format($0) }
        switch Int(raw) {
        case Int(RA_FORMAT_GGUF):             return .gguf
        case Int(RA_FORMAT_ONNX):              return .onnx
        case Int(RA_FORMAT_COREML):            return .coreml
        case Int(RA_FORMAT_MLX_SAFETENSORS):   return .mlxSafetensors
        case Int(RA_FORMAT_WHISPERKIT):        return .whisperKit
        default:                               return .unknown
        }
    }

    /// Infer the semantic category of a model from its id (heuristic).
    static func inferModelCategory(from modelId: String) -> ModelCategory {
        let raw = modelId.withCString { ra_model_infer_category($0) }
        switch Int(raw) {
        case Int(RA_MODEL_CATEGORY_LLM):        return .llm
        case Int(RA_MODEL_CATEGORY_STT):        return .stt
        case Int(RA_MODEL_CATEGORY_TTS):        return .tts
        case Int(RA_MODEL_CATEGORY_VAD):        return .vad
        case Int(RA_MODEL_CATEGORY_EMBEDDING):  return .embedding
        case Int(RA_MODEL_CATEGORY_VLM):        return .vlm
        case Int(RA_MODEL_CATEGORY_DIFFUSION):  return .diffusion
        case Int(RA_MODEL_CATEGORY_RERANK):     return .rerank
        case Int(RA_MODEL_CATEGORY_WAKEWORD):   return .wakeword
        default:                                return .unknown
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
        case .llamaCpp, .whisperCpp:                 return .gguf
        case .onnx, .sherpa:                         return .onnx
        case .whisperKit, .whisperKitCoreML:         return .whisperKit
        case .coreML:                                return .coreml
        case .mlx:                                   return .mlxSafetensors
        default:                                     return .unknown
        }
    }
}

// Public alias since the legacy enum case was capitalised .coreML.
public extension ModelFormat {
    static var coreML: ModelFormat { .coreml }
}

// MARK: - DownloadProgress + RunAnywhere.downloadModel(_:) streaming

public struct DownloadProgress: Sendable {
    public enum State: Sendable {
        case pending
        case downloading
        case extracting
        case complete(localPath: String)
        case failed(message: String)
        case cancelled
    }
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public var percent: Double
    public var state: State

    public init(bytesDownloaded: Int64 = 0, totalBytes: Int64 = 0,
                percent: Double = 0, state: State = .pending) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.percent = percent
        self.state = state
    }
}

@MainActor
public extension RunAnywhere {

    /// Stream progress for a registered model download. Drives the URLSession
    /// download via the platform adapter and maps its callback fire rate into
    /// `DownloadProgress` chunks. Terminates with `.complete(localPath:)` or
    /// `.failed(message:)` and then finishes the stream.
    static func downloadModel(_ modelId: String)
        -> AsyncThrowingStream<DownloadProgress, Error>
    {
        AsyncThrowingStream { continuation in
            guard let info = ModelCatalog.model(id: modelId) else {
                continuation.finish(throwing: RunAnywhereError.invalidArgument(
                    "model not registered: \(modelId)"))
                return
            }
            guard let url = info.url else {
                continuation.finish(throwing: RunAnywhereError.invalidArgument(
                    "model has no download URL: \(modelId)"))
                return
            }

            // Compute destination path via ra_file_model_path.
            var path: UnsafeMutablePointer<CChar>?
            let rc = info.framework.rawValue.withCString { fw in
                modelId.withCString { mid in
                    ra_file_model_path(fw, mid, &path)
                }
            }
            guard rc == RA_OK, let raw = path else {
                continuation.finish(throwing: RunAnywhereError.invalidArgument(
                    "could not resolve destination path"))
                return
            }
            let destPath = String(cString: raw)
            ra_file_string_free(path)

            // Use Foundation URLSession so we get KVO progress today,
            // even before the full platform-adapter download upgrade lands.
            Task.detached {
                do {
                    continuation.yield(DownloadProgress(state: .downloading))
                    let (tmpURL, _) = try await URLSession.shared.download(from: url)
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: destPath).deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(atPath: destPath)
                    try FileManager.default.moveItem(
                        at: tmpURL, to: URL(fileURLWithPath: destPath))
                    let size = (try? FileManager.default.attributesOfItem(
                        atPath: destPath)[.size] as? Int64) ?? 0
                    continuation.yield(DownloadProgress(
                        bytesDownloaded: size, totalBytes: size, percent: 1.0,
                        state: .complete(localPath: destPath)))
                    continuation.finish()
                } catch {
                    continuation.yield(DownloadProgress(
                        state: .failed(message: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - LoRAAdapterCatalog facade

/// Legacy-named LoRA catalog entry point. Sample apps call
/// `LoRAAdapterCatalog.registerAll()` at startup; this forwards to the
/// catalog's flush pass so any adapter entries enqueued before the SDK
/// was fully initialised get applied.
@MainActor
public enum LoRAAdapterCatalog {
    /// Runs any pending registrations queued into the catalog. No-op if
    /// there are none.
    public static func registerAll() async {
        ModelCatalog.runPendingFlushes()
    }

    /// Enumerate all registered LoRA catalog entries.
    public static var allEntries: [LoraAdapterCatalogEntry] {
        ModelCatalog.allLoraEntries
    }
}
