//
//  TypeConversions.swift
//  RunAnywhereAI
//
//  Type conversions between sample app and SDK types
//

import Foundation
import RunAnywhereSDK

// MARK: - Type Conversion Extensions

extension LLMFramework {
    /// Convert sample app framework to SDK framework
    var toSDKFramework: RunAnywhereSDK.LLMFramework? {
        switch self {
        case .coreML:
            return .coreML
        case .tensorFlowLite:
            return .tensorFlowLite
        case .mlx:
            return .mlx
        case .swiftTransformers:
            return .swiftTransformers
        case .onnxRuntime:
            return .onnx
        case .execuTorch:
            return .execuTorch
        case .llamaCpp:
            return .llamaCpp
        case .foundationModels:
            return .foundationModels
        case .picoLLM:
            return .picoLLM
        case .mlc:
            return .mlc
        }
    }

    /// Create from SDK framework
    static func fromSDK(_ sdkFramework: RunAnywhereSDK.LLMFramework) -> LLMFramework? {
        switch sdkFramework {
        case .coreML:
            return .coreML
        case .tensorFlowLite:
            return .tensorFlowLite
        case .mlx:
            return .mlx
        case .swiftTransformers:
            return .swiftTransformers
        case .onnx:
            return .onnxRuntime
        case .execuTorch:
            return .execuTorch
        case .llamaCpp:
            return .llamaCpp
        case .foundationModels:
            return .foundationModels
        case .picoLLM:
            return .picoLLM
        case .mlc:
            return .mlc
        }
    }
}

extension ModelFormat {
    /// Convert sample app format to SDK format
    var toSDKFormat: RunAnywhereSDK.ModelFormat? {
        switch self {
        case .mlPackage:
            return .mlpackage
        case .coreML:
            return .mlmodel
        case .tflite:
            return .tflite
        case .onnx, .onnxRuntime:
            return .onnx
        case .safetensors:
            return .safetensors
        case .gguf:
            return .gguf
        case .ggml:
            return .ggml
        case .pte:
            return .pte
        default:
            return .bin
        }
    }

    /// Create from SDK format
    static func fromSDK(_ sdkFormat: RunAnywhereSDK.ModelFormat) -> ModelFormat? {
        switch sdkFormat {
        case .mlmodel:
            return .coreML
        case .mlpackage:
            return .mlPackage
        case .tflite:
            return .tflite
        case .onnx:
            return .onnx
        case .ort:
            return .onnxRuntime
        case .safetensors:
            return .safetensors
        case .gguf:
            return .gguf
        case .ggml:
            return .ggml
        case .pte:
            return .pte
        case .bin:
            return .other
        default:
            return .other
        }
    }
}

// MARK: - Model Info Conversions

extension ModelInfo {
    /// Convert sample app ModelInfo to SDK ModelInfo
    func toSDKModelInfo() -> RunAnywhereSDK.ModelInfo? {
        guard let sdkFormat = format.toSDKFormat else { return nil }

        let sdkFrameworks: [RunAnywhereSDK.LLMFramework] = LLMFramework.allCases.compactMap { appFramework in
            guard appFramework.supportedFormats.contains(format) else { return nil }
            return appFramework.toSDKFramework
        }

        return RunAnywhereSDK.ModelInfo(
            id: id,
            name: name,
            format: sdkFormat,
            downloadURL: downloadURL,
            localPath: path.flatMap { URL(fileURLWithPath: $0) },
            estimatedMemory: minimumMemory,
            contextLength: contextLength ?? 2048,
            downloadSize: nil,
            checksum: sha256,
            compatibleFrameworks: sdkFrameworks,
            preferredFramework: framework.toSDKFramework,
            hardwareRequirements: [],
            tokenizerFormat: nil,
            metadata: RunAnywhereSDK.ModelInfoMetadata(
                author: nil,
                license: nil,
                tags: [],
                description: description,
                trainingDataset: nil,
                baseModel: nil,
                quantizationLevel: quantization.flatMap { _ in .int8 }
            ),
            alternativeDownloadURLs: alternativeURLs.isEmpty ? nil : alternativeURLs
        )
    }

    /// Create from SDK ModelInfo
    static func fromSDK(_ sdkModel: RunAnywhereSDK.ModelInfo) -> ModelInfo? {
        guard let appFormat = ModelFormat.fromSDK(sdkModel.format),
              let preferredFramework = sdkModel.preferredFramework,
              let appFramework = LLMFramework.fromSDK(preferredFramework) else {
            return nil
        }

        let sizeString = ByteCountFormatter.string(fromByteCount: sdkModel.estimatedMemory, countStyle: .file)

        return ModelInfo(
            id: sdkModel.id,
            name: sdkModel.name,
            path: sdkModel.localPath?.path,
            format: appFormat,
            size: sizeString,
            framework: appFramework,
            quantization: sdkModel.metadata?.quantizationLevel?.rawValue,
            contextLength: sdkModel.contextLength,
            isLocal: sdkModel.localPath != nil,
            downloadURL: sdkModel.downloadURL,
            downloadedFileName: sdkModel.localPath?.lastPathComponent,
            modelType: .text,
            sha256: sdkModel.checksum,
            requiresUnzip: false,
            requiresAuth: false,
            authType: .none,
            alternativeURLs: sdkModel.alternativeDownloadURLs ?? [],
            notes: nil,
            description: sdkModel.metadata?.description ?? "",
            minimumMemory: sdkModel.estimatedMemory,
            recommendedMemory: Int64(Double(sdkModel.estimatedMemory) * 1.5)
        )
    }
}

// MARK: - Hardware Acceleration Conversions

extension HardwareAcceleration {
    /// Convert to SDK hardware acceleration
    static func fromString(_ value: String) -> RunAnywhereSDK.HardwareAcceleration {
        switch value.lowercased() {
        case "cpu":
            return .cpu
        case "gpu":
            return .gpu
        case "neuralengine", "neural engine":
            return .neuralEngine
        case "metal":
            return .metal
        case "coreml":
            return .coreML
        default:
            return .auto
        }
    }
}
