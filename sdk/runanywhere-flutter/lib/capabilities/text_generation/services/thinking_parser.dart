/// Thinking Parser for extracting reasoning from model outputs
/// Similar to Swift SDK's ThinkingParser
class ThinkingParser {
  static const String defaultPattern = r'<think>(.*?)</think>';
  static const String alternativePattern = r'<thinking>(.*?)</thinking>';

  /// Parse thinking content from text
  static ThinkingParseResult parse(String text, {String? pattern}) {
    final regex = RegExp(pattern ?? defaultPattern, dotAll: true);
    final matches = regex.allMatches(text);

    if (matches.isEmpty) {
      return ThinkingParseResult(
        hasThinking: false,
        thinkingContent: null,
        finalContent: text,
      );
    }

    final thinkingParts = matches.map((m) => m.group(1) ?? '').toList();
    final thinkingContent = thinkingParts.join('\n');

    // Remove thinking tags from final content
    final finalContent = text.replaceAll(regex, '').trim();

    return ThinkingParseResult(
      hasThinking: true,
      thinkingContent: thinkingContent,
      finalContent: finalContent,
    );
  }
}

/// Thinking Parse Result
class ThinkingParseResult {
  final bool hasThinking;
  final String? thinkingContent;
  final String finalContent;

  ThinkingParseResult({
    required this.hasThinking,
    this.thinkingContent,
    required this.finalContent,
  });
}

