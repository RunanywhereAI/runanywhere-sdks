import Foundation

/// Tracks real-time performance metrics during generation
public actor PerformanceTracker {
    // MARK: - Properties

    private let generationId: UUID
    private let sessionId: UUID
    private let startTime: Date
    private var firstTokenTime: Date?
    private var tokenCount: Int = 0
    private var lastUpdateTime: Date

    private let metricsStream: AsyncStream<LiveGenerationMetrics>
    private let continuation: AsyncStream<LiveGenerationMetrics>.Continuation
    private var metricsTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(generationId: UUID, sessionId: UUID) {
        self.generationId = generationId
        self.sessionId = sessionId
        self.startTime = Date()
        self.lastUpdateTime = startTime

        // Create metrics stream
        var continuation: AsyncStream<LiveGenerationMetrics>.Continuation!
        self.metricsStream = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation

        // Start metrics timer
        self.metricsTask = Task { [weak self] in
            await self?.startMetricsTimer()
        }
    }https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf',
    }

    deinit {
        metricsTask?.cancel()
        continuation.finish()
    }https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf',

    // MARK: - Public Methods

    /// Record the first token generated
    public func recordFirstToken() {
        if firstTokenTime == nil {
            firstTokenTime = Date()
        }
    }

    /// Record a token generated
    public func recordToken() {
        tokenCount += 1
        if firstTokenTime == nil {
            recordFirstToken()
        }
        lastUpdateTime = Date()
    }

    /// Record multiple tokens at once
    public func recordTokens(_ count: Int) {
        tokenCount += count
        if firstTokenTime == nil && count > 0 {
            recordFirstToken()
        }
        lastUpdateTime = Date()
    }

    /// Complete tracking and return final performance metrics
    public func complete(
        result: AnalyticsGenerationResult,
        routingDecision: RoutingDecision,
        metrics: GenerationMetrics? = nil,
        cost: GenerationCost? = nil
    ) -> GenerationPerformance {
        metricsTask?.cancel()
        continuation.finish()

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)
        let timeToFirst = firstTokenTime?.timeIntervalSince(startTime) ?? 0

        // Use provided metrics or fall back to result metrics
        let finalMetrics = metrics ?? result.metrics

        return GenerationPerformance(
            timeToFirstToken: timeToFirst,
            totalGenerationTime: totalTime,
            inputTokens: finalMetrics.inputTokens,
            outputTokens: finalMetrics.outputTokens,
            tokensPerSecond: finalMetrics.tokensPerSecond,
            modelId: result.model.model.id,
            executionTarget: result.executionTarget,
            routingDecision: routingDecision
        )
    }

    /// Get the stream of live metrics
    public var liveMetricsStream: AsyncStream<LiveGenerationMetrics> {
        metricsStream
    }

    /// Get current metrics snapshot
    public func getCurrentMetrics() -> LiveGenerationMetrics {
        let elapsed = Date().timeIntervalSince(startTime)
        let tokensPerSecond = elapsed > 0 ? Double(tokenCount) / elapsed : 0

        return LiveGenerationMetrics(
            generationId: generationId,
            sessionId: sessionId,
            elapsedTime: elapsed,
            tokensGenerated: tokenCount,
            currentTokensPerSecond: tokensPerSecond,
            hasFirstToken: firstTokenTime != nil,
            timeToFirstToken: firstTokenTime?.timeIntervalSince(startTime)
        )
    }

    // MARK: - Private Methods

    private func startMetricsTimer() async {
        // Emit metrics every 100ms
        while !Task.isCancelled {
            let metrics = getCurrentMetrics()
            continuation.yield(metrics)

            // Sleep for 100ms
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                // Task cancelled
                break
            }
        }
    }
}
