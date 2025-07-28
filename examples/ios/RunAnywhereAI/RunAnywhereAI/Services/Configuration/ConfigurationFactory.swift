//
//  ConfigurationFactory.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Factory for creating framework-specific configurations
enum ConfigurationFactory {
    /// Create configuration for a specific framework
    static func configuration(for framework: LLMFramework) -> LLMFrameworkConfiguration {
        switch framework {
        case .foundationModels:
            return FoundationModelsConfiguration.default
        case .coreML:
            return CoreMLConfiguration.default
        case .mlx:
            return MLXConfiguration.default
        case .mlc:
            return MLCConfiguration.default
        case .onnxRuntime:
            return ONNXConfiguration.default
        case .execuTorch:
            return ExecuTorchConfiguration.default
        case .llamaCpp:
            return LlamaCppConfiguration.default
        case .tensorFlowLite:
            return TFLiteConfiguration.default
        case .picoLLM:
            return PicoLLMConfiguration.default
        case .swiftTransformers:
            return SwiftTransformersConfiguration.default
        }
    }

    /// Convert configuration to dictionary for service configuration
    static func toDictionary(_ configuration: LLMFrameworkConfiguration) -> [String: Any] {
        var dict: [String: Any] = [
            "enableLogging": configuration.enableLogging,
            "logLevel": configuration.logLevel.rawValue,
            "performanceTracking": configuration.performanceTracking
        ]

        if let memoryLimit = configuration.memoryLimit {
            dict["memoryLimit"] = memoryLimit
        }

        // Add framework-specific properties
        switch configuration {
        case let config as FoundationModelsConfiguration:
            dict["useSystemCache"] = config.useSystemCache
            dict["privacyMode"] = String(describing: config.privacyMode)
            dict["systemIntegration"] = config.systemIntegration

        case let config as CoreMLConfiguration:
            dict["computeUnits"] = String(describing: config.computeUnits)
            dict["allowLowPrecision"] = config.allowLowPrecision
            dict["enableBatching"] = config.enableBatching
            dict["maxBatchSize"] = config.maxBatchSize
            dict["useFlexibleShapes"] = config.useFlexibleShapes

        case let config as MLXConfiguration:
            dict["device"] = String(describing: config.device)
            dict["lazyEvaluation"] = config.lazyEvaluation
            dict["unifiedMemory"] = config.unifiedMemory
            dict["customKernels"] = config.customKernels
            if let seed = config.seed {
                dict["seed"] = seed
            }

        case let config as MLCConfiguration:
            dict["backend"] = String(describing: config.backend)
            dict["optimizationLevel"] = config.optimizationLevel
            dict["useWebGPU"] = config.useWebGPU
            dict["openAICompatible"] = config.openAICompatible
            dict["compilationCache"] = config.compilationCache

        case let config as ONNXConfiguration:
            dict["executionProvider"] = String(describing: config.executionProvider)
            dict["graphOptimizationLevel"] = config.graphOptimizationLevel
            dict["enableProfiling"] = config.enableProfiling
            dict["interOpNumThreads"] = config.interOpNumThreads
            dict["intraOpNumThreads"] = config.intraOpNumThreads

        case let config as ExecuTorchConfiguration:
            dict["quantizationBits"] = config.quantizationBits
            dict["backend"] = String(describing: config.backend)
            dict["enableDynamicShapes"] = config.enableDynamicShapes
            if let customPath = config.customOperatorPath {
                dict["customOperatorPath"] = customPath
            }

        case let config as LlamaCppConfiguration:
            dict["useMetalAcceleration"] = config.useMetalAcceleration
            dict["contextSize"] = config.contextSize
            dict["batchSize"] = config.batchSize
            dict["numberOfThreads"] = config.numberOfThreads
            dict["numberOfGPULayers"] = config.numberOfGPULayers
            dict["mmap"] = config.mmap
            dict["mlock"] = config.mlock

        case let config as TFLiteConfiguration:
            dict["delegate"] = String(describing: config.delegate)
            dict["numberOfThreads"] = config.numberOfThreads
            dict["allowFP16"] = config.allowFP16
            dict["enableXNNPACK"] = config.enableXNNPACK

        case let config as PicoLLMConfiguration:
            dict["compressionLevel"] = String(describing: config.compressionLevel)
            dict["voiceOptimized"] = config.voiceOptimized
            dict["realTimeMode"] = config.realTimeMode
            if let apiKey = config.apiKey {
                dict["apiKey"] = apiKey
            }

        case let config as SwiftTransformersConfiguration:
            dict["modelSource"] = String(describing: config.modelSource)
            dict["tokenizerType"] = String(describing: config.tokenizerType)
            if let cacheDir = config.cacheDirectory {
                dict["cacheDirectory"] = cacheDir.path
            }
            dict["downloadTimeout"] = config.downloadTimeout

        default:
            break
        }

        return dict
    }
}

