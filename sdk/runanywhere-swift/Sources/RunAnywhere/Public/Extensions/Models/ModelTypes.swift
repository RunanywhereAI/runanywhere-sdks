//
//  ModelTypes.swift
//  RunAnywhere SDK
//
//  Public types for model management.
//  These are thin wrappers over C++ types in rac_model_types.h
//  Business logic (format support, capability checks) is in C++.
//

import CRACommons
import Foundation

// MARK: - Model Source

/// Source of model data (where the model info came from)
public enum ModelSource: String, Codable, Sendable {
    /// Model info came from remote API (backend model catalog)
    case remote

    /// Model info was provided locally via SDK input (addModel calls)
    case local
}

// MARK: - Model Format

/// Model formats supported
public enum ModelFormat: String, CaseIterable, Codable, Sendable {
    case onnx
    case ort
    case gguf
    case bin
    case unknown
}

// MARK: - Model Category

/// Defines the category/type of a model based on its input/output modality
public enum ModelCategory: String, CaseIterable, Codable, Sendable {
    case language = "language"              // Text-to-text models (LLMs)
    case speechRecognition = "speech-recognition"  // Voice-to-text models (ASR)
    case speechSynthesis = "speech-synthesis"      // Text-to-voice models (TTS)
    case vision = "vision"                  // Image understanding models
    case imageGeneration = "image-generation"      // Text-to-image models
    case multimodal = "multimodal"          // Models that handle multiple modalities
    case audio = "audio"                    // Audio processing (diarization, etc.)

    /// Whether this category typically requires context length
    /// Note: C++ equivalent is rac_model_category_requires_context_length()
    public var requiresContextLength: Bool {
        switch self {
        case .language, .multimodal:
            return true
        case .speechRecognition, .speechSynthesis, .vision, .imageGeneration, .audio:
            return false
        }
    }

    /// Whether this category typically supports thinking/reasoning
    /// Note: C++ equivalent is rac_model_category_supports_thinking()
    public var supportsThinking: Bool {
        switch self {
        case .language, .multimodal:
            return true
        case .speechRecognition, .speechSynthesis, .vision, .imageGeneration, .audio:
            return false
        }
    }
}

// MARK: - Inference Framework

/// Supported inference frameworks/runtimes for executing models
public enum InferenceFramework: String, CaseIterable, Codable, Sendable {
    // Model-based frameworks
    case onnx = "ONNX"
    case llamaCpp = "LlamaCpp"
    case foundationModels = "FoundationModels"
    case systemTTS = "SystemTTS"
    case fluidAudio = "FluidAudio"
    case coreml = "CoreML"        // Core ML (Apple Neural Engine) for diffusion models

    // Special cases
    case builtIn = "BuiltIn"      // For simple services (e.g., energy-based VAD)
    case none = "None"            // For services that don't use a model
    case unknown = "Unknown"      // For unknown/unspecified frameworks

    /// Human-readable display name for the framework
    public var displayName: String {
        switch self {
        case .onnx: return "ONNX Runtime"
        case .llamaCpp: return "llama.cpp"
        case .foundationModels: return "Foundation Models"
        case .systemTTS: return "System TTS"
        case .fluidAudio: return "FluidAudio"
        case .coreml: return "Core ML"
        case .builtIn: return "Built-in"
        case .none: return "None"
        case .unknown: return "Unknown"
        }
    }

    /// Snake_case key for analytics/telemetry
    public var analyticsKey: String {
        switch self {
        case .onnx: return "onnx"
        case .llamaCpp: return "llama_cpp"
        case .foundationModels: return "foundation_models"
        case .systemTTS: return "system_tts"
        case .fluidAudio: return "fluid_audio"
        case .coreml: return "coreml"
        case .builtIn: return "built_in"
        case .none: return "none"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - InferenceFramework C++ Bridge

public extension InferenceFramework {
    /// Convert Swift InferenceFramework to C rac_inference_framework_t
    func toCFramework() -> rac_inference_framework_t {
        switch self {
        case .onnx: return RAC_FRAMEWORK_ONNX
        case .llamaCpp: return RAC_FRAMEWORK_LLAMACPP
        case .foundationModels: return RAC_FRAMEWORK_FOUNDATION_MODELS
        case .systemTTS: return RAC_FRAMEWORK_SYSTEM_TTS
        case .fluidAudio: return RAC_FRAMEWORK_FLUID_AUDIO
        case .coreml: return RAC_FRAMEWORK_COREML
        case .builtIn: return RAC_FRAMEWORK_BUILTIN
        case .none: return RAC_FRAMEWORK_NONE
        case .unknown: return RAC_FRAMEWORK_UNKNOWN
        }
    }

    /// Create Swift InferenceFramework from C rac_inference_framework_t
    static func fromCFramework(_ cFramework: rac_inference_framework_t) -> InferenceFramework {
        switch cFramework {
        case RAC_FRAMEWORK_ONNX: return .onnx
        case RAC_FRAMEWORK_LLAMACPP: return .llamaCpp
        case RAC_FRAMEWORK_FOUNDATION_MODELS: return .foundationModels
        case RAC_FRAMEWORK_SYSTEM_TTS: return .systemTTS
        case RAC_FRAMEWORK_FLUID_AUDIO: return .fluidAudio
        case RAC_FRAMEWORK_COREML: return .coreml
        case RAC_FRAMEWORK_BUILTIN: return .builtIn
        case RAC_FRAMEWORK_NONE: return .none
        default: return .unknown
        }
    }

    /// Initialize from a string, matching case-insensitively.
    init?(caseInsensitive string: String) {
        let lowercased = string.lowercased()

        if let exact = InferenceFramework(rawValue: string) {
            self = exact
            return
        }

        if let framework = InferenceFramework.allCases.first(where: { $0.rawValue.lowercased() == lowercased }) {
            self = framework
            return
        }

        if let framework = InferenceFramework.allCases.first(where: { $0.analyticsKey == lowercased }) {
            self = framework
            return
        }

        return nil
    }
}

// MARK: - Archive Types

/// Supported archive formats for model packaging
public enum ArchiveType: String, CaseIterable, Codable, Sendable {
    case zip = "zip"
    case tarBz2 = "tar.bz2"
    case tarGz = "tar.gz"
    case tarXz = "tar.xz"

    /// File extension for this archive type
    public var fileExtension: String {
        rawValue
    }

    /// Detect archive type from URL
    /// Note: C++ equivalent is rac_archive_type_from_path()
    public static func from(url: URL) -> ArchiveType? {
        let path = url.path.lowercased()
        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") {
            return .tarBz2
        } else if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
            return .tarGz
        } else if path.hasSuffix(".tar.xz") || path.hasSuffix(".txz") {
            return .tarXz
        } else if path.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }
}

/// Describes the internal structure of an archive after extraction
public enum ArchiveStructure: String, Codable, Sendable, Equatable {
    case singleFileNested
    case directoryBased
    case nestedDirectory
    case unknown
}

// MARK: - Expected Model Files

/// Describes what files are expected after model extraction/download
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

/// Describes a file that needs to be downloaded as part of a multi-file model
public struct ModelFileDescriptor: Codable, Sendable, Equatable {
    public let relativePath: String
    public let destinationPath: String
    public let isRequired: Bool

    public init(relativePath: String, destinationPath: String, isRequired: Bool = true) {
        self.relativePath = relativePath
        self.destinationPath = destinationPath
        self.isRequired = isRequired
    }
}

// MARK: - Model Artifact Type

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
            return "\(type.rawValue.uppercased()) Archive"
        case .multiFile(let files):
            return "Multi-File (\(files.count) files)"
        case .custom(let strategyId):
            return "Custom (\(strategyId))"
        case .builtIn:
            return "Built-in"
        }
    }

    /// Infer artifact type from download URL
    /// Note: C++ equivalent is rac_artifact_infer_from_url()
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
    private enum CodingKeys: String, CodingKey {
        case type, archiveType, structure, expectedFiles, files, strategyId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "singleFile":
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: .expectedFiles) ?? .none
            self = .singleFile(expectedFiles: expected)
        case "archive":
            let archiveType = try container.decode(ArchiveType.self, forKey: .archiveType)
            let structure = try container.decode(ArchiveStructure.self, forKey: .structure)
            let expected = try container.decodeIfPresent(ExpectedModelFiles.self, forKey: .expectedFiles) ?? .none
            self = .archive(archiveType, structure: structure, expectedFiles: expected)
        case "multiFile":
            let files = try container.decode([ModelFileDescriptor].self, forKey: .files)
            self = .multiFile(files)
        case "custom":
            let strategyId = try container.decode(String.self, forKey: .strategyId)
            self = .custom(strategyId: strategyId)
        case "builtIn":
            self = .builtIn
        default:
            self = .singleFile()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .singleFile(let expected):
            try container.encode("singleFile", forKey: .type)
            if expected != .none {
                try container.encode(expected, forKey: .expectedFiles)
            }
        case .archive(let archiveType, let structure, let expected):
            try container.encode("archive", forKey: .type)
            try container.encode(archiveType, forKey: .archiveType)
            try container.encode(structure, forKey: .structure)
            if expected != .none {
                try container.encode(expected, forKey: .expectedFiles)
            }
        case .multiFile(let files):
            try container.encode("multiFile", forKey: .type)
            try container.encode(files, forKey: .files)
        case .custom(let strategyId):
            try container.encode("custom", forKey: .type)
            try container.encode(strategyId, forKey: .strategyId)
        case .builtIn:
            try container.encode("builtIn", forKey: .type)
        }
    }
}

// MARK: - Model Info

/// Information about a model - in-memory entity
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

    /// Whether this model is downloaded and available locally
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

    /// Whether this model is available for use
    public var isAvailable: Bool {
        isDownloaded
    }

    /// Whether this is a built-in platform model
    public var isBuiltIn: Bool {
        if artifactType == .builtIn {
            return true
        }
        if let localPath = localPath, localPath.scheme == "builtin" {
            return true
        }
        return framework == .foundationModels || framework == .systemTTS
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
