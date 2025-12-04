//
//  stt_analytics_service.dart
//  RunAnywhere SDK
//
//  STT-specific analytics service following unified pattern
//
//  Corresponds to iOS SDK's STTAnalyticsService.swift

import 'package:uuid/uuid.dart';

import '../../../core/protocols/analytics/analytics.dart';
import '../../../foundation/analytics/analytics_queue_manager.dart';
import '../../../foundation/logging/sdk_logger.dart';

// MARK: - STT Event

/// STT-specific analytics event
class STTEvent implements AnalyticsEvent {
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

  STTEvent({
    required STTEventType eventType,
    this.sessionId,
    required this.eventData,
  })  : id = const Uuid().v4(),
        type = eventType.rawValue,
        timestamp = DateTime.now();
}

/// STT event types
enum STTEventType {
  transcriptionStarted('stt_transcription_started'),
  transcriptionCompleted('stt_transcription_completed'),
  partialTranscript('stt_partial_transcript'),
  finalTranscript('stt_final_transcript'),
  speakerDetected('stt_speaker_detected'),
  speakerChanged('stt_speaker_changed'),
  languageDetected('stt_language_detected'),
  error('stt_error');

  final String rawValue;
  const STTEventType(this.rawValue);
}

// MARK: - STT Metrics

/// STT-specific metrics
class STTMetrics implements AnalyticsMetrics {
  @override
  final int totalEvents;

  @override
  final DateTime startTime;

  @override
  final DateTime? lastEventTime;

  final int totalTranscriptions;
  final double averageConfidence;
  final Duration averageLatency;

  const STTMetrics({
    required this.totalEvents,
    required this.startTime,
    this.lastEventTime,
    required this.totalTranscriptions,
    required this.averageConfidence,
    required this.averageLatency,
  });

  /// Create initial empty metrics
  factory STTMetrics.initial() => STTMetrics(
        totalEvents: 0,
        startTime: DateTime.now(),
        lastEventTime: null,
        totalTranscriptions: 0,
        averageConfidence: 0,
        averageLatency: Duration.zero,
      );
}

// MARK: - STT Analytics Service

/// STT analytics service using unified pattern
class STTAnalyticsService implements AnalyticsService<STTEvent, STTMetrics> {
  // Properties
  final AnalyticsQueueManager _queueManager;
  final SDKLogger _logger;
  _SessionInfo? _currentSession;
  final List<STTEvent> _events = [];

  // Metrics tracking
  int _transcriptionCount = 0;
  double _totalConfidence = 0;
  Duration _totalLatency = Duration.zero;

  // Initialization
  STTAnalyticsService({AnalyticsQueueManager? queueManager})
      : _queueManager = queueManager ?? AnalyticsQueueManager.shared,
        _logger = SDKLogger(category: 'STTAnalytics');

  // MARK: - Analytics Service Protocol

  @override
  Future<void> track(STTEvent event) async {
    _events.add(event);
    await _queueManager.enqueue(event);
    await _processEvent(event);
  }

  @override
  Future<void> trackBatch(List<STTEvent> events) async {
    _events.addAll(events);
    await _queueManager.enqueueBatch(events);
    for (final event in events) {
      await _processEvent(event);
    }
  }

  @override
  Future<STTMetrics> getMetrics() async {
    return STTMetrics(
      totalEvents: _events.length,
      startTime: DateTime.now(),
      lastEventTime: _events.isNotEmpty ? _events.last.timestamp : null,
      totalTranscriptions: _transcriptionCount,
      averageConfidence: _transcriptionCount > 0
          ? _totalConfidence / _transcriptionCount
          : 0,
      averageLatency: _transcriptionCount > 0
          ? Duration(
              milliseconds:
                  (_totalLatency.inMilliseconds / _transcriptionCount).round())
          : Duration.zero,
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

  // MARK: - STT-Specific Methods

  /// Track a transcription completion
  Future<void> trackTranscription({
    required String text,
    required double confidence,
    required Duration duration,
    required Duration audioLength,
    String? speaker,
  }) async {
    final eventData = STTTranscriptionData(
      wordCount: text.split(' ').length,
      confidence: confidence,
      durationMs: duration.inMilliseconds.toDouble(),
      audioLengthMs: audioLength.inMilliseconds.toDouble(),
      realTimeFactor: duration.inMilliseconds / audioLength.inMilliseconds,
      speakerId: speaker ?? 'unknown',
    );

    final event = STTEvent(
      eventType: STTEventType.transcriptionCompleted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);

    // Update metrics
    _transcriptionCount += 1;
    _totalConfidence += confidence;
    _totalLatency += duration;
  }

  /// Track speaker change
  Future<void> trackSpeakerChange({
    String? from,
    required String to,
  }) async {
    final eventData = SpeakerChangeData(
      fromSpeaker: from,
      toSpeaker: to,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    final event = STTEvent(
      eventType: STTEventType.speakerChanged,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );
    await track(event);
  }

  /// Track language detection
  Future<void> trackLanguageDetection({
    required String language,
    required double confidence,
  }) async {
    final eventData = LanguageDetectionData(
      language: language,
      confidence: confidence,
    );
    final event = STTEvent(
      eventType: STTEventType.languageDetected,
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
    final event = STTEvent(
      eventType: STTEventType.transcriptionStarted,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );
    await track(event);
  }

  /// Track final transcript
  Future<void> trackFinalTranscript({
    required String text,
    required double confidence,
    String? speaker,
  }) async {
    final eventData = FinalTranscriptData(
      textLength: text.length,
      wordCount: text.split(' ').length,
      confidence: confidence,
      speakerId: speaker ?? 'unknown',
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    final event = STTEvent(
      eventType: STTEventType.finalTranscript,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );
    await track(event);
  }

  /// Track partial transcript
  Future<void> trackPartialTranscript(String text) async {
    final eventData = PartialTranscriptData(
      textLength: text.length,
      wordCount: text.split(' ').length,
    );
    final event = STTEvent(
      eventType: STTEventType.partialTranscript,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );
    await track(event);
  }

  /// Track speaker detection
  Future<void> trackSpeakerDetection({
    required String speaker,
    required double confidence,
  }) async {
    final eventData = SpeakerDetectionData(
      speakerId: speaker,
      confidence: confidence,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    final event = STTEvent(
      eventType: STTEventType.speakerDetected,
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
    final event = STTEvent(
      eventType: STTEventType.error,
      sessionId: _currentSession?.id,
      eventData: eventData,
    );

    await track(event);
  }

  // MARK: - Private Methods

  Future<void> _processEvent(STTEvent event) async {
    // Custom processing for STT events if needed
    _logger.debug('Processed STT event: ${event.type}');
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
