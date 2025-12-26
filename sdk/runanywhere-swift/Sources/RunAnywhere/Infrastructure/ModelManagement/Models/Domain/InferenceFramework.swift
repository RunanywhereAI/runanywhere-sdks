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
    case coreML = "CoreML"
    case tensorFlowLite = "TFLite"
    case mlx = "MLX"
    case swiftTransformers = "SwiftTransformers"
    case onnx = "ONNX"
    case execuTorch = "ExecuTorch"
    case llamaCpp = "LlamaCpp"
    case foundationModels = "FoundationModels"
    case picoLLM = "PicoLLM"
    case mlc = "MLC"
    case mediaPipe = "MediaPipe"
    case whisperKit = "WhisperKit"
    case openAIWhisper = "OpenAIWhisper"
    case systemTTS = "SystemTTS"
    case fluidAudio = "FluidAudio"

    // Special cases
    case builtIn = "BuiltIn"      // For simple services (e.g., energy-based VAD)
    case none = "None"            // For services that don't use a model
    case unknown = "Unknown"      // For unknown/unspecified frameworks

    /// Human-readable display name for the framework
    public var displayName: String {
        switch self {
        case .coreML: return "Core ML"
        case .tensorFlowLite: return "TensorFlow Lite"
        case .mlx: return "MLX"
        case .swiftTransformers: return "Swift Transformers"
        case .onnx: return "ONNX Runtime"
        case .execuTorch: return "ExecuTorch"
        case .llamaCpp: return "llama.cpp"
        case .foundationModels: return "Foundation Models"
        case .picoLLM: return "Pico LLM"
        case .mlc: return "MLC"
        case .mediaPipe: return "MediaPipe"
        case .whisperKit: return "WhisperKit"
        case .openAIWhisper: return "OpenAI Whisper"
        case .systemTTS: return "System TTS"
        case .fluidAudio: return "FluidAudio"
        case .builtIn: return "Built-in"
        case .none: return "None"
        case .unknown: return "Unknown"
        }
    }

    /// Snake_case key for analytics/telemetry (e.g., "llama_cpp", "whisper_kit")
    public var analyticsKey: String {
        switch self {
        case .coreML: return "core_ml"
        case .tensorFlowLite: return "tensorflow_lite"
        case .mlx: return "mlx"
        case .swiftTransformers: return "swift_transformers"
        case .onnx: return "onnx"
        case .execuTorch: return "executorch"
        case .llamaCpp: return "llama_cpp"
        case .foundationModels: return "foundation_models"
        case .picoLLM: return "pico_llm"
        case .mlc: return "mlc"
        case .mediaPipe: return "media_pipe"
        case .whisperKit: return "whisper_kit"
        case .openAIWhisper: return "openai_whisper"
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
        case .llamaCpp, .mlx, .coreML, .onnx, .foundationModels, .picoLLM, .mlc:
            return true
        default:
            return false
        }
    }

    /// Whether this framework supports STT (speech-to-text)
    public var supportsSTT: Bool {
        switch self {
        case .whisperKit, .openAIWhisper, .mediaPipe, .onnx:
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
