/**
 * analytics.ts
 *
 * Analytics event types and data structures for all analytics events
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Analytics/Models/AnalyticsEventData.swift
 */

// MARK: - Base Analytics Interfaces

/**
 * Base protocol for all structured event data
 */
export interface AnalyticsEventData {}

/**
 * Base analytics event interface
 */
export interface AnalyticsEvent {
  readonly id: string;
  readonly type: string;
  readonly timestamp: Date;
  readonly sessionId?: string;
  readonly eventData: AnalyticsEventData;
}

/**
 * Analytics metrics interface
 */
export interface AnalyticsMetrics {
  readonly totalEvents: number;
  readonly startTime: Date;
  readonly lastEventTime?: Date;
}

/**
 * Session metadata
 */
export interface SessionMetadata {
  readonly id: string;
  readonly modelId?: string;
  readonly type?: string;
}

/**
 * Analytics error context types
 */
export enum AnalyticsContext {
  TRANSCRIPTION = 'transcription',
  PIPELINE_PROCESSING = 'pipeline_processing',
  INITIALIZATION = 'initialization',
  COMPONENT_EXECUTION = 'component_execution',
  MODEL_LOADING = 'model_loading',
  AUDIO_PROCESSING = 'audio_processing',
  TEXT_GENERATION = 'text_generation',
  SPEAKER_DIARIZATION = 'speaker_diarization',
  TTS_SYNTHESIS = 'tts_synthesis',
}

// MARK: - STT Event Types and Data

/**
 * STT event types
 */
export enum STTEventType {
  TRANSCRIPTION_STARTED = 'stt_transcription_started',
  TRANSCRIPTION_COMPLETED = 'stt_transcription_completed',
  PARTIAL_TRANSCRIPT = 'stt_partial_transcript',
  FINAL_TRANSCRIPT = 'stt_final_transcript',
  SPEAKER_DETECTED = 'stt_speaker_detected',
  SPEAKER_CHANGED = 'stt_speaker_changed',
  LANGUAGE_DETECTED = 'stt_language_detected',
  MODEL_LOADED = 'stt_model_loaded',
  MODEL_LOAD_FAILED = 'stt_model_load_failed',
  ERROR = 'stt_error',
}

/**
 * STT transcription start event data
 */
export interface TranscriptionStartData extends AnalyticsEventData {
  audioLengthMs: number;
  startTimestamp: number;
}

/**
 * STT transcription completion data
 */
export interface STTTranscriptionData extends AnalyticsEventData {
  wordCount: number;
  confidence: number;
  durationMs: number;
  audioLengthMs: number;
  realTimeFactor: number;
  speakerId: string;
}

/**
 * Final transcript event data
 */
export interface FinalTranscriptData extends AnalyticsEventData {
  textLength: number;
  wordCount: number;
  confidence: number;
  speakerId: string;
  timestamp: number;
}

/**
 * Partial transcript event data
 */
export interface PartialTranscriptData extends AnalyticsEventData {
  textLength: number;
  wordCount: number;
}

/**
 * Speaker detection event data
 */
export interface SpeakerDetectionData extends AnalyticsEventData {
  speakerId: string;
  confidence: number;
  timestamp: number;
}

/**
 * Speaker change event data
 */
export interface SpeakerChangeData extends AnalyticsEventData {
  fromSpeaker: string;
  toSpeaker: string;
  timestamp: number;
}

/**
 * Language detection event data
 */
export interface LanguageDetectionData extends AnalyticsEventData {
  language: string;
  confidence: number;
}

/**
 * STT metrics
 */
export interface STTMetrics extends AnalyticsMetrics {
  totalTranscriptions: number;
  averageConfidence: number;
  averageLatency: number;
}

// MARK: - TTS Event Types and Data

/**
 * TTS event types
 */
export enum TTSEventType {
  SYNTHESIS_STARTED = 'tts_synthesis_started',
  SYNTHESIS_COMPLETED = 'tts_synthesis_completed',
  SYNTHESIS_CHUNK = 'tts_synthesis_chunk',
  MODEL_LOADED = 'tts_model_loaded',
  MODEL_LOAD_FAILED = 'tts_model_load_failed',
  ERROR = 'tts_error',
}

/**
 * TTS synthesis start event data
 */
export interface TTSSynthesisStartData extends AnalyticsEventData {
  characterCount: number;
  voice: string;
  language: string;
  startTimestamp: number;
}

/**
 * TTS synthesis completion event data
 */
export interface TTSSynthesisCompletionData extends AnalyticsEventData {
  characterCount: number;
  audioDurationMs: number;
  audioSizeBytes: number;
  processingTimeMs: number;
  charactersPerSecond: number;
  realTimeFactor: number;
}

/**
 * TTS metrics
 */
export interface TTSMetrics extends AnalyticsMetrics {
  totalSyntheses: number;
  averageCharactersPerSecond: number;
  averageProcessingTimeMs: number;
  totalCharactersProcessed: number;
}

// MARK: - LLM Event Types and Data

/**
 * LLM/Generation event types
 */
export enum GenerationEventType {
  SESSION_STARTED = 'generation_session_started',
  SESSION_ENDED = 'generation_session_ended',
  GENERATION_STARTED = 'generation_started',
  GENERATION_COMPLETED = 'generation_completed',
  FIRST_TOKEN_GENERATED = 'generation_first_token',
  STREAMING_UPDATE = 'generation_streaming_update',
  ERROR = 'generation_error',
  MODEL_LOADED = 'generation_model_loaded',
  MODEL_LOAD_FAILED = 'generation_model_load_failed',
  MODEL_UNLOADED = 'generation_model_unloaded',
}

/**
 * Generation start event data
 */
export interface GenerationStartData extends AnalyticsEventData {
  generationId: string;
  modelId: string;
  executionTarget: string;
  promptTokens: number;
  maxTokens: number;
}

/**
 * Generation completion event data
 */
export interface GenerationCompletionData extends AnalyticsEventData {
  generationId: string;
  modelId: string;
  executionTarget: string;
  inputTokens: number;
  outputTokens: number;
  totalTimeMs: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
}

/**
 * First token event data
 */
export interface FirstTokenData extends AnalyticsEventData {
  generationId: string;
  timeToFirstTokenMs: number;
}

/**
 * Streaming update event data
 */
export interface StreamingUpdateData extends AnalyticsEventData {
  generationId: string;
  tokensGenerated: number;
}

/**
 * Model loading event data
 */
export interface ModelLoadingData extends AnalyticsEventData {
  modelId: string;
  loadTimeMs: number;
  success: boolean;
  errorCode?: string;
}

/**
 * Model unloading event data
 */
export interface ModelUnloadingData extends AnalyticsEventData {
  modelId: string;
  timestamp: number;
}

/**
 * Session started event data
 */
export interface SessionStartedData extends AnalyticsEventData {
  modelId: string;
  sessionType: string;
  timestamp: number;
}

/**
 * Session ended event data
 */
export interface SessionEndedData extends AnalyticsEventData {
  sessionId: string;
  duration: number;
  timestamp: number;
}

/**
 * LLM/Generation metrics
 */
export interface GenerationMetrics extends AnalyticsMetrics {
  totalGenerations: number;
  averageTimeToFirstToken: number;
  averageTokensPerSecond: number;
  totalInputTokens: number;
  totalOutputTokens: number;
}

// MARK: - Common Event Data

/**
 * Generic error event data
 */
export interface ErrorEventData extends AnalyticsEventData {
  error: string;
  context: string;
  errorCode?: string;
  timestamp: number;
}

// MARK: - Telemetry Event Data

/**
 * Telemetry data for backend submission
 */
export interface TelemetryData {
  eventType: string;
  properties: Record<string, string>;
  timestamp: Date;
}

/**
 * Device information for telemetry
 */
export interface DeviceInfo {
  device: string;
  osVersion: string;
  platform: string;
  sdkVersion: string;
}
