/// Generation Types
///
/// Types for LLM text generation, STT transcription, and TTS synthesis.
/// Mirrors Swift LLMGenerationOptions, LLMGenerationResult, STTOutput, and TTSOutput.
library generation_types;

import 'dart:typed_data';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/public/types/structured_output_types.dart';

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
  final StructuredOutputConfig? structuredOutput;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.preferredFramework,
    this.systemPrompt,
    this.structuredOutput,
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
  final Map<String, dynamic>? structuredData;

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
    this.structuredData,
  });
}

/// Result of streaming LLM text generation
/// Matches Swift's LLMStreamingResult
///
/// Contains:
/// - `stream`: Stream of tokens as they are generated
/// - `result`: Future that completes with final generation metrics
/// - `cancel`: Function to cancel the generation
class LLMStreamingResult {
  /// Stream of tokens as they are generated.
  /// Listen to this to receive real-time token updates.
  final Stream<String> stream;

  /// Future that completes with the final generation result and metrics
  /// when streaming finishes. Wait for this after consuming the stream
  /// to get the complete analytics.
  final Future<LLMGenerationResult> result;

  /// Function to cancel the ongoing generation.
  /// Call this to stop generation early (e.g., user pressed stop button).
  final void Function() cancel;

  const LLMStreamingResult({
    required this.stream,
    required this.result,
    required this.cancel,
  });
}

/// Result of STT transcription
/// Matches Swift's STTOutput
class STTResult {
  /// The transcribed text
  final String text;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Duration of audio processed in milliseconds
  final int durationMs;

  /// Detected language (if available)
  final String? language;

  const STTResult({
    required this.text,
    required this.confidence,
    required this.durationMs,
    this.language,
  });

  @override
  String toString() =>
      'STTResult(text: "$text", confidence: $confidence, durationMs: $durationMs, language: $language)';
}

/// Result of TTS synthesis
/// Matches Swift's TTSOutput
class TTSResult {
  /// Audio samples as PCM float data
  final Float32List samples;

  /// Sample rate in Hz (typically 22050 for Piper)
  final int sampleRate;

  /// Duration of audio in milliseconds
  final int durationMs;

  const TTSResult({
    required this.samples,
    required this.sampleRate,
    required this.durationMs,
  });

  /// Duration in seconds
  double get durationSeconds => durationMs / 1000.0;

  /// Number of audio samples
  int get numSamples => samples.length;

  @override
  String toString() =>
      'TTSResult(samples: ${samples.length}, sampleRate: $sampleRate, durationMs: $durationMs)';
}
