import Foundation

/// Result of a text generation request
public struct GenerationResult {
    /// Generated text
    public let text: String

    /// Number of tokens used
    public let tokensUsed: Int

    /// Model used for generation
    public let modelUsed: String

    /// Latency in milliseconds
    public let latencyMs: TimeInterval

    /// Execution target (device/cloud/hybrid)
    public let executionTarget: ExecutionTarget

    /// Amount saved by using on-device execution
    public let savedAmount: Double

    /// Framework used for generation (if on-device)
    public let framework: LLMFramework?

    /// Hardware acceleration used
    public let hardwareUsed: HardwareAcceleration

    /// Memory used during generation (in bytes)
    public let memoryUsed: Int64

    /// Tokenizer format used
    public let tokenizerFormat: TokenizerFormat?

    /// Detailed performance metrics
    public let performanceMetrics: PerformanceMetrics

    /// Additional metadata
    public let metadata: ResultMetadata?

    /// Initializer
    internal init(
        text: String,
        tokensUsed: Int,
        modelUsed: String,
        latencyMs: TimeInterval,
        executionTarget: ExecutionTarget,
        savedAmount: Double,
        framework: LLMFramework? = nil,
        hardwareUsed: HardwareAcceleration = .cpu,
        memoryUsed: Int64 = 0,
        tokenizerFormat: TokenizerFormat? = nil,
        performanceMetrics: PerformanceMetrics,
        metadata: ResultMetadata? = nil
    ) {
        self.text = text
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.executionTarget = executionTarget
        self.savedAmount = savedAmount
        self.framework = framework
        self.hardwareUsed = hardwareUsed
        self.memoryUsed = memoryUsed
        self.tokenizerFormat = tokenizerFormat
        self.performanceMetrics = performanceMetrics
        self.metadata = metadata
    }
}

/// Detailed performance metrics
public struct PerformanceMetrics {
    /// Time spent on tokenization (milliseconds)
    public let tokenizationTimeMs: TimeInterval

    /// Time spent on inference (milliseconds)
    public let inferenceTimeMs: TimeInterval

    /// Time spent on post-processing (milliseconds)
    public let postProcessingTimeMs: TimeInterval

    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Peak memory usage during generation
    public let peakMemoryUsage: Int64

    /// Queue wait time if any (milliseconds)
    public let queueWaitTimeMs: TimeInterval

    public init(
        tokenizationTimeMs: TimeInterval = 0,
        inferenceTimeMs: TimeInterval = 0,
        postProcessingTimeMs: TimeInterval = 0,
        tokensPerSecond: Double = 0,
        peakMemoryUsage: Int64 = 0,
        queueWaitTimeMs: TimeInterval = 0
    ) {
        self.tokenizationTimeMs = tokenizationTimeMs
        self.inferenceTimeMs = inferenceTimeMs
        self.postProcessingTimeMs = postProcessingTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryUsage = peakMemoryUsage
        self.queueWaitTimeMs = queueWaitTimeMs
    }
}

/// Result metadata for additional strongly-typed information
public struct ResultMetadata {
    public let routingReason: RoutingReasonType
    public let fallbackUsed: Bool
    public let cacheHit: Bool
    public let modelVersion: String?
    public let experimentId: String?
    public let debugInfo: DebugInfo?

    public init(
        routingReason: RoutingReasonType,
        fallbackUsed: Bool = false,
        cacheHit: Bool = false,
        modelVersion: String? = nil,
        experimentId: String? = nil,
        debugInfo: DebugInfo? = nil
    ) {
        self.routingReason = routingReason
        self.fallbackUsed = fallbackUsed
        self.cacheHit = cacheHit
        self.modelVersion = modelVersion
        self.experimentId = experimentId
        self.debugInfo = debugInfo
    }
}

/// Strongly typed routing reason
public enum RoutingReasonType {
    case userPreference
    case costOptimization
    case performanceOptimization
    case resourceConstraint
    case policyDriven
    case fallback
    case experimental
}

/// Debug information for development
public struct DebugInfo {
    public let startTime: Date
    public let endTime: Date
    public let threadCount: Int
    public let deviceLoad: DeviceLoadLevel

    public init(startTime: Date, endTime: Date, threadCount: Int, deviceLoad: DeviceLoadLevel) {
        self.startTime = startTime
        self.endTime = endTime
        self.threadCount = threadCount
        self.deviceLoad = deviceLoad
    }
}

/// Device load level
public enum DeviceLoadLevel {
    case idle       // 0-20%
    case low        // 20-40%
    case moderate   // 40-60%
    case high       // 60-80%
    case critical   // 80-100%

    public init(percentage: Double) {
        switch percentage {
        case 0..<0.2:
            self = .idle
        case 0.2..<0.4:
            self = .low
        case 0.4..<0.6:
            self = .moderate
        case 0.6..<0.8:
            self = .high
        default:
            self = .critical
        }
    }
}
