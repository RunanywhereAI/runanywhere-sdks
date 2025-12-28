//
//  GenerationAnalyticsService.swift
//  RunAnywhere SDK
//
//  LLM Generation analytics service - THIN WRAPPER over C++ rac_llm_analytics_*.
//  Delegates all state management and metrics calculation to C++.
//  Swift handles: type conversion, event emission, logging.
//

import CRACommons
import Foundation

// MARK: - Generation Analytics Service

/// LLM analytics service for tracking generation operations.
/// Thin wrapper over C++ rac_llm_analytics_* functions.
public actor GenerationAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "GenerationAnalytics")
    private var handle: rac_llm_analytics_handle_t?

    // MARK: - Initialization

    public init() {
        var analyticsHandle: rac_llm_analytics_handle_t?
        let result = rac_llm_analytics_create(&analyticsHandle)
        if result == RAC_SUCCESS {
            self.handle = analyticsHandle
        } else {
            logger.error("Failed to create LLM analytics handle: \(result)")
        }
    }

    deinit {
        if let analyticsHandle = handle {
            rac_llm_analytics_destroy(analyticsHandle)
        }
    }

    // MARK: - Generation Tracking

    /// Start tracking a non-streaming generation (generate())
    public func startGeneration(
        modelId: String,
        framework: InferenceFramework = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    ) -> String {
        guard let analyticsHandle = handle else {
            logger.error("Analytics handle not initialized")
            return UUID().uuidString
        }

        var generationIdPtr: UnsafeMutablePointer<CChar>?
        let cFramework = framework.toCFramework()

        let result = callStartGeneration(
            handle: analyticsHandle,
            modelId: modelId,
            framework: cFramework,
            temperature: temperature,
            maxTokens: maxTokens,
            contextLength: contextLength,
            streaming: false,
            generationIdPtr: &generationIdPtr
        )

        let generationId: String
        if result == RAC_SUCCESS, let ptr = generationIdPtr {
            generationId = String(cString: ptr)
            rac_free(ptr)
        } else {
            generationId = UUID().uuidString
            logger.error("Failed to start generation in C++: \(result)")
        }

        // Emit Swift event
        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: generationId,
            modelId: modelId,
            prompt: nil,
            isStreaming: false,
            framework: framework
        ))

        logger.debug("Non-streaming generation started: \(generationId)")
        return generationId
    }

    /// Start tracking a streaming generation (generateStream())
    public func startStreamingGeneration(
        modelId: String,
        framework: InferenceFramework = .unknown,
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        contextLength: Int? = nil
    ) -> String {
        guard let analyticsHandle = handle else {
            logger.error("Analytics handle not initialized")
            return UUID().uuidString
        }

        var generationIdPtr: UnsafeMutablePointer<CChar>?
        let cFramework = framework.toCFramework()

        let result = callStartGeneration(
            handle: analyticsHandle,
            modelId: modelId,
            framework: cFramework,
            temperature: temperature,
            maxTokens: maxTokens,
            contextLength: contextLength,
            streaming: true,
            generationIdPtr: &generationIdPtr
        )

        let generationId: String
        if result == RAC_SUCCESS, let ptr = generationIdPtr {
            generationId = String(cString: ptr)
            rac_free(ptr)
        } else {
            generationId = UUID().uuidString
            logger.error("Failed to start streaming generation in C++: \(result)")
        }

        // Emit Swift event
        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: generationId,
            modelId: modelId,
            prompt: nil,
            isStreaming: true,
            framework: framework
        ))

        logger.debug("Streaming generation started: \(generationId)")
        return generationId
    }

    /// Helper to call start generation with optional parameters
    private func callStartGeneration(
        handle: rac_llm_analytics_handle_t,
        modelId: String,
        framework: rac_inference_framework_t,
        temperature: Float?,
        maxTokens: Int?,
        contextLength: Int?,
        streaming: Bool,
        generationIdPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    ) -> rac_result_t {
        return modelId.withCString { modelIdPtr in
            // Helper closure to call C API with optional pointers
            func callAPI(
                tempPtr: UnsafePointer<Float>?,
                maxTokPtr: UnsafePointer<Int32>?,
                ctxPtr: UnsafePointer<Int32>?
            ) -> rac_result_t {
                if streaming {
                    return rac_llm_analytics_start_streaming_generation(
                        handle,
                        modelIdPtr,
                        framework,
                        tempPtr,
                        maxTokPtr,
                        ctxPtr,
                        generationIdPtr
                    )
                } else {
                    return rac_llm_analytics_start_generation(
                        handle,
                        modelIdPtr,
                        framework,
                        tempPtr,
                        maxTokPtr,
                        ctxPtr,
                        generationIdPtr
                    )
                }
            }

            // Handle optional temperature
            if let temp = temperature {
                var tempValue = temp
                return withUnsafePointer(to: &tempValue) { tempPtr in
                    // Handle optional maxTokens
                    if let maxTok = maxTokens {
                        var maxTokValue = Int32(maxTok)
                        return withUnsafePointer(to: &maxTokValue) { maxTokPtr in
                            // Handle optional contextLength
                            if let ctx = contextLength {
                                var ctxValue = Int32(ctx)
                                return withUnsafePointer(to: &ctxValue) { ctxPtr in
                                    callAPI(tempPtr: tempPtr, maxTokPtr: maxTokPtr, ctxPtr: ctxPtr)
                                }
                            } else {
                                return callAPI(tempPtr: tempPtr, maxTokPtr: maxTokPtr, ctxPtr: nil)
                            }
                        }
                    } else {
                        if let ctx = contextLength {
                            var ctxValue = Int32(ctx)
                            return withUnsafePointer(to: &ctxValue) { ctxPtr in
                                callAPI(tempPtr: tempPtr, maxTokPtr: nil, ctxPtr: ctxPtr)
                            }
                        } else {
                            return callAPI(tempPtr: tempPtr, maxTokPtr: nil, ctxPtr: nil)
                        }
                    }
                }
            } else {
                // No temperature
                if let maxTok = maxTokens {
                    var maxTokValue = Int32(maxTok)
                    return withUnsafePointer(to: &maxTokValue) { maxTokPtr in
                        if let ctx = contextLength {
                            var ctxValue = Int32(ctx)
                            return withUnsafePointer(to: &ctxValue) { ctxPtr in
                                callAPI(tempPtr: nil, maxTokPtr: maxTokPtr, ctxPtr: ctxPtr)
                            }
                        } else {
                            return callAPI(tempPtr: nil, maxTokPtr: maxTokPtr, ctxPtr: nil)
                        }
                    }
                } else {
                    if let ctx = contextLength {
                        var ctxValue = Int32(ctx)
                        return withUnsafePointer(to: &ctxValue) { ctxPtr in
                            callAPI(tempPtr: nil, maxTokPtr: nil, ctxPtr: ctxPtr)
                        }
                    } else {
                        return callAPI(tempPtr: nil, maxTokPtr: nil, ctxPtr: nil)
                    }
                }
            }
        }
    }

    /// Track first token for streaming generation (time-to-first-token metric)
    public func trackFirstToken(generationId: String) {
        guard let analyticsHandle = handle else { return }

        _ = generationId.withCString { idPtr in
            rac_llm_analytics_track_first_token(analyticsHandle, idPtr)
        }

        logger.debug("First token tracked for \(generationId)")
    }

    /// Track streaming update (analytics only)
    public func trackStreamingUpdate(generationId: String, tokensGenerated: Int) {
        guard let analyticsHandle = handle else { return }

        _ = generationId.withCString { idPtr in
            rac_llm_analytics_track_streaming_update(analyticsHandle, idPtr, Int32(tokensGenerated))
        }

        EventPublisher.shared.track(LLMEvent.streamingUpdate(
            generationId: generationId,
            tokensGenerated: tokensGenerated
        ))
    }

    /// Complete a generation (works for both streaming and non-streaming)
    public func completeGeneration(
        generationId: String,
        inputTokens: Int,
        outputTokens: Int,
        modelId: String
    ) {
        guard let analyticsHandle = handle else { return }

        _ = generationId.withCString { idPtr in
            modelId.withCString { modelPtr in
                rac_llm_analytics_complete_generation(
                    analyticsHandle,
                    idPtr,
                    Int32(inputTokens),
                    Int32(outputTokens),
                    modelPtr
                )
            }
        }

        logger.debug("Generation completed: \(generationId)")

        // Emit Swift event
        EventPublisher.shared.track(LLMEvent.generationCompleted(
            generationId: generationId,
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: 0,  // C++ tracks this internally
            tokensPerSecond: 0,  // C++ calculates this
            isStreaming: false,
            timeToFirstTokenMs: nil,
            framework: .unknown,
            temperature: nil,
            maxTokens: nil,
            contextLength: nil
        ))
    }

    /// Track generation failure
    public func trackGenerationFailed(generationId: String, error: Error) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .llm)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = generationId.withCString { idPtr in
            sdkError.message.withCString { msgPtr in
                rac_llm_analytics_track_generation_failed(analyticsHandle, idPtr, errorCode, msgPtr)
            }
        }

        EventPublisher.shared.track(LLMEvent.generationFailed(
            generationId: generationId,
            error: sdkError
        ))
    }

    /// Track an error during LLM operations
    public func trackError(_ error: Error, operation: String, modelId: String? = nil, generationId: String? = nil) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .llm)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = operation.withCString { opPtr in
            sdkError.message.withCString { msgPtr in
                rac_llm_analytics_track_error(
                    analyticsHandle,
                    errorCode,
                    msgPtr,
                    opPtr,
                    modelId,
                    generationId
                )
            }
        }

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
        guard let analyticsHandle = handle else {
            return GenerationMetrics()
        }

        var cMetrics = rac_generation_metrics_t()
        let result = rac_llm_analytics_get_metrics(analyticsHandle, &cMetrics)

        guard result == RAC_SUCCESS else {
            logger.error("Failed to get metrics: \(result)")
            return GenerationMetrics()
        }

        return GenerationMetrics(
            totalEvents: Int(cMetrics.total_generations),
            startTime: Date(timeIntervalSince1970: Double(cMetrics.start_time_ms) / 1000.0),
            lastEventTime: cMetrics.last_event_time_ms > 0
                ? Date(timeIntervalSince1970: Double(cMetrics.last_event_time_ms) / 1000.0)
                : nil,
            totalGenerations: Int(cMetrics.total_generations),
            streamingGenerations: Int(cMetrics.streaming_generations),
            nonStreamingGenerations: Int(cMetrics.non_streaming_generations),
            averageTimeToFirstToken: cMetrics.average_ttft_ms / 1000.0,  // Convert ms to seconds
            averageTokensPerSecond: cMetrics.average_tokens_per_second,
            totalInputTokens: Int(cMetrics.total_input_tokens),
            totalOutputTokens: Int(cMetrics.total_output_tokens)
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
