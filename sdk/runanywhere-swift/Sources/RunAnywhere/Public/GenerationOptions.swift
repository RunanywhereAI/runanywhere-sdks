import Foundation

/// Options for text generation
public struct GenerationOptions {
    /// Maximum number of tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling (0.0 - 1.0)
    public let temperature: Float

    /// Top-p sampling parameter
    public let topP: Float

    /// Context for the generation
    public let context: Context?

    /// Enable real-time tracking for cost dashboard
    public let enableRealTimeTracking: Bool

    /// Stop sequences
    public let stopSequences: [String]

    /// Seed for reproducible generation
    public let seed: Int?

    /// Enable streaming mode
    public let streamingEnabled: Bool

    /// Token budget constraint (for cost control)
    public let tokenBudget: TokenBudget?

    /// Framework-specific options
    public let frameworkOptions: FrameworkOptions?

    /// Preferred execution target
    public let preferredExecutionTarget: ExecutionTarget?

    /// Initialize generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate (default: 100)
    ///   - temperature: Sampling temperature (default: 0.7)
    ///   - topP: Top-p sampling (default: 1.0)
    ///   - context: Optional context
    ///   - enableRealTimeTracking: Enable real-time cost tracking (default: true)
    ///   - stopSequences: Stop generation at these sequences (default: empty)
    ///   - seed: Optional seed for reproducibility
    ///   - streamingEnabled: Enable streaming mode (default: false)
    ///   - tokenBudget: Token budget constraints
    ///   - frameworkOptions: Framework-specific options
    ///   - preferredExecutionTarget: Preferred execution target
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.7,
        topP: Float = 1.0,
        context: Context? = nil,
        enableRealTimeTracking: Bool = true,
        stopSequences: [String] = [],
        seed: Int? = nil,
        streamingEnabled: Bool = false,
        tokenBudget: TokenBudget? = nil,
        frameworkOptions: FrameworkOptions? = nil,
        preferredExecutionTarget: ExecutionTarget? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.context = context
        self.enableRealTimeTracking = enableRealTimeTracking
        self.stopSequences = stopSequences
        self.seed = seed
        self.streamingEnabled = streamingEnabled
        self.tokenBudget = tokenBudget
        self.frameworkOptions = frameworkOptions
        self.preferredExecutionTarget = preferredExecutionTarget
    }
}

/// Token budget constraints
public struct TokenBudget {
    /// Maximum tokens allowed
    public let maxTokens: Int

    /// Maximum cost allowed (in cents)
    public let maxCost: Double?

    /// Fallback behavior when budget exceeded
    public let fallbackBehavior: FallbackBehavior

    public enum FallbackBehavior {
        case stop
        case switchToDevice
        case truncate
    }

    public init(
        maxTokens: Int,
        maxCost: Double? = nil,
        fallbackBehavior: FallbackBehavior = .stop
    ) {
        self.maxTokens = maxTokens
        self.maxCost = maxCost
        self.fallbackBehavior = fallbackBehavior
    }
}

/// Framework-specific options
public struct FrameworkOptions {
    /// Core ML specific options
    public let coreMLOptions: CoreMLOptions?

    /// TensorFlow Lite specific options
    public let tfliteOptions: TFLiteOptions?

    /// MLX specific options
    public let mlxOptions: MLXOptions?

    /// GGUF/llama.cpp specific options
    public let ggufOptions: GGUFOptions?

    public init(
        coreMLOptions: CoreMLOptions? = nil,
        tfliteOptions: TFLiteOptions? = nil,
        mlxOptions: MLXOptions? = nil,
        ggufOptions: GGUFOptions? = nil
    ) {
        self.coreMLOptions = coreMLOptions
        self.tfliteOptions = tfliteOptions
        self.mlxOptions = mlxOptions
        self.ggufOptions = ggufOptions
    }
}

/// Core ML specific options
public struct CoreMLOptions {
    /// Use Neural Engine if available
    public let useNeuralEngine: Bool

    /// Compute units preference
    public let computeUnits: ComputeUnits

    public enum ComputeUnits {
        case all
        case cpuOnly
        case cpuAndGPU
        case cpuAndNeuralEngine
    }

    public init(
        useNeuralEngine: Bool = true,
        computeUnits: ComputeUnits = .all
    ) {
        self.useNeuralEngine = useNeuralEngine
        self.computeUnits = computeUnits
    }
}

/// TensorFlow Lite specific options
public struct TFLiteOptions {
    /// Number of threads to use
    public let numThreads: Int

    /// Use GPU delegate
    public let useGPUDelegate: Bool

    /// Use Core ML delegate
    public let useCoreMLDelegate: Bool

    public init(
        numThreads: Int = 4,
        useGPUDelegate: Bool = false,
        useCoreMLDelegate: Bool = true
    ) {
        self.numThreads = numThreads
        self.useGPUDelegate = useGPUDelegate
        self.useCoreMLDelegate = useCoreMLDelegate
    }
}

/// MLX specific options
public struct MLXOptions {
    /// Use unified memory
    public let useUnifiedMemory: Bool

    /// Metal performance shaders
    public let useMPS: Bool

    public init(
        useUnifiedMemory: Bool = true,
        useMPS: Bool = true
    ) {
        self.useUnifiedMemory = useUnifiedMemory
        self.useMPS = useMPS
    }
}

/// GGUF/llama.cpp specific options
public struct GGUFOptions {
    /// Number of layers to offload to GPU
    public let gpuLayers: Int

    /// Use memory mapping
    public let useMemoryMap: Bool

    /// Batch size
    public let batchSize: Int

    public init(
        gpuLayers: Int = 0,
        useMemoryMap: Bool = true,
        batchSize: Int = 8
    ) {
        self.gpuLayers = gpuLayers
        self.useMemoryMap = useMemoryMap
        self.batchSize = batchSize
    }
}
