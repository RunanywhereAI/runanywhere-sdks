import Foundation

/// Configuration for text generation behavior
public struct GenerationConfiguration: Codable, Sendable {
    /// Default generation settings
    public var defaults: DefaultGenerationSettings

    /// Token budget configuration (optional)
    public var tokenBudget: TokenBudgetConfiguration?

    /// Preferred frameworks for generation in order of preference
    public var frameworkPreferences: [LLMFramework]

    /// Maximum context length
    public var maxContextLength: Int

    /// Whether to enable thinking/reasoning extraction
    public var enableThinkingExtraction: Bool

    /// Pattern for thinking content extraction
    public var thinkingPattern: String?

    public init(
        defaults: DefaultGenerationSettings = DefaultGenerationSettings(),
        tokenBudget: TokenBudgetConfiguration? = nil,
        frameworkPreferences: [LLMFramework] = [],
        maxContextLength: Int = 4096,
        enableThinkingExtraction: Bool = false,
        thinkingPattern: String? = nil
    ) {
        self.defaults = defaults
        self.tokenBudget = tokenBudget
        self.frameworkPreferences = frameworkPreferences
        self.maxContextLength = maxContextLength
        self.enableThinkingExtraction = enableThinkingExtraction
        self.thinkingPattern = thinkingPattern
    }
}

/// Default settings for text generation
public struct DefaultGenerationSettings: Codable {
    /// Default temperature for generation
    public var temperature: Double

    /// Default maximum tokens for generation
    public var maxTokens: Int

    /// Default top-p value
    public var topP: Double

    /// Default top-k value
    public var topK: Int?

    /// Default repetition penalty
    public var repetitionPenalty: Double?

    /// Default stop sequences
    public var stopSequences: [String]?

    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 256,
        topP: Double = 0.9,
        topK: Int? = nil,
        repetitionPenalty: Double? = nil,
        stopSequences: [String]? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.stopSequences = stopSequences
    }
}

/// Token budget configuration for managing usage
public struct TokenBudgetConfiguration: Codable {
    /// Maximum tokens per request
    public var maxTokensPerRequest: Int?

    /// Maximum tokens per day
    public var maxTokensPerDay: Int?

    /// Maximum tokens per month
    public var maxTokensPerMonth: Int?

    /// Whether to enforce token limits strictly
    public var enforceStrictly: Bool

    public init(
        maxTokensPerRequest: Int? = nil,
        maxTokensPerDay: Int? = nil,
        maxTokensPerMonth: Int? = nil,
        enforceStrictly: Bool = false
    ) {
        self.maxTokensPerRequest = maxTokensPerRequest
        self.maxTokensPerDay = maxTokensPerDay
        self.maxTokensPerMonth = maxTokensPerMonth
        self.enforceStrictly = enforceStrictly
    }
}
