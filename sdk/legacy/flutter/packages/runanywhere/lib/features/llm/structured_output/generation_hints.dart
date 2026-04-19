/// Hints for structured output generation
/// Matches iOS GenerationHints from Features/LLM/StructuredOutput/GenerationHints.swift
class GenerationHints {
  /// Temperature for generation (0.0 - 1.0)
  final double temperature;

  /// Maximum tokens to generate
  final int? maxTokens;

  /// Top-p sampling
  final double? topP;

  /// Top-k sampling
  final int? topK;

  /// Whether to stop at first valid JSON
  final bool stopAtFirstValidJSON;

  /// Whether to include reasoning/thinking
  final bool includeReasoning;

  const GenerationHints({
    this.temperature = 0.7,
    this.maxTokens,
    this.topP,
    this.topK,
    this.stopAtFirstValidJSON = true,
    this.includeReasoning = false,
  });

  /// Create hints optimized for JSON output
  factory GenerationHints.forJSON() {
    return const GenerationHints(
      temperature: 0.3,
      stopAtFirstValidJSON: true,
    );
  }

  /// Create hints for creative output
  factory GenerationHints.forCreative() {
    return const GenerationHints(
      temperature: 0.9,
      topP: 0.95,
    );
  }
}
