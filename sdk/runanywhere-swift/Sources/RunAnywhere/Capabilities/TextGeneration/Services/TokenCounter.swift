import Foundation

/// Result of splitting token counts between thinking and response content
public struct TokenCountResult {
    public let thinkingTokens: Int?
    public let responseTokens: Int
    public let totalTokens: Int

    public init(thinkingTokens: Int?, responseTokens: Int, totalTokens: Int) {
        self.thinkingTokens = thinkingTokens
        self.responseTokens = responseTokens
        self.totalTokens = totalTokens
    }
}

/// Service for counting tokens in text with improved accuracy
public class TokenCounter {

    /// Count tokens with improved estimation (more accurate than simple word count)
    /// This is a heuristic approach until we integrate actual tokenizers
    public static func estimateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        // Improved heuristic based on GPT tokenization patterns:
        // - Average ~4 characters per token for English text
        // - Punctuation often creates separate tokens
        // - Whitespace handling
        // - Special characters

        let characterCount = text.count
        let wordCount = text.split(separator: " ").count

        // Count punctuation marks (often separate tokens)
        let punctuationCount = text.filter { ".,!?;:()[]{}\"'".contains($0) }.count

        // Count newlines and special whitespace (often separate tokens)
        let newlineCount = text.filter { $0.isNewline }.count

        // Heuristic formula:
        // Base estimate: characters / 4 (GPT average)
        // Add extra tokens for punctuation (most become separate tokens)
        // Add tokens for newlines
        // Ensure we're at least counting words (minimum tokens)

        let baseEstimate = Double(characterCount) / 4.0
        let punctuationTokens = Double(punctuationCount) * 0.7 // Most punctuation becomes tokens
        let newlineTokens = Double(newlineCount)

        let estimatedTokens = Int(ceil(baseEstimate + punctuationTokens + newlineTokens))

        // Sanity check: token count should be between word count and character count
        return max(wordCount, min(estimatedTokens, characterCount))
    }

    /// Estimate tokens per second based on token count and elapsed time
    public static func calculateTokensPerSecond(tokenCount: Int, elapsedSeconds: TimeInterval) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(tokenCount) / elapsedSeconds
    }

    /// Split token count between thinking and response content
    public static func splitTokenCounts(
        fullText: String,
        thinkingContent: String?,
        responseContent: String
    ) -> TokenCountResult {
        let responseTokens = estimateTokenCount(responseContent)

        if let thinking = thinkingContent, !thinking.isEmpty {
            let thinkingTokens = estimateTokenCount(thinking)
            let totalTokens = thinkingTokens + responseTokens
            return TokenCountResult(thinkingTokens: thinkingTokens, responseTokens: responseTokens, totalTokens: totalTokens)
        } else {
            return TokenCountResult(thinkingTokens: nil, responseTokens: responseTokens, totalTokens: responseTokens)
        }
    }
}
