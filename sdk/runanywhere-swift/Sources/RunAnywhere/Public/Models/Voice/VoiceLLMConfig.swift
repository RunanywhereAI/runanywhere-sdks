import Foundation

/// Configuration for LLM generation in voice pipeline
public struct VoiceLLMConfig {
    /// Model identifier for LLM (nil uses current model)
    public let modelId: String?

    /// System prompt for conversation context
    public let systemPrompt: String?

    /// Enable streaming generation
    public let streamingEnabled: Bool

    /// Temperature for generation
    public let temperature: Float

    /// Maximum tokens to generate
    public let maxTokens: Int

    /// Convenience property for accessing streaming flag
    public var useStreaming: Bool {
        return streamingEnabled
    }

    public init(
        modelId: String? = nil,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true,
        temperature: Float = 0.7,
        maxTokens: Int = 100
    ) {
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.streamingEnabled = streamingEnabled
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}
