/// Analytics error context types for strongly typed error tracking
///
/// Corresponds to iOS SDK's AnalyticsContext enum in AnalyticsContext.swift
enum AnalyticsContext {
  /// Transcription-related context
  transcription('transcription'),

  /// Pipeline processing context
  pipelineProcessing('pipeline_processing'),

  /// Initialization context
  initialization('initialization'),

  /// Component execution context
  componentExecution('component_execution'),

  /// Model loading context
  modelLoading('model_loading'),

  /// Audio processing context
  audioProcessing('audio_processing'),

  /// Text generation context
  textGeneration('text_generation'),

  /// Speaker diarization context
  speakerDiarization('speaker_diarization');

  /// The raw string value of the context
  final String rawValue;

  const AnalyticsContext(this.rawValue);

  /// Get context from raw value string
  static AnalyticsContext? fromRawValue(String value) {
    for (final context in AnalyticsContext.values) {
      if (context.rawValue == value) {
        return context;
      }
    }
    return null;
  }
}
