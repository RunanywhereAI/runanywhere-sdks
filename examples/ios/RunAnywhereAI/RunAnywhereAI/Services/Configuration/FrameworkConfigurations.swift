//
//  FrameworkConfigurations.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

// MARK: - Base Configuration Protocol

protocol LLMFrameworkConfiguration {
    var enableLogging: Bool { get }
    var logLevel: LogLevel { get }
    var performanceTracking: Bool { get }
    var memoryLimit: Int64? { get }
}

// MARK: - Apple Foundation Models Configuration

struct FoundationModelsConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // Foundation Models specific
    let useSystemCache: Bool
    let privacyMode: PrivacyMode
    let systemIntegration: Bool
    
    enum PrivacyMode {
        case standard
        case enhanced
        case maximum
    }
    
    static let `default` = FoundationModelsConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        useSystemCache: true,
        privacyMode: .enhanced,
        systemIntegration: true
    )
}

// MARK: - Core ML Configuration

struct CoreMLConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // Core ML specific
    let computeUnits: MLComputeUnits
    let allowLowPrecision: Bool
    let enableBatching: Bool
    let maxBatchSize: Int
    let useFlexibleShapes: Bool
    
    enum MLComputeUnits {
        case cpuOnly
        case cpuAndGPU
        case cpuAndNeuralEngine
        case all
    }
    
    static let `default` = CoreMLConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        computeUnits: .all,
        allowLowPrecision: true,
        enableBatching: false,
        maxBatchSize: 1,
        useFlexibleShapes: true
    )
}

// MARK: - MLX Configuration

struct MLXConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // MLX specific
    let device: MLXDevice
    let lazyEvaluation: Bool
    let unifiedMemory: Bool
    let customKernels: Bool
    let seed: Int?
    
    enum MLXDevice {
        case cpu
        case gpu
        case automatic
    }
    
    static let `default` = MLXConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        device: .automatic,
        lazyEvaluation: true,
        unifiedMemory: true,
        customKernels: false,
        seed: nil
    )
}

// MARK: - MLC-LLM Configuration

struct MLCConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // MLC specific
    let backend: MLCBackend
    let optimizationLevel: Int
    let useWebGPU: Bool
    let openAICompatible: Bool
    let compilationCache: Bool
    
    enum MLCBackend {
        case metal
        case webGPU
        case cuda
        case vulkan
    }
    
    static let `default` = MLCConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        backend: .metal,
        optimizationLevel: 2,
        useWebGPU: false,
        openAICompatible: true,
        compilationCache: true
    )
}

// MARK: - ONNX Runtime Configuration

struct ONNXConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // ONNX specific
    let executionProvider: ONNXExecutionProvider
    let graphOptimizationLevel: Int
    let enableProfiling: Bool
    let interOpNumThreads: Int
    let intraOpNumThreads: Int
    
    enum ONNXExecutionProvider {
        case cpu
        case coreML
        case metal
        case cuda
        case tensorRT
    }
    
    static let `default` = ONNXConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        executionProvider: .coreML,
        graphOptimizationLevel: 99,
        enableProfiling: false,
        interOpNumThreads: 0,
        intraOpNumThreads: 0
    )
}

// MARK: - ExecuTorch Configuration

struct ExecuTorchConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // ExecuTorch specific
    let quantizationBits: Int
    let backend: ExecuTorchBackend
    let enableDynamicShapes: Bool
    let customOperatorPath: String?
    
    enum ExecuTorchBackend {
        case xnnpack
        case metal
        case coreML
        case custom(String)
    }
    
    static let `default` = ExecuTorchConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        quantizationBits: 8,
        backend: .metal,
        enableDynamicShapes: true,
        customOperatorPath: nil
    )
}

// MARK: - llama.cpp Configuration

struct LlamaCppConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // llama.cpp specific
    let useMetalAcceleration: Bool
    let contextSize: Int
    let batchSize: Int
    let numberOfThreads: Int
    let numberOfGPULayers: Int
    let mmap: Bool
    let mlock: Bool
    
    static let `default` = LlamaCppConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        useMetalAcceleration: true,
        contextSize: 2048,
        batchSize: 512,
        numberOfThreads: 4,
        numberOfGPULayers: 32,
        mmap: true,
        mlock: false
    )
}

// MARK: - TensorFlow Lite Configuration

struct TFLiteConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // TFLite specific
    let delegate: TFLiteDelegate
    let numberOfThreads: Int
    let allowFP16: Bool
    let enableXNNPACK: Bool
    
    enum TFLiteDelegate {
        case none
        case metal
        case coreML
        case gpu
        case nnapi
    }
    
    static let `default` = TFLiteConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        delegate: .metal,
        numberOfThreads: 4,
        allowFP16: true,
        enableXNNPACK: true
    )
}

// MARK: - picoLLM Configuration

struct PicoLLMConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // picoLLM specific
    let compressionLevel: CompressionLevel
    let voiceOptimized: Bool
    let realTimeMode: Bool
    let apiKey: String?
    
    enum CompressionLevel {
        case standard
        case high
        case ultra
        case custom(bits: Int)
    }
    
    static let `default` = PicoLLMConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        compressionLevel: .high,
        voiceOptimized: false,
        realTimeMode: false,
        apiKey: nil
    )
}

// MARK: - Swift Transformers Configuration

struct SwiftTransformersConfiguration: LLMFrameworkConfiguration {
    let enableLogging: Bool
    let logLevel: LogLevel
    let performanceTracking: Bool
    let memoryLimit: Int64?
    
    // Swift Transformers specific
    let modelSource: ModelSource
    let tokenizerType: TokenizerType
    let cacheDirectory: URL?
    let downloadTimeout: TimeInterval
    
    enum ModelSource {
        case huggingFace
        case local
        case custom(URL)
    }
    
    enum TokenizerType {
        case auto
        case gpt2
        case bert
        case llama
        case custom(String)
    }
    
    static let `default` = SwiftTransformersConfiguration(
        enableLogging: true,
        logLevel: .info,
        performanceTracking: true,
        memoryLimit: nil,
        modelSource: .huggingFace,
        tokenizerType: .auto,
        cacheDirectory: nil,
        downloadTimeout: 300
    )
}

// MARK: - Common Types

enum LogLevel: String, CaseIterable {
    case verbose = "VERBOSE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}