//
//  AppTypes.swift
//  RunAnywhereAI
//
//  App-specific types and extensions
//

import Foundation
import RunAnywhereSDK

// MARK: - System Device Info

struct SystemDeviceInfo {
    let modelName: String
    let chipName: String
    let totalMemory: Int64
    let availableMemory: Int64
    let neuralEngineAvailable: Bool
    let osVersion: String
    let appVersion: String

    init(
        modelName: String = "",
        chipName: String = "",
        totalMemory: Int64 = 0,
        availableMemory: Int64 = 0,
        neuralEngineAvailable: Bool = false,
        osVersion: String = "",
        appVersion: String = ""
    ) {
        self.modelName = modelName
        self.chipName = chipName
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.neuralEngineAvailable = neuralEngineAvailable
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
}

// MARK: - Local Framework Types

enum LLMFramework: String, CaseIterable {
    case foundationModels = "Foundation Models"
    case mediaPipe = "MediaPipe"
    // Deferred frameworks
    case coreML = "CoreML"
    case mlx = "MLX"
    case tensorFlowLite = "TFLite"
    case onnx = "ONNX"
    case execuTorch = "ExecuTorch"
    case llamaCpp = "LlamaCpp"
    case mlc = "MLC"
    case picoLLM = "PicoLLM"
    case swiftTransformers = "SwiftTransformers"

    static var availableFrameworks: [LLMFramework] {
        return [.foundationModels, .mediaPipe]
    }

    static var deferredFrameworks: [LLMFramework] {
        return [.coreML, .mlx, .tensorFlowLite, .onnx, .execuTorch,
                .llamaCpp, .mlc, .picoLLM, .swiftTransformers]
    }

    var isDeferred: Bool {
        Self.deferredFrameworks.contains(self)
    }

    var displayName: String {
        return self.rawValue
    }
}

// MARK: - SDK Type Conversions

extension LLMFramework {
    var toSDKFramework: RunAnywhereSDK.LLMFramework? {
        switch self {
        case .foundationModels:
            return .foundationModels
        case .coreML:
            return .coreML
        case .mlx:
            return .mlx
        case .tensorFlowLite:
            return .tensorFlowLite
        case .onnx:
            return .onnx
        case .execuTorch:
            return .execuTorch
        case .llamaCpp:
            return .llamaCpp
        case .mlc:
            return .mlc
        case .picoLLM:
            return .picoLLM
        case .swiftTransformers:
            return .swiftTransformers
        case .mediaPipe:
            // MediaPipe might not exist in SDK yet, map to a compatible one
            return .tensorFlowLite
        }
    }
}

extension RunAnywhereSDK.LLMFramework {
    var toLocalFramework: LLMFramework? {
        switch self {
        case .foundationModels:
            return .foundationModels
        case .coreML:
            return .coreML
        case .mlx:
            return .mlx
        case .tensorFlowLite:
            return .tensorFlowLite
        case .onnx:
            return .onnx
        case .execuTorch:
            return .execuTorch
        case .llamaCpp:
            return .llamaCpp
        case .mlc:
            return .mlc
        case .picoLLM:
            return .picoLLM
        case .swiftTransformers:
            return .swiftTransformers
        }
    }
}

extension LLMFramework {
    static func fromSDK(_ sdkFramework: RunAnywhereSDK.LLMFramework) -> LLMFramework? {
        return sdkFramework.toLocalFramework
    }
}

// MARK: - Model Info Conversions

struct ModelInfo {
    let id: String
    let name: String
    let format: ModelFormat
    let size: String
    let framework: LLMFramework
    let downloadURL: URL?

    init(
        id: String,
        name: String,
        format: ModelFormat,
        size: String = "Unknown",
        framework: LLMFramework,
        downloadURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.size = size
        self.framework = framework
        self.downloadURL = downloadURL
    }

    static func fromSDK(_ sdkModel: RunAnywhereSDK.ModelInfo) -> ModelInfo? {
        guard let localFormat = sdkModel.format.toLocalFormat,
              let localFramework = sdkModel.preferredFramework?.toLocalFramework ?? .foundationModels else {
            return nil
        }

        let sizeString = "\(sdkModel.estimatedMemory / 1_000_000)MB"

        return ModelInfo(
            id: sdkModel.id,
            name: sdkModel.name,
            format: localFormat,
            size: sizeString,
            framework: localFramework,
            downloadURL: sdkModel.downloadURL
        )
    }
}

extension RunAnywhereSDK.ModelFormat {
    var toLocalFormat: ModelFormat? {
        switch self {
        case .gguf:
            return .gguf
        case .mlmodel:
            return .mlmodel
        case .mlpackage:
            return .mlpackage
        case .onnx:
            return .onnx
        case .tflite:
            return .tflite
        case .pte:
            return .pte
        case .safetensors:
            return .safetensors
        case .npz:
            return .npz
        case .pv:
            return .pv
        }
    }
}

// MARK: - Model Format Types

enum ModelFormat: String, CaseIterable {
    case gguf = "gguf"
    case mlmodel = "mlmodel"
    case mlpackage = "mlpackage"
    case onnx = "onnx"
    case tflite = "tflite"
    case pte = "pte"
    case safetensors = "safetensors"
    case npz = "npz"
    case pv = "pv"

    static func from(extension ext: String) -> ModelFormat {
        return ModelFormat(rawValue: ext.lowercased()) ?? .gguf
    }
}

extension ModelFormat {
    var toSDKFormat: RunAnywhereSDK.ModelFormat? {
        switch self {
        case .gguf:
            return .gguf
        case .mlmodel:
            return .mlmodel
        case .mlpackage:
            return .mlpackage
        case .onnx:
            return .onnx
        case .tflite:
            return .tflite
        case .pte:
            return .pte
        case .safetensors:
            return .safetensors
        case .npz:
            return .npz
        case .pv:
            return .pv
        }
    }
}
