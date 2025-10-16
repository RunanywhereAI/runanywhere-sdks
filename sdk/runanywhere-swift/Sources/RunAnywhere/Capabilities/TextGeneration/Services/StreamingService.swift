import Foundation

/// Service for streaming text generation
public class StreamingService {
    private let generationService: GenerationService
    private let modelLoadingService: ModelLoadingService
    private let optionsResolver = GenerationOptionsResolver()
    private let logger = SDKLogger(category: "StreamingService")

    public init(
        generationService: GenerationService,
        modelLoadingService: ModelLoadingService? = nil
    ) {
        self.generationService = generationService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
    }

    /// Generate streaming text with metrics tracking
    ///
    /// Returns both the token stream and a task that resolves to final metrics.
    /// This is the recommended method for streaming with analytics.
    ///
    /// Priority for settings resolution:
    /// 1. Runtime Options (highest priority) - User knows best for their specific request
    /// 2. Remote Configuration - Organization-wide defaults from console
    /// 3. SDK Defaults (lowest priority) - Fallback values when nothing else is specified
    public func generateStreamWithMetrics(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) -> StreamingResult {
        // Shared state between stream and result task
        actor MetricsCollector {
            var fullText = ""
            var thinkingContent: String?
            var startTime = Date()
            var firstTokenTime: Date?
            var thinkingStartTime: Date?
            var thinkingEndTime: Date?
            var tokenCount = 0
            var error: Error?
            var isComplete = false
            var modelName: String?
            var framework: LLMFramework?

            // Continuation for result task
            private var resultContinuation: CheckedContinuation<GenerationResult, Error>?

            func recordToken(_ token: String, isThinking: Bool) {
                fullText += token
                tokenCount += 1

                if firstTokenTime == nil {
                    firstTokenTime = Date()
                }

                if isThinking && thinkingStartTime == nil {
                    thinkingStartTime = Date()
                }
            }

            func recordThinkingEnd(_ thinking: String) {
                thinkingContent = thinking
                thinkingEndTime = Date()
            }

            func recordError(_ err: Error) {
                error = err
                resultContinuation?.resume(throwing: err)
                resultContinuation = nil
            }

            func recordStreamComplete(modelName: String, framework: LLMFramework?) {
                self.modelName = modelName
                self.framework = framework
                self.isComplete = true

                // Build result and resume continuation
                if let continuation = resultContinuation {
                    let result = buildResultSync(modelUsed: modelName, framework: framework)
                    continuation.resume(returning: result)
                    resultContinuation = nil
                }
            }

            func waitForResult() async throws -> GenerationResult {
                // If already complete, return immediately
                if isComplete, let modelName = modelName {
                    return buildResultSync(modelUsed: modelName, framework: framework)
                }

                // Otherwise, wait for completion
                return try await withCheckedThrowingContinuation { continuation in
                    resultContinuation = continuation
                }
            }

            private func buildResultSync(modelUsed: String, framework: LLMFramework?) -> GenerationResult {
                let endTime = Date()
                let totalTime = endTime.timeIntervalSince(startTime)

                // Use TokenCounter for accurate token counting
                let tokenCounts = TokenCounter.splitTokenCounts(
                    fullText: fullText,
                    thinkingContent: thinkingContent,
                    responseContent: fullText.replacingOccurrences(of: thinkingContent ?? "", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                )

                // Calculate timing metrics
                let timeToFirstToken = firstTokenTime?.timeIntervalSince(startTime)
                let thinkingTime = (thinkingStartTime != nil && thinkingEndTime != nil)
                    ? thinkingEndTime!.timeIntervalSince(thinkingStartTime!) : nil
                let responseTime = thinkingTime != nil ? totalTime - thinkingTime! : totalTime

                // Calculate tokens per second
                let tokensPerSecond = TokenCounter.calculateTokensPerSecond(
                    tokenCount: tokenCounts.totalTokens,
                    elapsedSeconds: totalTime
                )

                let performanceMetrics = PerformanceMetrics(
                    tokenizationTimeMs: 0,
                    inferenceTimeMs: totalTime * 1000,
                    postProcessingTimeMs: 0,
                    tokensPerSecond: tokensPerSecond,
                    peakMemoryUsage: 0,
                    queueWaitTimeMs: 0,
                    timeToFirstTokenMs: timeToFirstToken.map { $0 * 1000 },
                    thinkingTimeMs: thinkingTime.map { $0 * 1000 },
                    responseTimeMs: responseTime * 1000,
                    thinkingStartTimeMs: thinkingStartTime != nil ? thinkingStartTime!.timeIntervalSince(startTime) * 1000 : nil,
                    thinkingEndTimeMs: thinkingEndTime != nil ? thinkingEndTime!.timeIntervalSince(startTime) * 1000 : nil,
                    firstResponseTokenTimeMs: firstTokenTime != nil ? firstTokenTime!.timeIntervalSince(startTime) * 1000 : nil
                )

                return GenerationResult(
                    text: fullText.replacingOccurrences(of: thinkingContent ?? "", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                    thinkingContent: thinkingContent,
                    tokensUsed: tokenCounts.totalTokens,
                    modelUsed: modelUsed,
                    latencyMs: totalTime * 1000,
                    executionTarget: .onDevice,
                    savedAmount: 0.0,
                    framework: framework,
                    hardwareUsed: .cpu,
                    memoryUsed: 0,
                    performanceMetrics: performanceMetrics,
                    thinkingTokens: tokenCounts.thinkingTokens,
                    responseTokens: tokenCounts.responseTokens
                )
            }
        }

        let collector = MetricsCollector()

        // Create the token stream
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    // Get remote configuration
                    let remoteConfig = RunAnywhere.configurationData?.generation

                    // Apply remote constraints to options
                    let resolvedOptions = optionsResolver.resolve(
                        options: options,
                        remoteConfig: remoteConfig
                    )

                    // Get the current loaded model
                    guard let loadedModel = generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Prepare prompt
                    let effectivePrompt = optionsResolver.preparePrompt(prompt, withOptions: resolvedOptions)

                    // Check if model supports thinking
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
                    let thinkingPattern = modelInfo.thinkingPattern ?? ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false
                    var accumulatedThinking = ""

                    // Start timing
                    await collector.recordToken("", isThinking: false) // Initialize timing

                    // Use the actual streaming method
                    try await loadedModel.service.streamGenerate(
                        prompt: effectivePrompt,
                        options: resolvedOptions,
                        onToken: { token in
                            Task {
                                if shouldParseThinking {
                                    // Parse token for thinking content
                                    let (tokenType, cleanToken) = ThinkingParser.parseStreamingToken(
                                        token: token,
                                        pattern: thinkingPattern,
                                        buffer: &buffer,
                                        inThinkingSection: &inThinkingSection
                                    )

                                    // Track thinking content
                                    if tokenType == .thinking, let thinkingToken = cleanToken {
                                        accumulatedThinking += thinkingToken
                                    }

                                    // Record metrics
                                    await collector.recordToken(token, isThinking: inThinkingSection)

                                    // Only yield non-thinking tokens
                                    if tokenType == .content, let cleanToken = cleanToken {
                                        continuation.yield(cleanToken)
                                    }
                                } else {
                                    // No thinking parsing
                                    await collector.recordToken(token, isThinking: false)
                                    continuation.yield(token)
                                }
                            }
                        }
                    )

                    // Record thinking content if any
                    if !accumulatedThinking.isEmpty {
                        await collector.recordThinkingEnd(accumulatedThinking)
                    }

                    // Yield any remaining content in buffer
                    if shouldParseThinking && !buffer.isEmpty && !inThinkingSection {
                        continuation.yield(buffer)
                    }

                    continuation.finish()

                    // After stream finishes, signal completion to result task
                    await collector.recordStreamComplete(
                        modelName: loadedModel.model.name,
                        framework: loadedModel.model.compatibleFrameworks.first
                    )
                } catch {
                    await collector.recordError(error)
                    continuation.finish(throwing: error)
                }
            }
        }

        // Create the result task that waits for metrics (NOT consuming stream)
        let resultTask = Task<GenerationResult, Error> {
            // Wait for collector to signal completion
            return try await collector.waitForResult()
        }

        return StreamingResult(stream: stream, result: resultTask)
    }

    // Note: Legacy generateStream() method removed - use generateStreamWithMetrics() instead
    // All streaming now includes metrics by default

    /// Generate streaming text with token-level granularity
    public func generateTokenStream(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) -> AsyncThrowingStream<StreamingToken, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get remote configuration
                    let remoteConfig = RunAnywhere.configurationData?.generation

                    // Apply remote constraints to options (respecting priority: Runtime > Remote > SDK Defaults)
                    let resolvedOptions = optionsResolver.resolve(
                        options: options,
                        remoteConfig: remoteConfig
                    )

                    // Get the current loaded model from generation service
                    guard let loadedModel = generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Prepare prompt with system prompt and structured output formatting
                    let effectivePrompt = optionsResolver.preparePrompt(prompt, withOptions: resolvedOptions)


                    // Check if model supports thinking and get pattern
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
                    // Use model-specific pattern or fall back to default
                    let thinkingPattern = modelInfo.thinkingPattern ?? ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false

                    var tokenIndex = 0

                    // Use the actual streaming method from the LLM service
                    try await loadedModel.service.streamGenerate(
                        prompt: effectivePrompt,
                        options: resolvedOptions,
                        onToken: { token in
                            if shouldParseThinking {
                                // Parse token for thinking content
                                let (tokenType, cleanToken) = ThinkingParser.parseStreamingToken(
                                    token: token,
                                    pattern: thinkingPattern,
                                    buffer: &buffer,
                                    inThinkingSection: &inThinkingSection
                                )

                                if let cleanToken = cleanToken {
                                    let streamingToken = StreamingToken(
                                        text: cleanToken,
                                        tokenIndex: tokenIndex,
                                        isLast: false,
                                        timestamp: Date(),
                                        type: tokenType
                                    )
                                    tokenIndex += 1
                                    continuation.yield(streamingToken)
                                }
                            } else {
                                // No thinking parsing, yield token as-is
                                let streamingToken = StreamingToken(
                                    text: token,
                                    tokenIndex: tokenIndex,
                                    isLast: false,
                                    timestamp: Date(),
                                    type: .content
                                )
                                tokenIndex += 1
                                continuation.yield(streamingToken)
                            }
                        }
                    )

                    // Yield any remaining content in buffer
                    if shouldParseThinking && !buffer.isEmpty {
                        let tokenType: TokenType = inThinkingSection ? .thinking : .content
                        let streamingToken = StreamingToken(
                            text: buffer,
                            tokenIndex: tokenIndex,
                            isLast: true,
                            timestamp: Date(),
                            type: tokenType
                        )
                        continuation.yield(streamingToken)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Check if service is healthy
    public func isHealthy() -> Bool {
        // Basic health check - always return true for now
        return true
    }
}

// MARK: - Supporting Types

/// Token type for streaming
public enum TokenType {
    case thinking  // Token is part of model's thinking/reasoning
    case content   // Token is part of the actual response
}

/// Represents a streaming token
public struct StreamingToken {
    public let text: String
    public let tokenIndex: Int
    public let isLast: Bool
    public let timestamp: Date
    public let type: TokenType

    public init(text: String, tokenIndex: Int, isLast: Bool, timestamp: Date, type: TokenType = .content) {
        self.text = text
        self.tokenIndex = tokenIndex
        self.isLast = isLast
        self.timestamp = timestamp
        self.type = type
    }
}
