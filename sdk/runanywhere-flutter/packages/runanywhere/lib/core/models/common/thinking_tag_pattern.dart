/// Pattern for extracting thinking/reasoning content from model output
/// Matches iOS ThinkingTagPattern from Capabilities/TextGeneration/Models/ThinkingTagPattern.swift
class ThinkingTagPattern {
  final String openingTag;
  final String closingTag;

  const ThinkingTagPattern({
    required this.openingTag,
    required this.closingTag,
  });

  /// Default pattern used by models like DeepSeek and Hermes
  static const ThinkingTagPattern defaultPattern = ThinkingTagPattern(
    openingTag: '<think>',
    closingTag: '</think>',
  );

  /// Alternative pattern with full "thinking" word
  static const ThinkingTagPattern thinkingPattern = ThinkingTagPattern(
    openingTag: '<thinking>',
    closingTag: '</thinking>',
  );

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'openingTag': openingTag,
        'closingTag': closingTag,
      };

  factory ThinkingTagPattern.fromJson(Map<String, dynamic> json) {
    return ThinkingTagPattern(
      openingTag: json['openingTag'] as String,
      closingTag: json['closingTag'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThinkingTagPattern &&
          runtimeType == other.runtimeType &&
          openingTag == other.openingTag &&
          closingTag == other.closingTag;

  @override
  int get hashCode => openingTag.hashCode ^ closingTag.hashCode;
}
