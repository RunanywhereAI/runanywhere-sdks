import Foundation

// MARK: - Streaming Structured Output Types

/// Token emitted during streaming
public struct StreamToken: Sendable {
    public let text: String
    public let timestamp: Date
    public let tokenIndex: Int

    public init(text: String, timestamp: Date = Date(), tokenIndex: Int) {
        self.text = text
        self.timestamp = timestamp
        self.tokenIndex = tokenIndex
    }
}

/// Result containing both the token stream and final parsed result
/// Note: Uses @unchecked Sendable because generatable types are decoded safely in async context
public struct StructuredOutputStreamResult<T: Generatable>: @unchecked Sendable {
    /// Stream of tokens as they're generated
    public let tokenStream: AsyncThrowingStream<StreamToken, Error>

    /// Final parsed result (available after stream completes)
    public let result: Task<T, Error>
}
