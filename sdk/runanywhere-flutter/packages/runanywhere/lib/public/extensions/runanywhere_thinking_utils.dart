// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_thinking_utils.dart — Pure Dart utilities for thinking-token
// extraction and structured-output parsing.
//
// These are stateless helpers — no FFI, no C ABI calls. All logic is
// expressed in Dart against the canonical proto types.

import 'dart:convert';

import 'package:runanywhere/generated/structured_output.pb.dart'
    show StructuredOutputResult, StructuredOutputValidation, JSONSchema;

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

/// Pure-Dart utilities for thinking-token parsing and structured output
/// extraction. Exposed as a static helper class; the public-facing
/// flat aliases on [RunAnywhereSDK] (in `runanywhere_flat_aliases.dart`)
/// delegate here.
class RunAnywhereThinkingUtils {
  RunAnywhereThinkingUtils._();

  // Regex matching `<think>…</think>` (case-insensitive, non-greedy, DOTALL).
  static final _thinkRegex = RegExp(
    r'<think>([\s\S]*?)</think>',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Thinking-token helpers
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Structured output helpers
  // ---------------------------------------------------------------------------

  /// Extract structured output from raw [text] against [schema].
  ///
  /// Strategy: locate the first JSON object / array in the text, attempt
  /// to parse it, and return a [StructuredOutputResult] with validation
  /// status. This is a pure Dart implementation (no C ABI call needed
  /// because the extraction is a string search + JSON parse).
  static Future<StructuredOutputResult> extractStructuredOutput(
    String text,
    JSONSchema schema,
  ) async {
    // Strip thinking tokens first.
    final cleanText = stripThinkingTokens(text);

    // Attempt to locate and parse a JSON object or array.
    final jsonStr = _extractFirstJson(cleanText);
    final isValid = jsonStr != null && _isValidJson(jsonStr);

    return StructuredOutputResult(
      rawText: text,
      // jsonStr is non-null when isValid is true (flow analysis confirms).
      parsedJson: isValid ? utf8.encode(jsonStr) : [],
      validation: StructuredOutputValidation(isValid: isValid),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Find the first balanced JSON object `{…}` or array `[…]` in [text].
  static String? _extractFirstJson(String text) {
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{' || ch == '[') {
        final closing = ch == '{' ? '}' : ']';
        final end = _findClosing(text, i, ch, closing);
        if (end != -1) {
          return text.substring(i, end + 1);
        }
      }
    }
    return null;
  }

  /// Find the index of the matching closing bracket starting from [start].
  static int _findClosing(String s, int start, String open, String close) {
    var depth = 0;
    var inString = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (ch == '"' && (i == 0 || s[i - 1] != '\\')) {
        inString = !inString;
      }
      if (!inString) {
        if (ch == open) depth++;
        if (ch == close) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }

  static bool _isValidJson(String s) {
    try {
      jsonDecode(s);
      return true;
    } catch (_) {
      return false;
    }
  }
}
