/// STT (Speech-to-Text) Events.
///
/// All STT-related events in one place.
/// Each event declares its destination (public, analytics, or both).
///
/// Matches iOS `STTEvent` enum from STTEvent.swift

import '../../../infrastructure/events/event_category.dart';
import '../../../infrastructure/events/event_destination.dart';
import '../../../public/events/sdk_event.dart';

/// All STT (Speech-to-Text) related events.
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(STTTranscriptionCompletedEvent(...));
/// ```
///
/// Matches iOS `STTEvent` enum from STTEvent.swift
sealed class STTEvent with SDKEventDefaults {
  const STTEvent();

  @override
  EventCategory get category => EventCategory.stt;
}

// MARK: - Model Lifecycle Events

/// Model load started
class STTModelLoadStartedEvent extends STTEvent {
  final String modelId;
  final int modelSizeBytes;
  final String framework;

  const STTModelLoadStartedEvent({
    required this.modelId,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'stt_model_load_started';

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
class STTModelLoadCompletedEvent extends STTEvent {
  final String modelId;
  final double durationMs;
  final int modelSizeBytes;
  final String framework;

  const STTModelLoadCompletedEvent({
    required this.modelId,
    required this.durationMs,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'stt_model_load_completed';

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
class STTModelLoadFailedEvent extends STTEvent {
  final String modelId;
  final String error;
  final String framework;

  const STTModelLoadFailedEvent({
    required this.modelId,
    required this.error,
    this.framework = 'unknown',
  });

  @override
  String get type => 'stt_model_load_failed';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error,
        'framework': framework,
      };
}

/// Model unloaded
class STTModelUnloadedEvent extends STTEvent {
  final String modelId;

  const STTModelUnloadedEvent({required this.modelId});

  @override
  String get type => 'stt_model_unloaded';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// MARK: - Transcription Events

/// Transcription started
class STTTranscriptionStartedEvent extends STTEvent {
  final String transcriptionId;
  final double audioLengthMs;
  final int audioSizeBytes;
  final String language;
  final String framework;

  const STTTranscriptionStartedEvent({
    required this.transcriptionId,
    required this.audioLengthMs,
    required this.audioSizeBytes,
    required this.language,
    this.framework = 'unknown',
  });

  @override
  String get type => 'stt_transcription_started';

  @override
  Map<String, String> get properties => {
        'transcription_id': transcriptionId,
        'audio_length_ms': audioLengthMs.toStringAsFixed(1),
        'audio_size_bytes': audioSizeBytes.toString(),
        'language': language,
        'framework': framework,
      };
}

/// Partial transcript (streaming)
class STTPartialTranscriptEvent extends STTEvent {
  final String text;
  final int wordCount;

  const STTPartialTranscriptEvent({
    required this.text,
    required this.wordCount,
  });

  @override
  String get type => 'stt_partial_transcript';

  @override
  Map<String, String> get properties => {
        'text_length': text.length.toString(),
        'word_count': wordCount.toString(),
      };
}

/// Final transcript
class STTFinalTranscriptEvent extends STTEvent {
  final String text;
  final double confidence;

  const STTFinalTranscriptEvent({
    required this.text,
    required this.confidence,
  });

  @override
  String get type => 'stt_final_transcript';

  @override
  Map<String, String> get properties => {
        'text_length': text.length.toString(),
        'confidence': confidence.toStringAsFixed(3),
      };
}

/// Transcription completed
class STTTranscriptionCompletedEvent extends STTEvent {
  final String transcriptionId;
  final String text;
  final double confidence;
  final double durationMs;
  final double audioLengthMs;
  final int audioSizeBytes;
  final int wordCount;
  final double realTimeFactor;
  final String framework;

  const STTTranscriptionCompletedEvent({
    required this.transcriptionId,
    required this.text,
    required this.confidence,
    required this.durationMs,
    required this.audioLengthMs,
    required this.audioSizeBytes,
    required this.wordCount,
    required this.realTimeFactor,
    this.framework = 'unknown',
  });

  @override
  String get type => 'stt_transcription_completed';

  @override
  Map<String, String> get properties => {
        'transcription_id': transcriptionId,
        'text_length': text.length.toString(),
        'confidence': confidence.toStringAsFixed(3),
        'duration_ms': durationMs.toStringAsFixed(1),
        'audio_length_ms': audioLengthMs.toStringAsFixed(1),
        'audio_size_bytes': audioSizeBytes.toString(),
        'word_count': wordCount.toString(),
        'real_time_factor': realTimeFactor.toStringAsFixed(3),
        'framework': framework,
      };
}

/// Transcription failed
class STTTranscriptionFailedEvent extends STTEvent {
  final String transcriptionId;
  final String error;

  const STTTranscriptionFailedEvent({
    required this.transcriptionId,
    required this.error,
  });

  @override
  String get type => 'stt_transcription_failed';

  @override
  Map<String, String> get properties => {
        'transcription_id': transcriptionId,
        'error': error,
      };
}

// MARK: - Detection Events

/// Language detected (analytics only)
class STTLanguageDetectedEvent extends STTEvent {
  final String language;
  final double confidence;

  const STTLanguageDetectedEvent({
    required this.language,
    required this.confidence,
  });

  @override
  String get type => 'stt_language_detected';

  /// Language detection is analytics only
  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  @override
  Map<String, String> get properties => {
        'language': language,
        'confidence': confidence.toStringAsFixed(3),
      };
}
