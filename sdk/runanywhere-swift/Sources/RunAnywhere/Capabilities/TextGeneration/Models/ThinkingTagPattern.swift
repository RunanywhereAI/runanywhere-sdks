import Foundation

/// Pattern for extracting thinking/reasoning content from model output
public struct ThinkingTagPattern {
    public let openingTag: String
    public let closingTag: String

    public init(openingTag: String, closingTag: String) {
        self.openingTag = openingTag
        self.closingTag = closingTag
    }

    /// Default pattern used by models like DeepSeek and Hermes
    public static let defaultPattern = ThinkingTagPattern(
        openingTag: "<think>",
        closingTag: "</think>"
    )

    /// Alternative pattern with full "thinking" word
    public static let thinkingPattern = ThinkingTagPattern(
        openingTag: "<thinking>",
        closingTag: "</thinking>"
    )
}
