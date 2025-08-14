import Foundation

/// Protocol for monitoring voice processing performance
public protocol VoicePerformanceMonitor: AnyObject {
    /// Track a transcription operation
    /// - Parameters:
    ///   - duration: Time taken to perform transcription
    ///   - audioLength: Length of the audio transcribed
    ///   - model: Model used for transcription
    func trackTranscription(duration: TimeInterval, audioLength: TimeInterval, model: String)

    /// Track a text-to-speech operation
    /// - Parameters:
    ///   - duration: Time taken to generate speech
    ///   - textLength: Number of characters in the text
    ///   - voice: Voice used for synthesis
    func trackTTS(duration: TimeInterval, textLength: Int, voice: String)

    /// Track a voice activity detection operation
    /// - Parameters:
    ///   - processingTime: Time taken to process
    ///   - audioLength: Length of audio analyzed
    func trackVAD(processingTime: TimeInterval, audioLength: TimeInterval)

    /// Track an LLM generation operation
    /// - Parameters:
    ///   - duration: Time taken to generate response
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    ///   - model: Model used for generation
    func trackLLMGeneration(
        duration: TimeInterval,
        inputTokens: Int,
        outputTokens: Int,
        model: String
    )

    /// Track end-to-end latency for a voice interaction
    /// - Parameters:
    ///   - duration: Total time from input to output
    ///   - sessionId: ID of the voice session
    func trackEndToEndLatency(duration: TimeInterval, sessionId: String)

    /// Get current performance metrics
    /// - Returns: Current voice performance metrics
    func getMetrics() -> VoicePerformanceMetrics

    /// Reset all tracked metrics
    func reset()
}

/// Voice processing performance metrics
public struct VoicePerformanceMetrics {
    /// Average real-time factor for transcription (< 1.0 is real-time)
    public let averageTranscriptionRTF: Float

    /// Average latency for TTS generation
    public let averageTTSLatency: TimeInterval

    /// Average latency for VAD processing
    public let averageVADLatency: TimeInterval

    /// Average latency for LLM generation
    public let averageLLMLatency: TimeInterval

    /// Average end-to-end latency
    public let averageEndToEndLatency: TimeInterval

    /// Total number of transcriptions performed
    public let totalTranscriptions: Int

    /// Total number of TTS operations
    public let totalTTSOperations: Int

    /// Total number of voice sessions
    public let totalSessions: Int

    /// Performance breakdown by model
    public let modelPerformance: [String: ModelMetrics]

    /// Performance percentiles
    public let percentiles: PerformancePercentiles

    public init(
        averageTranscriptionRTF: Float,
        averageTTSLatency: TimeInterval,
        averageVADLatency: TimeInterval,
        averageLLMLatency: TimeInterval,
        averageEndToEndLatency: TimeInterval,
        totalTranscriptions: Int,
        totalTTSOperations: Int,
        totalSessions: Int,
        modelPerformance: [String: ModelMetrics],
        percentiles: PerformancePercentiles
    ) {
        self.averageTranscriptionRTF = averageTranscriptionRTF
        self.averageTTSLatency = averageTTSLatency
        self.averageVADLatency = averageVADLatency
        self.averageLLMLatency = averageLLMLatency
        self.averageEndToEndLatency = averageEndToEndLatency
        self.totalTranscriptions = totalTranscriptions
        self.totalTTSOperations = totalTTSOperations
        self.totalSessions = totalSessions
        self.modelPerformance = modelPerformance
        self.percentiles = percentiles
    }
}

/// Performance metrics for a specific model
public struct ModelMetrics {
    /// Model identifier
    public let modelId: String

    /// Average processing time
    public let averageLatency: TimeInterval

    /// Minimum processing time
    public let minLatency: TimeInterval

    /// Maximum processing time
    public let maxLatency: TimeInterval

    /// Total operations performed
    public let operationCount: Int

    /// Average real-time factor (for transcription models)
    public let averageRTF: Float?

    /// Success rate (0.0 to 1.0)
    public let successRate: Float

    public init(
        modelId: String,
        averageLatency: TimeInterval,
        minLatency: TimeInterval,
        maxLatency: TimeInterval,
        operationCount: Int,
        averageRTF: Float? = nil,
        successRate: Float = 1.0
    ) {
        self.modelId = modelId
        self.averageLatency = averageLatency
        self.minLatency = minLatency
        self.maxLatency = maxLatency
        self.operationCount = operationCount
        self.averageRTF = averageRTF
        self.successRate = successRate
    }
}

/// Performance percentiles for latency analysis
public struct PerformancePercentiles {
    /// 50th percentile (median) latency
    public let p50: TimeInterval

    /// 90th percentile latency
    public let p90: TimeInterval

    /// 95th percentile latency
    public let p95: TimeInterval

    /// 99th percentile latency
    public let p99: TimeInterval

    public init(
        p50: TimeInterval,
        p90: TimeInterval,
        p95: TimeInterval,
        p99: TimeInterval
    ) {
        self.p50 = p50
        self.p90 = p90
        self.p95 = p95
        self.p99 = p99
    }
}
