import Foundation

/// Service for streaming text generation
public class StreamingService {
    private let generationService: GenerationService
    private let modelLoadingService: ModelLoadingService
    private let optionsResolver = GenerationOptionsResolver()

    public init(
        generationService: GenerationService,
        modelLoadingService: ModelLoadingService? = nil
    ) {
        self.generationService = generationService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
    }

    /// Generate streaming text using the loaded model
    ///
    /// Priority for settings resolution:
    /// 1. Runtime Options (highest priority) - User knows best for their specific request
    /// 2. Remote Configuration - Organization-wide defaults from console
    /// 3. SDK Defaults (lowest priority) - Fallback values when nothing else is specified
    public func generateStream(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
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
                    let thinkingPattern = ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false

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

                                // Only yield non-thinking tokens
                                if tokenType == .content, let cleanToken = cleanToken {
                                    continuation.yield(cleanToken)
                                }
                            } else {
                                // No thinking parsing, yield token as-is
                                continuation.yield(token)
                            }
                        }
                    )

                    // Yield any remaining content in buffer
                    if shouldParseThinking && !buffer.isEmpty && !inThinkingSection {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

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
                    let thinkingPattern = ThinkingTagPattern.defaultPattern

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
