// TTS analytics service.
// Tracks synthesis operations and metrics.
// Matches iOS TTSAnalyticsService.
//
// NOTE: Audio duration estimation assumes 16-bit PCM @ 22050Hz (standard for TTS).
// Formula: audioDurationMs = (bytes / 2) / 22050 * 1000
// Actual sample rates may vary depending on the TTS model/voice configuration.

import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// TTS analytics service for tracking synthesis operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
class TTSAnalyticsService {
  final SDKLogger _logger = SDKLogger(category: 'TTSAnalytics');

  /// Active synthesis operations
  final Map<String, _SynthesisTracker> _activeSyntheses = {};

  /// Metrics
  int _synthesisCount = 0;
  int _totalCharacters = 0;
  double _totalProcessingTimeMs = 0;
  double _totalAudioDurationMs = 0;
  int _totalAudioSizeBytes = 0;
  double _totalCharactersPerSecond = 0;
  final DateTime _startTime = DateTime.now();
  DateTime? _lastEventTime;

  TTSAnalyticsService();

  /// Start tracking a synthesis.
  /// Returns a unique synthesis ID for tracking.
  String startSynthesis({
    required String text,
    required String voice,
    String? framework,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final characterCount = text.length;

    _activeSyntheses[id] = _SynthesisTracker(
      startTime: DateTime.now(),
      voiceId: voice,
      characterCount: characterCount,
      framework: framework,
    );

    _logger.debug('Synthesis started: $id, $characterCount characters');
    return id;
  }

  /// Track synthesis chunk (for streaming synthesis).
  void trackSynthesisChunk({
    required String synthesisId,
    required int chunkSize,
  }) {
    _logger.debug('Synthesis chunk: $synthesisId, $chunkSize bytes');
  }

  /// Complete a synthesis.
  void completeSynthesis({
    required String synthesisId,
    required double audioDurationMs,
    required int audioSizeBytes,
  }) {
    final tracker = _activeSyntheses.remove(synthesisId);
    if (tracker == null) return;

    final endTime = DateTime.now();
    final processingTimeMs =
        endTime.difference(tracker.startTime).inMicroseconds / 1000.0;
    final characterCount = tracker.characterCount;

    // Calculate characters per second (synthesis speed)
    final charsPerSecond =
        processingTimeMs > 0 ? characterCount / (processingTimeMs / 1000.0) : 0;

    // Update metrics
    _synthesisCount++;
    _totalCharacters += characterCount;
    _totalProcessingTimeMs += processingTimeMs;
    _totalAudioDurationMs += audioDurationMs;
    _totalAudioSizeBytes += audioSizeBytes;
    _totalCharactersPerSecond += charsPerSecond;
    _lastEventTime = endTime;

    _logger.debug(
        'Synthesis completed: $synthesisId, audio: ${audioDurationMs.toStringAsFixed(1)}ms, $audioSizeBytes bytes');
  }

  /// Track synthesis failure.
  void trackSynthesisFailed({
    required String synthesisId,
    required String errorMessage,
  }) {
    _activeSyntheses.remove(synthesisId);
    _lastEventTime = DateTime.now();
    _logger.warning('Synthesis failed: $synthesisId - $errorMessage');
  }

  /// Track an error during operations.
  void trackError(Object error, String operation) {
    _lastEventTime = DateTime.now();
    _logger.error('Error in $operation: $error');
  }

  /// Get current TTS analytics metrics.
  TTSMetrics getMetrics() {
    return TTSMetrics(
      totalEvents: _synthesisCount,
      startTime: _startTime,
      lastEventTime: _lastEventTime,
      totalSyntheses: _synthesisCount,
      averageCharactersPerSecond: _synthesisCount > 0
          ? _totalCharactersPerSecond / _synthesisCount
          : 0.0,
      averageProcessingTimeMs:
          _synthesisCount > 0 ? _totalProcessingTimeMs / _synthesisCount : 0.0,
      averageAudioDurationMs:
          _synthesisCount > 0 ? _totalAudioDurationMs / _synthesisCount : 0.0,
      totalCharactersProcessed: _totalCharacters,
      totalAudioSizeBytes: _totalAudioSizeBytes,
    );
  }
}

/// Internal tracker for synthesis operations.
class _SynthesisTracker {
  final DateTime startTime;
  final String voiceId;
  final int characterCount;
  final String? framework;

  _SynthesisTracker({
    required this.startTime,
    required this.voiceId,
    required this.characterCount,
    this.framework,
  });
}

/// TTS metrics.
/// Matches iOS TTSMetrics.
class TTSMetrics {
  final int totalEvents;
  final DateTime startTime;
  final DateTime? lastEventTime;
  final int totalSyntheses;

  /// Average synthesis speed (characters processed per second)
  final double averageCharactersPerSecond;

  /// Average processing time in milliseconds
  final double averageProcessingTimeMs;

  /// Average audio duration in milliseconds
  final double averageAudioDurationMs;

  /// Total characters processed across all syntheses
  final int totalCharactersProcessed;

  /// Total audio size generated in bytes
  final int totalAudioSizeBytes;

  const TTSMetrics({
    this.totalEvents = 0,
    required this.startTime,
    this.lastEventTime,
    this.totalSyntheses = 0,
    this.averageCharactersPerSecond = 0,
    this.averageProcessingTimeMs = 0,
    this.averageAudioDurationMs = 0,
    this.totalCharactersProcessed = 0,
    this.totalAudioSizeBytes = 0,
  });
}
