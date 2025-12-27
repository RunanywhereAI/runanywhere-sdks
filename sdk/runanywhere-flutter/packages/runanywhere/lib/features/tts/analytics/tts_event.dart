import 'package:runanywhere/public/events/sdk_event.dart';

/// All TTS (Text-to-Speech) related events.
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(TTSSynthesisCompletedEvent(...));
/// ```
///
/// Matches iOS `TTSEvent` enum from TTSEvent.swift
sealed class TTSEvent with SDKEventDefaults {
  const TTSEvent();

  @override
  EventCategory get category => EventCategory.tts;
}

// MARK: - Model Lifecycle Events

/// Model load started
class TTSModelLoadStartedEvent extends TTSEvent {
  final String voiceId;
  final int modelSizeBytes;
  final String framework;

  const TTSModelLoadStartedEvent({
    required this.voiceId,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'tts_model_load_started';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'voice_id': voiceId,
      'framework': framework,
    };
    if (modelSizeBytes > 0) {
      props['model_size_bytes'] = modelSizeBytes.toString();
    }
    return props;
  }
}

/// Model load completed
class TTSModelLoadCompletedEvent extends TTSEvent {
  final String voiceId;
  final double durationMs;
  final int modelSizeBytes;
  final String framework;

  const TTSModelLoadCompletedEvent({
    required this.voiceId,
    required this.durationMs,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'tts_model_load_completed';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'voice_id': voiceId,
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
class TTSModelLoadFailedEvent extends TTSEvent {
  final String voiceId;
  final String error;
  final String framework;

  const TTSModelLoadFailedEvent({
    required this.voiceId,
    required this.error,
    this.framework = 'unknown',
  });

  @override
  String get type => 'tts_model_load_failed';

  @override
  Map<String, String> get properties => {
        'voice_id': voiceId,
        'error': error,
        'framework': framework,
      };
}

/// Model unloaded
class TTSModelUnloadedEvent extends TTSEvent {
  final String voiceId;

  const TTSModelUnloadedEvent({required this.voiceId});

  @override
  String get type => 'tts_model_unloaded';

  @override
  Map<String, String> get properties => {'voice_id': voiceId};
}

// MARK: - Synthesis Events

/// Synthesis started
class TTSSynthesisStartedEvent extends TTSEvent {
  final String synthesisId;
  final String voiceId;
  final int characterCount;
  final String framework;

  const TTSSynthesisStartedEvent({
    required this.synthesisId,
    required this.voiceId,
    required this.characterCount,
    this.framework = 'unknown',
  });

  @override
  String get type => 'tts_synthesis_started';

  @override
  Map<String, String> get properties => {
        'synthesis_id': synthesisId,
        'voice_id': voiceId,
        'character_count': characterCount.toString(),
        'framework': framework,
      };
}

/// Synthesis chunk generated (streaming)
class TTSSynthesisChunkEvent extends TTSEvent {
  final String synthesisId;
  final int chunkSize;

  const TTSSynthesisChunkEvent({
    required this.synthesisId,
    required this.chunkSize,
  });

  @override
  String get type => 'tts_synthesis_chunk';

  /// Chunk events are too chatty for public API
  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  @override
  Map<String, String> get properties => {
        'synthesis_id': synthesisId,
        'chunk_size': chunkSize.toString(),
      };
}

/// Synthesis completed
class TTSSynthesisCompletedEvent extends TTSEvent {
  final String synthesisId;
  final String voiceId;
  final int characterCount;
  final double audioDurationMs;
  final int audioSizeBytes;
  final double processingDurationMs;
  final double charactersPerSecond;
  final String framework;

  const TTSSynthesisCompletedEvent({
    required this.synthesisId,
    required this.voiceId,
    required this.characterCount,
    required this.audioDurationMs,
    required this.audioSizeBytes,
    required this.processingDurationMs,
    required this.charactersPerSecond,
    this.framework = 'unknown',
  });

  @override
  String get type => 'tts_synthesis_completed';

  @override
  Map<String, String> get properties => {
        'synthesis_id': synthesisId,
        'voice_id': voiceId,
        'character_count': characterCount.toString(),
        'audio_duration_ms': audioDurationMs.toStringAsFixed(1),
        'audio_size_bytes': audioSizeBytes.toString(),
        'processing_duration_ms': processingDurationMs.toStringAsFixed(1),
        'chars_per_second': charactersPerSecond.toStringAsFixed(2),
        'framework': framework,
      };
}

/// Synthesis failed
class TTSSynthesisFailedEvent extends TTSEvent {
  final String synthesisId;
  final String error;

  const TTSSynthesisFailedEvent({
    required this.synthesisId,
    required this.error,
  });

  @override
  String get type => 'tts_synthesis_failed';

  @override
  Map<String, String> get properties => {
        'synthesis_id': synthesisId,
        'error': error,
      };
}
