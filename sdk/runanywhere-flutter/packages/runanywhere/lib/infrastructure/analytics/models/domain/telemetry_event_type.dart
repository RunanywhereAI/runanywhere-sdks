//
//  telemetry_event_type.dart
//  RunAnywhere SDK
//
//  Telemetry event types matching iOS SDK's TelemetryEventType.swift
//

/// Standard telemetry event types
enum TelemetryEventType {
  // Model Events
  modelLoaded('model_loaded'),
  modelLoadFailed('model_load_failed'),
  modelUnloaded('model_unloaded'),

  // LLM Generation Events
  generationStarted('generation_started'),
  generationCompleted('generation_completed'),
  generationFailed('generation_failed'),

  // STT (Speech-to-Text) Events
  sttModelLoaded('stt_model_loaded'),
  sttModelLoadFailed('stt_model_load_failed'),
  sttTranscriptionStarted('stt_transcription_started'),
  sttTranscriptionCompleted('stt_transcription_completed'),
  sttTranscriptionFailed('stt_transcription_failed'),
  sttStreamingUpdate('stt_streaming_update'),

  // TTS (Text-to-Speech) Events
  ttsModelLoaded('tts_model_loaded'),
  ttsModelLoadFailed('tts_model_load_failed'),
  ttsSynthesisStarted('tts_synthesis_started'),
  ttsSynthesisCompleted('tts_synthesis_completed'),
  ttsSynthesisFailed('tts_synthesis_failed'),

  // Speaker Diarization Events
  speakerDiarizationStarted('speaker_diarization_started'),
  speakerDiarizationCompleted('speaker_diarization_completed'),
  speakerDiarizationFailed('speaker_diarization_failed'),

  // System Events
  error('error'),
  performance('performance'),
  memory('memory'),
  custom('custom');

  final String rawValue;

  const TelemetryEventType(this.rawValue);

  /// Create from raw string value
  static TelemetryEventType? fromRawValue(String value) {
    for (final type in TelemetryEventType.values) {
      if (type.rawValue == value) {
        return type;
      }
    }
    return null;
  }
}
