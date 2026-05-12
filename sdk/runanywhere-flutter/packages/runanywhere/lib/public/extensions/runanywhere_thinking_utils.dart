// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_thinking_utils.dart — Pure Dart utilities for thinking-token
// extraction. Structured-output parsing now lives on
// `RunAnywhereSDK.instance.llm.extractStructuredOutput(...)` to mirror
// Swift's `RunAnywhere.extractStructuredOutput(text:schema:)`.

/// Canonical result of `extractThinkingTokens` (§3).
class ThinkingExtractionResult {
  /// The extracted thinking content (between `<think>` and `</think>`).
  /// Empty string if no thinking tokens were found.
  final String thinking;

  /// The response text with thinking tokens stripped out.
  final String response;

  /// True if thinking tokens were present in the original text.
  final bool hasThinking;

  const ThinkingExtractionResult({
    required this.thinking,
    required this.response,
    required this.hasThinking,
  });
}

/// Pure-Dart utilities for thinking-token parsing. Exposed as a static helper
/// class. Swift has no equivalent surface — these helpers are Dart-only.
class RunAnywhereThinkingUtils {
  RunAnywhereThinkingUtils._();

  // Regex matching `<think>…</think>` (case-insensitive, non-greedy, DOTALL).
  static final _thinkRegex = RegExp(
    r'<think>([\s\S]*?)</think>',
    caseSensitive: false,
  );

  /// Extract `<think>…</think>` tokens from [text], returning a
  /// [ThinkingExtractionResult] with the thinking content and the clean
  /// response.
  static ThinkingExtractionResult extractThinkingTokens(String text) {
    final buffer = StringBuffer();
    var hasThinking = false;

    for (final match in _thinkRegex.allMatches(text)) {
      buffer.write(match.group(1) ?? '');
      hasThinking = true;
    }

    final thinking = buffer.toString().trim();
    final response = stripThinkingTokens(text);

    return ThinkingExtractionResult(
      thinking: thinking,
      response: response,
      hasThinking: hasThinking,
    );
  }

  /// Remove `<think>…</think>` blocks from [text] and return the
  /// remaining visible response (trimmed).
  static String stripThinkingTokens(String text) =>
      text.replaceAll(_thinkRegex, '').trim();

  /// Split [text] into its thinking portion and response portion.
  static ({String thinking, String response}) splitThinkingAndResponse(
    String text,
  ) {
    final result = extractThinkingTokens(text);
    return (thinking: result.thinking, response: result.response);
  }
}
