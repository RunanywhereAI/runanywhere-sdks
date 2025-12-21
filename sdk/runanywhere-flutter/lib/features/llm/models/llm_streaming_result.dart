import 'dart:async';

import 'package:runanywhere/core/module_registry.dart' show LLMGenerationResult;

/// Container for streaming generation with metrics.
/// Provides both the token stream and a future that resolves to final metrics.
///
/// Matches iOS `LLMStreamingResult` struct from LLMStreamingResult.swift
///
/// Example usage:
/// ```dart
/// final result = await llmService.generateStreamWithMetrics(prompt, options);
///
/// // Listen to streaming tokens
/// result.stream.listen((token) => print(token));
///
/// // Get final result with metrics
/// final finalResult = await result.result;
/// print('Tokens per second: ${finalResult.tokensPerSecond}');
/// ```
class LLMStreamingResult {
  /// Stream of tokens as they are generated.
  ///
  /// Matches iOS `stream: AsyncThrowingStream<String, Error>`
  final Stream<String> stream;

  /// Future that completes with final generation result including metrics.
  /// Resolves after streaming is complete.
  ///
  /// Matches iOS `result: Task<LLMGenerationResult, Error>`
  final Future<LLMGenerationResult> result;

  /// Creates a streaming result with both stream and final result future.
  LLMStreamingResult({
    required this.stream,
    required this.result,
  });

  /// Create a streaming result from a stream controller.
  ///
  /// Utility factory for creating from a broadcast stream controller
  /// and a completer for the final result.
  factory LLMStreamingResult.fromController({
    required StreamController<String> controller,
    required Completer<LLMGenerationResult> completer,
  }) {
    return LLMStreamingResult(
      stream: controller.stream,
      result: completer.future,
    );
  }

  /// Create an error streaming result.
  ///
  /// Used when generation fails before streaming starts.
  factory LLMStreamingResult.error(Object error) {
    final controller = StreamController<String>();
    controller.addError(error);
    unawaited(controller.close());
    return LLMStreamingResult(
      stream: controller.stream,
      result: Future.error(error),
    );
  }
}
