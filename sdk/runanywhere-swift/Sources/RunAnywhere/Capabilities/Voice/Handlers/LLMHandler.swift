import Foundation
import os

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
    public func processWithLLM(
        transcript: String,
        llmService: LLMService?,
        config: VoiceLLMConfig?,
        streamingTTSHandler: StreamingTTSHandler?,
        ttsEnabled: Bool,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        continuation.yield(.llmThinking)

        let options = RunAnywhereGenerationOptions(
            maxTokens: config?.maxTokens ?? 100,
            temperature: config?.temperature ?? 0.7,
            systemPrompt: config?.systemPrompt
        )

        // Check if streaming is enabled (prefer streaming for voice pipelines)
        let useStreaming = config?.useStreaming ?? true

        if useStreaming && llmService != nil && llmService!.isReady {
            // Use streaming for real-time responses
            return try await streamGenerate(
                transcript: transcript,
                llmService: llmService!,
                options: options,
                streamingTTSHandler: streamingTTSHandler,
                ttsEnabled: ttsEnabled,
                ttsConfig: nil,
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

    private func streamGenerate(
        transcript: String,
        llmService: LLMService,
        options: RunAnywhereGenerationOptions,
        streamingTTSHandler: StreamingTTSHandler?,
        ttsEnabled: Bool,
        ttsConfig: VoiceTTSConfig?,
        continuation: AsyncThrowingStream<ModularPipelineEvent, Error>.Continuation
    ) async throws -> String {

        logger.debug("Using streaming LLM service for real-time generation")

        // Reset streaming TTS handler for new response
        streamingTTSHandler?.reset()

        var fullResponse = ""
        var firstTokenReceived = false

        try await llmService.streamGenerate(
            prompt: transcript,
            options: options,
            onToken: { token in
                if !firstTokenReceived {
                    firstTokenReceived = true
                    continuation.yield(.llmStreamStarted)
                }
                fullResponse += token
                continuation.yield(.llmStreamToken(token))

                // Process token for streaming TTS if enabled
                if ttsEnabled, let handler = streamingTTSHandler {
                    Task {
                        await handler.processStreamingText(
                            token,
                            config: ttsConfig,
                            continuation: continuation
                        )
                    }
                }
            }
        )

        // Flush any remaining text in TTS buffer
        if ttsEnabled, let handler = streamingTTSHandler {
            let ttsOptions = TTSOptions(
                voice: ttsConfig?.voice,
                language: "en",
                rate: ttsConfig?.rate ?? 1.0,
                pitch: ttsConfig?.pitch ?? 1.0,
                volume: ttsConfig?.volume ?? 1.0
            )
            await handler.flushRemaining(options: ttsOptions, continuation: continuation)
        }

        continuation.yield(.llmFinalResponse(fullResponse))
        return fullResponse
    }

    private func generateNonStreaming(
        transcript: String,
        llmService: LLMService?,
        options: RunAnywhereGenerationOptions,
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
            let generationService = RunAnywhereSDK.shared.serviceContainer.generationService
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
