/**
 * TokenCounter.ts
 *
 * Service for counting tokens in text with improved accuracy
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/TextGeneration/Services/TokenCounter.swift
 */

/**
 * Service for counting tokens in text with improved accuracy
 */
export class TokenCounter {
  /**
   * Count tokens with improved estimation (more accurate than simple word count)
   * This is a heuristic approach until we integrate actual tokenizers
   */
  public static estimateTokenCount(text: string): number {
    if (text.length === 0) {
      return 0;
    }

    // Improved heuristic based on GPT tokenization patterns:
    // - Average ~4 characters per token for English text
    // - Punctuation often creates separate tokens
    // - Whitespace handling
    // - Special characters

    const characterCount = text.length;
    const wordCount = text.split(/\s+/).filter((w) => w.length > 0).length;

    // Count punctuation marks (often separate tokens)
    const punctuationCount = text.split('').filter((c) => ".,!?;:()[]{}\"'".includes(c)).length;

    // Count newlines and special whitespace (often separate tokens)
    const newlineCount = text.split('').filter((c) => c === '\n' || c === '\r').length;

    // Heuristic formula:
    // Base estimate: characters / 4 (GPT average)
    // Add extra tokens for punctuation (most become separate tokens)
    // Add tokens for newlines
    // Ensure we're at least counting words (minimum tokens)

    const baseEstimate = characterCount / 4.0;
    const punctuationTokens = punctuationCount * 0.7; // Most punctuation becomes tokens
    const newlineTokens = newlineCount;

    const estimatedTokens = Math.ceil(baseEstimate + punctuationTokens + newlineTokens);

    // Sanity check: token count should be between word count and character count
    return Math.max(wordCount, Math.min(estimatedTokens, characterCount));
  }

  /**
   * Estimate tokens per second based on token count and elapsed time
   */
  public static calculateTokensPerSecond(tokenCount: number, elapsedSeconds: number): number {
    if (elapsedSeconds <= 0) {
      return 0;
    }
    return tokenCount / elapsedSeconds;
  }

  /**
   * Split token count between thinking and response content
   */
  public static splitTokenCounts(
    fullText: string,
    thinkingContent: string | null | undefined,
    responseContent: string
  ): {
    thinkingTokens: number | null;
    responseTokens: number;
    totalTokens: number;
  } {
    const responseTokens = this.estimateTokenCount(responseContent);

    if (thinkingContent && thinkingContent.length > 0) {
      const thinkingTokens = this.estimateTokenCount(thinkingContent);
      const totalTokens = thinkingTokens + responseTokens;
      return { thinkingTokens, responseTokens, totalTokens };
    } else {
      return { thinkingTokens: null, responseTokens, totalTokens: responseTokens };
    }
  }
}

