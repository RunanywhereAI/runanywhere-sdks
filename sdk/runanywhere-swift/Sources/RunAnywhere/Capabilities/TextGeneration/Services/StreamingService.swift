import Foundation

/// Service for streaming text generation
public class StreamingService {
    private let generationService: GenerationService
    private let modelLoadingService: ModelLoadingService

    public init(generationService: GenerationService, modelLoadingService: ModelLoadingService? = nil) {
        self.generationService = generationService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
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

                    // Create context for the prompt
                    let context = Context(messages: [Message(role: .user, content: prompt)])
                    await loadedModel.service.setContext(context)

                    // Use the actual streaming method from the LLM service
                    try await loadedModel.service.streamGenerate(
                        prompt: prompt,
                        options: options,
                        onToken: { token in
                            continuation.yield(token)
                        }
                    )

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

                    // Create context for the prompt
                    let context = Context(messages: [Message(role: .user, content: prompt)])
                    await loadedModel.service.setContext(context)

                    var tokenIndex = 0

                    // Use the actual streaming method from the LLM service
                    try await loadedModel.service.streamGenerate(
                        prompt: prompt,
                        options: options,
                        onToken: { token in
                            let streamingToken = StreamingToken(
                                text: token,
                                tokenIndex: tokenIndex,
                                isLast: false, // We don't know if it's the last token
                                timestamp: Date()
                            )
                            tokenIndex += 1
                            continuation.yield(streamingToken)
                        }
                    )

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

/// Represents a streaming token
public struct StreamingToken {
    public let text: String
    public let tokenIndex: Int
    public let isLast: Bool
    public let timestamp: Date

    public init(text: String, tokenIndex: Int, isLast: Bool, timestamp: Date) {
        self.text = text
        self.tokenIndex = tokenIndex
        self.isLast = isLast
        self.timestamp = timestamp
    }
}
