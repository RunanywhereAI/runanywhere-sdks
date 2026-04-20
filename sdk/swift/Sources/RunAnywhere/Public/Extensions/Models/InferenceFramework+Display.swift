// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Human-readable display names for each `InferenceFramework` case.
// Sample UI renders the framework column in model-listing screens.

import Foundation

public extension InferenceFramework {
    var displayName: String {
        switch self {
        case .llamaCpp:           return "llama.cpp"
        case .onnx:               return "ONNX Runtime"
        case .whisperKit:         return "WhisperKit"
        case .whisperKitCoreML:   return "WhisperKit (CoreML)"
        case .metalRT:            return "MetalRT"
        case .genie:              return "Qualcomm Genie"
        case .foundationModels:   return "Apple Foundation Models"
        case .coreML:             return "Core ML"
        case .mlx:                return "MLX"
        case .sherpa:             return "Sherpa-ONNX"
        case .whisperCpp:         return "whisper.cpp"
        case .systemTTS:          return "System TTS"
        case .fluidAudio:         return "Fluid Audio"
        case .unknown:            return "Unknown"
        }
    }
}
