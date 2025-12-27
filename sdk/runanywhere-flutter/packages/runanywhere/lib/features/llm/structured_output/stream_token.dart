/// Token from structured output stream
/// Matches iOS StreamToken from Features/LLM/StructuredOutput/StreamToken.swift
class StreamToken {
  /// The token text
  final String text;

  /// Whether this is the final token
  final bool isFinal;

  /// Token index in the stream
  final int? index;

  const StreamToken({
    required this.text,
    this.isFinal = false,
    this.index,
  });

  @override
  String toString() => 'StreamToken(text: "$text", isFinal: $isFinal)';
}
