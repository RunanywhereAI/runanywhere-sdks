//
//  InferenceFramework.swift
//  RunAnywhere SDK
//
//  Supported inference frameworks/runtimes for running models
//
//  ARCHITECTURE NOTE:
//  Each framework declares what model formats it supports via `supportedFormats`.
//  This is the single source of truth for format-framework compatibility.
//  When adding a new framework:
//  1. Add a new case to this enum
//  2. Add its supported formats in `supportedFormats`
//  3. Create the corresponding module that conforms to `RunAnywhereModule`
//

import Foundation

/// Supported inference frameworks/runtimes for executing models
///
/// ## Adding a New Framework
///
/// 1. Add a new case to this enum with its API identifier as the raw value
/// 2. Add supported formats in the `supportedFormats` property
/// 3. Create a module conforming to `RunAnywhereModule`
///
/// ```swift
/// // Example: Adding a new framework
/// case myFramework = "MyFramework"
///
/// // In supportedFormats:
/// case .myFramework: return [.myFormat]
/// ```
public enum InferenceFramework: String, CaseIterable, Codable, Sendable {
    // Model-based frameworks
    case onnx = "ONNX"
    case llamaCpp = "LlamaCpp"
    case foundationModels = "FoundationModels"
    case systemTTS = "SystemTTS"
    case fluidAudio = "FluidAudio"

    // Special cases
    case builtIn = "BuiltIn"      // For simple services (e.g., energy-based VAD)
    case none = "None"            // For services that don't use a model
    case unknown = "Unknown"      // For unknown/unspecified frameworks

    // MARK: - Format Support (Single Source of Truth)

    /// Model formats supported by this framework.
    /// This is the single source of truth for format-framework compatibility.
    /// When adding a new framework, declare its supported formats here.
    public var supportedFormats: Set<ModelFormat> {
        switch self {
        case .onnx:
            return [.onnx, .ort]
        case .llamaCpp:
            return [.gguf]
        case .foundationModels:
            return []  // Uses system models, no file format
        case .systemTTS:
            return []  // Uses system voices, no file format
        case .fluidAudio:
            return [.bin]  // FluidAudio soundfont files
        case .builtIn, .none, .unknown:
            return []
        }
    }

    /// Check if this framework supports the given model format
    public func supports(format: ModelFormat) -> Bool {
        supportedFormats.contains(format)
    }

    /// Whether this framework uses directory-based models (multiple files per model).
    /// This determines how models are stored and discovered on disk.
    public var usesDirectoryBasedModels: Bool {
        switch self {
        case .onnx:
            // ONNX models (e.g., sherpa-onnx) extract to directories
            // with multiple files like encoder.onnx, decoder.onnx, etc.
            return true
        case .llamaCpp, .fluidAudio:
            // Single-file models (.gguf, .bin)
            return false
        case .foundationModels, .systemTTS:
            // System-provided, no file storage
            return false
        case .builtIn, .none, .unknown:
            return false
        }
    }

    /// Find the framework that supports a given format.
    /// Returns nil if no framework supports the format or if multiple frameworks support it.
    /// Use this only for auto-discovery of local files when framework is not explicitly provided.
    public static func framework(for format: ModelFormat) -> InferenceFramework? {
        let matchingFrameworks = Self.allCases.filter { $0.supportedFormats.contains(format) }
        // Return only if exactly one framework supports this format
        return matchingFrameworks.count == 1 ? matchingFrameworks.first : nil
    }

    // MARK: - Display Properties

    /// Human-readable display name for the framework
    public var displayName: String {
        switch self {
        case .onnx: return "ONNX Runtime"
        case .llamaCpp: return "llama.cpp"
        case .foundationModels: return "Foundation Models"
        case .systemTTS: return "System TTS"
        case .fluidAudio: return "FluidAudio"
        case .builtIn: return "Built-in"
        case .none: return "None"
        case .unknown: return "Unknown"
        }
    }

    /// Snake_case key for analytics/telemetry (e.g., "llama_cpp")
    public var analyticsKey: String {
        switch self {
        case .onnx: return "onnx"
        case .llamaCpp: return "llama_cpp"
        case .foundationModels: return "foundation_models"
        case .systemTTS: return "system_tts"
        case .fluidAudio: return "fluid_audio"
        case .builtIn: return "built_in"
        case .none: return "none"
        case .unknown: return "unknown"
        }
    }

    // MARK: - Capability Support

    /// Whether this framework supports LLM (text-to-text)
    public var supportsLLM: Bool {
        switch self {
        case .llamaCpp, .onnx, .foundationModels:
            return true
        default:
            return false
        }
    }

    /// Whether this framework supports STT (speech-to-text)
    public var supportsSTT: Bool {
        switch self {
        case .onnx:
            return true
        default:
            return false
        }
    }

    /// Whether this framework supports TTS (text-to-speech)
    public var supportsTTS: Bool {
        switch self {
        case .systemTTS, .onnx:
            return true
        default:
            return false
        }
    }
}

// MARK: - Case-Insensitive Initialization

public extension InferenceFramework {
    /// Initialize from a string, matching case-insensitively.
    /// This is useful when parsing API responses where the case may vary.
    ///
    /// - Parameter string: The string to parse (e.g., "llamacpp", "LlamaCpp", "LLAMACPP")
    /// - Returns: The matching framework, or nil if no match found
    init?(caseInsensitive string: String) {
        let lowercased = string.lowercased()

        // Try exact raw value match first (for already-correct casing)
        if let exact = InferenceFramework(rawValue: string) {
            self = exact
            return
        }

        // Case-insensitive match against raw values
        if let framework = InferenceFramework.allCases.first(where: { $0.rawValue.lowercased() == lowercased }) {
            self = framework
            return
        }

        // Also match against analytics keys (snake_case variants)
        if let framework = InferenceFramework.allCases.first(where: { $0.analyticsKey == lowercased }) {
            self = framework
            return
        }

        return nil
    }
}
