//
//  RAModelCategory+DefaultFramework.swift
//  RunAnywhere SDK
//
//  SDK-owned default-framework lookup per `RAModelCategory`. Example apps
//  previously hand-rolled this fallback (LLM/VLM → llamaCpp; STT/TTS/VAD/
//  embedding → onnx) because the SDK did not surface the implicit assignment
//  the C++ backends already encode. Centralising it here keeps example
//  view-models free of SDK-internal framework defaults.
//

import Foundation

public extension RAModelCategory {

    /// The framework the SDK falls back to when a category has no explicit
    /// `RAModelInfo.framework` resolved (e.g. a pending UI selection that has
    /// not yet matched a catalogued model). Mirrors the implicit defaults the
    /// C++ component registries already enforce so example apps stop encoding
    /// modality→framework string fallbacks of their own.
    var defaultFramework: InferenceFramework {
        switch self {
        case .language, .multimodal:
            return .llamaCpp
        case .speechRecognition, .speechSynthesis, .embedding, .voiceActivityDetection:
            return .onnx
        default:
            return .unknown
        }
    }
}
