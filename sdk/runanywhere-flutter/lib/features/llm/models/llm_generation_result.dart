/// Result of LLM text generation with metrics.
///
/// Matches iOS `LLMGenerationResult` struct from LLMGenerationResult.swift
class LLMGenerationResult {
  /// Generated text content
  final String text;

  /// Number of input tokens (prompt)
  final int inputTokens;

  /// Number of output tokens (completion)
  final int outputTokens;

  /// Total tokens used (input + output)
  int get totalTokens => inputTokens + outputTokens;

  /// Generation duration in milliseconds
  final double durationMs;

  /// Tokens per second generation speed
  final double tokensPerSecond;

  /// Time to first token in milliseconds (streaming only)
  final double? timeToFirstTokenMs;

  /// Whether this was a streaming generation
  final bool isStreaming;

  /// Model ID used for generation
  final String? modelId;

  /// Framework used for generation
  final String? framework;

  /// Finish reason
  final LLMFinishReason finishReason;

  /// Optional thinking/reasoning content (for models that support it)
  final String? thinkingContent;

  LLMGenerationResult({
    required this.text,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.durationMs = 0,
    this.tokensPerSecond = 0,
    this.timeToFirstTokenMs,
    this.isStreaming = false,
    this.modelId,
    this.framework,
    this.finishReason = LLMFinishReason.completed,
    this.thinkingContent,
  });

  /// Create a copy with updated fields.
  LLMGenerationResult copyWith({
    String? text,
    int? inputTokens,
    int? outputTokens,
    double? durationMs,
    double? tokensPerSecond,
    double? timeToFirstTokenMs,
    bool? isStreaming,
    String? modelId,
    String? framework,
    LLMFinishReason? finishReason,
    String? thinkingContent,
  }) {
    return LLMGenerationResult(
      text: text ?? this.text,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      durationMs: durationMs ?? this.durationMs,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      timeToFirstTokenMs: timeToFirstTokenMs ?? this.timeToFirstTokenMs,
      isStreaming: isStreaming ?? this.isStreaming,
      modelId: modelId ?? this.modelId,
      framework: framework ?? this.framework,
      finishReason: finishReason ?? this.finishReason,
      thinkingContent: thinkingContent ?? this.thinkingContent,
    );
  }

  @override
  String toString() {
    return 'LLMGenerationResult(text: ${text.length} chars, '
        'tokens: $inputTokens in / $outputTokens out, '
        'duration: ${durationMs.toStringAsFixed(1)}ms, '
        'speed: ${tokensPerSecond.toStringAsFixed(2)} tok/s)';
  }
}

/// Reason why generation finished.
///
/// Matches iOS `LLMFinishReason` from LLMGenerationResult.swift
enum LLMFinishReason {
  /// Generation completed normally
  completed,

  /// Hit max token limit
  lengthLimit,

  /// Hit stop sequence
  stopSequence,

  /// User requested cancellation
  cancelled,

  /// Generation failed
  error,
}
