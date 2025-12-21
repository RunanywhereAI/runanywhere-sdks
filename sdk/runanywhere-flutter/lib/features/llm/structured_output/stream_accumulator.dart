import 'stream_token.dart';

/// Accumulates tokens from a stream into a complete response
/// Matches iOS StreamAccumulator from Features/LLM/StructuredOutput/StreamAccumulator.swift
class StreamAccumulator {
  final StringBuffer _buffer = StringBuffer();
  final List<StreamToken> _tokens = [];
  bool _isComplete = false;

  /// Get the accumulated text
  String get text => _buffer.toString();

  /// Get all accumulated tokens
  List<StreamToken> get tokens => List.unmodifiable(_tokens);

  /// Whether the stream is complete
  bool get isComplete => _isComplete;

  /// Add a token to the accumulator
  void addToken(StreamToken token) {
    _tokens.add(token);
    _buffer.write(token.text);
    if (token.isFinal) {
      _isComplete = true;
    }
  }

  /// Clear the accumulator
  void reset() {
    _buffer.clear();
    _tokens.clear();
    _isComplete = false;
  }

  /// Get token count
  int get tokenCount => _tokens.length;
}
