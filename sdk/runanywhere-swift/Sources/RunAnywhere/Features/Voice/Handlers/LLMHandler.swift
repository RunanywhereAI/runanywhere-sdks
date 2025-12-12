import Foundation

/// Handles Language Model processing in the voice pipeline
public class VoiceLLMHandler {
    private let logger = SDKLogger(category: "LLMHandler")

    public init() {}

    /// Process transcript through LLM
    /// - Parameters:
    ///   - transcript: Input text from STT
    ///   - llmService: Optional LLM service
    ///   - config: LLM configuration
    ///   - streamingTTSHandler: Optional streaming TTS handler
    ///   - ttsEnabled: Whether TTS is enabled in pipeline
    ///   - continuation: Event stream continuation
    /// - Returns: LLM response text
    public func processWithLLM( // swiftlint:disable:this function_parameter_count
        transcript: String,
        llmService: LLMService?,
        config: LLMConfiguration?,
        streamingTTSHandler: StreamingTTSHandler?,
        ttsEnabled: Bool,
        ttsConfig: TTSConfiguration?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        continuation.yield(.llmThinking)

        let options = LLMGenerationOptions(
            maxTokens: config?.maxTokens ?? 100,
            temperature: Float(config?.temperature ?? 0.7),
            preferredFramework: config?.preferredFramework,
            systemPrompt: config?.systemPrompt
        )

        // Check if streaming is enabled (prefer streaming for voice pipelines)
        let useStreaming = config?.streamingEnabled ?? true

        if useStreaming, let service = llmService, service.isReady {
            // Use streaming for real-time responses
            return try await streamGenerate(
                transcript: transcript,
                llmService: service,
                options: options,
                streamingTTSHandler: streamingTTSHandler,
                ttsEnabled: ttsEnabled,
                ttsConfig: ttsConfig,
                continuation: continuation
            )
        } else {
            // Fall back to non-streaming generation
            return try await generateNonStreaming(
                transcript: transcript,
                llmService: llmService,
                options: options,
                continuation: continuation
            )
        }
    }

    // MARK: - Private Methods

    // swiftlint:disable:next function_parameter_count function_body_length
    private func streamGenerate(
        transcript: String,
        llmService: LLMService,
        options: LLMGenerationOptions,
        streamingTTSHandler: StreamingTTSHandler?,
        ttsEnabled: Bool,
        ttsConfig: TTSConfiguration?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        logger.debug("Using streaming LLM service for real-time generation")

        // Reset streaming TTS handler for new response
        streamingTTSHandler?.reset()

        var fullResponse = ""
        var responseContent = "" // Content without thinking
        var thinkingContent = ""
        var firstTokenReceived = false

        // Get current loaded model to check if it supports thinking
        let loadedModel = RunAnywhere.serviceContainer.generationService.getCurrentModel()
        let shouldParseThinking = loadedModel?.model.supportsThinking ?? false
        let thinkingPattern = loadedModel?.model.thinkingPattern ?? ThinkingTagPattern.defaultPattern

        // Buffers for thinking parsing
        var buffer = ""
        var inThinkingSection = false

        try await llmService.streamGenerate(
            prompt: transcript,
            options: options,
            onToken: { token in
                if !firstTokenReceived {
                    firstTokenReceived = true
                    continuation.yield(.llmStreamStarted)
                }
                fullResponse += token

                // Parse thinking if model supports it
                if shouldParseThinking {
                    let (tokenType, cleanToken) = ThinkingParser.parseStreamingToken(
                        token: token,
                        pattern: thinkingPattern,
                        buffer: &buffer,
                        inThinkingSection: &inThinkingSection
                    )

                    switch tokenType {
                    case .thinking:
                        // Thinking token - don't send to TTS or emit as stream token
                        if let thinking = cleanToken {
                            thinkingContent += thinking
                        }
                    case .content:
                        // Response content token - send to TTS and emit
                        if let content = cleanToken {
                            responseContent += content
                            continuation.yield(.llmStreamToken(content))

                            // Process token for streaming TTS if enabled (only response content, not thinking)
                            if ttsEnabled, let handler = streamingTTSHandler {
                                Task {
                                    let ttsOptions = TTSOptions(
                                        voice: ttsConfig?.voice,
                                        language: "en",
                                        rate: ttsConfig?.speakingRate ?? 1.0,
                                        pitch: ttsConfig?.pitch ?? 1.0,
                                        volume: ttsConfig?.volume ?? 1.0
                                    )
                                    await handler.processToken(content, options: ttsOptions, continuation: continuation)
                                }
                            }
                        }
                    }
                } else {
                    // No thinking parsing - treat all tokens as content
                    responseContent += token
                    continuation.yield(.llmStreamToken(token))

                    // Process token for streaming TTS if enabled
                    if ttsEnabled, let handler = streamingTTSHandler {
                        Task {
                            let ttsOptions = TTSOptions(
                                voice: ttsConfig?.voice,
                                language: "en",
                                rate: ttsConfig?.speakingRate ?? 1.0,
                                pitch: ttsConfig?.pitch ?? 1.0,
                                volume: ttsConfig?.volume ?? 1.0
                            )
                            await handler.processToken(token, options: ttsOptions, continuation: continuation)
                        }
                    }
                }
            }
        )

        // Flush any remaining text in TTS buffer
        if ttsEnabled, let handler = streamingTTSHandler {
            let ttsOptions = TTSOptions(
                voice: ttsConfig?.voice,
                language: "en",
                rate: ttsConfig?.speakingRate ?? 1.0,
                pitch: ttsConfig?.pitch ?? 1.0,
                volume: ttsConfig?.volume ?? 1.0
            )
            await handler.flushRemaining(options: ttsOptions, continuation: continuation)
        }

        // Return only the response content (without thinking)
        let finalResponse = shouldParseThinking ? responseContent : fullResponse
        continuation.yield(.llmFinalResponse(finalResponse))
        return finalResponse
    }

    private func generateNonStreaming(
        transcript: String,
        llmService: LLMService?,
        options: LLMGenerationOptions,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        let response: String

        if let llm = llmService, llm.isReady {
            // Use the provided LLM service if it's ready
            logger.debug("Using initialized LLM service for generation")
            response = try await llm.generate(
                prompt: transcript,
                options: options
            )
        } else {
            // Use the SDK's generation service directly
            logger.debug("Using GenerationService directly for LLM processing")
            let generationService = RunAnywhere.serviceContainer.generationService
            let result = try await generationService.generate(
                prompt: transcript,
                options: options
            )
            response = result.text
        }

        continuation.yield(.llmFinalResponse(response))
        return response
    }
}
