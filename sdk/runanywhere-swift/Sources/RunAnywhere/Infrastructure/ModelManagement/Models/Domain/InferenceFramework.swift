//
//  InferenceFramework.swift
//  RunAnywhere SDK
//
//  Supported inference frameworks/runtimes for running models
//

import Foundation

/// Supported inference frameworks/runtimes for executing models
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
