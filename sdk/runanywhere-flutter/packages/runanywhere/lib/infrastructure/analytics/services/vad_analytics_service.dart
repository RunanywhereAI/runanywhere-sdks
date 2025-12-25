// VAD analytics service.
// Tracks VAD operations and metrics.
// Matches iOS VADAnalyticsService.

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/events/event_publisher.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// VAD analytics service for tracking voice activity detection.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle when applicable.
class VADAnalyticsService {
  final SDKLogger _logger = SDKLogger(category: 'VADAnalytics');

  /// Current framework being used
  String _currentFramework = 'builtIn';

  /// Speech segment tracking
  DateTime? _speechStartTime;

  /// Metrics
  int _totalSpeechSegments = 0;
  double _totalSpeechDurationMs = 0;
  final DateTime _startTime = DateTime.now();
  DateTime? _lastEventTime;

  VADAnalyticsService();

  // MARK: - Lifecycle Tracking

  /// Track VAD initialization
  void trackInitialized({String framework = 'builtIn'}) {
    _currentFramework = framework;
    _lastEventTime = DateTime.now();

    EventPublisher.shared.track(SDKVoiceVADStarted());
    _logger.debug('VAD initialized with framework: $_currentFramework');
  }

  /// Track VAD initialization failure
  void trackInitializationFailed({
    required String error,
    String framework = 'builtIn',
  }) {
    _currentFramework = framework;
    _lastEventTime = DateTime.now();
    _logger.error('VAD initialization failed: $error (framework: $_currentFramework)');
  }

  /// Track VAD cleanup
  void trackCleanedUp() {
    _lastEventTime = DateTime.now();
    _logger.debug('VAD cleaned up');
  }

  // MARK: - Detection Tracking

  /// Track VAD started
  void trackStarted() {
    _lastEventTime = DateTime.now();
    EventPublisher.shared.track(SDKVoiceVADStarted());
    _logger.debug('VAD started');
  }

  /// Track VAD stopped
  void trackStopped() {
    _lastEventTime = DateTime.now();
    _logger.debug('VAD stopped');
  }

  /// Track speech detected (start of speech/voice activity)
  void trackSpeechStart() {
    _speechStartTime = DateTime.now();
    _lastEventTime = DateTime.now();

    EventPublisher.shared.track(SDKVoiceVADDetected());
    _logger.debug('Speech started');
  }

  /// Track speech ended (silence detected after speech)
  void trackSpeechEnd() {
    final startTime = _speechStartTime;
    if (startTime == null) return;

    final endTime = DateTime.now();
    final durationMs = endTime.difference(startTime).inMicroseconds / 1000.0;
    _speechStartTime = null;

    // Update metrics
    _totalSpeechSegments++;
    _totalSpeechDurationMs += durationMs;
    _lastEventTime = endTime;

    EventPublisher.shared.track(SDKVoiceVADEnded());
    _logger.debug('Speech ended, duration: ${durationMs.toStringAsFixed(1)}ms');
  }

  /// Track paused
  void trackPaused() {
    _lastEventTime = DateTime.now();
    _logger.debug('VAD paused');
  }

  /// Track resumed
  void trackResumed() {
    _lastEventTime = DateTime.now();
    _logger.debug('VAD resumed');
  }

  // MARK: - Model Lifecycle (for model-based VAD)

  /// Track model load started (for model-based VAD like Silero)
  void trackModelLoadStarted({
    required String modelId,
    int modelSizeBytes = 0,
    String framework = 'unknown',
  }) {
    _currentFramework = framework;
    _lastEventTime = DateTime.now();
    _logger.debug('VAD model load started: $modelId ($framework)');
  }

  /// Track model load completed
  void trackModelLoadCompleted({
    required String modelId,
    required double durationMs,
    int modelSizeBytes = 0,
  }) {
    _lastEventTime = DateTime.now();
    _logger.debug(
        'VAD model loaded: $modelId, duration: ${durationMs.toStringAsFixed(1)}ms');
  }

  /// Track model load failed
  void trackModelLoadFailed({
    required String modelId,
    required String error,
  }) {
    _lastEventTime = DateTime.now();
    _logger.error('VAD model load failed: $modelId - $error');
  }

  /// Track model unloaded
  void trackModelUnloaded({required String modelId}) {
    _lastEventTime = DateTime.now();
    _logger.debug('VAD model unloaded: $modelId');
  }

  /// Track an error during operations.
  void trackError(Object error, String operation) {
    _lastEventTime = DateTime.now();
    _logger.error('Error in $operation: $error');
  }

  // MARK: - Metrics

  /// Get current VAD analytics metrics.
  VADMetrics getMetrics() {
    return VADMetrics(
      totalEvents: _totalSpeechSegments,
      startTime: _startTime,
      lastEventTime: _lastEventTime,
      totalSpeechSegments: _totalSpeechSegments,
      totalSpeechDurationMs: _totalSpeechDurationMs,
      averageSpeechDurationMs: _totalSpeechSegments > 0
          ? _totalSpeechDurationMs / _totalSpeechSegments
          : -1, // -1 indicates N/A
      framework: _currentFramework,
    );
  }
}

/// VAD metrics.
/// Matches iOS VADMetrics.
class VADMetrics {
  final int totalEvents;
  final DateTime startTime;
  final DateTime? lastEventTime;
  final int totalSpeechSegments;

  /// Total duration of all speech segments in milliseconds
  final double totalSpeechDurationMs;

  /// Average duration of speech segments in milliseconds.
  /// -1 indicates N/A (no segments yet).
  final double averageSpeechDurationMs;

  /// Framework being used (e.g., 'builtIn', 'silero', 'webrtc')
  final String framework;

  const VADMetrics({
    this.totalEvents = 0,
    required this.startTime,
    this.lastEventTime,
    this.totalSpeechSegments = 0,
    this.totalSpeechDurationMs = 0,
    this.averageSpeechDurationMs = -1,
    this.framework = 'builtIn',
  });
}
