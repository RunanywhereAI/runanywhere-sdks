/**
 * TelemetryEventType.ts
 *
 * Standard telemetry event types
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/TelemetryEventType.swift
 */

/**
 * Standard telemetry event types
 */
export enum TelemetryEventType {
  // MARK: - Model Events
  ModelLoaded = 'model_loaded',
  ModelLoadFailed = 'model_load_failed',
  ModelUnloaded = 'model_unloaded',

  // MARK: - LLM Generation Events
  GenerationStarted = 'generation_started',
  GenerationCompleted = 'generation_completed',
  GenerationFailed = 'generation_failed',

  // MARK: - STT (Speech-to-Text) Events
  STTModelLoaded = 'stt_model_loaded',
  STTModelLoadFailed = 'stt_model_load_failed',
  STTTranscriptionStarted = 'stt_transcription_started',
  STTTranscriptionCompleted = 'stt_transcription_completed',
  STTTranscriptionFailed = 'stt_transcription_failed',
  STTStreamingUpdate = 'stt_streaming_update',

  // MARK: - TTS (Text-to-Speech) Events
  TTSModelLoaded = 'tts_model_loaded',
  TTSModelLoadFailed = 'tts_model_load_failed',
  TTSSynthesisStarted = 'tts_synthesis_started',
  TTSSynthesisCompleted = 'tts_synthesis_completed',
  TTSSynthesisFailed = 'tts_synthesis_failed',

  // MARK: - System Events
  Error = 'error',
  Performance = 'performance',
  Memory = 'memory',
  Custom = 'custom',
}
