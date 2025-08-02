import Foundation

/// Service for streaming text generation
public class StreamingService {
    private let generationService: GenerationService

    public init(generationService: GenerationService) {
        self.generationService = generationService
    }

    /// Generate streaming text using the loaded model
    public func generateStream(
        prompt: String,
        options: GenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // For now, simulate streaming by breaking up a regular generation
                    let result = try await generationService.generate(prompt: prompt, options: options)

                    // Split the result into chunks to simulate streaming
                    let words = result.text.components(separatedBy: " ")

                    for word in words {
                        continuation.yield(word + " ")

                        // Add a small delay to simulate streaming
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
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
                    // For now, simulate token streaming
                    let result = try await generationService.generate(prompt: prompt, options: options)

                    // Split into tokens (simplified)
                    let tokens = result.text.components(separatedBy: " ")

                    for (index, token) in tokens.enumerated() {
                        let streamingToken = StreamingToken(
                            text: token + " ",
                            tokenIndex: index,
                            isLast: index == tokens.count - 1,
                            timestamp: Date()
                        )

                        continuation.yield(streamingToken)

                        // Add a small delay to simulate streaming
                        try await Task.sleep(nanoseconds: 25_000_000) // 25ms
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
