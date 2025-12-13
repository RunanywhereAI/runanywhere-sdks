import Foundation

// MARK: - Generation Hints

/// Hints for customizing structured output generation
public struct GenerationHints: Sendable {
    public let temperature: Float?
    public let maxTokens: Int?
    public let systemRole: String?

    public init(temperature: Float? = nil, maxTokens: Int? = nil, systemRole: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemRole = systemRole
    }
}

// MARK: - Generatable Protocol Extensions

extension Generatable {
    /// Type-specific generation hints
    public static var generationHints: GenerationHints? {
        return nil
    }
}
