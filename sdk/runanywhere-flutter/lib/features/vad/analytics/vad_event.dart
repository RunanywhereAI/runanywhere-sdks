/// VAD (Voice Activity Detection) Events.
///
/// All VAD-related events in one place.
/// Each event declares its destination (public, analytics, or both).
///
/// Matches iOS `VADEvent` enum from VADEvent.swift

import '../../../infrastructure/events/event_category.dart';
import '../../../infrastructure/events/event_destination.dart';
import '../../../public/events/sdk_event.dart';

/// All VAD (Voice Activity Detection) related events.
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(VADSpeechStartedEvent());
/// ```
///
/// Matches iOS `VADEvent` enum from VADEvent.swift
sealed class VADEvent with SDKEventDefaults {
  const VADEvent();

  @override
  EventCategory get category => EventCategory.voice;
}

// MARK: - Service Lifecycle Events

/// VAD service initialized
class VADInitializedEvent extends VADEvent {
  final String framework;

  const VADInitializedEvent({this.framework = 'builtIn'});

  @override
  String get type => 'vad_initialized';

  @override
  Map<String, String> get properties => {'framework': framework};
}

/// VAD initialization failed
class VADInitializationFailedEvent extends VADEvent {
  final String error;
  final String framework;

  const VADInitializationFailedEvent({
    required this.error,
    this.framework = 'builtIn',
  });

  @override
  String get type => 'vad_initialization_failed';

  @override
  Map<String, String> get properties => {
        'error': error,
        'framework': framework,
      };
}

/// VAD cleaned up
class VADCleanedUpEvent extends VADEvent {
  const VADCleanedUpEvent();

  @override
  String get type => 'vad_cleaned_up';

  @override
  Map<String, String> get properties => {};
}

// MARK: - Model Lifecycle Events

/// Model load started
class VADModelLoadStartedEvent extends VADEvent {
  final String modelId;
  final int modelSizeBytes;
  final String framework;

  const VADModelLoadStartedEvent({
    required this.modelId,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'vad_model_load_started';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'model_id': modelId,
      'framework': framework,
    };
    if (modelSizeBytes > 0) {
      props['model_size_bytes'] = modelSizeBytes.toString();
    }
    return props;
  }
}

/// Model load completed
class VADModelLoadCompletedEvent extends VADEvent {
  final String modelId;
  final double durationMs;
  final int modelSizeBytes;
  final String framework;

  const VADModelLoadCompletedEvent({
    required this.modelId,
    required this.durationMs,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'vad_model_load_completed';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'model_id': modelId,
      'duration_ms': durationMs.toStringAsFixed(1),
      'framework': framework,
    };
    if (modelSizeBytes > 0) {
      props['model_size_bytes'] = modelSizeBytes.toString();
    }
    return props;
  }
}

/// Model load failed
class VADModelLoadFailedEvent extends VADEvent {
  final String modelId;
  final String error;
  final String framework;

  const VADModelLoadFailedEvent({
    required this.modelId,
    required this.error,
    this.framework = 'unknown',
  });

  @override
  String get type => 'vad_model_load_failed';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error,
        'framework': framework,
      };
}

/// Model unloaded
class VADModelUnloadedEvent extends VADEvent {
  final String modelId;

  const VADModelUnloadedEvent({required this.modelId});

  @override
  String get type => 'vad_model_unloaded';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// MARK: - Detection Events

/// VAD started
class VADStartedEvent extends VADEvent {
  const VADStartedEvent();

  @override
  String get type => 'vad_started';

  @override
  Map<String, String> get properties => {};
}

/// VAD stopped
class VADStoppedEvent extends VADEvent {
  const VADStoppedEvent();

  @override
  String get type => 'vad_stopped';

  @override
  Map<String, String> get properties => {};
}

/// Speech started (analytics only)
class VADSpeechStartedEvent extends VADEvent {
  const VADSpeechStartedEvent();

  @override
  String get type => 'vad_speech_started';

  /// Speech events are analytics only to avoid flooding public API
  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  @override
  Map<String, String> get properties => {};
}

/// Speech ended (analytics only)
class VADSpeechEndedEvent extends VADEvent {
  final double durationMs;

  const VADSpeechEndedEvent({required this.durationMs});

  @override
  String get type => 'vad_speech_ended';

  /// Speech events are analytics only to avoid flooding public API
  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  @override
  Map<String, String> get properties =>
      {'duration_ms': durationMs.toStringAsFixed(1)};
}

/// VAD paused
class VADPausedEvent extends VADEvent {
  const VADPausedEvent();

  @override
  String get type => 'vad_paused';

  @override
  Map<String, String> get properties => {};
}

/// VAD resumed
class VADResumedEvent extends VADEvent {
  const VADResumedEvent();

  @override
  String get type => 'vad_resumed';

  @override
  Map<String, String> get properties => {};
}

// MARK: - VAD Metrics

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
