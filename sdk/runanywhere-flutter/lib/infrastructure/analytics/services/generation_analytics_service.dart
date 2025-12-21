/// LLM Generation analytics service.
/// Tracks generation operations and metrics.
/// Matches iOS GenerationAnalyticsService.
///
/// NOTE: ⚠️ Token estimation uses ~4 chars/token (approximation, not exact tokenizer count).
/// Actual token counts may vary depending on the model's tokenizer and input content.

import 'dart:async';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/module_registry.dart' show LLMGenerationResult;

/// LLM analytics service for tracking generation operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
///
/// Supports two generation modes:
/// - **Non-streaming** (`generate()`): Synchronous generation, no TTFT tracking
/// - **Streaming** (`generateStream()`): Asynchronous token-by-token generation with TTFT tracking
class GenerationAnalyticsService {
  final SDKLogger _logger = SDKLogger(category: 'GenerationAnalytics');

  /// Active generation operations
  final Map<String, _GenerationTracker> _activeGenerations = {};

  /// Metrics - separated by mode
  int _totalGenerations = 0;
  int _streamingGenerations = 0;
  int _nonStreamingGenerations = 0;
  double _totalTimeToFirstToken = 0;
  int _streamingTTFTCount = 0; // Only count TTFT for streaming generations
  double _totalTokensPerSecond = 0;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  final DateTime _startTime = DateTime.now();
  DateTime? _lastEventTime;

  GenerationAnalyticsService();

  /// Start tracking a non-streaming generation (generate())
  /// Returns a unique generation ID for tracking.
  String startGeneration({
    required String modelId,
    String? framework,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _activeGenerations[id] = _GenerationTracker(
      startTime: DateTime.now(),
      isStreaming: false,
      framework: framework,
    );

    _logger.debug('Non-streaming generation started: $id');
    return id;
  }

  /// Start tracking a streaming generation (generateStream())
  /// Returns a unique generation ID for tracking.
  String startStreamingGeneration({
    required String modelId,
    String? framework,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _activeGenerations[id] = _GenerationTracker(
      startTime: DateTime.now(),
      isStreaming: true,
      framework: framework,
    );

    _logger.debug('Streaming generation started: $id');
    return id;
  }

  /// Track first token for streaming generation (time-to-first-token metric).
  /// Only applicable for streaming generations. Call is ignored for non-streaming.
  void trackFirstToken({required String generationId}) {
    final tracker = _activeGenerations[generationId];
    if (tracker == null || !tracker.isStreaming) {
      // TTFT is only tracked for streaming generations
      return;
    }

    // Only record if not already recorded
    if (tracker.firstTokenTime != null) return;

    final firstTokenTime = DateTime.now();
    tracker.firstTokenTime = firstTokenTime;

    final latencyMs =
        firstTokenTime.difference(tracker.startTime).inMicroseconds / 1000.0;

    _logger.debug(
        'First token received for $generationId: ${latencyMs.toStringAsFixed(1)}ms');
  }

  /// Track streaming update (analytics only).
  /// Only applicable for streaming generations.
  void trackStreamingUpdate({
    required String generationId,
    required int tokensGenerated,
  }) {
    final tracker = _activeGenerations[generationId];
    if (tracker == null || !tracker.isStreaming) {
      return;
    }
    // Additional tracking can be added here
  }

  /// Complete a generation (works for both streaming and non-streaming).
  void completeGeneration({
    required String generationId,
    required int inputTokens,
    required int outputTokens,
    required String modelId,
  }) {
    final tracker = _activeGenerations.remove(generationId);
    if (tracker == null) return;

    final endTime = DateTime.now();
    final totalTimeMs =
        endTime.difference(tracker.startTime).inMicroseconds / 1000.0;
    final totalTimeSec = totalTimeMs / 1000.0;
    final tokensPerSecond =
        totalTimeSec > 0 ? outputTokens / totalTimeSec : 0.0;

    // Calculate TTFT for streaming generations
    double? timeToFirstTokenMs;
    if (tracker.isStreaming && tracker.firstTokenTime != null) {
      final ttftMs =
          tracker.firstTokenTime!.difference(tracker.startTime).inMicroseconds /
              1000.0;
      timeToFirstTokenMs = ttftMs;
      _totalTimeToFirstToken += ttftMs;
      _streamingTTFTCount++;
    }

    // Update metrics
    _totalGenerations++;
    if (tracker.isStreaming) {
      _streamingGenerations++;
    } else {
      _nonStreamingGenerations++;
    }
    _totalTokensPerSecond += tokensPerSecond;
    _totalInputTokens += inputTokens;
    _totalOutputTokens += outputTokens;
    _lastEventTime = endTime;

    final modeStr = tracker.isStreaming ? 'streaming' : 'non-streaming';
    _logger.debug('Generation completed ($modeStr): $generationId');
    if (timeToFirstTokenMs != null) {
      _logger.debug('TTFT: ${timeToFirstTokenMs.toStringAsFixed(1)}ms');
    }
  }

  /// Track generation failure.
  void trackGenerationFailed({
    required String generationId,
    required Object error,
  }) {
    _activeGenerations.remove(generationId);
    _lastEventTime = DateTime.now();
    _logger.warning('Generation failed: $generationId - $error');
  }

  /// Track an error during operations.
  void trackError(Object error, String operation) {
    _lastEventTime = DateTime.now();
    _logger.error('Error in $operation: $error');
  }

  /// Get current generation analytics metrics.
  GenerationMetrics getMetrics() {
    // Average TTFT only counts streaming generations that had TTFT recorded
    final avgTTFT = _streamingTTFTCount > 0
        ? _totalTimeToFirstToken / _streamingTTFTCount
        : 0.0;

    return GenerationMetrics(
      totalEvents: _totalGenerations,
      startTime: _startTime,
      lastEventTime: _lastEventTime,
      totalGenerations: _totalGenerations,
      streamingGenerations: _streamingGenerations,
      nonStreamingGenerations: _nonStreamingGenerations,
      averageTimeToFirstTokenMs: avgTTFT,
      averageTokensPerSecond: _totalGenerations > 0
          ? _totalTokensPerSecond / _totalGenerations
          : 0.0,
      totalInputTokens: _totalInputTokens,
      totalOutputTokens: _totalOutputTokens,
    );
  }
}

/// Internal tracker for generation operations.
class _GenerationTracker {
  final DateTime startTime;
  final bool isStreaming;
  final String? framework;
  DateTime? firstTokenTime;

  _GenerationTracker({
    required this.startTime,
    required this.isStreaming,
    this.framework,
  });
}

/// Generation metrics.
/// Matches iOS GenerationMetrics.
class GenerationMetrics {
  final int totalEvents;
  final DateTime startTime;
  final DateTime? lastEventTime;

  /// Total number of all generations (streaming + non-streaming)
  final int totalGenerations;

  /// Number of streaming generations (generateStream())
  final int streamingGenerations;

  /// Number of non-streaming generations (generate())
  final int nonStreamingGenerations;

  /// Average time to first token in milliseconds (only for streaming generations).
  /// Returns 0 if no streaming generations have completed.
  final double averageTimeToFirstTokenMs;

  /// Average tokens per second across all generations
  final double averageTokensPerSecond;

  /// Total input tokens processed
  final int totalInputTokens;

  /// Total output tokens generated
  final int totalOutputTokens;

  const GenerationMetrics({
    this.totalEvents = 0,
    required this.startTime,
    this.lastEventTime,
    this.totalGenerations = 0,
    this.streamingGenerations = 0,
    this.nonStreamingGenerations = 0,
    this.averageTimeToFirstTokenMs = 0,
    this.averageTokensPerSecond = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
  });
}

/// Streaming metrics collector for TTFT tracking.
/// Used internally by LLMCapability for streaming generations.
/// Matches iOS StreamingMetricsCollector actor pattern.
class StreamingMetricsCollector {
  final String modelId;
  final String generationId;
  final GenerationAnalyticsService analyticsService;
  final String? framework;
  final int promptLength;

  DateTime? _startTime;
  DateTime? _firstTokenTime;
  final StringBuffer _fullText = StringBuffer();
  bool _firstTokenRecorded = false;
  bool _isComplete = false;
  Object? _error;
  Completer<LLMGenerationResult>? _resultCompleter;

  StreamingMetricsCollector({
    required this.modelId,
    required this.generationId,
    required this.analyticsService,
    this.framework,
    required this.promptLength,
  });

  void markStart() {
    _startTime = DateTime.now();
  }

  void recordToken(String token) {
    _fullText.write(token);

    // Track first token for TTFT metric
    if (!_firstTokenRecorded) {
      _firstTokenRecorded = true;
      _firstTokenTime = DateTime.now();
      analyticsService.trackFirstToken(generationId: generationId);
    }
  }

  void markComplete() {
    _isComplete = true;

    // Simple token estimation (~4 chars per token)
    final inputTokens = (promptLength / 4).ceil().clamp(1, promptLength);
    final text = _fullText.toString();
    final outputTokens = (text.length / 4).ceil().clamp(1, text.length);

    analyticsService.completeGeneration(
      generationId: generationId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      modelId: modelId,
    );

    _resultCompleter?.complete(_buildResult());
    _resultCompleter = null;
  }

  void markFailed(Object error) {
    _error = error;
    analyticsService.trackGenerationFailed(
      generationId: generationId,
      error: error,
    );

    _resultCompleter?.completeError(error);
    _resultCompleter = null;
  }

  Future<LLMGenerationResult> waitForResult() async {
    if (_isComplete) {
      return _buildResult();
    }

    if (_error != null) {
      throw _error!;
    }

    _resultCompleter ??= Completer<LLMGenerationResult>();
    return _resultCompleter!.future;
  }

  LLMGenerationResult _buildResult() {
    final endTime = DateTime.now();
    final latencyMs = _startTime != null
        ? endTime.difference(_startTime!).inMicroseconds / 1000.0
        : 0.0;

    // Calculate TTFT for streaming
    double? timeToFirstTokenMs;
    if (_startTime != null && _firstTokenTime != null) {
      timeToFirstTokenMs =
          _firstTokenTime!.difference(_startTime!).inMicroseconds / 1000.0;
    }

    // Simple token estimation (~4 chars per token)
    final text = _fullText.toString();
    final inputTokens = (promptLength / 4).ceil().clamp(1, promptLength);
    final outputTokens = (text.length / 4).ceil().clamp(1, text.length);
    final latencySec = latencyMs / 1000.0;
    final tokensPerSecond = latencySec > 0 ? outputTokens / latencySec : 0.0;

    return LLMGenerationResult(
      text: text,
      thinkingContent: null,
      inputTokens: inputTokens,
      tokensUsed: outputTokens,
      modelUsed: modelId,
      latencyMs: latencyMs,
      framework: framework,
      tokensPerSecond: tokensPerSecond,
      timeToFirstTokenMs: timeToFirstTokenMs,
      thinkingTokens: 0,
      responseTokens: outputTokens,
    );
  }
}
