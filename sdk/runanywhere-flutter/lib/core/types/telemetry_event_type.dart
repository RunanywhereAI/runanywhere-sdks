/// Standard telemetry event types
/// Matches iOS TelemetryEventType from TelemetryEventType.swift
enum TelemetryEventType {
  // MARK: - Model Events
  modelLoaded('model_loaded'),
  modelLoadFailed('model_load_failed'),
  modelUnloaded('model_unloaded'),

  // MARK: - LLM Generation Events
  generationStarted('generation_started'),
  generationCompleted('generation_completed'),
  generationFailed('generation_failed'),

  // MARK: - STT (Speech-to-Text) Events
  sttModelLoaded('stt_model_loaded'),
  sttModelLoadFailed('stt_model_load_failed'),
  sttTranscriptionStarted('stt_transcription_started'),
  sttTranscriptionCompleted('stt_transcription_completed'),
  sttTranscriptionFailed('stt_transcription_failed'),
  sttStreamingUpdate('stt_streaming_update'),

  // MARK: - TTS (Text-to-Speech) Events
  ttsModelLoaded('tts_model_loaded'),
  ttsModelLoadFailed('tts_model_load_failed'),
  ttsSynthesisStarted('tts_synthesis_started'),
  ttsSynthesisCompleted('tts_synthesis_completed'),
  ttsSynthesisFailed('tts_synthesis_failed'),

  // MARK: - System Events
  error('error'),
  performance('performance'),
  memory('memory'),
  custom('custom');

  const TelemetryEventType(this.rawValue);
  final String rawValue;

  /// Create from raw string value
  static TelemetryEventType? fromString(String value) {
    return TelemetryEventType.values.cast<TelemetryEventType?>().firstWhere(
          (e) => e?.rawValue == value,
          orElse: () => null,
        );
  }

  @override
  String toString() => rawValue;
}
