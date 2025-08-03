import Foundation

/// Parser for extracting thinking/reasoning content from model output
public class ThinkingParser {

    /// Result of parsing thinking content
    public struct ParseResult {
        public let content: String           // Content without thinking tags
        public let thinkingContent: String?  // Extracted thinking content

        public init(content: String, thinkingContent: String?) {
            self.content = content
            self.thinkingContent = thinkingContent
        }
    }

    /// Parse and extract thinking content from text
    public static func parse(
        text: String,
        pattern: ThinkingTagPattern
    ) -> ParseResult {
        // Find the first occurrence of the opening tag
        guard let openRange = text.range(of: pattern.openingTag) else {
            // No thinking tags found
            return ParseResult(content: text, thinkingContent: nil)
        }

        // Find the corresponding closing tag
        guard let closeRange = text.range(of: pattern.closingTag, range: openRange.upperBound..<text.endIndex) else {
            // Opening tag found but no closing tag
            return ParseResult(content: text, thinkingContent: nil)
        }

        // Extract thinking content
        let thinkingContent = String(text[openRange.upperBound..<closeRange.lowerBound])

        // Remove thinking section from content
        var content = text
        content.removeSubrange(openRange.lowerBound..<closeRange.upperBound)

        // Trim any leading/trailing whitespace
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParseResult(
            content: content,
            thinkingContent: thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Parse streaming tokens and detect thinking sections
    public static func parseStreamingToken(
        token: String,
        pattern: ThinkingTagPattern,
        buffer: inout String,
        inThinkingSection: inout Bool
    ) -> (tokenType: TokenType, cleanToken: String?) {
        // Add token to buffer
        buffer += token

        // Check if we're entering a thinking section
        if !inThinkingSection && buffer.contains(pattern.openingTag) {
            // Found opening tag
            if let range = buffer.range(of: pattern.openingTag) {
                // Extract any content before the thinking tag
                let beforeThinking = String(buffer[..<range.lowerBound])

                // Update buffer to start after opening tag
                buffer = String(buffer[range.upperBound...])
                inThinkingSection = true

                // Return any content before thinking as regular content
                if !beforeThinking.isEmpty {
                    return (.content, beforeThinking)
                }
            }
        }

        // Check if we're exiting a thinking section
        if inThinkingSection && buffer.contains(pattern.closingTag) {
            // Found closing tag
            if let range = buffer.range(of: pattern.closingTag) {
                // Extract thinking content
                let thinkingContent = String(buffer[..<range.lowerBound])

                // Update buffer to start after closing tag
                buffer = String(buffer[range.upperBound...])
                inThinkingSection = false

                // Return the thinking content
                if !thinkingContent.isEmpty {
                    return (.thinking, thinkingContent)
                }

                // Check if there's content after the closing tag
                if !buffer.isEmpty {
                    let content = buffer
                    buffer = ""
                    return (.content, content)
                }
            }
        }

        // If we're in a thinking section, accumulate tokens
        if inThinkingSection {
            // Don't emit anything yet, just accumulate
            return (.thinking, nil)
        }

        // Regular content token
        let content = buffer
        buffer = ""
        return (.content, content.isEmpty ? nil : content)
    }
}
