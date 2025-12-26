//
//  GenerationAnalyticsService.swift
//  RunAnywhere SDK
//
//  LLM Generation analytics service.
//  Tracks generation operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//
//  NOTE: ⚠️ Token estimation uses ~4 chars/token (approximation, not exact tokenizer count).
//  Actual token counts may vary depending on the model's tokenizer and input content.
//

import Foundation

// MARK: - Generation Analytics Service

/// LLM analytics service for tracking generation operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
///
/// Supports two generation modes:
/// - **Non-streaming** (`generate()`): Synchronous generation, no TTFT tracking
/// - **Streaming** (`generateStream()`): Asynchronous token-by-token generation with TTFT tracking
public actor GenerationAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "GenerationAnalytics")

    /// Active generation operations
    private var activeGenerations: [String: GenerationTracker] = [:]

    /// Metrics - separated by mode
    private var totalGenerations = 0
    private var streamingGenerations = 0
    private var nonStreamingGenerations = 0
    private var totalTimeToFirstToken: TimeInterval = 0
    private var streamingTTFTCount = 0  // Only count TTFT for streaming generations
    private var totalTokensPerSecond: Double = 0
    private var totalInputTokens = 0
    private var totalOutputTokens = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct GenerationTracker {
        let startTime: Date
        let isStreaming: Bool
        let framework: InferenceFramework
        let modelId: String
        let temperature: Float?
        let maxTokens: Int?
        let contextLength: Int?
        var firstTokenTime: Date?
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Generation Tracking

    /// Start tracking a non-streaming generation (generate())
    /// - Parameters:
    ///   - modelId: The model ID being used
    ///   - framework: The inference framework type
    ///   - temperature: Generation temperature
    ///   - maxTokens: Maximum tokens to generate
    ///   - contextLength: Context window size
    /// - Returns: A unique generation ID for tracking
    public func startGeneration(
        modelId: String,
        framework: InferenceFramework = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    ) -> String {
        let id = UUID().uuidString
        activeGenerations[id] = GenerationTracker(
            startTime: Date(),
            isStreaming: false,
            framework: framework,
            modelId: modelId,
            temperature: temperature,
            maxTokens: maxTokens,
            contextLength: contextLength
        )

        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: id,
            modelId: modelId,
            prompt: nil,
            isStreaming: false,
            framework: framework
        ))

        logger.debug("Non-streaming generation started: \(id)")
        return id
    }

    /// Start tracking a streaming generation (generateStream())
    /// - Parameters:
    ///   - modelId: The model ID being used
    ///   - framework: The inference framework type
    ///   - temperature: Generation temperature
    ///   - maxTokens: Maximum tokens to generate
    ///   - contextLength: Context window size
    /// - Returns: A unique generation ID for tracking
    public func startStreamingGeneration(
        modelId: String,
        framework: InferenceFramework = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    ) -> String {
        let id = UUID().uuidString
        activeGenerations[id] = GenerationTracker(
            startTime: Date(),
            isStreaming: true,
            framework: framework,
            modelId: modelId,
            temperature: temperature,
            maxTokens: maxTokens,
            contextLength: contextLength
        )

        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: id,
            modelId: modelId,
            prompt: nil,
            isStreaming: true,
            framework: framework
        ))

        logger.debug("Streaming generation started: \(id)")
        return id
    }

    /// Track first token for streaming generation (time-to-first-token metric)
    /// - Note: Only applicable for streaming generations. Call is ignored for non-streaming.
    public func trackFirstToken(generationId: String) {
        guard var tracker = activeGenerations[generationId], tracker.isStreaming else {
            // TTFT is only tracked for streaming generations
            return
        }

        // Only record if not already recorded
        guard tracker.firstTokenTime == nil else { return }

        let firstTokenTime = Date()
        tracker.firstTokenTime = firstTokenTime
        activeGenerations[generationId] = tracker

        let timeToFirstTokenMs = firstTokenTime.timeIntervalSince(tracker.startTime) * 1000

        EventPublisher.shared.track(LLMEvent.firstToken(
            generationId: generationId,
            modelId: tracker.modelId,
            timeToFirstTokenMs: timeToFirstTokenMs,
            framework: tracker.framework
        ))

        logger.debug("First token received for \(generationId): \(String(format: "%.1f", timeToFirstTokenMs))ms")
    }

    /// Track streaming update (analytics only)
    /// - Note: Only applicable for streaming generations
    public func trackStreamingUpdate(generationId: String, tokensGenerated: Int) {
        guard let tracker = activeGenerations[generationId], tracker.isStreaming else {
            return
        }

        EventPublisher.shared.track(LLMEvent.streamingUpdate(
            generationId: generationId,
            tokensGenerated: tokensGenerated
        ))
    }

    /// Complete a generation (works for both streaming and non-streaming)
    /// - Parameters:
    ///   - generationId: The generation ID from startGeneration or startStreamingGeneration
    ///   - inputTokens: Number of input tokens processed
    ///   - outputTokens: Number of output tokens generated
    ///   - modelId: The model ID used
    public func completeGeneration(
        generationId: String,
        inputTokens: Int,
        outputTokens: Int,
        modelId: String
    ) {
        guard let tracker = activeGenerations.removeValue(forKey: generationId) else { return }

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(tracker.startTime)
        let tokensPerSecond = totalTime > 0 ? Double(outputTokens) / totalTime : 0

        // Calculate TTFT for streaming generations
        var timeToFirstTokenMs: Double?
        if tracker.isStreaming, let firstTokenTime = tracker.firstTokenTime {
            let ttft = firstTokenTime.timeIntervalSince(tracker.startTime)
            timeToFirstTokenMs = ttft * 1000
            totalTimeToFirstToken += ttft
            streamingTTFTCount += 1
        }

        // Update metrics
        totalGenerations += 1
        if tracker.isStreaming {
            streamingGenerations += 1
        } else {
            nonStreamingGenerations += 1
        }
        totalTokensPerSecond += tokensPerSecond
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        lastEventTime = endTime

        EventPublisher.shared.track(LLMEvent.generationCompleted(
            generationId: generationId,
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: totalTime * 1000,
            tokensPerSecond: tokensPerSecond,
            isStreaming: tracker.isStreaming,
            timeToFirstTokenMs: timeToFirstTokenMs,
            framework: tracker.framework,
            temperature: tracker.temperature,
            maxTokens: tracker.maxTokens,
            contextLength: tracker.contextLength
        ))

        let modeStr = tracker.isStreaming ? "streaming" : "non-streaming"
        logger.debug("Generation completed (\(modeStr)): \(generationId)")
    }

    /// Track generation failure
    public func trackGenerationFailed(generationId: String, error: Error) {
        activeGenerations.removeValue(forKey: generationId)
        lastEventTime = Date()

        EventPublisher.shared.track(LLMEvent.generationFailed(
            generationId: generationId,
            error: SDKError.from(error, category: .llm)
        ))
    }

    /// Track an error during LLM operations with full SDKError context
    public func trackError(_ error: Error, operation: String, modelId: String? = nil, generationId: String? = nil) {
        lastEventTime = Date()
        let sdkError = SDKError.from(error, category: .llm)
        let errorEvent = SDKErrorEvent.llmError(
            error: sdkError,
            modelId: modelId,
            generationId: generationId,
            operation: operation
        )
        EventPublisher.shared.track(errorEvent)
    }

    // MARK: - Metrics

    public func getMetrics() -> GenerationMetrics {
        // Average TTFT only counts streaming generations that had TTFT recorded
        let avgTTFT = streamingTTFTCount > 0 ? totalTimeToFirstToken / Double(streamingTTFTCount) : 0

        return GenerationMetrics(
            totalEvents: totalGenerations,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalGenerations: totalGenerations,
            streamingGenerations: streamingGenerations,
            nonStreamingGenerations: nonStreamingGenerations,
            averageTimeToFirstToken: avgTTFT,
            averageTokensPerSecond: totalGenerations > 0 ? totalTokensPerSecond / Double(totalGenerations) : 0,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens
        )
    }
}

// MARK: - Generation Metrics

public struct GenerationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?

    /// Total number of all generations (streaming + non-streaming)
    public let totalGenerations: Int

    /// Number of streaming generations (generateStream())
    public let streamingGenerations: Int

    /// Number of non-streaming generations (generate())
    public let nonStreamingGenerations: Int

    /// Average time to first token in seconds (only for streaming generations)
    /// Returns 0 if no streaming generations have completed
    public let averageTimeToFirstToken: TimeInterval

    /// Average tokens per second across all generations
    public let averageTokensPerSecond: Double

    /// Total input tokens processed
    public let totalInputTokens: Int

    /// Total output tokens generated
    public let totalOutputTokens: Int

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalGenerations: Int = 0,
        streamingGenerations: Int = 0,
        nonStreamingGenerations: Int = 0,
        averageTimeToFirstToken: TimeInterval = 0,
        averageTokensPerSecond: Double = 0,
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalGenerations = totalGenerations
        self.streamingGenerations = streamingGenerations
        self.nonStreamingGenerations = nonStreamingGenerations
        self.averageTimeToFirstToken = averageTimeToFirstToken
        self.averageTokensPerSecond = averageTokensPerSecond
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}
