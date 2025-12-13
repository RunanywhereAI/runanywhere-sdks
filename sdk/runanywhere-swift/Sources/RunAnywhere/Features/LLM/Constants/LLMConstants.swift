import Foundation

/// LLM generation configuration constants
public enum LLMConstants {

    // MARK: - Generation Defaults

    /// Default temperature for generation
    public static let defaultTemperature: Double = 0.8

    /// Default maximum tokens
    public static let defaultMaxTokens: Int = 256

    /// Default top-p (nucleus sampling)
    public static let defaultTopP: Double = 0.95

    /// Default top-k sampling
    public static let defaultTopK: Int = 40

    /// Default context length for models
    public static let defaultContextLength: Int = 4096
}
