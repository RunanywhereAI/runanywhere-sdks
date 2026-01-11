/// Generation Types
///
/// Types for LLM text generation operations.
/// Mirrors Swift LLMGenerationOptions and LLMGenerationResult.
library generation_types;

import 'package:runanywhere/core/types/model_types.dart';

/// Options for LLM text generation
/// Matches Swift's LLMGenerationOptions
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final InferenceFramework? preferredFramework;
  final String? systemPrompt;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.preferredFramework,
    this.systemPrompt,
  });
}

/// Result of LLM text generation
/// Matches Swift's LLMGenerationResult
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int inputTokens;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final String? framework;
  final double tokensPerSecond;
  final double? timeToFirstTokenMs;
  final int thinkingTokens;
  final int responseTokens;

  const LLMGenerationResult({
    required this.text,
    this.thinkingContent,
    required this.inputTokens,
    required this.tokensUsed,
    required this.modelUsed,
    required this.latencyMs,
    this.framework,
    required this.tokensPerSecond,
    this.timeToFirstTokenMs,
    this.thinkingTokens = 0,
    this.responseTokens = 0,
  });
}

/// Result of streaming LLM text generation
/// Matches Swift's LLMStreamingResult
class LLMStreamingResult {
  final Stream<String> stream;
  final Future<LLMGenerationResult> result;

  const LLMStreamingResult({
    required this.stream,
    required this.result,
  });
}
