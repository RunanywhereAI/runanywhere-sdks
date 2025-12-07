//
//  generation_analytics_service.dart
//  RunAnywhere SDK
//
//  Generation-specific analytics service following unified pattern
//
//  Corresponds to iOS SDK's GenerationAnalyticsService.swift

import 'package:uuid/uuid.dart';

import '../../../core/protocols/analytics/analytics.dart';
import '../../../foundation/analytics/analytics_queue_manager.dart';
import '../../../foundation/logging/sdk_logger.dart';

// MARK: - Generation Event

/// Generation-specific analytics event
class GenerationEvent implements AnalyticsEvent {
  @override
  final String id;

  @override
  final String type;

  @override
  final DateTime timestamp;

  @override
  final String? sessionId;

  @override
  final AnalyticsEventData eventData;

  GenerationEvent({
    required GenerationEventType eventType,
    this.sessionId,
    required this.eventData,
  })  : id = const Uuid().v4(),
        type = eventType.rawValue,
        timestamp = DateTime.now();
}

/// Generation event types
enum GenerationEventType {
  sessionStarted('generation_session_started'),
  sessionEnded('generation_session_ended'),
  generationStarted('generation_started'),
  generationCompleted('generation_completed'),
  firstTokenGenerated('generation_first_token'),
  streamingUpdate('generation_streaming_update'),
  error('generation_error'),
  modelLoaded('generation_model_loaded'),
  modelUnloaded('generation_model_unloaded');

  final String rawValue;
  const GenerationEventType(this.rawValue);
}

// MARK: - Generation Metrics

/// Generation-specific metrics
class GenerationMetrics implements AnalyticsMetrics {
  @override
  final int totalEvents;

  @override
  final DateTime startTime;

  @override
  final DateTime? lastEventTime;

  final int totalGenerations;
  final Duration averageTimeToFirstToken;
  final double averageTokensPerSecond;
  final int totalInputTokens;
  final int totalOutputTokens;

  const GenerationMetrics({
    required this.totalEvents,
    required this.startTime,
    this.lastEventTime,
    required this.totalGenerations,
    required this.averageTimeToFirstToken,
    required this.averageTokensPerSecond,
    required this.totalInputTokens,
    required this.totalOutputTokens,
  });

  /// Create initial empty metrics
  factory GenerationMetrics.initial() => GenerationMetrics(
        totalEvents: 0,
        startTime: DateTime.now(),
        lastEventTime: null,
        totalGenerations: 0,
        averageTimeToFirstToken: Duration.zero,
        averageTokensPerSecond: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
      );
}

// MARK: - Generation Analytics Service

/// Generation analytics service using unified pattern
class GenerationAnalyticsService
    implements AnalyticsService<GenerationEvent, GenerationMetrics> {
  // Properties
  final AnalyticsQueueManager _queueManager;
  final SDKLogger _logger;
  _SessionInfo? _currentSession;
  final List<GenerationEvent> _events = [];

  // Metrics tracking
  int _totalGenerations = 0;
  Duration _totalTimeToFirstToken = Duration.zero;
  double _totalTokensPerSecond = 0;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;

  // Generation tracking
  final Map<String, _GenerationTracker> _activeGenerations = {};

  // Initialization
  GenerationAnalyticsService({AnalyticsQueueManager? queueManager})
      : _queueManager = queueManager ?? AnalyticsQueueManager.shared,
        _logger = SDKLogger(category: 'GenerationAnalytics');

  // MARK: - Analytics Service Protocol

  @override
  Future<void> track(GenerationEvent event) async {
    _events.add(event);
    await _queueManager.enqueue(event);
    await _processEvent(event);
  }

  @override
  Future<void> trackBatch(List<GenerationEvent> events) async {
    _events.addAll(events);
    await _queueManager.enqueueBatch(events);
    for (final event in events) {
      await _processEvent(event);
    }
  }

  @override
  Future<GenerationMetrics> getMetrics() async {
    return GenerationMetrics(
      totalEvents: _events.length,
      startTime: DateTime.now(),
      lastEventTime: _events.isNotEmpty ? _events.last.timestamp : null,
      totalGenerations: _totalGenerations,
      averageTimeToFirstToken: _totalGenerations > 0
          ? Duration(
              milliseconds:
                  (_totalTimeToFirstToken.inMilliseconds / _totalGenerations)
                      .round())
          : Duration.zero,
      averageTokensPerSecond:
          _totalGenerations > 0 ? _totalTokensPerSecond / _totalGenerations : 0,
      totalInputTokens: _totalInputTokens,
      totalOutputTokens: _totalOutputTokens,
    );
  }

  @override
  Future<void> clearMetrics({required DateTime olderThan}) async {
    _events.removeWhere((event) => event.timestamp.isBefore(olderThan));
  }

  @override
  Future<String> startSession(SessionMetadata metadata) async {
    _currentSession = _SessionInfo(
      id: metadata.id,
      modelId: metadata.modelId,
      startTime: DateTime.now(),
    );
    return metadata.id;
  }

  @override
  Future<void> endSession(String sessionId) async {
    if (_currentSession?.id == sessionId) {
      _currentSession = null;
    }
  }

  @override
  Future<bool> isHealthy() async => true;

  // MARK: - Generation-Specific Methods

  /// Start tracking a new generation
  Future<String> startGeneration({
    String? generationId,
    required String modelId,
    required String executionTarget,
  }) async {
    final id = generationId ?? const Uuid().v4();

    final tracker = _GenerationTracker(
      id: id,
      startTime: DateTime.now(),
    );
    _activeGenerations[id] = tracker;

    final eventData = GenerationStartData(
      generationId: id,
      modelId: modelId,
      executionTarget: executionTarget,
      promptTokens: 0, // Will be updated when available
      maxTokens: 0, // Will be updated when available
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.generationStarted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
    return id;
  }

  /// Track first token generation
  Future<void> trackFirstToken(String generationId) async {
    final tracker = _activeGenerations[generationId];
    if (tracker == null) return;

    tracker.firstTokenTime = DateTime.now();
    _activeGenerations[generationId] = tracker;

    final timeToFirstToken =
        tracker.firstTokenTime!.difference(tracker.startTime);

    final eventData = FirstTokenData(
      generationId: generationId,
      timeToFirstTokenMs: timeToFirstToken.inMilliseconds.toDouble(),
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.firstTokenGenerated,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Complete a generation with performance metrics
  Future<void> completeGeneration({
    required String generationId,
    required int inputTokens,
    required int outputTokens,
    required String modelId,
    required String executionTarget,
  }) async {
    final tracker = _activeGenerations[generationId];
    if (tracker == null) return;

    tracker.endTime = DateTime.now();
    tracker.inputTokens = inputTokens;
    tracker.outputTokens = outputTokens;

    final totalTime = tracker.endTime!.difference(tracker.startTime);
    final timeToFirstToken = tracker.firstTokenTime != null
        ? tracker.firstTokenTime!.difference(tracker.startTime)
        : Duration.zero;
    final tokensPerSecond = totalTime.inMilliseconds > 0
        ? outputTokens / (totalTime.inMilliseconds / 1000.0)
        : 0.0;

    // Update metrics
    _totalGenerations += 1;
    _totalTimeToFirstToken += timeToFirstToken;
    _totalTokensPerSecond += tokensPerSecond;
    _totalInputTokens += inputTokens;
    _totalOutputTokens += outputTokens;

    final eventData = GenerationCompletionData(
      generationId: generationId,
      modelId: modelId,
      executionTarget: executionTarget,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTimeMs: totalTime.inMilliseconds.toDouble(),
      timeToFirstTokenMs: timeToFirstToken.inMilliseconds.toDouble(),
      tokensPerSecond: tokensPerSecond,
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.generationCompleted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);

    // Clean up tracker
    _activeGenerations.remove(generationId);
  }

  /// Track streaming update
  Future<void> trackStreamingUpdate({
    required String generationId,
    required int tokensGenerated,
  }) async {
    final eventData = StreamingUpdateData(
      generationId: generationId,
      tokensGenerated: tokensGenerated,
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.streamingUpdate,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track model loading
  Future<void> trackModelLoading({
    required String modelId,
    required Duration loadTime,
    required bool success,
  }) async {
    final eventData = ModelLoadingData(
      modelId: modelId,
      loadTimeMs: loadTime.inMilliseconds.toDouble(),
      success: success,
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.modelLoaded,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track model unloading
  Future<void> trackModelUnloading(String modelId) async {
    final eventData = ModelUnloadingData(modelId: modelId);
    final event = GenerationEvent(
      eventType: GenerationEventType.modelUnloaded,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track error
  Future<void> trackError({
    required Object error,
    required AnalyticsContext context,
  }) async {
    final eventData = ErrorEventData(
      error: error.toString(),
      analyticsContext: context,
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.error,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  // MARK: - Session Management Override

  /// Start a generation session
  Future<String> startGenerationSession({
    required String modelId,
    String type = 'text',
  }) async {
    final metadata = SessionMetadata.create(
      modelId: modelId,
      type: type,
    );

    final sessionId = await startSession(metadata);

    final eventData = SessionStartedData(
      modelId: modelId,
      sessionType: type,
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.sessionStarted,
      sessionId: sessionId,
      eventData: eventData,
    );

    await track(event);
    return sessionId;
  }

  /// End a generation session
  Future<void> endGenerationSession(String sessionId) async {
    await endSession(sessionId);

    final eventData = SessionEndedData(
      sessionId: sessionId,
      duration: 0, // Duration tracking would need session start time
    );
    final event = GenerationEvent(
      eventType: GenerationEventType.sessionEnded,
      sessionId: sessionId,
      eventData: eventData,
    );

    await track(event);
  }

  // MARK: - Private Methods

  Future<void> _processEvent(GenerationEvent event) async {
    // Custom processing for generation events if needed
    _logger.debug('Processed generation event: ${event.type}');
  }
}

// MARK: - Private Helper Classes

class _SessionInfo {
  final String id;
  final String? modelId;
  final DateTime startTime;

  const _SessionInfo({
    required this.id,
    this.modelId,
    required this.startTime,
  });
}

class _GenerationTracker {
  final String id;
  final DateTime startTime;
  DateTime? firstTokenTime;
  DateTime? endTime;
  int inputTokens = 0;
  int outputTokens = 0;

  _GenerationTracker({
    required this.id,
    required this.startTime,
  });
}
