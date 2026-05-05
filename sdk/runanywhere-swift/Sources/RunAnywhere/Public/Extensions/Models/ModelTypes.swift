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
        case .genie:               return RAC_FRAMEWORK_GENIE
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
        case RAC_FRAMEWORK_GENIE:               return .genie
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

extension RAModelThinkingTagPattern: Codable {
    public static var defaultPattern: RAModelThinkingTagPattern {
        var pattern = RAModelThinkingTagPattern()
        pattern.openTag = "<think>"
        pattern.closeTag = "</think>"
        return pattern
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        openTag = try container.decodeIfPresent(String.self, forKey: .openTag) ?? ""
        closeTag = try container.decodeIfPresent(String.self, forKey: .closeTag) ?? ""
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(openTag, forKey: .openTag)
        try container.encode(closeTag, forKey: .closeTag)
    }

    private enum CodingKeys: String, CodingKey {
        case openTag
        case closeTag
    }
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

// MARK: - Generated Model Contract Helpers

extension RAModelInfo: Identifiable {}

public extension RAExpectedModelFiles {
    static var none: RAExpectedModelFiles { RAExpectedModelFiles() }

    var isEmptyManifest: Bool {
        files.isEmpty
            && rootDirectory.isEmpty
            && requiredPatterns.isEmpty
            && optionalPatterns.isEmpty
            && description_p.isEmpty
    }
}

public extension RAModelFileDescriptor {
    init(url: URL, filename: String, isRequired: Bool = true) {
        self.init()
        self.url = url.absoluteString
        self.filename = filename
        self.isRequired = isRequired
        self.relativePath = url.lastPathComponent
        self.destinationPath = filename
    }

    var urlValue: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: url)
    }

    var destinationFilename: String {
        if !destinationPath.isEmpty { return destinationPath }
        if !filename.isEmpty { return filename }
        return relativePath
    }

    var resolvedLocalPath: String? {
        guard !localPath.isEmpty else { return nil }
        return localPath
    }
}

public extension Collection where Element == RAModelFileDescriptor {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        first { $0.role == role }?.resolvedLocalPath
    }

    var resolvedPrimaryModelPath: String? {
        resolvedModelFilePath(role: .primaryModel)
    }

    var resolvedVisionProjectorPath: String? {
        resolvedModelFilePath(role: .visionProjector)
    }

    var resolvedTokenizerPath: String? {
        resolvedModelFilePath(role: .tokenizer)
    }

    var resolvedConfigPath: String? {
        resolvedModelFilePath(role: .config)
    }

    var resolvedVocabularyPath: String? {
        resolvedModelFilePath(role: .vocabulary)
    }
}

public extension RAModelLoadResult {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        resolvedArtifacts.resolvedModelFilePath(role: role)
    }

    var resolvedPrimaryModelPath: String? {
        resolvedArtifacts.resolvedPrimaryModelPath
    }

    var resolvedVisionProjectorPath: String? {
        resolvedArtifacts.resolvedVisionProjectorPath
    }

    var resolvedTokenizerPath: String? {
        resolvedArtifacts.resolvedTokenizerPath
    }

    var resolvedConfigPath: String? {
        resolvedArtifacts.resolvedConfigPath
    }

    var resolvedVocabularyPath: String? {
        resolvedArtifacts.resolvedVocabularyPath
    }

    var lifecyclePrimaryArtifactPath: String? {
        resolvedPrimaryModelPath ?? resolvedPath.nilIfEmpty
    }
}

public extension RACurrentModelResult {
    func resolvedModelFilePath(role: RAModelFileRole) -> String? {
        resolvedArtifacts.resolvedModelFilePath(role: role)
    }

    var resolvedPrimaryModelPath: String? {
        resolvedArtifacts.resolvedPrimaryModelPath
    }

    var resolvedVisionProjectorPath: String? {
        resolvedArtifacts.resolvedVisionProjectorPath
    }

    var resolvedTokenizerPath: String? {
        resolvedArtifacts.resolvedTokenizerPath
    }

    var resolvedConfigPath: String? {
        resolvedArtifacts.resolvedConfigPath
    }

    var resolvedVocabularyPath: String? {
        resolvedArtifacts.resolvedVocabularyPath
    }

    var lifecyclePrimaryArtifactPath: String? {
        resolvedPrimaryModelPath ?? resolvedPath.nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension RAModelArtifactType {
    var requiresExtraction: Bool {
        switch self {
        case .archive, .zipArchive, .tarGzArchive, .tarBz2Archive, .tarXzArchive:
            return true
        default:
            return false
        }
    }

    var requiresDownload: Bool {
        self != .builtIn
    }

    var displayName: String {
        switch self {
        case .singleFile:
            return "Single File"
        case .archive:
            return "Archive"
        case .zipArchive:
            return "ZIP Archive"
        case .tarGzArchive:
            return "TAR.GZ Archive"
        case .tarBz2Archive:
            return "TAR.BZ2 Archive"
        case .tarXzArchive:
            return "TAR.XZ Archive"
        case .directory:
            return "Directory"
        case .multiFile:
            return "Multi-File"
        case .custom:
            return "Custom"
        case .builtIn:
            return "Built-in"
        default:
            return "Unspecified"
        }
    }
}

public extension RAModelInfo.OneOf_Artifact {
    var artifactType: RAModelArtifactType {
        switch self {
        case .singleFile:
            return .singleFile
        case .archive(let archive):
            return archive.type.artifactType
        case .multiFile:
            return .multiFile
        case .customStrategyID:
            return .custom
        case .builtIn(let enabled):
            return enabled ? .builtIn : .unspecified
        }
    }

    var requiresExtraction: Bool {
        if case .archive = self { return true }
        return artifactType.requiresExtraction
    }

    var requiresDownload: Bool {
        if case .builtIn(let enabled) = self, enabled { return false }
        return artifactType.requiresDownload
    }

    var displayName: String {
        switch self {
        case .singleFile:
            return RAModelArtifactType.singleFile.displayName
        case .archive(let artifact):
            return "\(artifact.type.displayName) Archive"
        case .multiFile(let artifact):
            return "Multi-File (\(artifact.files.count) files)"
        case .customStrategyID(let strategyId):
            return strategyId.isEmpty ? "Custom" : "Custom (\(strategyId))"
        case .builtIn:
            return RAModelArtifactType.builtIn.displayName
        }
    }

    var archiveArtifact: RAArchiveArtifact? {
        if case .archive(let artifact) = self { return artifact }
        return nil
    }

    var multiFileDescriptors: [RAModelFileDescriptor] {
        if case .multiFile(let artifact) = self { return artifact.files }
        return []
    }

    var expectedFiles: RAExpectedModelFiles {
        switch self {
        case .singleFile(let artifact):
            if artifact.hasExpectedFiles { return artifact.expectedFiles }
            return RAExpectedModelFiles.patterns(
                required: artifact.requiredPatterns,
                optional: artifact.optionalPatterns
            )
        case .archive(let artifact):
            if artifact.hasExpectedFiles { return artifact.expectedFiles }
            return RAExpectedModelFiles.patterns(
                required: artifact.requiredPatterns,
                optional: artifact.optionalPatterns
            )
        default:
            return .none
        }
    }
}

public extension RAModelInfo {
    static func make(
        id: String,
        name: String,
        category: ModelCategory,
        format: ModelFormat,
        framework: InferenceFramework,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        artifact: RAModelInfo.OneOf_Artifact? = nil,
        downloadSizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        supportsThinking: Bool = false,
        thinkingPattern: RAModelThinkingTagPattern? = nil,
        description: String? = nil,
        source: ModelSource = .remote,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> RAModelInfo {
        var model = RAModelInfo()
        model.id = id
        model.name = name
        model.category = category
        model.format = format
        model.framework = framework
        model.setDownloadURL(downloadURL)
        model.setLocalPath(localPath)
        model.downloadSizeBytes = downloadSizeBytes ?? 0
        model.contextLength = Int32(contextLength ?? (category.requiresContextLength ? 2048 : 0))
        model.supportsThinking = category.supportsThinking ? supportsThinking : false
        if model.supportsThinking {
            model.thinkingPattern = thinkingPattern ?? .defaultPattern
        }
        model.description_p = description ?? ""
        model.source = source
        model.createdAtUnixMs = unixMilliseconds(from: createdAt)
        model.updatedAtUnixMs = unixMilliseconds(from: updatedAt)
        model.setArtifact(artifact ?? inferredArtifact(from: downloadURL, format: format))
        model.isDownloaded = model.isDownloadedOnDisk
        model.isAvailable = model.isAvailableForUse
        return model
    }

    var downloadURLValue: URL? {
        guard !downloadURL.isEmpty else { return nil }
        return URL(string: downloadURL)
    }

    var localPathURL: URL? {
        Self.registryURL(from: localPath)
    }

    var downloadSizeHint: Int64 {
        downloadSizeBytes
    }

    var isBuiltIn: Bool {
        if case .builtIn(let enabled)? = artifact, enabled {
            return true
        }
        if artifactType == .builtIn {
            return true
        }
        if localPath.hasPrefix("builtin:") {
            return true
        }
        return framework == .foundationModels || framework == .systemTts
    }

    var isDownloadedOnDisk: Bool {
        if isBuiltIn { return true }
        guard let localPath = localPathURL else { return false }

        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: localPath)
        if exists && isDirectory {
            return FileOperationsUtilities.isNonEmptyDirectory(at: localPath)
        }
        return exists
    }

    var isAvailableForUse: Bool {
        isBuiltIn || isDownloadedOnDisk || isAvailable
    }

    var requiresExtraction: Bool {
        artifact?.requiresExtraction ?? artifactType.requiresExtraction
    }

    var requiresDownload: Bool {
        if isBuiltIn { return false }
        return artifact?.requiresDownload ?? artifactType.requiresDownload
    }

    var artifactDisplayName: String {
        artifact?.displayName ?? artifactType.displayName
    }

    var archiveArtifact: RAArchiveArtifact? {
        if let artifact = artifact?.archiveArtifact {
            return artifact
        }
        switch artifactType {
        case .archive:
            return makeArchiveArtifact(type: .zip, structure: .unknown)
        case .zipArchive:
            return makeArchiveArtifact(type: .zip, structure: .unknown)
        case .tarGzArchive:
            return makeArchiveArtifact(type: .tarGz, structure: .unknown)
        case .tarBz2Archive:
            return makeArchiveArtifact(type: .tarBz2, structure: .unknown)
        case .tarXzArchive:
            return makeArchiveArtifact(type: .tarXz, structure: .unknown)
        default:
            return nil
        }
    }

    var multiFileDescriptors: [RAModelFileDescriptor] {
        artifact?.multiFileDescriptors ?? multiFile.files
    }

    var expectedArtifactFiles: RAExpectedModelFiles {
        if hasExpectedFiles { return expectedFiles }
        return artifact?.expectedFiles ?? .none
    }

    mutating func setDownloadURL(_ url: URL?) {
        downloadURL = url?.absoluteString ?? ""
    }

    mutating func setLocalPath(_ url: URL?) {
        localPath = url.map(Self.registryPathString(from:)) ?? ""
        isDownloaded = isDownloadedOnDisk
        isAvailable = isAvailableForUse
    }

    mutating func setArtifact(_ artifact: RAModelInfo.OneOf_Artifact) {
        self.artifact = artifact
        artifactType = artifact.artifactType
        let expected = artifact.expectedFiles
        if !expected.isEmptyManifest {
            expectedFiles = expected
        }
    }

    static func inferredArtifact(from url: URL?, format _: ModelFormat) -> RAModelInfo.OneOf_Artifact {
        guard let url, let archiveType = ArchiveType.from(url: url) else {
            return .singleFile(RASingleFileArtifact())
        }
        return .archive(makeArchiveArtifact(type: archiveType, structure: .unknown))
    }
}

private extension RAExpectedModelFiles {
    static func patterns(required: [String], optional: [String]) -> RAExpectedModelFiles {
        var files = RAExpectedModelFiles()
        files.requiredPatterns = required
        files.optionalPatterns = optional
        return files
    }
}

private extension RAArchiveType {
    var artifactType: RAModelArtifactType {
        switch self {
        case .zip:
            return .zipArchive
        case .tarGz:
            return .tarGzArchive
        case .tarBz2:
            return .tarBz2Archive
        case .tarXz:
            return .tarXzArchive
        default:
            return .archive
        }
    }
}

private func makeArchiveArtifact(type: RAArchiveType, structure: RAArchiveStructure) -> RAArchiveArtifact {
    var artifact = RAArchiveArtifact()
    artifact.type = type
    artifact.structure = structure
    return artifact
}

private func unixMilliseconds(from date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
}

private extension RAModelInfo {
    static func registryPathString(from url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    static func registryURL(from value: String) -> URL? {
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}
