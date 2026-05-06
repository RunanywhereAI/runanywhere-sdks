// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_thinking_utils.dart — Pure Dart utilities for thinking-token
// extraction, plus structured-output parsing via commons proto bytes.
//
// Thinking-token helpers remain in Dart (simple regex); structured-output
// extraction routes through `rac_structured_output_parse_proto` so SDKs do
// not duplicate commons-owned JSON extraction logic.

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/structured_output.pb.dart'
    show
        JSONSchema,
        StructuredOutputOptions,
        StructuredOutputParseRequest,
        StructuredOutputResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

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
/// extraction. Exposed as a static helper class.
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
  /// Routes through commons `rac_structured_output_parse_proto`, which runs
  /// the canonical JSON extractor + schema validator in C++ and returns a
  /// [StructuredOutputResult]. Thinking tokens are stripped first so the
  /// parser sees the visible response only.
  static Future<StructuredOutputResult> extractStructuredOutput(
    String text,
    JSONSchema schema,
  ) async {
    final fn = RacNative.bindings.rac_structured_output_parse_proto;
    if (fn == null) {
      throw SDKException.featureNotAvailable(
        'rac_structured_output_parse_proto is unavailable',
      );
    }

    final cleanText = stripThinkingTokens(text);
    final request = StructuredOutputParseRequest()
      ..text = cleanText
      ..options = StructuredOutputOptions(schema: schema);

    return DartBridgeProtoUtils.callRequest<StructuredOutputResult>(
      request: request,
      invoke: fn,
      decode: StructuredOutputResult.fromBuffer,
      symbol: 'rac_structured_output_parse_proto',
    );
  }
}
