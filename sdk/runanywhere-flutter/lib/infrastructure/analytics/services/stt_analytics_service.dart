// STT analytics service.
// Tracks transcription operations and metrics.
// Matches iOS STTAnalyticsService.
//
// NOTE: Audio length estimation assumes 16-bit PCM @ 16kHz (standard for STT).
// Formula: audioLengthMs = (bytes / 2) / 16000 * 1000
//
// NOTE: Real-Time Factor (RTF) will be 0 or undefined for streaming transcription
// since audioLengthMs = 0 when audio is processed in chunks of unknown total length.

import '../../../foundation/logging/sdk_logger.dart';

/// STT analytics service for tracking transcription operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
class STTAnalyticsService {
  final SDKLogger _logger = SDKLogger(category: 'STTAnalytics');

  /// Active transcription operations
  final Map<String, _TranscriptionTracker> _activeTranscriptions = {};

  /// Metrics
  int _transcriptionCount = 0;
  double _totalConfidence = 0;
  double _totalLatency = 0;
  double _totalAudioProcessed = 0; // Total audio length in ms
  double _totalRealTimeFactor = 0;
  final DateTime _startTime = DateTime.now();
  DateTime? _lastEventTime;

  STTAnalyticsService();

  /// Start tracking a transcription.
  /// Returns a unique transcription ID for tracking.
  String startTranscription({
    required double audioLengthMs,
    required int audioSizeBytes,
    required String language,
    String? framework,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _activeTranscriptions[id] = _TranscriptionTracker(
      startTime: DateTime.now(),
      audioLengthMs: audioLengthMs,
      audioSizeBytes: audioSizeBytes,
      framework: framework,
    );

    _logger.debug(
        'Transcription started: $id, audio: ${audioLengthMs.toStringAsFixed(1)}ms, $audioSizeBytes bytes');
    return id;
  }

  /// Track partial transcript (for streaming transcription).
  void trackPartialTranscript(String text) {
    final wordCount = text.split(' ').length;
    _logger.debug('Partial transcript: $wordCount words');
  }

  /// Track final transcript (for streaming transcription).
  void trackFinalTranscript(
      {required String text, required double confidence}) {
    _logger.debug(
        'Final transcript, confidence: ${confidence.toStringAsFixed(2)}');
  }

  /// Complete a transcription.
  void completeTranscription({
    required String transcriptionId,
    required String text,
    required double confidence,
  }) {
    final tracker = _activeTranscriptions.remove(transcriptionId);
    if (tracker == null) return;

    final endTime = DateTime.now();
    final processingTimeMs =
        endTime.difference(tracker.startTime).inMicroseconds / 1000.0;
    final wordCount = text.split(' ').length;

    // Calculate real-time factor (RTF): processing time / audio length
    // RTF < 1.0 means faster than real-time
    final realTimeFactor = tracker.audioLengthMs > 0
        ? processingTimeMs / tracker.audioLengthMs
        : 0;

    // Update metrics
    _transcriptionCount++;
    _totalConfidence += confidence;
    _totalLatency += processingTimeMs / 1000.0;
    _totalAudioProcessed += tracker.audioLengthMs;
    _totalRealTimeFactor += realTimeFactor;
    _lastEventTime = endTime;

    _logger.debug(
        'Transcription completed: $transcriptionId, words: $wordCount, RTF: ${realTimeFactor.toStringAsFixed(3)}');
  }

  /// Track transcription failure.
  void trackTranscriptionFailed({
    required String transcriptionId,
    required String errorMessage,
  }) {
    _activeTranscriptions.remove(transcriptionId);
    _lastEventTime = DateTime.now();
    _logger.warning('Transcription failed: $transcriptionId - $errorMessage');
  }

  /// Track language detection.
  void trackLanguageDetection({
    required String language,
    required double confidence,
  }) {
    _logger.debug(
        'Language detected: $language, confidence: ${confidence.toStringAsFixed(2)}');
  }

  /// Track an error during operations.
  void trackError(Object error, String operation) {
    _lastEventTime = DateTime.now();
    _logger.error('Error in $operation: $error');
  }

  /// Get current STT analytics metrics.
  STTMetrics getMetrics() {
    // Average RTF only if we have transcriptions
    final avgRTF = _transcriptionCount > 0
        ? _totalRealTimeFactor / _transcriptionCount
        : 0.0;

    return STTMetrics(
      totalEvents: _transcriptionCount,
      startTime: _startTime,
      lastEventTime: _lastEventTime,
      totalTranscriptions: _transcriptionCount,
      averageConfidence: _transcriptionCount > 0
          ? _totalConfidence / _transcriptionCount
          : 0.0,
      averageLatency:
          _transcriptionCount > 0 ? _totalLatency / _transcriptionCount : 0.0,
      averageRealTimeFactor: avgRTF,
      totalAudioProcessedMs: _totalAudioProcessed,
    );
  }
}

/// Internal tracker for transcription operations.
class _TranscriptionTracker {
  final DateTime startTime;
  final double audioLengthMs;
  final int audioSizeBytes;
  final String? framework;

  _TranscriptionTracker({
    required this.startTime,
    required this.audioLengthMs,
    required this.audioSizeBytes,
    this.framework,
  });
}

/// STT metrics.
/// Matches iOS STTMetrics.
class STTMetrics {
  final int totalEvents;
  final DateTime startTime;
  final DateTime? lastEventTime;
  final int totalTranscriptions;

  /// Average confidence score across all transcriptions (0.0 to 1.0)
  final double averageConfidence;

  /// Average processing latency in seconds
  final double averageLatency;

  /// Average real-time factor (processing time / audio length).
  /// Values < 1.0 indicate faster-than-real-time processing.
  final double averageRealTimeFactor;

  /// Total audio processed in milliseconds
  final double totalAudioProcessedMs;

  const STTMetrics({
    this.totalEvents = 0,
    required this.startTime,
    this.lastEventTime,
    this.totalTranscriptions = 0,
    this.averageConfidence = 0,
    this.averageLatency = 0,
    this.averageRealTimeFactor = 0,
    this.totalAudioProcessedMs = 0,
  });
}
