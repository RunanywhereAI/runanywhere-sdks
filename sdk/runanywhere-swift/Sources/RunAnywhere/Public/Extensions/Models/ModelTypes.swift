//
//  ModelTypes.swift
//  RunAnywhere SDK
//
//  Public types for model management. Thin wrappers over C++ types in
//  rac_model_types.h. Business logic (format support, capability checks)
//  lives in C++.
//
//  GAP 01 Phase 2: enums below are typealiases for the IDL-generated
//  `RAModelSource`, `RAModelFormat`, `RAModelCategory`,
//  `RAInferenceFramework`, `RAArchiveType`, `RAArchiveStructure`
//  (idl/model_types.proto). Hand-written case sets were removed; extensions
//  preserve the public API surface: rawValue-style JSON encoding, display
//  names, analytics keys, C-bridge converters, and the
//  `requiresContextLength` / `supportsThinking` semantics previously on
//  `ModelCategory`.
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Typealiases to proto-generated enums

public typealias ModelSource = RAModelSource
public typealias ModelFormat = RAModelFormat
public typealias ModelCategory = RAModelCategory
public typealias InferenceFramework = RAInferenceFramework
public typealias ArchiveType = RAArchiveType
public typealias ArchiveStructure = RAArchiveStructure

// MARK: - ModelSource
//
// Note: `SwiftProtobuf.Enum` already refines `Sendable`, so no extra
// `@unchecked Sendable` is required on the typealiased enums.

extension RAModelSource: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "remote": self = .remote
        case "local":  self = .local
        default:       self = .unspecified
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

public extension RAModelSource {
    /// Canonical lowercase wire string (JSON compat).
    var wireString: String {
        switch self {
        case .remote:       return "remote"
        case .local:        return "local"
        default:            return "unspecified"
        }
    }
}

// MARK: - ModelFormat

extension RAModelFormat: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAModelFormat.fromWireString(raw) ?? .unknown
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

public extension RAModelFormat {
    /// Canonical lowercase wire string (JSON compat).
    var wireString: String {
        switch self {
        case .gguf:         return "gguf"
        case .ggml:         return "ggml"
        case .onnx:         return "onnx"
        case .ort:          return "ort"
        case .bin:          return "bin"
        case .coreml:       return "coreml"
        case .mlmodel:      return "mlmodel"
        case .mlpackage:    return "mlpackage"
        case .tflite:       return "tflite"
        case .safetensors:  return "safetensors"
        case .qnnContext:   return "qnn_context"
        case .zip:          return "zip"
        case .folder:       return "folder"
        case .proprietary:  return "proprietary"
        case .unknown:      return "unknown"
        default:            return "unknown"
        }
    }

    static func fromWireString(_ s: String) -> RAModelFormat? {
        switch s.lowercased() {
        case "gguf":                return .gguf
        case "ggml":                return .ggml
        case "onnx":                return .onnx
        case "ort":                 return .ort
        case "bin":                 return .bin
        case "coreml":              return .coreml
        case "mlmodel":             return .mlmodel
        case "mlpackage":           return .mlpackage
        case "tflite":              return .tflite
        case "safetensors":         return .safetensors
        case "qnn_context":         return .qnnContext
        case "zip":                 return .zip
        case "folder":              return .folder
        case "proprietary":         return .proprietary
        case "", "unknown":         return .unknown
        default:                    return nil
        }
    }
}

// MARK: - ModelCategory

extension RAModelCategory: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAModelCategory.fromWireString(raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

public extension RAModelCategory {
    /// Canonical kebab-case wire string (JSON compat).
    var wireString: String {
        switch self {
        case .language:                 return "language"
        case .speechRecognition:        return "speech-recognition"
        case .speechSynthesis:          return "speech-synthesis"
        case .vision:                   return "vision"
        case .imageGeneration:          return "image-generation"
        case .multimodal:               return "multimodal"
        case .audio:                    return "audio"
        case .embedding:                return "embedding"
        case .voiceActivityDetection:   return "voice-activity-detection"
        default:                        return "unspecified"
        }
    }

    static func fromWireString(_ s: String) -> RAModelCategory? {
        switch s.lowercased() {
        case "language":                    return .language
        case "speech-recognition":          return .speechRecognition
        case "speech-synthesis":            return .speechSynthesis
        case "vision":                      return .vision
        case "image-generation":            return .imageGeneration
        case "multimodal":                  return .multimodal
        case "audio":                       return .audio
        case "embedding":                   return .embedding
        case "voice-activity-detection":    return .voiceActivityDetection
        default:                            return nil
        }
    }

    /// Whether this category typically requires a context length.
    /// Matches `rac_model_category_requires_context_length()` on the C side.
    var requiresContextLength: Bool {
        switch self {
        case .language, .multimodal:
            return true
        default:
            return false
        }
    }

    /// Whether this category typically supports thinking/reasoning.
    /// Matches `rac_model_category_supports_thinking()` on the C side.
    var supportsThinking: Bool {
        switch self {
        case .language, .multimodal:
            return true
        default:
            return false
        }
    }
}

// MARK: - InferenceFramework

extension RAInferenceFramework: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let parsed = RAInferenceFramework(caseInsensitive: raw) {
            self = parsed
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

public extension RAInferenceFramework {
    /// Canonical PascalCase wire string matching the original Swift raw values
    /// used in existing JSON payloads.
    var wireString: String {
        switch self {
        case .onnx:                return "ONNX"
        case .sherpa:              return "Sherpa"
        case .llamaCpp:            return "LlamaCpp"
        case .foundationModels:    return "FoundationModels"
        case .systemTts:           return "SystemTTS"
        case .fluidAudio:          return "FluidAudio"
        case .coreml:              return "CoreML"
        case .mlx:                 return "MLX"
        case .whisperkitCoreml:    return "WhisperKitCoreML"
        case .metalrt:             return "MetalRT"
        case .genie:               return "Genie"
        case .tflite:              return "TFLite"
        case .executorch:          return "ExecuTorch"
        case .mediapipe:           return "MediaPipe"
        case .mlc:                 return "MLC"
        case .picoLlm:             return "PicoLLM"
        case .piperTts:            return "PiperTTS"
        case .whisperkit:          return "WhisperKit"
        case .openaiWhisper:       return "OpenAIWhisper"
        case .swiftTransformers:   return "SwiftTransformers"
        case .builtIn:             return "BuiltIn"
        case .none:                return "None"
        case .unknown:             return "Unknown"
        default:                   return "Unknown"
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .onnx:                return "ONNX Runtime"
        case .sherpa:              return "Sherpa-ONNX"
        case .llamaCpp:            return "llama.cpp"
        case .foundationModels:    return "Foundation Models"
        case .systemTts:           return "System TTS"
        case .fluidAudio:          return "FluidAudio"
        case .coreml:              return "Core ML"
        case .mlx:                 return "MLX"
        case .whisperkitCoreml:    return "WhisperKit CoreML"
        case .metalrt:             return "MetalRT"
        case .genie:               return "Genie"
        case .tflite:              return "TFLite"
        case .executorch:          return "ExecuTorch"
        case .mediapipe:           return "MediaPipe"
        case .mlc:                 return "MLC"
        case .picoLlm:             return "PicoLLM"
        case .piperTts:            return "Piper TTS"
        case .whisperkit:          return "WhisperKit"
        case .openaiWhisper:       return "OpenAI Whisper"
        case .swiftTransformers:   return "Swift Transformers"
        case .builtIn:             return "Built-in"
        case .none:                return "None"
        case .unknown:             return "Unknown"
        default:                   return "Unknown"
        }
    }

    /// Snake_case key for analytics/telemetry.
    var analyticsKey: String {
        switch self {
        case .onnx:                return "onnx"
        case .sherpa:              return "sherpa"
        case .llamaCpp:            return "llama_cpp"
        case .foundationModels:    return "foundation_models"
        case .systemTts:           return "system_tts"
        case .fluidAudio:          return "fluid_audio"
        case .coreml:              return "coreml"
        case .mlx:                 return "mlx"
        case .whisperkitCoreml:    return "whisperkit_coreml"
        case .metalrt:             return "metalrt"
        case .genie:               return "genie"
        case .tflite:              return "tflite"
        case .executorch:          return "executorch"
        case .mediapipe:           return "mediapipe"
        case .mlc:                 return "mlc"
        case .picoLlm:             return "pico_llm"
        case .piperTts:            return "piper_tts"
        case .whisperkit:          return "whisperkit"
        case .openaiWhisper:       return "openai_whisper"
        case .swiftTransformers:   return "swift_transformers"
        case .builtIn:             return "built_in"
        case .none:                return "none"
        case .unknown:             return "unknown"
        default:                   return "unknown"
        }
    }

    /// Convert Swift InferenceFramework to C rac_inference_framework_t.
    func toCFramework() -> rac_inference_framework_t {
        switch self {
        case .onnx:                return RAC_FRAMEWORK_ONNX
        case .sherpa:              return RAC_FRAMEWORK_SHERPA
        case .llamaCpp:            return RAC_FRAMEWORK_LLAMACPP
        case .foundationModels:    return RAC_FRAMEWORK_FOUNDATION_MODELS
        case .systemTts:           return RAC_FRAMEWORK_SYSTEM_TTS
        case .fluidAudio:          return RAC_FRAMEWORK_FLUID_AUDIO
        case .coreml:              return RAC_FRAMEWORK_COREML
        case .mlx:                 return RAC_FRAMEWORK_MLX
        case .whisperkitCoreml:    return RAC_FRAMEWORK_WHISPERKIT_COREML
        case .metalrt:             return RAC_FRAMEWORK_METALRT
        case .builtIn:             return RAC_FRAMEWORK_BUILTIN
        case .none:                return RAC_FRAMEWORK_NONE
        default:                   return RAC_FRAMEWORK_UNKNOWN
        }
    }

    /// Create Swift InferenceFramework from C rac_inference_framework_t.
    static func fromCFramework(_ cFramework: rac_inference_framework_t) -> RAInferenceFramework {
        switch cFramework {
        case RAC_FRAMEWORK_ONNX:                return .onnx
        case RAC_FRAMEWORK_SHERPA:              return .sherpa
        case RAC_FRAMEWORK_LLAMACPP:            return .llamaCpp
        case RAC_FRAMEWORK_FOUNDATION_MODELS:   return .foundationModels
        case RAC_FRAMEWORK_SYSTEM_TTS:          return .systemTts
        case RAC_FRAMEWORK_FLUID_AUDIO:         return .fluidAudio
        case RAC_FRAMEWORK_COREML:              return .coreml
        case RAC_FRAMEWORK_MLX:                 return .mlx
        case RAC_FRAMEWORK_WHISPERKIT_COREML:   return .whisperkitCoreml
        case RAC_FRAMEWORK_METALRT:             return .metalrt
        case RAC_FRAMEWORK_BUILTIN:             return .builtIn
        case RAC_FRAMEWORK_NONE:                return .none
        default:                                return .unknown
        }
    }

    /// Initialize from a string matching case-insensitively against wire names,
    /// display names, and analytics keys.
    init?(caseInsensitive string: String) {
        let lowered = string.lowercased()
        for c in RAInferenceFramework.knownCases {
            if c.wireString.lowercased() == lowered
                || c.analyticsKey == lowered
                || c.displayName.lowercased() == lowered {
                self = c
                return
            }
        }
        return nil
    }

    /// All known concrete cases (excludes `.UNRECOGNIZED` and `.unspecified`).
    static var knownCases: [RAInferenceFramework] {
        [
            .onnx, .sherpa, .llamaCpp, .foundationModels, .systemTts, .fluidAudio,
            .coreml, .mlx, .whisperkitCoreml, .metalrt, .genie,
            .tflite, .executorch, .mediapipe, .mlc, .picoLlm,
            .piperTts, .whisperkit, .openaiWhisper, .swiftTransformers,
            .builtIn, .none, .unknown,
        ]
    }

    // MARK: - Pre-IDL case-name aliases
    //
    // The hand-written `InferenceFramework` enum used `.systemTTS` and
    // `.whisperKitCoreML` (UK-TLA camel-case). Proto conversion normalizes to
    // `.systemTts` and `.whisperkitCoreml`. Aliases below keep every existing
    // call site compiling with zero edits.

    static var systemTTS: RAInferenceFramework        { .systemTts }
    static var whisperKitCoreML: RAInferenceFramework { .whisperkitCoreml }
    static var picoLLM: RAInferenceFramework          { .picoLlm }
    static var piperTTS: RAInferenceFramework         { .piperTts }
    static var openAIWhisper: RAInferenceFramework    { .openaiWhisper }
    static var execuTorch: RAInferenceFramework       { .executorch }
    static var mediaPipe: RAInferenceFramework        { .mediapipe }
}

// MARK: - ArchiveType

extension RAArchiveType: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "zip":              self = .zip
        case "tar.bz2", "tbz2":  self = .tarBz2
        case "tar.gz",  "tgz":   self = .tarGz
        case "tar.xz",  "txz":   self = .tarXz
        default:                 self = .unspecified
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.fileExtension)
    }
}

public extension RAArchiveType {
    /// File extension used in URLs (preserved from hand-written enum raw values).
    var fileExtension: String {
        switch self {
        case .zip:     return "zip"
        case .tarBz2:  return "tar.bz2"
        case .tarGz:   return "tar.gz"
        case .tarXz:   return "tar.xz"
        default:       return ""
        }
    }

    /// Short uppercase form used in UI labels (e.g. "ZIP", "TAR.BZ2").
    var displayName: String { fileExtension.uppercased() }

    /// Detect archive type from URL suffix.
    static func from(url: URL) -> RAArchiveType? {
        let path = url.path.lowercased()
        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") { return .tarBz2 }
        if path.hasSuffix(".tar.gz")  || path.hasSuffix(".tgz")  { return .tarGz }
        if path.hasSuffix(".tar.xz")  || path.hasSuffix(".txz")  { return .tarXz }
        if path.hasSuffix(".zip")                                 { return .zip }
        return nil
    }
}

// MARK: - ArchiveStructure

extension RAArchiveStructure: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "singleFileNested":    self = .singleFileNested
        case "directoryBased":      self = .directoryBased
        case "nestedDirectory":     self = .nestedDirectory
        case "unknown":             self = .unknown
        default:                    self = .unspecified
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

public extension RAArchiveStructure {
    var wireString: String {
        switch self {
        case .singleFileNested: return "singleFileNested"
        case .directoryBased:   return "directoryBased"
        case .nestedDirectory:  return "nestedDirectory"
        case .unknown:          return "unknown"
        default:                return "unspecified"
        }
    }
}

// MARK: - Expected Model Files (unchanged — Swift-only domain type)

/// Describes what files are expected after model extraction/download.
public struct ExpectedModelFiles: Codable, Sendable, Equatable {
    public let requiredPatterns: [String]
    public let optionalPatterns: [String]
    public let description: String?

    public init(
        requiredPatterns: [String] = [],
        optionalPatterns: [String] = [],
        description: String? = nil
    ) {
        self.requiredPatterns = requiredPatterns
        self.optionalPatterns = optionalPatterns
        self.description = description
    }

    public static let none = ExpectedModelFiles()
}

/// Describes a file that needs to be downloaded as part of a multi-file model.
public struct ModelFileDescriptor: Codable, Sendable, Equatable {
    /// Full URL to download this file from.
    public let url: URL
    /// Filename to save as (e.g., "model.gguf" or "mmproj.gguf").
    public let filename: String
    /// Whether this file is required for the model to work.
    public let isRequired: Bool

    public init(url: URL, filename: String, isRequired: Bool = true) {
        self.url = url
        self.filename = filename
        self.isRequired = isRequired
    }

    // Legacy compatibility
    public var relativePath: String { url.lastPathComponent }
    public var destinationPath: String { filename }
}

// MARK: - Model Artifact Type (unchanged — Swift-only sugar over IDL artifact oneof)

/// Describes how a model is packaged and what processing is needed after download.
public enum ModelArtifactType: Codable, Sendable, Equatable {
    case singleFile(expectedFiles: ExpectedModelFiles = .none)
    case archive(ArchiveType, structure: ArchiveStructure, expectedFiles: ExpectedModelFiles = .none)
    case multiFile([ModelFileDescriptor])
    case custom(strategyId: String)
    case builtIn

    public var requiresExtraction: Bool {
        if case .archive = self { return true }
        return false
    }

    public var requiresDownload: Bool {
        if case .builtIn = self { return false }
        return true
    }

    public var expectedFiles: ExpectedModelFiles {
        switch self {
        case .singleFile(let expected), .archive(_, _, let expected):
            return expected
        default:
            return .none
        }
    }

    public var displayName: String {
        switch self {
        case .singleFile:
            return "Single File"
        case .archive(let type, _, _):
            return "\(type.displayName) Archive"
        case .multiFile(let files):
            return "Multi-File (\(files.count) files)"
        case .custom(let strategyId):
            return "Custom (\(strategyId))"
        case .builtIn:
            return "Built-in"
        }
    }

    /// Infer artifact type from download URL.
    /// Note: C++ equivalent is `rac_artifact_infer_from_url()`.
    public static func infer(from url: URL?, format _: ModelFormat) -> ModelArtifactType {
        guard let url = url else {
            return .singleFile(expectedFiles: .none)
        }
        if let archiveType = ArchiveType.from(url: url) {
            return .archive(archiveType, structure: .unknown, expectedFiles: .none)
        }
        return .singleFile(expectedFiles: .none)
    }
}

// MARK: - ModelArtifactType Codable

extension ModelArtifactType {
    fileprivate enum ArtifactCodingKeys: String, CodingKey {
        case type, archiveType, structure, expectedFiles, files, strategyId
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: ArtifactCodingKeys.self)
        let type = try container.decode(String.self, forKey: ArtifactCodingKeys.type)

        switch type {
        case "singleFile":
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: ArtifactCodingKeys.expectedFiles) ?? .none
            self = .singleFile(expectedFiles: expected)
        case "archive":
            let archiveType = try container.decode(ArchiveType.self, forKey: ArtifactCodingKeys.archiveType)
            let structure = try container.decode(ArchiveStructure.self, forKey: ArtifactCodingKeys.structure)
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: ArtifactCodingKeys.expectedFiles) ?? .none
            self = .archive(archiveType, structure: structure, expectedFiles: expected)
        case "multiFile":
            let files = try container.decode([ModelFileDescriptor].self, forKey: ArtifactCodingKeys.files)
            self = .multiFile(files)
        case "custom":
            let strategyId = try container.decode(String.self, forKey: ArtifactCodingKeys.strategyId)
            self = .custom(strategyId: strategyId)
        case "builtIn":
            self = .builtIn
        default:
            self = .singleFile()
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.container(keyedBy: ArtifactCodingKeys.self)

        switch self {
        case .singleFile(let expected):
            try container.encode("singleFile", forKey: ArtifactCodingKeys.type)
            if expected != .none {
                try container.encode(expected, forKey: ArtifactCodingKeys.expectedFiles)
            }
        case .archive(let archiveType, let structure, let expected):
            try container.encode("archive", forKey: ArtifactCodingKeys.type)
            try container.encode(archiveType, forKey: ArtifactCodingKeys.archiveType)
            try container.encode(structure, forKey: ArtifactCodingKeys.structure)
            if expected != .none {
                try container.encode(expected, forKey: ArtifactCodingKeys.expectedFiles)
            }
        case .multiFile(let files):
            try container.encode("multiFile", forKey: ArtifactCodingKeys.type)
            try container.encode(files, forKey: ArtifactCodingKeys.files)
        case .custom(let strategyId):
            try container.encode("custom", forKey: ArtifactCodingKeys.type)
            try container.encode(strategyId, forKey: ArtifactCodingKeys.strategyId)
        case .builtIn:
            try container.encode("builtIn", forKey: ArtifactCodingKeys.type)
        }
    }
}

// MARK: - Model Info (unchanged — uses typealiased enums above)

/// Information about a model - in-memory entity.
public struct ModelInfo: Codable, Sendable, Identifiable {
    // Essential identifiers
    public let id: String
    public let name: String
    public let category: ModelCategory

    // Format and location
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?

    // Artifact type
    public let artifactType: ModelArtifactType

    // Size information
    public let downloadSize: Int64?

    // Framework
    public let framework: InferenceFramework

    // Model-specific capabilities
    public let contextLength: Int?
    public let supportsThinking: Bool
    public let thinkingPattern: ThinkingTagPattern?

    // Optional metadata
    public let description: String?

    // Tracking fields
    public let source: ModelSource
    public let createdAt: Date
    public var updatedAt: Date

    // MARK: - Computed Properties

    /// Whether this model is downloaded and available locally.
    public var isDownloaded: Bool {
        guard let localPath = localPath else { return false }

        if localPath.scheme == "builtin" {
            return true
        }

        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)

        if exists && isDirectory {
            return FileOperationsUtilities.isNonEmptyDirectory(at: localPath)
        }

        return exists
    }

    /// Whether this model is available for use.
    public var isAvailable: Bool {
        isDownloaded
    }

    /// Whether this is a built-in platform model.
    public var isBuiltIn: Bool {
        if artifactType == .builtIn {
            return true
        }
        if let localPath = localPath, localPath.scheme == "builtin" {
            return true
        }
        return framework == .foundationModels || framework == .systemTts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, format, downloadURL, localPath
        case artifactType
        case downloadSize
        case framework
        case contextLength, supportsThinking, thinkingPattern
        case description
        case source, createdAt, updatedAt
    }

    public init(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        framework: InferenceFramework,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        artifactType: ModelArtifactType? = nil,
        downloadSize: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        thinkingPattern: ThinkingTagPattern? = nil,
        description: String? = nil,
        source: ModelSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.format = format
        self.framework = framework
        self.downloadURL = downloadURL
        self.localPath = localPath

        self.artifactType = artifactType ?? ModelArtifactType.infer(from: downloadURL, format: format)

        self.downloadSize = downloadSize

        if category.requiresContextLength {
            self.contextLength = contextLength ?? 2048
        } else {
            self.contextLength = contextLength
        }

        self.supportsThinking = category.supportsThinking ? supportsThinking : false
        self.thinkingPattern = supportsThinking ? (thinkingPattern ?? .defaultPattern) : nil

        self.description = description
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
