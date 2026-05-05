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
//  Artifact / archive / expected-files helpers (RAModelInfo.make,
//  resolvedPrimaryModelPath, inferredArtifact, etc.) live in
//  `ModelTypes+Artifacts.swift` to keep this file below the SwiftLint
//  `file_length` threshold.
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

extension RAThinkingTagPattern: Codable {
    // `defaultPattern` lives in `RALLMTypes+CppBridge.swift` (canonical
    // C-bridge extension). Codable conformance stays here next to the other
    // model-type Codable extensions so RAModelInfo persists cleanly to JSON.

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
