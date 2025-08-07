import Foundation

/// Service for streaming text generation
public class StreamingService {
    private let generationService: GenerationService
    private let modelLoadingService: ModelLoadingService
    private let structuredOutputHandler: StructuredOutputHandler

    public init(
        generationService: GenerationService,
        modelLoadingService: ModelLoadingService? = nil,
        structuredOutputHandler: StructuredOutputHandler? = nil
    ) {
        self.generationService = generationService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
        self.structuredOutputHandler = structuredOutputHandler ?? StructuredOutputHandler()
    }

    /// Generate streaming text using the loaded model
    public func generateStream(
        prompt: String,
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get the current loaded model from generation service
                    guard let loadedModel = generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Prepare prompt with structured output if needed
                    let effectivePrompt: String
                    if let structuredConfig = options.structuredOutput {
                        effectivePrompt = self.structuredOutputHandler.preparePrompt(
                            originalPrompt: prompt,
                            config: structuredConfig
                        )
                    } else {
                        effectivePrompt = prompt
                    }


                    // Check if model supports thinking and get pattern
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
                    let thinkingPattern = modelInfo.thinkingTagPattern ?? ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false

                    // Use the actual streaming method from the LLM service
                    try await loadedModel.service.streamGenerate(
                        prompt: effectivePrompt,
                        options: options,
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
        options: GenerationOptions
    ) -> AsyncThrowingStream<StreamingToken, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get the current loaded model from generation service
                    guard let loadedModel = generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Prepare prompt with structured output if needed
                    let effectivePrompt: String
                    if let structuredConfig = options.structuredOutput {
                        effectivePrompt = self.structuredOutputHandler.preparePrompt(
                            originalPrompt: prompt,
                            config: structuredConfig
                        )
                    } else {
                        effectivePrompt = prompt
                    }


                    // Check if model supports thinking and get pattern
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
                    let thinkingPattern = modelInfo.thinkingTagPattern ?? ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false

                    var tokenIndex = 0

                    // Use the actual streaming method from the LLM service
                    try await loadedModel.service.streamGenerate(
                        prompt: effectivePrompt,
                        options: options,
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
