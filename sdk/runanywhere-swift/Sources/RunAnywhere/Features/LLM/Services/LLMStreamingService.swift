// swiftlint:disable file_length
//
//  LLMStreamingService.swift
//  RunAnywhere SDK
//
//  Service for streaming text generation
//

import Foundation

/// Service for streaming text generation
public class LLMStreamingService { // swiftlint:disable:this type_body_length

    private let generationService: LLMGenerationService
    private let modelLoadingService: ModelLoadingService
    private let analyticsService: DevAnalyticsSubmissionService
    private let optionsResolver = LLMOptionsResolver()
    private let logger = SDKLogger(category: "LLMStreamingService")

    public init(
        generationService: LLMGenerationService,
        modelLoadingService: ModelLoadingService? = nil,
        analyticsService: DevAnalyticsSubmissionService? = nil
    ) {
        self.generationService = generationService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
        self.analyticsService = analyticsService ?? DevAnalyticsSubmissionService.shared
    }

    // MARK: - Helper Methods

    /// Submit dev analytics for failed generation
    private func submitFailureAnalytics(
        modelName: String,
        error: Error,
        prompt: String,
        options: LLMGenerationOptions
    ) async {
        let inputTokens = TokenCounter.estimateTokenCount(prompt)

        await analyticsService.submitInternal(
            generationId: UUID().uuidString,
            modelId: modelName,
            latencyMs: 0,
            tokensPerSecond: 0,
            inputTokens: inputTokens,
            outputTokens: 0,
            success: false
        )

        let temperature = options.temperature
        let maxTokens = options.maxTokens
        let deviceInfo = TelemetryDeviceInfo.current
        let eventData = GenerationCompletionData(
            modelId: modelName,
            modelName: modelName,
            framework: nil,
            device: deviceInfo.device,
            osVersion: deviceInfo.osVersion,
            platform: deviceInfo.platform,
            sdkVersion: SDKConstants.version,
            processingTimeMs: nil,
            success: false,
            errorMessage: error.localizedDescription,
            inputTokens: inputTokens,
            outputTokens: 0,
            totalTokens: inputTokens,
            tokensPerSecond: nil,
            timeToFirstTokenMs: nil,
            generationTimeMs: nil,
            temperature: Double(temperature),
            maxTokens: maxTokens
        )
        let event = GenerationEvent(type: .generationCompleted, eventData: eventData)
        await AnalyticsQueueManager.shared.enqueue(event)
        await AnalyticsQueueManager.shared.flush()
    }

    /// Submit success analytics for completed generation
    private func submitSuccessAnalytics( // swiftlint:disable:this function_parameter_count
        result: LLMGenerationResult,
        modelName: String,
        prompt: String,
        options: LLMGenerationOptions,
        contextLength: Int?,
        framework: LLMFramework?
    ) async {
        let inputTokens = TokenCounter.estimateTokenCount(prompt)

        // Dev analytics
        await analyticsService.submitInternal(
            generationId: UUID().uuidString,
            modelId: result.modelUsed,
            latencyMs: result.latencyMs,
            tokensPerSecond: result.tokensPerSecond,
            inputTokens: inputTokens,
            outputTokens: result.tokensUsed,
            success: true
        )

        // Production telemetry
        let temperature = options.temperature
        let maxTokens = options.maxTokens
        let deviceInfo = TelemetryDeviceInfo.current
        let eventData = GenerationCompletionData(
            modelId: result.modelUsed,
            modelName: modelName,
            framework: framework?.rawValue,
            device: deviceInfo.device,
            osVersion: deviceInfo.osVersion,
            platform: deviceInfo.platform,
            sdkVersion: SDKConstants.version,
            processingTimeMs: result.latencyMs,
            success: true,
            inputTokens: inputTokens,
            outputTokens: result.tokensUsed,
            totalTokens: inputTokens + result.tokensUsed,
            tokensPerSecond: result.tokensPerSecond,
            timeToFirstTokenMs: nil,
            generationTimeMs: result.latencyMs,
            contextLength: contextLength,
            temperature: Double(temperature),
            maxTokens: maxTokens
        )
        let event = GenerationEvent(type: .generationCompleted, eventData: eventData)
        await AnalyticsQueueManager.shared.enqueue(event)
        await AnalyticsQueueManager.shared.flush()
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
    public func generateStreamWithMetrics( // swiftlint:disable:this function_body_length
        prompt: String,
        options: LLMGenerationOptions
    ) -> LLMStreamingResult {
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
            private var resultContinuation: CheckedContinuation<LLMGenerationResult, Error>?

            /// Reset start time to now - call this right before model inference begins
            func resetStartTime() {
                startTime = Date()
            }

            func recordToken(_ token: String, isThinking: Bool) {
                fullText += token
                tokenCount += 1

                // Only set firstTokenTime for non-empty tokens (real tokens from model)
                if firstTokenTime == nil && !token.isEmpty {
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

            func recordError(
                _ err: Error,
                modelName: String?,
                prompt: String,
                options: LLMGenerationOptions,
                submitAnalytics: @escaping (String, Error, String, LLMGenerationOptions) async -> Void
            ) {
                error = err
                resultContinuation?.resume(throwing: err)
                resultContinuation = nil

                // Submit analytics (non-blocking, silent failures)
                if let modelName = modelName {
                    Task.detached(priority: .background) {
                        await submitAnalytics(modelName, err, prompt, options)
                    }
                }
            }

            // swiftlint:disable:next function_parameter_count
            func recordStreamComplete(
                modelName: String,
                framework: LLMFramework?,
                prompt: String,
                options: LLMGenerationOptions,
                contextLength: Int?,
                submitAnalytics: @escaping (
                    LLMGenerationResult,
                    String,
                    String,
                    LLMGenerationOptions,
                    Int?,
                    LLMFramework?
                ) async -> Void
            ) {
                self.modelName = modelName
                self.framework = framework
                self.isComplete = true

                // Build result and resume continuation
                if let continuation = resultContinuation {
                    let result = buildResultSync(modelUsed: modelName, framework: framework)
                    continuation.resume(returning: result)
                    resultContinuation = nil

                    // Submit analytics (non-blocking, silent failures)
                    Task.detached(priority: .background) {
                        await submitAnalytics(result, modelName, prompt, options, contextLength, framework)
                    }
                }
            }

            func waitForResult() async throws -> LLMGenerationResult {
                // If already complete, return immediately
                if isComplete, let modelName = modelName {
                    return buildResultSync(modelUsed: modelName, framework: framework)
                }

                // Otherwise, wait for completion
                return try await withCheckedThrowingContinuation { continuation in
                    resultContinuation = continuation
                }
            }

            private func buildResultSync(modelUsed: String, framework: LLMFramework?) -> LLMGenerationResult {
                let endTime = Date()
                let totalTime = endTime.timeIntervalSince(startTime)

                // Use TokenCounter for accurate token counting
                let responseContent = fullText.replacingOccurrences(of: thinkingContent ?? "", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let tokenCounts = TokenCounter.splitTokenCounts(
                    fullText: fullText,
                    thinkingContent: thinkingContent,
                    responseContent: responseContent
                )

                // Calculate tokens per second
                let tokensPerSecond = TokenCounter.calculateTokensPerSecond(
                    tokenCount: tokenCounts.totalTokens,
                    elapsedSeconds: totalTime
                )

                return LLMGenerationResult(
                    text: fullText.replacingOccurrences(of: thinkingContent ?? "", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    thinkingContent: thinkingContent,
                    tokensUsed: tokenCounts.totalTokens,
                    modelUsed: modelUsed,
                    latencyMs: totalTime * 1000,
                    framework: framework,
                    tokensPerSecond: tokensPerSecond,
                    thinkingTokens: tokenCounts.thinkingTokens,
                    responseTokens: tokenCounts.responseTokens
                )
            }
        }

        let collector = MetricsCollector()

        // Create the token stream
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                var modelName: String?
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
                        throw RunAnywhereError.modelNotFound("No model is currently loaded")
                    }

                    modelName = loadedModel.model.name

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

                    // Reset start time RIGHT before inference begins
                    await collector.resetStartTime()

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
                        framework: loadedModel.model.compatibleFrameworks.first,
                        prompt: prompt,
                        options: resolvedOptions,
                        contextLength: loadedModel.model.contextLength,
                        submitAnalytics: self.submitSuccessAnalytics
                    )
                } catch {
                    await collector.recordError(
                        error,
                        modelName: modelName,
                        prompt: prompt,
                        options: options,
                        submitAnalytics: self.submitFailureAnalytics
                    )
                    continuation.finish(throwing: error)
                }
            }
        }

        // Create the result task that waits for metrics (NOT consuming stream)
        let resultTask = Task<LLMGenerationResult, Error> {
            // Wait for collector to signal completion
            return try await collector.waitForResult()
        }

        return LLMStreamingResult(stream: stream, result: resultTask)
    }

    /// Generate streaming text with token-level granularity
    public func generateTokenStream( // swiftlint:disable:this function_body_length
        prompt: String,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<StreamingToken, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get remote configuration
                    let remoteConfig = RunAnywhere.configurationData?.generation

                    // Apply remote constraints to options
                    let resolvedOptions = optionsResolver.resolve(
                        options: options,
                        remoteConfig: remoteConfig
                    )

                    // Get the current loaded model from generation service
                    guard let loadedModel = generationService.getCurrentModel() else {
                        throw RunAnywhereError.modelNotFound("No model is currently loaded")
                    }

                    // Prepare prompt with system prompt and structured output formatting
                    let effectivePrompt = optionsResolver.preparePrompt(prompt, withOptions: resolvedOptions)

                    // Check if model supports thinking and get pattern
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
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
