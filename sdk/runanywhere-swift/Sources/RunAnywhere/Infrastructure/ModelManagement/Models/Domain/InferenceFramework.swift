//
//  InferenceFramework.swift
//  RunAnywhere SDK
//
//  Supported inference frameworks/runtimes for running models
//

import Foundation

/// Supported inference frameworks/runtimes for executing models
public enum InferenceFramework: String, CaseIterable, Codable, Sendable {
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
        case .whisperKit, .openAIWhisper, .mediaPipe:
            return true
        default:
            return false
        }
    }

    /// Whether this framework supports TTS (text-to-speech)
    public var supportsTTS: Bool {
        switch self {
        case .systemTTS:
            return true
        default:
            return false
        }
    }
}
