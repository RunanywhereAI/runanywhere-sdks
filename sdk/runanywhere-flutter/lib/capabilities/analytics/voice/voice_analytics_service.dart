//
//  voice_analytics_service.dart
//  RunAnywhere SDK
//
//  Voice-specific analytics service following unified pattern
//
//  Corresponds to iOS SDK's VoiceAnalyticsService.swift

import 'package:uuid/uuid.dart';

import '../../../core/protocols/analytics/analytics.dart';
import '../../../foundation/analytics/analytics_queue_manager.dart';
import '../../../foundation/logging/sdk_logger.dart';

// MARK: - Voice Event

/// Voice-specific analytics event
class VoiceEvent implements AnalyticsEvent {
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

  VoiceEvent({
    required VoiceEventType eventType,
    this.sessionId,
    required this.eventData,
  })  : id = const Uuid().v4(),
        type = eventType.rawValue,
        timestamp = DateTime.now();
}

/// Voice event types
enum VoiceEventType {
  pipelineCreated('voice_pipeline_created'),
  pipelineStarted('voice_pipeline_started'),
  pipelineCompleted('voice_pipeline_completed'),
  transcriptionStarted('voice_transcription_started'),
  transcriptionCompleted('voice_transcription_completed'),
  stageExecuted('voice_stage_executed'),
  error('voice_error');

  final String rawValue;
  const VoiceEventType(this.rawValue);
}

// MARK: - Voice Metrics

/// Voice-specific metrics
class VoiceMetrics implements AnalyticsMetrics {
  @override
  final int totalEvents;

  @override
  final DateTime startTime;

  @override
  final DateTime? lastEventTime;

  final int totalTranscriptions;
  final int totalPipelineExecutions;
  final Duration averageTranscriptionDuration;
  final Duration averagePipelineDuration;
  final double averageRealTimeFactor;

  const VoiceMetrics({
    required this.totalEvents,
    required this.startTime,
    this.lastEventTime,
    required this.totalTranscriptions,
    required this.totalPipelineExecutions,
    required this.averageTranscriptionDuration,
    required this.averagePipelineDuration,
    required this.averageRealTimeFactor,
  });

  /// Create initial empty metrics
  factory VoiceMetrics.initial() => VoiceMetrics(
        totalEvents: 0,
        startTime: DateTime.now(),
        lastEventTime: null,
        totalTranscriptions: 0,
        totalPipelineExecutions: 0,
        averageTranscriptionDuration: Duration.zero,
        averagePipelineDuration: Duration.zero,
        averageRealTimeFactor: 0,
      );
}

// MARK: - Voice Analytics Service

/// Voice analytics service using unified pattern
class VoiceAnalyticsService
    implements AnalyticsService<VoiceEvent, VoiceMetrics> {
  // Properties
  final AnalyticsQueueManager _queueManager;
  final SDKLogger _logger;
  _SessionInfo? _currentSession;
  final List<VoiceEvent> _events = [];

  // Metrics tracking
  int _totalTranscriptions = 0;
  int _totalPipelineExecutions = 0;
  Duration _totalTranscriptionDuration = Duration.zero;
  Duration _totalPipelineDuration = Duration.zero;
  double _totalRealTimeFactor = 0;

  // Initialization
  VoiceAnalyticsService({AnalyticsQueueManager? queueManager})
      : _queueManager = queueManager ?? AnalyticsQueueManager.shared,
        _logger = SDKLogger(category: 'VoiceAnalytics');

  // MARK: - Analytics Service Protocol

  @override
  Future<void> track(VoiceEvent event) async {
    _events.add(event);
    await _queueManager.enqueue(event);
    await _processEvent(event);
  }

  @override
  Future<void> trackBatch(List<VoiceEvent> events) async {
    _events.addAll(events);
    await _queueManager.enqueueBatch(events);
    for (final event in events) {
      await _processEvent(event);
    }
  }

  @override
  Future<VoiceMetrics> getMetrics() async {
    return VoiceMetrics(
      totalEvents: _events.length,
      startTime: DateTime.now(),
      lastEventTime: _events.isNotEmpty ? _events.last.timestamp : null,
      totalTranscriptions: _totalTranscriptions,
      totalPipelineExecutions: _totalPipelineExecutions,
      averageTranscriptionDuration: _totalTranscriptions > 0
          ? Duration(
              milliseconds:
                  (_totalTranscriptionDuration.inMilliseconds /
                          _totalTranscriptions)
                      .round())
          : Duration.zero,
      averagePipelineDuration: _totalPipelineExecutions > 0
          ? Duration(
              milliseconds:
                  (_totalPipelineDuration.inMilliseconds /
                          _totalPipelineExecutions)
                      .round())
          : Duration.zero,
      averageRealTimeFactor: _totalTranscriptions > 0
          ? _totalRealTimeFactor / _totalTranscriptions
          : 0,
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

  // MARK: - Voice-Specific Methods

  /// Track pipeline creation
  Future<void> trackPipelineCreation(List<String> stages) async {
    final eventData = PipelineCreationData(
      stageCount: stages.length,
      stages: stages,
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.pipelineCreated,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track pipeline start
  Future<void> trackPipelineStarted(List<String> stages) async {
    final eventData = PipelineStartedData(
      stageCount: stages.length,
      stages: stages,
      startTimestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.pipelineStarted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track transcription start
  Future<void> trackTranscriptionStarted(Duration audioLength) async {
    final eventData = TranscriptionStartData(
      audioLengthMs: audioLength.inMilliseconds.toDouble(),
      startTimestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.transcriptionStarted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track pipeline execution
  Future<void> trackPipelineExecution({
    required List<String> stages,
    required Duration totalTime,
  }) async {
    _totalPipelineExecutions += 1;
    _totalPipelineDuration += totalTime;

    final eventData = PipelineCompletionData(
      stageCount: stages.length,
      stages: stages,
      totalTimeMs: totalTime.inMilliseconds.toDouble(),
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.pipelineCompleted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track transcription performance
  Future<void> trackTranscription({
    required Duration duration,
    required int wordCount,
    required Duration audioLength,
  }) async {
    final realTimeFactor =
        duration.inMilliseconds / audioLength.inMilliseconds;

    _totalTranscriptions += 1;
    _totalTranscriptionDuration += duration;
    _totalRealTimeFactor += realTimeFactor;

    final eventData = VoiceTranscriptionData(
      durationMs: duration.inMilliseconds.toDouble(),
      wordCount: wordCount,
      audioLengthMs: audioLength.inMilliseconds.toDouble(),
      realTimeFactor: realTimeFactor,
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.transcriptionCompleted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  /// Track stage execution
  Future<void> trackStageExecution({
    required String stage,
    required Duration duration,
  }) async {
    final eventData = StageExecutionData(
      stageName: stage,
      durationMs: duration.inMilliseconds.toDouble(),
    );
    final event = VoiceEvent(
      eventType: VoiceEventType.stageExecuted,
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
    final event = VoiceEvent(
      eventType: VoiceEventType.error,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  // MARK: - Private Methods

  Future<void> _processEvent(VoiceEvent event) async {
    // Custom processing for voice events if needed
    _logger.debug('Processed voice event: ${event.type}');
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
